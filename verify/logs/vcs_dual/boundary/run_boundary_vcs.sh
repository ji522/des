#!/bin/bash
# ============================================================================
# run_boundary_vcs.sh —— DES 边界/等价类 TB 的 VCS 版
# VM 副本专用：~/work/vcs_boundary/  （不改 ~/work/des_pipeline_soc_v2）
#
# 用法：./run_boundary_vcs.sh
# 工作目录：$ROOT/verify（TB 用 $readmemh("bkeys.mem",...) 相对路径）
# 判据：sim.log 出现 "BOUNDARY TB PASS : 18/18" 且 "property 4/4"
# ============================================================================
set -u

ROOT="$HOME/work/vcs_boundary"
VER="$ROOT/verify"

# VCS 环境（非交互 shell 不读 .bashrc，显式导出）
export VCS_HOME=/home/synopsys/vcs/O-2018.09-SP2
export VCS_TARGET_ARCH=amd64
export PATH="$VCS_HOME/bin:$PATH"
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@localhost}

cd "$VER" || { echo "!! cannot cd $VER"; exit 1; }

# TB 用裸文件名 $readmemh，复制到工作目录
cp vectors_bnd/bkeys.mem vectors_bnd/bins.mem vectors_bnd/bexps.mem . || exit 1

echo "=============================================="
echo " VCS boundary compile (VCS O-2018.09-SP2)"
echo " workdir: $VER"
echo "=============================================="
rm -rf csrc simv simv.daidir
vcs -full64 -sverilog +v2k -debug_access+all \
    -timescale=1ns/1ps \
    +incdir+"$ROOT" +incdir+"$VER" \
    -Mdir=csrc -o simv \
    "$ROOT/des_pipe_round_fb.v" \
    "$ROOT/des_pipeline_fb.v" \
    "$ROOT/key_ram_gen.v" \
    "$VER/tb_des_boundary.v" \
    -l compile.log 2>&1
rc=$?
echo "vcs exit=$rc"

if [ ! -x ./simv ]; then
    echo "!! COMPILE FAILED (no simv)"
    exit 1
fi

echo ""
echo "=============================================="
echo " RUN"
echo "=============================================="
./simv -l sim.log
echo "simv exit=$?"

echo ""
echo "=============================================="
echo " RESULT"
echo "=============================================="
grep -aE "BOUNDARY TB (PASS|FAIL)|property" sim.log | tail -5
if grep -qa "BOUNDARY TB PASS : 18/18" sim.log && grep -qa "property 4/4" sim.log; then
    echo "VCS_BOUNDARY_RESULT: PASS"
else
    echo "VCS_BOUNDARY_RESULT: FAIL"
fi
