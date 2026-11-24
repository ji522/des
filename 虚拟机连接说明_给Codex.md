# IC_EDA 虚拟机连接说明（给 Codex）

> 用途：数字 IC 设计流程（综合 / 布局布线 / 时序 / 形式验证）的调研与运行
> 更新日期：2026-10-31
> 维护：本文件由 Claude 侧维护，参数变化时同步更新

---

## 一、基本信息

| 项 | 值 |
|---|---|
| 虚拟机文件 | `D:\Centos7\IC_EDA.vmx` |
| 宿主机 VMware | Workstation（`C:\Program Files (x86)\VMware`） |
| 系统 | CentOS 7.9.2009 |
| 主机名 | `IC_EDA` |
| 用户 | `ICer` |
| 密码 | `2022` |
| 宿主机 VMnet8 网关 | `192.168.188.2`（NAT 网关） |
| 虚拟机 IP | **`192.168.188.100`（已固定为静态，不会变）** |

---

## 二、SSH 连接

```bash
ssh ICer@192.168.188.100
# 密码：2022
```

### ⚠️ 最常见连不上的原因

**SELinux**。CentOS 默认 `Enforcing`，会拒绝 SSH 公钥认证。

已做永久关闭（2026-10-31）：`/etc/selinux/config` 改为 `SELINUX=disabled`。
**但需要重启虚拟机才完全生效**，重启前可临时执行：

```bash
sudo setenforce 0
```

### ⚠️ 第二种连不上：NetworkManager 被关掉（2026-11-03 实测）

现象：ping 不通、ARP 表里看不到 `.100`、SSH 超时；进虚拟机的桌面看得到系统正常。
原因：`/var/lib/NetworkManager/NetworkManager.state` 里 `NetworkingEnabled=false`，
所有网卡（包括 `lo`）都显示“未托管”，`ens33` 没有 IP。

```bash
sudo nmcli networking on
sudo systemctl restart NetworkManager
ip addr show ens33          # 应看到 192.168.188.100/24
```

### 没有 SSH 时的应急通道（vmrun）

宿主机可执行 `C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe`：

```bash
vmrun -T ws -gu ICer -gp 2022 captureScreen  "D:\Centos7\IC_EDA.vmx" C:\tmp\screen.png
vmrun -T ws -gu ICer -gp 2022 listProcessesInGuest "D:\Centos7\IC_EDA.vmx"
vmrun -T ws -gu ICer -gp 2022 runProgramInGuest "D:\Centos7\IC_EDA.vmx" /bin/bash -c "cmd > /tmp/o 2>&1"
vmrun -T ws -gu ICer -gp 2022 CopyFileFromGuestToHost "D:\Centos7\IC_EDA.vmx" /tmp/o C:\tmp\o.txt
```

> **Git Bash 下必须 `export MSYS_NO_PATHCONV=1`**，否则 `/bin/bash` 被转成 Windows 路径，
> 报 “The file does not exist”。
> `runProgramInGuest` 不会把 stdout 传回来，必须重定向到文件再 `CopyFileFromGuestToHost`。

### 免密登录（已配置，若失效则重装）

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKv+dAk18a9Eup9pyvPqRsMjPVxWAZ37Vxykjwk7bvD shiyunji2002@163.com' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## 三、网络配置（已改静态，2026-10-31）

原先用 DHCP，IP 每次重启都变（观察到 `.128` → `.129`）。已改为静态 IP。

**当前配置** `/etc/sysconfig/network-scripts/ifcfg-ens33`：

```
BOOTPROTO=static
IPADDR=192.168.188.100
PREFIX=24
GATEWAY=192.168.188.2
DNS1=8.8.8.8
DNS2=114.114.114.114
```

**备份在** `ifcfg-ens33.bak`。网络出问题时恢复：

```bash
sudo cp /etc/sysconfig/network-scripts/ifcfg-ens33.bak /etc/sysconfig/network-scripts/ifcfg-ens33
sudo systemctl restart network
```

### 万一还是连不上，怎么找 IP

```bash
# 虚拟机里
ip addr | grep "inet " | grep -v 127.0.0.1

# 宿主机
arp -a | Select-String "192.168.188"

# 扫网段
nmap -sn 192.168.188.0/24
```

> 注意：NAT 模式下宿主机 `ping 192.168.188.1` 通常不通（VMware 虚拟网卡默认屏蔽 ICMP），
> **这是正常的**，用 `ssh` 测试连通性才准。

---

## 四、文件传输

### 共享文件夹（已配置）

| 宿主机路径 | 虚拟机内路径 |
|---|---|
| `F:\DeskTop\IC项目` | `/mnt/hgfs/IC项目` |

**注意**：共享目录是 VMware 的 9p 文件系统，**直接在里面跑 EDA 工具会很慢，且可执行文件可能因权限问题跑不起来**。
正确做法是先复制到虚拟机本地：

```bash
cp -r "/mnt/hgfs/IC项目/xxx" ~/work/
```

### SCP

```bash
scp -r local_dir ICer@<VM_IP>:~/work/
scp -r ICer@<VM_IP>:~/work/xxx ./local_dir
```

---

## 五、已安装的 EDA 工具

全部在 `PATH` 里，直接敲命令即可。

### 数字设计流程（Codex 负责的部分）

