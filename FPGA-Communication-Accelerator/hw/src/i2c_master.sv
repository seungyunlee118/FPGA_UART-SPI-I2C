`timescale 1ns / 1ps

module i2c_master (
    input  logic        clk,
    input  logic        rst_n,
    
    // [User Interface]
    input  logic        start,
    input  logic [6:0]  addr,
    input  logic        rw,
    input  logic [7:0]  wdata,
    output logic [7:0]  rdata,
    output logic        busy,
    output logic        done,
    output logic        ack_error,

    // [Physical Interface]
    input  logic        scl_i,
    output logic        scl_o,
    output logic        scl_t,
    input  logic        sda_i,
    output logic        sda_o,
    output logic        sda_t
);

    // 100kHz 생성용 (100MHz / 1000분주 -> 4분할하므로 250)
    localparam int CLK_DIV = 250; 
    
    logic [8:0] clk_cnt;
    logic [1:0] q_cnt;
    logic       tick;

    typedef enum logic [3:0] {
        IDLE, START, ADDR, ACK_ADDR, DATA_TX, ACK_TX,
        DATA_RX, ACK_RX, NACK_RX, STOP
    } state_t;

    state_t state;
    
    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;

    // ====================================================
    // 1. 타이밍 생성기 (수정됨)
    // ====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 0;   // [수정] '0 대신 0 사용
            q_cnt   <= 0;   // [수정] '0 대신 0 사용
            tick    <= 1'b0;
        end else begin
            // busy 상태거나 start 명령이 오면 무조건 카운터 돌림
            if (busy || start) begin
                if (clk_cnt == CLK_DIV - 1) begin
                    clk_cnt <= 0; // [수정]
                    q_cnt   <= q_cnt + 1;
                    tick    <= 1'b1;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                    tick    <= 1'b0;
                end
            end else begin
                // 정말 아무일도 없을 때만 리셋
                clk_cnt <= 0; // [수정]
                q_cnt   <= 0; // [수정]
                tick    <= 1'b0;
            end
        end
    end

    // ====================================================
    // 2. FSM (수정됨)
    // ====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            scl_t     <= 1'b1; sda_t <= 1'b1;
            scl_o     <= 1'b0; sda_o <= 1'b0;
            busy      <= 1'b0; done  <= 1'b0;
            ack_error <= 1'b0;
            bit_cnt   <= 3'd7;
            shift_reg <= 0; // [수정]
            rdata     <= 0; // [수정]
        end else begin
            // IDLE 탈출 로직 (즉시 반응)
            if (state == IDLE) begin
                scl_t <= 1'b1;
                sda_t <= 1'b1;
                done  <= 1'b0;
                
                if (start) begin
                    state     <= START;
                    busy      <= 1'b1;
                    ack_error <= 1'b0;
                    shift_reg <= {addr, rw};
                end else begin
                    busy <= 1'b0;
                end
            end
            
            // 나머지 상태는 타이밍(Tick)에 맞춰서 동작
            else if (tick) begin
                // SCL 생성 로직
                case (q_cnt)
                    0: scl_t <= 1'b0; 
                    1: scl_t <= 1'b0; 
                    2: scl_t <= 1'b1; 
                    3: scl_t <= 1'b1; 
                endcase

                case (state)
                    // IDLE은 위에서 처리했으므로 생략

                    START: begin
                        // q_cnt 0: SCL=H, SDA=H
                        // q_cnt 1: SCL=H, SDA=L (Start Condition!)
                        if (q_cnt == 0) begin scl_t <= 1'b1; sda_t <= 1'b1; end
                        if (q_cnt == 1) begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        if (q_cnt == 2) begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        if (q_cnt == 3) begin scl_t <= 1'b0; sda_t <= 1'b0; state <= ADDR; bit_cnt <= 7; end
                    end

                    ADDR: begin
                        if (q_cnt == 0) begin 
                            if (shift_reg[7]) sda_t <= 1'b1; 
                            else              sda_t <= 1'b0; 
                        end
                        if (q_cnt == 3) begin
                            if (bit_cnt == 0) state <= ACK_ADDR;
                            else begin
                                bit_cnt   <= bit_cnt - 1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end
                        end
                    end

                    ACK_ADDR: begin
                        if (q_cnt == 0) sda_t <= 1'b1; // Release
                        if (q_cnt == 2) begin 
                            if (sda_i == 1'b1) ack_error <= 1'b1; 
                        end
                        if (q_cnt == 3) begin
                            if (ack_error) state <= STOP; 
                            else if (shift_reg[0]) begin // Read Mode
                                state <= DATA_RX; 
                                bit_cnt <= 7;
                            end else begin // Write Mode
                                state <= DATA_TX;
                                bit_cnt <= 7;
                                shift_reg <= wdata; 
                            end
                        end
                    end

                    DATA_TX: begin
                        if (q_cnt == 0) begin
                            if (shift_reg[7]) sda_t <= 1'b1; 
                            else              sda_t <= 1'b0; 
                        end
                        if (q_cnt == 3) begin
                            if (bit_cnt == 0) state <= ACK_TX;
                            else begin
                                bit_cnt   <= bit_cnt - 1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end
                        end
                    end

                    ACK_TX: begin
                        if (q_cnt == 0) sda_t <= 1'b1; 
                        if (q_cnt == 2) begin
                             if (sda_i == 1'b1) ack_error <= 1'b1; 
                        end
                        if (q_cnt == 3) state <= STOP; 
                    end
                    
                    STOP: begin
                        if (q_cnt == 0) begin scl_t <= 1'b0; sda_t <= 1'b0; end
                        if (q_cnt == 1) begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        if (q_cnt == 2) begin scl_t <= 1'b1; sda_t <= 1'b1; done <= 1'b1; busy <= 1'b0; state <= IDLE; end
                    end
                endcase
            end
        end
    end

endmodule