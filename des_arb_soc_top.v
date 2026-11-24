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
//   s_axil_des_*  -> des_soc_top 内部 5 个寄存器（key/mode/enable/status/guard）
//   s_axil_arb_*  -> axis_arb_regs（enable/mode/threshold/irq/counters）
//
// 说明：本 demo 把两套控制面暴露成两个 AXI4-Lite 从端口，便于分模块验证；
// 真实 SoC 会在前面放一个 AXI4-Lite crossbar/地址译码，把两者映射到同一
// 控制总线。数据面两个输入同属 clk 域，不含跨时钟；如需跨域，可在
// axis_arb2 前各接一个 async_fifo。
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

    // ---- DES control plane (AXI4-Lite) ----
    input  wire        s_axil_des_awvalid,
    output wire        s_axil_des_awready,
    input  wire [31:0] s_axil_des_awaddr,
    input  wire        s_axil_des_wvalid,
    output wire        s_axil_des_wready,
    input  wire [31:0] s_axil_des_wdata,
    input  wire [3:0]  s_axil_des_wstrb,
    output wire        s_axil_des_bvalid,
    input  wire        s_axil_des_bready,
    output wire [1:0]  s_axil_des_bresp,
    input  wire        s_axil_des_arvalid,
    output wire        s_axil_des_arready,
    input  wire [31:0] s_axil_des_araddr,
    input  wire        s_axil_des_rready,
    output wire        s_axil_des_rvalid,
    output wire [31:0] s_axil_des_rdata,
    output wire [1:0]  s_axil_des_rresp,

    // ---- arbiter control plane (AXI4-Lite) ----
    input  wire        s_axil_arb_awvalid,
    output wire        s_axil_arb_awready,
    input  wire [31:0] s_axil_arb_awaddr,
    input  wire        s_axil_arb_wvalid,
    output wire        s_axil_arb_wready,
    input  wire [31:0] s_axil_arb_wdata,
    input  wire [3:0]  s_axil_arb_wstrb,
    output wire        s_axil_arb_bvalid,
    input  wire        s_axil_arb_bready,
    output wire [1:0]  s_axil_arb_bresp,
    input  wire        s_axil_arb_arvalid,
    output wire        s_axil_arb_arready,
    input  wire [31:0] s_axil_arb_araddr,
    input  wire        s_axil_arb_rready,
    output wire        s_axil_arb_rvalid,
    output wire [31:0] s_axil_arb_rdata,
    output wire [1:0]  s_axil_arb_rresp,

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

        .s_axil_awvalid         (s_axil_arb_awvalid),
        .s_axil_awready         (s_axil_arb_awready),
        .s_axil_awaddr          (s_axil_arb_awaddr),
        .s_axil_wvalid          (s_axil_arb_wvalid),
        .s_axil_wready          (s_axil_arb_wready),
        .s_axil_wdata           (s_axil_arb_wdata),
        .s_axil_wstrb           (s_axil_arb_wstrb),
        .s_axil_bvalid          (s_axil_arb_bvalid),
        .s_axil_bready          (s_axil_arb_bready),
        .s_axil_bresp           (s_axil_arb_bresp),
        .s_axil_arvalid         (s_axil_arb_arvalid),
        .s_axil_arready         (s_axil_arb_arready),
        .s_axil_araddr          (s_axil_arb_araddr),
        .s_axil_rready          (s_axil_arb_rready),
        .s_axil_rvalid          (s_axil_arb_rvalid),
        .s_axil_rdata           (s_axil_arb_rdata),
        .s_axil_rresp           (s_axil_arb_rresp),

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

        .s_axil_awvalid   (s_axil_des_awvalid),
        .s_axil_awready   (s_axil_des_awready),
        .s_axil_awaddr    (s_axil_des_awaddr),
        .s_axil_wvalid    (s_axil_des_wvalid),
        .s_axil_wready    (s_axil_des_wready),
        .s_axil_wdata     (s_axil_des_wdata),
        .s_axil_wstrb     (s_axil_des_wstrb),
        .s_axil_bvalid    (s_axil_des_bvalid),
        .s_axil_bready    (s_axil_des_bready),
        .s_axil_bresp     (s_axil_des_bresp),
        .s_axil_arvalid   (s_axil_des_arvalid),
        .s_axil_arready   (s_axil_des_arready),
        .s_axil_araddr    (s_axil_des_araddr),
        .s_axil_rvalid    (s_axil_des_rvalid),
        .s_axil_rready    (s_axil_des_rready),
        .s_axil_rdata     (s_axil_des_rdata),
        .s_axil_rresp     (s_axil_des_rresp),

        .ready_key_o      (ready_key_o)
    );

    assign m_axis_tvalid = des_m_tvalid;
    assign m_axis_tdata  = des_m_tdata;
    assign m_axis_tlast  = des_m_tlast;

endmodule
