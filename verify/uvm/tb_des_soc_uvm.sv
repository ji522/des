`timescale 1ns/1ps
// ============================================================================
// tb_des_soc_uvm.sv —— 双 agent UVM 平台顶层
//
// DUT：des_soc_top（数据面 AXI4-Stream + 控制面 AXI4-Lite）
// 两个 interface 各自进 config_db：
//   des_if  → "vif"      （数据面，供 des_uvm_pkg 的现有组件使用）
//   axil_if → "axil_vif" （控制面，供 des_axil_pkg 的 driver/monitor 使用）
// ============================================================================
`include "uvm_macros.svh"

module tb_des_soc_uvm;
    import uvm_pkg::*;
    import des_uvm_pkg::*;
    import des_axil_pkg::*;
    import des_ral_pkg::*;
    import des_ral_adapter_pkg::*;
    import des_soc_env_pkg::*;
    import des_soc_test_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---------------- 数据面接口 ----------------
    des_if dif (.clk(clk));

    // ---------------- 控制面接口 ----------------
    axil_if aif (.clk(clk));

    // 复位完全交给数据面 agent 的 des_driver::reset()（它在 run_phase 开头
    // 拉低 10 拍再释放）。TB 不驱动 dif.rst_n，否则双驱动。
    // 控制面 interface 跟随数据面的 rst_n。
    assign aif.rst_n = dif.rst_n;

    // des_if 里 tlast 未接时保持 0，避免 X 传播到 DUT
    assign dif.tlast_i = 1'b0;

    // ---------------- DUT ----------------
    des_soc_top dut (
        .clk            (clk),
        .rst_n          (dif.rst_n),
        // 数据面
        .s_axis_tvalid  (dif.valid_i),
        .s_axis_tready  (dif.ready_o),
        .s_axis_tdata   (dif.data_i),
        .s_axis_tlast   (dif.tlast_i),
        .m_axis_tvalid  (dif.valid_o),
        .m_axis_tready  (dif.ready_i),
        .m_axis_tdata   (dif.data_o),
        .m_axis_tlast   (dif.tlast_o),
        // 控制面
        .s_axil_awvalid (aif.awvalid), .s_axil_awready(aif.awready), .s_axil_awaddr(aif.awaddr),
        .s_axil_wvalid  (aif.wvalid),  .s_axil_wready (aif.wready),  .s_axil_wdata (aif.wdata),
        .s_axil_wstrb   (aif.wstrb),
        .s_axil_bvalid  (aif.bvalid),  .s_axil_bready (aif.bready),  .s_axil_bresp (aif.bresp),
        .s_axil_arvalid (aif.arvalid), .s_axil_arready(aif.arready), .s_axil_araddr(aif.araddr),
        .s_axil_rvalid  (aif.rvalid),  .s_axil_rready (aif.rready),  .s_axil_rdata (aif.rdata),
        .s_axil_rresp   (aif.rresp),
        // 状态观测
        .ready_key_o    (dif.ready_key_o)
    );

    // 探针：直接看 DUT 内部寄存器与总线握手，用于定位 RAL 事务是否真的到了
    always @(posedge clk) begin
        if (dut.u_regs.do_write)
            $display("[PROBE %0t] DO_WRITE addr=%0h data=%08h strb=%b key_r=%016h",
                     $time, dut.u_regs.wr_addr, dut.u_regs.wr_data, dut.u_regs.wr_strb,
                     dut.u_regs.key_r);
        if (dut.u_regs.ar_fire)
            $display("[PROBE %0t] AR_FIRE addr=%0h key_r=%016h",
                     $time, dut.u_regs.s_axil_araddr[5:2], dut.u_regs.key_r);
    end

    initial begin
        uvm_config_db#(virtual des_if)::set(null, "uvm_test_top*", "vif", dif);
        uvm_config_db#(virtual axil_if)::set(null, "uvm_test_top*", "axil_vif", aif);
        // 不用 +UVM_TESTNAME：XSim 2018.3 的 --testplusarg 对 "NAME=VALUE" 形式会
        // 拆成两个 switch 而报错。直接在这里指定 test 类名。
        run_test("des_soc_override_test");
    end

    initial begin
        #1;
        uvm_top.set_report_verbosity_level(UVM_FULL);
    end

    initial begin
        // dummy
    end

    initial begin
        #5000000;
        `uvm_fatal("TIMEOUT", "SoC UVM 仿真超时")
        $finish;
    end
endmodule
