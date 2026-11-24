// ============================================================================
// des_ral_pkg.sv —— DES 的 UVM 寄存器模型（RAL）
//
// 对应 DUT：des_axil_regs.v（0x00 KEY_LO / 0x04 KEY_HI / 0x08 CTRL /
//                            0x0C STATUS / 0x10 REKEY_GUARD）
//
// 结构（标准三件套）：
//   des_reg_block     —— uvm_reg_block，default_map 定义地址映射
//   des_reg_adapter   —— uvm_reg_adapter，把 uvm_reg_bus_op 双向翻译成
//                        本项目 axil_seq_item；两个必需方法：
//                          reg2bus()   模型 → 总线（写/读请求）
//                          bus2reg()   总线 → 模型（回填读值与状态）
//   des_reg_predictor —— 无关紧要的"可选件"：本例用显式 predict，
//                        不建独立 predictor，理由见文件末尾注释。
//
// 为什么要有 RAL（面试口径）：
//   1) 抽象：test/sequence 里写 `ral.ctrl.write(...)`、`ral.status.read(...)`，
//      不再手工拼地址和字段，DUT 地址一变只改 model。
//   2) 内建检查：status 字段声明为 RO 后，对它的写操作会被模型直接拒绝。
//   3) 镜像一致性：mirror()/update() 让"模型以为的值"和"DUT 实际值"可比，
//      这是 RAL 相对裸 AXI-Lite 写读的唯一硬价值。
//
// 已知边界（被追问要主动说）：
//   - 本环境在 XSim 2018.3 下用 uvm_reg_frontdoor 绕开工具缺陷（见下），
//     因此 map 的自动地址计算 / check_on_read / byte_enable 不生效。
//   - 没有独立 predictor 订阅 monitor，用的是显式 predict。
//   - 没有 backdoor。backdoor 需要 DPI 或层次化引用，XSim 2018.3 下不稳。
//   - build() 里调 configure() 而不是先用 create() 再 configure()，
//     因为 uvm_reg 的工厂注册由宏完成，create 会在 _reg_block 内部二次分配。
// ============================================================================
package des_ral_pkg;

    import uvm_pkg::*;
    import des_axil_pkg::*;      // axil_seq_item / axil_reg_op_e
    import des_ral_frontdoor_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- 寄存器：KEY_LO ----------------
    class ral_reg_key_lo extends uvm_reg;
        rand uvm_reg_field key_lo;      // [31:0] 密钥低字，RW
        `uvm_object_utils(ral_reg_key_lo)
        function new(string name = "ral_reg_key_lo");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            key_lo = uvm_reg_field::type_id::create("key_lo");
            // configure(parent, size, lsb_pos, access, volatile, reset, has_reset, is_rand, individually_accessible)
            key_lo.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
        endfunction
    endclass

    // ---------------- 寄存器：KEY_HI ----------------
    // 关键语义：写这个寄存器会触发一次换钥（DUT 侧产生 load_key_o 单拍脉冲）。
    // RAL 本身不表达"写产生副作用"，这个行为在 sequence 与 scoreboard 里跟踪；
    // 寄存器只负责值的一致性。
    class ral_reg_key_hi extends uvm_reg;
        rand uvm_reg_field key_hi;
        `uvm_object_utils(ral_reg_key_hi)
        function new(string name = "ral_reg_key_hi");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            key_hi = uvm_reg_field::type_id::create("key_hi");
            key_hi.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
        endfunction
    endclass

    // ---------------- 寄存器：CTRL ----------------
    class ral_reg_ctrl extends uvm_reg;
        rand uvm_reg_field mode;        // [0]
        rand uvm_reg_field enable;      // [1]
        rand uvm_reg_field clr_err;     // [2] 写 1 清 REKEY_ERR
        `uvm_object_utils(ral_reg_ctrl)
        function new(string name = "ral_reg_ctrl");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            mode    = uvm_reg_field::type_id::create("mode");
            enable  = uvm_reg_field::type_id::create("enable");
            clr_err = uvm_reg_field::type_id::create("clr_err");
            mode.configure   (this, 1, 0, "RW", 0, 1'b1, 1, 1, 0);
            enable.configure (this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
            clr_err.configure(this, 1, 2, "WO", 0, 1'b0, 1, 1, 0);
        endfunction
    endclass

    // ---------------- 寄存器：STATUS（只读） ----------------
    // volatile=1：这些位由 DUT 内部状态驱动，模型不能假设它们等于写入值，
    // 因此必须 volatile，否则 mirror 会误判。
    class ral_reg_status extends uvm_reg;
        uvm_reg_field key_ready;
        uvm_reg_field busy;
        uvm_reg_field key_busy;
        uvm_reg_field rekey_err;
        `uvm_object_utils(ral_reg_status)
        function new(string name = "ral_reg_status");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            key_ready = uvm_reg_field::type_id::create("key_ready");
            busy      = uvm_reg_field::type_id::create("busy");
            key_busy  = uvm_reg_field::type_id::create("key_busy");
            rekey_err = uvm_reg_field::type_id::create("rekey_err");
            key_ready.configure(this, 1, 0, "RO", 1, 1'b0, 1, 0, 0);
            busy.configure     (this, 1, 1, "RO", 1, 1'b0, 1, 0, 0);
            key_busy.configure (this, 1, 2, "RO", 1, 1'b0, 1, 0, 0);
            rekey_err.configure(this, 1, 3, "RO", 1, 1'b0, 1, 0, 0);
        endfunction
    endclass

    // ---------------- 寄存器：REKEY_GUARD ----------------
    class ral_reg_guard extends uvm_reg;
        rand uvm_reg_field allow_rekey;   // [0] 0=在途拒绝（默认） 1=放行
        `uvm_object_utils(ral_reg_guard)
        function new(string name = "ral_reg_guard");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            allow_rekey = uvm_reg_field::type_id::create("allow_rekey");
            allow_rekey.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
        endfunction
    endclass

    // ---------------- 寄存器块 ----------------
    class des_reg_block extends uvm_reg_block;
        rand ral_reg_key_lo  key_lo;
        rand ral_reg_key_hi  key_hi;
        rand ral_reg_ctrl    ctrl;
             ral_reg_status  status;
        rand ral_reg_guard   guard;

        `uvm_object_utils(des_reg_block)

        function new(string name = "des_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction

        virtual function void build();
            // 1) default_map：地址宽度 32 位、字节地址、基址 0
            default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 0);

            key_lo = ral_reg_key_lo::type_id::create("key_lo");
            key_lo.configure(this, null, "");
            key_lo.build();
            default_map.add_reg(key_lo, 'h00, "RW");

            key_hi = ral_reg_key_hi::type_id::create("key_hi");
            key_hi.configure(this, null, "");
            key_hi.build();
            default_map.add_reg(key_hi, 'h04, "RW");

            ctrl = ral_reg_ctrl::type_id::create("ctrl");
            ctrl.configure(this, null, "");
            ctrl.build();
            default_map.add_reg(ctrl, 'h08, "RW");

            status = ral_reg_status::type_id::create("status");
            status.configure(this, null, "");
            status.build();
            default_map.add_reg(status, 'h0C, "RO");

            guard = ral_reg_guard::type_id::create("guard");
            guard.configure(this, null, "");
            guard.build();
            default_map.add_reg(guard, 'h10, "RW");

            // 无后门：见文件头"已知边界"
            lock_model();
        endfunction

        // 便捷：把 64 位密钥拆成两次写（注意 KEY_HI 写会触发换钥）
        task write_key(input bit [63:0] k);
            uvm_status_e st;
            key_lo.write(st, k[31:0]);
            key_hi.write(st, k[63:32]);
        endtask

        // ------------------------------------------------------------------
        // frontdoor 绑定（XSim 2018.3 专用 workaround）
        //
        // 原因见 des_ral_adapter.sv / des_ral_frontdoor.sv 文件头：XSim 2018.3
        // 在 virtual class 的 pure virtual + ref 参数组合下不回传，导致
        // uvm_reg_map::do_bus_read 里 data 恒为 0。
        //
        // 开关：uses_frontdoor 为 1 时挂 frontdoor（走对象语义，绕开缺陷）；
        //       换到 VCS/Questa 后把它设 0，即回到标准 adapter 路径。
        //       两种路径共用同一套寄存器定义与 test 代码，无需改 test。
        // ------------------------------------------------------------------
        bit uses_frontdoor = 1;
        uvm_reg_frontdoor fd_list[$];   // 保活：防止 frontdoor 对象被回收

        function void install_frontdoor(uvm_reg_frontdoor fd_proto);
            uvm_reg regs[$];
            uvm_reg_frontdoor fd;
            des_axil_frontdoor axil_fd;
            bit [31:0] offsets[$];

            regs.push_back(key_lo);  offsets.push_back(32'h00);
            regs.push_back(key_hi);  offsets.push_back(32'h04);
            regs.push_back(ctrl);    offsets.push_back(32'h08);
            regs.push_back(status);  offsets.push_back(32'h0C);
            regs.push_back(guard);   offsets.push_back(32'h10);

            foreach (regs[i]) begin
                void'($cast(fd, fd_proto.clone()));
                if (!$cast(axil_fd, fd)) begin
                    `uvm_fatal("RAL", "frontdoor 类型不是 des_axil_frontdoor")
                    return;
                end
                axil_fd.fixed_offset = offsets[i];
                regs[i].set_frontdoor(fd, default_map);
                fd_list.push_back(fd);
            end
        endfunction

        // 便捷：读 STATUS 并解成四个字段
        task read_status(output bit key_ready, output bit busy,
                         output bit key_busy, output bit rekey_err);
            uvm_status_e st;
            uvm_reg_data_t v;
            status.read(st, v);
            key_ready = v[0];
            busy      = v[1];
            key_busy  = v[2];
            rekey_err = v[3];
        endtask

        // ------------------------------------------------------------------
        // 跨包类型转换：des_reg_block 定义在 des_ral_pkg，但 axil_seq_item
        // 定义在 des_axil_pkg。这里只声明接口，不需要知道具体类型。
        // ------------------------------------------------------------------

        // ------------------------------------------------------------------
        // 备用读路径：不经 RAL，直接在 AXI4-Lite sequencer 上发事务
        //
        // 用途：frontdoor 未启用时的兜底，或需要读「RAL 未建模的地址」时使用。
        // 注意本方法在 des_reg_block 内，需要 axil_sequencer 类型 —— 因此
        // 实际定义放在 des_soc_env_pkg（那里同时 import 了两边）。
        // 这里只保留 STATUS 字段解码的纯函数，便于复用。
        // ------------------------------------------------------------------
        function void decode_status(bit [31:0] v,
                                    output bit key_ready, output bit busy,
                                    output bit key_busy, output bit rekey_err);
            key_ready = v[0];
            busy      = v[1];
            key_busy  = v[2];
            rekey_err = v[3];
        endfunction

    endclass

endpackage
