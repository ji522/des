# 100 MHz reference clock for des_soc_top.
set clk_period 10.0
create_clock -name clk -period $clk_period [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]

set input_ports [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay 2.0 -clock clk $input_ports
set_output_delay 2.0 -clock clk [all_outputs]
set_load 0.02 [all_outputs]

# rst_n is an asynchronous reset, not a timed data input.
set_false_path -from [get_ports rst_n]
