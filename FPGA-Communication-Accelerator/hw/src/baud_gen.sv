`timescale 1ns / 1ps

module baud_gen (
    input  logic        clk,        // System Clock
    input  logic        reset_n,    // Active Low Reset
    input  logic [15:0] divisor,    // 분주비 = Sys_Clk / (Baudrate * 16)
    output logic        tick        // 16x Oversampling Tick (1 cycle pulse)
);

    logic [15:0] counter;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= '0;
            tick    <= 1'b0;
        end else begin
            if (counter >= divisor) begin
                counter <= '0;
                tick    <= 1'b1; // 설정한 주기마다 1클럭 펄스 발생
            end else begin
                counter <= counter + 1;
                tick    <= 1'b0;
            end
        end
    end

endmodule