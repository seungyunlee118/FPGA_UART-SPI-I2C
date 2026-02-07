`timescale 1ns / 1ps

module spi_master (
    input  logic        clk,        // 시스템 클럭 (100MHz)
    input  logic        rst_n,      // 리셋 (Active Low)
    
    // [User Interface]
    input  logic        start,      // 전송 시작 신호 (Pulse)
    input  logic [7:0]  tx_data,    // 보낼 데이터
    output logic [7:0]  rx_data,    // 받은 데이터
    output logic        busy,       // 동작 중 상태
    output logic        done,       // 완료 신호 (Pulse)

    // [Physical Interface]
    output logic        sclk,       // SPI Serial Clock
    output logic        mosi,       // Master Out Slave In
    input  logic        miso,       // Master In Slave Out
    output logic        cs_n        // Chip Select (Active Low)
);

    // ====================================================
    // 1. 파라미터 및 타입 정의 (SystemVerilog의 장점!)
    // ====================================================
    localparam int CLK_DIV = 100;       // 100MHz / 100 = 1MHz
    localparam int CNT_MID = CLK_DIV/2; // 50 (Rising Edge 지점)

    // [Enum] 상태를 명시적인 이름으로 정의 (디버깅할 때 숫자가 아닌 이름으로 보임)
    typedef enum logic [1:0] {
        IDLE,
        START,
        TRANS,
        DONE_STATE
    } state_t;

    state_t state;  // 현재 상태 변수

    // 내부 신호 정의 (reg/wire 대신 logic 하나로 통일)
    logic [6:0] clk_cnt;    // 분주 카운터 (0~99)
    logic [2:0] bit_cnt;    // 비트 카운터 (7~0)
    logic [7:0] shift_reg;  // 시프트 레지스터

    // ====================================================
    // 2. 메인 시퀀셜 로직 (always_ff 사용)
    // ====================================================
    // always_ff: 플립플롭 합성을 명시하여 실수를 방지함
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            cs_n      <= 1'b1;
            sclk      <= 1'b0;  // Mode 0
            mosi      <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
            rx_data   <= 8'b0;
            clk_cnt   <= '0;    // '0은 모든 비트를 0으로 채움
            bit_cnt   <= '0;
            shift_reg <= '0;
        end else begin
            case (state)
                // ------------------------------------------------
                // [IDLE] 대기 상태
                // ------------------------------------------------
                IDLE: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    done <= 1'b0;
                    
                    if (start) begin
                        shift_reg <= tx_data; // 데이터 로드
                        busy      <= 1'b1;
                        state     <= START;
                    end else begin
                        busy      <= 1'b0;
                    end
                end

                // ------------------------------------------------
                // [START] Setup 단계
                // ------------------------------------------------
                START: begin
                    clk_cnt <= '0;
                    bit_cnt <= 3'd7; 
                    
                    cs_n    <= 1'b0;      // Slave 선택
                    
                    // Mode 0: 첫 클럭 Rising 전에 데이터가 나가있어야 함
                    mosi    <= shift_reg[7]; 
                    
                    state   <= TRANS;
                end

                // ------------------------------------------------
                // [TRANS] 데이터 전송 (Mode 0: Rising Sample, Falling Shift)
                // ------------------------------------------------
                TRANS: begin
                    // 클럭 분주 카운터
                    if (clk_cnt < CLK_DIV - 1) 
                        clk_cnt <= clk_cnt + 1;
                    else 
                        clk_cnt <= '0;

                    // --- Timing 1: Rising Edge (Sample MISO) ---
                    if (clk_cnt == 0) begin
                        sclk <= 1'b0; 
                    end
                    else if (clk_cnt == CNT_MID) begin
                        sclk <= 1'b1;         // SCLK Rising
                        shift_reg[0] <= miso; // LSB에 수신 데이터 저장
                    end

                    // --- Timing 2: Falling Edge (Shift & MOSI Update) ---
                    else if (clk_cnt == CLK_DIV - 1) begin
                        sclk <= 1'b0;         // SCLK Falling
                        
                        if (bit_cnt > 0) begin
                            bit_cnt <= bit_cnt - 1;
                            // Shift Left: {기존[6:0], 0}
                            shift_reg <= {shift_reg[6:0], 1'b0}; 
                            mosi      <= shift_reg[6]; // 다음 비트 출력
                        end else begin
                            state <= DONE_STATE; // 8비트 완료
                        end
                    end
                end

                // ------------------------------------------------
                // [DONE] 종료 처리
                // ------------------------------------------------
                DONE_STATE: begin
                    cs_n    <= 1'b1;
                    busy    <= 1'b0;
                    done    <= 1'b1;      // 완료 펄스 발생
                    rx_data <= shift_reg; // 수신 데이터 업데이트
                    state   <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule