#!/bin/bash
# ============================================================================
# run_cov_vcs.sh —— DES 工程 VCS 覆盖率回归（line/cond/fsm/tgl/branch）
#
# 用法（VM 上）：  ./run_cov_vcs.sh
# 输出：           $HOME/work/vcs_cov/
#                    cov_db/<case>.vdb/  每个用例独立 VDB（-cm_dir，VCS 自动加 .vdb）
#                    urgReport/          urg 合并后的文本报告
#                    logs/<case>.log     编译+仿真日志
#                    run_status.txt      每个用例的编译/仿真/判定
#
# 覆盖率口径（与原 run_all_vcs.sh 完全一致，只增加 -cm 选项）：
#   - 编译/运行都加 -cm line+cond+fsm+tgl+branch
#   - 每个用例独立 -cm_name，VDB 放在 cov_db/<case>
#   - 合并：urg -dir cov_db/* （不同 top 的 VDB 不能共用同一个 -cm_dir，
#     否则后编译的 design base 会覆盖前面的，urg 报 Instance not found）
#
# PASS/FAIL 判据原样沿用 run_all_vcs.sh，未做任何改动。
# ============================================================================
set -u

PROJ="$HOME/work/des_pipeline_soc_v2"
VER="$PROJ/verify"
SV="$VER/sv"
UVM="$VER/uvm"
ACDC="$UVM/axis_cdc"
CDC="$PROJ/cdc"
OUT="$HOME/work/vcs_cov"
VDBROOT="$OUT/cov_db"
REPORT="$OUT/urgReport"
STATUS="$OUT/run_status.txt"

INC="-full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2"
INCDIR="+incdir+$PROJ +incdir+$VER +incdir+$SV +incdir+$UVM +incdir+$ACDC"
# VCS 上关掉 XSim 专用的 frontdoor workaround（与 run_all_vcs.sh 相同）
STD="+define+DES_NO_FRONTDOOR"
METRICS="line+cond+fsm+tgl+branch"
TIMEOUT=1800

rm -rf "$OUT"
mkdir -p "$OUT/logs" "$VDBROOT"
: > "$STATUS"

PASS=0
FAIL=0
SKIP=0
MERGE_LIST=""

echo "=============================================="
echo " DES VCS 覆盖率回归 (O-2018.09-SP2)"
echo " metrics: $METRICS"
echo "=============================================="
df -h "$HOME" | tail -1

