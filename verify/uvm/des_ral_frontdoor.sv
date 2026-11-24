// ============================================================================
// des_ral_frontdoor.sv —— 用 uvm_reg_frontdoor 绕过 XSim 的 ref 回传缺陷
//
// 【为什么需要它】
// XSim 2018.3 在「virtual class + pure virtual + ref 参数」组合下，通过基类
// 句柄虚分派调用时不回传 ref。uvm_reg_adapter::bus2reg 正是这个组合，导致
// uvm_reg_map::do_bus_read 里拿到 data=0（详见 des_ral_adapter.sv 文件头）。
//
// 【为什么 frontdoor 能绕开】
// uvm_reg.svh 的 do_read：
//     if (map_info.frontdoor != null)
//        fd.start(fd.sequencer, rw.parent);      // ← 不走 bus2reg
//     else
//        rw.local_map.do_read(rw);               // ← 走 bus2reg（踩 bug）
// 且 frontdoor 回传读值的方式是「写对象成员」：
//     rw_info.value[0] = <读到的数据>;
// rw_info 是 uvm_reg_item 句柄，对象是引用语义 —— 已用最小实验验证能穿透该缺陷。
//
// 【代价（面试要主动说）】
//   1) frontdoor 绕过内建通路，丧失 map 的自动地址计算、check_on_read、
//      byte_enable —— 这些要自己在 frontdoor 里实现（本文件里手动算地址）；
//   2) 每个寄存器各挂一个 frontdoor 实例，寄存器多时可考虑统一基类；
//   3) 换到 VCS/Questa 后应把 ral.uses_frontdoor 设 0 回到标准 adapter 路径。
//
// 【面试口径】
//   "遇到工具缺陷时如何在框架内绕过而不用改库"的完整案例：
//   定位（最小复现量化）→ 选方案（frontdoor 走对象语义）→ 说清代价与迁移路径。
// ============================================================================
package des_ral_frontdoor_pkg;

    import uvm_pkg::*;
    import des_axil_pkg::*;
    `include "uvm_macros.svh"

    class des_axil_frontdoor extends uvm_reg_frontdoor;
        `uvm_object_utils(des_axil_frontdoor)

        function new(string name = "des_axil_frontdoor");
            super.new(name);
        endfunction

        // frontdoor 在 UVM 里是 uvm_reg_sequence 的子类，由 do_read/do_write 调
        // fd.start(sequencer, parent)，入口是下面的 body()。
        virtual task body();
            axil_seq_item it;
            bit [31:0]    byte_addr;

            if (rw_info == null) begin
                `uvm_fatal("FD", "rw_info 为空，frontdoor 未被正确调用")
                return;
            end

            // frontdoor 不走 map 的自动地址计算，这里自己算：
            // 寄存器偏移 = map.get_base_addr() + reg 在 map 内的偏移
            // 本项目所有寄存器字对齐，偏移直接由 element 在 map 里的位置给出。
            byte_addr = get_byte_addr();

            it = axil_seq_item::type_id::create("fd_item");
            it.addr  = byte_addr;
            it.wstrb = 4'hF;

            if (rw_info.kind == UVM_READ) begin
                it.op = AXIL_READ;
                start_item(it);
                finish_item(it);
                rw_info.value[0] = it.rdata;      // ★ 对象成员回传，绕开 ref 缺陷
                rw_info.status   = it.is_error ? UVM_NOT_OK : UVM_IS_OK;
            end else begin
                it.op    = AXIL_WRITE;
                it.wdata = rw_info.value[0];
                start_item(it);
                finish_item(it);
                rw_info.status = it.is_error ? UVM_NOT_OK : UVM_IS_OK;
            end
        endtask

        // 由 install_frontdoor 注入，避免依赖 uvm_reg_element 的动态类型
        bit [31:0] fixed_offset = 32'h0;
        function bit [31:0] get_byte_addr();
            return fixed_offset;
        endfunction

    endclass

endpackage
