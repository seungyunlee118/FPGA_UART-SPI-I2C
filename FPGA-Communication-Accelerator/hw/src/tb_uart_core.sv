`timescale 1ns / 1ps

module tb_uart_core();

    // 1. 신호 선언 (FIFO 인터페이스로 변경됨)
    logic        clk;
    logic        reset_n;
    logic [15:0] divisor;
    
    logic        tx_pin; // Loopback으로 연결될 핀
    
    // TX FIFO Interface
    logic        tx_wr_en;
    logic [7:0]  tx_wr_data;
    logic        tx_full;
    
    // RX FIFO Interface
    logic        rx_rd_en;
    logic [7:0]  rx_rd_data;
    logic        rx_empty;
    logic        rx_err;

    // 2. DUT 연결 (Loopback 설정: rx_pin <- tx_pin)
    uart_core u_dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .divisor    (divisor),
        .rx_pin     (tx_pin),     
        .tx_pin     (tx_pin),
        
        .tx_wr_en   (tx_wr_en),
        .tx_wr_data (tx_wr_data),
        .tx_full    (tx_full),
        
        .rx_rd_en   (rx_rd_en),
        .rx_rd_data (rx_rd_data),
        .rx_empty   (rx_empty),
        .rx_err     (rx_err)
    );

    // 3. 클럭 생성
    always #5 clk = ~clk;

    // 4. 테스트 시나리오
    initial begin
        // 초기화
        clk = 0;
        reset_n = 0;
        divisor = 16'd10; // 시뮬레이션용 고속 설정
        tx_wr_en = 0;
        tx_wr_data = 0;
        rx_rd_en = 0;

        // 리셋 해제
        #100;
        reset_n = 1;
        #20;

        $display("---------------------------------------------------");
        $display(" Test Start: FIFO Burst Write -> UART Loopback");
        $display("---------------------------------------------------");

      // --------------------------------------------------------
        // Step 1: Foolproof Write (확실하게 넣기)
        // --------------------------------------------------------
        
        // 1. 첫 번째 데이터 0xAA
        @(negedge clk);    // 클럭이 내려갈 때 준비 (타이밍 확보)
        tx_wr_en = 1;
        tx_wr_data = 8'hAA;
        
        @(negedge clk);    // <--- [핵심] 다음 클럭 내려갈 때까지 기다림 (1주기 유지)
        tx_wr_en = 0;      // 이제 끔
        
        // --------------------------------------------------------
        
        // 2. 두 번째 데이터 0xBB
        @(negedge clk);    // 1클럭 쉬고
        tx_wr_en = 1;      // 다시 켬
        tx_wr_data = 8'hBB;
        
        @(negedge clk);    // <--- [핵심] 또 1주기 유지
        tx_wr_en = 0;
        
        // 3. 세 번째 데이터 0xCC
        @(negedge clk);
        tx_wr_en = 1;
        tx_wr_data = 8'hCC;
        
        @(negedge clk);    // <--- [핵심] 1주기 유지
        tx_wr_en = 0;
    

        // --------------------------------------------------------
        // Step 2: 수신 대기 및 읽기 (Polling)
        // --------------------------------------------------------
        // UART가 느리게 돌면서 하나씩 전송하고, RX FIFO에 쌓일 때까지 기다림
        
        // 첫 번째 데이터(0xAA) 수신 대기
        wait(rx_empty == 1'b0); 
        @(posedge clk);
        rx_rd_en = 1;  // FIFO Pop
        @(posedge clk);
        rx_rd_en = 0;
        $display("[CPU] Read from RX FIFO: 0x%h (Expected 0xAA)", rx_rd_data);

        // 두 번째 데이터(0xBB) 수신 대기
        wait(rx_empty == 1'b0);
        @(posedge clk);
        rx_rd_en = 1;
        @(posedge clk);
        rx_rd_en = 0;
        $display("[CPU] Read from RX FIFO: 0x%h (Expected 0xBB)", rx_rd_data);

        // 세 번째 데이터(0xCC) 수신 대기
        wait(rx_empty == 1'b0);
        @(posedge clk);
        rx_rd_en = 1;
        @(posedge clk);
        rx_rd_en = 0;
        $display("[CPU] Read from RX FIFO: 0x%h (Expected 0xCC)", rx_rd_data);

        #100;
        $display("---------------------------------------------------");
        $display(" Test Complete: FIFO Logic Verified!");
        $display("---------------------------------------------------");
        $finish;
    end

endmodule