// ============================================================================
// des_axil_agent_pkg.sv —— AXI4-Lite 控制面 agent（UVM 第二个 agent）
//
// 与数据面 des_uvm_pkg 的 des_agent 并列，构成双 agent 拓扑：
//
//   des_env
//     ├── data_agent  (des_agent)      数据面 AXI4-Stream 激励 + 反压 + 监测
//     ├── axil_agent  (本包)            控制面 AXI4-Lite 激励 + 监测
//     ├── virtual_sequencer             同时持有两个 sequencer 的句柄
//     └── scoreboard / coverage
//
// 本包只含控制面：item、driver、monitor、sequencer、agent。
// AXI4-Lite 的读和写用同一个 item 类型（op 字段区分），因为从机的
// AW/W 与 AR 通道彼此独立、可并发，用两个类型反而要在 driver 里分两路 fork。
//
// 已知边界：单 outstanding（一次只做一笔，等 B/R 响应回来才发下一笔）。
// 这不是 AXI4-Lite 的限制（它允许 outstanding），是我为了先把 RAL 跑通做的
// 简化；真实项目应支持多笔 outstanding，并用 ID 之外的顺序表管理响应。
// ============================================================================
package des_axil_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum { AXIL_WRITE, AXIL_READ } axil_op_e;

    // ---------------- 事务 ----------------
    class axil_seq_item extends uvm_sequence_item;
        rand axil_op_e      op;
        rand bit [31:0]     addr;
        rand bit [31:0]     wdata;
        rand bit [3:0]      wstrb;
             bit [31:0]     rdata;
             bit [1:0]      bresp;
             bit [1:0]      rresp;
             bit            is_error;   // 由 driver 根据 bresp/rresp 置位

        `uvm_object_utils_begin(axil_seq_item)
            `uvm_field_enum(axil_op_e, op,    UVM_ALL_ON)
            `uvm_field_int (addr,             UVM_ALL_ON)
            `uvm_field_int (wdata,            UVM_ALL_ON)
            `uvm_field_int (wstrb,            UVM_ALL_ON)
            `uvm_field_int (rdata,            UVM_ALL_ON)
            `uvm_field_int (bresp,            UVM_ALL_ON)
            `uvm_field_int (rresp,            UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axil_seq_item");
            super.new(name);
            wstrb = 4'hF;
        endfunction

        // 地址必须 4 字节对齐
        constraint c_align { addr[1:0] == 2'b00; }

        function string convert2string();
            return $sformatf("%s addr=0x%08h wdata=0x%08h rdata=0x%08h",
                             op.name(), addr, wdata, rdata);
        endfunction
    endclass

    typedef uvm_sequencer#(axil_seq_item) axil_sequencer;

    // ---------------- 驱动器 ----------------
    class axil_driver extends uvm_driver#(axil_seq_item);
        `uvm_component_utils(axil_driver)

        virtual axil_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", vif))
                `uvm_fatal("AXIL_NOVIF", "axil_driver 拿不到 vif")
        endfunction

        task run_phase(uvm_phase phase);
            reset_bus();
            forever begin
                seq_item_port.get_next_item(req);
                if (req.op == AXIL_WRITE) do_write(req);
                else                      do_read(req);
                seq_item_port.item_done();
            end
        endtask

        task reset_bus();
            vif.awvalid = 1'b0; vif.awaddr = '0;
            vif.wvalid  = 1'b0; vif.wdata  = '0; vif.wstrb = '0;
            vif.bready  = 1'b1;                 // 始终接收写响应，简化
            vif.arvalid = 1'b0; vif.araddr = '0;
            vif.rready  = 1'b1;
            wait (vif.rst_n === 1'b1);
            @(negedge vif.clk);
        endtask

        task do_write(axil_seq_item it);
            @(negedge vif.clk);
            vif.awaddr  = it.addr;
            vif.awvalid = 1'b1;
            vif.wdata   = it.wdata;
            vif.wstrb   = it.wstrb;
            vif.wvalid  = 1'b1;
            `uvm_info("AXIL_DRV", $sformatf("WRITE addr=0x%08h data=0x%08h", it.addr, it.wdata), UVM_HIGH)

            // AW 与 W 同时给出，等两者都被接收
            fork
                begin
                    @(posedge vif.clk);
                    while (!(vif.awvalid && vif.awready)) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.awvalid = 1'b0;
                end
                begin
                    @(posedge vif.clk);
                    while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.wvalid = 1'b0;
                end
            join

            // 等写响应
            @(posedge vif.clk);
            while (!vif.bvalid) @(posedge vif.clk);
            it.bresp = vif.bresp;
            it.is_error = (vif.bresp != 2'b00);
            @(negedge vif.clk);
        endtask

        task do_read(axil_seq_item it);
            @(negedge vif.clk);
            vif.araddr  = it.addr;
            vif.arvalid = 1'b1;

            @(posedge vif.clk);
            while (!(vif.arvalid && vif.arready)) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.arvalid = 1'b0;

            @(posedge vif.clk);
            while (!vif.rvalid) @(posedge vif.clk);
            it.rdata = vif.rdata;
            it.rresp = vif.rresp;
            it.is_error = (vif.rresp != 2'b00);
            @(negedge vif.clk);
        endtask
    endclass

    // ---------------- 监测器 ----------------
    // 只上报"真正完成了的传输"，供 RAL 的 predictor 或覆盖率使用。
    class axil_monitor extends uvm_monitor;
        `uvm_component_utils(axil_monitor)

        virtual axil_if vif;
        uvm_analysis_port#(axil_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", vif))
                `uvm_fatal("AXIL_NOVIF", "axil_monitor 拿不到 vif")
        endfunction

        task run_phase(uvm_phase phase);
            axil_seq_item it;
            forever begin
                @(posedge vif.clk);
                if (vif.rst_n) begin
                    // 写完成：B 通道握手
                    if (vif.bvalid && vif.bready) begin
                        it = axil_seq_item::type_id::create("mon_wr");
                        it.op      = AXIL_WRITE;
                        it.bresp   = vif.bresp;
                        it.wdata   = vif.wdata;
                        ap.write(it);
                    end
                    // 读完成：R 通道握手
                    if (vif.rvalid && vif.rready) begin
                        it = axil_seq_item::type_id::create("mon_rd");
                        it.op    = AXIL_READ;
                        it.rdata = vif.rdata;
                        it.rresp = vif.rresp;
                        ap.write(it);
                    end
                end
            end
        endtask
    endclass

    // ---------------- Agent ----------------
    class axil_agent extends uvm_agent;
        `uvm_component_utils(axil_agent)

        axil_sequencer sqr;
        axil_driver    drv;
        axil_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = axil_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = axil_sequencer::type_id::create("sqr", this);
                drv = axil_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ---------------- 基础 sequence ----------------
    class axil_base_seq extends uvm_sequence#(axil_seq_item);
        `uvm_object_utils(axil_base_seq)
        function new(string name = "axil_base_seq");
            super.new(name);
        endfunction

        task reg_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb = 4'hF);
            axil_seq_item it;
            it = axil_seq_item::type_id::create("wr");
            start_item(it);
            it.op = AXIL_WRITE; it.addr = addr; it.wdata = data; it.wstrb = strb;
            finish_item(it);
        endtask

        task reg_read(bit [31:0] addr, output bit [31:0] data);
            axil_seq_item it;
            it = axil_seq_item::type_id::create("rd");
            start_item(it);
            it.op = AXIL_READ; it.addr = addr;
            finish_item(it);
            data = it.rdata;
        endtask
    endclass

endpackage