| 工具 | 命令 | 版本 | 用途 | 路径 |
|---|---|---|---|---|
| **Design Compiler** | `dc_shell` | O-2018.06-SP1 | 逻辑综合，RTL → 网表 | `/home/synopsys/syn/O-2018.06-SP1/bin/dc_shell` |
| **IC Compiler** | `icc_shell` | O-2018.06-SP1 | 布局布线，网表 → GDS | `/home/synopsys/icc/icc/O-2018.06-SP1/bin/icc_shell` |
| **PrimeTime** | `pt_shell` | O-2018.06-SP1 | 静态时序分析 | `/home/synopsys/pts/O-2018.06-SP1/bin/pt_shell` |
| **Formality** | `fm_shell` | O-2018.06-SP1 | 形式验证，RTL vs 网表等价性 | `/home/synopsys/fm/fm/O-2018.06-SP1/bin/fm_shell` |

### 仿真流程（Claude 负责的部分，勿冲突）

| 工具 | 命令 | 版本 |
|---|---|---|
| VCS | `vcs` | O-2018.09-SP2 |
| Verdi | `verdi` | O-2018.09-SP2 |
| QuestaSim | `vsim` | linux_x86_64 |

### 常用启动方式

```bash
# 交互式
dc_shell -f script.tcl
pt_shell -f script.tcl
fm_shell -f script.tcl
icc_shell -f script.tcl

# 批处理（推荐，不占终端）
dc_shell -f script.tcl -output_log_file dc.log
```

**GUI 需要 X11**，虚拟机有桌面环境，直接在 VMware 窗口里敲命令即可。

---

## 六、License

**已配置好，VCS/Verdi/DC/PT/ICC/FM 都能用。**

license 文件位置：`/opt/synopsys/scl/2024.06/admin/license/syn.license.dat`

> 注意：`/opt/synopsys/` 下那套是之前在 WSL 里装的，和虚拟机里的 `/home/synopsys/` 是**两套独立安装**。
> 虚拟机这套的 license 是好的，直接用。

检查 license 状态：

```bash
lmstat -a 2>&1 | head -30
```

如果提示 `lmstat: command not found`，用完整路径：

```bash
/home/synopsys/scl/*/linux64/bin/lmstat -a 2>&1 | head -30
```

---

## 七、工程位置

| 内容 | 路径 |
|---|---|
| 代码验证工程（Claude 用） | `~/work/des_pipeline_soc_v2/` |
| VCS 回归结果 | `~/work/vcs_regress/` |
| 原始工程（只读，从共享盘拷来） | `~/work/des_pipeline_soc_v2/` |

**数字设计流程建议另建目录**，例如 `~/work/des_dc_flow/`，不要和验证工程混在一起。

---

## 八、资源占用提醒

虚拟机配置：**4 核 CPU / 4.7 GB 内存**。

| 操作 | 资源占用 | 建议 |
|---|---|---|
| VCS 小规模仿真 | 低 | 可以和别的并行 |
| VCS 大规模回归 | 中 | 避免同时跑多个 |
| **DC 综合** | **高** | **独占，别和别的同时跑** |
| **ICC 布局布线** | **很高** | **独占，且耗时长（几十分钟到几小时）** |
| PT 时序分析 | 高 | 独占 |

**协调建议**：Codex 跑综合/PR 时，Claude 这边不要同时跑 VCS 大规模回归，否则会互相拖慢甚至 OOM。

---

## 九、快速自检

在虚拟机里执行，确认环境可用：

```bash
echo "=== 系统 ==="; cat /etc/redhat-release; getenforce 2>/dev/null || echo "selinux disabled"
echo "=== 工具 ==="; for t in vcs verdi vsim dc_shell pt_shell icc_shell fm_shell; do printf "%-10s " $t; which $t 2>/dev/null || echo "缺失"; done
echo "=== 资源 ==="; nproc; free -h | head -2; df -h /home | tail -1
```

---

## 十、已知问题

| 问题 | 现象 | 解决 |
|---|---|---|
| **NetworkManager 全局关闭**（2026-11-03 实测） | 所有网卡“未托管/state 10”、`ens33` 无 IP、ARP 里查不到、SSH 超时 | `sudo nmcli networking on` + `sudo systemctl restart NetworkManager`；查 `cat /var/lib/NetworkManager/NetworkManager.state` 是否为 `NetworkingEnabled=true` |
| SSH 连接被拒 | `Permission denied (publickey,...)` | `sudo setenforce 0`（重启前临时方案） |
| 共享文件夹跑工具报错 | 权限/性能问题 | 先 `cp -r` 到 `~/work/` 再跑 |
| `/opt/synopsys` 那套不能用 | license 签名无效 | **别用那套**，用 `/home/synopsys/` |
| **虚拟机无外网** | `ping 114.114.114.114` 不通、`yum` 失败、无法下载 | 见下方说明 |

### 关于"无外网"

**当前状态（2026-10-31 实测）**：
- 内网通：能 ping 通网关 `192.168.188.2`，SSH 正常
- 外网不通：DNS 超时、`curl` 失败、`yum` 无法访问源

**原因**：宿主机上 `VMware NAT Service` 没在运行（只有 `VMnetDHCP` 在跑）。
在 **Windows 管理员 PowerShell** 里修复：

```powershell
Start-Service "VMware NAT Service"
```

**影响评估**（对数字设计流程）：

| 操作 | 需要外网 |
|---|---|
| 跑 DC / ICC / PT / Formality | ❌ 不需要 |
| 传代码（共享文件夹 / scp） | ❌ 不需要 |
| 装新软件、`yum install` | ✅ 需要 |
| 下载标准单元库 / 工艺库 | ✅ 需要 |

**结论：跑现有流程不受影响，需要装东西时再修 NAT。**
