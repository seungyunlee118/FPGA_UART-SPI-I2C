`timescale 1ns / 1ps

// ============================================================================
// Self-checking UART loopback testbench
//  - [LINE] TX 핀을 DUT의 baud_gen과 독립된 bit 시간으로 디코딩해서 보낸 바이트와 비교
//           (loopback만으로는 TX/RX가 같은 baud_gen을 써서 baud 오류를 못 잡음)
//  - [RX ]  RX FIFO에서 꺼낸 바이트를 보낸 바이트와 비교
//           (FIFO는 show-ahead: head를 먼저 읽고 비교한 뒤에 pop)
//  - [FULL] 16-deep TX FIFO에 20바이트 burst → 정확히 16개만 받아야 함
//  - 마지막 줄은 비교 결과로만 결정 (PASS = 에러 0 AND 보낸 개수만큼 전부 확인)
// ============================================================================
module tb_uart_core();

    localparam int CLK_PERIOD = 10;     // 100 MHz
    localparam int DIVISOR    = 10;     // 시뮬레이션용 고속 설정
    // tick 주기 = divisor + 1 clock, 1 bit = 16 tick (DUT 코드가 아니라 스펙에서 계산)
    localparam realtime BIT_NS     = 16.0 * (DIVISOR + 1) * CLK_PERIOD;
    localparam int      BIT_CYCLES = 16 * (DIVISOR + 1);

    logic        clk = 1'b0;
    logic        reset_n;
    logic [15:0] divisor;
    logic        tx_pin;               // Loopback으로 연결될 핀

    logic        tx_wr_en;
    logic [7:0]  tx_wr_data;
    logic        tx_full;
    logic        rx_rd_en;
    logic [7:0]  rx_rd_data;
    logic        rx_empty;
    logic        rx_err;

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

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------------------
    logic [7:0] exp_line[$];            // TX 핀에 나와야 할 바이트
    logic [7:0] exp_rx[$];              // RX FIFO에서 나와야 할 바이트
    int errors       = 0;
    int accepted     = 0;               // TX FIFO가 실제로 받은 바이트 수
    int line_checked = 0;
    int rx_checked   = 0;
    bit saw_full     = 0;

    // bit0 != bit7 인 값과 경계값을 섞음
    logic [7:0] pattern[] = '{8'hAA, 8'hBB, 8'hCC, 8'h55, 8'h00, 8'hFF, 8'h01, 8'h80, 8'hA5, 8'h3C};

    // TX FIFO에 쓰기 (모든 구동은 negedge → posedge의 DUT와 race 없음)
    // full이면 FIFO가 버리므로 expected에 넣지 않음
    task automatic write_tx(input logic [7:0] b);
        @(negedge clk);
        tx_wr_en   = 1'b1;
        tx_wr_data = b;
        if (!tx_full) begin
            exp_line.push_back(b);
            exp_rx.push_back(b);
            accepted++;
        end else begin
            saw_full = 1'b1;
        end
    endtask

    task automatic write_done();
        @(negedge clk);
        tx_wr_en = 1'b0;
    endtask

    // 남은 바이트가 다 확인될 때까지 대기 (프레임 수 기준 timeout)
    task automatic wait_drain(input int max_frames);
        int n     = 0;
        int limit = (max_frames + 2) * 10 * BIT_CYCLES;
        while ((exp_line.size() != 0 || exp_rx.size() != 0) && n < limit) begin
            @(negedge clk);
            n++;
        end
        if (n >= limit) begin
            $error("[TB  ] timeout: %0d byte(s) never seen on the line, %0d never read from RX FIFO",
                   exp_line.size(), exp_rx.size());
            errors++;
        end
        repeat (BIT_CYCLES) @(negedge clk);   // 마지막 프레임의 stop bit가 끝날 때까지
    endtask

    // ------------------------------------------------------------------------
    // [LINE] TX 핀 디코더: falling edge 기준 0.5 bit에 start, 이후 1 bit 간격으로 sample
    // ------------------------------------------------------------------------
    initial begin : line_monitor
        logic [7:0] b;
        forever begin
            @(negedge tx_pin);
            if (reset_n !== 1'b1) continue;
            #(BIT_NS * 0.5);
            if (tx_pin !== 1'b0) begin
                $error("[LINE] start bit not low at mid-bit (glitch?)");
                errors++;
                continue;
            end
            for (int i = 0; i < 8; i++) begin
                #(BIT_NS);
                b[i] = tx_pin;                   // LSB first
            end
            #(BIT_NS);
            if (tx_pin !== 1'b1) begin
                $error("[LINE] stop bit is low (framing error on TX)");
                errors++;
            end
            if (exp_line.size() == 0) begin
                $error("[LINE] unexpected byte 0x%02h on the line", b);
                errors++;
            end else begin
                if (b !== exp_line[0]) begin
                    $error("[LINE] got 0x%02h, expected 0x%02h", b, exp_line[0]);
                    errors++;
                end
                void'(exp_line.pop_front());
                line_checked++;
            end
        end
    end

    // ------------------------------------------------------------------------
    // [RX] RX FIFO 체커: show-ahead이므로 비교 → pop 순서
    // ------------------------------------------------------------------------
    initial begin : rx_checker
        rx_rd_en = 1'b0;
        forever begin
            @(negedge clk);
            if (reset_n === 1'b1 && !rx_empty) begin
                if (exp_rx.size() == 0) begin
                    $error("[RX  ] unexpected byte 0x%02h in RX FIFO", rx_rd_data);
                    errors++;
                end else begin
                    if (rx_rd_data !== exp_rx[0]) begin
                        $error("[RX  ] got 0x%02h, expected 0x%02h", rx_rd_data, exp_rx[0]);
                        errors++;
                    end
                    void'(exp_rx.pop_front());
                    rx_checked++;
                end
                if (rx_err) begin
                    $error("[RX  ] rx_err set (stop bit sampled low)");
                    errors++;
                end
                rx_rd_en = 1'b1;                 // 읽은 다음에 pop
                @(negedge clk);
                rx_rd_en = 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------------------
    initial begin
        #(BIT_NS * 10 * 100);
        $fatal(1, "[TB  ] watchdog expired");
    end

    // ------------------------------------------------------------------------
    // 시나리오
    // ------------------------------------------------------------------------
    initial begin
        int burst_before;

        reset_n    = 1'b0;
        divisor    = DIVISOR;
        tx_wr_en   = 1'b0;
        tx_wr_data = '0;

        #100;
        reset_n = 1'b1;
        #20;

        $display("---------------------------------------------------");
        $display(" Test 1: directed bytes (bit0 != bit7 포함)");
        $display("---------------------------------------------------");
        foreach (pattern[i]) begin
            write_tx(pattern[i]);
            write_done();                       // 1 cycle 쉬고 다음 바이트
        end
        wait_drain(pattern.size());

        $display("---------------------------------------------------");
        $display(" Test 2: 20-byte burst into a 16-deep TX FIFO");
        $display("---------------------------------------------------");
        burst_before = accepted;
        for (int i = 0; i < 20; i++) write_tx(8'h10 + i);   // 연속 20 cycle
        write_done();
        if (accepted - burst_before != 16) begin
            $error("[FULL] TX FIFO accepted %0d of 20 bytes, expected 16", accepted - burst_before);
            errors++;
        end
        if (!saw_full) begin
            $error("[FULL] tx_full never asserted during the burst");
            errors++;
        end
        wait_drain(20);

        $display("---------------------------------------------------");
        if (errors == 0 && line_checked == accepted && rx_checked == accepted)
            $display(" *** TEST PASSED *** %0d bytes checked on the line and through RX FIFO", accepted);
        else
            $display(" *** TEST FAILED *** errors=%0d, line checked %0d/%0d, RX checked %0d/%0d",
                     errors, line_checked, accepted, rx_checked, accepted);
        $display("---------------------------------------------------");
        $finish;
    end

endmodule
