`timescale 1ns / 1ps

module spi_ip #
(
    // AXI4-Lite 파라미터
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
)
(
    // [1] 시스템 신호
    input  logic                                s_axi_aclk,
    input  logic                                s_axi_aresetn,

    // [2] AXI4-Lite Slave 인터페이스
    // Write Address Channel
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_awaddr,
    input  logic [2 : 0]                        s_axi_awprot,
    input  logic                                s_axi_awvalid,
    output logic                                s_axi_awready,
    // Write Data Channel
    input  logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1 : 0] s_axi_wstrb,
    input  logic                                s_axi_wvalid,
    output logic                                s_axi_wready,
    // Write Response Channel
    output logic [1 : 0]                        s_axi_bresp,
    output logic                                s_axi_bvalid,
    input  logic                                s_axi_bready,
    // Read Address Channel
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_araddr,
    input  logic [2 : 0]                        s_axi_arprot,
    input  logic                                s_axi_arvalid,
    output logic                                s_axi_arready,
    // Read Data Channel
    output logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_rdata,
    output logic [1 : 0]                        s_axi_rresp,
    output logic                                s_axi_rvalid,
    input  logic                                s_axi_rready,

    // [3] 사용자 포트 (보드 밖으로 나갈 SPI 핀들)
    output logic                                spi_sclk,
    output logic                                spi_mosi,
    input  logic                                spi_miso,
    output logic                                spi_cs_n
);

    // ====================================================
    // 레지스터 정의 (Address Map)
    // ====================================================
    // 0x00: Control Reg (Write Only) - bit 0: Start
    // 0x04: Status Reg  (Read Only)  - bit 0: Busy, bit 1: Done
    // 0x08: TX Data Reg (Write Only) - lower 8 bits
    // 0x0C: RX Data Reg (Read Only)  - lower 8 bits
    
    logic [31:0] reg0_ctrl;
    logic [31:0] reg1_status; 
    logic [31:0] reg2_tx;
    logic [31:0] reg3_rx;     

    // AXI 핸드쉐이크 내부 신호
    logic axi_awready, axi_wready, axi_arready, axi_rvalid, axi_bvalid;
    logic [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    logic [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;

    // SPI 모듈 연결용 신호
    logic        spi_start;
    logic        spi_busy;
    logic        spi_done;
    logic [7:0]  spi_tx_data;
    logic [7:0]  spi_rx_data;

    // 출력 할당
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_bresp   = 2'b00; // OKAY
    assign s_axi_arready = axi_arready;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00; // OKAY

    // ====================================================
    // [1] SPI Master 모듈 인스턴스화 (하위 모듈 연결)
    // ====================================================
    // 주의: 하위 모듈 파일 이름은 여전히 spi_master.sv 여야 합니다.
    spi_master u_spi_master (
        .clk     (s_axi_aclk),
        .rst_n   (s_axi_aresetn), 
        
        // User Interface -> Register와 연결
        .start   (spi_start),
        .tx_data (spi_tx_data),
        .rx_data (spi_rx_data),
        .busy    (spi_busy),
        .done    (spi_done),

        // Physical Interface -> 외부 핀과 연결
        .sclk    (spi_sclk),
        .mosi    (spi_mosi),
        .miso    (spi_miso),
        .cs_n    (spi_cs_n)
    );

    // 레지스터와 신호 연결
    assign spi_start   = reg0_ctrl[0]; 
    assign spi_tx_data = reg2_tx[7:0];

    // ====================================================
    // [2] AXI Write Logic (PS -> FPGA)
    // ====================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            reg0_ctrl   <= 32'b0;
            reg2_tx     <= 32'b0;
        end else begin
            // 1. Write Address Handshake
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
                axi_awaddr  <= s_axi_awaddr; 
            end else begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end

            // 2. Write Data Latching
            if (axi_awready && axi_wready) begin
                case (axi_awaddr[3:2]) 
                    2'b00: reg0_ctrl <= s_axi_wdata; // 0x00: Control
                    2'b10: reg2_tx   <= s_axi_wdata; // 0x08: TX Data
                    default: ;
                endcase
            end

            // 3. Write Response
            if (axi_awready && axi_wready) begin
                axi_bvalid <= 1'b1;
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ====================================================
    // [3] AXI Read Logic (PS <- FPGA)
    // ====================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'b0;
        end else begin
            // 1. Read Address Handshake
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            // 2. Read Data Output
            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                
                case (axi_araddr[3:2])
                    2'b00: axi_rdata <= reg0_ctrl; 
                    2'b01: axi_rdata <= {30'b0, spi_done, spi_busy}; // 0x04: Status
                    2'b10: axi_rdata <= reg2_tx;
                    2'b11: axi_rdata <= {24'b0, spi_rx_data};        // 0x0C: RX Data
                    default: axi_rdata <= 32'b0;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

endmodule