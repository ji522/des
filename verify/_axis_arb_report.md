# 2 通道 AXI4-Stream 仲裁/交换器 + DES SoC 集成

日期：2026-11-24  
工具：VCS O-2018.09-SP2（CentOS7 VM）；DC/PT/Formality O-2018.06-SP1  
结论：VCS 全量回归 **14/14 PASS**（原 10 组 + 新增 4 组：standalone / corner / DES 集成 / 多时钟 CDC）；单时钟、多时钟、低功耗三套 DC/PT/Formality 见 `asic_flow_20261124_arb/`、`asic_flow_20261125_arb_cdc/`、`asic_flow_20261125_lowpower/`

---

## 1. 结构

```
s0_axis ──> [sync_fifo 16 x 65] ──┐
                                  ├──> 包级 round-robin 仲裁 ──> des_soc_top ──> m_axis
s1_axis ──> [sync_fifo 16 x 65] ──┘                                      (DES 16 级流水)
```

- 每通道 FIFO 存 `{tlast, tdata}`，深度 16（`FIFO_AW=4`），可参数化。
- **包级锁定**：一旦某通道开始输出，保持到该包 `TLAST`，不会在包内切换通道。
- **反压**：输出 `m_axis_tready=0` 时 FIFO 继续攒数；FIFO 满后对应 `s_axis_tready` 拉低，不丢数。
- **轮询**：默认 round-robin，一包结束把优先级交给另一通道；`CTRL.ARB_MODE=1` 时固定优先 ch0。
- **同字过域**：`tlast` 与 `tdata` 拼成 65 位一起写入 FIFO，避免 TLAST 与数据错位。

---

## 2. 寄存器映射（AXI4-Lite，`axis_arb_regs.v`）

| 地址 | 名称 | 属性 | 说明 |
|---|---|---|---|
| 0x00 | CTRL | RW | [0] ENABLE, [1] ARB_MODE(0=RR,1=固定 ch0), [2] CLR_COUNTERS(自清) |
| 0x04 | IRQ_STATUS | W1C | [0] ch0 almost_full, [1] ch1 almost_full, [2] ch0 full, [3] ch1 full, [4] ch0 done, [5] ch1 done |
| 0x08 | IRQ_MASK | RW | 同上，1=使能中断 |
| 0x0C | THRESH | RW | [7:0] ch0 almost_full 阈值, [15:8] ch1 |
| 0x10–0x24 | CH0_* | RO | beats/packets in/out、stall、blocked |
| 0x28–0x3C | CH1_* | RO | 同上 |
| 0x40 | STATUS | RO | fifo0/1 count、cur_ch、lock、busy |
| 0x44 | VERSION | RO | 0x0001_0000 |

中断：`irq_o = |(IRQ_STATUS & IRQ_MASK)`；状态为 sticky，W1C 清除；计数器由 `CTRL.CLR_COUNTERS` 统一清零。

---

## 3. 验证结果（VCS）

### 3.1 standalone（`tb_axis_arb2.v`）

- 两通道各 3 个 4-beat 包，输出周期反压（每 7 拍停 1 拍）。
- **24 beats / 6 packets**，0 数据错误、0 TLAST 错误、无包内交错。
- 计数器：ch0/ch1 各 12 beats in、3 packets in、12 beats out、3 packets out；ch0 stall > 0。
- 中断：阈值置 1 后 almost_full 事件置位、`irq_o=1`；W1C 后 `irq_o=0`。
- 通过标志：`AXIS ARB PASS : beats=24 packets=6`
- 功能覆盖率：73.33%（只走主路径，未覆盖 fixed / len1 / len8+ / FIFO full；由 corner 用例补齐）。

### 3.2 corner（`tb_axis_arb_corner.v`）

三个 phase：
1. **固定优先 ch0**：包长 1/2/5（ch0）+ 1/2/5（ch1），ch0 全部先出；
2. **FIFO 压满**：ch0 单包 20 beat、ch1 单包 20 beat，先不 ready，`blocked` 计数增加，释放后全出；
3. **单拍包**：ch0 len1、ch1 len1，覆盖 lock 旁路路径。

- **58 beats / 10 packets**，0 错误。
- 功能覆盖率：**100.00%**（ch/last/len/stall/mode/occ0/occ1/cross 全部 100%）。
- 通过标志：`AXIS ARB CORNER PASS : beats=58 packets=10`

### 3.3 集成（`tb_des_arb_soc.v`）

- ch0 发 `ins[0..3]`，ch1 发 `ins[4..7]`，经仲裁后进 DES 加密。
- **8 beats / 2 packets**，输出与 `exps[0..7]` 逐拍一致，TLAST 在第 4/8 拍对齐。
- 计数器：ch0/ch1 各 1 packet out、4 beats out。
- 通过标志：`DES ARB SOC PASS : 8 beats, 2 packets, TLAST aligned`
- 功能覆盖率：58.89%（集成用例只走单包路径，不做 100% 声明；覆盖率闭环看 corner）。

