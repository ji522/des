# DES 等价类 / 边界值定向回归报告

- 工程：`des_final_version\des_pipeline_soc_v2`（未改动 `des_pipeline\`）
- 日期：2026-11-14
- 结论：**参考实现可信，18 条向量全部生成并跑通，TB PASS 18/18，性质检查 4/4**
- 约束遵守：未修改任何现有 `.mem`、TB、`run_all.ps1`、日志；全部为新建文件

---

## 1. 参考实现与自检

### 1.1 解释器探测

| 候选 | 结果 |
|---|---|
| `D:\anaconda3\python.exe` | 0 字节坏文件，不可用 |
| `C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe` | **Python 3.12.14，可用** |
| `python` / `py` / `python3`（PATH） | 均不存在 |
| `node` | v22.17.0，可用（未使用） |

该 Python 自带环境里 **没有** pycryptodome（`import Crypto` 失败）。但探测发现
`D:\anaconda3\Lib\site-packages\Crypto` 是 **cp312** 的（与运行时 Python 3.12 同 ABI），
因此生成脚本把该目录追加进 `sys.path`，成功导入：

```
reference : pycryptodome Crypto 3.23.0
            (D:\anaconda3\Lib\site-packages\Crypto\Cipher\DES.py)
```

> 注意：这是"复用 anaconda 的库目录"，不是修好了 `D:\anaconda3\python.exe`。
> 如果该目录被清理，`gen_boundary_vectors.py` 会直接失败（不会伪造期望值）。

### 1.2 自检结果（全部通过，任一失败脚本拒绝写文件）

| 自检项 | 结果 |
|---|---|
| FIPS 标准向量 `133457799BBCDFF1 / 0123456789ABCDEF` | **85E813540F0AB405，命中** |
| 弱密钥 `0101...` 的 `E(E(P)) == P` | OK（回到 `0123456789ABCDEF`） |
| 弱密钥 `FEFE...` 的 `E(E(P)) == P` | OK（回到 `0123456789ABCDEF`） |
| 半弱对 `E(FE01..., E(01FE..., P)) == P` | OK（回到 `0123456789ABCDEF`） |
| 补性质 `E(~K,~P) == ~E(K,P)` | OK：`7A17ECABF0F54BFA == ~85E813540F0AB405` |
| 与 **OpenSSL 3.5.7**（legacy provider）逐条交叉验证 | **18/18 一致** |
| 与既有 `verify/vectors/exps.mem` 的 28 条 golden 对比（只读） | **28/28 复现** |

参考值不是手填的，全部由 pycryptodome 现算；OpenSSL 与既有 golden 两路交叉验证进一步排除了"单一库算错"的可能。

### 1.3 向量条数说明

任务列了 **15 个等价类/边界**，其中第 13/14/15 类各要求两行，因此实际生成 **18 行**：

- 12 类单行 = 12 行
- 第 13 类（同明文两拍）= 2 行
- 第 14 类（明文互补对）= 2 行
- 第 15 类（密钥+明文互补对）= 2 行

四个文件（`bkeys.mem` / `bins.mem` / `bexps.mem` / `blabels.txt`）均为 **18 行、逐行对齐**，每行 16 位大写十六进制。

---

## 2. 18 条向量与运行结果

| # | 标签 | 密钥 | 明文 | 期望密文 | 设计意图 | 实际 |
|---|---|---|---|---|---|---|
| 0 | B01 全零 | 0000000000000000 | 0000000000000000 | 8CA64DE9C1B123A7 | 全 0 密钥/明文，最小端边界 | **PASS** |
| 1 | B02 全 1 | FFFFFFFFFFFFFFFF | FFFFFFFFFFFFFFFF | 7359B2163E4EDC58 | 全 1 密钥/明文，最大端边界 | **PASS** |
| 2 | B03 弱密钥 0101 | 0101010101010101 | 0123456789ABCDEF | 617B3A0CE8F07100 | 弱密钥自反性 E(E(P))=P | **PASS** |
| 3 | B04 弱密钥 FEFE | FEFEFEFEFEFEFEFE | 0123456789ABCDEF | 6DCE0DC9006556A3 | 弱密钥自反性 E(E(P))=P | **PASS** |
| 4 | B05 半弱密钥 | 01FE01FE01FE01FE | 0123456789ABCDEF | 8A76C7A4F16D47ED | 与 FE01... 互为半弱对 | **PASS** |
| 5 | B06 交替模式 | 5555555555555555 | AAAAAAAAAAAAAAAA | 343A09F9B2CB5CCA | 0101 交替位模式 | **PASS** |
| 6 | B07 交替交叉 | AAAAAAAAAAAAAAAA | 5555555555555555 | CBC5F6064D34A335 | 密钥/明文 0101 模式互换 | **PASS** |
| 7 | B08 单比特密钥游走 | 0000000000000001 | 0000000000000000 | 8CA64DE9C1B123A7 | 密钥 LSB 单比特 | **PASS** |
| 8 | B09 单比特明文游走 | 133457799BBCDFF1 | 8000000000000000 | 87AB78D11E188DF6 | 明文 MSB 单比特 | **PASS** |
| 9 | B10 零明文 | 133457799BBCDFF1 | 0000000000000000 | 948A43F98A834F7E | 标准密钥 + 全零明文 | **PASS** |
| 10 | B11 全 1 明文 | 133457799BBCDFF1 | FFFFFFFFFFFFFFFF | 5A3DB304D64924FD | 标准密钥 + 全 1 明文 | **PASS** |
| 11 | B12 FIPS 复核 | 133457799BBCDFF1 | 0123456789ABCDEF | **85E813540F0AB405** | 标准向量复核 | **PASS** |
| 12 | B13 ECB 确定性 1 | 133457799BBCDFF1 | 0123456789ABCDEF | 85E813540F0AB405 | 同明文块第 1 拍 | **PASS** |
| 13 | B14 ECB 确定性 2 | 133457799BBCDFF1 | 0123456789ABCDEF | 85E813540F0AB405 | 同明文第 2 拍，查流水线串扰 | **PASS** |
| 14 | B15 互补对基准 | 133457799BBCDFF1 | 0123456789ABCDEF | 85E813540F0AB405 | 明文互补对基准 P | **PASS** |
| 15 | B16 明文互补 | 133457799BBCDFF1 | FEDCBA9876543210 | 4AB65B3D4B061518 | P = ~P0，同密钥 | **PASS** |
| 16 | B17 补性质基准 | 133457799BBCDFF1 | 0123456789ABCDEF | 85E813540F0AB405 | 补性质基准 E(K,P) | **PASS** |
| 17 | B18 密钥+明文互补 | ECCBA8866443200E | FEDCBA9876543210 | 7A17ECABF0F54BFA | E(~K,~P) 应 = ~E(K,P) | **PASS** |

### 2.1 一个值得注意的边界发现

B01（密钥 `0000000000000000`）与 B08（密钥 `0000000000000001`）密文**完全相同**：
`8CA64DE9C1B123A7`。

原因：`key_i[0]` 是**奇偶校验位**，DES 的 PC-1 置换会丢弃每个字节的校验位（本工程设计里
`pc1_C/pc1_D` 也没有引用 `key_i[0]`、`[8]`、`[16]`…）。所以这两个密钥对 DES 完全等价。

- 这条向量仍然有价值：它验证了 PC-1 对校验位的正确处理（该位不参与子密钥）；
- 但如果想测"真正的单比特密钥游走"，应改用非校验位，例如 `0000000000000002`；
- 面试里可以把这一点作为"为什么定向向量不能随便挑最低位"的例子，而不是说"单比特游走已经全覆盖"。

---

## 3. 性质检查结果

| 性质 | 参考实现（pycryptodome） | DUT（TB 内注入） | 结果 |
|---|---|---|---|
| 弱密钥 `0101...`：E(E(P)) == P | OK | P1：`0123456789ABCDEF` 回到原明文 | **PASS** |
| 弱密钥 `FEFE...`：E(E(P)) == P | OK | P2：`0123456789ABCDEF` 回到原明文 | **PASS** |
| 半弱对：E(FE01..., E(01FE..., P)) == P | OK | P3：`0123456789ABCDEF` 回到原明文 | **PASS** |
| 补性质：E(~K,~P) == ~E(K,P) | OK | P4：`7A17ECABF0F54BFA == ~85E813540F0AB405` | **PASS** |

- 弱密钥/半弱对检查是**真正过 DUT 的**：把 DUT 输出的密文再次注入同一流水线（或半弱对的另一半密钥），比对是否回到原明文，不是只比参考库。
- 补性质 P4 用主阶段捕获的两条 DUT 输出做按位取反比较。

---

## 4. TB 与脚本运行结果

### 4.1 新建文件

| 文件 | 作用 |
|---|---|
| `verify\gen_boundary_vectors.py` | 生成向量 + 全部自检（FIPS、弱密钥、半弱对、补性质、OpenSSL、既有 golden） |
| `verify\vectors_bnd\bkeys.mem` | 18 条密钥 |
| `verify\vectors_bnd\bins.mem` | 18 条明文 |
| `verify\vectors_bnd\bexps.mem` | 18 条期望密文 |
| `verify\vectors_bnd\blabels.txt` | 18 行标签，与 `.mem` 逐行对齐 |
| `verify\tb_des_boundary.v` | 独立 TB，纯 Verilog-2001，接 `des_pipeline_fb` |
| `verify\run_boundary.ps1` | 只跑该 TB 的 pwsh 7 脚本 |
| `verify\logs\tb_des_boundary.log` | 本次仿真日志 |
| `verify\_boundary_report.md` | 本报告 |

生成命令（已执行）：

```
pwsh -NoProfile -Command "& 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\gen_boundary_vectors.py'"
```

仿真命令（已执行）：

```
pwsh -NoProfile -ExecutionPolicy Bypass -File "F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\verify\run_boundary.ps1"
```

### 4.2 仿真结果

```
main : pass=18 err=0 x=0 extra=0
PROP OK : 0123456789abcdef
PROP OK : 0123456789abcdef
PROP OK : 0123456789abcdef
PROP OK : complement E(~K,~P)==~E(K,P) : 7a17ecabf0f54bfa

