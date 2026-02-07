`timescale 1ns / 1ps

module fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4  // 2^4 = 16 depth
)(
    input  logic                  clk,
    input  logic                  reset_n,
    
    // Write Interface (CPU -> FIFO)
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  full,
    
    // Read Interface (FIFO -> UART Core)
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  empty
);

    // 내부 메모리 배열
    logic [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];
    
    // [추가할 코드] 시뮬레이션을 위해 메모리를 0으로 초기화
    initial begin
        for (int i = 0; i < (2**ADDR_WIDTH); i++) begin
            mem[i] = '0;
        end
    end

    // 포인터들
    logic [ADDR_WIDTH:0] wr_ptr, wr_ptr_next; // 1비트 더 크게 잡음 (Full/Empty 구분용)
    logic [ADDR_WIDTH:0] rd_ptr, rd_ptr_next;

    // --------------------------------------------------------
    // Write & Read Logic
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            wr_ptr <= wr_ptr_next;
            rd_ptr <= rd_ptr_next;
        end
    end

    // Memory Write (No Reset needed for memory)
    always_ff @(posedge clk) begin
        if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // Next Pointer Logic
    always_comb begin
        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;

        if (wr_en && !full) begin
            wr_ptr_next = wr_ptr + 1;
        end

        if (rd_en && !empty) begin
            rd_ptr_next = rd_ptr + 1;
        end
    end

    // --------------------------------------------------------
    // Status Signals
    // --------------------------------------------------------
    // Read는 Combinational로 바로 출력 (First Word Fall Through 아님, 일반 모드)
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // Empty: 포인터가 완전히 같을 때
    assign empty = (wr_ptr == rd_ptr);

    // Full: MSB(최상위 비트)만 다르고 나머지가 같을 때
    // 예: wr_ptr=10000(16), rd_ptr=00000(0) -> 꽉 참
    assign full = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) &&
                  (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);

endmodule