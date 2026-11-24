# ============================================================================
# des_axis_cdc.sdc —— DES AXIS+CDC 合并顶层的双时钟约束
#
# 顶层：des_axis_cdc_top
#   wclk 10ns (100MHz) —— 慢速源域：AXI4-Stream slave + ready_key_o_wclk
#   clk   4ns (250MHz) —— 快域：AXI4-Lite 控制面 + AXI4-Stream master + DES 引擎
#
# 与单时钟版的关键区别：
#   1) 两个主时钟，用 set_clock_groups -asynchronous 声明异步；跨域路径
#      （格雷码指针、FIFO 存储、同步器第一级）全部退出 setup/hold 分析，
#      正确性由同步器结构 + 两级同步保证，不由 STA 保证。
#   2) IO 预算按各自域给：慢域 2.0ns，快域 1.0ns（快域 4ns 周期里 IO 占 25%，
#      这是本次 250MHz 运行显式采用的假设，不是从原流程继承的 2.0ns）。
# ============================================================================

set wclk_period 10.0
set clk_period  4.0

create_clock -name wclk -period $wclk_period [get_ports wclk]
create_clock -name clk  -period $clk_period  [get_ports clk]

# 两域异步：跨域路径不参与 setup/hold
set_clock_groups -asynchronous -group [get_clocks wclk] -group [get_clocks clk]

# --- 时钟不确定度：setup / hold 分开 ---
set_clock_uncertainty -setup 0.10 [get_clocks wclk]
set_clock_uncertainty -hold  0.05 [get_clocks wclk]
set_clock_uncertainty -setup 0.10 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

set_clock_transition 0.05 [get_clocks wclk]
set_clock_transition 0.05 [get_clocks clk]

# --- 慢域 IO（wclk，10ns）---
set slow_in  [get_ports {s_axis_tvalid s_axis_tdata s_axis_tlast}]
set slow_out [get_ports {s_axis_tready ready_key_o_wclk}]
set_input_delay  2.0 -clock wclk $slow_in
set_output_delay 2.0 -clock wclk $slow_out

# --- 快域 IO（clk，4ns）---
set fast_in  [get_ports {s_axil_awvalid s_axil_awaddr s_axil_wvalid s_axil_wdata \
                        s_axil_wstrb s_axil_bready s_axil_arvalid s_axil_araddr \
                        s_axil_rready m_axis_tready}]
set fast_out [get_ports {s_axil_awready s_axil_wready s_axil_bvalid s_axil_bresp \
                        s_axil_arready s_axil_rvalid s_axil_rdata s_axil_rresp \
                        m_axis_tvalid m_axis_tdata m_axis_tlast}]
set_input_delay  1.0 -clock clk $fast_in
set_output_delay 1.0 -clock clk $fast_out

set_load 0.02 [all_outputs]

# --- 输入驱动建模 ---
set data_in [remove_from_collection [remove_from_collection [all_inputs] \
             [get_ports {wclk clk}]] [get_ports {wrst_n rst_n}]]
set_driving_cell -lib_cell BUF_X2 -pin Z $data_in

# --- 设计规则 ---
set_max_transition 0.198535 [current_design]

# --- 复位 ---
# wrst_n / rst_n 只驱动各自域的 reset_sync 异步复位端（异步置位不需要时序检查）；
# 同步器输出到域内各异步清零端的 recovery/removal 走正常时序路径，会被检查。
set_false_path -from [get_ports {wrst_n rst_n}]
