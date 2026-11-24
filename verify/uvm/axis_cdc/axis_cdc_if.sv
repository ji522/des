`timescale 1ns / 1ps
// ============================================================================
// axis_cdc_if.sv —— 合并版顶层 des_axis_cdc_top 的双时钟验证接口
//
// 一个 interface 同时承载两个时钟域：
//   慢域 wclk：s_axis_*（AXI4-Stream slave，TB/UVM driver 驱动）
//   快域 clk ：m_axis_*（AXI4-Stream master，DUT 驱动；tready 由 ready driver 驱动）
//              ready_key_o_wclk（DUT 的慢域状态输出，只观测）
//
// 复位 wrst_n / rst_n 由 TB module 驱动，作为 interface 的输入端口接入，
// 这样 driver/monitor 可以直接用 vif.wrst_n / vif.rst_n 做门控。
//
// 注意：UVM 侧用的是 virtual interface，modport 只作文档/接线约束，
// driver 内部仍直接访问成员（与项目里 des_if / axil_if 的用法一致）。
// ============================================================================
interface axis_cdc_if (
    input logic wclk,
    input logic clk,
    input logic wrst_n,
    input logic rst_n
);

    // ---------------- 慢域：AXI4-Stream slave ----------------
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic [63:0] s_axis_tdata;
    logic        s_axis_tlast;

    // ---------------- 快域：AXI4-Stream master ----------------
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic [63:0] m_axis_tdata;
    logic        m_axis_tlast;

    // ---------------- 反向状态：ready_key_o 的慢域副本 ----------------
    logic        ready_key_o_wclk;

    // ---------------- DUT 接线视图 ----------------
    modport DUT (
        input  wclk, wrst_n, clk, rst_n,
        input  s_axis_tvalid, s_axis_tdata, s_axis_tlast, m_axis_tready,
        output s_axis_tready, m_axis_tvalid, m_axis_tdata, m_axis_tlast,
        output ready_key_o_wclk
    );

    // ---------------- 慢域数据驱动视图 ----------------
    modport DRV_SLOW (
        input  wclk, wrst_n, s_axis_tready,
        output s_axis_tvalid, s_axis_tdata, s_axis_tlast
    );

    // ---------------- 快域输出监测 / 反压视图 ----------------
    modport MON_FAST (
        input  clk, rst_n, m_axis_tvalid, m_axis_tdata, m_axis_tlast,
        output m_axis_tready
    );

endinterface
