// ============================================================================
// des_ral_adapter.sv —— uvm_reg_adapter：RAL 与 AXI4-Lite 事务的双向翻译
//
// 【重要：本文件在 XSim 2018.3 下的已知缺陷与应对】
//
// 缺陷：XSim 2018.3 在「virtual class + pure virtual 方法 + ref 参数」的组合下，
//       通过基类句柄虚分派调用时，ref 参数写回的值会丢失。
//       uvm_reg_adapter 恰好是 virtual class，bus2reg 恰好是 pure virtual 且
//       第二参数是 ref uvm_reg_bus_op。因此 UVM 内部 do_bus_read 里
//          adapter.bus2reg(bus_req, rw_access);
//          data = rw_access.data & mask;
//       会拿到 data = 0 —— 与本 adapter 写得对不对无关。
//
// 已验证（最小复现）：
//   子类句柄直调 bus2reg        -> ref 回传 OK
//   基类句柄虚分派（UVM 实际路径）-> ref 回传 LOST
//   普通 class 的 virtual 方法   -> ref 回传 OK
//   同结构改成对象句柄传回       -> OK
//
// 结论：这是工具链缺陷，不是 adapter 实现问题。换 VCS/Questa 不会出现。
//
// 应对：本环境不依赖 uvm_reg::read() 的返回 value，改用
//       des_reg_block::read_reg_via_bus()（见 des_ral_pkg.sv），
//       由 sequence 在 axil_sequencer 上直接发总线事务取数据。
//       寄存器模型仍然用于：地址映射、字段定义、只读保护、地址解码，
//       只是「读值回填」这一条路绕开 RAL 的 ref 通道。
//
// 面试口径：这是一个真实可讲的 debug 故事——现象（RAL 读回全 0）→ 假设（adapter
// 写错 / auto_predict / 地址映射）→ 逐个排除 → 最小复现定位到仿真器缺陷 →
// 量化边界（三种调用方式对照）→ 给出绕行方案并说明其代价。
// ============================================================================
package des_ral_adapter_pkg;

    import uvm_pkg::*;
    import des_axil_pkg::*;
    `include "uvm_macros.svh"

    class des_ral_adapter extends uvm_reg_adapter;
        `uvm_object_utils(des_ral_adapter)

        function new(string name = "des_ral_adapter");
            super.new(name);
            supports_byte_enable = 0;
            provides_responses   = 0;
        endfunction

        // RAL -> 总线
        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            axil_seq_item it = axil_seq_item::type_id::create("ral2bus");
            it.op    = (rw.kind == UVM_READ) ? AXIL_READ : AXIL_WRITE;
            it.addr  = rw.addr;
            it.wdata = rw.data;
            it.wstrb = 4'hF;
            return it;
        endfunction

        // 总线 -> RAL
        // 注意：此方法的 ref 回传在 XSim 2018.3 下被丢弃（见文件头）。
        // 保留它是为了满足 UVM 抽象方法的义务，并保证写方向语义完整；
        // 读方向的数据由 des_reg_block::read_reg_via_bus() 直接取。
        virtual function void bus2reg(uvm_sequence_item bus_item,
                                      ref uvm_reg_bus_op rw);
            axil_seq_item it;
            if (!$cast(it, bus_item)) begin
                `uvm_fatal("AXIL_ADP", "bus2reg 拿到的事务类型不是 axil_seq_item")
                return;
            end
            rw.kind   = (it.op == AXIL_READ) ? UVM_READ : UVM_WRITE;
            rw.addr   = it.addr;
            rw.data   = (it.op == AXIL_READ) ? it.rdata : it.wdata;
            rw.status = it.is_error ? UVM_NOT_OK : UVM_IS_OK;
        endfunction

    endclass

endpackage
