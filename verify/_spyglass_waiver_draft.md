# SpyGlass CDC waiver 草稿（剩余 6 条）

> **草稿，需本人确认，不能直接当签核结论。**
> 本文所有“性质判断”和“waiver 草稿”均基于现有本地报告 + RTL 静态阅读推断，
> 其中涉及协议假设、位映射、after-fix 产物完整性的地方，必须由设计者逐条确认后
> 才能作为签核依据。本文只读生成，未修改任何报告文件。

---

## 0. 证据来源与版本对账（先看这一节）

1. 目标目录
   `<...>/verify/spyglass/after_fix/consolidated_reports/des_cdc_top_cdc_cdc_verify/`
   下**只有 `.rpt`，没有 `.csv`**（README 也只说“critical reports”）。任务里提到的
   `Ac_conv01.csv / Ac_conv02.csv / Ac_cdc01a.csv / Ac_datahold01a.csv` 实际只存在于
   `<...>/verify/spyglass/goals/cdc_verify/spyglass_reports/clock-reset/`，其文件时间为
   **2026-11-01 21:32**，属于**“修复前”**那次 run。
2. after_fix 这次 run 的报告时间戳：`CDC-report.rpt / adv_cdc.rpt / elab_summary.rpt`
   均为 **2026-11-02 09:40**（README 09:40:22）。对应源码时间：`cdc/cdc_sync.v`
   11-02 09:12、`cdc/des_cdc_top.v` 11-02 09:22，
   即 **after_fix 编译的是“已加 ready_key 展宽（RDY_HOLD=8）”的版本**
   （`elab_summary.rpt` 已列出 `RDY_HOLD = 8`）。
3. after_fix 的 CSV 是 SpyGlass 在 VM 的 `/home/ICer/work/cdc_spyglass/wdir/...` 下重新
   生成的（`spyglass.log` 有 `spyOpenFile ... Ac_cdc01a.csv ... "w" mode`），但**没有回拷**
   到本机 `consolidated_reports`。本机仅有的归档 `spyglass_cdc_reports.tar.gz`
   时间是 **2026-11-02 08:50**，仍早于修复（09:12/09:22），所以它也是**修复前**的快照。
   → 结论：**Ac_cdc01a 的 after-fix 源信号只能取自 `adv_cdc.rpt`（09:40）**，
   不能再用旧 CSV 的 `ready_key_o`。
4. `CDC-report.rpt` 的 Section G 是**消息条数**，不是失败数。真正判定在
   `adv_cdc.rpt` 的 Section E/G。after_fix 的 `adv_cdc.rpt` 显示：
   - `Ac_conv02`：2 Passed / 0 Failed（两条均 PROVED）
   - `Ac_cdc01a`：2 Passed / 0 Failed（两条均 PROVED）
   - `Ac_datahold01a`：0 Passed / 0 Failed / **1 Partially-Proved（depth 83(200)）**
   - `Ac_conv01` 未进功能表（纯结构消息）。
   即 6 条消息中 **4 条已被形式证明、1 条部分证明、1 条仅结构性**。

### 汇总表

| # | 规则 | 条数 | 类别 | 性质判断 | 关键依据 |
|---|------|------|------|----------|----------|
| 1 | Ac_conv01 | 1 (ID 84) | 汇聚(same-domain sync) | 可waiver但需理由 | 6 同步器 depth 全=2；纯数据通路；靠“换钥前排空”协议 |
| 2 | Ac_conv02 | 1 (ID 7F) | 组合汇聚 | 可能误报 | 格雷码单 bit + 保守空判断 + PROVED |
| 3 | Ac_conv02 | 1 (ID 81) | 组合汇聚 | 可能误报 | 格雷码单 bit + 保守满判断 + PROVED |
| 4 | Ac_cdc01a | 1 (ID 85) | Fast->Slow | 可waiver但需理由 | after_fix 已加展宽 → PROVED（修复前 FAILED） |
| 5 | Ac_cdc01a | 1 (ID 86) | Fast->Slow | 可能误报 | 格雷指针 MSB 本身极慢 + PROVED |
| 6 | Ac_datahold01a | 1 (ID 87) | 数据保持 | 可waiver但需理由 | 写指针 2 级同步晚于写完成；标准 Cummings FIFO |