================ BOUNDARY SUMMARY ================
  vectors             : 18
  scoreboard pass     : 18
  mismatch            : 0
  X/Z                 : 0
  extra output        : 0
  property pass/fail  : 4/0
==================================================
BOUNDARY TB PASS : 18/18  (property 4/4)
```

- 工具：Vivado 2018.3 XSim（`xvlog` / `xelab` / `xsim`）
- 退出码：0（脚本检测到 `BOUNDARY TB PASS`）
- 日志：`verify\logs\tb_des_boundary.log`
- 仿真工作目录：`_sim_tb_des_boundary\`（新建，未复用/覆盖现有 `_sim_*`）

---

## 5. 未完成部分与限制（如实说明）

1. **没有把边界回归挂进 `run_all.ps1`**：硬约束要求不改现有回归入口，所以它是独立脚本；
   要纳入 5/10 组汇总，需要再改 `run_all.ps1`（本次未做）。
2. **本 TB 只测加密方向、`ready_i` 恒 1**：反压/溢出场景由现有
   `tb_des_pipeline_fb_v2.v` 的 42 笔回归覆盖，本 TB 不重复；解密方向也未覆盖。
3. **单比特游走不是 64 位全扫描**：按任务要求只取了密钥 LSB 和明文 MSB 各一条；
   且密钥 LSB 是校验位（见 2.1），真正想覆盖非校验位需另加 `0000000000000002` 等向量。
4. **pycryptodome 依赖 anaconda 的 site-packages 目录**：本机 PATH 里没有可用 `python`，
   anaconda 的 `python.exe` 是 0 字节；当前通过 `sys.path` 复用其 cp312 库。若该目录被删，
   生成脚本会失败并退出，不会产出未经验证的期望值。OpenSSL 可作为第二参考，但脚本目前以
   pycryptodome 为主。
5. **`blabels.txt` 只作文档**：TB 不读取标签，标签与 `.mem` 靠行号对齐（已检查 18/18 行一致）。
6. **报告里的"16 条"与"18 行"**：任务列了 15 类，其中 13/14/15 各两行，实际为 18 行；
   15 个类别全部覆盖，没有删减。

---

## 6. 面试口径建议（一句话）

可以说：**"我补了 18 条 DES 等价类/边界定向向量，期望值由 pycryptodome 现算并做了 FIPS、
OpenSSL、既有 28 条 golden 三重自检；独立 TB 在 XSim 跑到 18/18，弱密钥自反、半弱对、
补性质 4 项也过 DUT 验证；还发现了密钥 LSB 是校验位、PC-1 会丢弃的有趣边界。"**

不可以说：**"边界覆盖已经完备/64 位单比特全扫描"**——实际只覆盖指定类别，
单比特游走只有两条且其中一条打在奇偶校验位；也**不能说"已并入主回归"**，它目前是独立脚本。
