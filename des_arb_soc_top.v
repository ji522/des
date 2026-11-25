`timescale 1ns / 1ps
// ============================================================================
// des_arb_soc_top.v —— 2 通道 AXIS 仲裁 + DES 加密 SoC 集成顶层
//
//   s0_axis ─┐
//            ├─> axis_arb2 (每通道 16x65 FIFO + 包级 round-robin)
//   s1_axis ─┘          │
//                       └─> des_soc_top (DES 16 级流水 + AXIL 控制)
//                                  │
//                                  └─> m_axis
//
// 控制面：
//   s_axil_* -> axil_2to1_demux 地址译码（单 AXI4-Lite 从端口）
//               0x0000-0x00FF -> DES 5 个寄存器（key/mode/enable/status/guard）
//               0x0100-0x01FF -> 仲裁器寄存器（enable/mode/threshold/irq/counters）
//
// 数据面两个输入同属 clk 域；如需跨域，可在 axis_arb2 前各接一个 async_fifo。
// ============================================================================
module des_arb_soc_top (
    input  wire        clk,
    input  wire        rst_n,

    // ---- channel 0 AXI4-Stream slave ----
    input  wire        s0_axis_tvalid,
    output wire        s0_axis_tready,
    input  wire [63:0] s0_axis_tdata,
    input  wire        s0_axis_tlast,

    // ---- channel 1 AXI4-Stream slave ----
    input  wire        s1_axis_tvalid,
    output wire        s1_axis_tready,
    input  wire [63:0] s1_axis_tdata,
    input  wire        s1_axis_tlast,

    // ---- merged/encrypted AXI4-Stream master ----
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // ---- AXI4-Lite control plane（单端口，内部 1->2 地址译码）----
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

    // ---- observability ----
    output wire        irq_o,
    output wire        arb_busy_o,
    output wire        ready_key_o
);

    // ------------------------------------------------------------------
    // arbiter <-> DES data path
    // ------------------------------------------------------------------
    wire        arb_m_tvalid;
    wire        arb_m_tready;
    wire [63:0] arb_m_tdata;
    wire        arb_m_tlast;
    wire        arb_m_tuser;

    wire        des_s_tready;
    wire        des_m_tvalid;
    wire [63:0] des_m_tdata;
    wire        des_m_tlast;

    // ------------------------------------------------------------------
    // arbiter configuration / status
    // ------------------------------------------------------------------
    wire        arb_enable;
    wire        arb_mode;
    wire [7:0]  af_thresh0;
    wire [7:0]  af_thresh1;
    wire        arb_clear_counters;

    wire [4:0]  fifo0_count;
    wire [4:0]  fifo1_count;
    wire        fifo0_full, fifo1_full;
    wire        fifo0_af, fifo1_af;
    wire        ch0_done, ch1_done;
    wire        cur_ch, arb_lock;
    wire        arb_busy;

    wire [31:0] ch0_beats_in, ch0_packets_in, ch0_beats_out, ch0_packets_out;
    wire [31:0] ch0_stall, ch0_blocked;
    wire [31:0] ch1_beats_in, ch1_packets_in, ch1_beats_out, ch1_packets_out;
    wire [31:0] ch1_stall, ch1_blocked;

    // ------------------------------------------------------------------
    // 单 AXIL 端口 -> DES(0x000-0x0FF) / arbiter(0x100-0x1FF)
    // ------------------------------------------------------------------
    wire        d_axil_awvalid, d_axil_awready;
    wire [31:0] d_axil_awaddr;
    wire        d_axil_wvalid,  d_axil_wready;
    wire [31:0] d_axil_wdata;
    wire [3:0]  d_axil_wstrb;
    wire        d_axil_bvalid,  d_axil_bready;
    wire [1:0]  d_axil_bresp;
    wire        d_axil_arvalid, d_axil_arready;
    wire [31:0] d_axil_araddr;
    wire        d_axil_rvalid,  d_axil_rready;
    wire [31:0] d_axil_rdata;
    wire [1:0]  d_axil_rresp;

    wire        a_axil_awvalid, a_axil_awready;
    wire [31:0] a_axil_awaddr;
    wire        a_axil_wvalid,  a_axil_wready;
    wire [31:0] a_axil_wdata;
    wire [3:0]  a_axil_wstrb;
    wire        a_axil_bvalid,  a_axil_bready;
    wire [1:0]  a_axil_bresp;
    wire        a_axil_arvalid, a_axil_arready;
    wire [31:0] a_axil_araddr;
    wire        a_axil_rvalid,  a_axil_rready;
    wire [31:0] a_axil_rdata;
    wire [1:0]  a_axil_rresp;

    axil_2to1_demux u_axil_demux (
        .clk            (clk),
        .rst_n          (rst_n),

        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),

        .m0_awvalid     (d_axil_awvalid),
        .m0_awready     (d_axil_awready),
        .m0_awaddr      (d_axil_awaddr),
        .m0_wvalid      (d_axil_wvalid),
        .m0_wready      (d_axil_wready),
        .m0_wdata       (d_axil_wdata),
        .m0_wstrb       (d_axil_wstrb),
        .m0_bvalid      (d_axil_bvalid),
        .m0_bready      (d_axil_bready),
        .m0_bresp       (d_axil_bresp),
        .m0_arvalid     (d_axil_arvalid),
        .m0_arready     (d_axil_arready),
        .m0_araddr      (d_axil_araddr),
        .m0_rvalid      (d_axil_rvalid),
        .m0_rready      (d_axil_rready),
        .m0_rdata       (d_axil_rdata),
        .m0_rresp       (d_axil_rresp),

        .m1_awvalid     (a_axil_awvalid),
        .m1_awready     (a_axil_awready),
        .m1_awaddr      (a_axil_awaddr),
        .m1_wvalid      (a_axil_wvalid),
        .m1_wready      (a_axil_wready),
        .m1_wdata       (a_axil_wdata),
        .m1_wstrb       (a_axil_wstrb),
        .m1_bvalid      (a_axil_bvalid),
        .m1_bready      (a_axil_bready),
        .m1_bresp       (a_axil_bresp),
        .m1_arvalid     (a_axil_arvalid),
        .m1_arready     (a_axil_arready),
        .m1_araddr      (a_axil_araddr),
        .m1_rvalid      (a_axil_rvalid),
        .m1_rready      (a_axil_rready),
        .m1_rdata       (a_axil_rdata),
        .m1_rresp       (a_axil_rresp)
    );

    assign arb_busy_o = arb_busy;

    // ------------------------------------------------------------------
    // 2-channel arbiter
    // ------------------------------------------------------------------
    axis_arb2 #(
        .DATA_W (64),
        .FIFO_AW(4)
    ) u_arb (
        .clk                  (clk),
        .rst_n                (rst_n),

        .s0_axis_tvalid       (s0_axis_tvalid),
        .s0_axis_tready       (s0_axis_tready),
        .s0_axis_tdata        (s0_axis_tdata),
        .s0_axis_tlast        (s0_axis_tlast),

        .s1_axis_tvalid       (s1_axis_tvalid),
        .s1_axis_tready       (s1_axis_tready),
        .s1_axis_tdata        (s1_axis_tdata),
        .s1_axis_tlast        (s1_axis_tlast),

        .m_axis_tvalid        (arb_m_tvalid),
        .m_axis_tready        (arb_m_tready),
        .m_axis_tdata         (arb_m_tdata),
        .m_axis_tlast         (arb_m_tlast),
        .m_axis_tuser         (arb_m_tuser),

        .enable               (arb_enable),
        .arb_mode             (arb_mode),
        .almost_full_thresh0  (af_thresh0),
        .almost_full_thresh1  (af_thresh1),
        .clear_counters       (arb_clear_counters),

        .fifo0_count_o        (fifo0_count),
        .fifo1_count_o        (fifo1_count),
        .fifo0_full_o         (fifo0_full),
        .fifo1_full_o         (fifo1_full),
        .fifo0_almost_full_o  (fifo0_af),
        .fifo1_almost_full_o  (fifo1_af),
        .ch0_done_o           (ch0_done),
        .ch1_done_o           (ch1_done),
        .cur_ch_o             (cur_ch),
        .lock_o               (arb_lock),
        .busy_o               (arb_busy),

        .ch0_beats_in_o       (ch0_beats_in),
        .ch0_packets_in_o     (ch0_packets_in),
        .ch0_beats_out_o      (ch0_beats_out),
        .ch0_packets_out_o    (ch0_packets_out),
        .ch0_stall_o          (ch0_stall),
        .ch0_blocked_o        (ch0_blocked),

        .ch1_beats_in_o       (ch1_beats_in),
        .ch1_packets_in_o     (ch1_packets_in),
        .ch1_beats_out_o      (ch1_beats_out),
        .ch1_packets_out_o    (ch1_packets_out),
        .ch1_stall_o          (ch1_stall),
        .ch1_blocked_o        (ch1_blocked)
    );

    // arbiter -> DES input; DES input ready back-pressures the arbiter
    assign arb_m_tready = des_s_tready;

    // ------------------------------------------------------------------
    // arbiter AXI4-Lite control/status
    // ------------------------------------------------------------------
    axis_arb_regs #(.FIFO_AW(4)) u_arb_regs (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .s_axil_awvalid         (a_axil_awvalid),
        .s_axil_awready         (a_axil_awready),
        .s_axil_awaddr          (a_axil_awaddr),
        .s_axil_wvalid          (a_axil_wvalid),
        .s_axil_wready          (a_axil_wready),
        .s_axil_wdata           (a_axil_wdata),
        .s_axil_wstrb           (a_axil_wstrb),
        .s_axil_bvalid          (a_axil_bvalid),
        .s_axil_bready          (a_axil_bready),
        .s_axil_bresp           (a_axil_bresp),
        .s_axil_arvalid         (a_axil_arvalid),
        .s_axil_arready         (a_axil_arready),
        .s_axil_araddr          (a_axil_araddr),
        .s_axil_rready          (a_axil_rready),
        .s_axil_rvalid          (a_axil_rvalid),
        .s_axil_rdata           (a_axil_rdata),
        .s_axil_rresp           (a_axil_rresp),

        .enable_o               (arb_enable),
        .arb_mode_o             (arb_mode),
        .af_thresh0_o           (af_thresh0),
        .af_thresh1_o           (af_thresh1),
        .clear_counters_o       (arb_clear_counters),

        .fifo0_count_i          (fifo0_count),
        .fifo1_count_i          (fifo1_count),
        .fifo0_full_i           (fifo0_full),
        .fifo1_full_i           (fifo1_full),
        .fifo0_almost_full_i    (fifo0_af),
        .fifo1_almost_full_i    (fifo1_af),
        .ch0_done_i             (ch0_done),
        .ch1_done_i             (ch1_done),
        .cur_ch_i               (cur_ch),
        .lock_i                 (arb_lock),
        .busy_i                 (arb_busy),

        .ch0_beats_in_i         (ch0_beats_in),
        .ch0_packets_in_i       (ch0_packets_in),
        .ch0_beats_out_i        (ch0_beats_out),
        .ch0_packets_out_i      (ch0_packets_out),
        .ch0_stall_i            (ch0_stall),
        .ch0_blocked_i          (ch0_blocked),
        .ch1_beats_in_i         (ch1_beats_in),
        .ch1_packets_in_i       (ch1_packets_in),
        .ch1_beats_out_i        (ch1_beats_out),
        .ch1_packets_out_i      (ch1_packets_out),
        .ch1_stall_i            (ch1_stall),
        .ch1_blocked_i          (ch1_blocked),

        .irq_o                  (irq_o)
    );

    // ------------------------------------------------------------------
    // DES SoC
    // ------------------------------------------------------------------
    des_soc_top u_des (
        .clk              (clk),
        .rst_n            (rst_n),

        .s_axis_tvalid    (arb_m_tvalid),
        .s_axis_tready    (des_s_tready),
        .s_axis_tdata     (arb_m_tdata),
        .s_axis_tlast     (arb_m_tlast),

        .m_axis_tvalid    (des_m_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tdata     (des_m_tdata),
        .m_axis_tlast     (des_m_tlast),

        .s_axil_awvalid   (d_axil_awvalid),
        .s_axil_awready   (d_axil_awready),
        .s_axil_awaddr    (d_axil_awaddr),
        .s_axil_wvalid    (d_axil_wvalid),
        .s_axil_wready    (d_axil_wready),
        .s_axil_wdata     (d_axil_wdata),
        .s_axil_wstrb     (d_axil_wstrb),
        .s_axil_bvalid    (d_axil_bvalid),
        .s_axil_bready    (d_axil_bready),
        .s_axil_bresp     (d_axil_bresp),
        .s_axil_arvalid   (d_axil_arvalid),
        .s_axil_arready   (d_axil_arready),
        .s_axil_araddr    (d_axil_araddr),
        .s_axil_rvalid    (d_axil_rvalid),
        .s_axil_rready    (d_axil_rready),
        .s_axil_rdata     (d_axil_rdata),
        .s_axil_rresp     (d_axil_rresp),

        .ready_key_o      (ready_key_o)
    );

    assign m_axis_tvalid = des_m_tvalid;
    assign m_axis_tdata  = des_m_tdata;
    assign m_axis_tlast  = des_m_tlast;

endmodule
