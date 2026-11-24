# CDC 随机时钟比 / 相位回归报告

- 日期：2026-11-15
- 工程：`F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2`
- 工具：Vivado 2018.3 XSim（`xvlog.bat` / `xelab.bat` / `xsim.bat`），Windows + PowerShell 7
- 被测设计：`cdc/des_cdc_top.v`（异步 FIFO + 2FF/toggle 同步 + reset_sync）
- 基线 TB：`verify/tb_cdc/tb_des_cdc.v`（未修改）

## 1. 目的

参考 TB 把写时钟固定为 100 MHz（`#5`）、读时钟固定为 250 MHz（`#2`）。
本回归把两个时钟的半周期和初始相位改成 plusargs 可配置，在**不改 RTL、不改向量、
不改原 TB 和原脚本**的前提下，用 10 组不同时钟比/相位重复同一套 190 笔激励，
检验跨域数据通路在更宽的时钟关系下是否仍然零丢失、零重复、零 X。

## 2. 新增文件

| 文件 | 作用 |
|---|---|
| `verify/tb_cdc/tb_des_cdc_randclk.v` | 可配置时钟的 TB，激励/判据复制自 `tb_des_cdc.v` |
| `verify/run_cdc_randclk.ps1` | 编译一次 + 10 组回归 + 超时保护 + 汇总表 |
| `verify/_cdc_randclk_report.md` | 本报告 |
| `verify/logs/cdc_randclk/*.log` | 每组一个日志（另有 `_compile.log`、`_summary.csv`） |
| `verify/_sim_tb_des_cdc_randclk/` | XSim 工作目录（编译产物 + 拷入的向量） |

## 3. 时钟配置方式

TB 接受四个 plusargs（单位 ns）：

| plusarg | 含义 | 默认 |
|---|---|---|
| `+W_HALF=<ns>` | 写时钟半周期 | 5 |
| `+C_HALF=<ns>` | 读时钟半周期 | 2 |
| `+W_PHASE=<ns>` | 写时钟初始相位偏移 | 0 |
| `+C_PHASE=<ns>` | 读时钟初始相位偏移 | 0 |

实现要点：

```verilog
integer w_half = 5;   // 声明处初始化，时间 0 之前生效
...
initial begin
    if (!$value$plusargs("W_HALF=%d", w_half)) w_half = 5;
    ...
    clk_go = 1'b1;    // 解析完成后才允许时钟启动
end

always @(posedge clk_go) begin
    #(w_phase);
    forever #(w_half) wclk = ~wclk;   // 每次循环重新求值半周期
end
```

- 半周期/相位变量用声明初始化值，保证时钟进程第一次求值时不是 `x`；
- plusargs 解析完成后才置 `clk_go`，时钟进程等该上升沿启动，
  避免 `#x` 被当作 0 延迟造成零延迟死循环；
- 复位释放后第一个上升沿在 `phase + half` 处，`phase=0` 时与基线
  （`#5`/`#2`）的边沿时刻完全一致。

激励与判据（逐行复制自参考 TB，diff 已核对，除时钟/打印外无功能改动）：

- 3 轮 ×（28 加密 + 14 解密）+ 64 笔单密钥满压力 = 190 笔；
- 下游 85% 随机 ready，每 8 笔插入一次 250 拍长 stall；
- 换钥前 drain，两域复位释放错开（#37 / #50）；
- 比对条件：`n_err==0 && n_x==0 && n_extra==0 && n_cmp==n_push && n_push==190`；
- 结束打印统一格式：
  `RANDCLK PASS push=190/cmp=190/mismatch=0/x=0/extra=0 wfull=...`
  （失败为 `RANDCLK FAIL ...`）；`wfull` 仅作信息记录。

## 4. 运行方式

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File `
  "F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\run_cdc_randclk.ps1"
```

