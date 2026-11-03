`timescale 1ns / 1ps

// ============================================================================
// Self-checking SPI testbench (AXI4-Lite → spi_ip → pins)
//  - MISO는 MOSI loopback이 아니라 독립된 SPI Slave 모델 (Mode 0, 자기 shift register)
//    loopback은 Master가 틀린 바이트를 보내도 그 바이트를 그대로 받아서 항상 일치함
//  - 양방향 비교: Slave가 받은 MOSI 바이트 == TX 레지스터, Master RX 레지스터 == Slave가 보낸 바이트
//  - 패턴은 Master TX bit0 != Slave TX bit7 (원래 LSB 덮어쓰기 버그는 이 조건에서만 보임)
//  - Start(W1S) 한 번에 프레임 정확히 1개, Done sticky + W1C, CS High 동안 SCLK 정지
// ============================================================================
module tb_spi_ip();

    // 1. 신호 선언
    logic clk = 1'b0;
    logic rst_n;

    // AXI4-Lite Signals
    logic [3:0]  s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [3:0]  s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // SPI Signals
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;

    // 2. DUT 연결
    spi_ip u_dut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (3'b000),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (4'b1111),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (3'b000),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .spi_sclk      (spi_sclk),
        .spi_mosi      (spi_mosi),
        .spi_miso      (spi_miso),
        .spi_cs_n      (spi_cs_n)
    );

    // 3. 클럭 생성 (100MHz)
    always #5 clk = ~clk;

    int errors  = 0;
    int checked = 0;
    int frames  = 0;

    // ------------------------------------------------------------------------
    // 4. AXI4-Lite master tasks (negedge에서 구동, posedge에서 handshake 확인)
    // ------------------------------------------------------------------------
    task automatic axi_write(input logic [3:0] addr, input logic [31:0] data);
        @(negedge clk);
        s_axi_awaddr  = addr;  s_axi_awvalid = 1'b1;
        s_axi_wdata   = data;  s_axi_wvalid  = 1'b1;
        s_axi_bready  = 1'b1;
        do @(posedge clk); while (!(s_axi_awready && s_axi_wready));
        @(negedge clk);
        s_axi_awvalid = 1'b0;  s_axi_wvalid  = 1'b0;
        while (!s_axi_bvalid) @(posedge clk);
        @(negedge clk);
        s_axi_bready  = 1'b0;
    endtask

    task automatic axi_read(input logic [3:0] addr, output logic [31:0] data);
        @(negedge clk);
        s_axi_araddr  = addr;  s_axi_arvalid = 1'b1;
        s_axi_rready  = 1'b1;
        do @(posedge clk); while (!s_axi_arready);
        @(negedge clk);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(posedge clk);
        data = s_axi_rdata;
        @(negedge clk);
        s_axi_rready  = 1'b0;
    endtask

    // ------------------------------------------------------------------------
    // 5. 독립 SPI Slave 모델 (Mode 0: rising에서 MOSI sample, falling에서 MISO 변경)
    // ------------------------------------------------------------------------
    logic [7:0] slv_tx;                  // 다음 프레임에 MISO로 보낼 바이트
    logic [7:0] slv_shift;
    logic [7:0] slv_rx_q[$];             // Slave가 받은 바이트
    int         slv_bits;
    logic       miso_drv = 1'b0;
    assign spi_miso = miso_drv;

    always @(negedge spi_cs_n) begin
        slv_shift = slv_tx;
        slv_bits  = 0;
        miso_drv  = slv_tx[7];           // CPHA=0: 첫 rising 전에 MSB가 나가 있어야 함
    end

    always @(posedge spi_sclk) if (spi_cs_n === 1'b0) begin
        slv_shift = {slv_shift[6:0], spi_mosi};
        slv_bits++;
    end

    always @(negedge spi_sclk) if (spi_cs_n === 1'b0) miso_drv = slv_shift[7];

    always @(posedge spi_cs_n) if (rst_n === 1'b1) begin
        if (slv_bits != 8) begin
            $error("[SLV ] frame had %0d SCLK rising edges, expected 8", slv_bits);
            errors++;
        end
        slv_rx_q.push_back(slv_shift);
        frames++;
    end

    // CS가 High인 동안 SCLK가 움직이면 안 됨
    always @(spi_sclk) if (rst_n === 1'b1 && spi_cs_n === 1'b1) begin
        $error("[SPI ] SCLK toggled while CS is high");
        errors++;
    end

    // ------------------------------------------------------------------------
    // 6. 전송 하나 + 검사
    // ------------------------------------------------------------------------
    task automatic xfer_check(input logic [7:0] m_tx, input logic [7:0] s_tx);
        logic [31:0] st, rx, ctrl;
        logic [7:0]  got_mosi = 8'hxx;
        int polls;
        int frames_before;

        slv_tx        = s_tx;
        frames_before = frames;

        axi_write(4'h8, {24'h0, m_tx});          // TX Data
        axi_write(4'h0, 32'h0000_0001);          // Start (W1S)

        axi_read(4'h4, st);
        if (!st[0] && !st[1]) begin
            $error("[REG ] BUSY not set right after start (status=0x%0h)", st);
            errors++;
        end
        polls = 0;
        while (!st[1] && polls < 2000) begin
            axi_read(4'h4, st);
            polls++;
        end
        if (!st[1]) begin
            $error("[REG ] timeout waiting for DONE (status=0x%0h)", st);
            errors++;
            return;
        end

        axi_read(4'hC, rx);
        if (rx[7:0] !== s_tx) begin
            $error("[MISO] master RX = 0x%02h, slave sent 0x%02h", rx[7:0], s_tx);
            errors++;
        end
        if (slv_rx_q.size() == 0) begin
            $error("[MOSI] slave received nothing");
            errors++;
        end else begin
            got_mosi = slv_rx_q[0];
            if (slv_rx_q[0] !== m_tx) begin
                $error("[MOSI] slave received 0x%02h, master TX reg = 0x%02h", slv_rx_q[0], m_tx);
                errors++;
            end
            void'(slv_rx_q.pop_front());
        end

        axi_read(4'h0, ctrl);
        if (ctrl[0]) begin
            $error("[REG ] CTRL.start reads back 1 (should be self-clearing)");
            errors++;
        end

        axi_write(4'h4, 32'h0000_0002);          // DONE W1C
        axi_read(4'h4, st);
        if (st[1]) begin
            $error("[REG ] DONE still set after W1C");
            errors++;
        end

        // start 한 번에 프레임 하나: 2.5 프레임 시간 동안 재전송이 없어야 함
        repeat (2000) @(negedge clk);
        if (frames != frames_before + 1) begin
            $error("[SPI ] %0d frame(s) for one start, expected 1", frames - frames_before);
            errors++;
        end

        $display("[TB  ] master 0x%02h -> slave 0x%02h | slave 0x%02h -> master 0x%02h",
                 m_tx, got_mosi, s_tx, rx[7:0]);
        checked++;
    endtask

    // Watchdog
    initial begin
        #5_000_000;
        $fatal(1, "[TB  ] watchdog expired");
    end

    // ------------------------------------------------------------------------
    // 7. 시나리오
    // ------------------------------------------------------------------------
    // {master TX, slave TX}: 모두 master_tx[0] != slave_tx[7]
    logic [15:0] pairs[] = '{
        {8'h55, 8'h3C}, {8'hAA, 8'hA5}, {8'h01, 8'h00}, {8'h80, 8'hFF},
        {8'hFE, 8'h81}, {8'h7F, 8'h7E}, {8'h00, 8'hC3}, {8'hFF, 8'h18}
    };

    initial begin
        logic [15:0] p;

        rst_n = 1'b0;
        s_axi_awvalid = 1'b0; s_axi_wvalid = 1'b0; s_axi_bready = 1'b0;
        s_axi_arvalid = 1'b0; s_axi_rready = 1'b0;
        s_axi_awaddr  = '0;   s_axi_wdata  = '0;   s_axi_araddr = '0;
        slv_tx = 8'h00;

        #100; rst_n = 1'b1; #100;
        $display("=== SPI Simulation Start ===");

        foreach (pairs[i]) begin
            p = pairs[i];
            xfer_check(p[15:8], p[7:0]);
        end

        // 추가 패턴 8개 (시뮬레이터와 무관하게 항상 같은 값이 나오도록 산술로 생성)
        for (int i = 0; i < 8; i++) begin
            p[15:8] = i * 73 + 19;
            p[7:0]  = i * 151 + 7;
            xfer_check(p[15:8], p[7:0]);
        end

        $display("============================================");
        if (errors == 0 && checked == pairs.size() + 8)
            $display(" *** TEST PASSED *** %0d transfers checked in both directions", checked);
        else
            $display(" *** TEST FAILED *** errors=%0d, transfers checked %0d/%0d", errors, checked, pairs.size() + 8);
        $display("============================================");
        $finish;
    end

endmodule
