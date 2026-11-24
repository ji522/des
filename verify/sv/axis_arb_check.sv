`timescale 1ns / 1ps
// ============================================================================
// axis_arb_check.sv —— 2 通道 AXIS 仲裁器的 SVA + 功能覆盖率（bind 到 axis_arb2）
//
// 断言：
//  A1/A2  FIFO 满时不得给出 tready（写使能不会越过 full）
//  A3/A4  空时不得读（rd 只在非空时有效）
//  A5/A6  不出现 FIFO overflow/underflow 脉冲
//  A7     输出反压期间 valid/data/tlast/tuser 保持
//  A8     enable=0 时无输出、无输入 ready
//  A9     lock 时输出通道必须等于 cur_ch
//  A10    FIFO count 不得越界
//  A11    包内不得切换通道（tuser 在 TLAST 前保持不变）
//
// 覆盖率：
//  ch、last、包长（1/2-3/4-7/8+）、stall、arb_mode、FIFO 占用（空/低/中/高/满）
//  以及 ch x last、ch x len 两个 cross。
// ============================================================================
module axis_arb_check #(
    parameter integer DATA_W = 64,
    parameter integer FIFO_AW = 4
)(
    input wire              clk,
    input wire              rst_n,
    input wire              enable,
    input wire              arb_mode,

    input wire              s0_tvalid,
    input wire              s0_tready,
    input wire              s1_tvalid,
    input wire              s1_tready,

    input wire              m_tvalid,
    input wire              m_tready,
    input wire              m_tlast,
    input wire              m_tuser,
    input wire [DATA_W-1:0] m_tdata,

    input wire              f0_full,
    input wire              f1_full,
    input wire              f0_empty,
    input wire              f1_empty,
    input wire [FIFO_AW:0]  f0_count,
    input wire [FIFO_AW:0]  f1_count,
    input wire              rd0,
    input wire              rd1,
    input wire              f0_ovf,
    input wire              f1_ovf,
    input wire              f0_unf,
    input wire              f1_unf,
    input wire              lock,
    input wire              cur_ch
);

    localparam integer DEPTH = (1 << FIFO_AW);

    // ------------------------------------------------------------------
    // SVA
    // ------------------------------------------------------------------
    a_s0_no_write_full: assert property (@(posedge clk) disable iff (!rst_n)
        s0_tready |-> !f0_full)
        else $error("[ARB A1] s0_tready=1 while fifo0 full");

    a_s1_no_write_full: assert property (@(posedge clk) disable iff (!rst_n)
        s1_tready |-> !f1_full)
        else $error("[ARB A2] s1_tready=1 while fifo1 full");

    a_rd0_not_empty: assert property (@(posedge clk) disable iff (!rst_n)
        rd0 |-> !f0_empty)
        else $error("[ARB A3] fifo0 read while empty");

    a_rd1_not_empty: assert property (@(posedge clk) disable iff (!rst_n)
        rd1 |-> !f1_empty)
        else $error("[ARB A4] fifo1 read while empty");

    a_no_overflow: assert property (@(posedge clk) disable iff (!rst_n)
        !f0_ovf && !f1_ovf)
        else $error("[ARB A5] FIFO overflow pulse");

    a_no_underflow: assert property (@(posedge clk) disable iff (!rst_n)
        !f0_unf && !f1_unf)
        else $error("[ARB A6] FIFO underflow pulse");

    a_out_stable: assert property (@(posedge clk) disable iff (!rst_n)
        (m_tvalid && !m_tready) |=> (m_tvalid && $stable(m_tdata) &&
                                     $stable(m_tlast) && $stable(m_tuser)))
        else $error("[ARB A7] output changed while back-pressured");

    a_disabled: assert property (@(posedge clk) disable iff (!rst_n)
        !enable |-> (!m_tvalid && !s0_tready && !s1_tready))
        else $error("[ARB A8] output/ready active while disabled");

    a_lock_ch: assert property (@(posedge clk) disable iff (!rst_n)
        (lock && m_tvalid) |-> (m_tuser == cur_ch))
        else $error("[ARB A9] lock channel mismatch");

    a_count_bounds: assert property (@(posedge clk) disable iff (!rst_n)
        (f0_count <= DEPTH) && (f1_count <= DEPTH))
        else $error("[ARB A10] FIFO count out of range");

    // 包内通道稳定：用状态机辅助
    reg     in_pkt;
    reg     pkt_ch;
    integer cur_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_pkt  <= 1'b0;
            pkt_ch  <= 1'b0;
            cur_len <= 0;
        end else if (m_tvalid && m_tready) begin
            if (!in_pkt) begin
                pkt_ch <= m_tuser;
                if (m_tlast) begin
                    in_pkt  <= 1'b0;
                    cur_len <= 0;
                end else begin
                    in_pkt  <= 1'b1;
                    cur_len <= 1;
                end
            end else begin
                cur_len <= cur_len + 1;
                if (m_tlast) begin
                    in_pkt  <= 1'b0;
                    cur_len <= 0;
                end
            end
        end
    end

    a_no_ch_switch: assert property (@(posedge clk) disable iff (!rst_n)
        (m_tvalid && m_tready && in_pkt) |-> (m_tuser == pkt_ch))
        else $error("[ARB A11] channel switched inside a packet");

    // ------------------------------------------------------------------
    // functional coverage
    // ------------------------------------------------------------------
    covergroup cg @(posedge clk);
        cp_ch: coverpoint m_tuser iff (m_tvalid && m_tready) {
            bins ch0 = {1'b0};
            bins ch1 = {1'b1};
        }

        cp_last: coverpoint m_tlast iff (m_tvalid && m_tready) {
            bins not_last = {1'b0};
            bins last     = {1'b1};
        }

        cp_len: coverpoint (cur_len + 1) iff (m_tvalid && m_tready && m_tlast) {
            bins len1   = {1};
            bins len2_3 = {[2:3]};
            bins len4_7 = {[4:7]};
            bins len8p  = {[8:64]};
        }

        cp_stall: coverpoint (m_tvalid && !m_tready) {
            bins no_stall = {1'b0};
            bins stall    = {1'b1};
        }

        cp_mode: coverpoint arb_mode {
            bins rr    = {1'b0};
            bins fixed = {1'b1};
        }

        cp_occ0: coverpoint f0_count {
            bins empty_b = {0};
            bins low_b   = {[1:3]};
            bins mid_b   = {[4:7]};
            bins high_b  = {[8:DEPTH-1]};
            bins full_b  = {DEPTH};
        }

        cp_occ1: coverpoint f1_count {
            bins empty_b = {0};
            bins low_b   = {[1:3]};
            bins mid_b   = {[4:7]};
            bins high_b  = {[8:DEPTH-1]};
            bins full_b  = {DEPTH};
        }

        x_ch_last: cross cp_ch, cp_last;
        x_ch_len:  cross cp_ch, cp_len;
    endgroup : cg

    cg cg_inst = new;

    final begin
        $display("AXIS ARB COV : %.2f%%", cg_inst.get_coverage());
        $display("AXIS ARB COV detail : ch=%.1f last=%.1f len=%.1f stall=%.1f mode=%.1f occ0=%.1f occ1=%.1f x_ch_last=%.1f x_ch_len=%.1f",
                 cg_inst.cp_ch.get_coverage(),
                 cg_inst.cp_last.get_coverage(),
                 cg_inst.cp_len.get_coverage(),
                 cg_inst.cp_stall.get_coverage(),
                 cg_inst.cp_mode.get_coverage(),
                 cg_inst.cp_occ0.get_coverage(),
                 cg_inst.cp_occ1.get_coverage(),
                 cg_inst.x_ch_last.get_coverage(),
                 cg_inst.x_ch_len.get_coverage());
    end

endmodule

// ----------------------------------------------------------------------------
// bind 到 axis_arb2，显式接内部信号（满/空/计数/读使能/溢出脉冲/lock）
// ----------------------------------------------------------------------------
bind axis_arb2 axis_arb_check #(.DATA_W(DATA_W), .FIFO_AW(FIFO_AW)) u_check (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable),
    .arb_mode   (arb_mode),

    .s0_tvalid  (s0_axis_tvalid),
    .s0_tready  (s0_axis_tready),
    .s1_tvalid  (s1_axis_tvalid),
    .s1_tready  (s1_axis_tready),

    .m_tvalid   (m_axis_tvalid),
    .m_tready   (m_axis_tready),
    .m_tlast    (m_axis_tlast),
    .m_tuser    (m_axis_tuser),
    .m_tdata    (m_axis_tdata),

    .f0_full    (f0_full),
    .f1_full    (f1_full),
    .f0_empty   (f0_empty),
    .f1_empty   (f1_empty),
    .f0_count   (f0_count),
    .f1_count   (f1_count),
    .rd0        (rd0),
    .rd1        (rd1),
    .f0_ovf     (f0_ovf),
    .f1_ovf     (f1_ovf),
    .f0_unf     (f0_unf),
    .f1_unf     (f1_unf),
    .lock       (lock),
    .cur_ch     (cur_ch)
);
