# 2 通道 AXI4-Stream 仲裁/交换器 + DES SoC 集成

日期：2026-11-24  
工具：VCS O-2018.09-SP2（CentOS7 VM）  
结论：VCS 全量回归 **12/12 PASS**（原 10 组 + 新增 2 组）

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

### 3.2 集成（`tb_des_arb_soc.v`）

- ch0 发 `ins[0..3]`，ch1 发 `ins[4..7]`，经仲裁后进 DES 加密。
- **8 beats / 2 packets**，输出与 `exps[0..7]` 逐拍一致，TLAST 在第 4/8 拍对齐。
- 计数器：ch0/ch1 各 1 packet out、4 beats out。
- 通过标志：`DES ARB SOC PASS : 8 beats, 2 packets, TLAST aligned`

### 3.3 全量回归

`verify/vcs/run_all_vcs.sh`：**PASS=12 FAIL=0**（新增 t11_arb、t12_arb_soc）。

---

## 4. 边界（面试要主动说）

- 两个输入与输出同属 `clk` 域；不含异步 FIFO。需要跨时钟时，在每个输入前各接一个 `cdc/async_fifo.v`。
- 两个 AXI4-Lite 从端口（DES 控制面 + 仲裁器控制面）分开暴露；真实 SoC 前面会放 AXI4-Lite crossbar/地址译码。
- 仲裁是**包级**，不是 beat 级；beats 交错会破坏 DES 块边界。
- `almost_full` 是 advisory 预判，不接去门控 `s_axis_tready` 代替 `full`；正确性仍由 `full` 保证。
- 未做形式验证；断言/覆盖率可后续补（SVA：满不写、空不读、TLAST 位置、包内通道不变）。

---

## 5. 面试 60 秒口径

> “这是一个 2 通道 AXI4-Stream 仲裁器：每通道 16 深 FIFO，存 `{tlast, tdata}`；包级 round-robin，一旦开始一个包就锁到 TLAST，避免两路数据交错；输出反压时 FIFO 攒数，满了向上游反压，不丢数。控制面是 AXI4-Lite，有 almost_full 阈值、每通道 beats/packets/stall/blocked 计数器和中断。验证在 VCS 上跑：standalone 24 beats/6 packets 零错，集成到 DES 后 8 beats/2 packets、TLAST 对齐，全量回归 12/12。”

---

## 6. 文件

- `sync_fifo.v` — 参数化同步 FIFO（count、almost、overflow/underflow 脉冲）
- `axis_arb2.v` — 2 通道仲裁/交换器
- `axis_arb_regs.v` — AXI4-Lite 控制/状态/计数器
- `des_arb_soc_top.v` — 与 `des_soc_top` 集成
- `verify/tb_axis_arb2.v` — standalone 自检
- `verify/tb_des_arb_soc.v` — DES 集成自检
- `verify/vcs/run_axis_arb_vcs.sh` — 新增 2 组 VCS 回归
- `verify/vcs/run_all_vcs.sh` — 已并入第 11、12 组
