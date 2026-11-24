# PrimeTime signoff-style timing analysis for the DC netlist.
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

redirect -file [file join $RPT_DIR pt_timing.rpt] {report_timing -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_hold.rpt] {report_timing -delay_type min -max_paths 10 -nworst 1 -slack_lesser_than 100 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_qor.rpt] {report_qor}
redirect -file [file join $RPT_DIR pt_clock.rpt] {report_clock}

exit


