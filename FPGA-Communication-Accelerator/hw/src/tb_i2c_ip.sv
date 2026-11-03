`timescale 1ns / 1ps

// ============================================================================
// Self-checking I2C testbench (AXI4-Lite → i2c_ip → open-drain bus)
//  - 독립 I2C Slave 모델: START/STOP을 edge로 감지 (SCL High에서 SDA ↓/↑),
//    bit는 SCL rising마다 하나, ACK은 9번째 clock 동안 SDA를 당김
//    (원래 TB는 START를 level로 잡고 SCL falling을 세서 ACK이 1 bit 일찍 나갔음 → 전부 NACK)
//  - 주소가 맞을 때만 ACK → 잘못된 주소는 NACK 경로 확인
//  - Write: Slave가 받은 주소/데이터 비교 / Read: Master RDATA == Slave가 보낸 값, Master NACK 확인
//  - Start(W1S) 한 번에 트랜잭션 하나 (START/STOP 개수로 확인), Done sticky + W1C
// ============================================================================
module tb_i2c_ip();

    // 1. 신호 선언
    logic clk = 1'b0;
    logic rst_n;

    // AXI4-Lite Signals
    logic [4:0]  s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [4:0]  s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // I2C Physical Ports
    wire i2c_scl;
    wire i2c_sda;

    // 2. DUT 연결
    i2c_ip u_dut (
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
        .i2c_scl       (i2c_scl),
        .i2c_sda       (i2c_sda)
    );

    // 3. 클럭 생성 (100MHz)
    always #5 clk = ~clk;

    int errors  = 0;
    int checked = 0;

    // ------------------------------------------------------------------------
    // 4. AXI4-Lite master tasks (negedge에서 구동, posedge에서 handshake 확인)
    // ------------------------------------------------------------------------
    task automatic axi_write(input logic [4:0] addr, input logic [31:0] data);
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

    task automatic axi_read(input logic [4:0] addr, output logic [31:0] data);
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
    // 5. I2C bus + 독립 Slave 모델
    // ------------------------------------------------------------------------
    pullup(i2c_scl);
    pullup(i2c_sda);

    localparam logic [6:0] SLV_ADDR = 7'h50;
    logic       slv_pull = 1'b0;          // 1이면 SDA를 0으로 당김 (open-drain)
    assign i2c_sda = slv_pull ? 1'b0 : 1'bz;

    logic [7:0] slv_read_byte = 8'h00;    // Master가 읽어갈 값
    logic [7:0] slv_addr_byte;            // 마지막으로 받은 address byte
    logic [7:0] slv_wdata;                // 마지막으로 받은 data byte
    logic       master_ack_bit;           // Read 후 Master가 보낸 9번째 bit (1 = NACK)
    int starts = 0, stops = 0, slv_writes = 0, slv_reads = 0;

    // START / STOP: SCL이 High인 동안의 SDA edge
    always @(negedge i2c_sda) if (rst_n === 1'b1 && i2c_scl === 1'b1) starts++;
    always @(posedge i2c_sda) if (rst_n === 1'b1 && i2c_scl === 1'b1) stops++;

    task automatic slv_get_byte(output logic [7:0] b);
        for (int i = 7; i >= 0; i--) begin
            @(posedge i2c_scl);
            b[i] = i2c_sda;                   // SCL rising 하나 = bit 하나
        end
    endtask

    task automatic slv_ack();
        @(negedge i2c_scl);  slv_pull = 1'b1; // 8번째 bit가 끝난 SCL Low부터
        @(negedge i2c_scl);  slv_pull = 1'b0; // 9번째 clock 내내 유지
    endtask

    initial begin : i2c_slave
        logic [7:0] a, d;
        forever begin
            do @(negedge i2c_sda); while (i2c_scl !== 1'b1 || rst_n !== 1'b1);   // START
            slv_get_byte(a);
            slv_addr_byte = a;
            if (a[7:1] != SLV_ADDR) continue;             // 내 주소가 아니면 ACK 안 함 → NACK
            slv_ack();
            if (a[0] == 1'b0) begin                       // Master Write
                slv_get_byte(d);
                slv_wdata = d;
                slv_writes++;
                slv_ack();
            end else begin                                // Master Read: Slave가 8 bit 구동
                for (int i = 7; i >= 0; i--) begin
                    slv_pull = ~slv_read_byte[i];          // 1이면 놓고 0이면 당김 (SCL Low에서 변경)
                    @(negedge i2c_scl);
                end
                slv_pull = 1'b0;                          // 놓고 Master의 ACK/NACK을 본다
                @(posedge i2c_scl);
                master_ack_bit = i2c_sda;
                slv_reads++;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 6. 트랜잭션 하나 실행 + 공통 검사
    // ------------------------------------------------------------------------
    // ctrl_rw: 0 = write, 1 = read. 반환: STATUS 값
    task automatic run_txn(input logic [6:0] addr, input logic ctrl_rw, input logic [7:0] wdata,
                           output logic [31:0] st);
        int polls;
        int starts_before = starts;
        int stops_before  = stops;

        axi_write(5'h08, {25'h0, addr});
        axi_write(5'h0C, {24'h0, wdata});
        axi_write(5'h00, {30'h0, ctrl_rw, 1'b1});     // Bit1 R/W, Bit0 Start (W1S)

        axi_read(5'h04, st);
        if (!st[0] && !st[1]) begin
            $error("[REG ] BUSY not set right after start (status=0x%0h)", st);
            errors++;
        end
        polls = 0;
        while (!st[1] && polls < 5000) begin
            axi_read(5'h04, st);
            polls++;
        end
        if (!st[1]) begin
            $error("[REG ] timeout waiting for DONE (status=0x%0h)", st);
            errors++;
        end

        // start 한 번에 트랜잭션 하나: 50 us(SCL 5주기) 더 기다려도 START/STOP이 하나씩이어야 함
        #50_000;
        if (starts - starts_before != 1 || stops - stops_before != 1) begin
            $error("[BUS ] %0d START / %0d STOP for one start command, expected 1 / 1",
                   starts - starts_before, stops - stops_before);
            errors++;
        end
    endtask

    task automatic clear_done();
        logic [31:0] st;
        axi_write(5'h04, 32'h0000_0002);              // DONE W1C
        axi_read(5'h04, st);
        if (st[1]) begin
            $error("[REG ] DONE still set after W1C");
            errors++;
        end
    endtask

    task automatic check_write(input logic [7:0] wdata);
        logic [31:0] st;
        int writes_before = slv_writes;
        run_txn(SLV_ADDR, 1'b0, wdata, st);
        if (st[2])                         begin $error("[WR  ] ACK error reported for a present slave"); errors++; end
        if (slv_writes != writes_before + 1) begin $error("[WR  ] slave saw no data byte"); errors++; end
        if (slv_addr_byte !== {SLV_ADDR, 1'b0}) begin
            $error("[WR  ] address byte 0x%02h, expected 0x%02h", slv_addr_byte, {SLV_ADDR, 1'b0}); errors++;
        end
        if (slv_wdata !== wdata) begin
            $error("[WR  ] slave received 0x%02h, expected 0x%02h", slv_wdata, wdata); errors++;
        end
        $display("[TB  ] write 0x%02h to 0x%02h -> slave got 0x%02h", wdata, SLV_ADDR, slv_wdata);
        clear_done();
        checked++;
    endtask

    task automatic check_read(input logic [7:0] slave_value);
        logic [31:0] st, rd;
        int reads_before  = slv_reads;
        int writes_before = slv_writes;
        slv_read_byte = slave_value;
        run_txn(SLV_ADDR, 1'b1, 8'hEE, st);           // WDATA는 무시되어야 함
        if (st[2])                           begin $error("[RD  ] ACK error reported for a present slave"); errors++; end
        if (slv_reads != reads_before + 1)   begin $error("[RD  ] slave never served a read"); errors++; end
        if (slv_writes != writes_before)     begin $error("[RD  ] a read request executed as a write"); errors++; end
        if (slv_addr_byte !== {SLV_ADDR, 1'b1}) begin
            $error("[RD  ] address byte 0x%02h, expected 0x%02h", slv_addr_byte, {SLV_ADDR, 1'b1}); errors++;
        end
        if (master_ack_bit !== 1'b1) begin
            $error("[RD  ] master ACKed the last byte; a 1-byte read must end with NACK"); errors++;
        end
        axi_read(5'h10, rd);
        if (rd[7:0] !== slave_value) begin
            $error("[RD  ] RDATA = 0x%02h, slave sent 0x%02h", rd[7:0], slave_value); errors++;
        end
        $display("[TB  ] read from 0x%02h -> RDATA 0x%02h (slave sent 0x%02h)", SLV_ADDR, rd[7:0], slave_value);
        clear_done();
        checked++;
    endtask

    task automatic check_nack();
        logic [31:0] st;
        int writes_before = slv_writes;
        run_txn(SLV_ADDR + 7'd1, 1'b0, 8'h99, st);    // 없는 주소
        if (!st[2]) begin $error("[NACK] no ACK error for an absent address"); errors++; end
        if (slv_writes != writes_before) begin $error("[NACK] data phase ran after a NACK"); errors++; end
        $display("[TB  ] write to absent 0x%02h -> ack_error=%0b", SLV_ADDR + 7'd1, st[2]);
        clear_done();
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
    initial begin
        rst_n = 1'b0;
        s_axi_awvalid = 1'b0; s_axi_wvalid = 1'b0; s_axi_bready = 1'b0;
        s_axi_arvalid = 1'b0; s_axi_rready = 1'b0;
        s_axi_awaddr  = '0;   s_axi_wdata  = '0;   s_axi_araddr = '0;

        #100; rst_n = 1'b1; #100;
        $display("=== I2C Simulation Start ===");

        check_write(8'hAB);
        check_read (8'h3C);
        check_read (8'hC5);
        check_nack ();
        check_write(8'h5A);                           // NACK 후에도 정상 동작

        $display("============================================");
        if (errors == 0 && checked == 5)
            $display(" *** TEST PASSED *** %0d transactions checked (write, read, NACK)", checked);
        else
            $display(" *** TEST FAILED *** errors=%0d, transactions checked %0d/5", errors, checked);
        $display("============================================");
        $finish;
    end

endmodule
