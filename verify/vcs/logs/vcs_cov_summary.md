# VCS 代码覆盖率回归报告（DES SoC v2）

- 日期：2026-11-13
- 工具：VCS / URG O-2018.09-SP2（CentOS7 虚拟机 IC_EDA）
- 工程：`$HOME/work/des_pipeline_soc_v2`（与 Windows 工程同步后的副本）
- 脚本：`verify/vcs/run_cov_vcs.sh`
- 覆盖率指标：`-cm line+cond+fsm+tgl+branch`（编译与运行都加）
- 合并方式：每个用例独立 VDB（`cov_db/<case>.vdb`），`urg` 合并
  - `urgReport/`：`-flex_merge modules`，跨不同 top 合并（line/cond/tgl，26 个模块）
  - `urgReport_full5/`：普通合并（五项指标，但 VCS 只保留首个 design 的模块）
  - `urgReport_cases/<case>/`：每个用例单独的全指标报告（FSM/BRANCH 数据来源）

> 说明：VCS O-2018.09 的 `-flex_merge modules` 明确提示
> “not yet implemented for FSM metric”，且 branch 无法跨 design 载入。
> 因此 **跨用例合并报告只有 line/cond/tgl**；FSM/BRANCH 来自单用例报告，
> 数字全部取自 urg 文本报告，未做任何估算。

---

## 1. 用例执行结果

| # | 用例 | 内容 | 判定 | 耗时 | 覆盖率 VDB |
|---|---|---|---|---|---|
| 1 | t1_dir | Verilog 定向 42 笔 | PASS | 4s | cov_db/t1_dir.vdb |
| 2 | t3_sv | SV 约束随机 58 笔 | PASS | 5s | cov_db/t3_sv.vdb |
| 3 | t5_uvm | UVM 58 笔 | PASS | 6s | cov_db/t5_uvm.vdb |
| 4 | t6_axis | AXIS 封装 42 笔 | PASS | 4s | cov_db/t6_axis.vdb |
| 5 | t7_axil | AXIL 23 项 | PASS | 4s | cov_db/t7_axil.vdb |
| 6 | t8_soc | SoC 集成 | PASS | 4s | cov_db/t8_soc.vdb |
| 7 | t10_socuvm | SoC UVM（双 agent + RAL） | PASS | 7s | cov_db/t10_socuvm.vdb |
| 8 | t4_cdc | CDC 多时钟 190 笔 | PASS | 4s | cov_db/t4_cdc.vdb |
| 9 | t_axis_cdc | AXIS+CDC 合并顶层 90/90 | PASS | 7s | cov_db/t_axis_cdc.vdb |
| 10 | t_axis_cdc_uvm | AXIS+CDC 合并顶层 UVM 42 beats | PASS | 6s | cov_db/t_axis_cdc_uvm.vdb |

- 合计：**10/10 PASS，0 FAIL，0 编译失败**。
- PASS 判据完全沿用 `run_all_vcs.sh` 原有正则，未修改。
- 未跑用例：`t2_rekey`（换钥 hazard 专项）、`t9_sva`（SVA 负向测试）。
  原因：不在本次覆盖率用例清单内；t9 是故意注入协议违例的负向测试，
  其覆盖率不具代表性，故未纳入。

---

## 2. 合并覆盖率（总体）

来源：`urgReport/dashboard.txt`（10 个用例，`-flex_merge modules`，26 个模块）

| 指标 | 数值 |
|---|---|
| SCORE | 77.49 |
| **LINE** | **47.67 %** |
| **COND** | **81.55 %** |
| **TOGGLE** | **80.74 %** |
| **FSM** | VCS flex mode 不支持，见下 |
| **BRANCH** | VCS flex mode 无法跨 design 载入，见下 |
| GROUP | 100.00 % |

同报告的 “Total Module Definition Coverage Summary”：

| 指标 | 数值 |
|---|---|
| SCORE | 83.02 |
| LINE | 90.06 % |
| COND | 76.29 % |
| TOGGLE | 82.71 % |

