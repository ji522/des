#!/bin/bash
# ============================================================================
# run_flow.sh —— 多时钟 2 通道安全加密前端 DC -> PT -> FM
# ============================================================================
set -e

ROOT="$HOME/work/des_arb_cdc_flow_20261125"
PROJ="$HOME/work/des_pipeline_soc_v2"
BASE="$HOME/work/des_frontend_run_20261108"

mkdir -p "$ROOT"/{rtl,constraints,scripts,outputs,reports,logs,pdk/nangate45}

cp "$PROJ"/des_arb_cdc_top.v "$PROJ"/des_arb_soc_top.v \
   "$PROJ"/axis_arb2.v "$PROJ"/axis_arb_regs.v "$PROJ"/axil_2to1_demux.v \
   "$PROJ"/sync_fifo.v "$PROJ"/des_soc_top.v "$PROJ"/des_axil_regs.v \
   "$PROJ"/des_axis_wrap.v "$PROJ"/des_pipeline_fb.v "$PROJ"/des_pipe_round_fb.v \
   "$PROJ"/key_ram_gen.v "$PROJ"/sbox_funcs.v \
   "$PROJ"/cdc/async_fifo.v "$PROJ"/cdc/cdc_sync.v "$PROJ"/cdc/async_axis_fifo.v \
   "$ROOT/rtl/"

cp "$BASE"/pdk/nangate45/NangateOpenCellLibrary_typical.db \
   "$BASE"/pdk/nangate45/NangateOpenCellLibrary_typical.lib \
   "$ROOT/pdk/nangate45/"

cd "$ROOT"

echo "=== DC ==="
dc_shell -f scripts/dc_arb_cdc.tcl -output_log_file logs/dc.log

echo "=== PT ==="
pt_shell -f scripts/pt_arb_cdc.tcl -output_log_file logs/pt.log

echo "=== FM ==="
fm_shell -f scripts/fm_arb_cdc.tcl > logs/fm.log 2>&1

echo "=== KEY RESULTS ==="
grep -E "INSTANCE CHECK|Total cell area|Number of cells|Number of sequential" reports/dc_area.rpt || true
echo "--- PT QOR ---"
grep -E "Path Group|No. of Violating" reports/pt_qor.rpt | head -20 || true
echo "--- FM ---"
grep -E "SUCCEEDED|FAILED|Passing|Failing" reports/fm_status.rpt | head -10 || true
