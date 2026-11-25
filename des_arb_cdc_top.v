`timescale 1ns / 1ps
// ============================================================================
// des_arb_cdc_top.v —— 多时钟 2 通道安全加密前端
//
//   s0_axis (wclk0) ──> async_axis_fifo ──┐
//                                         ├─> des_arb_soc_top (clk) ──> m_axis (clk)
//   s1_axis (wclk1) ──> async_axis_fifo ──┘        （仲裁 + DES + 单 AXIL）
//
// 每个输入通道自己的时钟域：写侧 {tlast,tdata} 同字进 65 位异步 FIFO；
// 快域 show-ahead 读出，背靠背每拍一个字；FIFO 满后向上游反压，不丢数。
//
// 控制面：单 AXI4-Lite（clk 域），内部 0x000=DES、0x100=仲裁器。
// 复位：每个时钟域各自 2 级同步释放；异步 FIFO 写/读侧用各自域内的同步复位。
// ============================================================================
module des_arb_cdc_top (
    // channel 0 write domain
    input  wire        wclk0,
    input  wire        wrst0_n,
    input  wire        s0_axis_tvalid,
    output wire        s0_axis_tready,
    input  wire [63:0] s0_axis_tdata,
    input  wire        s0_axis_tlast,

    // channel 1 write domain
    input  wire        wclk1,
    input  wire        wrst1_n,
    input  wire        s1_axis_tvalid,
    output wire        s1_axis_tready,
    input  wire [63:0] s1_axis_tdata,
    input  wire        s1_axis_tlast,

    // core domain
    input  wire        clk,
    input  wire        rst_n,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // single AXI4-Lite control plane (clk domain)
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
    input  wire        s_axil_rready,
    output wire        s_axil_rvalid,
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,

    // observability
    output wire        irq_o,
    output wire        arb_busy_o,
    output wire        ready_key_o,
    output wire        fifo0_full,
    output wire        fifo0_empty,
    output wire        fifo1_full,
    output wire        fifo1_empty
);

    // ------------------------------------------------------------------
    // per-domain reset synchronizers (async assert / sync deassert)
    // ------------------------------------------------------------------
    wire wrst0_sync, wrst1_sync, rst_sync;

    reset_sync u_rs0 (.clk(wclk0), .arst_n(wrst0_n), .srst_n(wrst0_sync));
    reset_sync u_rs1 (.clk(wclk1), .arst_n(wrst1_n), .srst_n(wrst1_sync));
    reset_sync u_rsc (.clk(clk),   .arst_n(rst_n),   .srst_n(rst_sync));

    // ------------------------------------------------------------------
    // channel 0 async FIFO
    // ------------------------------------------------------------------
    wire        c0_tvalid, c0_tready, c0_tlast;
    wire [63:0] c0_tdata;

    async_axis_fifo #(.DATA_W(64), .ADDR_W(4)) u_af0 (
        .wclk          (wclk0),
        .wrst_n        (wrst0_sync),
        .s_axis_tvalid (s0_axis_tvalid),
        .s_axis_tready (s0_axis_tready),
        .s_axis_tdata  (s0_axis_tdata),
        .s_axis_tlast  (s0_axis_tlast),
        .wfull         (fifo0_full),

        .rclk          (clk),
        .rrst_n        (rst_sync),
        .m_axis_tvalid (c0_tvalid),
        .m_axis_tready (c0_tready),
        .m_axis_tdata  (c0_tdata),
        .m_axis_tlast  (c0_tlast),
        .rempty        (fifo0_empty)
    );

    // ------------------------------------------------------------------
    // channel 1 async FIFO
    // ------------------------------------------------------------------
    wire        c1_tvalid, c1_tready, c1_tlast;
    wire [63:0] c1_tdata;

    async_axis_fifo #(.DATA_W(64), .ADDR_W(4)) u_af1 (
        .wclk          (wclk1),
        .wrst_n        (wrst1_sync),
        .s_axis_tvalid (s1_axis_tvalid),
        .s_axis_tready (s1_axis_tready),
        .s_axis_tdata  (s1_axis_tdata),
        .s_axis_tlast  (s1_axis_tlast),
        .wfull         (fifo1_full),

        .rclk          (clk),
        .rrst_n        (rst_sync),
        .m_axis_tvalid (c1_tvalid),
        .m_axis_tready (c1_tready),
        .m_axis_tdata  (c1_tdata),
        .m_axis_tlast  (c1_tlast),
        .rempty        (fifo1_empty)
    );

    // ------------------------------------------------------------------
    // core: 2-channel arbiter + DES + single AXIL
    // ------------------------------------------------------------------
    des_arb_soc_top u_core (
        .clk                 (clk),
        .rst_n               (rst_n),

        .s0_axis_tvalid      (c0_tvalid),
        .s0_axis_tready      (c0_tready),
        .s0_axis_tdata       (c0_tdata),
        .s0_axis_tlast       (c0_tlast),

        .s1_axis_tvalid      (c1_tvalid),
        .s1_axis_tready      (c1_tready),
        .s1_axis_tdata       (c1_tdata),
        .s1_axis_tlast       (c1_tlast),

        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),
        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tlast        (m_axis_tlast),

        .s_axil_awvalid      (s_axil_awvalid),
        .s_axil_awready      (s_axil_awready),
        .s_axil_awaddr       (s_axil_awaddr),
        .s_axil_wvalid       (s_axil_wvalid),
        .s_axil_wready       (s_axil_wready),
        .s_axil_wdata        (s_axil_wdata),
        .s_axil_wstrb        (s_axil_wstrb),
        .s_axil_bvalid       (s_axil_bvalid),
        .s_axil_bready       (s_axil_bready),
        .s_axil_bresp        (s_axil_bresp),
        .s_axil_arvalid      (s_axil_arvalid),
        .s_axil_arready      (s_axil_arready),
        .s_axil_araddr       (s_axil_araddr),
        .s_axil_rready       (s_axil_rready),
        .s_axil_rvalid       (s_axil_rvalid),
        .s_axil_rdata        (s_axil_rdata),
        .s_axil_rresp        (s_axil_rresp),

        .irq_o               (irq_o),
        .arb_busy_o          (arb_busy_o),
        .ready_key_o         (ready_key_o)
    );

endmodule
