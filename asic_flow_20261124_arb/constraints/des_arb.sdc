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

set_driving_cell -lib_cell BUF_X2 -pin Z $data_in
set_max_transition 0.198535 [current_design]

set_false_path -from $rst_coll
