`timescale 1ns / 1ps
// ============================================================================
// axil_2to1_demux.v —— 1 个 AXI4-Lite 从端口 -> 2 个 AXI4-Lite 主端口
//
// 地址映射（用 addr[8] 选路）：
//   0x0000_0000 – 0x0000_00FF  -> m0（DES 控制面）
//   0x0000_0100 – 0x0000_01FF  -> m1（仲裁器控制面）
//
// 约束/取舍：
//  - 单 outstanding：aw_seen / ar_seen 在响应握手后清除；
//  - W 必须等 AW 先到（W 先到会被反压），这样保持 AW/W 同属一个 slave；
//  - 读地址在 AR 握手时锁存，R 数据按锁存的选择回送；
//  - 不做 burst、不做 ID/outstanding 重排，符合 AXI4-Lite。
// ============================================================================
module axil_2to1_demux (
    input  wire        clk,
    input  wire        rst_n,

    // ---- slave ----
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,
    output wire [1:0]  s_axil_bresp,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    input  wire [31:0] s_axil_araddr,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,

    // ---- master 0 (DES) ----
    output wire        m0_awvalid,
    input  wire        m0_awready,
    output wire [31:0] m0_awaddr,
    output wire        m0_wvalid,
    input  wire        m0_wready,
    output wire [31:0] m0_wdata,
    output wire [3:0]  m0_wstrb,
    input  wire        m0_bvalid,
    output wire        m0_bready,
    input  wire [1:0]  m0_bresp,
    output wire        m0_arvalid,
    input  wire        m0_arready,
    output wire [31:0] m0_araddr,
    input  wire        m0_rvalid,
    output wire        m0_rready,
    input  wire [31:0] m0_rdata,
    input  wire [1:0]  m0_rresp,

    // ---- master 1 (arbiter) ----
    output wire        m1_awvalid,
    input  wire        m1_awready,
    output wire [31:0] m1_awaddr,
    output wire        m1_wvalid,
    input  wire        m1_wready,
    output wire [31:0] m1_wdata,
    output wire [3:0]  m1_wstrb,
    input  wire        m1_bvalid,
    output wire        m1_bready,
    input  wire [1:0]  m1_bresp,
    output wire        m1_arvalid,
    input  wire        m1_arready,
    output wire [31:0] m1_araddr,
    input  wire        m1_rvalid,
    output wire        m1_rready,
    input  wire [31:0] m1_rdata,
    input  wire [1:0]  m1_rresp
);

    // m0 = addr[8]==0, m1 = addr[8]==1
    wire aw_sel = s_axil_awaddr[8];
    wire ar_sel = s_axil_araddr[8];

    reg  aw_seen, aw_sel_r;
    reg  ar_seen, ar_sel_r;

    // ------------------------------------------------------------------
    // write: AW 先到，W 等 aw_seen
    // ------------------------------------------------------------------
    assign s_axil_awready = !aw_seen && (aw_sel ? m1_awready : m0_awready);
    assign m0_awvalid     = s_axil_awvalid && !aw_sel && !aw_seen;
    assign m1_awvalid     = s_axil_awvalid &&  aw_sel && !aw_seen;
    assign m0_awaddr      = s_axil_awaddr;
    assign m1_awaddr      = s_axil_awaddr;

    assign s_axil_wready = aw_seen && (aw_sel_r ? m1_wready : m0_wready);
    assign m0_wvalid     = s_axil_wvalid && aw_seen && !aw_sel_r;
    assign m1_wvalid     = s_axil_wvalid && aw_seen &&  aw_sel_r;
    assign m0_wdata      = s_axil_wdata;
    assign m1_wdata      = s_axil_wdata;
    assign m0_wstrb      = s_axil_wstrb;
    assign m1_wstrb      = s_axil_wstrb;

    assign s_axil_bvalid = aw_seen && (aw_sel_r ? m1_bvalid : m0_bvalid);
    assign s_axil_bresp  = aw_sel_r ? m1_bresp : m0_bresp;
    assign m0_bready     = s_axil_bready && aw_seen && !aw_sel_r;
    assign m1_bready     = s_axil_bready && aw_seen &&  aw_sel_r;

    wire aw_fire = s_axil_awvalid && s_axil_awready;
    wire b_fire  = s_axil_bvalid  && s_axil_bready;

    // ------------------------------------------------------------------
    // read: AR 握手锁存选择，R 按锁存回送
    // ------------------------------------------------------------------
    assign s_axil_arready = !ar_seen && (ar_sel ? m1_arready : m0_arready);
    assign m0_arvalid     = s_axil_arvalid && !ar_sel && !ar_seen;
    assign m1_arvalid     = s_axil_arvalid &&  ar_sel && !ar_seen;
    assign m0_araddr      = s_axil_araddr;
    assign m1_araddr      = s_axil_araddr;

    assign s_axil_rvalid = ar_seen && (ar_sel_r ? m1_rvalid : m0_rvalid);
    assign s_axil_rdata  = ar_sel_r ? m1_rdata : m0_rdata;
    assign s_axil_rresp  = ar_sel_r ? m1_rresp : m0_rresp;
    assign m0_rready     = s_axil_rready && ar_seen && !ar_sel_r;
    assign m1_rready     = s_axil_rready && ar_seen &&  ar_sel_r;

    wire ar_fire = s_axil_arvalid && s_axil_arready;
    wire r_fire  = s_axil_rvalid  && s_axil_rready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen  <= 1'b0;
            aw_sel_r <= 1'b0;
            ar_seen  <= 1'b0;
            ar_sel_r <= 1'b0;
        end else begin
            if (aw_fire) begin
                aw_seen  <= 1'b1;
                aw_sel_r <= aw_sel;
            end else if (b_fire) begin
                aw_seen  <= 1'b0;
            end

            if (ar_fire) begin
                ar_seen  <= 1'b1;
                ar_sel_r <= ar_sel;
            end else if (r_fire) begin
                ar_seen  <= 1'b0;
            end
        end
    end

endmodule
