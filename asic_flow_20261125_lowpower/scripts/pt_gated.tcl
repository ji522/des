# ============================================================================
# pt_gated.tcl —— gated 网表 PrimeTime（三时钟）
# ============================================================================
set DESIGN des_arb_cdc_top
set FLOW_ROOT [file normalize .]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs gated]
set RPT_DIR [file join $FLOW_ROOT reports gated]

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

set ff_ck [all_registers -clock_pins]
set ff_d  [all_registers -data_pins]
redirect -file [file join $RPT_DIR pt_timing_reg2reg.rpt] {report_timing -from $ff_ck -to $ff_d -max_paths 10 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_hold.rpt] {report_timing -delay_type min -from $ff_ck -to $ff_d -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_timing.rpt] {report_timing -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}

exit