脚本行为：`xvlog --nolog -sv` 编译一次（RTL 列表与 `run_cdc.ps1` 相同，只把 TB 换成
`tb_des_cdc_randclk.v`）→ `xelab` 生成快照 → 每组用
`xsim <snap> -R -testplusarg "W_HALF=..." ...` 运行；每组独立日志，
`Start-Process + WaitForExit(300s)` 做超时保护，超时用 `taskkill /T /F` 杀进程树；
日志正则解析 `RANDCLK PASS/FAIL` 行，最后打印汇总表并写 `_summary.csv`。

> 注意：xsim 的参数解析会把未加引号的 `a=b` 拆成两个词
> （报 `Expected a switch but found b`），脚本里整行拼成带双引号的字符串再传入。

## 5. 结果

运行环境：Windows 11，Vivado 2018.3 XSim，2026-11-15。
10 组全部完成，单组墙钟 3.4–5.5 s，无超时；所有 `.err.log` 为空。

| # | 配置 (W_HALF, C_HALF, W_PHASE, C_PHASE) | 写时钟 | 读时钟 | 读/写频率比 | 结果 | push/cmp | mismatch | x | extra | wfull | 仿真结束 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | (5, 2, 0, 0) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 406 | 39778 ns |
| 2 | (5, 2, 1, 3) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 409 | 39781 ns |
| 3 | (5, 2, 3, 1) | 100.0 MHz | 250.0 MHz | 2.50x | PASS | 190/190 | 0 | 0 | 0 | 404 | 39779 ns |
| 4 | (5, 3, 0, 2) | 100.0 MHz | 166.7 MHz | 1.67x | PASS | 190/190 | 0 | 0 | 0 | 514 | 58019 ns |
| 5 | (4, 2, 1, 0) | 125.0 MHz | 250.0 MHz | 2.00x | PASS | 190/190 | 0 | 0 | 0 | 534 | 38882 ns |
| 6 | (3, 2, 2, 1) | 166.7 MHz | 250.0 MHz | 1.50x | PASS | 190/190 | 0 | 0 | 0 | 617 | 38675 ns |
| 7 | (6, 2, 3, 0) | 83.3 MHz | 250.0 MHz | 3.00x | PASS | 190/190 | 0 | 0 | 0 | 250 | 39546 ns |
| 8 | (5, 1, 0, 1) | 100.0 MHz | 500.0 MHz | 5.00x | PASS | 190/190 | 0 | 0 | 0 | 139 | 21488 ns |
| 9 | (7, 2, 2, 3) | 71.4 MHz | 250.0 MHz | 3.50x | PASS | 190/190 | 0 | 0 | 0 | 96 | 39829 ns |
| 10 | (5, 4, 1, 2) | 100.0 MHz | 125.0 MHz | 1.25x | PASS | 190/190 | 0 | 0 | 0 | 960 | 76874 ns |

**汇总：10/10 PASS（每组 push=190、cmp=190、mismatch=0、x=0、extra=0）。**

观察：

- 时钟比覆盖 1.25x–5.00x，写时钟 71.4–166.7 MHz，读时钟 125–500 MHz；
- `wfull` 从 96（3.5x）到 960（1.25x）不等，说明各组都实际进入了 FIFO 满/源侧节流路径，
  不是“FIFO 从未写满”的空跑；长 stall 与随机反压两种机制均被激励到；
- 同频率不同相位（第 1/2/3 组）结果一致，`wfull` 仅小幅波动（404–409），
  符合“只改相位不改功能”的预期；
- 读时钟越快，仿真结束时间越短（第 8 组 21.5 µs），说明长 stall 以读时钟拍数计。

## 6. 日志

