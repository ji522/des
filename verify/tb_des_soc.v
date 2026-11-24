`timescale 1ns / 1ps
// ============================================================================
// tb_des_soc.v —— des_soc_top 集成 testbench
//
// 验证"控制面 + 数据面同时工作"：
//   S1 复位后经 AXI-Lite 读 STATUS（KEY_READY=0、BUSY=0）
//   S2 经 AXI-Lite 写 KEY_HI 触发换钥 → STATUS.KEY_READY 应升起
//   S3 ENABLE=0 时灌数据，不应有任何输出（门控生效）
//   S4 ENABLE=1 后重发同一批数据，应全部正确输出
//   S5 数据在途时经 AXI-Lite 换钥 → 被拒绝，REKEY_ERR 置位，数据不被打乱
//   S6 排空后再换钥 → 正常接受
//   S7 解密方向：MODE=0，用 dexps 向量校验
//
// 关键点：S5 是这次集成的核心收益——原来只能靠"验证环境强制排空"规避的
// 换钥 hazard，现在是 RTL 自己拒绝，并且有可观测的状态位。
// ============================================================================
`include "params.vh"

module tb_des_soc;

    reg         clk;
    reg         rst_n;

    reg         s_tvalid;
    wire        s_tready;
    reg  [63:0] s_tdata;
    reg         s_tlast;

    wire        m_tvalid;
    reg         m_tready;
    wire [63:0] m_tdata;
    wire        m_tlast;

    reg         awvalid, wvalid, arvalid, bready, rready;
    wire        awready, wready, bvalid, arready, rvalid;
    reg  [31:0] awaddr, wdata, araddr;
    reg  [3:0]  wstrb;
    wire [31:0] rdata;
    wire [1:0]  bresp, rresp;

    reg [63:0] k_arr [0:`N_ENC-1];
    reg [63:0] i_arr [0:`N_ENC-1];
    reg [63:0] e_arr [0:`N_ENC-1];
    reg [63:0] dk_arr[0:`N_DEC-1];
    reg [63:0] di_arr[0:`N_DEC-1];
    reg [63:0] de_arr[0:`N_DEC-1];

    reg [63:0] exp_q [0:127];
    integer    q_head, q_tail;

    integer n_pass, n_err, n_extra;
    integer pushed, popped, stall_cnt;
    integer j;
    integer WD_LIMIT;
    reg [31:0] rd;

    des_soc_top uut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tdata(s_tdata),   .s_axis_tlast(s_tlast),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tdata(m_tdata),   .m_axis_tlast(m_tlast),
        .s_axil_awvalid(awvalid), .s_axil_awready(awready), .s_axil_awaddr(awaddr),
        .s_axil_wvalid(wvalid),   .s_axil_wready(wready),   .s_axil_wdata(wdata),
        .s_axil_wstrb(wstrb),
        .s_axil_bvalid(bvalid),   .s_axil_bready(bready),   .s_axil_bresp(bresp),
        .s_axil_arvalid(arvalid), .s_axil_arready(arready), .s_axil_araddr(araddr),
        .s_axil_rvalid(rvalid),   .s_axil_rready(rready),   .s_axil_rdata(rdata),
        .s_axil_rresp(rresp)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 输出比对
    always @(posedge clk) begin
        if (rst_n) begin
            if (m_tvalid && m_tready) begin
                popped = popped + 1;
                if (q_head < q_tail) begin
                    if ($isunknown(m_tdata)) begin
                        n_err = n_err + 1;
                        $display("[%0t] X/Z OUTPUT #%0d", $time, q_head);
                    end else if (m_tdata !== exp_q[q_head]) begin
                        n_err = n_err + 1;
                        $display("[%0t] MISMATCH #%0d : DUT=%h EXP=%h", $time, q_head, m_tdata, exp_q[q_head]);
                    end else begin
                        n_pass = n_pass + 1;
                    end
                    q_head = q_head + 1;
                end else begin
                    n_extra = n_extra + 1;
                    $display("[%0t] EXTRA OUTPUT : %h", $time, m_tdata);
                end
            end
            if (m_tvalid && !m_tready) stall_cnt = stall_cnt + 1;
            if (s_tvalid && s_tready)  pushed = pushed + 1;
        end
    end

    // ---------------- AXI-Lite 任务 ----------------
    task axil_write(input [31:0] addr, input [31:0] data);
        integer wd;
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            wdata  = data; wstrb   = 4'hF; wvalid = 1'b1;
            bready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(awvalid && awready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            wd = 0;
            while (!(wvalid && wready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            wd = 0;
            while (!bvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axil_read(input [31:0] addr, output [31:0] data);
        integer wd;
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1'b1; rready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(arvalid && arready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            @(negedge clk);
            arvalid = 1'b0;
            wd = 0;
            while (!rvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            data = rdata;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task load_key_via_axil(input [63:0] k);
        begin
            axil_write(32'h00, k[31:0]);
            axil_write(32'h04, k[63:32]);   // 写高字触发加载
        end
    endtask

    task send_beat(input [63:0] d, input last);
        integer wd;
        begin
            @(negedge clk);
            s_tvalid = 1'b1;
            s_tdata  = d;
            s_tlast  = last;
            @(posedge clk);
            wd = 0;
            while (!(s_tvalid && s_tready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            @(negedge clk);
            s_tvalid = 1'b0;
            s_tdata  = 64'h0;
            s_tlast  = 1'b0;
        end
    endtask

    task wait_drain;
        integer wd;
        begin
            wd = 0;
            while (popped < pushed && wd < WD_LIMIT * 20) begin @(posedge clk); wd = wd + 1; end
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        s_tvalid = 1'b0; s_tdata = 64'h0; s_tlast = 1'b0;
        m_tready = 1'b1;
        awvalid = 1'b0; wvalid = 1'b0; arvalid = 1'b0;
        bready  = 1'b0; rready = 1'b0;
        awaddr  = 32'h0; wdata  = 32'h0; araddr = 32'h0; wstrb = 4'h0;
        q_head = 0; q_tail = 0;
        n_pass = 0; n_err = 0; n_extra = 0;
        pushed = 0; popped = 0; stall_cnt = 0;
        WD_LIMIT = 400;

        $readmemh("keys.mem",  k_arr);
        $readmemh("ins.mem",   i_arr);
        $readmemh("exps.mem",  e_arr);
        $readmemh("dkeys.mem", dk_arr);
        $readmemh("dins.mem",  di_arr);
        $readmemh("dexps.mem", de_arr);

        #100;
        rst_n = 1'b1;
        #50;

        // ---- S1: 复位后状态 ----
        axil_read(32'h0C, rd);
        $display("S1 STATUS=0x%08h (KEY_READY=%b BUSY=%b)", rd, rd[0], rd[1]);
        if (rd[0] !== 1'b0) begin n_err = n_err + 1; $display("S1 FAIL: KEY_READY 应为 0"); end
        else n_pass = n_pass + 1;

        // ---- S2: 换钥后 KEY_READY=1 ----
        load_key_via_axil(k_arr[0]);
        #200;
        axil_read(32'h0C, rd);
        $display("S2 STATUS=0x%08h (KEY_READY=%b)", rd, rd[0]);
        if (rd[0] !== 1'b1) begin n_err = n_err + 1; $display("S2 FAIL: 换钥后 KEY_READY 应为 1"); end
        else n_pass = n_pass + 1;

        // ---- S3: ENABLE=0 时数据被挡 ----
        axil_write(32'h08, 32'h00000001);   // MODE=1, ENABLE=0
        s_tvalid = 1'b1; s_tdata = i_arr[0]; s_tlast = 1'b1;
        repeat (20) @(posedge clk);
        if (pushed != 0) begin n_err = n_err + 1; $display("S3 FAIL: ENABLE=0 仍有 %0d 拍被接收", pushed); end
        else n_pass = n_pass + 1;
        s_tvalid = 1'b0; s_tdata = 64'h0; s_tlast = 1'b0;

        // ---- S4: ENABLE=1 后正常出数 ----
        axil_write(32'h08, 32'h00000003);   // MODE=1, ENABLE=1
        exp_q[q_tail] = e_arr[0]; q_tail = q_tail + 1;
        send_beat(i_arr[0], 1'b1);
        wait_drain;
        $display("S4 加密：pushed=%0d popped=%0d", pushed, popped);

        // ---- S5: 在途换钥被拒绝 ----
        // 先填满流水线：m_tready=0 后连续灌 8 笔，确保在途深度接近 16 级
        m_tready = 1'b0;
        repeat (2) @(posedge clk);
        for (j = 1; j <= 8; j = j + 1) begin
            exp_q[q_tail] = e_arr[j]; q_tail = q_tail + 1;
            send_beat(i_arr[j], (j == 8));
        end
        axil_read(32'h0C, rd);
        $display("S5 换钥前 STATUS=0x%08h BUSY=%b", rd, rd[1]);
        if (rd[1] !== 1'b1) begin n_err = n_err + 1; $display("S5 FAIL: 灌入数据后 BUSY 应为 1"); end
        else n_pass = n_pass + 1;
        load_key_via_axil(k_arr[1]);        // 在途换钥 → 应被拒绝
        axil_read(32'h0C, rd);
        $display("S5 换钥后 STATUS=0x%08h REKEY_ERR=%b", rd, rd[3]);
        if (rd[3] !== 1'b1) begin n_err = n_err + 1; $display("S5 FAIL: 在途换钥应置 REKEY_ERR"); end
        else n_pass = n_pass + 1;

        // 放开反压，数据应原样正确输出（未被半路换钥污染）
        m_tready = 1'b1;
        wait_drain;
        $display("S5 数据未受影响：popped=%0d err=%0d", popped, n_err);

        // ---- S6: 排空后换钥正常 ----
        load_key_via_axil(k_arr[1]);
        #300;
        axil_read(32'h0C, rd);
        $display("S6 排空后换钥 STATUS=0x%08h KEY_READY=%b", rd, rd[0]);
        if (rd[0] !== 1'b1) begin n_err = n_err + 1; $display("S6 FAIL: 排空后换钥应成功"); end
        else n_pass = n_pass + 1;

        // ---- S7: 解密方向 ----
        axil_write(32'h08, 32'h00000002);   // MODE=0 (解密), ENABLE=1
        load_key_via_axil(dk_arr[0]);
        #300;
        for (j = 0; j < 4 && j < `N_DEC; j = j + 1) begin
            exp_q[q_tail] = de_arr[j]; q_tail = q_tail + 1;
            send_beat(di_arr[j], (j == 3));
        end
        wait_drain;
        $display("S7 解密：pushed=%0d popped=%0d", pushed, popped);

        #200;
        $display("=================================================");
        $display("  pass       : %0d", n_pass);
        $display("  data err   : %0d", n_err);
        $display("  extra      : %0d", n_extra);
        $display("  pushed/popped : %0d / %0d", pushed, popped);
        $display("  stalls     : %0d", stall_cnt);
        if (n_err == 0 && n_extra == 0 && pushed == popped && popped == q_tail && stall_cnt > 0)
            $display("  SOC TB PASS : %0d/%0d", n_pass, q_tail);
        else
            $display("  SOC TB FAIL : pass=%0d err=%0d extra=%0d pushed=%0d popped=%0d tail=%0d",
                     n_pass, n_err, n_extra, pushed, popped, q_tail);
        $display("=================================================");
        $finish;
    end

    initial begin
        #2000000;
        $display("SOC TB TIMEOUT");
        $finish;
    end

endmodule
