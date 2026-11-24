# CDC 随机时钟比/相位 —— VCS 双工具回归报告

- 日期：2026-11-15
- 工具：Synopsys VCS O-2018.09-SP2_Full64（CentOS 7.9 虚拟机 `IC_EDA`，`ICer@192.168.188.100`）
- 对照工具：Vivado 2018.3 XSim（Windows 11 + PowerShell 7，见 [`_cdc_randclk_report.md`](_cdc_randclk_report.md)）
- 被测设计：`cdc/des_cdc_top.v`（异步 FIFO + 2FF/toggle 同步 + reset_sync），RTL 未做任何修改
- TB：`verify/tb_cdc/tb_des_cdc_randclk.v`（与 XSim 回归同一份，未修改）
- VM 工作目录：`/home/ICer/work/vcs_randclk/`（**未改动** `/home/ICer/work/des_pipeline_soc_v2`）
- Windows 侧只新增本报告与 `verify/logs/vcs_dual/cdc_randclk/` 下的日志，未改任何源码

## 1. 结论

**VCS 上 10/10 PASS。** 10 组配置每组均为
`RANDCLK PASS push=190/cmp=190/mismatch=0/x=0/extra=0`，与 XSim 的判定完全一致
（XSim 10/10 PASS）。两工具的**功能结论相同**，差异只体现在不作为判据的
信息量 `wfull` 与仿真结束时刻上，原因见第 6 节（`$urandom` 随机流因工具而异）。

## 2. 同步到虚拟机的内容

从共享盘 `/mnt/hgfs/IC项目/des_final_version/des_pipeline_soc_v2/` 复制到
`~/work/vcs_randclk/`，源文件与 VM 副本 **md5 逐一相同**：

| 类别 | 文件 | 目标子目录 |
|---|---|---|
| RTL | `des_pipeline_fb.v`, `key_ram_gen.v`, `des_pipe_round_fb.v`, `sbox_funcs.v` | `rtl/` |
| CDC | `cdc/async_fifo.v`, `cdc/cdc_sync.v`, `cdc/des_cdc_top.v` | `cdc/` |
| TB | `verify/tb_cdc/tb_des_cdc_randclk.v` | `tb/` |
| 向量 | `verify/vectors/{keys,ins,exps,dkeys,dins,dexps}.mem` | `vectors/`（并复制到工作目录根部供 `$readmemh` 相对名读取） |

