# Strata 本机补丁

Strata Terminal 以版本化压缩包发布，**升级时整个目录被替换**，本机改动会消失。
这个目录保存这些改动，升级后一条命令重新应用。

## 快速使用

```powershell
cd $env:STRATA_HOME\patches

.\apply.ps1 -Check       # 只报告状态，不改文件（默认）
.\apply.ps1 -Apply       # 应用缺失的补丁
.\apply.ps1 -Revert      # 移除所有补丁，回到上游原始状态
```

指定其它 Terminal 安装位置：

```powershell
.\apply.ps1 -Check -Terminal "<你的 Strata 目录>"
```

退出码：`0` 正常，`1` 需要人工处理，`2` 参数错误。

## 包含的补丁

| ID | 文件 | 作用 |
| --- | --- | --- |
| `gpu-power-module` | `strata_cli/launch/gpu_power.py`（新文件） | `nvidia-smi -pl` 的 UAC 提权封装 |
| `gpu-power-cap` | `strata_cli/launch/runner.py` | `launch` 时限功耗到 `STRATA_GPU_POWER_LIMIT` |
| `gpu-power-restore` | `strata_cli/launch/cmd.py` | `--stop` 时恢复默认功耗 |
| `bare-help` | `strata_cli/cli.py` | 裸敲 `strata` 时显示常用命令 |

**为什么需要这些**：这台机器的 USB 小屏和键盘在 GPU 从待机跳到满载时会断线（6 次实测记录）。
限制功耗能缓解；但 `nvidia-smi -pl` 需要管理员权限，所以加了自动 UAC 提权。

`bare-help` 是独立的体验改进，与硬件问题无关。

## 目录结构

```
patches/
├── apply.ps1            应用/检查/回滚脚本
├── patches.json         补丁清单（锚点、调用点、文件位置）
├── gpu_power.py         新文件的完整内容
├── snippets/
│   ├── runner_cap.py        要插入 runner.py 的函数
│   ├── cmd_restore.py       要插入 cmd.py 的函数
│   └── cli_bare_help.py     要插入 cli.py 的函数
└── README.md            本文件
```

## 设计原则

### 只插入，不改写

补丁**只在函数定义前插入新函数**，并在调用点插入一行调用。
不改动任何已有代码行——这样上游的改动不会和本机补丁纠缠。

### 锚点用精确字符串，不用行号

```json
"insert_before": "def start(self) -> None:",
"insert_after": "        self.check_port_free()",
```

锚点找不到时**明确报错，绝不猜测位置**——插错地方比不插更糟。

### 幂等

每个补丁用 `marker` 识别是否已应用：

```json
"marker": "def _cap_gpu_power(self) -> None:"
```

重复运行 `-Apply` 不会重复插入。

### 三种状态分开报告

| 状态 | 含义 | 怎么办 |
| --- | --- | --- |
| `applied` | 已应用，调用点也在 | 不用管 |
| `not-applied` | 锚点都能找到，可以应用 | 运行 `-Apply` |
| `anchor-missing` | 上游改了这个函数 | **人工处理**（见下） |
| `partial` | 函数在但没人调用 | 可能上次插入不完整 |
| `conflict` | 新文件已存在但内容不同 | 人工确认后再覆盖 |
| `missing-file` | 目标文件不存在 | 上游可能删了这个文件 |

## 升级后怎么办

```powershell
.\apply.ps1 -Check
```

**三种结果，三种处理**：

### 1. 全部 `applied`

升级没碰这些文件，或者你还没升级。无事可做。

### 2. 有 `not-applied`

上游重写了这些文件（正常的版本更新）。直接：

```powershell
.\apply.ps1 -Apply
```

### 3. 有 `anchor-missing`

**这是唯一需要人工判断的情况。** 打开上游新版本对应文件，看是什么变化：

| 情况 | 处理 |
| --- | --- |
| 函数重命名/重构了 | 改 `patches.json` 里的锚点 |
| **上游自己实现了这个功能** | **删掉这个补丁**（这是好事） |
| 文件被拆分了 | 改 `"file"` 字段，重新确认锚点 |

删补丁的方法：从 `patches.json` 的 `patches` 数组里删掉那一项。

**不要为了让补丁"能用"而强行改锚点**——如果上游已经做了同样的事，你的补丁就是多余的。

## 改动内容详解

### `gpu_power.py`（新文件）

完整内容在 `gpu_power.py`。核心是 `ask_for_admin()`：

```python
ps = (f"$p = Start-Process -FilePath 'nvidia-smi' -ArgumentList {quoted} "
      f"-Verb RunAs -Wait -PassThru -WindowStyle Hidden; exit $p.ExitCode")
```

**安全边界**：
- 只执行 `nvidia-smi`（写死在 `EXE` 常量），不执行任意命令
- 参数只接受整数（功耗瓦数、GPU 索引）
- 结果通过**读回**功耗值判断，不看子进程退出码
- 不创建计划任务、不写注册表、不设服务——UAC 取消就什么都没发生

### `runner.py` 的 `_cap_gpu_power()`

插入在 `start()` 里、`check_port_free()` 之后、**引擎加载之前**。
下载和准备阶段不限制功耗，只在真正要跑推理时限制。

### `cmd.py` 的 `_restore_gpu_power()`

在 `_stop_all()` 的 `return 0` 之前调用，确保：
- 无论有没有真停掉服务，只要检测到功耗被限就恢复
- 恢复失败**绝不影响停止命令**（整段包在 try/except 里）

### `cli.py` 的 `_print_bare_help()`

在 `main()` 里 `ap = parser()` 之后拦截"无参数"的情况。

命令列表从 parser 动态读取：

```python
for action in ap._actions:
    if isinstance(action, _SubParsersAction):
        names = list(action.choices)
```

所以上游新增命令时会自动出现，不会过期。

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `STRATA_GPU_POWER_LIMIT` | 限功耗的目标瓦数。未设或 `0` = 完全不管功耗 |

当前设为 `200`（用户级）：

```powershell
[Environment]::GetEnvironmentVariable('STRATA_GPU_POWER_LIMIT','User')
```

## 测试记录

2026-10-26 完整验证：

| 测试 | 结果 |
| --- | --- |
| `-Check` 在当前已打补丁的安装上 | 4/4 `applied` |
| `-Check` 在干净上游副本上 | 4/4 `not-applied` |
| `-Apply` 到干净副本 | 4/4 成功，语法检查通过 |
| **打补丁结果 vs 当前运行版本** | **三个 Python 文件语义完全一致** |
| `-Revert` | 4/4 移除，恢复到上游原始状态 |
| 往返（apply → revert） | 语义与上游逐行一致 |

验证方法：用 `.bak-strata` 作为上游原始文件，打补丁后用 AST 解析确认语法，
再逐行对比（忽略空行和行尾注释）。

## 已知限制

- **不支持部分应用**：任一补丁 `anchor-missing` 时 `-Apply` 拒绝执行，避免半打状态
- **`gpu_power.py` 是覆盖式**：如果目标位置已有同名文件且内容不同，报 `conflict`，不自动覆盖
- **CRLF/LF 处理**：Terminal 文件是 CRLF，snippet 是 LF，脚本会转换
- 补丁内容是**这台机器专用的**（GPU 功耗），不适合提给上游
