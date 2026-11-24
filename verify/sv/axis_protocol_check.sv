`timescale 1ns / 1ps
// ============================================================================
// axis_protocol_check.sv —— AXI4-Stream 封装层的协议断言
//
// 为什么单独放这里：verify/sv/des_if.sv 的 A1~A5 绑在 des_pipeline_fb 的
// 核心 valid/ready 口上，看不到封装的 TDATA/TLAST。而 TLAST 边带对齐正是
// 封装新增的唯一功能，必须有断言保护，不能只靠 scoreboard 逐拍比对。
//
// 用 bind 挂载，不改 des_axis_wrap.v 一行：run_axis.ps1 以 -sv 编译本文件
// 即可生效。
//
// 每个断言失败时累加自己的命中计数（XSim 2018.3 不支持 assert.triggered），
// 供 tb_axis_sva_neg 负向测试读取，防止"编译通过但空过"。
// ============================================================================
module axis_protocol_check (
    input wire        clk,
    input wire        rst_n,
    input wire        s_axis_tvalid,
    input wire        s_axis_tready,
    input wire [63:0] s_axis_tdata,
    input wire        s_axis_tlast,
    input wire        m_axis_tvalid,
    input wire        m_axis_tready,
    input wire [63:0] m_axis_tdata,
    input wire        m_axis_tlast
);

    integer a6_hits  = 0;
    integer a7_hits  = 0;
    integer a8_hits  = 0;
    integer a9_hits  = 0;
    integer a10_hits = 0;
    integer a11_hits = 0;

    // 断言覆盖率：前件真正发生的拍数。
    // XSim 2018.3 不支持 cover property（xelab 报 XSIM 43-4127 并忽略），
    // 故用 always 块手工计数，见本文件末尾。
    integer a6_cov   = 0;
    integer a7_cov   = 0;
    integer a8_cov   = 0;
    integer a9_cov   = 0;
    integer a10_cov  = 0;
    integer a11_cov  = 0;

    // A6：输出反压期间 TLAST 必须保持不变
    //     边带 FIFO 若与数据拍失去同步，最先坏的就是这条
    property p_m_tlast_stable;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && !m_axis_tready) |=> (m_axis_tvalid && $stable(m_axis_tlast));
    endproperty
    a_m_tlast_stable : assert property (p_m_tlast_stable)
        else begin a6_hits = a6_hits + 1;
                   $error("[SVA A6] m_axis_tlast 在 stall 期间发生变化（边带 FIFO 与数据拍失步）"); end

    // A7：输出反压期间 TDATA 必须保持不变
    property p_m_tdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && !m_axis_tready) |=> $stable(m_axis_tdata);
    endproperty
    a_m_tdata_stable : assert property (p_m_tdata_stable)
        else begin a7_hits = a7_hits + 1;
                   $error("[SVA A7] m_axis_tdata 在 stall 期间发生变化"); end

    // A8：握手成功拍 TLAST 不得为 X/Z
    //     last_count==0 时 tlast 被强制为 0，若 FIFO 读侧未初始化会漏出 X
    property p_m_tlast_no_x;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && m_axis_tready) |-> !$isunknown(m_axis_tlast);
    endproperty
    a_m_tlast_no_x : assert property (p_m_tlast_no_x)
        else begin a8_hits = a8_hits + 1;
                   $error("[SVA A8] 握手成功拍 m_axis_tlast 含 X/Z"); end

    // A9：输出 valid 在握手前不得撤销
    property p_m_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && !m_axis_tready) |=> m_axis_tvalid;
    endproperty
    a_m_valid_stable : assert property (p_m_valid_stable)
        else begin a9_hits = a9_hits + 1;
                   $error("[SVA A9] m_axis_tvalid 在未握手时被撤销"); end

    // A10：输入侧——未被接受时上游必须保持 valid 与数据
    property p_s_hold;
        @(posedge clk) disable iff (!rst_n)
        (s_axis_tvalid && !s_axis_tready) |=> (s_axis_tvalid && $stable(s_axis_tdata) && $stable(s_axis_tlast));
    endproperty
    a_s_hold : assert property (p_s_hold)
        else begin a10_hits = a10_hits + 1;
                   $error("[SVA A10] 上游在未握手时撤销 valid 或改变 tdata/tlast"); end

    // A11：控制信号不得出现 X/Z
    property p_ctrl_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({s_axis_tready, m_axis_tvalid, m_axis_tlast});
    endproperty
    a_ctrl_known : assert property (p_ctrl_known)
        else begin a11_hits = a11_hits + 1;
                   $error("[SVA A11] 控制信号 s_axis_tready/m_axis_tvalid/m_axis_tlast 出现 X/Z"); end

    // ------------------------------------------------------------------
    // 断言覆盖率：前件命中计数
    //   A6/A7/A9 前件：m_axis_tvalid && !m_axis_tready（输出反压）
    //   A8      前件：m_axis_tvalid && m_axis_tready （输出握手）
    //   A10     前件：s_axis_tvalid && !s_axis_tready（输入反压）
    //   A11     无前件（组合检查），统计断言被使能检查的非复位拍数
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (m_axis_tvalid && !m_axis_tready) begin
                a6_cov = a6_cov + 1;
                a7_cov = a7_cov + 1;
                a9_cov = a9_cov + 1;
            end
            if (m_axis_tvalid && m_axis_tready) a8_cov = a8_cov + 1;
            if (s_axis_tvalid && !s_axis_tready) a10_cov = a10_cov + 1;
            a11_cov = a11_cov + 1;
        end
    end

    final begin
        $display("[SVA COV] A6  fail=%0d fire=%0d", a6_hits,  a6_cov);
        $display("[SVA COV] A7  fail=%0d fire=%0d", a7_hits,  a7_cov);
        $display("[SVA COV] A8  fail=%0d fire=%0d", a8_hits,  a8_cov);
        $display("[SVA COV] A9  fail=%0d fire=%0d", a9_hits,  a9_cov);
        $display("[SVA COV] A10 fail=%0d fire=%0d", a10_hits, a10_cov);
        $display("[SVA COV] A11 fail=%0d fire=%0d", a11_hits, a11_cov);
    end

endmodule

// ---------------------------------------------------------------------------
// 挂载：不改 RTL，直接绑到 des_axis_wrap
// ---------------------------------------------------------------------------
bind des_axis_wrap axis_protocol_check u_axis_check (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tlast  (s_axis_tlast),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tlast  (m_axis_tlast)
);
