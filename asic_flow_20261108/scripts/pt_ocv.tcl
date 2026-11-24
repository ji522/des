# ============================================================================
# pt_ocv.tcl —— OCV 降额时序分析（近似慢/快角）
#
# 说明：这台虚拟机的 Nangate45 只有 typical 一套库，没有 SS/FF corner 的
# .lib/.db，所以做不了真正的多 corner 时序。这里用 set_timing_derate 做
# on-chip variation 降额，作为"慢角 setup / 快角 hold"的近似：
#   late  1.05 —— 近似慢角（延时变大，卡 setup）
#   early 0.95 —— 近似快角（延时变小，卡 hold）
# 这两个数字是经验值，不是 silicon 认可的 signoff 值。
# ============================================================================
set DESIGN des_soc_top
set FLOW_ROOT [file normalize .]
set PDK_DIR [file join $FLOW_ROOT pdk nangate45]
set OUT_DIR [file join $FLOW_ROOT outputs]
set RPT_DIR [file join $FLOW_ROOT reports]
set STD_DB [file join $PDK_DIR NangateOpenCellLibrary_typical.db]

set link_path [list "*" $STD_DB]
set search_path [list . $PDK_DIR]

read_verilog [file join $OUT_DIR ${DESIGN}_netlist.v]
current_design $DESIGN
link
read_sdc [file join $OUT_DIR ${DESIGN}.sdc]

set_timing_derate -late  1.05
set_timing_derate -early 0.95
set_timing_derate -late  1.05 -net_delay
set_timing_derate -early 0.95 -net_delay

redirect -file [file join $RPT_DIR pt_ocv_setup.rpt] {report_timing -max_paths 10 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_ocv_hold.rpt]  {report_timing -delay_type min -max_paths 10 -significant_digits 4}
redirect -file [file join $RPT_DIR pt_ocv_qor.rpt]   {report_qor}

exit
