`timescale 1ns / 1ps
// ============================================================================
// tb_des_pipeline_fb_v2.v  —— DES 反压验证环境改进版
//
// 相对原 tb_des_pipeline_fb.v 的升级点：
//   1) 激励不再硬编码，由 verify/gen_vectors.py 生成 .mem 文件，
//      `$readmemh` 读入：支持随机明文、多组密钥、加解密双向。
//   2) 覆盖从"9 笔定向"扩展到 28 笔加密 + 14 笔解密，三场景 + 加解密 + 密钥切换。
//   3) 密钥切换验证：场景之间切换 KEY1/KEY2/KEY3，重载 key schedule，
//      验证"密钥可换、换密钥期间不灌数据"的工程口径。
//   4) 自检断言：期望队列 scoreboard 逐笔比对，不丢、不重、不错序；
//      任何 mismatch 记 err 并打印 DUT vs expect，不靠人眼。
//   5) 覆盖率统计（准功能覆盖率）：
//         - valid_o && ready_i  (握手成功传输) 累计拍数
//         - valid_o && !ready_i (被下游压住)    累计拍数
//         - !valid_o            (输出空闲)       累计拍数
//         - 各场景 stall 计数（back-to-back / backpressure / overflow）
//   6) 超时保护 + 最终 PASS/FAIL 汇总。
// 语言：纯 Verilog-2001（XSim 2018.3 可编译）。
// ============================================================================
`include "params.vh"