---

## 1. Ac_conv01 — 顺序汇聚（1 条）

- **规则名**：`Ac_conv01`（Sequential Convergence of same domain synchronized signals）
- **数量**：1（CSV ID = 84）
- **汇聚门（CONVERGING GATE）**：
  `des_cdc_top.u_des.\pipe_stages[0].u_round .xored_R[11]`，`combinational gate`
  （`des_pipe_round_fb.v:29`）
- **属性**：NUMBER OF SYNCHRONIZERS = 6，SOURCE DIVERGENCE = no，SCALAR SOURCE = no，
  MAX/MIN/AVG DEPTH = 2 / 2 / 2.00，SAME DEPTH CONVERGENCE = **yes**
- **CSV 原始描述（规则表）**：
  `84,des_cdc_top.u_des.\pipe_stages[0].u_round .xored_R[11],combinational gate,6,no,no,2,2,2.00,yes,no,.../Ac_conv01/ac_conv_03.csv`
- **明细 CSV（`Ac_conv01/ac_conv_03.csv`，修复前，与 `cdc_verify_struct` 版一致）**：
  | Schematic | Type | Signal Name | Depth | Source(s) | Dest Clk | Src Clk | File:Line |
  |---|---|---|---|---|---|---|---|
  | 5 | Converging Gate | `...u_round .xored_R[11]` | - | - | - | - | `des_pipe_round_fb.v:29` |
  | 6 | Destination flop | `des_cdc_top.u_sync_loadkey.sync_ff[0]` | 2 | `u_sync_loadkey.toggle` | `des_cdc_top.clk` | `des_cdc_top.wclk` | `cdc_sync.v:58` |
  | 7 | Destination flop | `des_cdc_top.u_fifo.wgray_sync1[4:0]` | 2 | `u_fifo.wgray[4:0]` | `des_cdc_top.clk` | `des_cdc_top.wclk` | `async_fifo.v:94` |
- **源 → 目的路径**：
  - 路 A（密钥）：`wclk` 域 `u_sync_loadkey.toggle` →（toggle_sync 2 级，depth=2）→
    `u_sync_loadkey.sync_ff` → 边沿还原出 `load_key_pulse` → `u_des.u_key_ram_gen`
    （clk）算出 `round_keys` → `subkey_i[11]`。
  - 路 B（数据）：`wclk` 域 `u_fifo.wgray[4:0]` →（2 级，depth=2）→ `wgray_sync1/2`
    → 空判断 → `rdata_r` → `data_i` → `R_init` → `R[0]`(=R_i) → `expanded_R[11]=R_i[8]`。
  - 两路在 `xored_R[11] = expanded_R[11] ^ subkey_i[11]` 汇聚，再经 S 盒/P 盒 → `R_o`
    （clk 域寄存器）。（`xored_R[11]=R_i[8]` 为按位拼接人工推算，**需本人核对**。）
- **性质判断：可 waiver 但需理由**
  - 依据 1：6 个同步器 depth 全为 2 且 `SAME DEPTH CONVERGENCE = yes`，两路相对延迟
    一致，不会引入额外的不确定 skew（同深度保持源域相对时序）。
  - 依据 2：汇聚点是**纯数据通路**（XOR→S 盒→P 盒→`R_o` 寄存器），不是控制/状态判决，
    单拍瞬态最多污染一级流水寄存器的值。
  - 依据 3：真正的风险是“换钥计算期间数据仍在途”导致旧数据配新子密钥；而
    `des_cdc_top.v` 头注释（22–23 行）约定“换钥/切换前源侧必须停流并等流水线排空”，
    `key_ram_gen` 只有在 READY 才 `keys_ready_o=1` 且 `key_ram` 稳定，CALC 期间
    （`round_cnt` 0..15 改写 `key_ram`）不应有数据流过。
