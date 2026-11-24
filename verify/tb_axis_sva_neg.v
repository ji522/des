`timescale 1ns / 1ps
// ============================================================================
// tb_axis_sva_neg.v —— 负向测试：故意违反 AXI4-Stream 协议，证明断言非空过
//
// 存在的理由：A6~A11 编译通过、正向回归 0 报错，只能说明"没抓到违规"，
// 不能说明"抓得到违规"。本 TB 故意制造一次输入侧 valid 提前撤销（违反 A10），
// 期望 SVA A10 报错；若日志无 A10 报错，说明 bind 没生效。
//
// 判据：日志出现 [SVA A10]，且本 TB 打印 SVA-NEG PASS。
// ============================================================================
module tb_axis_sva_neg;

    reg         clk;
    reg         rst_n;

    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg  [63:0] s_axis_tdata;
    reg         s_axis_tlast;

    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire [63:0] m_axis_tdata;
    wire        m_axis_tlast;

    reg         load_key_i;
    reg  [63:0] key_i;
    wire        ready_key_o;
    reg         encrypt_i;

    integer     sva_hits;

    des_axis_wrap uut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),   .s_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),   .m_axis_tlast(m_axis_tlast),
        .load_key_i(load_key_i), .key_i(key_i),
        .ready_key_o(ready_key_o), .encrypt_i(encrypt_i)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 统计 A10 命中次数：读 bind 进来的 checker 实例内部计数器
    always @(posedge clk) begin
        if (rst_n) sva_hits = uut.u_axis_check.a10_hits;
    end

    initial begin
        rst_n         = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 64'h0;
        s_axis_tlast  = 1'b0;
        load_key_i    = 1'b0;
        key_i         = 64'h0123456789ABCDEF;
        encrypt_i     = 1'b1;
        m_axis_tready = 1'b1;
        sva_hits      = 0;

        #100;
        rst_n = 1'b1;
        #20;

        // ---- 合法载钥 ----
        @(negedge clk);
        load_key_i = 1'b1;
        @(negedge clk);
        load_key_i = 1'b0;
        wait (ready_key_o == 1'b1);
        #40;

        // ---- 违规：拉高 valid，等一拍（不是握手），然后直接撤销 ----
        // 此时若 s_axis_tready 为高，这一拍就握手成功了，撤销是合法的，
        // 所以先把 ready 拉低制造"未握手"状态，再撤 valid。
        m_axis_tready = 1'b0;          // 施加反压，使流水线不前进
        repeat (20) @(negedge clk);

        @(negedge clk);
        s_axis_tvalid = 1'b1;
        s_axis_tdata  = 64'hDEADBEEFCAFEF00D;
        s_axis_tlast  = 1'b0;

        // 等到确实发生"valid 且未 ready"
        while (!(s_axis_tvalid && !s_axis_tready)) @(negedge clk);

        // 违规动作：在未握手时撤销 valid
        @(negedge clk);
        s_axis_tvalid = 1'b0;

        repeat (10) @(negedge clk);

        $display("=================================================");
        $display("  SVA A10 命中次数 : %0d", sva_hits);
        if (sva_hits > 0)
            $display("  SVA-NEG PASS : 断言确实生效，违规被捕获");
        else
            $display("  SVA-NEG FAIL : 断言未触发，bind 可能未生效（空过）");
        $display("=================================================");
        $finish;
    end

    initial begin
        #200000;
        $display("SVA-NEG TIMEOUT");
        $finish;
    end

endmodule
