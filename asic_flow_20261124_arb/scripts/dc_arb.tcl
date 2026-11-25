# ============================================================================
# dc_arb.tcl —— 2 通道 AXIS 仲裁 + DES SoC 逻辑综合
#
# 关键：必须用 analyze/elaborate/link，不能用 read_file —— 参数化实例
# (sync_fifo / axis_arb2 / axis_arb_regs) 用 read_file 时会被静默丢成空引用，
# 面积/时序报告看起来正常但实际少了整块逻辑。elaborate 后加实例自检。
# ============================================================================
set DESIGN des_arb_soc_top
set FLOW_ROOT [file normalize .]
set RTL_DIR [file join $FLOW_ROOT rtl]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]

if {![info exists synopsys_root]} {
    set synopsys_root /home/synopsys/syn/O-2018.06-SP1
}
set DW_LIB [file join $synopsys_root libraries syn dw_foundation.sldb]
set STD_DB [file join $PDK_DIR NangateOpenCellLibrary_typical.db]

set search_path [list . $RTL_DIR $PDK_DIR]
set target_library [list $STD_DB]
set link_library [list "*" $STD_DB $DW_LIB]
set synthetic_library [list $DW_LIB]

set verilogout_no_tri true
set verilogout_equation false

set_svf [file join $OUT_DIR ${DESIGN}.svf]

set rtl_files [list \
    [file join $RTL_DIR des_arb_soc_top.v] \
    [file join $RTL_DIR axis_arb2.v] \
    [file join $RTL_DIR axis_arb_regs.v] \
    [file join $RTL_DIR sync_fifo.v] \
    [file join $RTL_DIR des_soc_top.v] \
    [file join $RTL_DIR des_axil_regs.v] \
    [file join $RTL_DIR des_axis_wrap.v] \
    [file join $RTL_DIR des_pipeline_fb.v] \
    [file join $RTL_DIR des_pipe_round_fb.v] \
    [file join $RTL_DIR key_ram_gen.v] \
]

analyze -format verilog $rtl_files
elaborate $DESIGN
current_design $DESIGN
link

# ---- 参数化实例自检：空了说明 elaborate 没把模块带进来 ----
set n_fifo [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ sync_fifo*"]]
set n_arb  [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ axis_arb2*"]]
set n_regs [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ axis_arb_regs*"]]
puts "INSTANCE CHECK: sync_fifo=$n_fifo axis_arb2=$n_arb axis_arb_regs=$n_regs"
if {$n_fifo < 2} { error "sync_fifo instances missing after elaborate" }
if {$n_arb  < 1} { error "axis_arb2 instance missing after elaborate" }
if {$n_regs < 1} { error "axis_arb_regs instance missing after elaborate" }

source [file join $FLOW_ROOT constraints des_arb.sdc]

check_design > [file join $RPT_DIR dc_check_design.rpt]
check_timing > [file join $RPT_DIR dc_check_timing.rpt]

compile_ultra

report_area   -hierarchy > [file join $RPT_DIR dc_area.rpt]
report_qor                > [file join $RPT_DIR dc_qor.rpt]
report_clock              > [file join $RPT_DIR dc_clock.rpt]
report_power              > [file join $RPT_DIR dc_power.rpt]
report_constraint -all_violators > [file join $RPT_DIR dc_violators.rpt]

set clk_coll [get_ports clk]
set data_in  [remove_from_collection [remove_from_collection [all_inputs] $clk_coll] [get_ports rst_n]]
set ff_ck    [all_registers -clock_pins]
set ff_d     [all_registers -data_pins]

report_timing -from $ff_ck -to $ff_d -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_reg2reg.rpt]
report_timing -from $data_in -to $ff_d -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_in2reg.rpt]
report_timing -from $ff_ck -to [all_outputs] -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_reg2out.rpt]
report_timing -from $data_in -to [all_outputs] -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_in2out.rpt]
report_timing -from $ff_ck -to $ff_d -delay_type min -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_hold.rpt]

write -format verilog -hierarchy -output [file join $OUT_DIR ${DESIGN}_netlist.v]
write_sdc [file join $OUT_DIR ${DESIGN}.sdc]

exit
