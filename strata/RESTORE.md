# 环境恢复手册（给 Agent 用）

**目标**：在一台重装过的机器上，把本地 AI 环境恢复到当前可用的调优状态。

**使用者是 Agent**，不是人。所以本文按「可执行、可验证」写：每一步都有
确切的命令、预期输出、以及失败时怎么判断。

- 目标机器：Windows 11，RTX 4080 16 GB，i7-13700K，64 GB DDR5
- 首次建成的日期：2026-10-26；最后验证：2026-10-28
- 总耗时估计：下载 40–60 分钟（73 GB），配置 20 分钟

**路径约定**（全文通用）：`$env:STRATA_HOME` 指 **Strata 的安装目录**，即含
`terminal\`、`models\`、`patches\` 的那一层；cmd 批处理里写 `%STRATA_HOME%`。
下文示例假定它是 `D:\llm\Strata`，你的可以完全不同——**先设一次**：

```powershell
$env:STRATA_HOME = 'D:\llm\Strata'    # 换成你的路径
# 想长期生效（新开的终端也认）：
[Environment]::SetEnvironmentVariable('STRATA_HOME', $env:STRATA_HOME, 'User')
```

---

## 0. 先读这一段

如果你只记得三件事：

1. **所有 Strata 文件放同一个非系统盘**，用户 PATH 里只加一个入口。模型 73 GB，别放系统盘。
2. **四项调优参数缺一不可**（第 4 步），它们各有独立收益，不是可选装饰。
3. **`/effort medium` 是最大的单项提升（5.4 倍）**，但它必须每次会话手动设，
   写配置里无效（原因见 5.2）。

---

## 1. 前置检查

在开始前确认这些，任何一条不满足就先解决：

```powershell
# GPU 与驱动
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
# 期望：NVIDIA GeForce RTX 4080, 16376 MiB, 驱动 580+

# 磁盘：模型盘至少 100 GB 可用（模型 73 GB + 余量）
Get-PSDrive (Split-Path $env:STRATA_HOME -Qualifier) | Select-Object Used,Free

