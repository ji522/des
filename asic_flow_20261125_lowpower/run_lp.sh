#!/bin/bash
# ============================================================================
# run_lp.sh —— 低功耗对比：基线 vs DC 自动时钟门控，同一份 SAIF
# ============================================================================
set -e

ROOT="$HOME/work/des_arb_cdc_lp_20261125"
PROJ="$HOME/work/des_pipeline_soc_v2"
BASE="$HOME/work/des_frontend_run_20261108"

mkdir -p "$ROOT"/{rtl,constraints,scripts,outputs,reports,logs,pdk/nangate45,saif}

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

if [ -f "$HOME/work/des_arb_cdc.saif" ]; then
    cp "$HOME/work/des_arb_cdc.saif" "$ROOT/saif/des_arb_cdc.saif"
fi

cd "$ROOT"

echo "=== DC baseline ==="
dc_shell -f scripts/dc_base_saif.tcl -output_log_file logs/dc_base.log

echo "=== DC gated ==="
dc_shell -f scripts/dc_gated_saif.tcl -output_log_file logs/dc_gated.log

echo "=== PT gated ==="
pt_shell -f scripts/pt_gated.tcl -output_log_file logs/pt_gated.log

echo "=== FM gated ==="
fm_shell -f scripts/fm_gated.tcl > logs/fm_gated.log 2>&1

echo "=== KEY RESULTS ==="
echo "--- baseline area ---"
grep -E "Number of cells|Number of sequential|Total cell area" reports/base/dc_area.rpt || true
echo "--- gated area ---"
grep -E "Number of cells|Number of sequential|Total cell area" reports/gated/dc_area.rpt || true
echo "--- ICG ---"
grep -E "CLOCK GATING" logs/dc_gated.log || true
echo "--- baseline power ---"
grep -E "Total Dynamic Power|Cell Leakage Power|clock_network|register" reports/base/dc_power_saif.rpt | head -10 || true
echo "--- gated power ---"
grep -E "Total Dynamic Power|Cell Leakage Power|clock_network|register" reports/gated/dc_power_saif.rpt | head -10 || true
echo "--- PT gated ---"
grep -E "Path Group|No. of Violating" reports/gated/pt_qor.rpt | head -20 || true
echo "--- FM gated ---"
grep -E "SUCCEEDED|FAILED|Passing|Failing" reports/gated/fm_status.rpt | head -8 || true