- **waiver 草稿**：
  > 本违规为 `u_des.pipe_stages[0].u_round.xored_R[11]` 处两条同源（wclk）两拍同步
  > 信号（load_key 经 toggle_sync、FIFO 读指针 wgray 经两级同步）在组合逻辑汇聚
  > （`des_pipe_round_fb.v:29`，`xored_R = expanded_R ^ subkey`）。该汇聚点是 DES 数据
  > 通路而非控制判决，且 6 个同步器深度全部为 2、同深度汇聚，两路相对延迟一致，不会
  > 产生额外的不确定偏斜；最坏瞬态只污染一级流水寄存器的值。功能上二者不应在“有数据
  > 在途”时同时变化：设计约定换钥前源侧停流并等流水线排空，`key_ram_gen` 在 READY
  > 状态下 `key_ram` 保持稳定，CALC 期间不应有数据通过，因此汇聚瞬时错配不会进入有效
  > 数据。**需本人确认**：(a) `xored_R[11]=R_i[8]^subkey_i[11]` 的位映射，
  > (b) “换钥前排空”协议在系统/上层确实被强制执行。

---

## 2. Ac_conv02 — `rempty_val` 组合汇聚（1 条）

- **规则名**：`Ac_conv02`（Combinational Convergence of same domain synchronized signals）
- **数量**：1（CSV ID = 7F，规则计数 2 之一）
- **汇聚门**：`des_cdc_top.u_fifo.rempty_val`，`combinational gate`（`async_fifo.v:46`）
- **属性**：NUMBER OF SYNCHRONIZERS = 5，STATUS = **PASSED**
- **CSV 原始描述**：
  `7F,des_cdc_top.u_fifo.rempty_val,combinational gate,5,PASSED,no,no,no,.../Ac_conv02/ac_conv_01.csv`
- **明细 CSV（`Ac_conv02/ac_conv_01.csv`）**：
  | Schematic | Type | Signal Name | Source(s) | Dest Clk | Src Clk | File:Line |
  |---|---|---|---|---|---|---|
  | 1 | Converging Gate | `u_fifo.rempty_val` | - | - | - | `async_fifo.v:46` |
  | 2 | Destination flop | `u_fifo.wgray_sync1[4:0]` | `u_fifo.wgray[4:0]` | `des_cdc_top.clk` | `des_cdc_top.wclk` | `async_fifo.v:94` |
- **源 → 目的路径**：`wclk` 域 `u_fifo.wgray[4:0]` →（2 级 `wgray_sync1/2`，`ASYNC_REG`）→
  `clk` 域 `wgray_sync2` → 与本地 `rgray_next` 在 `rempty_val = (rgray_next == wgray_sync2)`
  组合比较汇聚（`async_fifo.v:46`）。5 个同步器 = `wgray_sync1[4:0]` 这 5 个 bit。
- **性质判断：可能误报**
  - 依据 1：被“汇聚”的 5 个 bit 是**同一个 wclk 格雷码指针**，源端每次自增只翻转 1 位；
    经两级同步后，整条总线只可能是“旧值”或“新值”，不会出现两段码混合的错误值。
  - 依据 2：因此 `==` 比较最坏退化为**保守的空判断**（假空/早空），只会让读侧晚一拍
    取数，绝不导致下溢或读到未写数据。
  - 依据 3：after_fix `adv_cdc.rpt` 对 `rempty_val` 的判定为 **PROVED**。
- **waiver 草稿**：
  > 本违规是 FIFO 空判断组合比较 `u_fifo.rempty_val = (rgray_next == wgray_sync2)`
  > （`async_fifo.v:46`）处，5 位写格雷指针 `wgray[4:0]` 经两拍同步后在组合逻辑汇聚。
  > 由于 wgray 是格雷码编码、源端每次只变化 1 位，两级同步后整条总线只可能取“旧值”
  > 或“新值”，不存在多 bit 同时翻转导致的撕裂码，比较最坏只在指针刚更新时退化为
  > 偏保守的“假空”，不会造成下溢或误读。该结构是 Cummings 异步 FIFO 的标准做法，
  > 且 after_fix 功能分析已 **PROVED**（`adv_cdc.rpt` Section E：Ac_conv02 2 Passed /
  > 0 Failed）。可 waive，理由为格雷码单 bit 跳变 + 保守空判断。

---

## 3. Ac_conv02 — `wfull_val` 组合汇聚（1 条）

- **规则名**：`Ac_conv02`
- **数量**：1（CSV ID = 81，规则计数 2 之二）
- **汇聚门**：`des_cdc_top.u_fifo.wfull_val`，`combinational gate`（`async_fifo.v:44`）
- **属性**：NUMBER OF SYNCHRONIZERS = 5，STATUS = **PASSED**
- **CSV 原始描述**：
  `81,des_cdc_top.u_fifo.wfull_val,combinational gate,5,PASSED,no,no,no,.../Ac_conv02/ac_conv_02.csv`
- **明细 CSV（`Ac_conv02/ac_conv_02.csv`）**：
  | Schematic | Type | Signal Name | Source(s) | Dest Clk | Src Clk | File:Line |
  |---|---|---|---|---|---|---|
  | 3 | Converging Gate | `u_fifo.wfull_val` | - | - | - | `async_fifo.v:44` |
  | 4 | Destination flop | `u_fifo.rgray_sync1[4:0]` | `u_fifo.rgray[4:0]` | `des_cdc_top.wclk` | `des_cdc_top.clk` | `async_fifo.v:72` |
- **源 → 目的路径**：`clk` 域 `u_fifo.rgray[4:0]` →（2 级 `rgray_sync1/2`）→ `wclk` 域
  `rgray_sync2` → 与本地 `wgray_next` 在
  `wfull_val = (wgray_next == {~rgray_sync2[4:3], rgray_sync2[2:0]})`
  组合比较汇聚（`async_fifo.v:44`）。5 个同步器 = `rgray_sync1[4:0]`。
- **性质判断：可能误报**
  - 依据 1：5 位 `rgray` 同为格雷码指针，源端每次只变 1 位；两级同步后总线不可能
    出现撕裂码。
  - 依据 2：比较结果只影响“满”判断，最坏退化为**保守的满**（假满/早满），只会让
    写侧暂停，不会溢出覆盖未读数据。
  - 依据 3：after_fix `adv_cdc.rpt` 对 `wfull_val` 判定 **PROVED**。
- **waiver 草稿**：
  > 本违规是 FIFO 满判断 `u_fifo.wfull_val = (wgray_next == {~rgray_sync2[4:3], rgray_sync2[2:0]})`
  > （`async_fifo.v:44`）处，5 位读格雷指针 `rgray[4:0]` 经两拍同步后在组合比较逻辑
  > 汇聚。与空判断同源：格雷码单 bit 跳变保证同步后的总线只可能是旧值或新值，比较最坏
  > 退化为偏保守的“假满”，只会让写侧暂停而不会溢出覆盖未读数据。该结构为标准异步
  > FIFO 正确性所依赖的保守满/空机制，且 after_fix 功能分析已 **PROVED**。可 waive，
  > 理由为格雷码单 bit 跳变 + 保守满判断。

---

## 4. Ac_cdc01a — `ready_key` Fast→Slow（1 条，**修复前 FAILED / 修复后 PROVED**）

