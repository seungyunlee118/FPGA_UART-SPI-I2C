`timescale 1ns / 1ps

module tb_i2c_ip();

    // 1. 신호 선언
    logic clk;
    logic rst_n;

    // AXI4-Lite Signals
    logic [4:0]  s_axi_awaddr;
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
    logic [4:0]  s_axi_araddr;
    logic [2:0]  s_axi_arprot;
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

    // ====================================================
    // I2C 환경 시뮬레이션
    // ====================================================
    pullup(i2c_scl);
    pullup(i2c_sda);

    reg slave_ack_en = 0;
    assign i2c_sda = slave_ack_en ? 1'b0 : 1'bz;

    initial begin
        forever begin
            wait(i2c_scl == 1 && i2c_sda == 0); // Start 감지
            repeat(8) @(negedge i2c_scl);       // 8비트 대기
            
            // ACK 응답 (9번째 펄스)
            slave_ack_en = 1; 
            @(negedge i2c_scl); 
            slave_ack_en = 0;   

            repeat(8) @(negedge i2c_scl);       // 데이터 대기
            
            // ACK 응답
            slave_ack_en = 1;
            @(negedge i2c_scl);
            slave_ack_en = 0;
        end
    end

    // ====================================================
    // [수정됨] 3. 클럭 생성 (가장 안전한 방법)
    // ====================================================
    initial begin
        clk = 0;             // 0으로 확실히 초기화
        forever #5 clk = ~clk; // 그 다음 무한루프로 토글 (100MHz)
    end

    // 4. AXI Write Task
    task axi_write(input [4:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b0;
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            s_axi_bready  <= 1'b1;
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    // 5. 시나리오 실행
    initial begin
        // clk 초기화는 위에서 했으므로 생략
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_arvalid = 0;
        s_axi_bready = 0; s_axi_rready = 0;

        #100; rst_n = 1; #100;

        $display("=== I2C Simulation Start ===");

        // Slave Address (0x50) 설정
        axi_write(5'h08, 32'h0000_0050);

        // Data (0xAB) 설정
        axi_write(5'h0C, 32'h0000_00AB);

        // Start 명령
        axi_write(5'h00, 32'h0000_0001);

        // I2C 전송 대기 (충분한 시간)
        #300000; 

        $display("=== I2C Simulation Done ===");
        $finish;
    end

endmodule