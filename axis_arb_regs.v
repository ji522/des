`timescale 1ns / 1ps
// ============================================================================
// axis_arb_regs.v —— 2 通道 AXIS 仲裁器的 AXI4-Lite 控制/状态寄存器
//
// 地址映射（字对齐，addr[7:2] 解码；每个寄存器 4 字节）：
//   0x00 CTRL          RW  [0] ENABLE 仲裁器使能
//                          [1] ARB_MODE 0=round-robin 1=固定优先 ch0
//                          [2] CLR_COUNTERS 写 1 清零全部性能计数（自清）
//   0x04 IRQ_STATUS    W1C [0] ch0 almost_full 事件
//                          [1] ch1 almost_full 事件
//                          [2] ch0 full 事件
//                          [3] ch1 full 事件
//                          [4] ch0 packet done
//                          [5] ch1 packet done
//   0x08 IRQ_MASK      RW  同上，1=使能中断
//   0x0C THRESH        RW  [7:0] ch0 almost_full 阈值
//                          [15:8] ch1 almost_full 阈值
//   0x10 CH0_BEATS_IN      RO
//   0x14 CH0_PACKETS_IN    RO
//   0x18 CH0_BEATS_OUT     RO
//   0x1C CH0_PACKETS_OUT   RO
//   0x20 CH0_STALL         RO  输出反压拍数
//   0x24 CH0_BLOCKED       RO  输入被 FIFO 满挡住的拍数
//   0x28 CH1_BEATS_IN      RO
//   0x2C CH1_PACKETS_IN    RO
//   0x30 CH1_BEATS_OUT     RO
//   0x34 CH1_PACKETS_OUT   RO
//   0x38 CH1_STALL         RO
//   0x3C CH1_BLOCKED       RO
//   0x40 STATUS        RO  [FIFO_AW:0] ch0 count
//                          [2*FIFO_AW+1:FIFO_AW+1] ch1 count
//                          [2*FIFO_AW+2] cur_ch
//                          [2*FIFO_AW+3] lock
//                          [2*FIFO_AW+4] busy
//   0x44 VERSION       RO  0x0001_0000
//
// 设计取舍：单拍、无 burst/outstanding；AW/W 独立到达；WSTRB 逐字节；
// 中断状态为 sticky，W1C 清除；计数器由 CTRL.CLR_COUNTERS 统一清零。
// ============================================================================
module axis_arb_regs #(
    parameter integer FIFO_AW = 4
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- AXI4-Lite slave ----
    input  wire                 s_axil_awvalid,
    output wire                 s_axil_awready,
    input  wire [31:0]          s_axil_awaddr,
    input  wire                 s_axil_wvalid,
    output wire                 s_axil_wready,
    input  wire [31:0]          s_axil_wdata,
    input  wire [3:0]           s_axil_wstrb,
    output wire                 s_axil_bvalid,
    input  wire                 s_axil_bready,
    output wire [1:0]           s_axil_bresp,
    input  wire                 s_axil_arvalid,
    output wire                 s_axil_arready,
    input  wire [31:0]          s_axil_araddr,
    input  wire                 s_axil_rready,
    output wire                 s_axil_rvalid,
    output wire [31:0]          s_axil_rdata,
    output wire [1:0]           s_axil_rresp,

    // ---- configuration to arbiter ----
    output reg                  enable_o,
    output reg                  arb_mode_o,
    output reg  [7:0]           af_thresh0_o,
    output reg  [7:0]           af_thresh1_o,
    output reg                  clear_counters_o,

    // ---- status from arbiter ----
    input  wire [FIFO_AW:0]     fifo0_count_i,
    input  wire [FIFO_AW:0]     fifo1_count_i,
    input  wire                 fifo0_full_i,
    input  wire                 fifo1_full_i,
    input  wire                 fifo0_almost_full_i,
    input  wire                 fifo1_almost_full_i,
    input  wire                 ch0_done_i,
    input  wire                 ch1_done_i,
    input  wire                 cur_ch_i,
    input  wire                 lock_i,
    input  wire                 busy_i,

    // ---- counters from arbiter ----
    input  wire [31:0]          ch0_beats_in_i,
    input  wire [31:0]          ch0_packets_in_i,
    input  wire [31:0]          ch0_beats_out_i,
    input  wire [31:0]          ch0_packets_out_i,
    input  wire [31:0]          ch0_stall_i,
    input  wire [31:0]          ch0_blocked_i,
    input  wire [31:0]          ch1_beats_in_i,
    input  wire [31:0]          ch1_packets_in_i,
    input  wire [31:0]          ch1_beats_out_i,
    input  wire [31:0]          ch1_packets_out_i,
    input  wire [31:0]          ch1_stall_i,
    input  wire [31:0]          ch1_blocked_i,

    output wire                 irq_o
);

    localparam [5:0] A_CTRL          = 6'h00;
    localparam [5:0] A_IRQ_STATUS    = 6'h01;
    localparam [5:0] A_IRQ_MASK      = 6'h02;
    localparam [5:0] A_THRESH        = 6'h03;
    localparam [5:0] A_CH0_BEATS_IN  = 6'h04;
    localparam [5:0] A_CH0_PKTS_IN   = 6'h05;
    localparam [5:0] A_CH0_BEATS_OUT = 6'h06;
    localparam [5:0] A_CH0_PKTS_OUT  = 6'h07;
    localparam [5:0] A_CH0_STALL     = 6'h08;
    localparam [5:0] A_CH0_BLOCKED   = 6'h09;
    localparam [5:0] A_CH1_BEATS_IN  = 6'h0A;
    localparam [5:0] A_CH1_PKTS_IN   = 6'h0B;
    localparam [5:0] A_CH1_BEATS_OUT = 6'h0C;
    localparam [5:0] A_CH1_PKTS_OUT  = 6'h0D;
    localparam [5:0] A_CH1_STALL     = 6'h0E;
    localparam [5:0] A_CH1_BLOCKED   = 6'h0F;
    localparam [5:0] A_STATUS        = 6'h10;
    localparam [5:0] A_VERSION       = 6'h11;

    // ------------------------------------------------------------------
    // write channel (AW/W independent)
    // ------------------------------------------------------------------
    reg        aw_pend, w_pend;
    reg [5:0]  aw_addr_lat;
    reg [31:0] w_data_lat;
    reg [3:0]  w_strb_lat;
    reg        bvalid_r;

    assign s_axil_awready = !aw_pend;
    assign s_axil_wready  = !w_pend;
    assign s_axil_bvalid  = bvalid_r;
    assign s_axil_bresp   = 2'b00;

    wire aw_fire = s_axil_awvalid && s_axil_awready;
    wire w_fire  = s_axil_wvalid  && s_axil_wready;
    wire do_write = (aw_pend || aw_fire) && (w_pend || w_fire);

    wire [5:0]  wr_addr = aw_pend ? aw_addr_lat : s_axil_awaddr[7:2];
    wire [31:0] wr_data = w_pend  ? w_data_lat  : s_axil_wdata;
    wire [3:0]  wr_strb = w_pend  ? w_strb_lat  : s_axil_wstrb;

    // ------------------------------------------------------------------
    // read channel
    // ------------------------------------------------------------------
    reg        rvalid_r;
    reg [5:0]  ar_addr_lat;
    reg [31:0] rdata_r;      // 读数据打一拍：切断 rdata mux 到输出端口的组合路径

    assign s_axil_arready = !rvalid_r;
    assign s_axil_rvalid  = rvalid_r;
    assign s_axil_rresp   = 2'b00;

    wire ar_fire = s_axil_arvalid && s_axil_arready;
    wire [5:0] rd_addr = rvalid_r ? ar_addr_lat : s_axil_araddr[7:2];

    // ------------------------------------------------------------------
    // config / interrupt registers
    // ------------------------------------------------------------------
    reg [7:0] irq_mask_r;
    reg [7:0] irq_status_r;

    // events (rising edge for level signals, pulse for done)
    reg af0_d, af1_d, full0_d, full1_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            af0_d   <= 1'b0;
            af1_d   <= 1'b0;
            full0_d <= 1'b0;
            full1_d <= 1'b0;
        end else begin
            af0_d   <= fifo0_almost_full_i;
            af1_d   <= fifo1_almost_full_i;
            full0_d <= fifo0_full_i;
            full1_d <= fifo1_full_i;
        end
    end

    wire af0_ev   = fifo0_almost_full_i && !af0_d;
    wire af1_ev   = fifo1_almost_full_i && !af1_d;
    wire full0_ev = fifo0_full_i        && !full0_d;
    wire full1_ev = fifo1_full_i        && !full1_d;
    wire [7:0] set_mask = {2'b00, ch1_done_i, ch0_done_i,
                           full1_ev, full0_ev, af1_ev, af0_ev};

    assign irq_o = |(irq_status_r & irq_mask_r);

    // 写控制/状态：字节使能只影响对应字节
    wire [1:0] ctrl_new = wr_strb[0] ? wr_data[1:0] : {arb_mode_o, enable_o};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_o       <= 1'b0;
            arb_mode_o     <= 1'b0;
            af_thresh0_o   <= 8'd12;
            af_thresh1_o   <= 8'd12;
            irq_mask_r     <= 8'h00;
            irq_status_r   <= 8'h00;
        end else begin
            if (do_write) begin
                case (wr_addr)
                    A_CTRL: begin
                        enable_o   <= ctrl_new[0];
                        arb_mode_o <= ctrl_new[1];
                    end
                    A_IRQ_MASK: begin
                        if (wr_strb[0]) irq_mask_r <= wr_data[7:0];
                    end
                    A_THRESH: begin
                        if (wr_strb[0]) af_thresh0_o <= wr_data[7:0];
                        if (wr_strb[1]) af_thresh1_o <= wr_data[15:8];
                    end
                    default: ;
                endcase
            end

            // IRQ_STATUS: W1C，事件置位优先，避免同拍丢事件
            if (do_write && (wr_addr == A_IRQ_STATUS) && wr_strb[0])
                irq_status_r <= (irq_status_r & ~wr_data[7:0]) | set_mask;
            else
                irq_status_r <= irq_status_r | set_mask;
        end
    end

    // CLR_COUNTERS 自清：写 1 产生单拍脉冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clear_counters_o <= 1'b0;
        else if (do_write && (wr_addr == A_CTRL) && wr_strb[0] && wr_data[2])
            clear_counters_o <= 1'b1;
        else
            clear_counters_o <= 1'b0;
    end

    // ------------------------------------------------------------------
    // read mux
    // ------------------------------------------------------------------
    reg [31:0] rdata_mux;
    always @(*) begin
        case (rd_addr)
            A_CTRL:          rdata_mux = {29'b0, 1'b0, arb_mode_o, enable_o};
            A_IRQ_STATUS:    rdata_mux = {24'b0, irq_status_r};
            A_IRQ_MASK:      rdata_mux = {24'b0, irq_mask_r};
            A_THRESH:        rdata_mux = {16'b0, af_thresh1_o, af_thresh0_o};
            A_CH0_BEATS_IN:  rdata_mux = ch0_beats_in_i;
            A_CH0_PKTS_IN:   rdata_mux = ch0_packets_in_i;
            A_CH0_BEATS_OUT: rdata_mux = ch0_beats_out_i;
            A_CH0_PKTS_OUT:  rdata_mux = ch0_packets_out_i;
            A_CH0_STALL:     rdata_mux = ch0_stall_i;
            A_CH0_BLOCKED:   rdata_mux = ch0_blocked_i;
            A_CH1_BEATS_IN:  rdata_mux = ch1_beats_in_i;
            A_CH1_PKTS_IN:   rdata_mux = ch1_packets_in_i;
            A_CH1_BEATS_OUT: rdata_mux = ch1_beats_out_i;
            A_CH1_PKTS_OUT:  rdata_mux = ch1_packets_out_i;
            A_CH1_STALL:     rdata_mux = ch1_stall_i;
            A_CH1_BLOCKED:   rdata_mux = ch1_blocked_i;
            A_STATUS:        rdata_mux = {19'b0, busy_i, lock_i, cur_ch_i,
                                          fifo1_count_i, fifo0_count_i};
            A_VERSION:       rdata_mux = 32'h0001_0000;
            default:         rdata_mux = 32'hDEAD_BEEF;
        endcase
    end

    assign s_axil_rdata = rdata_r;

    // ------------------------------------------------------------------
    // AXI-Lite handshake state
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pend     <= 1'b0;
            w_pend      <= 1'b0;
            aw_addr_lat <= 6'h0;
            w_data_lat  <= 32'h0;
            w_strb_lat  <= 4'h0;
            bvalid_r    <= 1'b0;
            rvalid_r    <= 1'b0;
            ar_addr_lat <= 6'h0;
        end else begin
            if (aw_fire) begin
                aw_pend     <= 1'b1;
                aw_addr_lat <= s_axil_awaddr[7:2];
            end
            if (w_fire) begin
                w_pend     <= 1'b1;
                w_data_lat <= s_axil_wdata;
                w_strb_lat <= s_axil_wstrb;
            end
            if (do_write) begin
                aw_pend  <= 1'b0;
                w_pend   <= 1'b0;
                bvalid_r <= 1'b1;
            end
            if (bvalid_r && s_axil_bready)
                bvalid_r <= 1'b0;

            if (ar_fire) begin
                ar_addr_lat <= s_axil_araddr[7:2];
                rdata_r     <= rdata_mux;
                rvalid_r    <= 1'b1;
            end else if (rvalid_r && s_axil_rready) begin
                rvalid_r    <= 1'b0;
            end
        end
    end

endmodule