# 内存：至少 64 GB
(Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1MB
```

| 项 | 最低 | 本机 |
| --- | ---: | ---: |
| GPU 显存 | 16 GB | 16 GB |
| 磁盘（模型盘） | 100 GB 可用 | — |
| 内存 | 64 GB | 64 GB |

**驱动不需要装 CUDA Toolkit。** Strata 的预编译引擎自带 CUDA 运行时。

---

## 2. 目录布局（照这个结构）

```
$env:STRATA_HOME\                ← 示例里是 D:\llm\Strata
├── terminal\0.1.51\           Strata Terminal（自带 Python 3.12）
├── terminal\current → 0.1.51  junction，升级后不用改脚本
├── models\                    73 GB
│   ├── models\IQ2_XS\         两个 GGUF 分片
│   ├── mtp\                   MTP 草稿层
│   └── packs\iq2_xs\          打包后的 dense 权重 + tokenizer
├── patches\                   四个本机补丁 + apply.ps1
├── strata-preset.ps1          主入口
├── strata-launch.cmd          备用入口（cmd.exe，需 CRLF 换行）
└── STRATA-快速入门.md          完整手册
```

**为什么单独放一块盘**：模型 73 GB，系统盘通常放不下。引擎组件仍在
`%LOCALAPPDATA%\Strata\components\`（引擎本体约 200 MB，这个位置是 Strata
自己决定的，不用改）。

---

## 3. 安装 Strata

### 3.1 下载安装器

从 <https://github.com/Niko1221/Strata/releases> 取最新版（本机是 0.2.6，
Terminal 0.1.51，engine 0.1.50）。

**安装时把数据目录指到 `$env:STRATA_HOME`。** 安装器会问，或者用参数：

```powershell
# 安装器把 Terminal 放到 $env:STRATA_HOME\terminal\<版本>\
# 数据目录（模型）放到 $env:STRATA_HOME\models\
```

### 3.2 验证安装

```powershell
& "$env:STRATA_HOME\terminal\current\bin\strata.cmd" --version
```

**预期**：打印版本号，无错误。

### 3.3 加 PATH（只加这一条）

```powershell
# 已有则跳过；用在 cmd / PowerShell 里直接敲 strata
$p = [Environment]::GetEnvironmentVariable('Path','User')
if ($p -notlike '*Strata\terminal\current\bin*') {
    [Environment]::SetEnvironmentVariable('Path', "$p;$env:STRATA_HOME\terminal\current\bin", 'User')
}
```

> **注意**：Git Bash 里 `strata` 不可用，因为那是另一套 PATH。
> 在 Git Bash 里要写全路径。

---

## 4. 关键：四项调优参数

**这四项是本机实测调出来的，缺一项就退回未优化状态。**

### 4.1 四个预设（必须逐个写入）

预设存放在 `%APPDATA%\Strata\launch-presets\`，文件名必须是
`iq2_xs-<档位>.json`（`slug()` 保留模型名的下划线，写成 `iq2-xs-64k.json` 会找不到）。

**一次性生成四档的脚本**（在 PowerShell 里跑）：

```powershell
$dir = Join-Path $env:APPDATA 'Strata\launch-presets'
$common = [ordered]@{
    '--expert-cache'          = '4096'
    '--prefill'               = 'auto'
    '--conversation-cache-mib'= '8192'
    '--pool-workers'          = '10'
}
$modelsPath = Join-Path $env:STRATA_HOME 'models'
$tiers = @(
    @{ key='32k';  ctx=32768;  kv='int8'; vision='cpu' }
    @{ key='64k';  ctx=65536;  kv='int8'; vision='cpu' }
    @{ key='128k'; ctx=131072; kv='int8'; vision='off' }
    @{ key='256k'; ctx=262144; kv='k8v4'; vision='off' }
)
foreach ($t in $tiers) {
    $obj = [ordered]@{
        access='local'; api_key=$null; context=$t.ctx; data_dir=$modelsPath
        drafting=$null; dsv41_package=$null; extra=$common
        family='qwen'; gpu_roles=$null; gpus=$null; kv=$t.kv
        model='IQ2_XS'; model_path=$null; mtp=$null
        name="IQ2_XS $($t.key.ToUpper())"; no_key=$false
        parallel=$null; port=8080; schema='strata.launch/1'
        speed=$null; tune='skip'; tune_allow_small=$false
        tuned_at=$null; tuned_preset=$null; vision=$t.vision
    }
    $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dir "iq2_xs-$($t.key).json") -Encoding utf8
}
```

> 上面这段脚本已实测：生成的四份预设与当前环境逐字段一致
> （`access` 必须是字符串 `'local'`，不是布尔值）。
> `Set-Content -Encoding utf8` 会写入 UTF-8 BOM——**实测 Strata 能正常读取**，
> 不用特意去掉。

**为什么是这四个值**（每一项都有实测依据，不是抄来的默认值）：

| 参数 | 值 | 收益 | 依据 |
| --- | --- | --- | --- |
| `--expert-cache` | `4096` | 显存 15.8 → 14.0 GiB | 这是**下限**，引擎会自己扩到 4292 或 6295 槽 |
| `--prefill` | `auto` | 读提示词 **2.09 倍** | 写死 2048 时 999 tok/s，auto 时 2089；auto 反而比写死 8192 还快（2219） |
| `--conversation-cache-mib` | `8192` | 多会话复用 **0/8 → 8/8** | 默认自动算出 0（关闭），因为 33 GiB arena 加载后只剩 4.6 GiB |
| `--pool-workers` | `10` | **界面不卡死**，decode +6% | 默认 15 个把 CPU 队列推到 131.7，键盘输入延后 186 ms |

**不要改成别的值**，除非重新做一遍测量。特别提醒两个曾试过且有害的：

- `--prefill 2048`：读提示词慢一倍。这是早期为省显存定的，属于调过头。
- `--conversation-cache-min-tokens`：加上后短会话**完全失去缓存**，反而更慢。

### 4.2 验证参数生效

```powershell
& "$env:STRATA_HOME\strata-preset.ps1" 256k

# 等它打印 "Strata is serving"，然后：
$log = "$env:LOCALAPPDATA\Strata\launch\iq2_xs-256k.engine.log"
Select-String -Path $log -Pattern 'engine started:' | Select-Object -Last 1 |
    ForEach-Object { $_.Line } |
    Select-String -Pattern '--prefill (\S+)|--expert-cache (\d+)|--conversation-cache-mib (\d+)|--pool-workers (\d+)' -AllMatches |
    ForEach-Object { $_.Matches.Value }