# run_case <case> <pass_regex> <files...>
run_case() {
    local dir="$1"; local check="$2"; shift 2
    local work="$OUT/$dir"
    local log="$OUT/logs/${dir}.log"
    local cmdir="$VDBROOT/$dir"     # VCS 实际生成 ${dir}.vdb
    local t0 t1 cstat sstat judge real_vdb cand

    echo ""
    echo "--------------------------------------------------------------"
    echo "[CASE] $dir"
    echo "--------------------------------------------------------------"
    mkdir -p "$work"
    cp "$VER"/vectors/*.mem "$work"/ 2>/dev/null

    t0=$(date +%s)
    (
        cd "$work" || exit 1
        echo "=== compile $dir ==="
        timeout $TIMEOUT vcs $INC $INCDIR $STD \
            -cm $METRICS -cm_dir "$cmdir" -cm_name "$dir" \
            "$@" -Mdir=csrc -o simv 2>&1
    ) > "$log" 2>&1

    if [ ! -x "$work/simv" ]; then
        cstat="COMPILE_FAIL"
        echo "" >> "$STATUS"
        echo "CASE $dir COMPILE_FAIL log=logs/${dir}.log" >> "$STATUS"
        FAIL=$((FAIL+1))
        printf "%-18s COMPILE_FAIL\n" "$dir"
        return
    fi
    cstat="COMPILE_OK"

    echo "=== run $dir ===" >> "$log"
    (
        cd "$work" || exit 1
        timeout $TIMEOUT ./simv -cm $METRICS -cm_dir "$cmdir" -cm_name "$dir" -l sim.log 2>&1
    ) >> "$log" 2>&1
    sstat="SIM_DONE"
    t1=$(date +%s)

    if [ -f "$work/sim.log" ] && grep -qaE "$check" "$work/sim.log"; then
        judge="PASS"; PASS=$((PASS+1))
    else
        judge="FAIL"; FAIL=$((FAIL+1))
    fi

    # VCS 会在 -cm_dir 后自动补 .vdb；兼容两种情况
    real_vdb=""
    for cand in "$cmdir.vdb" "$cmdir"; do
        if [ -d "$cand/snps/coverage/db/testdata" ]; then real_vdb="$cand"; break; fi
    done
    if [ -n "$real_vdb" ]; then
        MERGE_LIST="$MERGE_LIST $real_vdb"
        sstat="COV_OK"
    else
        sstat="COV_MISSING"
    fi

    echo "CASE $dir $cstat $sstat JUDGE=$judge TIME=$((t1-t0))s log=logs/${dir}.log" >> "$STATUS"
    printf "%-18s %s  (%ds)\n" "$dir" "$judge" "$((t1-t0))"
    grep -aE "$check" "$work/sim.log" 2>/dev/null | head -1
}

# ---------------- 用例（按优先级）----------------
run_case t1_dir "PASS[[:space:]]*:[[:space:]]*42/42" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$VER/tb_des_pipeline_fb_v2.v"

run_case t3_sv "SV ENV PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$SV/des_if.sv" "$SV/des_pkg.sv" "$SV/tb_des_sv.sv"

run_case t5_uvm "UVM ENV PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$SV/des_if.sv" "$UVM/des_uvm_pkg.sv" "$UVM/tb_des_uvm.sv"

run_case t6_axis "AXIS TB PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" "$SV/axis_protocol_check.sv" "$VER/tb_des_axis_wrap.v"

run_case t7_axil "AXIL TB PASS" \
    "$PROJ/des_axil_regs.v" "$VER/tb_des_axil.v"

run_case t8_soc "SOC TB PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" "$PROJ/des_axil_regs.v" "$PROJ/des_soc_top.v" \
    "$SV/axis_protocol_check.sv" "$VER/tb_des_soc.v"

run_case t10_socuvm "SOC RAL TEST PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" "$PROJ/des_axil_regs.v" "$PROJ/des_soc_top.v" \
    "$SV/des_if.sv" "$SV/axil_if.sv" \
    "$UVM/des_uvm_pkg.sv" "$UVM/des_axil_agent_pkg.sv" "$UVM/des_ral_frontdoor.sv" \
    "$UVM/des_ral_pkg.sv" "$UVM/des_ral_adapter.sv" "$UVM/des_soc_env_pkg.sv" \
    "$UVM/des_soc_test_pkg.sv" "$UVM/tb_des_soc_uvm.sv"

run_case t4_cdc "CDC TB PASS" \
    "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" "$PROJ/des_pipe_round_fb.v" \
    "$CDC/async_fifo.v" "$CDC/cdc_sync.v" "$CDC/des_cdc_top.v" \
    "$VER/tb_cdc/tb_des_cdc.v"

# 可选：AXIS+CDC 合并顶层（纯 Verilog TB）
run_case t_axis_cdc "AXIS-CDC TB PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" "$PROJ/des_axil_regs.v" \
    "$CDC/async_fifo.v" "$CDC/cdc_sync.v" "$CDC/des_axis_cdc_top.v" \
    "$VER/tb_cdc/tb_des_axis_cdc.v"

# 可选：AXIS+CDC 合并顶层（UVM）
run_case t_axis_cdc_uvm "AXIS CDC UVM PASS" \
    "$PROJ/des_pipe_round_fb.v" "$PROJ/des_pipeline_fb.v" "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" "$PROJ/des_axil_regs.v" \
    "$CDC/async_fifo.v" "$CDC/cdc_sync.v" "$CDC/des_axis_cdc_top.v" \
    "$SV/axil_if.sv" "$ACDC/axis_cdc_if.sv" \
    "$UVM/des_axil_agent_pkg.sv" "$ACDC/axis_cdc_pkg.sv" \
    "$ACDC/tb_des_axis_cdc_uvm.sv"

# ---------------- 合并 ----------------
echo ""
echo "=============================================="
echo " urg 合并"
echo "=============================================="
if [ -z "$MERGE_LIST" ]; then
    echo "!! 没有可合并的覆盖率数据库"
    echo "MERGE none" >> "$STATUS"
    exit 1
fi
echo "merge dirs:$MERGE_LIST"
rm -rf "$OUT/cov_merged.vdb" "$OUT/cov_merged_full5.vdb" "$REPORT" "$OUT/urgReport_full5"

# (1) 全指标合并：line/cond/fsm/tgl/branch 都有，但 VCS 2018.09 只能按
#     “同一 design”合并；各用例 top/实例层次不同，实际只保留首个 VDB 的
#     design（本工程为 t1_dir 的 4 个模块）。
# shellcheck disable=SC2086
urg -full64 -dir $MERGE_LIST -dbname "$OUT/cov_merged_full5.vdb" \
    -report "$OUT/urgReport_full5" -format text > "$OUT/urg_merge_full5.log" 2>&1
echo "urg(full5) rc=$?"

# (2) 跨层次模块合并（VCS flex mode）：line/cond/tgl 可跨不同 top 合并，
#     模块集合取并集（26 个）；VCS O-2018.09 的 flex mode 不支持 FSM，
#     branch 也无法跨 design 载入，故本报告只有 line/cond/tgl。
# shellcheck disable=SC2086
urg -full64 -flex_merge modules -dir $MERGE_LIST -dbname "$OUT/cov_merged.vdb" \
    -report "$REPORT" -format text > "$OUT/urg_merge.log" 2>&1
echo "urg(flex) rc=$?"
ls "$REPORT" 2>&1 | head
echo "MERGE_OK dirs=$(echo $MERGE_LIST | wc -w)" >> "$STATUS"

echo ""
echo "=============================================="
printf " 结果: PASS=%d  FAIL=%d\n" "$PASS" "$FAIL"
echo " cov_db  -> $VDBROOT"
echo " report  -> $REPORT"
echo " status  -> $STATUS"
echo "=============================================="
