# Formality equivalence check: RTL reference vs DC gate netlist.
set DESIGN des_soc_top
set FLOW_ROOT [file normalize .]
set RTL_DIR [file join $FLOW_ROOT rtl]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]

set synopsys_auto_setup true
set search_path [list . $RTL_DIR $PDK_DIR]
read_db [file join $PDK_DIR NangateOpenCellLibrary_typical.db]
set_svf [file join $OUT_DIR ${DESIGN}.svf]

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
report_status > [file join $RPT_DIR fm_status.rpt]

exit

