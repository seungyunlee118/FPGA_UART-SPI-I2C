`timescale 1ns / 1ps

module uart_rx (
    input  logic       clk,
    input  logic       reset_n,
    input  logic       tick,
    input  logic       rx_pin,
    
    output logic       rx_done,    // 이제 레지스터(Flip-flop) 출력이 됩니다.
    output logic [7:0] rx_data,
    output logic       rx_err
);

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state, state_next;

    logic [3:0] tick_cnt, tick_cnt_next;
    logic [2:0] bit_cnt, bit_cnt_next;
    logic [7:0] shift_reg, shift_reg_next;
    
    // Sync Logic
    logic rx_sync_0, rx_sync_1;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx_pin;
            rx_sync_1 <= rx_sync_0;
        end
    end

    // ----------------------------------------------------------------
    // [핵심 변경] State Machine과 Output Logic을 분리하지 않고
    // rx_done과 rx_data를 '동시에' 업데이트하도록 수정 (Glitch 방지)
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= IDLE;
            tick_cnt  <= 0;
            bit_cnt   <= 0;
            shift_reg <= 0;
            rx_data   <= 0;
            rx_done   <= 0;    // Reset
            rx_err    <= 0;
        end else begin
            // Default
            rx_done <= 0;      // 기본적으로 0 (1클럭 펄스 만들기 위함)
            
            // Next State Logic을 여기에 통합하여 타이밍을 맞춤
            case (state)
                IDLE: begin
                    if (rx_sync_1 == 1'b0) begin
                        state <= START;
                        tick_cnt <= 0;
                    end
                end

                START: begin
                    if (tick) begin
                        if (tick_cnt == 7) begin
                            if (rx_sync_1 == 1'b0) begin
                                tick_cnt <= 0;
                                bit_cnt  <= 0;
                                state    <= DATA;
                            end else begin
                                state <= IDLE;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                DATA: begin
                    if (tick) begin
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            shift_reg <= {rx_sync_1, shift_reg[7:1]};
                            if (bit_cnt == 7) begin
                                state <= STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                STOP: begin
                    if (tick) begin
                        if (tick_cnt == 15) begin
                            state <= IDLE;
                            rx_done <= 1'b1;       // Done 신호 발생!
                            rx_data <= shift_reg;  // 데이터 업데이트! (동시에 발생)
                            
                            if (rx_sync_1 == 1'b0) rx_err <= 1'b1;
                            else                   rx_err <= 1'b0;
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule