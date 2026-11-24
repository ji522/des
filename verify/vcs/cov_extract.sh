#!/bin/bash
# 从 urgReport/modinfo.txt 中抽取指定模块的覆盖率详情摘要
cd "$HOME/work/vcs_cov" || exit 1
MODS="des_soc_top des_axis_cdc_top des_axil_regs reset_sync des_pipeline_fb key_ram_gen des_axis_wrap async_fifo des_cdc_top des_pipe_round_fb"
for m in $MODS; do
  echo "########## $m"
  awk -v m="Module : $m" '
    index($0,"Module : ")==1 {if (f && $0 != m) exit; if ($0==m) f=1}
    f {print}
  ' urgReport/modinfo.txt | grep -E \
    "^(SCORE|  *[0-9]+\.[0-9]+|Totals|Port Bits|Signal Bits|Ports |Signals )|Not Covered|^[[:space:]]*[0-9]+[[:space:]]+0/|^[a-zA-Z_]+(\[[0-9:.]+\])? +No " | head -35
  echo ""
done
