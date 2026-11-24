`timescale 1ns / 1ps
// ============================================================================
// axis_arb2.v —— 2 通道 AXI4-Stream 仲裁/交换器
//
// 结构：
//   s0_axis ──> [sync_fifo 16x65] ──┐
//                                   ├──> 包级 round-robin 仲裁 ──> m_axis
//   s1_axis ──> [sync_fifo 16x65] ──┘
//
// 关键行为：
//  - 包级锁定：一旦某通道开始输出，就保持该通道直到 TLAST，绝不在包内
//    切换到另一通道（避免两路数据交错）。
//  - 反压：输出 m_axis_tready=0 时 FIFO 继续攒数；FIFO 满后对应
//    s_axis_tready 拉低，向上游反压，不丢数。
//  - 轮询：默认 round-robin，一个包结束后把优先级交给另一通道；
//    arb_mode=1 时固定优先 ch0（饥饿场景可演示）。
//  - 性能计数：每通道 beats/packets in/out、stall（输出反压）、blocked
//    （输入被 FIFO 满挡住），可经 AXI4-Lite 读取/清零。
//
// 边界：FIFO 满时同拍有读允许写；m_axis_tuser 输出当前通道号，便于 TB
//       和上层观测；本模块不含跨时钟域，两个输入与输出同属 clk 域。
// ============================================================================
module axis_arb2 #(
    parameter integer DATA_W = 64,
    parameter integer FIFO_AW = 4,       // 深度 = 2^FIFO_AW
    parameter integer CNT_W = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- channel 0 AXI4-Stream slave ----
    input  wire                 s0_axis_tvalid,
    output wire                 s0_axis_tready,
    input  wire [DATA_W-1:0]    s0_axis_tdata,
    input  wire                 s0_axis_tlast,

    // ---- channel 1 AXI4-Stream slave ----
    input  wire                 s1_axis_tvalid,
    output wire                 s1_axis_tready,
    input  wire [DATA_W-1:0]    s1_axis_tdata,
    input  wire                 s1_axis_tlast,

    // ---- merged AXI4-Stream master ----
    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,
    output wire [DATA_W-1:0]    m_axis_tdata,
    output wire                 m_axis_tlast,
    output wire                 m_axis_tuser,   // 0/1 = 源通道号

    // ---- configuration ----
    input  wire                 enable,
    input  wire                 arb_mode,       // 0=round-robin, 1=fixed ch0 priority
    input  wire [7:0]           almost_full_thresh0,
    input  wire [7:0]           almost_full_thresh1,
    input  wire                 clear_counters,

    // ---- status ----
    output wire [FIFO_AW:0]     fifo0_count_o,
    output wire [FIFO_AW:0]     fifo1_count_o,
    output wire                 fifo0_full_o,
    output wire                 fifo1_full_o,
    output wire                 fifo0_almost_full_o,
    output wire                 fifo1_almost_full_o,
    output wire                 ch0_done_o,       // 单拍：ch0 一个包输出完
    output wire                 ch1_done_o,       // 单拍：ch1 一个包输出完
    output wire                 cur_ch_o,
    output wire                 lock_o,
    output wire                 busy_o,

    // ---- performance counters ----
    output reg  [CNT_W-1:0]     ch0_beats_in_o,
    output reg  [CNT_W-1:0]     ch0_packets_in_o,
    output reg  [CNT_W-1:0]     ch0_beats_out_o,
    output reg  [CNT_W-1:0]     ch0_packets_out_o,
    output reg  [CNT_W-1:0]     ch0_stall_o,
    output reg  [CNT_W-1:0]     ch0_blocked_o,

    output reg  [CNT_W-1:0]     ch1_beats_in_o,
    output reg  [CNT_W-1:0]     ch1_packets_in_o,
    output reg  [CNT_W-1:0]     ch1_beats_out_o,
    output reg  [CNT_W-1:0]     ch1_packets_out_o,
    output reg  [CNT_W-1:0]     ch1_stall_o,
    output reg  [CNT_W-1:0]     ch1_blocked_o
);

    localparam integer DEPTH = (1 << FIFO_AW);

    // ------------------------------------------------------------------
    // per-channel FIFO: 存 {tlast, tdata}
    // ------------------------------------------------------------------
    wire [DATA_W:0] f0_din = {s0_axis_tlast, s0_axis_tdata};
    wire [DATA_W:0] f1_din = {s1_axis_tlast, s1_axis_tdata};
    wire [DATA_W:0] f0_dout, f1_dout;

    wire            f0_full, f1_full;
    wire            f0_empty, f1_empty;
    wire            f0_af, f1_af;
    wire            f0_ae, f1_ae;
    wire [FIFO_AW:0] f0_count, f1_count;
    wire            f0_ovf, f0_unf, f1_ovf, f1_unf;

    wire [FIFO_AW:0] ae_th = 1;   // almost_empty = count <= 1

    // 阈值钳位到 DEPTH，避免配置成大于深度的值
    wire [FIFO_AW:0] af0_th = (almost_full_thresh0 > DEPTH) ? DEPTH : almost_full_thresh0[FIFO_AW:0];
    wire [FIFO_AW:0] af1_th = (almost_full_thresh1 > DEPTH) ? DEPTH : almost_full_thresh1[FIFO_AW:0];

    wire wr0 = s0_axis_tvalid && s0_axis_tready;
    wire wr1 = s1_axis_tvalid && s1_axis_tready;
    wire rd0, rd1;

    assign s0_axis_tready = enable && !f0_full;
    assign s1_axis_tready = enable && !f1_full;

    sync_fifo #(.DATA_W(DATA_W+1), .ADDR_W(FIFO_AW)) u_fifo0 (
        .clk                (clk),
        .rst_n              (rst_n),
        .wr_en              (wr0),
        .din                (f0_din),
        .full               (f0_full),
        .almost_full        (f0_af),
        .rd_en              (rd0),
        .dout               (f0_dout),
        .empty              (f0_empty),
        .almost_empty       (f0_ae),
        .count              (f0_count),
        .overflow_pulse     (f0_ovf),
        .underflow_pulse    (f0_unf),
        .almost_full_thresh (af0_th),
        .almost_empty_thresh(ae_th)
    );

    sync_fifo #(.DATA_W(DATA_W+1), .ADDR_W(FIFO_AW)) u_fifo1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .wr_en              (wr1),
        .din                (f1_din),
        .full               (f1_full),
        .almost_full        (f1_af),
        .rd_en              (rd1),
        .dout               (f1_dout),
        .empty              (f1_empty),
        .almost_empty       (f1_ae),
        .count              (f1_count),
        .overflow_pulse     (f1_ovf),
        .underflow_pulse    (f1_unf),
        .almost_full_thresh (af1_th),
        .almost_empty_thresh(ae_th)
    );

    // ------------------------------------------------------------------
    // 包级 round-robin 仲裁
    // ------------------------------------------------------------------
    reg  cur_ch;
    reg  lock;
    reg  rr_next;

    wire f0_avail = !f0_empty;
    wire f1_avail = !f1_empty;

    reg sel_ch;
    always @(*) begin
        if (lock)
            sel_ch = cur_ch;
        else if (arb_mode)
            sel_ch = f0_avail ? 1'b0 : 1'b1;          // 固定优先 ch0
        else if (f0_avail && f1_avail)
            sel_ch = rr_next;
        else if (f0_avail)
            sel_ch = 1'b0;
        else
            sel_ch = 1'b1;
    end

    wire sel_avail = sel_ch ? f1_avail : f0_avail;
    assign m_axis_tvalid = enable && sel_avail;
    assign m_axis_tdata  = sel_ch ? f1_dout[DATA_W-1:0] : f0_dout[DATA_W-1:0];
    assign m_axis_tlast  = sel_ch ? f1_dout[DATA_W]     : f0_dout[DATA_W];
    assign m_axis_tuser  = sel_ch;

    wire pop = m_axis_tvalid && m_axis_tready;
    assign rd0 = pop && !sel_ch;
    assign rd1 = pop &&  sel_ch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lock    <= 1'b0;
            cur_ch  <= 1'b0;
            rr_next <= 1'b0;
        end else begin
            if (!lock && m_axis_tvalid) begin
                if (pop && m_axis_tlast) begin
                    // 单拍包：不进入 lock，直接切换优先级
                    rr_next <= ~sel_ch;
                end else begin
                    lock   <= 1'b1;
                    cur_ch <= sel_ch;
                end
            end else if (lock && pop && m_axis_tlast) begin
                lock    <= 1'b0;
                rr_next <= ~cur_ch;
            end
        end
    end

    // ------------------------------------------------------------------
    // 状态 / 事件
    // ------------------------------------------------------------------
    assign fifo0_count_o       = f0_count;
    assign fifo1_count_o       = f1_count;
    assign fifo0_full_o        = f0_full;
    assign fifo1_full_o        = f1_full;
    assign fifo0_almost_full_o = f0_af;
    assign fifo1_almost_full_o = f1_af;
    assign ch0_done_o          = pop && !sel_ch && m_axis_tlast;
    assign ch1_done_o          = pop &&  sel_ch && m_axis_tlast;
    assign cur_ch_o            = cur_ch;
    assign lock_o              = lock;
    assign busy_o              = m_axis_tvalid || f0_avail || f1_avail || lock;

    // ------------------------------------------------------------------
    // 性能计数
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch0_beats_in_o    <= 0; ch0_packets_in_o  <= 0;
            ch0_beats_out_o   <= 0; ch0_packets_out_o <= 0;
            ch0_stall_o       <= 0; ch0_blocked_o     <= 0;
            ch1_beats_in_o    <= 0; ch1_packets_in_o  <= 0;
            ch1_beats_out_o   <= 0; ch1_packets_out_o <= 0;
            ch1_stall_o       <= 0; ch1_blocked_o     <= 0;
        end else if (clear_counters) begin
            ch0_beats_in_o    <= 0; ch0_packets_in_o  <= 0;
            ch0_beats_out_o   <= 0; ch0_packets_out_o <= 0;
            ch0_stall_o       <= 0; ch0_blocked_o     <= 0;
            ch1_beats_in_o    <= 0; ch1_packets_in_o  <= 0;
            ch1_beats_out_o   <= 0; ch1_packets_out_o <= 0;
            ch1_stall_o       <= 0; ch1_blocked_o     <= 0;
        end else begin
            if (wr0) begin
                ch0_beats_in_o <= ch0_beats_in_o + 1'b1;
                if (s0_axis_tlast) ch0_packets_in_o <= ch0_packets_in_o + 1'b1;
            end
            if (s0_axis_tvalid && !s0_axis_tready)
                ch0_blocked_o <= ch0_blocked_o + 1'b1;

            if (pop && !sel_ch) begin
                ch0_beats_out_o <= ch0_beats_out_o + 1'b1;
                if (m_axis_tlast) ch0_packets_out_o <= ch0_packets_out_o + 1'b1;
            end
            if (m_axis_tvalid && !m_axis_tready && !sel_ch)
                ch0_stall_o <= ch0_stall_o + 1'b1;

            if (wr1) begin
                ch1_beats_in_o <= ch1_beats_in_o + 1'b1;
                if (s1_axis_tlast) ch1_packets_in_o <= ch1_packets_in_o + 1'b1;
            end
            if (s1_axis_tvalid && !s1_axis_tready)
                ch1_blocked_o <= ch1_blocked_o + 1'b1;

            if (pop && sel_ch) begin
                ch1_beats_out_o <= ch1_beats_out_o + 1'b1;
                if (m_axis_tlast) ch1_packets_out_o <= ch1_packets_out_o + 1'b1;
            end
            if (m_axis_tvalid && !m_axis_tready && sel_ch)
                ch1_stall_o <= ch1_stall_o + 1'b1;
        end
    end

endmodule
