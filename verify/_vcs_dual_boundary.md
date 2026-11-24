# DES 边界向量 TB 在 VCS 上的双跑报告

- 工程：`des_final_version\des_pipeline_soc_v2`
- 日期：2026-11-15
- 结论：**VCS 上编译零错误零警告，仿真 `BOUNDARY TB PASS : 18/18  (property 4/4)`，
  与 XSim 结果逐笔、逐时间戳完全一致。VM 副本无需修改 TB 或 RTL。**
- 约束遵守：只动了 VM 副本 `~/work/vcs_boundary/`；Windows 原 TB / RTL / `run_boundary.ps1`
  未改；Windows 侧只新增日志与本报替代告。原 `~/work/des_pipeline_soc_v2/` 未触碰。

---

## 1. 环境与路径

| 项 | 值 |
|---|---|
| 工具 | VCS `O-2018.09-SP2_Full64`（VM: `/home/synopsys/vcs/O-2018.09-SP2`） |
| 平台 | CentOS 7.9 虚拟机 `IC_EDA`，`ICer@192.168.188.100` |
| VM 运行目录 | `~/work/vcs_boundary/verify/`（新增副本，与 `~/work/des_pipeline_soc_v2` 隔离） |
| 仿真工作目录 | `~/work/vcs_boundary/verify/`（TB 用相对文件名 `$readmemh`） |
| Windows 日志回拷 | `verify/logs/vcs_dual/boundary/` |

---

## 2. 同步清单（Windows → VM）

按 `run_boundary.ps1` 第 41-43 行列出的 RTL，再加 `des_pipe_round_fb.v` 用
`` `include "sbox_funcs.v" `` 引入的依赖：

| 文件 | Windows 源 | VM 目标 | MD5 一致 |
|---|---|---|---|
| `des_pipe_round_fb.v` | 工程根 | `~/work/vcs_boundary/` | ✅ |
| `des_pipeline_fb.v`   | 工程根 | `~/work/vcs_boundary/` | ✅ |
| `key_ram_gen.v`       | 工程根 | `~/work/vcs_boundary/` | ✅ |
| `sbox_funcs.v`        | 工程根（include 依赖） | `~/work/vcs_boundary/` | ✅ |
| `tb_des_boundary.v`   | `verify/` | `~/work/vcs_boundary/verify/` | ✅ |
| `vectors_bnd/{bkeys,bins,bexps}.mem`、`blabels.txt` | `verify/vectors_bnd/` | `~/work/vcs_boundary/verify/vectors_bnd/` | ✅ |

9 个文件（4 个 RTL + TB + 3 个 .mem + blabels.txt）的 MD5 在 Windows 与 VM 两侧逐一比对，**全部一致**（无编码/换行漂移）。

---

## 3. VM 侧唯一新增文件：`run_boundary_vcs.sh`

没有修改 TB 或 RTL。只新增一个运行脚本，放在 `~/work/vcs_boundary/run_boundary_vcs.sh`
（同内容回拷到 `verify/logs/vcs_dual/boundary/run_boundary_vcs.sh` 作证据）。

脚本要点：

- 显式 `export VCS_HOME=/home/synopsys/vcs/O-2018.09-SP2` 并把 `$VCS_HOME/bin` 放入 PATH
  —— 非交互 SSH shell 不读 `.bashrc`，否则 `vcs` 会报
  `Error-[VCS_COM_UNE] Cannot find VCS compiler`（首次裸 `vcs -id` 已实测）。
- `cd $ROOT/verify` 后运行，保证工作目录在 `verify/` 下。
- **一个可移植性处理**：TB 第 173-175 行用的是**裸文件名**
  `$readmemh("bkeys.mem", k_arr)` 等，并不带 `vectors_bnd/` 前缀。所以脚本先把
  `vectors_bnd/{bkeys,bins,bexps}.mem` 复制到工作目录 `verify/` 再仿真。
  这与 XSim 侧 `run_boundary.ps1` 第 28-36 行「把 `.mem` 拷贝到仿真工作目录」的做法一致，
  只是脚本层面的搬运，**不改 TB 源码**。
- 编译命令：

```bash
vcs -full64 -sverilog +v2k -debug_access+all \
    -timescale=1ns/1ps \
    +incdir+"$ROOT" +incdir+"$VER" \
    -Mdir=csrc -o simv \
    "$ROOT/des_pipe_round_fb.v" \
    "$ROOT/des_pipeline_fb.v" \
    "$ROOT/key_ram_gen.v" \
    "$VER/tb_des_boundary.v" \
    -l compile.log
