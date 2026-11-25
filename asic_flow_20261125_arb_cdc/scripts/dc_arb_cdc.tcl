# ============================================================================
# dc_arb_cdc.tcl —— 多时钟 2 通道安全加密前端综合
# 必须 analyze/elaborate/link；参数化 FIFO 用 read_file 会被静默丢引用。
# ============================================================================
set DESIGN des_arb_cdc_top
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
    [file join $RTL_DIR des_arb_cdc_top.v] \
    [file join $RTL_DIR async_fifo.v] \
    [file join $RTL_DIR cdc_sync.v] \
    [file join $RTL_DIR async_axis_fifo.v] \
    [file join $RTL_DIR des_arb_soc_top.v] \
    [file join $RTL_DIR axis_arb2.v] \
    [file join $RTL_DIR axis_arb_regs.v] \
    [file join $RTL_DIR axil_2to1_demux.v] \
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

set n_af  [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ async_fifo*"]]
set n_aaf [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ async_axis_fifo*"]]
set n_sf  [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ sync_fifo*"]]
set n_arb [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ axis_arb2*"]]
set n_dec [sizeof_collection [get_cells -hier -quiet -filter "ref_name =~ axil_2to1_demux*"]]
puts "INSTANCE CHECK: async_fifo=$n_af async_axis_fifo=$n_aaf sync_fifo=$n_sf axis_arb2=$n_arb demux=$n_dec"
if {$n_af  < 2} { error "async_fifo instances missing" }
if {$n_aaf < 2} { error "async_axis_fifo instances missing" }
if {$n_sf  < 2} { error "sync_fifo instances missing" }
if {$n_arb < 1} { error "axis_arb2 missing" }
if {$n_dec < 1} { error "axil_2to1_demux missing" }

source [file join $FLOW_ROOT constraints des_arb_cdc.sdc]

check_design > [file join $RPT_DIR dc_check_design.rpt]
check_timing > [file join $RPT_DIR dc_check_timing.rpt]

compile_ultra

report_area   -hierarchy > [file join $RPT_DIR dc_area.rpt]
report_qor                > [file join $RPT_DIR dc_qor.rpt]
report_clock              > [file join $RPT_DIR dc_clock.rpt]
report_power              > [file join $RPT_DIR dc_power.rpt]
report_constraint -all_violators > [file join $RPT_DIR dc_violators.rpt]

set ff_ck [all_registers -clock_pins]
set ff_d  [all_registers -data_pins]
set all_in [all_inputs]
set all_out [all_outputs]

report_timing -from $ff_ck -to $ff_d -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_reg2reg.rpt]
report_timing -from $all_in -to $ff_d -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_in2reg.rpt]
report_timing -from $ff_ck -to $all_out -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_reg2out.rpt]
report_timing -from $all_in -to $all_out -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_in2out.rpt]
report_timing -from $ff_ck -to $ff_d -delay_type min -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_hold.rpt]

write -format verilog -hierarchy -output [file join $OUT_DIR ${DESIGN}_netlist.v]
write_sdc [file join $OUT_DIR ${DESIGN}.sdc]

exit
