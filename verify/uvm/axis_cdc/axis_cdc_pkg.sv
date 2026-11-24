// ============================================================================
// axis_cdc_pkg.sv —— 合并版顶层 des_axis_cdc_top 的 UVM 验证包
//
// DUT 拓扑（两个时钟域）：
//   慢域 wclk 100MHz：AXI4-Stream slave（s_axis_*）—— 本包 axis_cdc_agent 驱动
//   快域 clk  250MHz：AXI4-Stream master（m_axis_*）—— 本包 monitor/cov 观测，
//                     m_axis_tready 由 axis_cdc_rdy_driver 反压
//                     AXI4-Lite slave（控制面）—— 复用 des_axil_pkg 的 axil_agent
//
// 环境拓扑：
//   axis_cdc_env
//     ├── agent      : axis_cdc_agent   [慢域 sqr/drv + 快域 mon]
//     ├── axil_agent : axil_agent      [快域 AXIL 控制面，复用 des_axil_pkg]
//     ├── rdy        : axis_cdc_rdy_driver  [快域 m_axis_tready 反压]
//     ├── sb         : axis_cdc_scoreboard  [exp/obs 双 imp，逐笔比 data + tlast]
//     ├── cov        : axis_cdc_cov         [快域 m_axis covergroup]
//     └── vseqr      : axis_cdc_vseqr       [持有 data_sqr / axil_sqr / sb / vif]
//
// XSim 2018.3 约束（沿用项目既有结论）：
//   - 任何 randomize() 都会崩内核 —— 本包全部手写激励，不调用 randomize；
//   - cover property 不支持 —— 覆盖率只用 covergroup + 计数器；
//   - coverpoint 只采接口信号（vif.*），不采 class 成员。
// ============================================================================
`include "uvm_macros.svh"

package axis_cdc_pkg;

    import uvm_pkg::*;
    import des_axil_pkg::*;

    // 两个 analysis imp：期望流（driver 推）与观测流（monitor 推）
    `uvm_analysis_imp_decl(_exp)
    `uvm_analysis_imp_decl(_obs)

    // ========================================================================
    // 事务
    // ========================================================================
    class axis_cdc_txn extends uvm_sequence_item;
        rand bit [63:0] data;      // 灌入 DUT 的原始数据
        bit      [63:0] exp;       // 期望输出（黄金向量）
        rand bit        last;      // 灌入的 TLAST
        bit             exp_last;  // 期望输出的 TLAST
        rand int unsigned gap;     // 本笔握手后插入的空闲慢域拍数

        `uvm_object_utils_begin(axis_cdc_txn)
            `uvm_field_int(data,     UVM_DEFAULT)
            `uvm_field_int(exp,      UVM_DEFAULT)
            `uvm_field_int(last,     UVM_DEFAULT)
            `uvm_field_int(exp_last, UVM_DEFAULT)
            `uvm_field_int(gap,      UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "axis_cdc_txn");
            super.new(name);
            data = '0; exp = '0; last = 1'b0; exp_last = 1'b0; gap = 0;
        endfunction
    endclass

    typedef uvm_sequencer#(axis_cdc_txn) axis_cdc_sequencer;

    // ========================================================================
    // 计分板（新建，不复用共享的 des_uvm_scoreboard）
    // ========================================================================
    class axis_cdc_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(axis_cdc_scoreboard)

        uvm_analysis_imp_exp#(axis_cdc_txn, axis_cdc_scoreboard) exp_export;
        uvm_analysis_imp_obs#(axis_cdc_txn, axis_cdc_scoreboard) obs_export;

        bit [63:0] q_exp[$];
        bit        q_last[$];

        int unsigned n_push;      // 期望入队数（= driver 已开始驱动的笔数）
        int unsigned n_cmp;       // 实际比对数
        int unsigned n_err;       // data 错误
        int unsigned n_tlast_err; // TLAST 错误
        int unsigned n_extra;     // 无期望的多余输出
        int unsigned n_xz;        // X/Z

        function new(string name, uvm_component parent);
            super.new(name, parent);
            exp_export = new("exp_export", this);
            obs_export = new("obs_export", this);
        endfunction

        function void write_exp(axis_cdc_txn t);
            q_exp.push_back(t.exp);
            q_last.push_back(t.exp_last);
            n_push++;
        endfunction

        function void write_obs(axis_cdc_txn t);
            bit [63:0] e;
            bit        el;
            if (q_exp.size() == 0) begin
                n_extra++;
                `uvm_error("AXIS_CDC_SCB",
                    $sformatf("EXTRA OUTPUT: data=%h last=%b（无待比对期望）", t.data, t.last))
                return;
            end
            e  = q_exp.pop_front();
            el = q_last.pop_front();
            n_cmp++;

            if ($isunknown(t.data) || $isunknown(e)) begin
                n_xz++;
                `uvm_error("AXIS_CDC_SCB",
                    $sformatf("X/Z #%0d : DUT=%h expect=%h", n_cmp-1, t.data, e))
            end else if (t.data !== e) begin
                n_err++;
                `uvm_error("AXIS_CDC_SCB",
                    $sformatf("DATA MISMATCH #%0d : DUT=%h expect=%h", n_cmp-1, t.data, e))
            end

            if (t.last !== el) begin
                n_tlast_err++;
                `uvm_error("AXIS_CDC_SCB",
                    $sformatf("TLAST MISMATCH #%0d : DUT=%b expect=%b", n_cmp-1, t.last, el))
            end
        endfunction

        function bit idle();
            return (n_push == n_cmp) && (q_exp.size() == 0);
        endfunction

        function bit pass();
            return (n_err == 0) && (n_tlast_err == 0) && (n_extra == 0) &&
                   (n_xz == 0) && (n_push == n_cmp) && (n_push > 0);
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("AXIS_CDC_SCB", "========== SCOREBOARD ==========", UVM_LOW)
            `uvm_info("AXIS_CDC_SCB", $sformatf("  push / cmp   : %0d / %0d", n_push, n_cmp), UVM_LOW)
            `uvm_info("AXIS_CDC_SCB", $sformatf("  data errors  : %0d", n_err),       UVM_LOW)
            `uvm_info("AXIS_CDC_SCB", $sformatf("  TLAST errors : %0d", n_tlast_err), UVM_LOW)
            `uvm_info("AXIS_CDC_SCB", $sformatf("  X/Z          : %0d", n_xz),        UVM_LOW)
            `uvm_info("AXIS_CDC_SCB", $sformatf("  extra output : %0d", n_extra),     UVM_LOW)
        endfunction
    endclass

    // ========================================================================
    // 慢域数据驱动
    //   - 负沿改 tvalid/tdata/tlast，正沿等 tvalid && s_axis_tready；
    //   - 握手成功后负沿撤 valid；
    //   - 每笔在握手前把 {exp, exp_last} 通过 analysis port 送给计分板，
    //     保证期望顺序与灌入顺序一致；
    //   - gap 个慢域空拍后开始下一笔。
    // ========================================================================
    class axis_cdc_driver extends uvm_driver#(axis_cdc_txn);
        `uvm_component_utils(axis_cdc_driver)

        virtual axis_cdc_if vif;
        uvm_analysis_port#(axis_cdc_txn) ap_exp;
        int unsigned n_drive;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_exp = new("ap_exp", this);
            n_drive = 0;
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "axis_cdc_driver 拿不到 vif")
        endfunction

        task run_phase(uvm_phase phase);
            axis_cdc_txn t;
            reset_slow();
            forever begin
                `uvm_info("AXIS_CDC_DRV", "wait next item", UVM_HIGH)
                seq_item_port.get_next_item(t);
                `uvm_info("AXIS_CDC_DRV",
                    $sformatf("got data=%h last=%b gap=%0d", t.data, t.last, t.gap), UVM_HIGH)
                drive_beat(t);
                seq_item_port.item_done();
            end
        endtask

        task reset_slow();
            vif.s_axis_tvalid = 1'b0;
            vif.s_axis_tdata  = 64'h0;
            vif.s_axis_tlast  = 1'b0;
            wait (vif.wrst_n === 1'b1);
            repeat (4) @(negedge vif.wclk);
        endtask

        task drive_beat(axis_cdc_txn t);
            @(negedge vif.wclk);
            vif.s_axis_tdata  = t.data;
            vif.s_axis_tlast  = t.last;
            vif.s_axis_tvalid = 1'b1;

            // 期望先入队，确保 scoreboard 的期望顺序 == 灌入顺序
            ap_exp.write(t);

            @(posedge vif.wclk);
            while (!(vif.s_axis_tvalid && vif.s_axis_tready))
                @(posedge vif.wclk);

            @(negedge vif.wclk);
            vif.s_axis_tvalid = 1'b0;
            vif.s_axis_tdata  = 64'h0;
            vif.s_axis_tlast  = 1'b0;
            n_drive++;

            if (t.gap > 0)
                repeat (t.gap) @(negedge vif.wclk);
        endtask
    endclass

    // ========================================================================
    // 快域输出监测（在 clk 正沿采样 m_axis 握手）
    // ========================================================================
    class axis_cdc_monitor extends uvm_monitor;
        `uvm_component_utils(axis_cdc_monitor)

        virtual axis_cdc_if vif;
        uvm_analysis_port#(axis_cdc_txn) ap_obs;

        int unsigned n_beat;    // 输出握手拍数
        int unsigned n_stall;   // m_axis_tvalid && !m_axis_tready 的快域拍数
        int unsigned n_idle;    // !m_axis_tvalid 的快域拍数
        int unsigned n_last;    // 输出 TLAST=1 的握手拍数

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_obs = new("ap_obs", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "axis_cdc_monitor 拿不到 vif")
        endfunction

        task run_phase(uvm_phase phase);
            axis_cdc_txn t;
            forever begin
                @(posedge vif.clk);
                if (vif.rst_n) begin
                    if (vif.m_axis_tvalid && !vif.m_axis_tready)
                        n_stall++;
                    else if (!vif.m_axis_tvalid)
                        n_idle++;

                    if (vif.m_axis_tvalid && vif.m_axis_tready) begin
                        t = axis_cdc_txn::type_id::create("obs");
                        t.data     = vif.m_axis_tdata;
                        t.last     = vif.m_axis_tlast;
                        t.exp      = 64'h0;
                        t.exp_last = 1'b0;
                        ap_obs.write(t);
                        n_beat++;
                        if (vif.m_axis_tlast) n_last++;
                    end
                end
            end
        endtask
    endclass

    // ========================================================================
    // 慢域数据 agent（sqr / drv / mon）
    // ========================================================================
    class axis_cdc_agent extends uvm_agent;
        `uvm_component_utils(axis_cdc_agent)

        axis_cdc_sequencer sqr;
        axis_cdc_driver    drv;
        axis_cdc_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = axis_cdc_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = axis_cdc_sequencer::type_id::create("sqr", this);
                drv = axis_cdc_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ========================================================================
    // 快域 m_axis_tready 反压驱动
    //   固定 3/10 拍反压 + TLAST 拍额外 3 拍反压（定向打 tlast×stall 交叉）。
    //   后者保证 covergroup 的 cross(last, stall) 一定被采到。
    // ========================================================================
    class axis_cdc_rdy_driver extends uvm_component;
        `uvm_component_utils(axis_cdc_rdy_driver)

        virtual axis_cdc_if vif;
        int unsigned cyc;
        int unsigned tail_hold;
        bit          tail_armed;
        int unsigned n_stall_drv;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cyc = 0;
            tail_hold = 0;
            tail_armed = 1'b1;
            n_stall_drv = 0;
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "axis_cdc_rdy_driver 拿不到 vif")
        endfunction

        task run_phase(uvm_phase phase);
            vif.m_axis_tready = 1'b1;
            forever begin
                @(negedge vif.clk);
                if (!vif.rst_n) begin
                    cyc        = 0;
                    tail_hold  = 0;
                    tail_armed = 1'b1;
                    vif.m_axis_tready = 1'b1;
                end else begin
                    cyc = cyc + 1;
                    if (tail_hold > 0) begin
                        // TLAST 拍定向反压
                        vif.m_axis_tready = 1'b0;
                        tail_hold = tail_hold - 1;
                        n_stall_drv++;
                    end else if (vif.m_axis_tvalid && vif.m_axis_tlast && tail_armed) begin
                        // 看到带 TLAST 的有效拍：本拍起连续 3 拍不 ready
                        vif.m_axis_tready = 1'b0;
                        tail_hold  = 2;
                        tail_armed = 1'b0;
                        n_stall_drv++;
                    end else begin
                        if (!vif.m_axis_tlast)
                            tail_armed = 1'b1;
                        // 3/10 的固定反压窗口（保证 stall 一定发生）
                        if ((cyc % 10) < 3) begin
                            vif.m_axis_tready = 1'b0;
                            n_stall_drv++;
                        end else begin
                            vif.m_axis_tready = 1'b1;
                        end
                    end
                end
            end
        endtask
    endclass

    // ========================================================================
    // 覆盖率：快域 m_axis
    // ========================================================================
    class axis_cdc_cov extends uvm_component;
        `uvm_component_utils(axis_cdc_cov)

        virtual axis_cdc_if vif;
        int unsigned n_obs;
        // XSim 2018.3 的覆盖率为"按调用作用域"取值：在别的组件里调用
        // env.cov.get_coverage() 会读回 0.00%，而本组件自己 report_phase
        // 里读是 100.00%。因此在这里取一次并缓存，test 直接读 cov_cached。
        real cov_cached;

        covergroup cg;
            option.per_instance = 1;

            cp_hs   : coverpoint (vif.m_axis_tvalid &&  vif.m_axis_tready)
                        { bins xfer  = {1'b1}; }
            cp_stall: coverpoint (vif.m_axis_tvalid && !vif.m_axis_tready)
                        { bins stall = {1'b1}; }
            cp_idle : coverpoint (!vif.m_axis_tvalid)
                        { bins idle  = {1'b1}; }
            cp_last : coverpoint vif.m_axis_tlast
                        { bins no_last = {1'b0}; bins last = {1'b1}; }

            // TLAST × 握手 / TLAST × 反压
            x_last_hs   : cross cp_last, cp_hs;
            x_last_stall: cross cp_last, cp_stall;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
            n_obs = 0;
            cov_cached = 0.0;
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "axis_cdc_cov 拿不到 vif")
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

        function void report_phase(uvm_phase phase);
            cov_cached = cg.get_coverage();
            `uvm_info("AXIS_CDC_COV", $sformatf("samples=%0d coverage=%0.2f%%",
                      n_obs, cov_cached), UVM_LOW)
        endfunction
    endclass

    // ========================================================================
    // 数据 sequence：把一组 beat 逐笔发到慢域 driver
    //   add_beat() 只做入队；body() 逐笔 start_item/finish_item。
    //   不使用 randomize：gap 用 $urandom_range 直接取值。
    // ========================================================================
    class axis_cdc_seq extends uvm_sequence#(axis_cdc_txn);
        `uvm_object_utils(axis_cdc_seq)

        bit [63:0] q_data[$];
        bit [63:0] q_exp[$];
        bit        q_last[$];

        function new(string name = "axis_cdc_seq");
            super.new(name);
        endfunction

        function void add_beat(bit [63:0] d, bit [63:0] e, bit l);
            q_data.push_back(d);
            q_exp.push_back(e);
            q_last.push_back(l);
        endfunction

        function void clear_beats();
            q_data.delete();
            q_exp.delete();
            q_last.delete();
        endfunction

        task body();
            axis_cdc_txn t;
            int unsigned i;
            int unsigned n;
            n = q_data.size();
            `uvm_info("AXIS_CDC_SEQ", $sformatf("body start n=%0d", n), UVM_HIGH)
            for (i = 0; i < n; i++) begin
                t = axis_cdc_txn::type_id::create($sformatf("beat%0d", i));
                `uvm_info("AXIS_CDC_SEQ", $sformatf("start_item %0d", i), UVM_HIGH)
                start_item(t);
                t.data     = q_data[i];
                t.exp      = q_exp[i];
                t.last     = q_last[i];
                t.exp_last = q_last[i];
                // 0/1/2 拍空隔；XSim 上不用 randomize
                t.gap      = $urandom_range(2, 0);
                finish_item(t);
                `uvm_info("AXIS_CDC_SEQ", $sformatf("finish_item %0d", i), UVM_HIGH)
            end
            `uvm_info("AXIS_CDC_SEQ", "body end", UVM_HIGH)
        endtask
    endclass

    // ========================================================================
    // AXIL 单笔写 / 读 sequence（控制面用）
    // ========================================================================
    class axis_cdc_axil_wr_seq extends uvm_sequence#(axil_seq_item);
        `uvm_object_utils(axis_cdc_axil_wr_seq)

        bit [31:0] addr;
        bit [31:0] data;

        function new(string name = "axis_cdc_axil_wr_seq");
            super.new(name);
            addr = 32'h0; data = 32'h0;
        endfunction

        task body();
            axil_seq_item it;
            it = axil_seq_item::type_id::create("wr");
            start_item(it);
            it.op    = AXIL_WRITE;
            it.addr  = addr;
            it.wdata = data;
            it.wstrb = 4'hF;
            finish_item(it);
        endtask
    endclass

    class axis_cdc_axil_rd_seq extends uvm_sequence#(axil_seq_item);
        `uvm_object_utils(axis_cdc_axil_rd_seq)

        bit [31:0] addr;
        bit [31:0] rdata;

        function new(string name = "axis_cdc_axil_rd_seq");
            super.new(name);
            addr = 32'h0; rdata = 32'h0;
        endfunction

        task body();
            axil_seq_item it;
            it = axil_seq_item::type_id::create("rd");
            start_item(it);
            it.op   = AXIL_READ;
            it.addr = addr;
            finish_item(it);
            rdata = it.rdata;
        endtask
    endclass

    // ========================================================================
    // 虚拟 sequencer：只放句柄，不产生 item
    // ========================================================================
    class axis_cdc_vseqr extends uvm_sequencer;
        `uvm_component_utils(axis_cdc_vseqr)

        axis_cdc_sequencer data_sqr;
        axil_sequencer     axil_sqr;
        axis_cdc_scoreboard sb;
        virtual axis_cdc_if vif;

        bit          rdy_wclk_ok;      // ready_key_o_wclk 观测到过高电平
        int unsigned rdy_wclk_cycles;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            rdy_wclk_ok = 1'b0;
            rdy_wclk_cycles = 0;
        endfunction
    endclass

    // ========================================================================
    // 虚拟 sequence：控制面配置 + 数据面灌数的完整测试流
    // ========================================================================
    class axis_cdc_vseq extends uvm_sequence;
        `uvm_object_utils(axis_cdc_vseq)
        `uvm_declare_p_sequencer(axis_cdc_vseqr)

        bit [63:0] k_enc[];
        bit [63:0] i_enc[];
        bit [63:0] e_enc[];
        bit [63:0] k_dec[];
        bit [63:0] i_dec[];
        bit [63:0] e_dec[];

        function new(string name = "axis_cdc_vseq");
            super.new(name);
        endfunction

        function void load_vectors();
            k_enc = new[28]; i_enc = new[28]; e_enc = new[28];
            k_dec = new[14]; i_dec = new[14]; e_dec = new[14];
            $readmemh("keys.mem",  k_enc);
            $readmemh("ins.mem",   i_enc);
            $readmemh("exps.mem",  e_enc);
            $readmemh("dkeys.mem", k_dec);
            $readmemh("dins.mem",  i_dec);
            $readmemh("dexps.mem", e_dec);
        endfunction

        // ---------------- 控制面基础操作 ----------------
        task axil_write(bit [31:0] a, bit [31:0] d);
            axis_cdc_axil_wr_seq wr;
            wr = axis_cdc_axil_wr_seq::type_id::create("wr");
            wr.addr = a;
            wr.data = d;
            wr.start(p_sequencer.axil_sqr);
        endtask

        task axil_read(bit [31:0] a, output bit [31:0] d);
            axis_cdc_axil_rd_seq rd;
            rd = axis_cdc_axil_rd_seq::type_id::create("rd");
            rd.addr = a;
            rd.start(p_sequencer.axil_sqr);
            d = rd.rdata;
        endtask

        task write_ctrl(bit mode, bit enable);
            bit [31:0] v;
            v = {30'h0, enable, mode};
            axil_write(32'h08, v);
        endtask

        // 写 KEY_LO / KEY_HI，等 key schedule 完成（STATUS[0]=1 且 STATUS[2]=0）
        task write_key(bit [63:0] k);
            bit [31:0] st;
            int unsigned tries;
            int unsigned i;

            axil_write(32'h00, k[31:0]);
            axil_write(32'h04, k[63:32]);   // 写高字触发 load_key

            // load_key 在写 B 响应后 1 拍才进 key_ram_gen，先等它把 ready 拉低，
            // 避免读到"旧密钥仍 ready"的假就绪窗口。
            repeat (8) @(posedge p_sequencer.vif.clk);

            tries = 0;
            st = 32'h0;
            while (tries < 200) begin
                axil_read(32'h0C, st);
                if (st[3] === 1'b1) begin
                    `uvm_error("AXIS_CDC_VSEQ",
                        $sformatf("换钥被拒绝（REKEY_ERR），key=%h", k))
                end
                if ((st[0] === 1'b1) && (st[2] === 1'b0))
                    return;
                tries++;
                repeat (2) @(posedge p_sequencer.vif.clk);
            end
            `uvm_error("AXIS_CDC_VSEQ", $sformatf("KEY_READY 超时，key=%h", k))
        endtask

        // 等计分板排空：期望 == 实际，且队列空
        task wait_drain();
            int unsigned guard;
            guard = 0;
            while (!p_sequencer.sb.idle() && guard < 200000) begin
                @(posedge p_sequencer.vif.clk);
                guard++;
            end
            if (guard >= 200000)
                `uvm_error("AXIS_CDC_VSEQ", "scoreboard 排空超时")
            // 等 DUT 的 rdata_v / FIFO 真正空掉（busy_any 归零）再换钥
            repeat (40) @(posedge p_sequencer.vif.clk);
        endtask

        task wait_rdy_wclk();
            int unsigned i;
            p_sequencer.rdy_wclk_ok = 1'b0;
            p_sequencer.rdy_wclk_cycles = 0;
            for (i = 0; i < 1000; i++) begin
                @(posedge p_sequencer.vif.wclk);
                if (p_sequencer.vif.ready_key_o_wclk === 1'b1) begin
                    p_sequencer.rdy_wclk_ok = 1'b1;
                    p_sequencer.rdy_wclk_cycles++;
                    if (p_sequencer.rdy_wclk_cycles >= 4) break;
                end
            end
            if (!p_sequencer.rdy_wclk_ok)
                `uvm_error("AXIS_CDC_VSEQ", "ready_key_o_wclk 在慢域始终未拉高")
        endtask

        // 一个完整段：排空 → 写密钥 → 等 ready → 配 CTRL → 灌 n 笔 → 排空
        task run_seg(bit [63:0] key, bit enc_mode, int unsigned base,
                     int unsigned n, bit [63:0] ins[], bit [63:0] exps[]);
            axis_cdc_seq dseq;
            int unsigned i;
            bit l;

            wait_drain();
            write_key(key);
            write_ctrl(enc_mode, 1'b1);

            dseq = axis_cdc_seq::type_id::create("dseq");
            for (i = 0; i < n; i++) begin
                l = ((i % 4) == 3) ? 1'b1 : 1'b0;   // 每 4 拍一个 TLAST
                dseq.add_beat(ins[base+i], exps[base+i], l);
            end

            // XSim 2018.3 workaround：同一 data sequencer 上连续 start 第 3 个
            // 子 sequence 时，若 start 与前一拍 AXIL 事务在同一零延时区域内
            // 发起，UVM 1.2 的 grant 唤醒会丢事件（start_item 永久阻塞在
            // wait_for_grant；已验证 delay 后不再复现）。这里留 16 个快域
            // 周期让 sequencer 仲裁进程先回到 wait 状态。
            repeat (16) @(posedge p_sequencer.vif.clk);

            `uvm_info("AXIS_CDC_VSEQ",
                $sformatf("段开始：base=%0d n=%0d mode=%0d key=%h",
                          base, n, enc_mode, key), UVM_LOW)

            dseq.start(p_sequencer.data_sqr);
            `uvm_info("AXIS_CDC_VSEQ",
                $sformatf("段数据完成：base=%0d n=%0d", base, n), UVM_LOW)
            wait_drain();
            `uvm_info("AXIS_CDC_VSEQ",
                $sformatf("段排空完成：base=%0d n=%0d", base, n), UVM_LOW)
        endtask

        task body();
            load_vectors();

            // 等两个域的复位都释放
            wait (p_sequencer.vif.wrst_n === 1'b1);
            wait (p_sequencer.vif.rst_n === 1'b1);
            repeat (30) @(posedge p_sequencer.vif.clk);
            #200;

            `uvm_info("AXIS_CDC_VSEQ", "=== 加密段1：keys[0..11]（key 1334...）===", UVM_LOW)
            run_seg(k_enc[0], 1'b1, 0, 12, i_enc, e_enc);
            // 第一次换钥后检查反向状态 ready_key_o_wclk（快→慢 CDC 通道）
            wait_rdy_wclk();

            `uvm_info("AXIS_CDC_VSEQ", "=== 加密段2：keys[12..19]（key FFFF...）===", UVM_LOW)
            run_seg(k_enc[12], 1'b1, 12, 8, i_enc, e_enc);

            `uvm_info("AXIS_CDC_VSEQ", "=== 加密段3：keys[20..27]（key 0123...）===", UVM_LOW)
            run_seg(k_enc[20], 1'b1, 20, 8, i_enc, e_enc);

            `uvm_info("AXIS_CDC_VSEQ", "=== 解密段1：dkeys[0..7]（key 1334...）===", UVM_LOW)
            run_seg(k_dec[0], 1'b0, 0, 8, i_dec, e_dec);

            `uvm_info("AXIS_CDC_VSEQ", "=== 解密段2：dkeys[8..13]（key FFFF...）===", UVM_LOW)
            run_seg(k_dec[8], 1'b0, 8, 6, i_dec, e_dec);

            `uvm_info("AXIS_CDC_VSEQ", "=== 全部 42 笔灌完，等待最后排空 ===", UVM_LOW)
        endtask
    endclass

    // ========================================================================
    // 环境
    // ========================================================================
    class axis_cdc_env extends uvm_env;
        `uvm_component_utils(axis_cdc_env)

        axis_cdc_agent      agent;
        axil_agent          axil_agent_h;
        axis_cdc_rdy_driver rdy;
        axis_cdc_scoreboard sb;
        axis_cdc_cov        cov;
        axis_cdc_vseqr      vseqr;

        virtual axis_cdc_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "env 拿不到 axis_cdc_if")

            agent        = axis_cdc_agent::type_id::create("agent", this);
            axil_agent_h = axil_agent::type_id::create("axil_agent", this);
            rdy          = axis_cdc_rdy_driver::type_id::create("rdy", this);
            sb           = axis_cdc_scoreboard::type_id::create("sb", this);
            cov          = axis_cdc_cov::type_id::create("cov", this);
            vseqr        = axis_cdc_vseqr::type_id::create("vseqr", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            // 期望流（driver）/ 观测流（monitor）→ 计分板
            agent.drv.ap_exp.connect(sb.exp_export);
            agent.mon.ap_obs.connect(sb.obs_export);

            // 虚拟 sequencer 句柄
            vseqr.data_sqr = agent.sqr;
            vseqr.axil_sqr = axil_agent_h.sqr;
            vseqr.sb       = sb;
            vseqr.vif      = vif;
        endfunction
    endclass

    // ========================================================================
    // Test
    // ========================================================================
    class axis_cdc_test extends uvm_test;
        `uvm_component_utils(axis_cdc_test)

        axis_cdc_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            virtual axis_cdc_if vif;
            virtual axil_if     axif;
            super.build_phase(phase);

            // TB 先把两个 vif 放到 "uvm_test_top*"，这里取到后统一下发给 env 子树。
            if (!uvm_config_db#(virtual axis_cdc_if)::get(this, "", "vif", vif))
                `uvm_fatal("AXIS_CDC_NOVIF", "test 拿不到 axis_cdc_if")
            if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", axif))
                `uvm_fatal("AXIS_CDC_NOVIF", "test 拿不到 axil_if")
            uvm_config_db#(virtual axis_cdc_if)::set(this, "env*", "vif", vif);
            uvm_config_db#(virtual axil_if)::set(this, "env*", "axil_vif", axif);

            env = axis_cdc_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_top.print_topology();
        endfunction

        task main_phase(uvm_phase phase);
            axis_cdc_vseq vseq;

            phase.raise_objection(this);

            vseq = axis_cdc_vseq::type_id::create("vseq");
            vseq.start(env.vseqr);

            // 让最后几拍反压/覆盖率采样完
            repeat (300) @(posedge env.vseqr.vif.clk);

            phase.drop_objection(this);
        endtask

        // XSim 2018.3 workaround：covergroup 覆盖率按"调用作用域"取值——
        // 在 test 里调 env.cov.get_coverage() 会读回 0.00%，而 cov 组件自己的
        // report_phase 里读是 100.00%。report_phase 自底向上执行，cov 先跑，
        // 因此在这里用 cov 缓存的 cov_cached 做最终判定。
        function void report_phase(uvm_phase phase);
            uvm_report_server srv;
            int unsigned n_uvm_err;
            bit ok;

            srv = uvm_report_server::get_server();
            n_uvm_err = srv.get_severity_count(UVM_ERROR) +
                        srv.get_severity_count(UVM_FATAL);

            ok = env.sb.pass() &&
                 (env.sb.n_push >= 42) &&
                 (env.agent.mon.n_stall > 0) &&
                 env.vseqr.rdy_wclk_ok &&
                 (env.cov.cov_cached > 0.0) &&
                 (n_uvm_err == 0);

            $display(" ");
            $display("================ AXIS-CDC UVM SUMMARY ================");
            $display("  beats pushed/cmp : %0d / %0d", env.sb.n_push, env.sb.n_cmp);
            $display("  data errors      : %0d", env.sb.n_err);
            $display("  TLAST errors     : %0d", env.sb.n_tlast_err);
            $display("  X/Z              : %0d", env.sb.n_xz);
            $display("  extra outputs    : %0d", env.sb.n_extra);
            $display("  output beats     : %0d  (TLAST=1: %0d)",
                     env.agent.mon.n_beat, env.agent.mon.n_last);
            $display("  stalls           : %0d cycles", env.agent.mon.n_stall);
            $display("  idle cycles      : %0d", env.agent.mon.n_idle);
            $display("  ready_key wclk   : %0d cycles / ok=%0d",
                     env.vseqr.rdy_wclk_cycles, env.vseqr.rdy_wclk_ok);
            $display("  coverage         : %0.2f%%  (samples=%0d)",
                     env.cov.cov_cached, env.cov.n_obs);
            $display("  UVM errors       : %0d", n_uvm_err);
            $display("======================================================");

            if (ok)
                $display("**** AXIS CDC UVM PASS : %0d beats, data_err=0, tlast_err=0, pushed==cmp ****",
                         env.sb.n_push);
            else
                $display("**** AXIS CDC UVM FAIL : push=%0d cmp=%0d data_err=%0d tlast_err=%0d xz=%0d extra=%0d stall=%0d cov=%0.2f uvm_err=%0d ****",
                         env.sb.n_push, env.sb.n_cmp, env.sb.n_err, env.sb.n_tlast_err,
                         env.sb.n_xz, env.sb.n_extra, env.agent.mon.n_stall,
                         env.cov.cov_cached, n_uvm_err);
        endfunction
    endclass

endpackage
