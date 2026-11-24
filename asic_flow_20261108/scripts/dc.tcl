# ============================================================================
# dc.tcl —— DES SoC 逻辑综合（2026-11-08 修订版）
#
# 相比 10-31 版：
#   1. 补 set_svf —— 原来是靠手工拷 default.svf 才让 Formality 过的，
#      脚本本身跑完根本不会生成 outputs/des_soc_top.svf，Formality 必报 FM-203
#   2. 增加 reg2reg / in2reg / reg2out / in2out 分类时序报告
#   3. 增加 check_timing / report_constraint -all_violators
# ============================================================================
set DESIGN des_soc_top
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

# Formality 指导文件必须由同一次 DC 会话产生
set_svf [file join $OUT_DIR ${DESIGN}.svf]

set rtl_files [list \
    [file join $RTL_DIR des_soc_top.v] \
    [file join $RTL_DIR des_axil_regs.v] \
    [file join $RTL_DIR des_axis_wrap.v] \
    [file join $RTL_DIR des_pipeline_fb.v] \
    [file join $RTL_DIR des_pipe_round_fb.v] \
    [file join $RTL_DIR key_ram_gen.v] \
]

read_file -format verilog $rtl_files
current_design $DESIGN
link
source [file join $FLOW_ROOT constraints des.sdc]

check_design > [file join $RPT_DIR dc_check_design.rpt]
check_timing   > [file join $RPT_DIR dc_check_timing.rpt]

compile_ultra

# ---- 汇总报告 ----
report_area   -hierarchy > [file join $RPT_DIR dc_area.rpt]
report_qor                > [file join $RPT_DIR dc_qor.rpt]
report_clock              > [file join $RPT_DIR dc_clock.rpt]
report_power              > [file join $RPT_DIR dc_power.rpt]
report_constraint -all_violators > [file join $RPT_DIR dc_violators.rpt]

# ---- 分类时序：别再只盯一条 IO 直通路径 ----
set clk_coll    [get_ports clk]
set data_in     [remove_from_collection [remove_from_collection [all_inputs] $clk_coll] [get_ports rst_n]]
set ff_ck       [all_registers -clock_pins]
set ff_d        [all_registers -data_pins]

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