```

**必须看到四行**：`--prefill auto`、`--expert-cache 4096`、
`--conversation-cache-mib 8192`、`--pool-workers 10`。

同时确认 worker 数：

```powershell
Select-String -Path $log -Pattern 'pool workers on logical processors' | Select-Object -Last 1
# 期望：10 pool workers on logical processors 2,4,6,...
```

---

## 5. Claude Code 接入

### 5.1 两个入口脚本

| 文件 | 作用 |
| --- | --- |
| `$env:STRATA_HOME\strata-preset.ps1` | **主入口**，选档启动 |
| `$env:STRATA_HOME\strata-launch.cmd` | 备用入口，cmd.exe 可用 |

`strata-launch.cmd` **必须用 CRLF 换行**，用 LF 时 `goto` 会报
「系统找不到指定的批处理标签」。用编辑器改过之后要重新确认：

```powershell
$bytes = [IO.File]::ReadAllBytes("$env:STRATA_HOME\strata-launch.cmd")
if ($bytes -match 10 -and -not ($bytes -match 13)) { 'LF — 需要转 CRLF' }
```

### 5.2 用 `/effort medium`（重要，容易被忽略）

**这是单项收益最大的一步：5.4 倍。**

本地模型默认按 `high` 思考，一次请求 85% 的输出 token 是思考内容。
改成 `medium` 后：311 秒 → 57 秒，而且代码结构更好。

```
每次开本地模型的会话后，敲一次：
/effort medium
```

**为什么不能写进配置**（两条路都验证过，无效）：

| 尝试 | 结果 |
| --- | --- |
| run config 写 `"reasoning_effort": "medium"` | ❌ 实测 204.8 秒，仍是 high 行为 |
| `MAX_THINKING_TOKENS` 环境变量 | ❌ 只对 Opus 4.6/Sonnet 4.6 生效，且发 `budget_tokens` 而非 `effort` |

原因：`serve/server.py` 只在请求不带 `output_config` 时才用配置默认值，
而 Claude Code **1498/1498 个请求都带**（`output_config.effort = "high"`）。

**换回云端模型时可以 `/effort high` 恢复。**

### 5.3 ccr-claude（可选）

如果要用 Claude Code 接入本地模型：

```powershell
& '<你的 ccr-claude 目录>\windows\ccr-claude.ps1'
```

它从 CCR 的配置里读 provider 和 key，脚本本身不含密钥。
CCR 的本地 provider 指向 `http://127.0.0.1:8080`。

---

## 6. 本机补丁（四个）

Terminal 的四个本机改动，用 `patches\apply.ps1` 管理：

```powershell
& "$env:STRATA_HOME\patches\apply.ps1" -Check    # 看状态
& "$env:STRATA_HOME\patches\apply.ps1" -Apply    # 打补丁
& "$env:STRATA_HOME\patches\apply.ps1" -Revert   # 撤销
```

| 补丁 | 状态 | 作用 | 现在是否起作用 |
| --- | --- | --- | --- |
| `gpu-power-module` | applied | 新增 `gpu_power.py`，UAC 提权封装 | 见下 |
| `gpu-power-cap` | applied | `runner.py` 读 `STRATA_GPU_POWER_LIMIT` 限功耗 | **休眠** |
| `gpu-power-restore` | applied | `cmd.py` 在 `--stop` 时恢复 | **休眠** |
| `bare-help` | applied | 裸敲 `strata` 显示常用命令 | ✅ 生效 |

**关于 GPU 功耗补丁**：它是为解决 USB 掉电问题写的，后来证明**无效**
（200 W 限制下仍然掉电 13 次）。现在环境变量不设，补丁不触发。

**恢复时不需要重新启用功耗限制。** 只跑 `-Apply` 让 `bare-help` 生效即可；
其余三个留着无害（不设变量就不动作）。

> **`strata update` 会覆盖 Terminal 的 Python 文件**，补丁需重打。
> 更新后跑一次 `apply.ps1 -Check` 确认。

---

## 7. 逐项验证

装完后按顺序跑这四条，全过才算完成。

### 7.1 服务能起、参数正确

```powershell
& "$env:STRATA_HOME\strata-preset.ps1" 256k
curl.exe -sS --noproxy '*' http://127.0.0.1:8080/health
```

**期望**：

```json
{"status":"ok","max_context":262144,"loaded":true,...}
```

### 7.2 prefill 速度（应约 2000 tok/s）

脚本在本项目的 `scripts/` 下，先把仓库克隆到任意位置：

```powershell
git clone https://github.com/<owner>/local-llm-runbook.git
cd <仓库路径>\strata\scripts

python -I bench-prefill.py 8080 8000 3
```

**期望**：`prefill median` 在 **1900–2300 tok/s**。
若只有 900–1100，说明 `--prefill` 没生效。

### 7.3 decode 速度（应约 90 tok/s）

