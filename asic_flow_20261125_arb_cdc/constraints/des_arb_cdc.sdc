# ============================================================================
# des_arb_cdc.sdc —— 多时钟 2 通道安全加密前端
#   wclk0 = 100MHz (10ns)   ch0 写域
#   wclk1 = 142.8MHz (7ns)  ch1 写域
#   clk   = 250MHz (4ns)    仲裁 + DES + AXIL 控制
# 三个时钟异步：set_clock_groups -asynchronous
# ============================================================================

create_clock -name wclk0 -period 10.0 [get_ports wclk0]
create_clock -name wclk1 -period  7.0 [get_ports wclk1]
create_clock -name clk   -period  4.0 [get_ports clk]

set_clock_groups -asynchronous -group {wclk0} -group {wclk1} -group {clk}

foreach c {wclk0 wclk1 clk} {
    set_clock_uncertainty -setup 0.10 [get_clocks $c]
    set_clock_uncertainty -hold  0.05 [get_clocks $c]
    set_clock_transition 0.05 [get_clocks $c]
}

# ---- IO 预算 ----
set s0_in   [get_ports {s0_axis_tvalid s0_axis_tdata s0_axis_tlast}]
set s1_in   [get_ports {s1_axis_tvalid s1_axis_tdata s1_axis_tlast}]
set axil_in [get_ports {s_axil_awvalid s_axil_awaddr s_axil_wvalid s_axil_wdata s_axil_wstrb s_axil_bready s_axil_arvalid s_axil_araddr s_axil_rready}]
set axil_out [get_ports {s_axil_awready s_axil_wready s_axil_bvalid s_axil_bresp s_axil_arready s_axil_rvalid s_axil_rdata s_axil_rresp}]
set m_out   [get_ports {m_axis_tvalid m_axis_tdata m_axis_tlast}]
set status_out [get_ports {irq_o arb_busy_o ready_key_o fifo0_full fifo0_empty fifo1_full fifo1_empty}]

set_input_delay  2.0 -clock wclk0 $s0_in
set_input_delay  2.0 -clock wclk1 $s1_in
set_input_delay  1.0 -clock clk  $axil_in
set_output_delay 2.0 -clock clk  $m_out
set_output_delay 1.0 -clock clk  $axil_out
set_output_delay 1.0 -clock clk  $status_out

set_load 0.02 [all_outputs]

set clk_coll [list [get_ports wclk0] [get_ports wclk1] [get_ports clk]]
set rst_coll [list [get_ports wrst0_n] [get_ports wrst1_n] [get_ports rst_n]]
set data_in  [remove_from_collection [remove_from_collection [all_inputs] [get_ports wclk0]] [get_ports wclk1]]
set data_in  [remove_from_collection $data_in [get_ports clk]]
set data_in  [remove_from_collection $data_in [get_ports wrst0_n]]
set data_in  [remove_from_collection $data_in [get_ports wrst1_n]]
set data_in  [remove_from_collection $data_in [get_ports rst_n]]
set_driving_cell -lib_cell BUF_X2 -pin Z $data_in

set_max_transition 0.198535 [current_design]

set_false_path -from [get_ports wrst0_n]
set_false_path -from [get_ports wrst1_n]
set_false_path -from [get_ports rst_n]
