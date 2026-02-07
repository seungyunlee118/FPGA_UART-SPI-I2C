`timescale 1ns / 1ps

module tb_spi_ip();

    // 1. 신호 선언
    logic clk;
    logic rst_n;

    // AXI4-Lite Signals
    logic [3:0]  s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [3:0]  s_axi_araddr;
    logic [2:0]  s_axi_arprot;
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

    // 2. DUT (Device Under Test) 연결
    spi_ip u_dut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),

        // Write Channel
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

        // Read Channel
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (3'b000),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        // SPI Ports
        .spi_sclk      (spi_sclk),
        .spi_mosi      (spi_mosi),
        .spi_miso      (spi_miso),
        .spi_cs_n      (spi_cs_n)
    );

    // [Loopback] 보낸 걸 그대로 받도록 연결 (MISO = MOSI)
    assign spi_miso = spi_mosi;

    // 3. 클럭 생성 (100MHz)
    always #5 clk = ~clk;

    // 4. AXI Write Task (CPU가 쓰는 척하는 함수)
    task axi_write(input [3:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b0;

            // Ready 신호 기다리기 (Handshake)
            wait(s_axi_awready && s_axi_wready);
            
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // 응답 대기
            s_axi_bready <= 1'b1;
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    // 5. 시나리오 실행
    initial begin
        // 초기화
        clk = 0;
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid  = 0;
        s_axi_arvalid = 0;
        s_axi_bready  = 0;
        s_axi_rready  = 0;

        // 리셋 해제
        #100;
        rst_n = 1;
        #100;

        $display("=== Simulation Start ===");

        // [Step 1] TX 데이터 레지스터(0x08)에 0x55 쓰기 (01010101)
        $display("[CPU] Writing Data 0x55 to TX Register...");
        axi_write(4'h8, 32'h0000_0055);

        // [Step 2] Control 레지스터(0x00)에 1을 써서 START 신호 주기
        $display("[CPU] Writing Start Command...");
        axi_write(4'h0, 32'h0000_0001);

        // [Step 3] SPI 전송이 끝날 때까지 대기
        // 1MHz SPI는 1비트에 1us, 8비트면 최소 8us 이상 걸림
        // 넉넉하게 20us 대기
        #20000; 
        
        // [Step 4] Control 레지스터(0x00) 끄기 (Optional)
        axi_write(4'h0, 32'h0000_0000);

        $display("=== Simulation Done ===");
        $finish;
    end

endmodule