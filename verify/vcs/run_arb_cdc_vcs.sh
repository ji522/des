#!/bin/bash
# ============================================================================
# run_arb_cdc_vcs.sh —— 多时钟 2 通道安全加密前端（VCS）
# ============================================================================
set -u

PROJ="$HOME/work/des_pipeline_soc_v2"
VER="$PROJ/verify"
OUT="$HOME/work/vcs_arb_cdc"
INC="-full64 -sverilog -timescale=1ns/1ps"
INCDIR="+incdir+$PROJ +incdir+$VER"

rm -rf "$OUT"
mkdir -p "$OUT/logs"
DIR="$OUT/arb_cdc"
mkdir -p "$DIR"

(
    cd "$DIR" || exit 1
    cp "$VER"/vectors/*.mem . 2>/dev/null
    echo "=== compile tb_des_arb_cdc_soc ==="
    vcs $INC $INCDIR \
        "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" \
        "$PROJ/key_ram_gen.v" "$PROJ/des_axis_wrap.v" \
        "$PROJ/des_axil_regs.v" "$PROJ/des_soc_top.v" \
        "$PROJ/sync_fifo.v" "$PROJ/axis_arb2.v" \
        "$PROJ/axis_arb_regs.v" "$PROJ/axil_2to1_demux.v" \
        "$PROJ/des_arb_soc_top.v" \
        "$PROJ/cdc/async_fifo.v" "$PROJ/cdc/cdc_sync.v" \
        "$PROJ/cdc/async_axis_fifo.v" "$PROJ/des_arb_cdc_top.v" \
        "$VER/sv/axis_arb_check.sv" "$VER/tb_des_arb_cdc_soc.v" \
        -Mdir=csrc -o simv 2>&1
    if [ ! -x ./simv ]; then
        echo "!! COMPILE FAILED"
        exit 1
    fi
    echo "=== run tb_des_arb_cdc_soc ==="
    ./simv -l sim.log 2>&1
) > "$OUT/logs/tb_des_arb_cdc_soc.log" 2>&1

if [ -f "$DIR/sim.log" ] && grep -qaE "DES ARB CDC PASS" "$DIR/sim.log"; then
    echo "arb_cdc PASS"
    exit 0
else
    echo "arb_cdc FAIL  (see $OUT/logs/tb_des_arb_cdc_soc.log)"
    exit 1
fi
