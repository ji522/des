#!/bin/bash
# ============================================================================
# run_soc_uvm_vcs.sh —— SoC UVM 回归的 VCS 版本
# 对应 Windows 上的 run_soc_uvm.ps1（XSim 版）
#
# 用法：./run_soc_uvm_vcs.sh [frontdoor|no_frontdoor]
#   frontdoor    : 保留 uvm_reg_frontdoor（XSim 的 workaround）
#   no_frontdoor : 关闭 frontdoor，走标准 adapter 路径（VCS 下应该能通）
# ============================================================================
set -u

MODE=${1:-frontdoor}
PROJ="$HOME/work/des_pipeline_soc_v2"
VER="$PROJ/verify"
UVM="$PROJ/verify/uvm"
SV="$VER/sv"
UVMLIB=/home/synopsys/vcs/O-2018.09-SP2/etc/uvm-1.2
OUT="$HOME/work/vcs_out_${MODE}"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$VER"/vectors/*.mem "$OUT"/ 2>/dev/null

PLUS=""
if [ "$MODE" = "no_frontdoor" ]; then
    PLUS="+define+DES_NO_FRONTDOOR"
    echo "[INFO] 关闭 frontdoor，走标准 adapter 路径"
else
    echo "[INFO] 保留 frontdoor"
fi

cd "$OUT" || exit 1

vcs -full64 -sverilog -timescale=1ns/1ps \
    -ntb_opts uvm-1.2 \
    -debug_access+all -kdb \
    $PLUS \
    -Mdir=csrc \
    +incdir+"$PROJ" \
    +incdir+"$VER" \
    +incdir+"$SV" \
    -o simv \
    \
    "$PROJ/des_pipe_round_fb.v" \
    "$PROJ/des_pipeline_fb.v" \
    "$PROJ/key_ram_gen.v" \
    "$PROJ/des_axis_wrap.v" \
    "$PROJ/des_axil_regs.v" \
    "$PROJ/des_soc_top.v" \
    \
    "$SV/des_if.sv" \
    "$SV/axil_if.sv" \
    \
    "$UVM/des_uvm_pkg.sv" \
    "$UVM/des_axil_agent_pkg.sv" \
    "$UVM/des_ral_frontdoor.sv" \
    "$UVM/des_ral_pkg.sv" \
    "$UVM/des_ral_adapter.sv" \
    "$UVM/des_soc_env_pkg.sv" \
    "$UVM/des_soc_test_pkg.sv" \
    "$UVM/tb_des_soc_uvm.sv" \
    2>&1 | tee compile.log

echo ""
echo "=============================================="
echo " 编译结果"
echo "=============================================="
if [ ! -x ./simv ]; then
    echo "!! 编译失败，见 compile.log"
    exit 1
fi
echo "编译成功"

echo ""
echo "=============================================="
echo " 运行仿真"
echo "=============================================="
./simv -l sim.log 2>&1 | tail -40

echo ""
echo "=============================================="
echo " 关键结果"
echo "=============================================="
grep -a -E "SOC RAL TEST|UVM_ERROR :|UVM_FATAL :|REF-OK|REF-LOST" sim.log | head -10
