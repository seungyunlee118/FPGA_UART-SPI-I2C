`timescale 1ns / 1ps

module uart_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [15:0] divisor,
    
    // UART Physical Interface
    input  logic        rx_pin,
    output logic        tx_pin,
    
    // --- User Interface (FIFO 제어용) ---
    
    // TX FIFO Write (CPU가 데이터를 넣음)
    input  logic        tx_wr_en,
    input  logic [7:0]  tx_wr_data,
    output logic        tx_full,
    
    // RX FIFO Read (CPU가 데이터를 꺼냄)
    input  logic        rx_rd_en,
    output logic [7:0]  rx_rd_data,
    output logic        rx_empty,
    
    output logic        rx_err // 에러 상태
);

    // Internal Signals
    logic       tick;
    
    // TX Channel Signals
    logic       tx_fifo_empty;
    logic [7:0] tx_fifo_out;
    logic       tx_core_start;
    logic       tx_core_done;
    logic       tx_core_busy;
    
    // RX Channel Signals
    logic       rx_core_done;
    logic [7:0] rx_core_data;
    logic       rx_core_err;

    // -------------------------------------------------------
    // 1. Baud Rate Generator
    // -------------------------------------------------------
    baud_gen u_baud_gen (
        .clk(clk), .reset_n(reset_n), .divisor(divisor), .tick(tick)
    );

    // -------------------------------------------------------
    // 2. TX Channel (FIFO + UART TX)
    // -------------------------------------------------------
    
    // [TX FIFO]
    fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) u_tx_fifo (
        .clk(clk), .reset_n(reset_n),
        .wr_en(tx_wr_en), .wr_data(tx_wr_data), .full(tx_full), // CPU Side
        .rd_en(tx_core_done), .rd_data(tx_fifo_out), .empty(tx_fifo_empty) // UART Side
    );
    // 주의: 여기서는 간단하게 구현하기 위해 UART가 전송을 마치면(tx_core_done)
    // 자동으로 FIFO의 다음 데이터를 꺼내도록(rd_en) 연결했습니다.
    // 하지만, 첫 데이터를 시작시키기 위한 트리거 로직이 필요합니다.

    // [TX Control Logic]
    // FIFO에 데이터가 있고(not empty), UART가 바쁘지 않으면(not busy) 전송 시작!
    assign tx_core_start = (!tx_fifo_empty) && (!tx_core_busy) && (!tx_core_done);

    // [UART TX Core]
    uart_tx u_uart_tx (
        .clk(clk), .reset_n(reset_n), .tick(tick),
        .tx_start(tx_core_start), .tx_data(tx_fifo_out),
        .tx_pin(tx_pin), .tx_done(tx_core_done), .tx_busy(tx_core_busy)
    );


    // -------------------------------------------------------
    // 3. RX Channel (UART RX + FIFO)
    // -------------------------------------------------------
    
    // [UART RX Core]
    uart_rx u_uart_rx (
        .clk(clk), .reset_n(reset_n), .tick(tick), .rx_pin(rx_pin),
        .rx_done(rx_core_done), .rx_data(rx_core_data), .rx_err(rx_core_err)
    );
    
    // [RX FIFO]
    // UART가 수신을 완료하면(rx_core_done) 자동으로 FIFO에 Write(wr_en) 합니다.
    fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) u_rx_fifo (
        .clk(clk), .reset_n(reset_n),
        .wr_en(rx_core_done), .wr_data(rx_core_data), .full(), // UART Side (full은 무시)
        .rd_en(rx_rd_en), .rd_data(rx_rd_data), .empty(rx_empty) // CPU Side
    );
    
    assign rx_err = rx_core_err;

endmodule