module tb_des_pipeline_fb_v2;

    // ---- DUT 接口 ----
    reg         clk, rst_n;
    reg         load_key_i;
    reg  [63:0] key_i;
    reg         encrypt_i;
    reg         valid_i;
    reg  [63:0] data_i;
    reg         ready_i;
    wire        ready_key_o;
    wire        valid_o;
    wire        ready_o;
    wire [63:0] data_o;

    des_pipeline_fb uut (
        .clk(clk), .rst_n(rst_n),
        .load_key_i(load_key_i), .key_i(key_i), .ready_key_o(ready_key_o),
        .encrypt_i(encrypt_i),
        .valid_i(valid_i), .data_i(data_i), .ready_i(ready_i),
        .valid_o(valid_o), .ready_o(ready_o), .data_o(data_o)
    );

    // ---- 向量存储（gen_vectors.py 生成） ----
    reg [63:0] k_arr   [0:`N_ENC-1];
    reg [63:0] i_arr   [0:`N_ENC-1];
    reg [63:0] e_arr   [0:`N_ENC-1];
    reg [63:0] dk_arr  [0:`N_DEC-1];
    reg [63:0] di_arr  [0:`N_DEC-1];
    reg [63:0] de_arr  [0:`N_DEC-1];

    // ---- 期望队列（scoreboard） ----
    reg  [63:0] expect_q [0:127];
    integer     q_head, q_tail;

    // ---- 计数 ----
    integer     n_pass, n_err;
    integer     pushed_total, popped_total;
    integer     stall_cnt, sc1, sc2, sc3, sc4;
    integer     cov_xfer, cov_stall, cov_idle;   // 输出口三态覆盖计数
    integer     cov_key_sw;                       // 密钥切换次数
    integer     rekey_while_busy;                 // 违例：在途数据未清空就换密钥
    reg  [63:0] cur_key;                          // 当前已加载的密钥（按值判断）

    // ---- 时钟：100MHz ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Scoreboard：valid_o && ready_i = 下游取走，弹出期望比对 ----
    always @(posedge clk) begin
        if (rst_n) begin
            cov_xfer  = cov_xfer  + (valid_o && ready_i ? 1 : 0);
            cov_stall = cov_stall + (valid_o && !ready_i ? 1 : 0);
            cov_idle  = cov_idle  + (!valid_o ? 1 : 0);

            if (valid_o && ready_i) begin
                if (q_head < q_tail) begin
                    // X/Z 检测：任一信号含 X/Z 一律判错，防止"向量文件缺失/未驱动"假通过
                    if ((^data_o === 1'bx) || (^expect_q[q_head] === 1'bx)) begin
                        n_err = n_err + 1;
                        $display("[%0t] ** X/Z DETECTED #%0d : DUT=%h expect=%h (向量文件可能缺失)", $time, q_head, data_o, expect_q[q_head]);
                    end else if (data_o !== expect_q[q_head]) begin
                        n_err = n_err + 1;
                        $display("[%0t] ** MISMATCH #%0d : DUT=%h expect=%h", $time, q_head, data_o, expect_q[q_head]);
                    end else begin
                        n_pass = n_pass + 1;
                        $display("[%0t]  OK   #%0d : %h", $time, q_head, data_o);
                    end
                    q_head = q_head + 1;
                    popped_total = popped_total + 1;
                end else begin
                    // 有输出但没有期望：说明 DUT 多发了数据（重复/多余）
                    n_err = n_err + 1;
                    $display("[%0t] ** EXTRA OUTPUT (no pending expect): %h", $time, data_o);
                end
            end
        end
    end

    // ---- stall 计数器（valid_o=1 且 ready_i=0 = 数据被压住） ----
    always @(posedge clk) begin
        if (rst_n && valid_o && !ready_i) stall_cnt = stall_cnt + 1;
    end

    // ---- 设计约束检查：禁止在流水线有在途数据时重算 key schedule ----
    // 这是本次改造从仿真里实测出来的真实约束：key_ram 无排空互锁，
    // 一旦在途数据未清空就触发 load_key_i，在途事务会读到被半途改写的子密钥。
    always @(posedge clk) begin
        if (rst_n && load_key_i && (popped_total < pushed_total)) begin
            rekey_while_busy = rekey_while_busy + 1;
            $display("[%0t] ** REKEY-WHILE-BUSY : 换密钥时仍有 %0d 笔在途数据",
                     $time, pushed_total - popped_total);
        end
    end

    // ---- 任务：加载密钥（可重复触发 key schedule） ----
    task load_key(input [63:0] k);
        begin
            @(negedge clk);
            key_i = k; load_key_i = 1;
            @(posedge clk);
            @(negedge clk);
            load_key_i = 0;
            // 等本轮 key schedule 完成：先看它拉低，再等拉高
            wait(ready_key_o == 1'b0);
            wait(ready_key_o == 1'b1);
        end
    endtask

    // ---- 任务：注入一笔（遵守握手，负沿更新，正沿采样） ----
    task inject(input [63:0] d);
        begin
            @(negedge clk);
            data_i = d; valid_i = 1;
            @(posedge clk);
            while (!(valid_i && ready_o)) @(posedge clk);  // 被反压就等
            @(negedge clk);
            valid_i = 0; data_i = 0;
        end
    endtask

    // ---- 任务：等待流水线排空（所有期望都被弹出） ----
    task wait_drain;
        begin
            while (popped_total < pushed_total) @(posedge clk);
        end
    endtask

    // ---- 任务：安全换密钥（带排空互锁） ----
    // 设计约束：key_ram 由 key schedule FSM 与流水线各级共用；FSM 在 CALC 期间
    // 会逐条重写 key_ram[0..15]。若此时流水线里还有在途数据，这些数据会读到
    // "半新半旧"的子密钥，输出必错。所以换密钥前必须先排空流水线。
    // rekey() 把这条约束固化进环境；rekey_while_busy 计数器把它显式暴露出来。
    task rekey(input [63:0] k);
        begin
            wait_drain;
            load_key(k);
            cur_key = k;
            cov_key_sw = cov_key_sw + 1;
        end
    endtask


    // ==========================================================================
    // 主流程
    // ==========================================================================
    integer j;
    initial begin
        // ---- 初始化 ----
        rst_n=0; valid_i=0; data_i=0; ready_i=1; load_key_i=0; key_i=0; encrypt_i=1;
        q_head=0; q_tail=0; n_pass=0; n_err=0;
        pushed_total=0; popped_total=0; stall_cnt=0;
        sc1=0; sc2=0; sc3=0; sc4=0;
        cov_xfer=0; cov_stall=0; cov_idle=0; cov_key_sw=0;
        rekey_while_busy=0; cur_key=64'h0;

        // ---- 读入向量 ----
        $readmemh("keys.mem",   k_arr);
        $readmemh("ins.mem",    i_arr);
        $readmemh("exps.mem",   e_arr);
        $readmemh("dkeys.mem",  dk_arr);
        $readmemh("dins.mem",   di_arr);
        $readmemh("dexps.mem",  de_arr);

        #100; rst_n=1; #20;
        $display("=== DES 反压验证 v2 开始 : N_ENC=%0d N_DEC=%0d ===", `N_ENC, `N_DEC);

        // ======================================================================
        // [加密通路] 场景1：back-to-back（ready 恒 1，KEY1 + NIST 向量）
        // ======================================================================
        ready_i = 1;
        for (j=0; j<`N_B2B; j=j+1) begin
            if (k_arr[j] !== cur_key) rekey(k_arr[j]);
            expect_q[q_tail] = e_arr[j]; q_tail = q_tail + 1;
            pushed_total = pushed_total + 1;
            inject(i_arr[j]);
        end
        @(negedge clk); valid_i=0; data_i=0;
        wait_drain; #40;
        sc1 = stall_cnt;
        $display("[%0t] 场景1 back-to-back  : push=%0d pop=%0d stall=%0d", $time, pushed_total, popped_total, stall_cnt);

        // ======================================================================
        // [加密通路] 场景2：backpressure（KEY2，数据到达输出级后拉低 ready）
        // ======================================================================
        fork
            begin
                for (j=`N_B2B; j<`N_B2B+`N_BPRS; j=j+1) begin
                    if (k_arr[j] !== cur_key) rekey(k_arr[j]);
                    expect_q[q_tail] = e_arr[j]; q_tail = q_tail + 1;
                    pushed_total = pushed_total + 1;
                    inject(i_arr[j]);
                end
                @(negedge clk); valid_i=0; data_i=0;
            end
            begin
                wait(valid_o == 1'b1);
                repeat(3) begin
                    @(negedge clk); ready_i = 1'b0;
                    repeat(8) @(negedge clk);
                    ready_i = 1'b1;
                    repeat(3) @(negedge clk);
                end
            end
        join
        wait_drain; #40;
        sc2 = stall_cnt;
        $display("[%0t] 场景2 backpressure  : push=%0d pop=%0d stall(累计)=%0d 本场景=%0d",
                 $time, pushed_total, popped_total, stall_cnt, sc2 - sc1);

        // ======================================================================
        // [加密通路] 场景3：overflow（KEY3，上游持续灌 + 下游反复收停）
        // ======================================================================
        fork
            begin
                for (j=`N_B2B+`N_BPRS; j<`N_ENC; j=j+1) begin
                    if (k_arr[j] !== cur_key) rekey(k_arr[j]);
                    expect_q[q_tail] = e_arr[j]; q_tail = q_tail + 1;
                    pushed_total = pushed_total + 1;
                    inject(i_arr[j]);
                end
                @(negedge clk); valid_i=0; data_i=0;
            end
            begin
                wait(valid_o == 1'b1);
                repeat(4) begin
                    @(negedge clk); ready_i = 1'b0;
                    repeat(5) @(negedge clk);
                    ready_i = 1'b1;
                    repeat(2) @(negedge clk);
                end
            end
        join
        wait_drain; #40;
        sc3 = stall_cnt;
        $display("[%0t] 场景3 overflow      : push=%0d pop=%0d stall(累计)=%0d 本场景=%0d",
                 $time, pushed_total, popped_total, stall_cnt, sc3 - sc2);

        // ======================================================================
        // [解密通路] 场景4：解密 back-to-back（encrypt_i=0，KEY1 + KEY2）
        // ======================================================================
        encrypt_i = 0;
        cur_key = 64'h0;
        for (j=0; j<`N_DEC; j=j+1) begin
            if (dk_arr[j] !== cur_key) rekey(dk_arr[j]);
            expect_q[q_tail] = de_arr[j]; q_tail = q_tail + 1;
            pushed_total = pushed_total + 1;
            inject(di_arr[j]);
        end
        @(negedge clk); valid_i=0; data_i=0;
        wait_drain; #40;
        sc4 = stall_cnt;
        $display("[%0t] 场景4 解密          : push=%0d pop=%0d stall=%0d", $time, pushed_total, popped_total, stall_cnt);

        // ======================================================================
        // 汇总
        // ======================================================================
        $display("");
        $display("==================== VERIFICATION SUMMARY ====================");
        $display("  pushed_total          : %0d", pushed_total);
        $display("  popped_total          : %0d", popped_total);
        $display("  pass                  : %0d", n_pass);
        $display("  error                 : %0d", n_err);
        $display("  key_schedule reloads  : %0d", cov_key_sw);
        $display("  rekey-while-busy 违例 : %0d  (应为 0；换密钥前已强制排空)", rekey_while_busy);
        $display("  stall  场景1 b2b       : %0d", sc1);
        $display("  stall  场景2 bprs      : %0d", sc2 - sc1);
        $display("  stall  场景3 ovf       : %0d", sc3 - sc2);
        $display("  stall  场景4 dec       : %0d", sc4 - sc3);
        $display("  stall  合计            : %0d", stall_cnt);
        $display("  cov 握手成功(valid&&ready): %0d 拍", cov_xfer);
        $display("  cov 下游压住(valid&&!ready): %0d 拍", cov_stall);
        $display("  cov 输出空闲(!valid)      : %0d 拍", cov_idle);
        $display("==============================================================");
        if (n_err == 0 && rekey_while_busy == 0 && popped_total == pushed_total && pushed_total > 0)
            $display("\n**** PASS : %0d/%0d outputs match golden (enc+dec, 3 scenarios, key switching) ****",
                     n_pass, pushed_total);
        else
            $display("\n**** FAIL : err=%0d, rekey_busy=%0d, pushed=%0d, popped=%0d ****",
                     n_err, rekey_while_busy, pushed_total, popped_total);
        $finish;
    end

    // 超时保护
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

