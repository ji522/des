// ============================================================================
// des_uvm_pkg.sv —— DES 反压流水线的 UVM 验证平台（UVM 1.2, Accellera 开源库）
//
// 对照原 class 环境（sv/des_pkg.sv）的 UVM 映射：
//   des_txn          -> uvm_sequence_item（DATA/KEY/STALL/IDLE/REKEY）
//   des_rnd_cfg      -> des_uvm_cfg      (uvm_object, config_db 下发)
//   des_driver       -> des_driver       (uvm_driver#(des_txn))
//   des_ready_agent  -> des_ready_driver (uvm_driver，无 sequence 的 responder)
//   des_monitor      -> des_monitor      (uvm_monitor + analysis_port)
//   des_scoreboard   -> des_uvm_scoreboard (uvm_scoreboard, exp/obs 双流 imp)
//   des_coverage     -> des_uvm_coverage (uvm_subscriber + rekey imp)
//   des_env          -> des_env          (uvm_env)
//   4 阶段激励       -> des_rand_sequence (uvm_sequence)
//   顶层             -> des_rand_test     (uvm_test)
// ============================================================================
`include "uvm_macros.svh"

package des_uvm_pkg;

    import uvm_pkg::*;
    `include "params.vh"

    localparam int N_STRESS = 8;

    // DATA=数据(带期望)  KEY=载密钥  STALL/IDLE=观测事件  REKEY=换钥事件
    typedef enum { TXN_DATA, TXN_KEY, TXN_STALL, TXN_IDLE, TXN_REKEY } txn_kind_e;

    `uvm_analysis_imp_decl(_exp)
    `uvm_analysis_imp_decl(_obs)

    // ---------------- 配置对象 ----------------
    // 反压参数用真正的约束随机（rand + dist）。
    //
    // 工具差异：XSim 2018.3 对 uvm_object::randomize() 会内核崩溃，
    // 因此编译时加 +define+DES_XSIM 时退化为手写的等价分布；
    // 在 VCS/Questa 上不加该宏，走标准 randomize()。
    class des_uvm_cfg extends uvm_object;
        rand int unsigned stall_len;
        rand int unsigned free_len;
        bit  rand_stall_en;
        bit  force_stall;
        bit  rst_done;
        `uvm_object_utils_begin(des_uvm_cfg)
            `uvm_field_int(stall_len, UVM_ALL_ON)
            `uvm_field_int(free_len,  UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "des_uvm_cfg");
            super.new(name);
            rand_stall_en = 0;
            force_stall   = 0;
            rst_done      = 0;
        endfunction

        // 停顿时长：短停顿和长停顿各占一半（权重随机，不是等概率均匀）
        constraint c_stall_len {
            stall_len dist { [1:3] := 50, [4:10] := 50 };
            free_len  inside { [0:3] };
        }
        // force_stall 为 1 时锁定为 4 拍（阶段3/4 用的固定反压）
        constraint c_force { if (force_stall) stall_len == 4; }

        function void gen_stall();
`ifdef DES_XSIM
            // XSim 2018.3 workaround：手写与 c_stall_len 等价的分布
            if (force_stall)               stall_len = 4;
            else if ($urandom_range(1, 0)) stall_len = $urandom_range(3, 1);
            else                           stall_len = $urandom_range(10, 4);
            free_len = $urandom_range(3, 0);
`else
            if (!this.randomize())
                `uvm_fatal("CFG", "des_uvm_cfg::randomize() 失败")