目录：`F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\logs\cdc_randclk\`

| 文件 | 内容 |
|---|---|
| `_compile.log` | xvlog / xelab 输出 |
| `w5_c2_wp0_cp0.log` | 第 1 组（基线 100M→250M） |
| `w5_c2_wp1_cp3.log` | 第 2 组 |
| `w5_c2_wp3_cp1.log` | 第 3 组 |
| `w5_c3_wp0_cp2.log` | 第 4 组 |
| `w4_c2_wp1_cp0.log` | 第 5 组 |
| `w3_c2_wp2_cp1.log` | 第 6 组 |
| `w6_c2_wp3_cp0.log` | 第 7 组 |
| `w5_c1_wp0_cp1.log` | 第 8 组 |
| `w7_c2_wp2_cp3.log` | 第 9 组 |
| `w5_c4_wp1_cp2.log` | 第 10 组 |
| `_summary.csv` | 脚本导出的汇总（便于二次处理） |

每组日志均含 `RANDCLK CFG ...`（确认 plusargs 确实生效）和
`RANDCLK PASS push=.../cmp=.../mismatch=.../x=.../extra=... wfull=...`。

## 7. 分析

### 7.1 没有出现失败组

10 组配置全部 190/190 对齐，没有任何 mismatch / extra / X。由于最后一组把读时钟降到
125 MHz（仅 1.25x），第一组之外的多数配置又把写域提高到 166.7 MHz（1.5x），
FIFO 两端压力方向和原 TB（2.5x）不同，仍然全对，说明：
异步 FIFO 的格雷码指针 + 2FF 同步、show-ahead 适配、换钥 toggle 同步在
这些整数 ns 比下都没有暴露功能问题。

### 7.2 公共时钟沿确实存在（不是“天然异步”）

原 TB 注释称 100 MHz/250 MHz“无公共沿”，实际 `#5` 与 `#2` 在 t=10/20/30… ns 同时有边沿。
本回归的 10 组中，至少 8 组存在公共沿，例如：

- (5,2,0,0)：每 10 ns 两域同时翻转；
- (5,3,0,2)：t=5/20/35… ns 同时有沿；
- (5,1,0,1)：读时钟每 1 ns 翻转，写时钟边沿必然与读时钟边沿重合；
- 只有 (4,2,1,0) 和 (6,2,3,0) 因一边恒为奇数时刻、另一边恒为偶数时刻而没有公共沿。

在零延迟 RTL 仿真里，公共沿由事件调度顺序决定，DUT 触发器用非阻塞赋值、
采到的是本拍沿之前的旧值，因此结果确定且不会出现亚稳态。**这正是本回归的局限**：
它验证的是功能协议（格雷码、2FF、握手），不是硅上公共沿附近的建立/保持与亚稳态行为。

### 7.3 XSim `$urandom` 流与参考 TB 不同（已定位，非功能问题）

基线配置 (5,2,0,0) 的 `wfull=406`，而直接重跑原 `tb_des_cdc.v` 的同一 RTL 是 `wfull=313`。
A/B 实验（均在当前工程、当前 RTL、同一台机器上可复现）：

| 变体 | 相对参考 TB 的改动 | wfull |
|---|---|---|
| 参考 TB（原样） | — | 313 |
| 参考 TB + 模块改名 | 仅改 module 名 | 313 |
| 参考 TB + 5 个空 `initial begin end` | 仅增加进程 | 313 |
| 参考 TB + 4 个整数/1 个 reg 声明初始化 | 仅增加变量声明 | 313 |
| 参考 TB + 额外 initial（只做赋值，无 plusargs） | 增加一个时间 0 的 initial | 313 |
| 参考 TB + 额外 initial 且调用 `$value$plusargs` | 增加 plusarg 解析 | **406** |
| 新 TB（默认配置） | 上述全部 | 406 |

结论：在 XSim 2018.3 中，`$value$plusargs` 的调用本身会改变 `$urandom` 的确定性序列
（不是模块名、进程数或变量初始化造成的）。因此本 TB 的随机反压/随机间隔序列与参考 TB
不是同一串随机数，但**激励结构与判据逐行相同**，且每组重复运行结果稳定可复现
（同一配置连续跑两次 `wfull` 均为 406）。这不影响“190 笔全对”的结论。

