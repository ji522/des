# ============================================================================
# dc_base_saif.tcl —— 基线综合（不插时钟门控），读 SAIF 出功耗
# ============================================================================
set DESIGN des_arb_cdc_top
set FLOW_ROOT [file normalize .]
set RTL_DIR [file join $FLOW_ROOT rtl]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs base]
set RPT_DIR [file join $FLOW_ROOT reports base]
file mkdir $OUT_DIR
file mkdir $RPT_DIR

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
source [file join $FLOW_ROOT constraints des_arb_cdc.sdc]

check_design > [file join $RPT_DIR dc_check_design.rpt]
check_timing > [file join $RPT_DIR dc_check_timing.rpt]

compile_ultra

report_area   -hierarchy > [file join $RPT_DIR dc_area.rpt]
report_qor                > [file join $RPT_DIR dc_qor.rpt]
report_clock              > [file join $RPT_DIR dc_clock.rpt]

# SAIF 驱动功耗（同一个 VCD -> SAIF）
# 不要加 -auto_map_names：DC 的 SAIF name mapping 机制默认未启用，加了反而报
# PWR-604/PWR-634 并整体放弃标注。信号名在 RTL 顶层端口/内部网一致，直接按
# -instance_name 做路径映射即可。
read_saif -input [file join $FLOW_ROOT saif des_arb_cdc.saif] \
          -instance_name tb_des_arb_cdc_soc/dut \
          -verbose
report_power -analysis_effort high > [file join $RPT_DIR dc_power_saif.rpt]
report_power -hierarchy            > [file join $RPT_DIR dc_power_hier.rpt]

write -format verilog -hierarchy -output [file join $OUT_DIR ${DESIGN}_netlist.v]
write_sdc [file join $OUT_DIR ${DESIGN}.sdc]

exit
