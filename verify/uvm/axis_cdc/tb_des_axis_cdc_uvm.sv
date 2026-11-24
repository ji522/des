`timescale 1ns / 1ps
// ============================================================================
// tb_des_axis_cdc_uvm.sv —— 合并版顶层（AXIS + 双时钟 CDC）UVM 顶层
//
//   DUT : cdc/des_axis_cdc_top
//   慢域 wclk = 100 MHz, 快域 clk = 250 MHz（无公共沿）
//
// 两个 interface：
//   axis_cdc_if → "vif"      （双时钟数据面）
//   axil_if     → "axil_vif" （快域控制面，复用 des_axil_pkg）
//
// 复位 wrst_n / rst_n 由本 module 驱动，200 ns 后同时释放。
// ============================================================================
`include "uvm_macros.svh"

module tb_des_axis_cdc_uvm;
    import uvm_pkg::*;
    import axis_cdc_pkg::*;

    // ---------------- 时钟 / 复位 ----------------
    logic wclk = 1'b0;
    logic clk  = 1'b0;
    logic wrst_n = 1'b0;
    logic rst_n  = 1'b0;

    always #5 wclk = ~wclk;   // 100 MHz
    always #2 clk  = ~clk;    // 250 MHz

    // ---------------- 接口 ----------------
    axis_cdc_if cif (
        .wclk  (wclk),
        .clk   (clk),
        .wrst_n(wrst_n),
        .rst_n (rst_n)
    );

    axil_if aif (.clk(clk));
    assign aif.rst_n = rst_n;

    // ---------------- DUT ----------------
    des_axis_cdc_top dut (
        .wclk             (wclk),
        .wrst_n           (wrst_n),

        .s_axis_tvalid    (cif.s_axis_tvalid),
        .s_axis_tready    (cif.s_axis_tready),
        .s_axis_tdata     (cif.s_axis_tdata),
        .s_axis_tlast     (cif.s_axis_tlast),

        .clk              (clk),
        .rst_n            (rst_n),

        .s_axil_awvalid   (aif.awvalid),
        .s_axil_awready   (aif.awready),
        .s_axil_awaddr    (aif.awaddr),
        .s_axil_wvalid    (aif.wvalid),
        .s_axil_wready    (aif.wready),
        .s_axil_wdata     (aif.wdata),
        .s_axil_wstrb     (aif.wstrb),
        .s_axil_bvalid    (aif.bvalid),
        .s_axil_bready    (aif.bready),
        .s_axil_bresp     (aif.bresp),
        .s_axil_arvalid   (aif.arvalid),
        .s_axil_arready   (aif.arready),
        .s_axil_araddr    (aif.araddr),
        .s_axil_rvalid    (aif.rvalid),
        .s_axil_rready    (aif.rready),
        .s_axil_rdata     (aif.rdata),
        .s_axil_rresp     (aif.rresp),

        .m_axis_tvalid    (cif.m_axis_tvalid),
        .m_axis_tready    (cif.m_axis_tready),
        .m_axis_tdata     (cif.m_axis_tdata),
        .m_axis_tlast     (cif.m_axis_tlast),

        .ready_key_o_wclk (cif.ready_key_o_wclk)
    );

    // ---------------- 复位释放 ----------------
    initial begin
        wrst_n = 1'b0;
        rst_n  = 1'b0;
        #200;
        wrst_n = 1'b1;
        rst_n  = 1'b1;
    end

    // ---------------- UVM 启动 ----------------
    initial begin
        uvm_config_db#(virtual axis_cdc_if)::set(null, "uvm_test_top*", "vif", cif);
        uvm_config_db#(virtual axil_if)::set(null, "uvm_test_top*", "axil_vif", aif);
        // XSim 2018.3 的 --testplusarg 对 "NAME=VALUE" 会误拆，直接指定 test 名
        run_test("axis_cdc_test");
    end

    // ---------------- 调试探针（每 50us 打印一次 DUT 内部状态） ----------------
    always #50000 begin
        $display("[PROBE %0t] wfull=%b rempty=%b rdata_v=%b rdy_key=%b infl=%0d | s_v=%b s_r=%b m_v=%b m_r=%b m_last=%b",
                 $time, dut.wfull, dut.rempty, dut.rdata_v, dut.ready_key_f,
                 dut.in_flight_f, cif.s_axis_tvalid, cif.s_axis_tready,
                 cif.m_axis_tvalid, cif.m_axis_tready, cif.m_axis_tlast);
    end

    // ---------------- 超时保护 ----------------
    initial begin
        #1_000_000;
        `uvm_fatal("TIMEOUT", "AXIS-CDC UVM 仿真超时")
        $finish;
    end

endmodule
