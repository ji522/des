`timescale 1ns / 1ps
// ============================================================================
// tb_des_boundary.v  —— DES 等价类 / 边界值定向回归（独立 TB，不改动现有 TB）
//
// 向量：verify/vectors_bnd/{bkeys,bins,bexps}.mem（18 行，16 hex/行）
//      由 verify/gen_boundary_vectors.py 用 pycryptodome 生成并自检。
//
// 覆盖：全0/全1、弱密钥、半弱密钥、交替模式、单比特游走、标准向量、
//       ECB 确定性（同明文两拍）、明文互补对、密钥+明文互补对。
//
// 结构：复用 tb_des_pipeline_fb_v2 的接法（des_pipeline_fb + valid/ready），
//       ready_i 恒 1，back-to-back 注入；scoreboard 逐笔比对，检测 X/Z 与多发。
//
// 额外性质检查（DUT 级，独立计数，不计入 N/N）：
//   P1/P2 弱密钥 E(E(P)) == P
//   P3    半弱对 E(FE01.., E(01FE.., P)) == P
//   P4    补性质 E(~K,~P) == ~E(K,P)
//
// 结束打印：BOUNDARY TB PASS : N/N  或 FAIL 明细。
// 语言：纯 Verilog-2001，$display 全 ASCII（避免日志中文乱码）。
// ============================================================================
module tb_des_boundary;

    localparam N_BND      = 18;
    localparam IDX_WEAK0  = 2;
    localparam IDX_WEAK1  = 3;
    localparam IDX_SEMI   = 4;
    localparam IDX_COMP_A = 16;
    localparam IDX_COMP_B = 17;

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

    // ---- 向量存储 ----
    reg [63:0] k_arr [0:N_BND-1];
    reg [63:0] i_arr [0:N_BND-1];
    reg [63:0] e_arr [0:N_BND-1];

    // ---- scoreboard ----
    reg  [63:0] expect_q [0:63];
    integer     q_head, q_tail;
    reg  [63:0] captured [0:N_BND-1];   // 主阶段实际输出，用于补性质
    integer     mode;                   // 0=主向量 1=性质注入

    // ---- 计数 ----
    integer n_pass, n_err, n_x, n_extra;
    integer prop_pass, prop_fail;
    reg     key_loaded;
    reg [63:0] cur_key;

    // ---- 时钟 100MHz ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Scoreboard ----
    always @(posedge clk) begin
        if (rst_n && valid_o && ready_i) begin
            if (q_head < q_tail) begin
                if (mode == 0 && q_head < N_BND)
                    captured[q_head] = data_o;

                if ((^data_o === 1'bx) || (^expect_q[q_head] === 1'bx)) begin
                    n_x = n_x + 1;
                    if (mode == 0) n_err = n_err + 1; else prop_fail = prop_fail + 1;
                    $display("[%0t] ** X/Z #%0d : DUT=%h expect=%h",
                             $time, q_head, data_o, expect_q[q_head]);
                end else if (data_o !== expect_q[q_head]) begin
                    if (mode == 0) begin
                        n_err = n_err + 1;
                        $display("[%0t] ** MISMATCH #%0d : DUT=%h expect=%h",
                                 $time, q_head, data_o, expect_q[q_head]);
                    end else begin
                        prop_fail = prop_fail + 1;
                        $display("[%0t] ** PROP MISMATCH : DUT=%h expect=%h",
                                 $time, data_o, expect_q[q_head]);
                    end
                end else begin
                    if (mode == 0) begin
                        n_pass = n_pass + 1;
                        $display("[%0t]  OK   #%0d : %h", $time, q_head, data_o);
                    end else begin
                        prop_pass = prop_pass + 1;
                        $display("[%0t]  PROP OK     : %h", $time, data_o);
                    end
                end
                q_head = q_head + 1;
            end else begin
                n_extra = n_extra + 1;
                $display("[%0t] ** EXTRA OUTPUT (no pending expect): %h", $time, data_o);
            end
        end
    end

    // ---- 任务：加载密钥 ----
    task load_key(input [63:0] k);
        begin
            @(negedge clk);
            key_i = k; load_key_i = 1;
            @(posedge clk);
            @(negedge clk);
            load_key_i = 0;
            wait(ready_key_o == 1'b0);
            wait(ready_key_o == 1'b1);
        end
    endtask

    // ---- 任务：注入一笔（负沿更新，正沿握手） ----
    task inject(input [63:0] d);
        begin
            @(negedge clk);
            data_i = d; valid_i = 1;
            @(posedge clk);
            while (!(valid_i && ready_o)) @(posedge clk);
            @(negedge clk);
            valid_i = 0; data_i = 0;
        end
    endtask

    // ---- 任务：排队一笔期望 ----
    task push_expect(input [63:0] e);
        begin
            expect_q[q_tail] = e;
            q_tail = q_tail + 1;
        end
    endtask

    // ---- 任务：等待排空 ----
    task wait_drain;
        begin
            while (q_head < q_tail) @(posedge clk);
        end
    endtask

    // ---- 任务：安全换钥（先排空） ----
    task rekey(input [63:0] k);
        begin
            wait_drain;
            load_key(k);
            cur_key = k;
            key_loaded = 1;
        end
    endtask

    integer j;
    initial begin
        // 初始化
        rst_n = 0; valid_i = 0; data_i = 0; ready_i = 1;
        load_key_i = 0; key_i = 0; encrypt_i = 1;
        q_head = 0; q_tail = 0; mode = 0;
        n_pass = 0; n_err = 0; n_x = 0; n_extra = 0;
        prop_pass = 0; prop_fail = 0;
        key_loaded = 0; cur_key = 64'h0;
        for (j = 0; j < N_BND; j = j + 1) captured[j] = 64'h0;

        $readmemh("bkeys.mem", k_arr);
        $readmemh("bins.mem",  i_arr);
        $readmemh("bexps.mem", e_arr);

        #100; rst_n = 1; #20;
        $display("=== DES boundary / equivalence-class regression : N=%0d ===", N_BND);

        // ---------------- 主向量：18 笔，ready 恒 1 ----------------
        ready_i = 1; encrypt_i = 1; mode = 0;
        for (j = 0; j < N_BND; j = j + 1) begin
            if (!key_loaded || k_arr[j] !== cur_key) rekey(k_arr[j]);
            push_expect(e_arr[j]);
            inject(i_arr[j]);
        end
        @(negedge clk); valid_i = 0; data_i = 0;
        wait_drain; #40;

        $display("main : pass=%0d err=%0d x=%0d extra=%0d",
                 n_pass, n_err, n_x, n_extra);

        // ---------------- 性质阶段（DUT 级，独立计数） ----------------
        mode = 1;

        // P1: 弱密钥 0101..  E(E(P)) == P
        rekey(k_arr[IDX_WEAK0]);
        push_expect(i_arr[IDX_WEAK0]);
        inject(e_arr[IDX_WEAK0]);
        wait_drain; #20;

        // P2: 弱密钥 FEFE..  E(E(P)) == P
        rekey(k_arr[IDX_WEAK1]);
        push_expect(i_arr[IDX_WEAK1]);
        inject(e_arr[IDX_WEAK1]);
        wait_drain; #20;

        // P3: 半弱对 E(FE01.., E(01FE.., P)) == P
        rekey(64'hFE01FE01FE01FE01);
        push_expect(i_arr[IDX_SEMI]);
        inject(e_arr[IDX_SEMI]);
        wait_drain; #20;

        // P4: 补性质 E(~K,~P) == ~E(K,P)（用主阶段已捕获的输出）
        if (captured[IDX_COMP_B] === ~captured[IDX_COMP_A]) begin
            prop_pass = prop_pass + 1;
            $display("  PROP OK     : complement E(~K,~P)==~E(K,P) : %h",
                     captured[IDX_COMP_B]);
        end else begin
            prop_fail = prop_fail + 1;
            $display("** PROP FAIL : complement  E(~K,~P)=%h  ~E(K,P)=%h",
                     captured[IDX_COMP_B], ~captured[IDX_COMP_A]);
        end

        // ---------------- 汇总 ----------------
        $display("");
        $display("================ BOUNDARY SUMMARY ================");
        $display("  vectors             : %0d", N_BND);
        $display("  scoreboard pass     : %0d", n_pass);
        $display("  mismatch            : %0d", n_err);
        $display("  X/Z                 : %0d", n_x);
        $display("  extra output        : %0d", n_extra);
        $display("  property pass/fail  : %0d/%0d", prop_pass, prop_fail);
        $display("==================================================");
        if (n_err == 0 && n_x == 0 && n_extra == 0 &&
            n_pass == N_BND && prop_fail == 0 && prop_pass == 4)
            $display("BOUNDARY TB PASS : %0d/%0d  (property %0d/%0d)",
                     n_pass, N_BND, prop_pass, prop_pass + prop_fail);
        else
            $display("BOUNDARY TB FAIL : pass=%0d/%0d err=%0d x=%0d extra=%0d prop_fail=%0d",
                     n_pass, N_BND, n_err, n_x, n_extra, prop_fail);
        $finish;
    end

    // 超时保护
    initial begin
        #200000;
        $display("BOUNDARY TB FAIL : TIMEOUT");
        $finish;
    end

endmodule
