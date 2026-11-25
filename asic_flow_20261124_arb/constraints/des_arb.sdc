# ============================================================================
# des_arb.sdc —— 2 通道 AXIS 仲裁 + DES SoC 单时钟约束（10ns / 100MHz）
#
# 与 asic_flow_20261108/constraints/des.sdc 同口径：
#  - setup/hold uncertainty 分开
#  - IO 2.0ns 是占位预算（真实值应来自系统接口）
#  - 输入驱动 BUF_X2，输出 load 0.02pF
#  - max_transition 取库默认 0.198535ns
#  - rst_n 只驱动内部复位同步器的异步端，set_false_path
# ============================================================================

set clk_period 10.0
create_clock -name clk -period $clk_period [get_ports clk]

set_clock_uncertainty -setup 0.10 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]

set clk_coll [get_ports clk]
set rst_coll [get_ports rst_n]
set data_in  [remove_from_collection [remove_from_collection [all_inputs] $clk_coll] $rst_coll]

set_input_delay  2.0 -clock clk $data_in
set_output_delay 2.0 -clock clk [all_outputs]
set_load 0.02 [all_outputs]

# ---- AXI4-Lite 控制面 IO 预算：1.0ns（AXIS 数据面仍 2.0ns）----
# 控制面通常低于数据面频率/有独立预算；这里显式分层，避免把
# address decode -> ready 的组合路径按数据面 2.0ns 预算误判。
set axil_in  [get_ports {s_axil_awvalid s_axil_awaddr s_axil_wvalid s_axil_wdata s_axil_wstrb s_axil_bready s_axil_arvalid s_axil_araddr s_axil_rready}]
set axil_out [get_ports {s_axil_awready s_axil_wready s_axil_bvalid s_axil_bresp s_axil_arready s_axil_rvalid s_axil_rdata s_axil_rresp}]
set_input_delay  1.0 -clock clk $axil_in
set_output_delay 1.0 -clock clk $axil_out

set_driving_cell -lib_cell BUF_X2 -pin Z $data_in
set_max_transition 0.198535 [current_design]

set_false_path -from $rst_coll
