#!/bin/bash
# ============================================================================
# run_axis_arb_vcs.sh —— 2 通道 AXIS 仲裁器 + DES SoC 集成（VCS 版）
# 用法：bash verify/vcs/run_axis_arb_vcs.sh
# 结果：$HOME/work/vcs_axis_arb/logs/*.log
# ============================================================================
set -u

PROJ="$HOME/work/des_pipeline_soc_v2"
VER="$PROJ/verify"
OUT="$HOME/work/vcs_axis_arb"
INC="-full64 -sverilog -timescale=1ns/1ps"
INCDIR="+incdir+$PROJ +incdir+$VER"

rm -rf "$OUT"
mkdir -p "$OUT/logs"

PASS=0
FAIL=0

run_case() {
    local name="$1"
    local top="$2"
    local files="$3"
    local check="$4"
    local dir="$OUT/$top"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        cp "$VER"/vectors/*.mem . 2>/dev/null
        echo "=== compile $top ==="
        vcs $INC $INCDIR $files -Mdir=csrc -o simv 2>&1
        if [ ! -x ./simv ]; then
            echo "!! COMPILE FAILED"
            exit 1
        fi
        echo "=== run $top ==="
        ./simv -l sim.log 2>&1
    ) > "$OUT/logs/$top.log" 2>&1

    if [ -f "$dir/sim.log" ] && grep -qaE "$check" "$dir/sim.log" 2>/dev/null; then
        PASS=$((PASS+1))
        printf "%-24s PASS\n" "$name"
    else
        FAIL=$((FAIL+1))
        printf "%-24s FAIL  (see %s)\n" "$name" "$OUT/logs/$top.log"
    fi
}

echo "=============================================="
echo " 2-channel AXIS arbiter (VCS O-2018.09-SP2)"
echo "=============================================="

run_case "standalone" "tb_axis_arb2" \
    "$PROJ/sync_fifo.v $PROJ/axis_arb2.v $PROJ/axis_arb_regs.v $VER/tb_axis_arb2.v" \
    "AXIS ARB PASS"

run_case "des_soc" "tb_des_arb_soc" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $PROJ/des_axil_regs.v $PROJ/des_soc_top.v $PROJ/sync_fifo.v $PROJ/axis_arb2.v $PROJ/axis_arb_regs.v $PROJ/des_arb_soc_top.v $VER/tb_des_arb_soc.v" \
    "DES ARB SOC PASS"

echo "----------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