- **规则名**：`Ac_cdc01a`（Data-loss for fast to slow synchronized control crossings）
- **数量**：1（CSV ID = 85，规则计数 2 之一）
- **修复前 CSV（本机 `goals/...`，11-01）**：
  `85,des_cdc_top.ready_key_o,des_cdc_top.clk,des_cdc_top.u_sync_rdykey_wclk.ff1[0],des_cdc_top.wclk,FAILED,Fast->Slow`
- **修复后 `adv_cdc.rpt`（11-02 09:40，权威）**：
  `SFlop:des_cdc_top.ready_key_o_hold SClk:des_cdc_top.clk DFlop:des_cdc_top.u_sync_rdykey_wclk.ff1[0] DClk:des_cdc_top.wclk, cdc_sync.v, 30 : PROVED`
- **源 → 目的路径**：`clk` 域 `u_des.u_key_ram_gen.keys_ready_o`（= `ready_key_o`）
  → `ready_key_o_hold`（clk 域“最小保持展宽”，`RDY_HOLD=8`，`des_cdc_top.v:100–118`）
  → `sync_2ff u_sync_rdykey_wclk.ff1[0]`（`wclk` 域，`des_cdc_top.v:120–122`，
  `cdc_sync.v:30`）。
- **性质判断：可 waiver 但需理由（修复后已 PROVED）**
  - 背景：修复前把 `ready_key_o` **直接**接同步器，快域 4ns 的电平对 10ns 慢域可能整拍
    漏采 → 旧 run 报 `FAILED through depth 23(57)`（见 `spyglass_cdc_reports.tar.gz` 内
    `adv_cdc.rpt`，Ac_cdc01a 1 Passed / 1 Failed）。
  - 现状：RTL 已插入 `ready_key_o_hold` 展宽器，每次更新后至少保持 `RDY_HOLD=8` 个 clk
    周期 = 8×4ns = **32ns > 3 个 wclk 周期（10ns）**，满足“源电平保持 ≥2 目的周期”的
    要求；`rdy_cool_sr` 冷却链保证 8 拍内不再接受新值（`des_cdc_top.v:102–118`）。
  - 依据：after_fix `elab_summary.rpt` 已含 `RDY_HOLD=8`，且 `adv_cdc.rpt` 对
    `ready_key_o_hold → ff1[0]` 判定 **PROVED**。
  - 注意：`CDC-report.rpt` 仍显示 `Ac_cdc01a = 2`，那是**消息条数**（含 PASSED 的
    rgray 那条），不是失败数；真实失败数为 0。
- **waiver 草稿**：
  > 本违规为快域 `ready_key_o` 到慢域 `u_sync_rdykey_wclk.ff1[0]` 的 Fast→Slow 电平
  > 跨域。修复前直接两级同步时，快域可能只保持 1 个 clk 周期（4ns），慢域 10ns 周期
  > 在极端情况下整拍漏采（旧 run `FAILED through depth 23(57)`）。现版本已在快域加入
  > `ready_key_o_hold` 最小保持展宽（`RDY_HOLD=8`，`des_cdc_top.v:100–118`），每次变化后
  > 至少稳定 8×4ns=32ns > 3 个 wclk 周期，慢域两级同步必能采到；after_fix 的
  > `adv_cdc.rpt` 已对 `ready_key_o_hold → ff1[0]` 判定 **PROVED**。因此该条可 waive，
  > 理由为源信号被结构性展宽至远大于目的域周期。**需本人确认**：(a) after_fix 实际
  > 编译的确实是 `des_cdc_top.v` 09:22 展宽版（elab 已见 RDY_HOLD=8），(b)`ready_key_o`
  > 的语义允许该副本最多晚 8 个快域周期（32ns）更新。

---

## 5. Ac_cdc01a — `rgray[4]` Fast→Slow（1 条）

