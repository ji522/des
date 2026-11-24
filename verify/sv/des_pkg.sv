// ============================================================================
// des_pkg.sv —— DES 反压验证环境（SystemVerilog 类化环境）
//
// 结构（对标 UVM 的最小可用骨架）：
//   des_txn         事务
//   des_rnd_cfg     约束随机配置
//   des_driver      驱动器（负责复位、载密钥、灌数据、wait_drain）
//   des_ready_agent ready_i 约束随机激励（制造随机反压）
//   des_monitor     监测器（采样输出，送 scoreboard + coverage）
//   des_scoreboard  计分板（期望队列 + X/Z 检查 + 计数）
//   des_coverage    功能覆盖率（covergroup）
//   des_env         环境顶层（装配 + 跑序列）
// ============================================================================
package des_pkg;

    `include "params.vh"

    localparam int N_STRESS = 8;

    // ------------------------------------------------------------------
    // 事务
    // ------------------------------------------------------------------
    class des_txn;
        rand bit [63:0] data;
        bit      [63:0] exp;
        bit             mode;   // 1 = 加密, 0 = 解密
        bit      [63:0] key;
        function new(bit [63:0] d = 0, bit [63:0] e = 0, bit m = 1, bit [63:0] k = 0);
            data = d; exp = e; mode = m; key = k;
        endfunction
        function string sprint();
            return $sformatf("mode=%0d key=%h data=%h exp=%h", mode, key, data, exp);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // 约束随机配置：事务间隔 + 反压时长分布
    // ------------------------------------------------------------------
    class des_rnd_cfg;
        rand int unsigned gap;         // 事务之间的空闲拍数
        rand int unsigned stall_len;   // 单次反压持续拍数
        rand int unsigned free_len;    // 反压之间的空闲拍数
        constraint c_gap   { gap inside {[0:2]}; }
        constraint c_stall { stall_len dist { [1:3] := 50, [4:10] := 50 }; }
        constraint c_free  { free_len inside {[0:3]}; }
    endclass

    // ------------------------------------------------------------------
    // 驱动器
    // ------------------------------------------------------------------
    class des_driver;
        virtual des_if vif;
        des_rnd_cfg    cfg;
        int unsigned   n_drive;

        function new(virtual des_if v);
            vif = v;
            cfg = new();
            n_drive = 0;
        endfunction

        task reset(int unsigned cycles = 10);
            vif.rst_n      = 1'b0;
            vif.valid_i    = 1'b0;
            vif.data_i     = '0;
            vif.ready_i    = 1'b1;
            vif.load_key_i = 1'b0;
            vif.key_i      = '0;
            vif.encrypt_i  = 1'b1;
            repeat (cycles) @(posedge vif.clk);
            vif.rst_n = 1'b1;
            repeat (2) @(posedge vif.clk);
        endtask

        // 载入密钥并等待 key schedule 完成
        task load_key(bit [63:0] k);
            @(negedge vif.clk);
            vif.key_i = k; vif.load_key_i = 1'b1;
            @(negedge vif.clk);
            vif.load_key_i = 1'b0;
            wait (vif.ready_key_o == 1'b0);
            wait (vif.ready_key_o == 1'b1);
        endtask

        // 驱动一笔，遵守 valid/ready 握手；gap 为事务后空闲拍数
        task drive(des_txn t, int unsigned gap = 0);
            vif.encrypt_i = t.mode;
            @(negedge vif.clk);
            vif.data_i  = t.data;
            vif.valid_i = 1'b1;
            @(posedge vif.clk);
            while (!(vif.valid_i && vif.ready_o)) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.valid_i = 1'b0;
            vif.data_i  = '0;
            n_drive++;
            if (gap > 0) repeat (gap) @(negedge vif.clk);
        endtask

        // 约束随机间隔版本
        task drive_rand(des_txn t);
            void'(cfg.randomize());
            drive(t, cfg.gap);
        endtask
    endclass

    // ------------------------------------------------------------------
    // ready 随机代理：制造约束随机反压
    // ------------------------------------------------------------------
    class des_ready_agent;
        virtual des_if vif;
        des_rnd_cfg    cfg;
        bit            active;

        function new(virtual des_if v);
            vif = v;
            cfg = new();
            active = 1'b0;
        endfunction

        task run();
            while (active) begin
                void'(cfg.randomize());
                @(negedge vif.clk);
                vif.ready_i = 1'b0;
                repeat (cfg.stall_len) @(negedge vif.clk);
                vif.ready_i = 1'b1;
                repeat (cfg.free_len) @(negedge vif.clk);
            end
            vif.ready_i = 1'b1;
        endtask
    endclass

    // ------------------------------------------------------------------
    // 计分板
    // ------------------------------------------------------------------
    class des_scoreboard;
        bit [63:0] q[$];
        int        n_push, n_cmp, n_err, n_extra, n_xz;

        function void push(bit [63:0] e);
            q.push_back(e);
            n_push++;
        endfunction

        function void check(bit [63:0] d);
            bit [63:0] e;
            if (q.size() == 0) begin
                n_extra++;
                $display("[%0t] ** EXTRA OUTPUT: %h (无待比对期望)", $time, d);
                return;
            end
            e = q.pop_front();
            n_cmp++;
            if ($isunknown(d) || $isunknown(e)) begin
                n_xz++;
                $display("[%0t] ** X/Z #%0d : DUT=%h expect=%h", $time, n_cmp-1, d, e);
            end
            else if (d !== e) begin
                n_err++;
                $display("[%0t] ** MISMATCH #%0d : DUT=%h expect=%h", $time, n_cmp-1, d, e);
            end
        endfunction

        function bit idle();
            return (n_push == n_cmp) && (q.size() == 0);
        endfunction

        function bit pass();
            return (n_err == 0) && (n_xz == 0) && (n_extra == 0) && (n_push == n_cmp) && (n_push > 0);
        endfunction

        function void report();
            $display("========== SCOREBOARD ==========");
            $display("  push / cmp        : %0d / %0d", n_push, n_cmp);
            $display("  mismatch          : %0d", n_err);
            $display("  X/Z               : %0d", n_xz);
            $display("  extra output      : %0d", n_extra);
            $display("=================================");
        endfunction
    endclass

    // ------------------------------------------------------------------
    // 功能覆盖率
    // ------------------------------------------------------------------
    class des_coverage;
        virtual des_if vif;

        // 不挂 clocking event，由 monitor 在 rst_n 有效时显式 sample()
        covergroup cg_handshake;
            option.per_instance = 1;

            cp_hs : coverpoint (vif.valid_o && vif.ready_i) {
                bins xfer = {1'b1};
            }
            cp_stall : coverpoint (vif.valid_o && !vif.ready_i) {
                bins stall = {1'b1};
            }
            cp_idle : coverpoint (!vif.valid_o) {
                bins idle = {1'b1};
            }
            cp_mode : coverpoint vif.encrypt_i {
                bins enc = {1'b1};
                bins dec = {1'b0};
            }
            cp_keyload : coverpoint vif.load_key_i {
                bins rekey = {1'b1};
            }
            x_mode_xfer : cross cp_mode, cp_hs;
            x_mode_stall : cross cp_mode, cp_stall;
        endgroup

        function new(virtual des_if v);
            vif = v;
            cg_handshake = new();
        endfunction

        function void report();
            $display("========== COVERAGE ==========");
            $display("  covergroup 总覆盖率 : %0.2f%%", cg_handshake.get_coverage());
            $display("==============================");
        endfunction
    endclass

    // ------------------------------------------------------------------
    // 监测器
    // ------------------------------------------------------------------
    class des_monitor;
        virtual des_if   vif;
        des_scoreboard   sb;
        des_coverage     cov;

        function new(virtual des_if v, des_scoreboard s, des_coverage c);
            vif = v; sb = s; cov = c;
        endfunction

        task run();
            forever begin
                @(posedge vif.clk);
                if (vif.rst_n) begin
                    if (vif.valid_o && vif.ready_i) sb.check(vif.data_o);
                    if (cov != null) cov.cg_handshake.sample();
                end
            end
        endtask
    endclass

    // ------------------------------------------------------------------
    // 环境
    // ------------------------------------------------------------------
    class des_env;
        virtual des_if   vif;
        des_driver       drv;
        des_ready_agent  rdy;
        des_monitor      mon;
        des_scoreboard   sb;
        des_coverage     cov;

        // 向量
        bit [63:0] k_enc[], i_enc[], e_enc[];
        bit [63:0] k_dec[], i_dec[], e_dec[];

        int n_rekey;

        function new(virtual des_if v);
            vif = v;
            drv = new(v);
            rdy = new(v);
            sb  = new();
            cov = new(v);
            mon = new(v, sb, cov);
            n_rekey = 0;
        endfunction

        function void load_vectors();
            k_enc = new[`N_ENC]; i_enc = new[`N_ENC]; e_enc = new[`N_ENC];
            k_dec = new[`N_DEC]; i_dec = new[`N_DEC]; e_dec = new[`N_DEC];
            $readmemh("keys.mem",  k_enc);
            $readmemh("ins.mem",   i_enc);
            $readmemh("exps.mem",  e_enc);
            $readmemh("dkeys.mem", k_dec);
            $readmemh("dins.mem",  i_dec);
            $readmemh("dexps.mem", e_dec);
        endfunction

        task wait_drain();
            while (!sb.idle()) @(posedge vif.clk);
        endtask

        // 安全换密钥：先排空流水线（设计约束，见 README）
        task rekey(bit [63:0] k);
            wait_drain();
            drv.load_key(k);
            n_rekey++;
        endtask

        task run();
            bit [63:0] cur_key;
            des_txn    t;

            load_vectors();
            fork mon.run(); join_none

            drv.reset();

            // ---------- 阶段1：加密向量，约束随机间隔 ----------
            $display("[%0t] === 阶段1：加密向量（%0d 笔，约束随机间隔） ===", $time, `N_ENC);
            cur_key = '0;
            for (int i = 0; i < `N_ENC; i++) begin
                if (k_enc[i] !== cur_key) begin
                    rekey(k_enc[i]);
                    cur_key = k_enc[i];
                end
                t = new(i_enc[i], e_enc[i], 1'b1, k_enc[i]);
                sb.push(e_enc[i]);
                drv.drive_rand(t);
            end
            wait_drain();

            // ---------- 阶段2：解密向量 ----------
            $display("[%0t] === 阶段2：解密向量（%0d 笔） ===", $time, `N_DEC);
            cur_key = '0;
            for (int i = 0; i < `N_DEC; i++) begin
                if (k_dec[i] !== cur_key) begin
                    rekey(k_dec[i]);
                    cur_key = k_dec[i];
                end
                t = new(i_dec[i], e_dec[i], 1'b0, k_dec[i]);
                sb.push(e_dec[i]);
                drv.drive_rand(t);
            end
            wait_drain();

            // ---------- 阶段3：约束随机反压 ----------
            $display("[%0t] === 阶段3：约束随机反压（%0d 笔） ===", $time, N_STRESS);
            rdy.active = 1'b1;
            fork rdy.run(); join_none
            rekey(k_enc[0]);
            for (int i = 0; i < N_STRESS; i++) begin
                t = new(i_enc[i], e_enc[i], 1'b1, k_enc[0]);
                sb.push(e_enc[i]);
                drv.drive_rand(t);
            end
            wait_drain();
            rdy.active = 1'b0;
            @(posedge vif.clk);
            vif.ready_i = 1'b1;
            repeat (5) @(posedge vif.clk);

            // ---------- 阶段4：解密方向 × 约束随机反压 ----------
            // 阶段3 只跑了加密方向，覆盖率报告显示 cross(dec, stall) 未被命中；
            // 这里专门补上这个覆盖洞：解密模式 + 随机反压。
            $display("[%0t] === 阶段4：解密 × 约束随机反压（补覆盖洞） ===", $time);
            rekey(k_dec[0]);
            rdy.active = 1'b1;
            fork rdy.run(); join_none
            for (int i = 0; i < N_STRESS; i++) begin
                t = new(i_dec[i], e_dec[i], 1'b0, k_dec[0]);
                sb.push(e_dec[i]);
                drv.drive_rand(t);
            end
            wait_drain();
            rdy.active = 1'b0;
            @(posedge vif.clk);
            vif.ready_i = 1'b1;
            repeat (5) @(posedge vif.clk);

            // ---------- 汇总 ----------
            sb.report();
            cov.report();
            $display("  key schedule 重载 : %0d", n_rekey);
            $display("  驱动事务数        : %0d", drv.n_drive);
            if (sb.pass()) $display("\n**** SV ENV PASS ****");
            else           $display("\n**** SV ENV FAIL ****");
            $finish;
        endtask
    endclass

endpackage