```powershell
python -I bench-ui-lag.py "verify" 8080
```

它同时报 decode 速度、CPU 队列、调度延迟。

**期望**：

| 指标 | 期望值 |
| --- | ---: |
| decode | **85–95 tok/s** |
| 忙碌时 CPU 队列 | **< 5** |

若 decode 只有 60–70，或队列超过 50，见第 8 节的排查表。

### 7.4 界面不卡（关键）

跑 7.2 的同一时刻，试着在记事本里打字。

```powershell
(Get-Counter '\System\Processor Queue Length' -SampleInterval 1 -MaxSamples 3).CounterSamples.CookedValue
```

**期望**：队列 **< 5**。
若超过 50，说明 `--pool-workers` 没生效（会卡到没法打字）。

---

## 8. 常见失败与判断

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `There is no saved preset called 'IQ2_XS 64K'. Did you mean 'IQ2_XS 64K'?` | 预设文件名用了 `iq2-xs-64k.json` | 改回 `iq2_xs-64k.json`（下划线） |
| `strata` 在 Git Bash 里找不到 | Git Bash 用另一套 PATH | 写全路径 `terminal/current/bin/strata.cmd` |
| 启动失败且日志显示 `unrecognized arguments` | 参数放错了位置 | 引擎参数进预设的 `extra`，服务端参数（如 `slot_save_path`）进 run config 顶层 |
| 打字时界面卡死 | `--pool-workers` 没设或设成 15 | 改 10，见 4.1 |
| decode 只有 60–70 | `--pool-workers` 过高，或内存紧张 | 先查队列，再查空闲内存 |
| 思考特别长（几万字） | 没设 `/effort medium` | 见 5.2 |
| 第二个会话每次重读全文 | `--conversation-cache-mib` 未生效 | 查日志有没有 `conversation cache off` |
| 模型加载报 `cudaMalloc failed` | 显存不够 | 确认没有别的程序占显存；`--expert-cache` 降不到 4096 以下就不该再降 |

---

## 9. 不要做的事

这些是踩过的坑，直接跳过：

| 不要 | 原因 |
| --- | --- |
| 装 CUDA Toolkit | 预编译引擎自带运行时，不需要 |
| 开 `STRATA_MMQ_DIRECT=1` | 预编译版没有 `STRATA_MMQ_TAB`，引擎会拒绝 |
| 手动开 `STRATA_ATTN_DAILY` 等内核开关 | sm_89 不在架构优化表里，实测 +1% 在噪声内 |
| 加 `--conversation-cache-min-tokens` | 会让短会话完全失去缓存，更慢 |
| 加 `--max-queue 0` | 引擎本来就只跑一个请求，限制只会让后来的早点失败 |
| 试图用 session files（存盘恢复） | 启动器每次重写 run config，字段被抹掉 |
| 改 GPU 功耗限制 | 对 USB 掉电无效（13 次实测） |
| 用 `--prefill 2048` 省显存 | 省下的显存不紧张，代价是读提示词慢一倍 |

---

## 10. 卸载/回滚

```powershell
# 停服务
& "$env:STRATA_HOME\strata-preset.ps1" -Stop

# 撤销 Terminal 补丁（想保留 clean 状态时）
& "$env:STRATA_HOME\patches\apply.ps1" -Revert

# 完全删除：删目录 + 清 PATH
Remove-Item -Recurse -Force $env:STRATA_HOME
$p = [Environment]::GetEnvironmentVariable('Path','User') -replace ';[^;]*Strata\\terminal\\current\\bin',''
[Environment]::SetEnvironmentVariable('Path', $p, 'User')
```

---

## 附：当前环境状态快照

供核对用，不是要照抄的内容。

| 项 | 值 |
| --- | --- |
| Strata | 0.2.6 |
| Terminal | 0.1.51（commit `562a0c2e`） |
| Engine | 0.1.50（`1aff6d14`，CUDA 13.0，archs 75/86/89/120） |
| 模型 | Qwen3.8-Flash-Next IQ2_XS（GSQ-RCO，2.3125 bpw） |
| 模型大小 | 63.34 GiB 文件 / 73 GB 目录 |
| 参数量 | 176.94 B |
| 上下文 | 262,144（原生） |
| 显存占用 | 13.7 GB / 16 GB |
| 内存占用 | 34 GB 常驻 / 51.6 GB 承诺 |
| 端口 | 8080（本地） |

**PATH 里的三条**（用户级）：

```
<ccr-claude>\windows
<ccr-claude>
$env:STRATA_HOME\terminal\current\bin
```