> LINE 47.67 % 是包含 10 个 testbench 层次的 dashboard 值（TB 中有大量
> 未执行的错误分支/打印代码）；RTL 模块定义维度为 90.06 %。

### FSM / BRANCH

来源：`urgReport_full5/dashboard.txt`（全指标合并，但 VCS 2018.09 只能按
同一 design 合并，实际只保留首个 VDB 即 t1_dir 的 4 个模块：
`tb_des_pipeline_fb_v2`、`key_ram_gen`、`des_pipeline_fb`、`des_pipe_round_fb`）

| 指标 | 数值 |
|---|---|
| LINE | 55.61 % |
| COND | 88.14 % |
| TOGGLE | 91.68 % |
| **FSM** | **60.00 %** |
| **BRANCH** | **88.52 %** |

各用例自身的 FSM/BRANCH（来自 `urgReport_cases/*/modlist.txt`）：
FSM 仅 `key_ram_gen` 有状态机，所有执行了它的用例均为 **60.00 %**；
BRANCH 在 80.16 %–100.00 % 之间（见分模块表）。

---

## 3. 分模块覆盖率

LINE/COND/TGL 来自 `urgReport/modlist.txt`（10 用例合并、模块定义维度）。
FSM/BRANCH 来自单用例报告，括号内标注来源用例。

| 模块 | LINE | COND | TGL | FSM | BRANCH |
|---|---|---|---|---|---|
| des_pipe_round_fb | 100.00 | -- | 99.87 | -- | 100.00 (t1) |
| des_pipeline_fb | -- | 100.00 | 83.15 | -- | 100.00 (t1) |
| key_ram_gen | 96.30 | 100.00 | 77.42 | 60.00 | 92.86 (t1) |
| des_axis_wrap | 100.00 | 85.71 | 95.76 | -- | 100.00 (t6) |
| des_axil_regs | 100.00 | 98.08 | 70.57 | -- | 90.91 (t7)；t8 60.61 / t10 72.73 / axis_cdc 57.58 |
| des_soc_top | 100.00 | 83.33 | 71.96 | -- | 100.00 (t8) |
| async_fifo | 100.00 | -- | 99.62 | -- | 100.00 (t4) |
| cdc_sync | **无此模块**（见下） | | | | |
| ├ sync_2ff | 100.00 | -- | 91.67 | -- | 100.00 (t4) |
| ├ toggle_sync | 100.00 | -- | 90.00 | -- | 100.00 (t4)；axis_cdc 用例中 0.00（实例未激励） |
| └ reset_sync | 100.00 | -- | 60.00 | -- | 100.00 (t4) |
| des_cdc_top | 100.00 | -- | 95.34 | -- | 100.00 (t4) |
| des_axis_cdc_top | 100.00 | -- | 74.55 | -- | 100.00 (t_axis_cdc) |

> `cdc/cdc_sync.v` 里实际定义的是三个 CDC 原语 `sync_2ff` / `toggle_sync` /
> `reset_sync`，不存在名为 `cdc_sync` 的 module，故按实际模块列出。

---

## 4. 覆盖率最低的模块与主要未覆盖点

按模块定义 SCORE（line/cond/tgl）：

1. **reset_sync — 80.00 %**：TGL 60.00 %。`srst_n` 只有 0→1，无 1→0；
   `sync[1:0]` 部分位未翻转。
2. **des_soc_top — 85.10 %**：LINE 100 %、COND 83.33 %、TGL 71.96 %。
   - 条件 line 107 `(axis_in_ready && enable_w)` 的 (0,1) 组合未覆盖。
   - AXI-Lite 端口大面积未翻转：`s_axil_awready`、`s_axil_wready` 从未变化；
     `s_axil_bresp[1:0]`、`s_axil_rresp[1:0]` 恒 0；
     `s_axil_awaddr[31:5]`、`s_axil_araddr[31:5]` 高位恒 0；
     `s_axil_rdata[4]/[20]/[22]/[29]` 未翻转。
   - `key_w` 的 [0]、[5:4]、[8:7]、[10]、[15]、[21:20] 等位未翻转。
