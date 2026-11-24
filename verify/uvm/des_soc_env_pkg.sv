// ============================================================================
// des_soc_env_pkg.sv —— 双 agent 验证环境（数据面 + 控制面）
//
// 拓扑（这就是被问"多 agent 怎么连"时要画的那张图）：
//
//   des_soc_env (uvm_env)
//     ├── data_agent : des_agent       [UVM_ACTIVE]  数据面 AXI4-Stream
//     │     └── sqr / drv / rdy / mon
//     ├── axil_agent : axil_agent      [UVM_ACTIVE]  控制面 AXI4-Lite
//     │     └── sqr / drv / mon
//     ├── vseqr      : des_virtual_sequencer          只持有两个 sqr 的句柄，
//     │                                              自己不是 #(ITEM) 类型
//     ├── sb         : des_soc_scoreboard              数据面比对
//     └── cov        : des_soc_coverage                数据面覆盖
//
// 为什么需要 virtual sequencer（面试口径）：
//   数据 flow 和控制 flow 是两个独立 sequencer，一个 test 里要"先配寄存器、
//   再灌数据、中途改寄存器"就必须同时持有两个句柄。virtual sequencer 不产生
//   item，它只是句柄容器；virtual sequence 用 `p_sequencer` 拿到它，再用
//   `uvm_do_on(子sequence, p_sequencer.axil_sqr)` 指定跑在哪条总线上。
//
// factory override（面试口径）：
//   本文件末尾的 des_axil_reg_override_config 演示了按需替换。真实动机不是
//   "为了用而用"，而是：DUT 有两版寄存器映射（比如调试版多了 REKEY_GUARD），
//   test 不改一行代码，只 override 掉 axil_driver 派生的 item 类型即可。
// ============================================================================
package des_soc_env_pkg;

    import uvm_pkg::*;
    import des_uvm_pkg::*;         // des_agent / des_txn / des_uvm_cfg / scoreboard / cov
    import des_axil_pkg::*;
    import des_ral_frontdoor_pkg::*;
    import des_ral_pkg::*;
    import des_ral_adapter_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- 虚拟 sequencer ----------------
    class des_virtual_sequencer extends uvm_sequencer;
        `uvm_component_utils(des_virtual_sequencer)

        des_sequencer  data_sqr;    // des_uvm_pkg 里的 typedef uvm_sequencer#(des_txn)
        axil_sequencer axil_sqr;
        des_reg_block  ral;         // 句柄容器：virtual sequence 经它访问 RAL

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    // ---------------- 配置覆盖演示 ----------------
    // 用法：test 的 build_phase 里
    //   set_type_override_by_type(axil_seq_item::get_type(),
    //                             axil_seq_item_dbg::get_type());
    // 之后所有 axil_seq_item::type_id::create() 都会造出 dbg 版本，
    // 而 driver/monitor 的代码一行不改。
    class axil_seq_item_dbg extends axil_seq_item;
        `uvm_object_utils(axil_seq_item_dbg)
        bit dbg_tag;    // 仅供打印区分，证明 override 生效
        function new(string name = "axil_seq_item_dbg");
            super.new(name);
        endfunction
        function string convert2string();
            return $sformatf("[DBG] %s addr=0x%08h wdata=0x%08h rdata=0x%08h",
                             op.name(), addr, wdata, rdata);
        endfunction
    endclass

    // ---------------- 环境 ----------------
    class des_soc_env extends uvm_env;
        `uvm_component_utils(des_soc_env)

        des_agent              data_agent;
        axil_agent             axil_agent_h;
        des_virtual_sequencer  vseqr;
        des_uvm_scoreboard     sb;
        des_uvm_coverage       cov;
        des_uvm_cfg            cfg;
        des_reg_block          ral;
        des_ral_adapter        adapter;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db#(des_uvm_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("SOC_NOCFG", "env 拿不到 cfg")
            uvm_config_db#(des_uvm_cfg)::set(this, "*", "cfg", cfg);

            data_agent   = des_agent::type_id::create("data_agent", this);
            axil_agent_h = axil_agent::type_id::create("axil_agent", this);
            vseqr        = des_virtual_sequencer::type_id::create("vseqr", this);
            sb           = des_uvm_scoreboard::type_id::create("sb", this);
            cov          = des_uvm_coverage::type_id::create("cov", this);

            uvm_config_db#(des_uvm_scoreboard)::set(this, "*", "sb", sb);

            // RAL：从 config_db 取（test 里建好并配好 adapter/map），没有就本地建
            if (!uvm_config_db#(des_reg_block)::get(this, "", "ral", ral)) begin
                ral = des_reg_block::type_id::create("ral");
                ral.configure(null, "");
                ral.build();
                ral.lock_model();
            end
            uvm_config_db#(des_reg_block)::set(this, "*", "ral", ral);

            adapter = des_ral_adapter::type_id::create("adapter");
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            // 数据面：driver 期望流 + monitor 观测流 接到 scoreboard
            data_agent.drv.ap_exp.connect(sb.exp_export);
            data_agent.mon.ap_obs.connect(sb.obs_export);

            // 虚拟 sequencer 握两个真 sequencer 的句柄
            vseqr.data_sqr = data_agent.sqr;
            vseqr.axil_sqr = axil_agent_h.sqr;
            vseqr.ral      = ral;

            // RAL 与总线的绑定：map 的 sequencer = axil sqr，adapter = 本 adapter
            // 这一行就是"RAL 怎么知道去哪条总线发事务"的答案
            ral.default_map.set_sequencer(axil_agent_h.sqr, adapter);
            // auto_predict=1：读/写事务完成后由 map 自动回填镜像。
            // 注意：若走 frontdoor，do_read 的 auto_predict 分支仍会执行，
            // 但 rw.value[0] 由 frontdoor 直接写入（对象语义，绕开 ref 缺陷）。
            ral.default_map.set_auto_predict(1);
            `uvm_info("SOC_ENV", $sformatf("RAL map 绑定: ral=%s map=%s sqr=%s adp=%s",
                      (ral==null)?"NULL":"ok",
                      (ral.default_map==null)?"NULL":"ok",
                      (ral.default_map.get_sequencer()==null)?"NULL":"ok",
                      (ral.default_map.get_adapter()==null)?"NULL":"ok"), UVM_LOW)
        endfunction

    endclass

    // ---------------- 虚拟序列示例 ----------------
    // 演示"配置 + 数据"在同一条测试流里协调
    class des_cfg_then_data_vseq extends uvm_sequence;
        `uvm_object_utils(des_cfg_then_data_vseq)

        `uvm_declare_p_sequencer(des_virtual_sequencer)

        function new(string name = "des_cfg_then_data_vseq");
            super.new(name);
        endfunction

        task body();
            // 1) 控制面：经 RAL 写密钥（这会通过 adapter 变成 AXI4-Lite 事务）
            uvm_status_e st;
            bit [63:0] k = 64'h133457799BBCDFF1;
            if (p_sequencer == null)
                `uvm_fatal("VSEQ", "p_sequencer 为空，virtual sequencer 没接好")
            if (p_sequencer.ral == null)
                `uvm_fatal("VSEQ", "p_sequencer.ral 为空，RAL 没接进 vseqr")

            p_sequencer.ral.key_lo.write(st, k[31:0]);
            p_sequencer.ral.key_hi.write(st, k[63:32]);   // 写高字触发换钥
            p_sequencer.ral.ctrl.write(st, 32'h1);        // MODE=1 加密
            `uvm_info("VSEQ", "经 RAL 配置完成", UVM_LOW)

            // 2) 数据面：从控制面切到数据面（同一 virtual sequence 里协调两条总线）
            `uvm_info("VSEQ", "控制面→数据面切换完成", UVM_LOW)
        endtask
    endclass

endpackage
