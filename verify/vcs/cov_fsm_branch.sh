#!/bin/bash
# 汇总每个用例 modlist.txt 中目标模块的 SCORE/LINE/COND/TGL/FSM/BRANCH
cd "$HOME/work/vcs_cov" || exit 1
MODS="des_pipe_round_fb des_pipeline_fb key_ram_gen des_axis_wrap des_axil_regs des_soc_top async_fifo sync_2ff toggle_sync reset_sync des_cdc_top des_axis_cdc_top"
echo "CASE|MODULE|SCORE|LINE|COND|TGL|FSM|BRANCH"
for d in urgReport_cases/*/modlist.txt; do
  tc=$(basename "$(dirname "$d")")
  awk -v tc="$tc" -v mods="$MODS" '
    BEGIN { n=split(mods, a, " "); for (i=1;i<=n;i++) want[a[i]]=1 }
    /^[[:space:]]+[0-9]/ {
      name=$NF
      if (name in want) {
        printf "%s|%s|%s|%s|%s|%s|%s|%s\n", tc, name, $1, $2, $3, $4, $5, $6
      }
    }
  ' "$d"
done
