#!/bin/bash
# ============================================================================
# run_randclk_vcs.sh —— CDC 随机时钟比/相位 VCS 回归（10 组）
#
# 编译一次 tb_des_cdc_randclk，然后按 10 组 (W_HALF,C_HALF,W_PHASE,C_PHASE)
# 分别以 plusargs 运行 ./simv，每组独立日志 + 300s 超时，最后解析
# "RANDCLK PASS/FAIL" 行并写 logs/_summary.csv。
#
# 工作目录 = 脚本所在目录；该目录根部放有 vectors/*.mem 的副本，
# 供 TB 里的 $readmemh("keys.mem") 等相对名读取。
#
# 用法：bash run_randclk_vcs.sh
# ============================================================================
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1

# 非交互 SSH 不读 .bashrc，这里显式加载 VCS/Verdi 环境
# （先关 set -u 再 source，避免 .bashrc 里未定义变量在 -u 下致命退出）
set +u
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" >/dev/null 2>&1
command -v vcs >/dev/null 2>&1 || { echo "!! vcs not in PATH"; exit 1; }
set -u

LOGD="$ROOT/logs"
CLOG="$LOGD/_compile.log"
mkdir -p "$LOGD"

# 向量拷到工作目录根部（TB 用相对名 $readmemh）
cp -f "$ROOT"/vectors/*.mem "$ROOT"/ 2>/dev/null

INC="+incdir+$ROOT/rtl +incdir+$ROOT/cdc"

echo "=========================================================="
echo " CDC RANDCLK VCS regression   $(date '+%F %T')"
echo " vcs = $(command -v vcs)"
echo " VCS_HOME = ${VCS_HOME:-<unset>}"
echo "=========================================================="

echo "=== compile (once) ==="
{
  vcs -full64 -sverilog -timescale=1ns/1ps $INC \
    "$ROOT/rtl/des_pipeline_fb.v" \
    "$ROOT/rtl/key_ram_gen.v" \
    "$ROOT/rtl/des_pipe_round_fb.v" \
    "$ROOT/cdc/async_fifo.v" \
    "$ROOT/cdc/cdc_sync.v" \
    "$ROOT/cdc/des_cdc_top.v" \
    "$ROOT/tb/tb_des_cdc_randclk.v" \
    -Mdir=csrc -o simv 2>&1
} | tee "$CLOG"
if [ ! -x ./simv ]; then
    echo "!! COMPILE FAILED — see $CLOG"
    exit 1
fi
echo "compile OK -> $CLOG"
echo ""

CONFIGS="
5 2 0 0
5 2 1 3
5 2 3 1
5 3 0 2
4 2 1 0
3 2 2 1
6 2 3 0
5 1 0 1
7 2 2 3
5 4 1 2
"

SUMMARY="$LOGD/_summary.csv"
echo "idx,W_HALF,C_HALF,W_PHASE,C_PHASE,status,push,cmp,mismatch,x,extra,wfull,sec,log" > "$SUMMARY"

idx=0; npass=0; nfail=0
while read -r w c wp cp; do
    [ -z "${w:-}" ] && continue
    idx=$((idx+1))
    name="w${w}_c${c}_wp${wp}_cp${cp}"
    log="$LOGD/${name}.log"
    t0=$(date +%s)
    timeout 300 ./simv +W_HALF=$w +C_HALF=$c +W_PHASE=$wp +C_PHASE=$cp > "$log" 2>&1
    ec=$?
    t1=$(date +%s)
    sec=$((t1-t0))

    line=$(grep -aE "RANDCLK (PASS|FAIL)" "$log" | tail -1)
    if [ $ec -eq 124 ]; then
        status="TIMEOUT"; push=0; cmpv=0; mm=0; xx=0; ex=0; wf=0
    elif [[ "$line" =~ RANDCLK\ (PASS|FAIL)\ push=([0-9]+)/cmp=([0-9]+)/mismatch=([0-9]+)/x=([0-9]+)/extra=([0-9]+)\ wfull=([0-9]+) ]]; then
        status="${BASH_REMATCH[1]}"
        push="${BASH_REMATCH[2]}"; cmpv="${BASH_REMATCH[3]}"; mm="${BASH_REMATCH[4]}"
        xx="${BASH_REMATCH[5]}"; ex="${BASH_REMATCH[6]}"; wf="${BASH_REMATCH[7]}"
    else
        if [ $ec -ne 0 ]; then status="ERROR(exit=$ec)"; else status="NO-RESULT"; fi
        push=0; cmpv=0; mm=0; xx=0; ex=0; wf=0
    fi

    if [ "$status" = "PASS" ]; then npass=$((npass+1)); else nfail=$((nfail+1)); fi
    printf "  [%2d] %-20s %-10s push=%s cmp=%s mismatch=%s x=%s extra=%s wfull=%s (%ss)\n" \
        "$idx" "$name" "$status" "$push" "$cmpv" "$mm" "$xx" "$ex" "$wf" "$sec"
    echo "$idx,$w,$c,$wp,$cp,$status,$push,$cmpv,$mm,$xx,$ex,$wf,$sec,$name.log" >> "$SUMMARY"
done <<< "$CONFIGS"

echo ""
echo "========================= SUMMARY ========================="
printf "%-22s %-7s %-5s %-5s %-9s %-4s %-5s %-6s\n" config result push cmp mismatch x extra wfull
awk -F',' 'NR>1{printf "%-22s %-7s %-5s %-5s %-9s %-4s %-5s %-6s\n", \
    "w"$2"_c"$3"_wp"$4"_cp"$5, $6,$7,$8,$9,$10,$11,$12}' "$SUMMARY"
echo "TOTAL: $npass/$idx PASS"
echo "logs : $LOGD"
echo "csv  : $SUMMARY"
echo "==========================================================="
if [ $nfail -eq 0 ]; then exit 0; else exit 1; fi
