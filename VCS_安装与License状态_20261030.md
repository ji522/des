# VCS/Verdi 安装与 License 状态记录

> 记录时间：2026-10-30
> 目的：环境可复现 + 后续换工具时知道哪些已就绪、哪些卡住

---

## 一、已完成（可复用）

### 1. 安装位置（全在 D 盘）

WSL 发行版磁盘在 `D:\WSL\ext4.vhdx`，**不占 C 盘**。

| 组件 | 路径 | 状态 |
|---|---|---|
| VCS | `/opt/synopsys/vcs/W-2024.09-SP1` | 已装，`vcs -id` 可运行 |
| Verdi | `/opt/synopsys/verdi/W-2024.09-SP1` | 已装，可启动 |
| Verdi 补充库 | `/opt/synopsys/verdi_supp/W-2024.09-SP1` | 已装（post-install 报错但不影响主体） |
| SCL | `/opt/synopsys/scl/2024.06` | 已装（二进制疑似被改动，见第四节） |

磁盘占用：约 65 GB，D 盘剩余约 890 GB。

### 2. 环境变量（已写入 `/root/.bashrc`）

```bash
export VCS_HOME=/opt/synopsys/vcs/W-2024.09-SP1
export VERDI_HOME=/opt/synopsys/verdi/W-2024.09-SP1
export NOVAS_HOME=/opt/synopsys/verdi/W-2024.09-SP1
export VCS_TARGET_ARCH=amd64
export VCS_ARCH_OVERRIDE=linux
export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${VERDI_HOME}/platform/LINUXAMD64/lib:${VERDI_HOME}/share/PLI/lib/LINUX64:${VCS_HOME}/linux64/lib:${LD_LIBRARY_PATH}"
```

### 3. HOST ID（已锁定，重要）

**HOST ID = `c0353267a4d5`**（Windows 物理网卡 WLAN 的 MAC，`C0-35-32-67-A4-D5`）

锁定方式：修改 `C:\Users\Lenovo\.wslconfig`

```ini
[wsl2]
networkingMode=mirrored
```

镜像网络模式下 WSL 能直接看到 Windows 物理网卡，`lmutil lmhostid` 能读到 `c0353267a4d5`。
**已实测连续 3 次 `wsl --shutdown` 重启后该值不变。**

> 注意：不能绑 WSL 虚拟网卡 eth0 的 MAC。默认 NAT 模式下该 MAC 每次重启都变
> （实测 `00155d5ac626` → `00155d5acea0` → `00155d5acabe`）。
> `.wslconfig` 里的 `macAddress` 选项在 WSL 2.7 已失效。

---

## 二、装 Ubuntu 24.04 的坑（重装时必看）

按踩坑顺序记录，重装可照做：

1. **`/mnt/d` 是 9p 文件系统，安装器识别不了 `.spf` 包**
   → 必须先把 `.spf` 拷进 WSL 内部目录（如 `~/synopsys_setup/`）再装。

2. **`.spf.part00/01` 不能手动 `cat` 合并**
   → 安装器会自己合并。手动合并出来的文件 CRC 对不上，装到一半会报
   `Extracting release information ... failed: This does not look like a tar archive`。

3. **`/bin/sh` 是 dash，Synopsys 工具要求 bash**
   → `ln -sf /bin/bash /bin/sh`。不改会报 `sh: 0: Illegal option -h`。

4. **Verdi 缺大量 Qt5 和 X11 库**
   → 已装：`libxss1 libnuma1 libtbb12` 及一整套 `libqt5*`（core/gui/widgets/network/
   x11extras/test/charts/printsupport/webenginewidgets/webview/concurrent/webchannel/
   sql/script/xml/svg/opengl）。

5. **在 Git Bash 里写 `.bashrc` 会被 Windows 变量提前展开**
   → 必须用脚本文件 + 单引号 heredoc（`<< 'EOF'`），不能让 `$VCS_HOME` 经过 Git Bash。

6. **Git Bash 会把 WSL 路径转换成 Windows 路径**
   → 调 `wsl` 前先 `export MSYS_NO_PATHCONV=1`。

7. **`wsl -d Ubuntu -- bash -lc '...'` 会重置 PATH**
   → 用脚本文件方式执行，不要依赖 `-lc` 传环境。

---

## 三、License 当前状态：卡住

### 现象

`/opt/synopsys/scl/2024.06/admin/license/syn.license.dat`（原名 `Synopsys.dat`，1,067,258 字节，11,391 行）

- `SERVER LAPTOP-0VJCE2AV c0353267a4d5 27000` ← **hostid 正确**
- 2847 个 `SIGN=` 字段**全是占位符**：`SIGN="0000 1111 2222 3333 4444 5555 6666 7777 8888 9999 AAAA BBBB CCCC DDDD EEEE FFFF ..."`
- 同样的占位序列重复出现在每条 `INCREMENT` 里

### lmgrd 日志

```
Invalid license key (inconsistent authentication code)  × 2843 次
No features to serve                                    × 2 次
```

`snpslmd` 因无可用 feature 退出（status 36）。

### 关键 feature 检查

| Feature | 条数 |
|---|---|
| VCS | 0 |
| VCSRuntime | 1 |
| Verdi | 1 |
| VerdiRuntime | 0 |

即使签名有效，`VCS` feature 本身也不在文件里。

### 结论

**这不是配置问题。** FlexNet 的 `SIGN` / `AUTH={LK=...}` 是用 Synopsys 私钥签的加密签名，
任何生成器都伪造不出来。占位符签名 = 这个文件从来没被真正签发过。

### 待办

联系学校重新签发 license，报：

> hostid = `c0353267a4d5`
> 需要 feature：VCS、Verdi（含 runtime）
> 版本 W-2024.09-SP1，SCL 2024.06

如果学校用的是共享 license 服务器，则不需要绑 MAC，只要服务器地址。

---

## 四、疑似被改动的东西（需要警惕）

| 项 | 证据 | 判断 |
|---|---|---|
| `S crack/` 目录 | 下载目录里存在 | 破解工具，未使用 |
| `/opt/synopsys/scl/2024.06/linux64/bin/snpslmd` | 修改时间 `2024-05-27 20:07`，而同目录 `lmgrd`/`lmutil` 是 `2024-05-23 20:14`；大小 14,930,152 字节 | 时间戳与同批文件不一致，**疑似被替换** |

当前 MD5：`ea4a7cf4e33e2ae5c1e885b9662c1690`

> 如果要用这套环境，建议先重装一次 SCL 恢复原版二进制，
> 再配学校签发的合法 license。用改动过的 daemon 跑合法 license 也可能出问题。

---

## 五、还没做的

- VCS 编译脚本（拿到 license 当天可一键跑 DES UVM 回归）
- 用 VCS 验证 `des_ral_pkg.sv` 里 `uses_frontdoor` 开关是否该关掉
  （XSim 的 `ref` 缺陷只在 XSim 存在，换 VCS 后应回到标准 adapter 路径）

---

## 六、相关文件

- 工程基线：`F:\DeskTop\IC项目\des_final_version\des_pipeline_soc_v2\`
- 回归入口：`verify\run_all.ps1`（11/11 全 PASS，跑在 Vivado XSim 2018.3 上）
- 环境脚本：`verify\wsl\`（query_hostid.sh / fix_verdi_libs.sh / setup_env.sh 等）
- WSL 配置：`C:\Users\Lenovo\.wslconfig`
