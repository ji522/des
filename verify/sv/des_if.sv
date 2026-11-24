// ============================================================================
// des_if.sv —— DES 反压流水线的验证接口（含 SVA 协议断言）
//
// 把 DUT 的所有端口收进一个 interface，用 modport 约束方向：
//   DUT : 硬件视角
//   DRV : 驱动端（写激励）
//   MON : 监测端（只读采样）
// 断言挂在 interface 上，任何用例只要例化这个接口就自动获得协议检查。
// ============================================================================
interface des_if (input logic clk);

    logic        rst_n = 1'b0;   // des_driver::reset() 会在 run_phase 开头接管
    logic        load_key_i;
    logic [63:0] key_i;
    logic        ready_key_o;
    logic        encrypt_i;
    logic        valid_i;
    logic [63:0] data_i;
    logic        ready_i;
    logic        valid_o;
    logic        ready_o;
    logic [63:0] data_o;

    // TLAST 仅 SoC 级（AXI4-Stream 封装）使用；纯 pipeline DUT 留空即可
    logic        tlast_i;
    logic        tlast_o;

    modport DUT (
        input  clk, rst_n, load_key_i, key_i, encrypt_i, valid_i, data_i, ready_i,
        output ready_key_o, valid_o, ready_o, data_o
    );

    modport DRV (
        input  clk, ready_key_o, valid_o, ready_o, data_o,
        output rst_n, load_key_i, key_i, encrypt_i, valid_i, data_i, ready_i
    );

    modport MON (
        input  clk, rst_n, load_key_i, encrypt_i, valid_i, ready_o,
        valid_o, ready_i, data_o, key_i
    );

    // ------------------------------------------------------------------
    // SVA 断言覆盖率计数器
    //
    // aN_hits：断言失败次数（失败分支自增）。
    // aN_cov ：前件真正发生过多少拍（断言覆盖率）。
    //
    // 为什么不写 cover property：XSim 2018.3 在 xelab 阶段对 cover property
    // 报 WARNING: [XSIM 43-4127] "System Verilog Assertion" is not supported
    // yet for simulation. The statement will be ignored. 即该覆盖点会被静默
    // 丢弃。这里用 always 块手工计数，XSim / VCS 行为一致。
    // ------------------------------------------------------------------
    integer a1_hits = 0;
    integer a2_hits = 0;
    integer a3_hits = 0;
    integer a4_hits = 0;
    integer a5_hits = 0;

    integer a1_cov = 0;
    integer a2_cov = 0;
    integer a3_cov = 0;
    integer a4_cov = 0;
    integer a5_cov = 0;

    // ------------------------------------------------------------------
    // SVA 协议断言（AXI-Stream 风格 valid/ready 握手）
    // ------------------------------------------------------------------

    // A1：输出侧 —— valid 一旦拉高，在握手成功前不得撤销
    property p_out_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        (valid_o && !ready_i) |=> valid_o;
    endproperty
    a_out_valid_stable : assert property (p_out_valid_stable)
        else begin a1_hits = a1_hits + 1;
                   $error("[SVA A1] valid_o 在未握手时被撤销"); end

    // A2：输出侧 —— 被反压(stall)期间数据必须保持不变
    property p_out_data_stable;
        @(posedge clk) disable iff (!rst_n)
        (valid_o && !ready_i) |=> $stable(data_o);
    endproperty
    a_out_data_stable : assert property (p_out_data_stable)
        else begin a2_hits = a2_hits + 1;
                   $error("[SVA A2] stall 期间 data_o 发生变化（应 hold）"); end

    // A3：输出侧 —— valid 有效时数据不得含 X/Z
    property p_out_no_x;
        @(posedge clk) disable iff (!rst_n)
        valid_o |-> !$isunknown(data_o);
    endproperty
    a_out_no_x : assert property (p_out_no_x)
        else begin a3_hits = a3_hits + 1;
                   $error("[SVA A3] valid_o 有效但 data_o 含 X/Z"); end

    // A4：输入侧 —— 上游在握手成功前必须保持 valid 和数据
    property p_in_stable;
        @(posedge clk) disable iff (!rst_n)
        (valid_i && !ready_o) |=> (valid_i && $stable(data_i));
    endproperty
    a_in_stable : assert property (p_in_stable)
        else begin a4_hits = a4_hits + 1;
                   $error("[SVA A4] 上游在未握手时撤销 valid 或改变 data_i"); end

    // A5：控制信号不得出现 X/Z
    // 注：不要在这里断言 ready_o == ~valid_o | ready_i —— ready_o 是**第一级**的
    //     反压输出，valid_o 是**最后一级**的有效标志，两者不对应同一级；
    //     该等式只在单级内部成立，属于模块内部信号，接口层看不到。
    property p_ctrl_no_x;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({valid_o, ready_o, ready_key_o});
    endproperty
    a_ctrl_no_x : assert property (p_ctrl_no_x)
        else begin a5_hits = a5_hits + 1;
                   $error("[SVA A5] 控制信号 valid_o/ready_o/ready_key_o 出现 X/Z"); end

    // ------------------------------------------------------------------
    // 断言覆盖率：对每条断言的前件是否真的发生过计数
    //   A1/A2 前件：valid_o && !ready_i  （输出反压）
    //   A3   前件：valid_o               （输出有效）
    //   A4   前件：valid_i && !ready_o   （输入反压）
    //   A5   无前件（组合检查），统计"断言被使能检查"的非复位拍数
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (valid_o && !ready_i) begin
                a1_cov = a1_cov + 1;
                a2_cov = a2_cov + 1;
            end
            if (valid_o)             a3_cov = a3_cov + 1;
            if (valid_i && !ready_o) a4_cov = a4_cov + 1;
            a5_cov = a5_cov + 1;
        end
    end

    final begin
        $display("[SVA COV] A1 fail=%0d fire=%0d", a1_hits, a1_cov);
        $display("[SVA COV] A2 fail=%0d fire=%0d", a2_hits, a2_cov);
        $display("[SVA COV] A3 fail=%0d fire=%0d", a3_hits, a3_cov);
        $display("[SVA COV] A4 fail=%0d fire=%0d", a4_hits, a4_cov);
        $display("[SVA COV] A5 fail=%0d fire=%0d", a5_hits, a5_cov);
    end

endinterface