3. **des_axis_cdc_top — 87.28 %**：LINE 100 %、TGL 74.55 %。
   - 同样是 AXI-Lite 端口未翻转：`s_axil_awready`、`s_axil_wready`、
     `s_axil_bresp[1:0]`、`s_axil_rresp[1:0]`、`s_axil_awaddr[31:4]`、
     `s_axil_araddr[31:4]`、`s_axil_rdata[31:3]`、`s_axil_rdata[1]`。
   - `wrst_n`/`rst_n` 只有 0→1；`wrst_n_sync`/`rst_n_sync` 同样。
   - `key_f` 的 [0]、[11:10]、[15:14]、[19]、[8:5] 等多位未翻转。
4. **des_axil_regs — 89.55 %**：LINE 100 %、COND 98.08 %、TGL 70.57 %。
   - 条件 line 140 `(bvalid_r && s_axil_bready)` 的 (1,0) 未覆盖：
     BVALID 有效期间 BREADY 反压从未发生。
   - `s_axil_awaddr[31:5]`、`s_axil_araddr[31:6]`/`[1:0]`、
     `s_axil_bresp/rresp`、`key_o/key_r` 多位未翻转。
5. **key_ram_gen — 91.24 %、FSM 60 %、BRANCH 92.86 %**：
   - 状态机 3/3 状态已覆盖，但 5 条转移只覆盖 3 条：
     **CALC→IDLE**、**READY→IDLE** 未覆盖（line 62 / line 101 的 IDLE 回退路径）。
   - line 101 `default: state <= IDLE;` 未执行（LINE 96.30 %）。
   - IF（line 61）8 个分支覆盖 7 个；TGL 77.42 %（`key_i` 多位恒 0）。
6. **des_pipeline_fb — 91.58 %**：LINE/COND 满分，TGL 83.15 %，
   内部信号与 `key_i` 多位未翻转（SoC 用例中只有部分轮次被激励，
   t10 的实例级 TGL 仅 28.97 %）。
7. **des_pipe_round_fb — 99.93 %**：模块定义维度几乎满分，但 t10 用例中
   每个实例只用到少数轮次（实例级 line 7 %–25 %），属正常现象。

---

## 5. 报告路径

VM（`/home/ICer/work/vcs_cov/`）：
- `urgReport/` — 10 用例合并（flex modules，line/cond/tgl，26 模块）
- `urgReport_full5/` — 全指标合并（FSM/BRANCH 可用，仅首个 design 的 4 模块）
- `urgReport_cases/<case>/` — 每个用例的全指标报告
- `cov_db/<case>.vdb/` — 各用例覆盖率数据库
- `urg_merge.log`、`urg_merge_full5.log`、`run_status.txt`

Windows（`F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\vcs\`）：
- `cov/urgReport/`、`cov/urgReport_full5/`、`cov/urgReport_cases/`
- `cov/urg_merge.log`、`cov/urg_merge_full5.log`、`cov/run_status.txt`
- 脚本：`verify/vcs/run_cov_vcs.sh`

---

## 6. 环境与同步说明

- 虚拟机启动时处于关机状态，已用 `vmrun -T ws start ... nogui` 启动；
  SSH 使用已有密钥免密登录成功，无需 `setenforce 0`。
- 同步到 VM 的文件（VM 缺失或较旧）：
  `des_soc_top.v`、`cdc/des_axis_cdc_top.v`、`verify/sv/axis_protocol_check.sv`、
  `verify/sv/des_if.sv`、`verify/tb_cdc/tb_des_axis_cdc.v`、
  `verify/uvm/des_ral_pkg.sv`、`verify/uvm/tb_des_soc_uvm.sv`、
  `verify/uvm/axis_cdc/*`（3 个文件）。
- 未同步 `_sim_*`、日志等生成物。
- 磁盘：`/home` 309G，已用 38G，剩余 272G。
- 全程未使用 XSim；未改 RTL、向量和原有 VCS 脚本判据。