- **规则名**：`Ac_cdc01a`
- **数量**：1（CSV ID = 86，规则计数 2 之二）
- **CSV 原始描述**：
  `86,des_cdc_top.u_fifo.rgray[4],des_cdc_top.clk,des_cdc_top.u_fifo.rgray_sync1[4],des_cdc_top.wclk,PASSED,Fast->Slow`
- **after_fix `adv_cdc.rpt`**：
  `SFlop:des_cdc_top.u_fifo.rgray[4] SClk:clk DFlop:u_fifo.rgray_sync1[4] DClk:wclk, async_fifo.v, 72 : PROVED`
- **源 → 目的路径**：`clk` 域 `u_fifo.rgray[4]` →（`rgray_sync1 <= rgray`，`async_fifo.v:72`，
  两级 `ASYNC_REG`）→ `wclk` 域 `rgray_sync1[4]/rgray_sync2[4]`。
- **性质判断：可能误报**
  - 依据 1：`rgray[4]` 是 5 位格雷读指针的最高位，只在读指针绕回（约每 16 次读）时翻转，
    本身变化极慢，远宽于 1 个 wclk 周期（10ns）。
  - 依据 2：目标触发器为 `ASYNC_REG` 两级同步器，结构正确。
  - 依据 3：修复前后该条均 **PASSED / PROVED**（旧 CSV `PASSED`，after_fix `adv_cdc` `PROVED`）。
- **waiver 草稿**：
  > 本违规为 FIFO 读格雷指针最高位 `u_fifo.rgray[4]`（clk 域）到 `rgray_sync1[4]`
  > （wclk 域的 ASYNC_REG 两级同步器，`async_fifo.v:72`）的 Fast→Slow 跨域。
  > `rgray[4]` 只在指针绕回时才翻转，翻转间隔约为 16 次读，远长于一个 wclk 周期
  > （10ns），源值在被慢域采样前已长期稳定；配合标准两级同步器，无数据丢失风险。
  > 该条在修复前 CSV 即为 `PASSED`、after_fix `adv_cdc.rpt` 亦为 **PROVED**，属于消息
  > 计数而非真实失败。可 waive，理由为格雷指针 MSB 天然慢变 + 两级同步结构正确。

---

## 6. Ac_datahold01a — FIFO 存储→读数据（1 条）

- **规则名**：`Ac_datahold01a`（Incorrect data-enable sequence in synchronized data crossings）
- **数量**：1（CSV ID = 87）
- **CSV 原始描述**：
  `87,des_cdc_top.u_fifo.mem[15:0][63:0],des_cdc_top.wclk,des_cdc_top.u_fifo.rdata_r[63:0],des_cdc_top.clk,Partially-Proved,N.A.`
- **明细 CSV（`Ac_datahold01a/ac_datahold_00.csv`）**：
  | Type | Signal Name | Clock | Status |
  |---|---|---|---|
  | Destination flop | `u_fifo.rdata_r[63:0]` | `des_cdc_top.clk` | Partially-Proved |
  | Source flop | `u_fifo.mem[15:0][63:0]` | `des_cdc_top.wclk` | Partially-Proved |
- **after_fix `adv_cdc.rpt`**：
  `Des: "u_fifo.\rdata_r_reg[0] .Q", Src: "u_fifo.\mem_reg[15][0] .Q", async_fifo.v, 103 : Partially-Proved through depth 83(200), [Flop-Count:95, Design-Cycle:12]`
- **源 → 目的路径**：`wclk` 域 `u_fifo.mem[wbin]`（写，`async_fifo.v:78–81`）→ 读侧
  `clk` 域 `rdata_r <= mem[rbin]`，使能 `rinc & ~rempty`（`async_fifo.v:101–104`）。