### 3.4 全量回归

`verify/vcs/run_all_vcs.sh`：**PASS=14 FAIL=0**（新增 t11_arb、t12_arb_soc、t13_arb_corner、t14_arb_cdc）。

### 3.5 SVA（bind 到 `axis_arb2`，`verify/sv/axis_arb_check.sv`）

| 断言 | 检查 |
|---|---|
| A1/A2 | FIFO 满时不得给 tready |
| A3/A4 | FIFO 空时不得读 |
| A5/A6 | 不出现 overflow / underflow 脉冲 |
| A7 | 输出反压期间 valid/data/tlast/tuser 保持 |
| A8 | enable=0 时无输出、无输入 ready |
| A9 | lock 时输出通道 = cur_ch |
| A10 | FIFO count 不越界 |
| A11 | 包内不得切换通道 |

三组用例（standalone / corner / 集成）均未出现 `[ARB A*]` 断言失败。

### 3.6 DC / PT / Formality（2026-11-25 更新）

详细报告：`asic_flow_20261124_arb/前端流程报告_20261124.md`

本轮改动：
- `axis_arb_regs.v` 的 `s_axil_rdata` 改为寄存器输出（读数据打一拍），消掉 250MHz 的 `s_axil_arb_rdata[*]` 组合输出违例；
- 新增 `axil_2to1_demux.v`，把 DES + 仲裁器两个 AXIL 从端口合并成 **一个** 控制端口（`0x000`/`0x100` 地址译码）；
- AXIL 控制面 IO 预算 1.0ns，AXIS 数据面 2.0ns（分层预算，已在 SDC 写明）。

| 项目 | 100MHz（10ns） | 250MHz（4ns） |
|---|---|---|
| Cells / DFF | 26,591 / 4,663 | 26,456 / 4,663 |
| Total area | 45,907.88 µm² | 45,869.31 µm² |
| PT clk setup 违例 | 0 | **0** |
| PT reg2reg 最差 slack | +7.4383 ns | +1.7302 ns（MET） |
| PT clk hold 违例 | 0 | 0 |
| PT async removal | 244 条（同沿悲观） | 186 条（同沿悲观） |
| Formality | 4,773/4,773 | 4,773/4,773 |

- 两个 16×65 FIFO 各 7,777.84 µm²，合计 **15,556 µm² / 33.9%**：Nangate45 无 SRAM 宏，小 FIFO 只能堆触发器。
- 250MHz 最差 reg2reg 是 `u_arb/u_fifo1/count_r_reg[0] → ch1_blocked_o_reg[31]`，不是 DES 数据通路。
- 100MHz / 250MHz 都是干净的单角 setup/hold 结果；仍不是签核：typical 单角、理想时钟、WLM、pre-CTS、无 DFT/P&R。
- 若统一按 2.0ns IO 预算，250MHz 还剩 2 条 `awaddr[8]→awready` / `araddr[8]→arready` 组合路径（约 −0.25/−0.19ns）；分层预算已明确写出，不藏。

### 3.7 多时钟版本（`des_arb_cdc_top`，2026-11-25）

详细报告：`asic_flow_20261125_arb_cdc/多时钟前端流程报告_20261125.md`

- 两路输入分别在 `wclk0=100MHz`、`wclk1=142.8MHz`，经 65 位 `async_axis_fifo`（`{tlast,tdata}` 同字过域、show-ahead 同拍 refill）进 `clk=250MHz` 的仲裁 + DES。
- `set_clock_groups -asynchronous`；每域独立 `reset_sync`；控制面仍是单 AXIL（`0x000`/`0x100`）。
- VCS `t14_arb_cdc`：8 beats / 2 packets、TLAST 对齐，**全量 14/14 PASS**；功能覆盖 58.89%（单包路径，不做 100% 声明）。
- DC/PT/Formality：**34,988 cells / 6,959 DFF / 62,580.22 µm²**；`clk` / `wclk0` / `wclk1` 三域 **setup 0 违例、hold 0 违例**；最差 reg2reg **+1.5054 ns @250MHz**；271 条 async removal（同沿悲观）；Formality **7,073/7,073**。
- 面积：两个异步 FIFO 各 8,337 µm²（13.3%×2），两个同步 FIFO 各 7,771 µm²（12.4%×2），DES 24,196 µm²（38.7%）；**4 个 65×16 FIFO 合计 51.5%**。
- 对比单时钟版：45,908 µm² / 4,663 DFF → 62,580 µm² / 6,959 DFF，面积 +36%、DFF +49%，主要来自两个异步 FIFO（各 1,040 FF）与复位/同步逻辑。

### 3.8 低功耗（SAIF + DC 时钟门控，2026-11-26）

详细报告：`asic_flow_20261125_lowpower/低功耗对比报告_20261125.md`

