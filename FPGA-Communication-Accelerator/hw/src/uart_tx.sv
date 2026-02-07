`timescale 1ns / 1ps

module uart_tx (
    input  logic       clk,
    input  logic       reset_n,
    input  logic       tick,      // baud_gen에서 오는 16x tick
    input  logic       tx_start,  // 전송 시작 신호
    input  logic [7:0] tx_data,   // 전송할 8비트 데이터
    
    output logic       tx_pin,    // 외부로 나가는 시리얼 핀
    output logic       tx_done,   // 전송 완료 신호 (1클럭 펄스)
    output logic       tx_busy    // 전송 중 상태 표시
);

    // FSM 상태 정의
    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state, state_next;

    // 내부 레지스터
    logic [3:0] tick_cnt, tick_cnt_next; // 0~15 세는 카운터 (한 비트 길이)
    logic [2:0] bit_cnt, bit_cnt_next;   // 0~7 세는 카운터 (데이터 비트 수)
    logic [7:0] shift_reg, shift_reg_next; // 데이터 저장 및 시프트용
    logic       tx_reg, tx_reg_next;     // TX 핀 출력용 레지스터

    // -----------------------------------------------------------
    // Sequential Logic: 클럭에 맞춰 상태 및 레지스터 업데이트
    // -----------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= IDLE;
            tick_cnt  <= 0;
            bit_cnt   <= 0;
            shift_reg <= 0;
            tx_reg    <= 1'b1; // Idle 상태에서는 High 유지
        end else begin
            state     <= state_next;
            tick_cnt  <= tick_cnt_next;
            bit_cnt   <= bit_cnt_next;
            shift_reg <= shift_reg_next;
            tx_reg    <= tx_reg_next;
        end
    end

    // -----------------------------------------------------------
    // Combinational Logic: Next State Logic
    // -----------------------------------------------------------
    always_comb begin
        // Default 값 유지 (Latch 방지)
        state_next     = state;
        tick_cnt_next  = tick_cnt;
        bit_cnt_next   = bit_cnt;
        shift_reg_next = shift_reg;
        tx_reg_next    = tx_reg;
        
        tx_done = 1'b0;
        tx_busy = 1'b1; // 기본적으로 바쁨 상태, IDLE에서만 0

        case (state)
            IDLE: begin
                tx_busy = 1'b0;
                tx_reg_next = 1'b1; // Idle Line is High
                
                if (tx_start) begin
                    state_next = START;
                    tick_cnt_next = 0;
                    shift_reg_next = tx_data; // 데이터 캡쳐
                end
            end

            START: begin
                tx_reg_next = 1'b0; // Start Bit = Low
                
                if (tick) begin // baud_gen에서 펄스가 튈 때만 카운트 증가
                    if (tick_cnt == 15) begin
                        state_next = DATA;
                        tick_cnt_next = 0;
                        bit_cnt_next = 0;
                    end else begin
                        tick_cnt_next = tick_cnt + 1;
                    end
                end
            end

            DATA: begin
                tx_reg_next = shift_reg[0]; // LSB부터 전송
                
                if (tick) begin
                    if (tick_cnt == 15) begin
                        tick_cnt_next = 0;
                        shift_reg_next = shift_reg >> 1; // 오른쪽으로 시프트
                        
                        if (bit_cnt == 7) begin // 8비트 전송 완료
                            state_next = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt + 1;
                        end
                    end else begin
                        tick_cnt_next = tick_cnt + 1;
                    end
                end
            end

            STOP: begin
                tx_reg_next = 1'b1; // Stop Bit = High
                
                if (tick) begin
                    if (tick_cnt == 15) begin // Stop bit 시간 충족
                        state_next = IDLE;
                        tx_done = 1'b1; // 완료 펄스 발생
                    end else begin
                        tick_cnt_next = tick_cnt + 1;
                    end
                end
            end
        endcase
    end

    // 출력 연결
    assign tx_pin = tx_reg;

endmodule