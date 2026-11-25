# ============================================================================
# fm_arb_cdc.tcl —— 多时钟 2 通道安全加密前端 Formality
# ============================================================================
set DESIGN des_arb_cdc_top
set FLOW_ROOT [file normalize .]
set RTL_DIR [file join $FLOW_ROOT rtl]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]

set SVF [file join $OUT_DIR ${DESIGN}.svf]
if {![file exists $SVF]} {
    error "SVF missing: $SVF —— dc_arb_cdc.tcl 里必须有 set_svf"
}

set synopsys_auto_setup true
set search_path [list . $RTL_DIR $PDK_DIR]
read_db [file join $PDK_DIR NangateOpenCellLibrary_typical.db]
set_svf $SVF

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
