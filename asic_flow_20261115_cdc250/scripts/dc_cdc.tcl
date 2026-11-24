# ============================================================================
# dc_cdc.tcl —— des_axis_cdc_top 双时钟综合（2026-11-15 修订）
#
# 相对单时钟版 dc.tcl 的增量：
#   1) 顶层换成 des_axis_cdc_top，RTL 增加 cdc/async_fifo.v 与 cdc/cdc_sync.v
#   2) 约束换成双时钟 des_axis_cdc.sdc（wclk 10ns / clk 4ns，异步时钟组）
#   3) 用 analyze + elaborate 而不是 read_file：
#      async_fifo 是参数化实例化（DATA_W=65 / ADDR_W=4），read_file 在 link
#      阶段重建参数化设计时会报 LBR-1 "Cannot find the design 'async_fifo'"
#      并把整个 FIFO 丢成空引用。analyze + elaborate 能正确生成
#      async_fifo_DATA_W65_ADDR_W4。
#   4) 报告按域拆分：慢域路径、快域路径分别看
# ============================================================================
set DESIGN des_axis_cdc_top
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

set search_path [list . $RTL_DIR [file join $RTL_DIR cdc] $PDK_DIR]
set target_library [list $STD_DB]
set link_library [list "*" $STD_DB $DW_LIB]
set synthetic_library [list $DW_LIB]

set verilogout_no_tri true
set verilogout_equation false

set_svf [file join $OUT_DIR ${DESIGN}.svf]

set rtl_files [list \
    [file join $RTL_DIR des_axis_cdc_top.v] \
    [file join $RTL_DIR cdc async_fifo.v] \
    [file join $RTL_DIR cdc cdc_sync.v] \
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

source [file join $FLOW_ROOT constraints des_axis_cdc.sdc]

check_design > [file join $RPT_DIR dc_check_design.rpt]
check_timing   > [file join $RPT_DIR dc_check_timing.rpt]

# 自检：FIFO 必须真的被展开进来，否则整个流程结果无意义
set fifo_inst [get_cells -hier -filter "ref_name =~ async_fifo*"]
if {[sizeof_collection $fifo_inst] == 0} {
    error "async_fifo 没有被展开（参数化实例化失败），综合结果无效"
} else {
    puts "INFO: FIFO instance = [get_object_name $fifo_inst]"
}

compile_ultra

report_area   -hierarchy > [file join $RPT_DIR dc_area.rpt]
report_qor                > [file join $RPT_DIR dc_qor.rpt]
report_clock              > [file join $RPT_DIR dc_clock.rpt]
report_power              > [file join $RPT_DIR dc_power.rpt]
report_constraint -all_violators > [file join $RPT_DIR dc_violators.rpt]

# ---- 分类时序：按域分别看 ----
set ff_ck  [all_registers -clock_pins]
set ff_d   [all_registers -data_pins]

report_timing -from $ff_ck -to $ff_d -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_reg2reg.rpt]
report_timing -from $ff_ck -to $ff_d -delay_type min -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_hold.rpt]
report_timing -from [get_clocks wclk] -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_wclk.rpt]
report_timing -from [get_clocks clk] -max_paths 10 -significant_digits 4 \
    > [file join $RPT_DIR dc_timing_clk.rpt]

write -format verilog -hierarchy -output [file join $OUT_DIR ${DESIGN}_netlist.v]
write_sdc [file join $OUT_DIR ${DESIGN}.sdc]

exit