`endif
        endfunction
    endclass

    // ---------------- 事务 ----------------
    class des_txn extends uvm_sequence_item;
        txn_kind_e    kind;
        bit      [63:0] data;
        bit      [63:0] exp;
        bit             mode;   // 1=加密 0=解密
        bit      [63:0] key;
        rand int unsigned gap;  // 相邻事务之间的空闲拍数
        `uvm_object_utils_begin(des_txn)
            `uvm_field_enum(txn_kind_e, kind, UVM_DEFAULT)
            `uvm_field_int (data, UVM_DEFAULT)
            `uvm_field_int (exp,  UVM_DEFAULT)
            `uvm_field_int (mode, UVM_DEFAULT)
            `uvm_field_int (key,  UVM_DEFAULT)
            `uvm_field_int (gap,  UVM_DEFAULT)
        `uvm_object_utils_end
        function new(string name = "des_txn");
            super.new(name);
            kind = TXN_DATA; mode = 1'b1;
        endfunction

        // 事务间隔：大多背靠背，偶尔拉开。
        // 三种场景都必须打到：0 拍（背靠背）、1 拍、≥2 拍。
        // 注：:= 表示"范围内每个值各取该权重"，故实际权重为
        //     0:50 / 1:25 / 2:25 / 3:25 / 4:25（合计 150）。
        //     若想三组 50/25/25，应写成 [2:4] :/ 25（本次未改，保持原激励）。
        constraint c_gap {
            gap dist { 0 := 50, 1 := 25, [2:4] := 25 };
        }
    endclass

    typedef uvm_sequencer#(des_txn) des_sequencer;

    // ---------------- 计分板 ----------------
    class des_uvm_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(des_uvm_scoreboard)
        uvm_analysis_imp_exp#(des_txn, des_uvm_scoreboard) exp_export;
        uvm_analysis_imp_obs#(des_txn, des_uvm_scoreboard) obs_export;
        bit [63:0] q[$];
        int n_push, n_cmp, n_err, n_extra, n_xz;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            exp_export = new("exp_export", this);
            obs_export = new("obs_export", this);
        endfunction
        function void write_exp(des_txn t);
            if (t.kind == TXN_DATA) begin q.push_back(t.exp); n_push++; end
        endfunction
        function void write_obs(des_txn t);
            bit [63:0] e;
            if (t.kind != TXN_DATA) return;
            if (q.size() == 0) begin
                n_extra++;
                `uvm_error("SCB", $sformatf("EXTRA OUTPUT: %h (无待比对期望)", t.data))
                return;
            end
            e = q.pop_front(); n_cmp++;
            if ($isunknown(t.data) || $isunknown(e)) begin
                n_xz++;
                `uvm_error("SCB", $sformatf("X/Z #%0d : DUT=%h expect=%h", n_cmp-1, t.data, e))
            end else if (t.data !== e) begin
                n_err++;
                `uvm_error("SCB", $sformatf("MISMATCH #%0d : DUT=%h expect=%h", n_cmp-1, t.data, e))
            end
        endfunction
        function bit idle();
            return (n_push == n_cmp) && (q.size() == 0);
        endfunction
        function bit pass();
            return (n_err==0) && (n_xz==0) && (n_extra==0) && (n_push==n_cmp) && (n_push>0);
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("SCB", "========== SCOREBOARD ==========", UVM_LOW)
            `uvm_info("SCB", $sformatf("  push / cmp   : %0d / %0d", n_push, n_cmp), UVM_LOW)
            `uvm_info("SCB", $sformatf("  mismatch     : %0d", n_err),  UVM_LOW)
            `uvm_info("SCB", $sformatf("  X/Z          : %0d", n_xz),   UVM_LOW)
            `uvm_info("SCB", $sformatf("  extra output : %0d", n_extra),UVM_LOW)
        endfunction
    endclass

    // ---------------- 覆盖率 ----------------
    class des_uvm_coverage extends uvm_component;
        `uvm_component_utils(des_uvm_coverage)
        virtual des_if vif;
        int unsigned n_obs;
        // XSim 2018.3：coverpoint 只能注册接口信号（vif.*），不注册类成员，故直接采接口
        covergroup cg;
            option.per_instance = 1;
            cp_hs   : coverpoint (vif.valid_o && vif.ready_i)  { bins xfer  = {1'b1}; }
            cp_stall: coverpoint (vif.valid_o && !vif.ready_i) { bins stall = {1'b1}; }
            cp_idle : coverpoint (!vif.valid_o)                { bins idle  = {1'b1}; }
            cp_mode : coverpoint vif.encrypt_i   { bins enc = {1'b1}; bins dec = {1'b0}; }
            cp_rekey: coverpoint vif.load_key_i  { bins rekey = {1'b1}; }
            x_mode_xfer : cross cp_mode, cp_hs;
            x_mode_stall: cross cp_mode, cp_stall;
        endgroup

        // ---------------- gap 分布统计（事务字段，不走 covergroup） ----------------
        // gap 是 sequence 里随机出来的事务字段，不是接口信号。XSim 2018.3 的
        // coverpoint 采 class 成员变量不可靠（其 covergroup 只适合采 vif.*），
        // 因此这里用普通计数器数组手工统计：两个工具（XSim / VCS）行为完全一致，
        // 且能在 report_phase 直接打直方图，便于面试时逐阶段举证。
        //
        // 分档与 des_txn::c_gap 对应：
        //   gap==0 背靠背 | gap==1 隔一拍 | gap 2..4 长间隔 | gap>4 意外值
        localparam int N_STAGE = 4;
        // 数组尺寸用字面量：XSim 2018.3 对"类内 localparam 作数组维度"支持不稳
        int unsigned g0_cnt  [4];   // 每阶段 gap==0
        int unsigned g1_cnt  [4];   // 每阶段 gap==1
        int unsigned g24_cnt [4];   // 每阶段 gap 2..4
        int unsigned gbig_cnt[4];   // 每阶段 gap>4（约束不应产生，用于发现意外）
        int unsigned g_val_cnt[5];        // 总计：gap 精确值 0..4 各自次数
        int unsigned gbig_tot;            // 总计：gap>4
        int unsigned n_gap_rec;           // 已记录 gap 的事务数
        // 反压参数统计（stall_len 1..10 直方图；free_len 0..3）
        int unsigned stall_hist[11];
        int unsigned f_len_cnt[4];
        int unsigned n_stall_rec;

        function string stall_hist_str();
            string s;
            s = "";
            for (int i = 1; i <= 10; i++)
                if (stall_hist[i] != 0) s = {s, $sformatf("%0d:%0d  ", i, stall_hist[i])};
            if (s == "") s = "(none)";
            return s;
        endfunction

        // ready_driver 每次 gen_stall() 后回写，用于展示反压参数分布
        function void record_stall(int unsigned sl, int unsigned fl);
            if (sl >= 1 && sl <= 10) stall_hist[sl]++;
            if (fl <= 3) f_len_cnt[fl]++;
            n_stall_rec++;
        endfunction

        function string stage_label(int unsigned s);
            case (s)
                0: return "PHASE1 enc";
                1: return "PHASE2 dec";
                2: return "PHASE3 enc+stall";
                3: return "PHASE4 dec+stall";
                default: return "UNKNOWN";
            endcase
        endfunction

        // sequence 在 randomize gap 后调用（阶段号 0..3）
        function void record_gap(int unsigned stage, int unsigned g);
            int unsigned s;
            s = (stage < N_STAGE) ? stage : 0;
            if (g == 0) begin
                g0_cnt[s]++; g_val_cnt[0]++;
            end else if (g == 1) begin
                g1_cnt[s]++; g_val_cnt[1]++;
            end else if (g <= 4) begin
                g24_cnt[s]++; g_val_cnt[g]++;
            end else begin
                gbig_cnt[s]++; gbig_tot++;
            end
            n_gap_rec++;
        endfunction

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
            n_obs = 0;
            n_gap_rec = 0;
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual des_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "coverage 拿不到 vif")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (vif.rst_n) begin
                    cg.sample();
                    n_obs++;
                end
            end
        endtask
        function real get_coverage();
            return cg.get_coverage();
        endfunction
        function bit pass();
            return (n_obs > 0) && (cg.get_coverage() >= 100.0);
        endfunction
        // 三种间隔场景在整轮回归（全部 58 笔）中必须都被打到；且不得出现
        // 约束范围外的 gap（gap>4）。注意：单个阶段只有 8 笔时，
        // 按 50/25/25 的分布有约 19% 概率某档为空，属正常统计波动，
        // 所以判定放在总量级，逐阶段数据仅作展示。
        function bit gap_pass();
            if (n_gap_rec == 0)        return 1'b0;
            if (gbig_tot != 0)         return 1'b0;
            if (g_val_cnt[0] == 0)     return 1'b0;
            if (g_val_cnt[1] == 0)     return 1'b0;
            if ((g_val_cnt[2] + g_val_cnt[3] + g_val_cnt[4]) == 0) return 1'b0;
            return 1'b1;
        endfunction
        // 逐阶段"三档齐全"的阶段数（仅展示，不参与判定）
        function int unsigned phases_full();
            int unsigned k;
            k = 0;
            for (int s = 0; s < N_STAGE; s++)
                if (g0_cnt[s] != 0 && g1_cnt[s] != 0 && g24_cnt[s] != 0) k++;
            return k;
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("COV", "========== COVERAGE ==========", UVM_LOW)
            `uvm_info("COV", $sformatf("  采样拍数 : %0d", n_obs), UVM_LOW)
            `uvm_info("COV", $sformatf("  covergroup 总覆盖率 : %0.2f%%", cg.get_coverage()), UVM_LOW)
            `uvm_info("COV", "========== GAP DISTRIBUTION ==========", UVM_LOW)
            // 注意：XSim 2018.3 的 $sformatf 对 "%-16s" 这类宽度化的字符串参数
            // 会报 "Incorrect argument specified" 并输出乱码，这里只用 %0d/%s。
            for (int s = 0; s < N_STAGE; s++)
                `uvm_info("COV", $sformatf("  stage%0d %s : gap=0:%0d  gap=1:%0d  gap=2-4:%0d  gap>4:%0d",
                          s, stage_label(s), g0_cnt[s], g1_cnt[s], g24_cnt[s], gbig_cnt[s]), UVM_LOW)
            `uvm_info("COV", $sformatf("  TOTAL           : gap=0:%0d  gap=1:%0d  gap=2:%0d  gap=3:%0d  gap=4:%0d  gap>4:%0d  (txns=%0d)",
                      g_val_cnt[0], g_val_cnt[1], g_val_cnt[2], g_val_cnt[3], g_val_cnt[4],
                      gbig_tot, n_gap_rec), UVM_LOW)
            // 先算成字符串再打印：XSim 的 %s 直接吃三元表达式会多补空格
            begin
                string gs;
                if (n_gap_rec == 0) gs = "N/A (no data txns in this test)";
                else               gs = gap_pass() ? "PASS" : "INCOMPLETE";
                `uvm_info("COV", $sformatf("  gap coverage : %s (phases with all 3 bins: %0d/%0d)",
                          gs, phases_full(), N_STAGE), UVM_LOW)
            end
            // 反压参数分布（附加信息：当前阶段3/4 强制 force_stall=1，
            // 因此 stall_len 恒为 4，这是现状而非统计错误；free_len 仍随机 0~3）
            `uvm_info("COV", "========== STALL / FREE DISTRIBUTION ==========", UVM_LOW)
            `uvm_info("COV", $sformatf("  stall_len draws=%0d : %s",
                      n_stall_rec, stall_hist_str()), UVM_LOW)
            `uvm_info("COV", $sformatf("  free_len  draws=%0d : 0:%0d  1:%0d  2:%0d  3:%0d",
                      n_stall_rec, f_len_cnt[0], f_len_cnt[1], f_len_cnt[2], f_len_cnt[3]), UVM_LOW)
        endfunction
    endclass

    // ---------------- 驱动器（数据 + 载钥） ----------------
    class des_driver extends uvm_driver#(des_txn);
        `uvm_component_utils(des_driver)
        virtual des_if vif;
        des_uvm_cfg  cfg;
        uvm_analysis_port#(des_txn) ap_exp;
        int unsigned n_drive;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_exp = new("ap_exp", this);
            n_drive = 0;
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual des_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "des_driver 拿不到 vif")
            if (!uvm_config_db#(des_uvm_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "des_driver 拿不到 cfg")
        endfunction
        task run_phase(uvm_phase phase);
            des_txn t;
            reset(10);
            cfg.rst_done = 1'b1;
            forever begin
                seq_item_port.get_next_item(t);
                if (t.kind == TXN_KEY) load_key(t.key);
                else drive(t);
                seq_item_port.item_done();
            end
        endtask
        task reset(int unsigned cycles = 10);
            vif.rst_n      = 1'b0;
            vif.valid_i    = 1'b0;
            vif.data_i     = '0;
            vif.load_key_i = 1'b0;
            vif.key_i      = '0;
            vif.encrypt_i  = 1'b1;
            repeat (cycles) @(posedge vif.clk);
            vif.rst_n = 1'b1;
            repeat (2) @(posedge vif.clk);
        endtask
        task load_key(bit [63:0] k);
            des_txn r;
            @(negedge vif.clk);
            vif.key_i = k; vif.load_key_i = 1'b1;
            @(negedge vif.clk);
            vif.load_key_i = 1'b0;
            wait (vif.ready_key_o == 1'b0);
            wait (vif.ready_key_o == 1'b1);
            r = des_txn::type_id::create("rekey");
            r.kind = TXN_REKEY; r.key = k;
            ap_exp.write(r);
        endtask
        task drive(des_txn t);
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
            ap_exp.write(t);   // 期望流：exp 进计分板，mode 供覆盖率
            if (t.gap > 0) repeat (t.gap) @(negedge vif.clk);
        endtask
    endclass

    // ---------------- ready 反压驱动（responder，无 sequence） ----------------
    class des_ready_driver extends uvm_driver#(des_txn);
        `uvm_component_utils(des_ready_driver)
        virtual des_if vif;
        des_uvm_cfg  cfg;
        des_uvm_coverage cov;   // 仅用于统计反压参数分布（可为 null）
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual des_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "ready_driver 拿不到 vif")
            if (!uvm_config_db#(des_uvm_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "ready_driver 拿不到 cfg")
            if (!uvm_config_db#(des_uvm_coverage)::get(this, "", "cov", cov))
                cov = null;
        endfunction
        task run_phase(uvm_phase phase);
            vif.ready_i = 1'b1;
            forever begin
                if (cfg.rand_stall_en) begin
                    cfg.gen_stall();
                    if (cov != null) cov.record_stall(cfg.stall_len, cfg.free_len);
                    @(negedge vif.clk);
                    vif.ready_i = 1'b0;
                    repeat (cfg.stall_len) @(negedge vif.clk);
                    vif.ready_i = 1'b1;
                    repeat (cfg.free_len) @(negedge vif.clk);
                end else begin
                    vif.ready_i = 1'b1;
                    @(negedge vif.clk);
                end
            end
        endtask
    endclass

    // ---------------- 监测器 ----------------
    class des_monitor extends uvm_monitor;
        `uvm_component_utils(des_monitor)
        virtual des_if vif;
        uvm_analysis_port#(des_txn) ap_obs;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_obs = new("ap_obs", this);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual des_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "monitor 拿不到 vif")
        endfunction
        task run_phase(uvm_phase phase);
            des_txn t;
            forever begin
                @(posedge vif.clk);
                if (vif.rst_n) begin
                    t = des_txn::type_id::create("obs");
                    t.mode = vif.encrypt_i;
                    if (vif.valid_o && vif.ready_i) begin
                        t.kind = TXN_DATA; t.data = vif.data_o;
                    end else if (vif.valid_o) begin
                        t.kind = TXN_STALL;
                    end else begin
                        t.kind = TXN_IDLE;
                    end
                    ap_obs.write(t);
                end
            end
        endtask
    endclass

    // ---------------- Agent ----------------
    // active agent 同时封装激励侧、ready 侧和输出监测侧，
    // env 只通过 agent 暴露的 monitor analysis port 连接检查器。
    class des_agent extends uvm_agent;
        `uvm_component_utils(des_agent)
        des_sequencer      sqr;
        des_driver         drv;
        des_ready_driver   rdy;
        des_monitor        mon;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = des_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = des_sequencer::type_id::create("sqr", this);
                drv = des_driver::type_id::create("drv", this);
                rdy = des_ready_driver::type_id::create("rdy", this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ---------------- 序列 ----------------
    class des_rand_sequence extends uvm_sequence#(des_txn);
        `uvm_object_utils(des_rand_sequence)
        bit [63:0] k_enc[], i_enc[], e_enc[];
        bit [63:0] k_dec[], i_dec[], e_dec[];
        des_uvm_cfg cfg;
        des_uvm_scoreboard sb;
        des_uvm_coverage   cov;
        virtual des_if vif;
        int unsigned       cur_stage;   // 0..3，当前激励阶段，供 gap 统计归类
        function new(string name = "des_rand_sequence");
            super.new(name);
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
        task send_data(bit[63:0] d, bit[63:0] e, bit m, bit[63:0] k);
            des_txn t;
            t = des_txn::type_id::create("t");
            start_item(t);
            t.kind = TXN_DATA; t.data = d; t.exp = e; t.mode = m; t.key = k;
            // gap 由 c_gap 约束随机决定（0/1/2-4 三档）
            // 注意：必须在 start_item 之后 randomize，才能和 sequence 的
            // 仲裁（prior）协同；先 randomize 再 start_item 会绕过仲裁。
`ifdef DES_XSIM
            // XSim 2018.3：randomize() 会崩内核，这里手写"设计意图"的分布：
            // 三种场景 gap=0 / 1 / 2~4 按 50/25/25 加权（2~4 内部均匀）。
            //
            // 重要（与 VCS 的差异）：c_gap 原文 dist { 0 := 50, 1 := 25, [2:4] := 25 }
            // 里 := 的语义是"范围内**每个值**各给该权重"，因此 VCS 上
            // 0/1/2/3/4 的实际权重是 50/25/25/25/25（三组约 33/17/50），
            // 并不是这里的 50/25/25。若要让 VCS 也按三组 50/25/25 加权，
            // 应把 c_gap 改成 [2:4] :/ 25（本次未改约束，保持原有激励不变）。
            if ($urandom_range(1, 0) == 0)      t.gap = 0;
            else if ($urandom_range(1, 0) == 0) t.gap = 1;
            else                                t.gap = $urandom_range(4, 2);
`else
            if (!t.randomize() with { kind == TXN_DATA; })
                `uvm_fatal("SEQ", "des_txn::randomize() 失败")
`endif
            // 记录本笔事务的 gap 到覆盖率组件（按当前阶段归类）
            if (cov != null) cov.record_gap(cur_stage, t.gap);
            finish_item(t);
        endtask
        task send_key(bit[63:0] k);
            des_txn t;
            // 换钥前停流排空（设计协议约束：不排空换钥会污染在途数据）
            do @(posedge vif.clk); while (!sb.idle());
            t = des_txn::type_id::create("t");
            start_item(t);
            t.kind = TXN_KEY; t.key = k;
            finish_item(t);
        endtask
        task drive_block(bit[63:0] ks[], is[], es[], bit m, int n);
            bit [63:0] cur;
            cur = 'x;
            for (int i = 0; i < n; i++) begin
                if (ks[i] !== cur) begin send_key(ks[i]); cur = ks[i]; end
                send_data(is[i], es[i], m, ks[i]);
            end
        endtask
        task body();
            if (!uvm_config_db#(des_uvm_cfg)::get(m_sequencer, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "sequence 拿不到 cfg")
            if (!uvm_config_db#(des_uvm_scoreboard)::get(m_sequencer, "", "sb", sb))
                `uvm_fatal("NOSB", "sequence 拿不到 sb")
            if (!uvm_config_db#(virtual des_if)::get(m_sequencer, "", "vif", vif))
                `uvm_fatal("NOVIF", "sequence 拿不到 vif")
            // gap 覆盖率统计组件（拿不到也不致命，只是不记录分布）
            if (!uvm_config_db#(des_uvm_coverage)::get(m_sequencer, "", "cov", cov))
                cov = null;
            load_vectors();
            wait (cfg.rst_done == 1'b1);

            `uvm_info("SEQ", $sformatf("=== 阶段1：加密向量（%0d 笔） ===", `N_ENC), UVM_LOW)
            cfg.rand_stall_en = 0;
            cur_stage = 0;
            drive_block(k_enc, i_enc, e_enc, 1'b1, `N_ENC);

            `uvm_info("SEQ", $sformatf("=== 阶段2：解密向量（%0d 笔） ===", `N_DEC), UVM_LOW)
            cur_stage = 1;
            drive_block(k_dec, i_dec, e_dec, 1'b0, `N_DEC);

            `uvm_info("SEQ", $sformatf("=== 阶段3：加密 × 随机反压（%0d 笔） ===", N_STRESS), UVM_LOW)
            send_key(k_enc[0]);
            cfg.rand_stall_en = 1;
            cfg.force_stall = 1;
            cur_stage = 2;
            for (int i = 0; i < N_STRESS; i++) send_data(i_enc[i], e_enc[i], 1'b1, k_enc[0]);
            cfg.force_stall = 0;
            cfg.rand_stall_en = 0;

            `uvm_info("SEQ", $sformatf("=== 阶段4：解密 × 随机反压（%0d 笔） ===", N_STRESS), UVM_LOW)
            send_key(k_dec[0]);
            cfg.rand_stall_en = 1;
            cfg.force_stall = 1;
            cur_stage = 3;
            for (int i = 0; i < N_STRESS; i++) send_data(i_dec[i], e_dec[i], 1'b0, k_dec[0]);
            cfg.force_stall = 0;
            cfg.rand_stall_en = 0;
        endtask
    endclass

    // ---------------- 环境 ----------------
    class des_env extends uvm_env;
        `uvm_component_utils(des_env)
        des_agent          agent;
        des_uvm_scoreboard sb;
        des_uvm_coverage   cov;
        des_uvm_cfg        cfg;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(des_uvm_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "env 拿不到 cfg")
            uvm_config_db#(des_uvm_cfg)::set(this, "*", "cfg", cfg);
            agent = des_agent::type_id::create("agent", this);
            sb  = des_uvm_scoreboard::type_id::create("sb", this);
            cov = des_uvm_coverage::type_id::create("cov", this);
            uvm_config_db#(des_uvm_scoreboard)::set(this, "*", "sb", sb);
            // sequence 在 randomize gap 后通过这个句柄回写统计
            uvm_config_db#(des_uvm_coverage)::set(this, "*", "cov", cov);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.drv.ap_exp.connect(sb.exp_export);
            agent.mon.ap_obs.connect(sb.obs_export);
        endfunction
    endclass

    // ---------------- 测试 ----------------
    class des_base_test extends uvm_test;
        `uvm_component_utils(des_base_test)
        des_env     env;
        des_uvm_cfg cfg;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cfg = des_uvm_cfg::type_id::create("cfg");
            uvm_config_db#(des_uvm_cfg)::set(this, "env", "cfg", cfg);
            env = des_env::type_id::create("env", this);
        endfunction
        function void report_phase(uvm_phase phase);
            uvm_report_server srv;
            srv = uvm_report_server::get_server();
            if (env.sb.pass() &&
                env.cov.pass() &&
                env.cov.gap_pass() &&     // 三种 gap 场景（0/1/2-4）都必须打到
                srv.get_severity_count(UVM_ERROR) == 0 &&
                srv.get_severity_count(UVM_FATAL) == 0)
                $display("\n**** UVM ENV PASS ****");
            else
                $display("\n**** UVM ENV FAIL ****");
        endfunction
    endclass

    class des_rand_test extends des_base_test;
        `uvm_component_utils(des_rand_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        task main_phase(uvm_phase phase);
            des_rand_sequence seq;
            phase.raise_objection(this);
            seq = des_rand_sequence::type_id::create("seq");
            seq.start(env.agent.sqr);
            while (!env.sb.idle()) #10;
            repeat (20) #10;
            phase.drop_objection(this);
        endtask
    endclass

endpackage
