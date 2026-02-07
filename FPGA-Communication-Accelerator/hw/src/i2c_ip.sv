`timescale 1ns / 1ps

module i2c_ip #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5 // 레지스터가 좀 늘어서 5비트로 늘림 (0x00 ~ 0x1F)
)
(
    // [1] 시스템 신호
    input  logic                                s_axi_aclk,
    input  logic                                s_axi_aresetn,

    // [2] AXI4-Lite 인터페이스
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_awaddr,
    input  logic [2 : 0]                        s_axi_awprot,
    input  logic                                s_axi_awvalid,
    output logic                                s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1 : 0] s_axi_wstrb,
    input  logic                                s_axi_wvalid,
    output logic                                s_axi_wready,
    output logic [1 : 0]                        s_axi_bresp,
    output logic                                s_axi_bvalid,
    input  logic                                s_axi_bready,
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_araddr,
    input  logic [2 : 0]                        s_axi_arprot,
    input  logic                                s_axi_arvalid,
    output logic                                s_axi_arready,
    output logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_rdata,
    output logic [1 : 0]                        s_axi_rresp,
    output logic                                s_axi_rvalid,
    input  logic                                s_axi_rready,

    // [3] 사용자 포트 (보드 밖으로 나갈 물리적 핀: inout 타입)
    inout  wire                                 i2c_scl,
    inout  wire                                 i2c_sda
);

    // ====================================================
    // 레지스터 정의 (Address Map)
    // ====================================================
    // 0x00: Control (RW) - Bit0: Start, Bit1: R/W(0:Write, 1:Read)
    // 0x04: Status  (RO) - Bit0: Busy, Bit1: Done, Bit2: Ack_Error
    // 0x08: Address (RW) - Slave Address (7-bit)
    // 0x0C: WData   (RW) - 쓸 데이터 (8-bit)
    // 0x10: RData   (RO) - 읽은 데이터 (8-bit)

    logic [31:0] reg_ctrl;
    logic [31:0] reg_addr;
    logic [31:0] reg_wdata;
    // Status와 RData는 Read Only라 레지스터 변수 선언 불필요 (Wire로 직결)

    // AXI 핸드쉐이크 신호
    logic axi_awready, axi_wready, axi_arready, axi_rvalid, axi_bvalid;
    logic [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    logic [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;

    // I2C Master 연결용 내부 신호 (3가닥으로 분리된 신호)
    logic scl_i, scl_o, scl_t;
    logic sda_i, sda_o, sda_t;
    
    // 제어 신호 연결
    logic i2c_start, i2c_rw, i2c_busy, i2c_done, i2c_ack_err;
    logic [7:0] i2c_rdata_out;

    // AXI 출력 연결
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = axi_arready;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00;

    // ====================================================
    // [1] IOBUF 인스턴스화 (가장 중요한 부분!)
    // ====================================================
    // Vivado가 "아, 이거 3상 버퍼구나" 하고 알아듣고 하드웨어 핀 처리를 해줌
    
    IOBUF iobuf_scl (
        .O  (scl_i),   // Buffer Output -> FPGA 내부 입력
        .IO (i2c_scl), // Bidirectional Pin (보드 밖)
        .I  (scl_o),   // FPGA Output -> Buffer Input
        .T  (scl_t)    // Tri-state Enable (1=Input/Float, 0=Output)
    );

    IOBUF iobuf_sda (
        .O  (sda_i),   
        .IO (i2c_sda), 
        .I  (sda_o),   
        .T  (sda_t)    
    );

    // ====================================================
    // [2] I2C Master 모듈 연결
    // ====================================================
    i2c_master u_i2c_master (
        .clk       (s_axi_aclk),
        .rst_n     (s_axi_aresetn),

        // User Interface
        .start     (i2c_start),
        .addr      (reg_addr[6:0]),
        .rw        (reg_ctrl[1]),   // Control 레지스터 1번 비트가 R/W
        .wdata     (reg_wdata[7:0]),
        .rdata     (i2c_rdata_out),
        .busy      (i2c_busy),
        .done      (i2c_done),
        .ack_error (i2c_ack_err),

        // Physical Interface (3-wire) -> IOBUF와 연결
        .scl_i     (scl_i),
        .scl_o     (scl_o),
        .scl_t     (scl_t),
        .sda_i     (sda_i),
        .sda_o     (sda_o),
        .sda_t     (sda_t)
    );

    // 레지스터 비트 매핑
    assign i2c_start = reg_ctrl[0]; // Control 레지스터 0번 비트가 Start

    // ====================================================
    // [3] AXI Write Logic
    // ====================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            reg_ctrl    <= 32'b0;
            reg_addr    <= 32'b0;
            reg_wdata   <= 32'b0;
        end else begin
            // Address Handshake
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end

            // Data Latching
            if (axi_awready && axi_wready) begin
                case (axi_awaddr[4:2]) // 0x00, 0x04... 4바이트 단위
                    3'b000: reg_ctrl  <= s_axi_wdata; // 0x00
                    // 0x04 Status는 Read Only
                    3'b010: reg_addr  <= s_axi_wdata; // 0x08
                    3'b011: reg_wdata <= s_axi_wdata; // 0x0C
                    default: ;
                endcase
            end

            // Response
            if (axi_awready && axi_wready) begin
                axi_bvalid <= 1'b1;
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ====================================================
    // [4] AXI Read Logic
    // ====================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'b0;
        end else begin
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (axi_araddr[4:2])
                    3'b000: axi_rdata <= reg_ctrl; 
                    3'b001: axi_rdata <= {29'b0, i2c_ack_err, i2c_done, i2c_busy}; // 0x04 Status
                    3'b010: axi_rdata <= reg_addr;
                    3'b011: axi_rdata <= reg_wdata;
                    3'b100: axi_rdata <= {24'b0, i2c_rdata_out}; // 0x10 Read Data
                    default: axi_rdata <= 32'b0;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

endmodule