- 长流量 **256 beats / 64 packets** → VCD → `vcd2saif` → DC `read_saif`；baseline 与 `compile_ultra -gate_clock`（144 个 ICG）用同一份 SAIF 对比。
- 动态功耗 **10.9865 mW → 3.2007 mW（−70.87%）**；leakage 1.2519 → 1.0222 mW；总功耗 12.2384 → 4.2229 mW（−65.50%）。
- 面积 **62,580.22 → 52,261.55 µm²（−16.5%）**；DFF 6,959 → 7,114（ICG 锁存/测试逻辑）；cells 34,988 → 24,393。
- gated 网表：三个时钟域 setup/hold 均 0（`clock_gating_default` 组也 0）；async_default 146 条 removal（同沿悲观）；reg2reg 最差 **+1.7046 ns @250MHz**；Formality **7,079/7,079**。
- 面积下降来自 ICG 替换寄存器前的写使能 mux，不是丢逻辑；Formality 等价性已证明。
- 突发 8-beat 窗口的 92.4% 是空闲占主导的上界，不作为主数字；主数字用稳态 256 beat 的 −70.9%。
- 边界：SAIF 来自 RTL、Nangate45 typical 单角、理想时钟、pre-CTS；功耗是相对趋势，不是签核。

---

## 4. 边界（面试要主动说）

- 两个输入与输出同属 `clk` 域；不含异步 FIFO。需要跨时钟时，在每个输入前各接一个 `cdc/async_fifo.v`。
- 单 AXI4-Lite 从端口，内部 `axil_2to1_demux` 按 `addr[8]` 译码（`0x000`=DES，`0x100`=仲裁器）；单 outstanding，W 等 AW 先到，AR 握手锁存选择。
- 仲裁是**包级**，不是 beat 级；beats 交错会破坏 DES 块边界。
- `almost_full` 是 advisory 预判，不接去门控 `s_axis_tready` 代替 `full`；正确性仍由 `full` 保证。
- 未做形式验证；断言/覆盖率可后续补（SVA：满不写、空不读、TLAST 位置、包内通道不变）。

---

## 5. 面试 60 秒口径

> “这是一个 2 通道 AXI4-Stream 仲裁器：每通道 16 深 FIFO，存 `{tlast, tdata}`；包级 round-robin，一旦开始一个包就锁到 TLAST，避免两路数据交错；输出反压时 FIFO 攒数，满了向上游反压，不丢数。控制面是单 AXI4-Lite 端口，内部 `0x000`/`0x100` 地址译码，有 almost_full 阈值、每通道 beats/packets/stall/blocked 计数器和中断。验证在 VCS 上跑：standalone 24 beats/6 packets 零错，corner 58 beats/10 packets、功能覆盖 100%，集成到 DES 后 8 beats/2 packets、TLAST 对齐，全量回归 14/14。综合用 Nangate45：单时钟版 100MHz 45,908 µm² / 4,663 DFF、reg2reg +7.44ns、setup/hold 0 违例；250MHz reg2reg +1.73ns、setup/hold 0 违例；Formality 4,773/4,773；两个 16×65 FIFO 占 34%。多时钟版把两路输入放到 100/142.8MHz 写域、250MHz 核心，62,580 µm² / 6,959 DFF，三域 setup/hold 0 违例，Formality 7,073/7,073，四个 65×16 FIFO 占 51.5%。边界：typical 单角、理想时钟、pre-CTS、控制面 IO 1.0ns 与数据面 2.0ns 分层预算，不是签核。”

---

## 6. 文件

- `sync_fifo.v` — 参数化同步 FIFO（count、almost、overflow/underflow 脉冲）
- `axis_arb2.v` — 2 通道仲裁/交换器
- `axis_arb_regs.v` — AXI4-Lite 控制/状态/计数器（读数据寄存器输出）
- `axil_2to1_demux.v` — 单 AXIL 端口 → DES / 仲裁器地址译码（`0x000`/`0x100`）
- `des_arb_soc_top.v` — 与 `des_soc_top` 集成（单 AXIL 控制端口）
- `des_arb_cdc_top.v` — 多时钟版本：每通道异步 FIFO（100/142.8MHz 写域）+ 250MHz 核心
- `cdc/async_axis_fifo.v` — 65 位异步 FIFO + show-ahead AXIS 适配
- `verify/sv/axis_arb_check.sv` — SVA（A1–A11）+ covergroup（bind 到 axis_arb2）
- `verify/tb_axis_arb2.v` — standalone 自检
- `verify/tb_axis_arb_corner.v` — corner 用例（fixed / FIFO full / 单拍包）
- `verify/tb_des_arb_soc.v` — DES 集成自检（单时钟）
- `verify/tb_des_arb_cdc_soc.v` — 多时钟 2 通道 + DES 自检
- `verify/vcs/run_axis_arb_vcs.sh` — 单时钟 3 组 VCS 回归
- `verify/vcs/run_arb_cdc_vcs.sh` — 多时钟 CDC 1 组 VCS 回归
- `verify/vcs/run_all_vcs.sh` — 已并入第 11、12、13 组
