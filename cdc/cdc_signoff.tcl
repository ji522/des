# =====================================================================
# cdc_signoff.tcl —— des_cdc_top 非工程批处理：综合 + 实现 + CDC/时序签署
# 用法（cwd = des_pipeline）：vivado -mode batch -source cdc/cdc_signoff.tcl
# =====================================================================
set out "cdc/_signoff"
file mkdir $out
file mkdir $out/reports

read_verilog "des_pipeline_fb.v"
read_verilog "key_ram_gen.v"
read_verilog "des_pipe_round_fb.v"
read_verilog "cdc/async_fifo.v"
read_verilog "cdc/cdc_sync.v"
read_verilog "cdc/des_cdc_top.v"
read_xdc     "cdc/cdc.xdc"

synth_design -top des_cdc_top -part xc7a35tfgg484-2 -include_dirs "."
opt_design
place_design
route_design

report_timing_summary -file $out/reports/timing_summary.rpt
report_cdc            -file $out/reports/cdc_report.rpt
report_utilization    -file $out/reports/utilization.rpt
write_checkpoint -force $out/des_cdc_top_signoff.dcp

puts "=== CDC SIGNOFF DONE: reports in cdc/_signoff/reports ==="