> `des_pipe_round_fb.v` 里 `` `include "sbox_funcs.v" ``，编译时用
> `+incdir+rtl` 提供搜索路径——这一点与 XSim 脚本的 `-i $proj` 等价。

## 3. 运行脚本 `run_randclk_vcs.sh`

位于 VM `~/work/vcs_randclk/run_randclk_vcs.sh`（副本随日志一起回拷）。要点：

- 编译**一次**：
  ```
  vcs -full64 -sverilog -timescale=1ns/1ps \
      +incdir+rtl +incdir+cdc \
      rtl/des_pipeline_fb.v rtl/key_ram_gen.v rtl/des_pipe_round_fb.v \
      cdc/async_fifo.v cdc/cdc_sync.v cdc/des_cdc_top.v \
      tb/tb_des_cdc_randclk.v -Mdir=csrc -o simv
  ```
- 循环 10 组，每组：`timeout 300 ./simv +W_HALF=.. +C_HALF=.. +W_PHASE=.. +C_PHASE=..`
  （工作目录即脚本目录，`.mem` 已在根部，`$readmemh("keys.mem")` 能找到）。
- 每组独立日志 `logs/<name>.log`；正则解析 `RANDCLK PASS/FAIL`；
  写 `logs/_summary.csv`；编译日志 `logs/_compile.log`。
- 退出码：全部 PASS 返回 0，否则返回 1。

复现：
```bash
ssh ICer@192.168.188.100   # 密码 2022
cd ~/work/vcs_randclk && bash run_randclk_vcs.sh
```

> 环境注意：非交互 SSH 不会加载 `~/.bashrc`，脚本内部在 `source ~/.bashrc`
> **之前先 `set +u`**（`.bashrc` 里 `$LD_LIBRARY_PATH` 等未定义变量在 `set -u`
> 下会让非交互 shell 直接退出），source 完再 `set -u`。此外 `vcs -ID` 在本机
> 会误报找不到编译器（它去 `$VCS_HOME/linux` 找，而实际是 `linux64`），
> 但正常 `vcs` 编译/仿真无误——脚本用 `command -v vcs` 判存在性，不依赖 `vcs -ID`。

## 4. VCS 结果（10 组）

频率：写时钟 `500/W_HALF` MHz、读时钟 `500/C_HALF` MHz；读/写频率比 = `W_HALF/C_HALF`。

| # | (W_HALF,C_HALF,W_PHASE,C_PHASE) | 写时钟 | 读时钟 | 读/写比 | 结果 | push/cmp | mismatch | x | extra | wfull | 结束(ns) | CPU(s) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | (5,2,0,0) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 308 | 39142 | 0.12 |
| 2 | (5,2,1,3) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 292 | 38169 | 0.13 |
| 3 | (5,2,3,1) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 307 | 39135 | 0.12 |
| 4 | (5,3,0,2) | 100.0 MHz | 166.7 MHz | 1.67x | PASS | 190/190 | 0 | 0 | 0 | 663 | 57539 | 0.13 |
| 5 | (4,2,1,0) | 125.0 MHz | 250.0 MHz | 2.00x | PASS | 190/190 | 0 | 0 | 0 | 413 | 39482 | 0.14 |
| 6 | (3,2,2,1) | 166.7 MHz | 250.0 MHz | 1.50x | PASS | 190/190 | 0 | 0 | 0 | 605 | 38395 | 0.16 |
| 7 | (6,2,3,0) | 83.3 MHz | 250.0 MHz | 3.00x | PASS | 190/190 | 0 | 0 | 0 | 225 | 38910 | 0.13 |
| 8 | (5,1,0,1) | 100.0 MHz | 500.0 MHz | 5.00x | PASS | 190/190 | 0 | 0 | 0 | 74 | 21044 | 0.13 |
| 9 | (7,2,2,3) | 71.4 MHz | 250.0 MHz | 3.50x | PASS | 190/190 | 0 | 0 | 0 | 191 | 40153 | 0.14 |
| 10 | (5,4,1,2) | 100.0 MHz | 125.0 MHz | 1.25x | PASS | 190/190 | 0 | 0 | 0 | 931 | 75082 | 0.14 |

**汇总：10/10 PASS；每组 push=190、cmp=190、mismatch=0、x=0、extra=0、rekey=16。**
单组 CPU 时间 0.12–0.16 s；XSim 侧是 PowerShell Stopwatch 墙钟 3.4–5.5 s/组（含进程启动），两者口径不同，不能直接横比“快慢”。

## 5. 与 XSim 对照

两工具对**功能判据**（190/190、mismatch/x/extra 全 0）结果完全一致。
差异只在不作判据的信息量与结束时刻：

| # | 配置 | XSim wfull | VCS wfull | Δwfull | XSim 结束(ns) | VCS 结束(ns) | Δ结束 |
|---|---|---|---|---|---|---|---|
| 1 | (5,2,0,0) | 406 | 308 | −98 | 39778 | 39142 | −636 |
| 2 | (5,2,1,3) | 409 | 292 | −117 | 39781 | 38169 | −1612 |
| 3 | (5,2,3,1) | 404 | 307 | −97 | 39779 | 39135 | −644 |
| 4 | (5,3,0,2) | 514 | 663 | +149 | 58019 | 57539 | −480 |
| 5 | (4,2,1,0) | 534 | 413 | −121 | 38882 | 39482 | +600 |
| 6 | (3,2,2,1) | 617 | 605 | −12 | 38675 | 38395 | −280 |
| 7 | (6,2,3,0) | 250 | 225 | −25 | 39546 | 38910 | −636 |
| 8 | (5,1,0,1) | 139 | 74 | −65 | 21488 | 21044 | −444 |
| 9 | (7,2,2,3) | 96 | 191 | +95 | 39829 | 40153 | +324 |
| 10 | (5,4,1,2) | 960 | 931 | −29 | 76874 | 75082 | −1792 |

观察：

- `wfull` 在两工具里**都非零**（VCS 74–931，XSim 96–960），说明各组都真实进入了
  FIFO 满 / 源侧节流路径，不是空跑。
- `wfull` 数值不同但量级一致：最大相对差约 29%（组 4，149/514），并非只有第 8/9 组偏大。
- 结束时刻最大偏差约 **4.05%**（组 2，1612 ns / 39781 ns）；多数组 VCS 略早，偏差方向与 `wfull` 偏差同向。

## 6. 差异分析与原因（如实记录）

### 6.1 功能结果无差异

10 组没有任何 mismatch / extra / X。VCS 与 XSim 对同一 RTL、同一向量、同一 plusargs
给出同一判定，说明差异**不是 RTL 功能问题**，不需要（也没有）改 RTL 去“掩盖”。

### 6.2 `wfull` / 结束时刻差异 = 两工具 `$urandom` 随机流不同

TB 的下游反压（85% ready + 每 8 笔 250 拍长 stall）和字间随机间隔都用
`$urandom_range` 生成。`$urandom` 的实现和默认种子是**工具相关的**，VCS 与 XSim
不是同一串随机数，因此：

- 长 stall 落在激励流的哪个位置不同 → FIFO 满的拍数（`wfull`）不同；
- 随机间隔不同 → 整条激励的墙钟/仿真时间略有差别；
- 但激励**结构**（3 轮×(28+14)+64、每次换钥前 drain、两域复位错开 #37/#50）逐行相同，
  所以 190 笔对齐判据不受影响。

这与 XSim 报告 7.3 的发现一脉相承：即使在 XSim 内部，仅调用 `$value$plusargs`
就会改变 `$urandom` 序列。换到 VCS 后随机流自然又是另一串。

### 6.3 VCS 结果可复现（非随机抖动）

同一配置连续跑两次（A/B）`wfull` 完全一致，例如：
- 组 1 `(5,2,0,0)`：两次均 308；
- 组 9 `(7,2,2,3)`：两次均 191。

即 VCS 的随机流在**工具内确定性**（默认种子固定），`wfull` 的差异来自
“VCS 与 XSim 不同”，而不是“每次跑都不同”。整份回归重跑一次也逐组复现了上表数值。

### 6.4 公共时钟沿

与 XSim 报告 7.2 一致：整数 ns 半周期下，多数配置两域存在同时翻转的时刻
（如 (5,2,0,0) 每 10 ns、(5,1,0,1) 读时钟每 1 ns 翻一次必然覆盖写沿）。
两个零延迟仿真器都用非阻塞赋值 + 事件调度化解，不建模亚稳态/建立保持。
**本次 VCS 通过同样只说明功能协议正确，不是 CDC 时序签核。**

### 6.5 工具层面的现象

- 编译无 error、无功能 warning（`_compile.log` 里唯一被 grep 命中的“error”是链接命令
  里的库名 `-lerrorinf`，不是报错）。
- `$finish` 都从 TB 第 230 行正常返回，无 watchdog 超时，无 300 s 脚本超时。

## 7. 产物

Windows：`F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\logs\vcs_dual\cdc_randclk\`

| 文件 | 内容 |
|---|---|
| `_compile.log` | vcs 编译输出 |
| `_summary.csv` | 10 组汇总（idx, W_HALF, C_HALF, W_PHASE, C_PHASE, status, push, cmp, mismatch, x, extra, wfull, sec, log） |
| `w5_c2_wp0_cp0.log` … `w5_c4_wp1_cp2.log` | 每组日志（含 `RANDCLK CFG`、`RANDCLK STAT`、`RANDCLK PASS`、`$finish`) |
| `run_randclk_vcs.sh` | 回归脚本副本（provenance） |

VM：`/home/ICer/work/vcs_randclk/`（含 `rtl/ cdc/ tb/ vectors/ logs/ simv run_randclk_vcs.sh`）。

## 8. 局限

1. 与 XSim 报告相同：整数 ns 半周期有公共沿，零延迟仿真不建模亚稳态；
2. 只覆盖 10 个离散（半周期, 相位）点，未做相位整周期扫描、未加 jitter/占空比/频偏；
3. 未注入 `+ntb_random_seed`，每组只有一条固定的随机反压轨迹（工具内可复现，
   但不等于覆盖所有 stall 分布）；
4. 只测了读时钟不慢于写时钟（1.25x–5x），读慢于写的方向未覆盖；
5. 本回归是行为级功能仿真，不替代 Spyglass CDC / `cdc.xdc` 的签核流程。

## 9. 结论

在 **不改 RTL / TB / 向量** 的前提下，把 CDC 随机时钟回归在 VCS O-2018.09-SP2 上跑通：
**10/10 PASS，190/190 逐笔对齐，mismatch/x/extra 全 0，rekey=16**。
与 XSim 的功能判定完全一致；`wfull` 与结束时刻的差异由两工具 `$urandom` 随机流不同
造成（VCS 内部确定性、可复现），不影响“190 笔全对”的结论，也不构成 RTL 缺陷。