# 运行
./simv -l sim.log
```

- 判据：`sim.log` 同时出现 `BOUNDARY TB PASS : 18/18` 与 `property 4/4`。

### 3.1 是否需要改 TB 的可移植性

**不需要。** 该 TB 按设计就是纯 Verilog-2001（文件头注释第 20 行已写明），
没用 XSim 专有语法（无 `$display` 之外的厂商任务、无 Vivado `xsim` 编译指令、
无 SystemVerilog 强依赖）。VCS `-sverilog +v2k` 直接一次编译通过。

实际编译日志**无 error、无 warning**：
`Parsing design file ... / Parsing included file '/home/ICer/work/vcs_boundary/sbox_funcs.v' / 2 modules and 0 UDP read.`
（唯一匹配到 "error" 字样的行是链接命令里的 `-lerrorinf` 库名，不是诊断信息。）

---

## 4. 运行结果

编译：`vcs exit=0`，`simv` 生成成功。
仿真：`simv exit=0`，CPU 时间 0.170 s。

```
================ BOUNDARY SUMMARY ================
  vectors             : 18
  scoreboard pass     : 18
  mismatch            : 0
  X/Z                 : 0
  extra output        : 0
  property pass/fail  : 4/0
==================================================
BOUNDARY TB PASS : 18/18  (property 4/4)
$finish at simulation time              4925000
```

- 判定：**PASS**（`VCS_BOUNDARY_RESULT: PASS`）
- 起止：`$finish at simulation time 4925000 ps` = 4925 ns
- 证据：`verify/logs/vcs_dual/boundary/compile.log`、`sim.log`

---

## 5. 与 XSim 的对比

| 维度 | XSim（Vivado 2018.3） | VCS（O-2018.09-SP2） | 一致性 |
|---|---|---|---|
| 主向量通过 | 18/18 | 18/18 | ✅ |
| mismatch / X-Z / extra | 0 / 0 / 0 | 0 / 0 / 0 | ✅ |
| 性质检查 | 4/0 | 4/0 | ✅ |
| 汇总行 | `BOUNDARY TB PASS : 18/18  (property 4/4)` | 同 | ✅ |
| 仿真结束时间 | 4925 ns | 4925 ns | ✅ |
| 逐笔密文 | 见 `logs/tb_des_boundary.log` | 见 `logs/vcs_dual/boundary/sim.log` | ✅ |

**逐行 diff 结果：18 条 `OK #n` 行的密文与时间戳在两侧完全相同（diff 无输出）。**
即不仅是最终 PASS 判定一致，连每一笔的采样时间点（如 `[455000]`、`[3765000]` …）
在这 18 个观测点上两个仿真器结果一致；这只能说明该激励路径上的观测值相同，不足以推出两个仿真器的调度语义完全等价。
观测点。

---

## 6. 差异与原因

1. **时间单位显示格式不同（非功能差异）**
   - XSim 日志时间戳单位是 ps 的裸数字（`[455000]`），`$finish` 行写 `4925 ns`。
   - VCS 同样以 ps 计数（`[455000]`），`$finish at simulation time 4925000`，
     Simulator Report 写 `Time: 4925000 ps`。
   - 原因：TB 用 `timescale 1ns/1ps`，两家都把 $time 以最小精度（ps）打印，数值相同。

2. **日志头尾不同（工具自身 banner）**
   - XSim 有 `Vivado Simulator 2018.3`、`Multi-threading is on. Using 30 slave threads.` 等；
   - VCS 有 `Chronologic VCS (TM) ...`、`V C S Simulation Report`。
   - 原因：工具 banner，与 DUT 行为无关。

3. **编译过程日志差异**
   - XSim 分 `xvlog`（分析）→ `xelab`（展开）→ `xsim`（运行）三步；
   - VCS 一步 `vcs`（解析 + inline pass + g++ 链接）→ `simv`。
   - 原因：工具流程不同，不影响结果。

4. **无功能性差异** —— 没有任何一笔向量、性质检查或结束时间在两侧不一致。

---

## 7. 限制与说明（如实）

1. 本报告只覆盖**边界 TB 这一组**，不代表整个 10 组回归；完整 VCS 回归另有
   `verify/vcs/run_all_vcs.sh`。
2. `-debug_access+all` 已加，本 TB 用不到波形；保留是为了后续可在 Verdi 里直接打开
   `simv.daidir` 调试，不影响通过判据。
3. TB 用**裸文件名** `$readmemh`，所以运行前必须把 `.mem` 放/拷到工作目录。脚本已处理，
   但若有人手动在 `vectors_bnd/` 目录里直接跑 `simv`，会读不到向量而全 X 失败——这是
   TB 原有约定，不是 VCS 问题，也未改 TB。
4. VM 副本目录 `~/work/vcs_boundary/` 内含编译中间物（`csrc/`、`simv`、`simv.daidir/`、
   `ucli.key`），未回拷 Windows，只回拷了 `compile.log`、`sim.log` 与运行脚本。