- **性质判断：可 waiver 但需理由**
  - 依据 1：写侧 `mem[wbin] <= wdata`、`wbin <= wbin_next`、`wgray <= wgray_next` 均在
    **同一个 posedge wclk** 更新（`async_fifo.v:62–81`），即 `wgray` 反映某字“已写入”。
  - 依据 2：`wgray` 经 `wgray_sync1/2` 两级同步进入 clk 域后，`rempty` 才可能撤销；
    读侧 `rdata_r` 仅在 `rinc & ~rempty` 时采样（`async_fifo.v:101–104`）。因此“读使能”
    必然**晚于“写完成”至少 2 个 wclk 周期**，被读数据在采样前已稳定。
  - 依据 3：这是 Cummings 异步 FIFO 的固有“写先于读使能”语义；工具受形式分析深度限制
    （depth 83/200）无法覆盖全 16 深度任意时序，故判 Partially-Proved 而非 Proved。
- **waiver 草稿**：
  > 本违规为异步 FIFO 存储阵列 `u_fifo.mem[15:0][63:0]`（写域 wclk）到读数据寄存器
  > `u_fifo.rdata_r[63:0]`（读域 clk，`async_fifo.v:101–104`）的“数据保持”检查，工具判
  > Partially-Proved（depth 83/200）。写侧 `mem[wbin]`、`wbin`、`wgray` 在同一 posedge
  > wclk 更新，`wgray` 经两级同步进入读域后 `rempty` 才可能撤销，而 `rdata_r` 只在
  > `rinc & ~rempty` 时采样，因此读使能必然比写完成晚至少 2 个 wclk 周期，数据在采样前
  > 已稳定。该结构是标准 Cummings 异步 FIFO 的固有顺序保证，工具只是受形式深度限制未能
  > 完全闭合。可 waive，理由为写指针两级同步晚于写完成的顺序语义。**需本人确认**：`mem`
  > 综合后未被映射成带读预取寄存器的 BRAM（RTL 已用 `ram_style="distributed"` 钉死，
  > `async_fifo.v:57` 注释说明），否则会多引入一级 BRAM 输出寄存器延迟。

---

## 7. 无法确认 / 需本人确认清单（caveats）

1. **after-fix 的逐条 CSV 未落盘本地**：`consolidated_reports/.../des_cdc_top_cdc_cdc_verify/`
   无 `.csv`；本机 `goals/...` CSV 与 `spyglass_cdc_reports.tar.gz` 均为 **修复前**
   （11-01 21:32 / 11-02 08:50）。Ac_cdc01a 的“修复后源信号”以 `adv_cdc.rpt`（09:40）
   为准，与旧 CSV 不一致（`ready_key_o` FAILED vs `ready_key_o_hold` PROVED）。
2. **`CDC-report.rpt` 计数 ≠ 失败数**：Section G 是消息条数；真实判定见 `adv_cdc.rpt`
   Section E（4 PROVED + 1 Partially-Proved + 1 纯结构）。
3. **Ac_conv01 的 after-fix 明细缺失**：本地只有 11-01 的 `ac_conv_03.csv`（`cdc_verify`
   与 `cdc_verify_struct` 两份一致），依赖 `des_pipe_round_fb.v` 未改（mtime 10-28）。若
   after-fix 重跑了该明细，需以新图核对汇聚门仍是 `xored_R[11]`。
4. **Ac_conv01 的“6 个同步器” vs 明细只列 2 组目的触发器**（toggle_sync 1 bit +
   wgray_sync1 5 bit）未完全展开对应，需用 Schematic 视图核对。
5. **`xored_R[11] = expanded_R[11] ^ subkey_i[11]` 且 `expanded_R[11]=R_i[8]`** 为人工按位
   拼接推算，需本人核对。
6. **“换钥前排空”协议**（Ac_conv01 waiver 的核心前提）RTL 无法自证，需系统/上层确认强制。
7. **32ns vs 10ns 的余量**基于 `clocks.csv` 的 clk=4ns、wclk=10ns；若实际频率不同需重算。

---

*（本文件为只读分析产出的草稿；未改动任何 SpyGlass 报告文件。）*
