# ============================================================================
# fm.tcl —— Formality RTL vs 网表等价性（2026-11-08 修订版）
#
# 相比 10-31 版：
#   1. 读 SVF（dc.tcl 现在会生成）之前先检查文件存在，缺了直接报错退出，
#      不再默默跑出一个 FAILED
#   2. 补 report_unread_endpoints / report_unmatched_points / report_constants /
#      report_dont_verify_points / report_black_boxes / report_guidance
# ============================================================================
set DESIGN des_soc_top
set FLOW_ROOT [file normalize .]
set RTL_DIR [file join $FLOW_ROOT rtl]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]

set SVF [file join $OUT_DIR ${DESIGN}.svf]
if {![file exists $SVF]} {
    error "SVF missing: $SVF —— dc.tcl 里必须有 set_svf（否则 Formality 会 FM-203）"
}

set synopsys_auto_setup true
set search_path [list . $RTL_DIR $PDK_DIR]
read_db [file join $PDK_DIR NangateOpenCellLibrary_typical.db]
set_svf $SVF

set rtl_files [list \
    [file join $RTL_DIR des_soc_top.v] \
    [file join $RTL_DIR des_axil_regs.v] \
    [file join $RTL_DIR des_axis_wrap.v] \
    [file join $RTL_DIR des_pipeline_fb.v] \
    [file join $RTL_DIR des_pipe_round_fb.v] \
    [file join $RTL_DIR key_ram_gen.v] \
]

read_verilog -container r -libname WORK -01 $rtl_files
set_top r:/WORK/$DESIGN

read_verilog -container i -libname WORK -01 [file join $OUT_DIR ${DESIGN}_netlist.v]
set_top i:/WORK/$DESIGN

match
verify

report_status            > [file join $RPT_DIR fm_status.rpt]
report_unread_endpoints -all > [file join $RPT_DIR fm_unread_endpoints.rpt]
report_unmatched_points  > [file join $RPT_DIR fm_unmatched_points.rpt]
report_dont_verify_points > [file join $RPT_DIR fm_dont_verify.rpt]
report_constants         > [file join $RPT_DIR fm_constants.rpt]
report_black_boxes       > [file join $RPT_DIR fm_black_boxes.rpt]
report_guidance          > [file join $RPT_DIR fm_guidance.rpt]

exit