### 7.4 设计层面的余量提示（不是本次失败项）

`des_cdc_top.v` 的反向通道用 `RDY_HOLD=8` 个快域周期展宽 `ready_key_o`，注释中的前提是
“8×4 ns = 32 ns > 3 个 wclk 周期（30 ns @100 MHz）”。当读时钟更快时：
- 第 8 组 500 MHz：保持窗仅 8×2 = 16 ns，只有 1.6 个 100 MHz 写周期；
- 第 9 组写时钟 71.4 MHz：3 个写周期需要 42 ns，大于 32 ns。

本 TB 里 `ready_key_o` 是换钥边界上的准静态状态（READY 一直保持到下一次 load_key），
不是窄脉冲，所以 2FF 同步仍能采到，10 组都通过。但**这次通过不能证明该保持窗在所有
时钟比下都满足 `Ac_cdc01a`**；真要签核该路径需要按最坏时钟比重新核算 RDY_HOLD 或做
Spyglass CDC 检查。这一条属于设计假设的边界，记录在此避免把“本次 PASS”误读成
“任意时钟比下反向通道都已证明”。

## 8. 局限

1. **整数 ns 半周期会产生公共沿**：如 7.2 所述，10 组中至少 8 组存在两域同时翻转。
   零延迟仿真用事件顺序 + NBA 化解，不建模亚稳态、建立/保持违例和 MTBF；
   通过只说明功能协议正确，不是 CDC 时序签核。
2. **不是形式化证明**：只覆盖 10 个离散（半周期, 相位）点，没有状态空间穷举，
   也没有覆盖所有可能的指针回绕/复位释放组合。
3. **未做随机种子扫描**：XSim 的 `$urandom` 序列由构建决定、组内可复现，但脚本不注入
   `+sv_seed`，每组只有一条随机反压轨迹；换种子可能得到不同的 stall 分布。
   另外已实测 plusargs 调用会改变随机流（7.3），因此与原 TB 的随机序列不同。
4. **相位覆盖很窄**：相位只取 0–3 ns，且都小于相应半周期，没有做整周期相位扫描，
   也没有覆盖“相位恰好等于半周期/整周期”的退化点。
5. **只测了读时钟不慢于写时钟**：10 组全部 `C_HALF <= W_HALF`（1.25x–5x）。
   读慢于写的方向（FIFO 长时间接近满、写侧持续背压）没有覆盖。
6. **无抖动/占空比/频率漂移**：时钟是理想 50% 占空比、固定周期的方波，
   没有加 jitter、频偏、非 50% 占空比或时钟门控。
7. **`wfull` 仅作信息**：脚本和 TB 都不对 `wfull` 下断言；它只用于确认 FIFO 满路径
   被激励到（本次 96–960 拍）。
8. **看门狗是仿真时间 1 ms、脚本超时是墙钟 300 s**：只防死循环/挂死，
   不保证覆盖所有慢速收敛场景。
9. **未做综合/Spyglass/CDC 约束检查**：本回归是 RTL 行为仿真，不能替代
   `cdc/cdc.xdc` 的 `set_clock_groups`、`ASYNC_REG` 检查和 CDC 签核流程。

## 9. 结论

在不修改任何现有 RTL / TB / 向量 / 脚本 / 日志的前提下，新建的可配置时钟 TB 与回归脚本
完成了 10 组时钟比/相位组合的实际仿真：**10/10 PASS，190/190 逐笔对齐，
mismatch/x/extra 全为 0**，且各组 `wfull` 均非零，说明 FIFO 满与源侧节流路径被真实激励。
结果同时暴露了两个需要如实记录的点：整数 ns 周期下公共时钟沿普遍存在（仿真不建模亚稳态），
以及 `RDY_HOLD` 反向通道在更极端时钟比下的余量需要另行核算。上述结论只对本次
10 组配置和 XSim 行为级仿真成立。
