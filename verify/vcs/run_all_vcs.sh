#!/bin/bash
# ============================================================================
# run_all_vcs.sh —— DES 工程完整回归（VCS 版）
# 对应 Windows 的 run_all.ps1（XSim 版，11 组）
#
# 用法：./run_all_vcs.sh
# 结果：$HOME/work/vcs_regress/summary.md
# ============================================================================
set -u

PROJ="$HOME/work/des_pipeline_soc_v2"
VER="$PROJ/verify"
SV="$VER/sv"
UVM="$VER/uvm"
OUT="$HOME/work/vcs_regress"
INC="-full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2"
INCDIR="+incdir+$PROJ +incdir+$VER +incdir+$SV +incdir+$UVM"
# VCS 上关掉 XSim 专用的 frontdoor workaround，让 RAL 走标准 adapter 路径。
# 这正是要验证的：标准路径在 VCS 上成立，frontdoor 只是 XSim 补丁。
STD="+define+DES_NO_FRONTDOOR"

rm -rf "$OUT"
mkdir -p "$OUT/logs"

PASS=0
FAIL=0
SUMMARY="$OUT/summary.md"
: > "$SUMMARY"
echo "| 组 | 用例 | 判定 | 证据 |" >> "$SUMMARY"
echo "|---|---|---|---|" >> "$SUMMARY"

run_case() {
    local name="$1"; local dir="$2"; local top="$3"; local files="$4"; local check="$5"
    local log="$OUT/logs/${dir}.log"
    mkdir -p "$OUT/$dir"
    (
      cd "$OUT/$dir" || exit 1
      cp "$VER"/vectors/*.mem . 2>/dev/null
      echo "=== compile $dir ==="
      vcs $INC $INCDIR $STD $files -Mdir=csrc -o simv 2>&1
      if [ ! -x ./simv ]; then
          echo "!! COMPILE FAILED"
          exit 1
      fi
      echo "=== run $dir ==="
      ./simv -l sim.log 2>&1
    ) > "$log" 2>&1

    if [ -f "$OUT/$dir/sim.log" ] && grep -qaE "$check" "$OUT/$dir/sim.log" 2>/dev/null; then
        PASS=$((PASS+1))
        echo "| $name | $dir | PASS | logs/${dir}.log |" >> "$SUMMARY"
        printf "%-32s PASS\n" "$name"
    else
        FAIL=$((FAIL+1))
        echo "| $name | $dir | **FAIL** | logs/${dir}.log |" >> "$SUMMARY"
        printf "%-32s FAIL\n" "$name"
    fi
}

echo "=============================================="
echo " DES 完整回归 (VCS O-2018.09-SP2)"
echo "=============================================="
echo ""

run_case "1 Verilog定向(42笔)"   "t1_dir"   "tb_des_pipeline_fb_v2" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $VER/tb_des_pipeline_fb_v2.v" \
    "PASS\s*:\s*42/42"

run_case "2 换钥hazard专项"      "t2_rekey" "tb_rekey_hazard" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $VER/tb_rekey_hazard.v" \
    "mismatch : 4 / 4"

run_case "3 SV约束随机(58笔)"    "t3_sv"    "tb_des_sv" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $SV/des_if.sv $SV/des_pkg.sv $SV/tb_des_sv.sv" \
    "SV ENV PASS"

run_case "4 CDC多时钟(190笔)"    "t4_cdc"   "tb_des_cdc" \
    "$PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_pipe_round_fb.v $PROJ/cdc/async_fifo.v $PROJ/cdc/cdc_sync.v $PROJ/cdc/des_cdc_top.v $VER/tb_cdc/tb_des_cdc.v" \
    "CDC TB PASS"

run_case "5 UVM回归(58笔)"       "t5_uvm"   "tb_des_uvm" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $SV/des_if.sv $UVM/des_uvm_pkg.sv $UVM/tb_des_uvm.sv" \
    "UVM ENV PASS"

run_case "6 AXI4-Stream(42笔)"   "t6_axis"  "tb_des_axis_wrap" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $SV/axis_protocol_check.sv $VER/tb_des_axis_wrap.v" \
    "AXIS TB PASS"

run_case "7 AXI4-Lite(23项)"     "t7_axil"  "tb_des_axil" \
    "$PROJ/des_axil_regs.v $VER/tb_des_axil.v" \
    "AXIL TB PASS"

run_case "8 SoC集成"             "t8_soc"   "tb_des_soc" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $PROJ/des_axil_regs.v $PROJ/des_soc_top.v $SV/axis_protocol_check.sv $VER/tb_des_soc.v" \
    "SOC TB PASS"

run_case "9 SVA负向测试"         "t9_sva"   "tb_axis_sva_neg" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $SV/axis_protocol_check.sv $VER/tb_axis_sva_neg.v" \
    "SVA-NEG PASS"

run_case "10 SoC UVM(双agent+RAL)" "t10_socuvm" "tb_des_soc_uvm" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $PROJ/des_axil_regs.v $PROJ/des_soc_top.v $SV/des_if.sv $SV/axil_if.sv $UVM/des_uvm_pkg.sv $UVM/des_axil_agent_pkg.sv $UVM/des_ral_frontdoor.sv $UVM/des_ral_pkg.sv $UVM/des_ral_adapter.sv $UVM/des_soc_env_pkg.sv $UVM/des_soc_test_pkg.sv $UVM/tb_des_soc_uvm.sv" \
    "SOC RAL TEST PASS"

run_case "11 2通道AXIS仲裁"       "t11_arb"  "tb_axis_arb2" \
    "$PROJ/sync_fifo.v $PROJ/axis_arb2.v $PROJ/axis_arb_regs.v $VER/tb_axis_arb2.v" \
    "AXIS ARB PASS"

run_case "12 2通道AXIS+DES集成"   "t12_arb_soc" "tb_des_arb_soc" \
    "$PROJ/des_pipe_round_fb.v $PROJ/des_pipeline_fb.v $PROJ/key_ram_gen.v $PROJ/des_axis_wrap.v $PROJ/des_axil_regs.v $PROJ/des_soc_top.v $PROJ/sync_fifo.v $PROJ/axis_arb2.v $PROJ/axis_arb_regs.v $PROJ/des_arb_soc_top.v $VER/tb_des_arb_soc.v" \
    "DES ARB SOC PASS"

echo ""
echo "=============================================="
printf " 结果: PASS=%d  FAIL=%d\n" "$PASS" "$FAIL"
echo "=============================================="
echo "summary -> $SUMMARY"
