# ============================================================================
# pt.tcl —— PrimeTime 时序分析（2026-11-08 修订版）
#
# 相比 10-31 版：
#   1. reg2reg / in2reg / reg2out / in2out 分类报告（原来只报一条 IO 直通路径）
#   2. check_timing + report_analysis_coverage（暴露 recovery/removal 覆盖率）
#   3. report_constraint -all_violators
# ============================================================================
set DESIGN des_soc_top
set FLOW_ROOT [file normalize .]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]

if {![info exists synopsys_root]} {
    set synopsys_root /home/synopsys/pts/O-2018.06-SP1
}
set DW_LIB [file join $synopsys_root libraries syn dw_foundation.sldb]
set STD_DB [file join $PDK_DIR NangateOpenCellLibrary_typical.db]

set search_path [list . $PDK_DIR]
set link_path [list "*" $STD_DB $DW_LIB]

read_verilog [file join $OUT_DIR ${DESIGN}_netlist.v]
current_design $DESIGN
link
read_sdc [file join $OUT_DIR ${DESIGN}.sdc]

redirect -file [file join $RPT_DIR pt_check_timing.rpt] {check_timing -verbose}
redirect -file [file join $RPT_DIR pt_coverage.rpt]     {report_analysis_coverage}
redirect -file [file join $RPT_DIR pt_violators.rpt]    {report_constraint -all_violators}
redirect -file [file join $RPT_DIR pt_qor.rpt]          {report_qor}
redirect -file [file join $RPT_DIR pt_clock.rpt]        {report_clock}

# ---- 分类时序 ----
set clk_coll [get_ports clk]
set data_in  [remove_from_collection [remove_from_collection [all_inputs] $clk_coll] [get_ports rst_n]]
set ff_ck    [all_registers -clock_pins]
set ff_d     [all_registers -data_pins]

redirect -file [file join $RPT_DIR pt_timing_reg2reg.rpt]  {report_timing -from $ff_ck -to $ff_d -max_paths 10 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_timing_in2reg.rpt]   {report_timing -from $data_in -to $ff_d -max_paths 10 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_timing_reg2out.rpt]  {report_timing -from $ff_ck -to [all_outputs] -max_paths 10 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_timing_in2out.rpt]   {report_timing -from $data_in -to [all_outputs] -max_paths 10 -slack_lesser_than 100 -significant_digits 4}

# hold
redirect -file [file join $RPT_DIR pt_hold.rpt] {report_timing -delay_type min -from $ff_ck -to $ff_d -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}

# 兼容旧报告名（综合视角的整条路径，含 IO）
redirect -file [file join $RPT_DIR pt_timing.rpt] {report_timing -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}

exit
