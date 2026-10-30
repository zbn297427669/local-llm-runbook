# Strata 快速入门

本机已装好 Strata 0.2.6（engine 0.1.50），模型 Qwen3.8-Flash-Next IQ2_XS，本地推理，无需账号，不需要联网。

文档日期：2026-10-26（最后更新 2026-10-28）。所有命令和数字都在本机实测过。

> **要在重装后的机器上重建环境？** 用 [`../RESTORE.md`](../RESTORE.md)，
> 那份是给 Agent 执行的分步清单；本文是人读的完整手册。

> **路径约定**：`$env:STRATA_HOME`（cmd 里写 `%STRATA_HOME%`）指 Strata 的安装目录，
> 即含 `terminal\`、`models\`、`patches\` 的那一层；示例假定 `D:\llm\Strata`。
> 这个仓库不写死盘符和用户名。

---

## 一、30 秒上手

**用档位脚本选一个上下文长度并启动**（见第八章）：

```powershell
& "$env:STRATA_HOME\strata-preset.ps1"          # 列出档位，问你选哪个
& "$env:STRATA_HOME\strata-preset.ps1" 64k      # 直接起 64K
& "$env:STRATA_HOME\strata-preset.ps1" -Status  # 现在跑的是哪档
& "$env:STRATA_HOME\strata-preset.ps1" -Stop    # 停服 + 恢复 GPU 功耗
```

**或者直接用 `strata` 命令**：

```powershell
strata launch --preset "IQ2_XS 256K" --no-tui  # 启动（推荐档位）
strata launch --status                          # 看状态
strata launch --stop                            # 停止
```

**不限制 GPU 功耗**，显卡以默认 350 W 运行。

去掉 `--no-tui` 会打开终端里的 Monitor 监控界面，按 `q` 退出。

启动后服务地址：`http://127.0.0.1:8080`

> **Windows 提示**：装好后需要**新开一个终端窗口**，`strata` 命令才会在 PATH 里生效。
> 在 Git Bash 里要写成 `strata.cmd`。

**不需要管理员权限。** 功耗限制已撤销，启动过程没有 UAC 弹窗。

---

## 二、装在哪

| 内容 | 路径 | 占用 |
| --- | --- | ---: |
| 程序 + 内置 Python | `$env:STRATA_HOME\terminal` | 0.2 GB |
| 模型 + MTP 草稿层 + 图片读取器 | `$env:STRATA_HOME\models` | 72.1 GB |
| 引擎 0.1.50 | `%LOCALAPPDATA%\Strata` | 1.0 GB |
| 源码克隆（**可删**，不影响运行） | `$env:STRATA_HOME\sourcecode` | 0.1 GB |

`$env:STRATA_HOME\sourcecode` 只是安装时用来读文档和跑硬件检查的，删掉不影响使用。

**为什么引擎留在系统盘？** 实测两块 NVMe：系统盘读 2.4 GB/s，模型盘读 3.1 GB/s。
引擎 838 MB 只在启动时读一次，之后完全不碰，放哪盘对推理速度没有影响。模型 63 GB 是热数据，推理时持续从模型盘读，
所以放在更快的那块盘。参考机器的系统盘也只剩 55 GB，装不下模型。

---

## 三、这台机器跑的是什么

| 项 | 值 |
| --- | --- |
| 模型 | Qwen3.8-Flash-Next **IQ2_XS**（ISTA-DASLab 原版） |
| 参数量 | **1769 亿**（MoE，512 专家 / 每 token 激活 10 个） |
| 量化 | GSQ-RCO 非均匀混合精度 |
| 上下文 | **可选 32K / 64K / 128K / 256K**（见第八章） |
| 显存占用 | 约 **14.8 / 16.0 GiB**（RTX 4080，已优化） |
| 图片输入 | 按档位开关 |
| GPU 功耗 | **350 W 默认**（不做限制） |
| 访问范围 | 仅本机（127.0.0.1），无 API key |
| MTP 草稿层 | 开启（提高生成速度） |

### 当前运行配置快照

**截至 2026-10-26，正在运行的是 256K 档**：

| 参数 | 值 |
| --- | --- |
| `--max-context` | 262144 |
| `--kv` | k8v4 |
| `--kv-resident` | 32768（引擎自动加） |
| `--expert-cache` | 4096 → 4292 槽 |
| `--prefill` | 8192（2026-10-27 从 2048 改；读提示词快 2.25 倍） |
| `--spec` / `--spec-min-p` | 4 / 0.5 |
| GPU 功耗限制 | **无**（350 W 默认） |

模型路径：

```
$env:STRATA_HOME\models\packs\iq2_xs                         (pack)
$env:STRATA_HOME\models\models\IQ2_XS\...-00001-of-00002.gguf (native)
$env:STRATA_HOME\models\models\IQ2_XS\...-00002-of-00002.gguf (ple-gguf)
$env:STRATA_HOME\models\mtp\rt                                (MTP 草稿层)
$env:STRATA_HOME\terminal\0.1.51\data\expert-profile.bin      (专家画像)
```

**所有档位共用的调优参数**（写在预设里，启动自动生效）：

| 参数 | 值 | 作用 |
| --- | --- | --- |
| `--prefill` | **8192** | 提示词分块大小。2048 → 8192 让读提示词从 999 涨到 2089 tok/s（**2.09 倍**） |
| `--expert-cache` | 4096 | 下限；引擎按显存自动扩（实测 4292 → 6295 槽） |

**`--prefill` 实测对比**（8K 提示词，每次 3 轮，带 nonce 避开前缀缓存）：

| `--prefill` | prefill 速度 | 相对 2048 |
| ---: | ---: | ---: |
| 2048 | 998.8 tok/s | 1.00x |
| 4096 | 1,682.7 tok/s | 1.68x |
| **8192** | **2,088.7 tok/s** | **2.09x** |
| 16384 | 2,094.9 tok/s | 2.10x（无额外收益，且不保证 bit-exact） |

显存代价可以忽略：256K 档下专家缓存仍是 4292 槽，显存余量 2820 → 2754 MiB。
prompt 缓冲是**按需借用**的，不常驻。

> 早期把 `--prefill` 压到 2048 是为了省显存，但那是个「调过头」的选择——
> 省下来的显存并不紧张，代价却是读提示词慢一倍。2026-10-27 全部档位改为 8192。
提示词处理变慢（422 → 113 tok/s），但**生成速度基本不变**。

### 已撤销的配置

| 项 | 现状 | 原因 |
| --- | --- | --- |
| `STRATA_GPU_POWER_LIMIT=200` | **已删除** | 13 次掉电证明无效 |
| GPU 功耗限制机制 | 补丁保留，**休眠** | 环境变量为空则不触发 |
| `--pcie-frac 0.35` | 未采用 | 六轮验证与基线无差异 |

### 补丁状态

Terminal 里有四处本机改动，用 `patches\apply.ps1 -Check` 查看：

| 补丁 | 状态 | 说明 |
| --- | --- | --- |
| `gpu-power-module` | 已装 | `gpu_power.py`，UAC 提权封装 |
| `gpu-power-cap` | 已装（休眠） | `runner.py`，读 `STRATA_GPU_POWER_LIMIT` |
| `gpu-power-restore` | 已装（休眠） | `cmd.py`，`--stop` 时恢复 |
| `bare-help` | 已装 | `cli.py`，裸敲 `strata` 显示常用命令 |

**实测速度**（RTX 4080 16GB + i7-13700K + 64GB RAM）：

| 场景 | 生成速度 | 条件 |
| --- | ---: | --- |
| **256K 档，当前配置（短请求）** | **90.5 tok/s** | 含 `--pool-workers 10` |
| 256K 档，内存充裕（仅 decode） | 102–130 tok/s | 空闲 35 GB，6295 槽，命中 90% |
| 256K 档，内存紧张 | 77.5 tok/s | 空闲 1.9 GB，4292 槽，命中 68–86% |
| 256K 档，首次请求 | 52.8 tok/s | 专家缓存还没学到路由 |
| 32K 档，短请求 | 63.7 tok/s | 200 W 限制下测的 |

> **两个数字口径不同**：90.5 是完整请求的 decode 均值（含专家未命中），
> 102–130 是内存充裕时仅 decode 的瞬时峰值。引用时要说清是哪一个。
| 64K 档 | 46.2 tok/s | 200 W 限制下测的 |
| 128K 档（无 vision） | 47.6 tok/s | 200 W 限制下测的 |
| 内存严重吃紧时 | 18.7 tok/s | Chrome + Battle.net + WSL 同时开着 |

**注意条件不同**：32K–128K 的数字是 200 W 限制 + 冷启动测的，被双重拖累。
**256K 在 350 W、预热后达到 77.5 tok/s，这才是这台机器的真实性能。**

详细调优结论见第八章「性能实测与调优结论」。

**速度对空闲内存非常敏感。** 引擎日志：

```
expert arena read unbuffered (2 of 16 probe reads from the file cache;
2.5 GiB available, 36.5 GiB of files)
```

36.5 GB 的专家数据里只有 2.5 GiB 能进文件缓存。其余每次前向都要从模型盘实打实读。
关掉 Chrome、游戏、WSL 等占内存的程序，速度会明显回升。

**为什么内存这么关键？** 16 GB 显存只装得下 8.57 GiB 的专家缓存（6398 个槽），
模型总共 63 GB，剩下的靠文件缓存 + SSD。缓存命中率高就快，被其它程序挤掉就慢。

参考：官方文档在 RTX 5070 上测得 79 tok/s。MTP 草稿接受率实测 79/94（84%）。

---

## 四、API 怎么调

服务同时提供 **OpenAI** 和 **Anthropic** 两种兼容接口。

### OpenAI 格式 — 路径带 `/v1`

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next-iq2_xs","messages":[{"role":"user","content":"你好"}]}'
```

Base URL：`http://127.0.0.1:8080/v1`

### Anthropic 格式 — Base URL 不带 `/v1`

```bash
curl http://127.0.0.1:8080/v1/messages \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next-iq2_xs","max_tokens":100,"messages":[{"role":"user","content":"你好"}]}'
```

Base URL：`http://127.0.0.1:8080`（**末尾不要加 `/v1`**）

**为什么？** Anthropic 客户端自己会往 Base URL 后面拼 `/v1/messages`。
- 写 `http://127.0.0.1:8080` → 实际请求 `/v1/messages` ✅
- 写 `http://127.0.0.1:8080/v1` → 实际请求 `/v1/v1/messages`，服务端做了别名兜底，也能用，但不规范

### 常用端点

| 端点 | 用途 |
| --- | --- |
| `GET /health` | 健康检查，返回 `loaded` 状态 |
| `GET /v1/models` | 列出模型 |
| `POST /v1/chat/completions` | OpenAI 格式对话 |
| `POST /v1/messages` | Anthropic 格式对话 |
| `POST /v1/responses` | OpenAI Responses 格式 |
| `POST /v1/unload` | 卸载模型、释放显存（服务继续跑） |
| `POST /v1/load` | 重新加载模型 |

### ⚠️ 短请求要给足 max_tokens

这个模型**默认开着思考模式**（`xhigh` effort）。`max_tokens` 给小了，token 会全花在推理内容上，正文一个字都不出。

实测：`max_tokens: 30` → 只返回 `thinking`，`stop_reason: "max_tokens"`，没有答案。
给到 100 以上就正常了。

---

## 五、接到 Claude Code

`strata connect claude-code` 会自动生成配置，`--write` 直接写进 `~/.claude/settings.json`（会先备份）。

> 下面这份是**直连本地 8080 的写法**。本机实际走的是 CCR 网关，见本章后面的「通过 CCR 接入」。

```bash
strata connect claude-code          # 只看配置
strata connect claude-code --write  # 写进去
strata connect claude-code --check  # 发一个真实请求+工具调用测试
```

写入的内容（实测输出）：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8080",
    "ANTHROPIC_AUTH_TOKEN": "strata-local",
    "ANTHROPIC_MODEL": "qwen3.8-flash-next-iq2_xs",
    "ANTHROPIC_SMALL_FAST_MODEL": "qwen3.8-flash-next-iq2_xs",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3.8-flash-next-iq2_xs",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3.8-flash-next-iq2_xs",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3.8-flash-next-iq2_xs",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "262144",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096",
    "CLAUDE_CODE_SIMPLE": "1"
  }
}
```

**关键两点**（来自 `strata connect` 的提示）：

1. `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 必须填**实际服务的上下文**。上面写的是 256K 档的 `262144`；用 64K 档就改成 `65536`。不填的话 Claude Code 会按 100K 窗口算，要么永不压缩，要么每轮都压缩。
2. 这里的 token 是你自己服务器校验的，跟 Anthropic 账号无关，不会联网验证。

### 通过 CCR 接入：`ccr-claude` 每次都让你选模型

本机用的是 **CCR 网关**（`127.0.0.1:3456`），模型选择在**启动时**决定。

| 启动方式 | 模型由谁决定 | 影响范围 |
| --- | --- | --- |
| **`ccr-claude`** | ✅ **每次启动弹菜单让你选** | 仅当前进程 |
| `claude`（直接敲） | `~/.claude/settings.json` 的 `ANTHROPIC_MODEL` | 所有直接启动的会话 |

`ccr-claude` 的菜单在满足全部条件时出现（`ccr-claude.ps1:647`）：

```
多个可选模型 + 交互式终端 + 没带 -p/--print + CCR_NO_PICK 未设
```

菜单会显示每个模型的上下文窗口：

```
Models this profile allows - pick one (context window in brackets):
  1) qwen3.8-flash-next-iq2_xs  [~262K]  (current)
  2) deepseek-v4.1-flash        [~1.0M]
  3) ...
```

**选中后会写进 `--settings` 覆盖层**，只作用于当前进程——**不影响其它已开的或新开的会话**。

### 多会话并存的正确用法

本地模型是**串行**的（`parallel=1`），同时只能服务一个请求。所以：

```
终端 A：ccr-claude → 选 XM/qwen3.8-flash-next-iq2_xs   → 走本地，独占
终端 B：ccr-claude → 选 OD/deepseek-v4.1-flash          → 走云端，不受影响
```

**唯一要避免的**：两个终端都选本地模型。那第二个会排队等待——实测并发 3 个请求时，第 3 个会超时。

### 为什么本地只能串行

`DETAILS.md:522`：

> One request at a time unless `"parallel": N` is set.

| 配置 | 上下文 | 并发 | 显存 |
| --- | ---: | ---: | --- |
| **当前** | 256K | **1** | 14.8 / 16 GB |
| `--parallel 2` | 256K | 2 | ❌ KV 翻倍，装不下 |
| `--parallel 2` | 64K | 2 | ✅ 可行，牺牲上下文 |

**上下文和并发数抢同一块显存。** 单会话用满 256K 是本机的正确取舍。

### 其它支持的客户端

`opencode`、`codex`、`omp`、`pi`、`hermes`、`openclaw`。

```bash
strata connect              # 列出全部
strata connect <app> --check --output json   # 测试
```

---

## 六、网络代理（只在下载时需要）

**这台机器的系统代理是关闭的**（`ProxyEnable=0`），但 7890 端口有本地代理在跑。GitHub 和 Hugging Face **直连均失败**，只能走代理。

### 关键结论：日常启动不需要代理

**实测验证**（2026-10-26）：不设任何代理环境变量，`strata launch` 正常启动，全程无网络等待。

原因在代码 `runner.py:693-698`：引擎已安装且版本够新时直接返回，**根本不读更新源**。

```python
if report.get("usable"):
    eng = report["engine"]
    stale = self.stale_engine(eng.get("version"))
    if not stale:
        self.emit("engine", f"Engine {eng['version']} ({eng['backend']}) is installed.", 100)
        return          # ← 不联网
```

### 什么时候才真的需要代理

| 场景 | 需要代理 |
| --- | --- |
| **引擎已装 + 模型已装 + 草稿层已存在** | ❌ **不需要** |
| 首次安装引擎 | ✅ |
| 下载模型 | ✅ |
| 引擎版本过旧需升级 | ✅ |
| DFlash2 草稿层缺失 | ✅ |
| `strata update` | ✅（实测无代理报 `WinError 10060`） |
| **本地推理本身** | ❌ 永不需要 |

### 包装脚本仍保留代理设置

`strata-launch.cmd` 里设了代理，纯粹是为了**将来万一需要更新时不卡住**，不是必需：

```bat
set "HTTPS_PROXY=http://127.0.0.1:7890"
set "HTTP_PROXY=http://127.0.0.1:7890"
```

你在别的终端直接敲 `strata`，日常使用**不需要**手动设这两个变量。

---

## 七、GPU 功耗管理（USB 掉电问题）

### 问题

USB 小屏幕和小键盘在 GPU 满载时会断线。**2026-10-26 实测记录**：

| 时间 | GPU 功耗 | 占用 | 结果 |
| --- | --- | --- | --- |
| 12:26:35 | 132.8 W | 95% | 屏幕**+键盘**断，设备重新枚举 |
| 12:34:47 | 121.1 W | 99% | 屏幕**+键盘**断，设备重新枚举 |
| 12:47:45 | 147.4 W | 99% | 屏幕**+键盘**断，设备重新枚举 |
| 12:58:50 | 173.7 W | 96% | 屏幕闪烁，**键盘正常**（200 W 限制下） |

**判断标准**：键盘断开 = 真故障（USB 链路复位）；只有屏幕闪烁 = 屏幕固件/背光问题，不是故障。

### 已排除的原因

- ❌ **显存不足**：第三次掉电时显存剩 2.3 GB
- ❌ **系统内存不足**：第三次掉电时空闲内存 3.8 GB
- ❌ **PCIe 链路拥塞**：GPU 独占 CPU 直连 x16 Gen4，USB 控制器在 PCH，不共用
- ⚠️ **GPU 功耗阶跃**：三次掉电都发生在 GPU 从低负载跳到 90%+ 的 1–4 秒内（唯一一致的规律）

### 缓解措施：已尝试，但无效

**2026-10-26 的结论：限制 GPU 功耗不能解决问题。**

试过的方案和结果：

| 方案 | 结果 |
| --- | --- |
| 限制到 200 W | 200 W 下记录到 **13 次掉电**，一次没少 |
| 保持 350 W（默认） | 同样掉电 |
| 换 USB 口（Genesys 外置 hub） | 观察中 |

**功耗限制已撤销**：环境变量删除，显卡恢复 350 W 默认值。

### 当前状态：不做任何限制

```powershell
strata launch --preset "IQ2_XS 256K"   # 直接启动，不弹 UAC，不限功耗
```

功耗相关的补丁（`patches/`）**保留了但处于休眠**——环境变量为空就不触发。
如果以后想实验，手动设这个变量即可：

```powershell
$env:STRATA_GPU_POWER_LIMIT = '200'
strata launch --preset "IQ2_XS 256K"
```

### 为什么这些补丁还留着

虽然功耗方案失败了，补丁没删，因为：

1. **零成本**——变量为空时完全跳过，不影响日常使用
2. **可复用**——如果将来换显卡、发现别的功耗相关问题，能直接启用
3. **可回滚**——`patches/apply.ps1 -Revert` 一键移除

### 手动管理（备用）

```powershell
& "$env:STRATA_HOME\gpu-power.ps1" -Status      # 查看当前限制
& "$env:STRATA_HOME\gpu-power.ps1" -Limit 200  # 设为 200 W（弹 UAC）
& "$env:STRATA_HOME\gpu-power.ps1" -Restore    # 恢复 350 W 默认
```

或者直接用 nvidia-smi（管理员）：

```powershell
nvidia-smi -pl 200    # 限制
nvidia-smi -pl 350    # 恢复
```

### 监控脚本

`usb-monitor.ps1` 每 2 秒记录一次，掉电时打 `WATCH` 标记。要监视哪台设备由 `-Devices` 指定
（设备序列号因机器而异，脚本里不预置）：

```powershell
# 不带参数会列出本机的 USB 设备，把 instance id 填进去
& "$env:STRATA_HOME\usb-monitor.ps1"
& "$env:STRATA_HOME\usb-monitor.ps1" -Devices @{ screen = 'USB\VID_1234&PID_5678\A1B2C3' }
```

输出到 `usb-monitor.csv`，字段：

| 字段 | 说明 |
| --- | --- |
| `event` | `tick` 正常 / **`WATCH` = 设备重新枚举** |
| `arrival_<label>` | 各设备的 `LastArrivalDate`，变化即掉电（label 由 `-Devices` 的键决定） |
| `gpu_power_w` / `gpu_util_pct` | 掉电瞬间的功耗和占用 |
| `ram_free_gb` / `strata_ram_gb` | 内存状态 |

停止监控：`Ctrl+C`。

### 对 Strata Terminal 的四处源码改动

| 文件 | 新增 | 作用 |
| --- | --- | --- |
| `strata_cli/launch/gpu_power.py` | **新文件** | `nvidia-smi -pl` 的 UAC 提权封装 |
| `strata_cli/launch/runner.py` | `_cap_gpu_power()` | `launch` 时按环境变量限功耗 |
| `strata_cli/launch/cmd.py` | `_restore_gpu_power()` | `--stop` 时恢复 |
| `strata_cli/cli.py` | `_print_bare_help()` | 裸敲 `strata` 时显示常用命令 |

**行为矩阵**：

| 场景 | `launch` | `stop` |
| --- | --- | --- |
| 非提权 + `STRATA_GPU_POWER_LIMIT=200` | ✅ **弹 UAC，限到 200 W** | ✅ **弹 UAC，恢复 350 W** |
| 提权运行 | ✅ 直接限制，不弹窗 | ✅ 直接恢复，不弹窗 |
| 环境变量未设置 | 静默跳过 | 静默跳过 |
| 功耗已是默认 | 静默跳过 | 静默跳过 |
| UAC 被拒绝 | ⚠️ 提示后不限，服务照常启动 | ⚠️ 提示手动恢复 |

**UAC 提权是怎么做的**（`gpu_power.py`）：

```python
$p = Start-Process -FilePath 'nvidia-smi' -ArgumentList '-pl','200' `
       -Verb RunAs -Wait -PassThru -WindowStyle Hidden
```

安全边界：只执行 `nvidia-smi`（写死在常量里），参数只接受整数，
结果通过**读回功耗值**判断，不建计划任务、不写注册表。

**⚠️ 升级 Terminal 会丢失全部四处改动。** 用 `patches\apply.ps1 -Apply` 重新应用（见下节）。

### 更新机制

**没有自动更新。** 检查结果：

- 无计划任务、无后台服务
- `strata launch` **不会**升级 Terminal 本身
- 只有你手动执行 `strata update` 才会替换 Terminal 文件

当前版本 `0.1.51` 已是最新，引擎 `0.1.50` 也是最新——**没有可用更新**。

### 补丁系统（升级后恢复改动）

四处改动保存在 `$env:STRATA_HOME\patches\`，升级 Terminal 后一条命令恢复。

```powershell
cd $env:STRATA_HOME\patches

.\apply.ps1 -Check    # 只报告状态（默认）
.\apply.ps1 -Apply    # 应用缺失的补丁
.\apply.ps1 -Revert   # 全部移除，回到上游原始
```

**目录结构**：

```
patches/
├── apply.ps1        应用/检查/回滚
├── patches.json     补丁清单（锚点、调用点）
├── gpu_power.py     新文件内容
├── README.md        完整说明
└── snippets/        要插入的三个函数
```

**设计原则**：

| 原则 | 含义 |
| --- | --- |
| 只插入，不改写 | 只在函数定义前插入新函数，不改已有代码行 |
| 锚点用精确字符串 | 不用行号；找不到就报 `anchor-missing`，**绝不猜位置** |
| 幂等 | 用 `marker` 识别，重复 `-Apply` 不会重复插入 |
| 全有或全无 | 任一补丁锚点失效时拒绝执行，避免半打状态 |

**升级后 `-Check` 出现 `anchor-missing` 怎么办**：

| 上游变化 | 处理 |
| --- | --- |
| 函数重构/重命名 | 改 `patches.json` 里的锚点 |
| **上游自己实现了这功能** | **删掉补丁**（这是好事，不是负担） |
| 文件被拆分 | 改 `"file"` 字段 |

**不要为了让补丁能用而强行改锚点。** 如果上游已经做了同样的事，补丁就是多余的。

**验证记录**（2026-10-26）：用 `.bak-strata` 作为上游原始文件，`-Apply` 后
三个 Python 文件与当前运行版本**语义逐行一致**；`-Revert` 后与上游原始逐行一致。

### 还未解决的问题

截至 2026-10-26 19:23，共记录 **15 次**掉电事件。已确认：

| 已排除 | 证据 |
| --- | --- |
| 显存不足 | 掉电时显存剩 2 GB 仍发生 |
| 系统内存不足 | 空闲 9.2 GB 时仍发生 |
| PCIe 拥塞 | GPU 独占 x16，USB 走 PCH |
| GPU 功耗 | 200 W 限制下 13 次掉电 |

**下一步**：换到主板后置 USB 2.0 口（已在 Genesys hub 上观察），若仍无效则指向电源/主板供电问题。

---

## 八、上下文档位（预设）

四档预设已建好，按场景选。**切档要重启服务**（原因见下）。

### 用脚本选（推荐）

**主入口 `strata-preset.ps1`**（有交互菜单）：

```powershell
& "$env:STRATA_HOME\strata-preset.ps1"          # 列出来，问你选哪个
& "$env:STRATA_HOME\strata-preset.ps1" 64k      # 直接起 64K
& "$env:STRATA_HOME\strata-preset.ps1" -Status  # 现在跑的是哪档
& "$env:STRATA_HOME\strata-preset.ps1" -Stop    # 停服 + 恢复 GPU 功耗
```

**备用入口 `strata-launch.cmd`**（纯命令行，PowerShell 脚本受限时可用，双击也行）：

```cmd
%STRATA_HOME%\strata-launch.cmd               默认 64k
%STRATA_HOME%\strata-launch.cmd 32k           指定档位
%STRATA_HOME%\strata-launch.cmd --list        列出预设
%STRATA_HOME%\strata-launch.cmd --plan 128k   预览计划，不启动
%STRATA_HOME%\strata-launch.cmd --status      当前状态
%STRATA_HOME%\strata-launch.cmd --stop        停止
%STRATA_HOME%\strata-launch.cmd -- --model q2_0 --context 32k   透传给 strata launch
```

两者能力对照：

| 能力 | `strata-preset.ps1` | `strata-launch.cmd` |
| --- | :---: | :---: |
| 选档启动 | ✅ | ✅ |
| 交互菜单 | ✅ | ❌ |
| 状态 / 停止 | ✅ | ✅ |
| 列出预设 | （在菜单里） | ✅ `--list` |
| **计划预览** | ❌ | ✅ `--plan` |
| **透传任意参数** | ❌ | ✅ `--` |

两个脚本**共用同一套预设名**，都调用 `strata launch`，功耗管理都由底层命令完成。
切档时自动 `--restart`。**不限制 GPU 功耗**，没有 UAC 弹窗。

> **cmd 脚本必须是 CRLF 换行。** `goto` 标签在 LF 下会报「系统找不到指定的批处理标签」，
> 而标签明明就在文件里。用编辑器改过 `strata-launch.cmd` 后要确认换行符没被改成 LF。

### 四个档位

| 键 | 预设名 | 上下文 | KV | 图片 | 实测生成速度 | 空闲 RAM | 适用 |
| --- | --- | ---: | --- | :---: | ---: | ---: | --- |
| `32k` | IQ2_XS 32K | 32K | int8 | ✅ | **63.7 tok/s** | 4.5 GB | 最快；要读图；同时开别的程序 |
| `64k` | IQ2_XS 64K | 64K | int8 | ✅ | **46.2 tok/s** | 2.9 GB | 平衡；要读图 |
| `128k` | IQ2_XS 128K | 128K | int8 | ❌ | 47.6 tok/s | 2.1 GB | 长文本；精度优先 |
| `256k` | IQ2_XS 256K | **256K** | **k8v4** | ❌ | **77.5 tok/s**（预热后） | 1.9 GB | **模型完整窗口；推荐** |

数据来源：2026-10-26 本机实测，RTX 4080 16GB + 64GB RAM。

**⚠️ 速度数字不可直接横向比较**——它们在不同日期、不同功耗限制下测的：

| 档位 | 测试条件 |
| --- | --- |
| 32k / 64k / 128k | 200 W 限制下，未预热（旧条件） |
| **256k** | **350 W 无限制，预热后，6 轮平均** |

**256K 的 77.5 tok/s 才是这台机器的真实水平。** 之前的 46–48 是功耗限制 + 冷启动双重拖累的结果。

**256K 是本机最优选择**：上下文最大、速度最快、占用最小的专家缓存（4292 槽四档相同）。

### CCR 里只显示一个模型——这是正常的

**架构限制**，不是配置问题：

| 事实 | 实测值 |
| --- | --- |
| Strata `/v1/models` 返回条目数 | **1 个** |
| 模型 id | `qwen3.8-flash-next-iq2_xs`（**不随档位变化**） |
| 窗口（`meta.n_ctx`） | 随当前档位变（256K 档时是 262144） |
| 单个实例显存 | ~14.8 GB，16 GB 卡装不下第二个 |

CCR 按 **id** 索引模型，所以四个档位不会变成四个菜单项——**它们共享同一个 id**。

### 你看到的 `[~262K]` 是正确的

`ccr-claude` 启动时会探测 `/v1/models` 的 `meta.n_ctx`，菜单里显示当前档位的窗口：

```
1) qwen3.8-flash-next-iq2_xs  [~262K]  (current)   ← 256K 档
```

切到 64K 档后重启 `ccr-claude`，会变成 `[~64K]`。

> **注意**：这个显示依赖 `ccr-claude` 的两个修复（已在 PR #1 / #2 合并）：
> 支持 `meta.n_ctx` 字段、修复 `~0.0M` 的格式化 bug。旧版本会显示 `unknown` 或 `~0.0M`。

### 正确的工作流程

```
1. strata-preset.ps1 256k        ← 选档并启动
2. 启动 ccr-claude                ← 探测到当前窗口
```

**顺序不能反**：`ccr-claude` 只在启动时探测一次。先开 ccr-claude 再切档，它显示的窗口是旧的。

### 想在 CCR 里直接切的代价

| 方案 | 做法 | 代价 |
| --- | --- | --- |
| 多端口 | 8080 跑 256K + 8081 跑 32K | **显存不够**（需 29.6 GB） |
| 动态改 id | 让 Strata 按档位报不同模型名 | 改源码 + 清 CCR 缓存 |
| 小模型副本 | 另装一个小模型跑低档位 | 额外 25 GB 磁盘 |

**都不划算。** 切档的频率远低于开 Claude Code 的频率——一天可能切一次档，但要开很多次会话。

### 手动管理预设

```powershell
strata launch --list-presets                              # 列出
strata launch --preset "IQ2_XS 64K" --restart --no-tui    # 切档
strata launch --delete-preset "IQ2_XS 64K"                # 删除
```

**`--restart` 是必须的**——不同档位的上下文不同，不加会被拒绝：

```
strata: A model is already running: ... These choices are different.
        Add --restart to stop it and start these, or run `strata launch --stop` first.
```

### 预设文件在哪

```
%APPDATA%\Strata\launch-presets\
  iq2_xs-32k-fast.json
  iq2_xs-64k.json
  iq2_xs-128k.json
  iq2_xs-128k-vision.json
```

**文件名必须等于 `slug(预设名)`**，不是随便起的。`slug("IQ2_XS 64K")` → `iq2_xs-64k`（保留模型名的下划线）。文件名不匹配时 Strata 报错会自相矛盾：

```
There is no saved preset called 'IQ2_XS 64K'. Did you mean 'IQ2_XS 64K'?
```

### 显存和内存的账

| 项目 | 占用 |
| --- | ---: |
| dense weights | 1475 MiB |
| MTP 草稿层 | 839 MiB |
| draft head | 138 MiB |
| CUDA context | 250 MiB |
| expert cache 4096 槽 | 5899 MiB |
| prefill 缓冲 | **按需借用**，不常驻（见下） |
| **小计（不含 KV）** | **约 8600 MiB** |

> **更正（2026-10-27）**：这里原先列着「prefill 2048 缓冲 1597 MiB」并计入常驻。
> 实测发现 prompt 缓冲是**读提示词时向专家缓存借用**的，引擎日志写的是
> `the prompt path borrows 3215 CUDA0 cache slots (4.30 GiB)`，请求结束后归还。
> 所以 `--prefill` 从 2048 提到 8192，专家槽数**一个没少**（仍 4292），
> 显存余量只从 2820 变成 2754 MiB。

KV 按 int8 **14.1 KiB/token** 算：

| 上下文 | KV 需求 | 说明 |
| --- | ---: | --- |
| 32K | 451 MiB | 全在显存 |
| 64K | 902 MiB | 全在显存 |
| 128K | 1804 MiB | 引擎自动 `kv_resident=32768`，其余进内存 |

128K 时引擎自动启用 KV streaming（前 32K 留显存，其余 96K 放内存），所以专家缓存仍保持 4096 槽不缩水——代价是内存多占约 1.3 GB。

### 想上更高？

模型原生窗口是 **262,144（256K）**，超过需要 `--rope-scaling yarn`。

要在 16 GB 卡上跑 256K，需要组合：

```
--context 256k --kv q4_0 --expert-cache 3072
```

KV 从 14.1 降到 7.7 KiB/token，缓存再让出 2.8 GB。代价：生成速度明显下降，q4_0 精度略低（困惑度 +8~12%）。

**256K 已经实测可行**（k8v4 KV），不需要 q4_0。见下一节。

### 性能实测与调优结论

**2026-10-26 实测，RTX 4080 16GB + i7-13700K + 64GB RAM，350 W 无限制，Chrome/WSL 关闭。**

#### 稳定的真实速度

固定提示词（68 token）+ 固定输出（256 token），预热后 6 轮：

| 配置 | 平均 | 范围 |
| --- | ---: | --- |
| 基线（pcie-frac 0.55） | **76.6 tok/s** | 73.7–79.7 |
| pcie-frac 0.35 | 77.5 tok/s | 73.6–81.4 |

**差异 1.2%，在噪声范围内。`pcie-frac 0.35` 没有实际提升。**

#### 冷启动的影响（"预热"）

| 请求序号 | 解码速度 | 专家缓存命中率 | PCIe 占比 |
| --- | ---: | ---: | ---: |
| **第 1 次** | **52.8** | **75.7%** | **12.4%** |
| 第 2 次 | 61.0 | 83.8% | 7.1% |
| 第 3 次起 | 77.5–79.7 | 81–84% | 5.4–6.9% |

**原因**：引擎有 24,576 个专家对，显存只能装 4,292 个。启动时按 `expert-profile` 预填充（通用分布），前几次请求在**学习实际路由**，命中率 75.7% → 83% 后就稳定了。

**"预热"就是先发一个请求。** 但**不值得专门做**：

- 只影响第一条，之后自动恢复
- 缓存不跨重启，重启后要重新学
- 换话题可能又要适应
- Claude Code 启动本身就有开销，感知不到

#### `strata tune auto` 的结果

```powershell
strata tune auto launch-iq2_xs-256k --mode quick --use coding --time 20 --allow-small-differences
```

13 分钟完成，结论：**「当前设置已经是最快的，没有改动」**。

它试过的候选（都拒绝了）：

| 候选项 | 参数 | 比值 | 拒绝原因 |
| --- | --- | ---: | --- |
| 保留更多对话在显存 | `--kv-resident 65536` | 0.960 | 解码慢 4%，提示词慢 5% |
| PCIe 份额 | `--pcie-frac 0.0 / 0.2 / 0.35` | 1.10 / 1.12 / 1.14 | 三次测量方差大，不可重复 |
| 投机阈值 | `--spec-min-p 0.5 / 0.7` | 1.05 / 0.92 | 未超过噪声 |
| 辅助 CPU | `--aux-cpus 1` | 0.99 | 无提升 |

基线：解码 79.4 tok/s，提示词 1088 tok/s（4K），噪声 1.55%。

**教训**：`pcie-frac 0.35` 单次测出「+20%」是**冷启动污染**造成的假象。调优器要求 3 次都超过噪声，正确地拒绝了它。**相信交叉验证，不信单次测量。**

#### 优化空间还有多少

稳定状态命中率 81–84%，PCIe 占比 5–7%。**这已经接近该配置的上限。**

能做的只剩硬件层面（更大显存、更好显卡），参数调优已经没有空间。

---

## 九、日常操作

```bash
# 启动（后台运行，打印地址后返回）
strata launch --preset "IQ2_XS 256K" --no-tui

# 启动并打开监控界面
strata launch --preset "IQ2_XS 256K"     # 不带 --no-tui 会打开 Monitor

# 看状态（注意：这是交互式界面，按 q 退出）
strata launch --status
strata status

# 停止（同时卸载模型、释放显存）
strata launch --stop
strata launch --stop --preset "IQ2_XS 256K"

# 查看预设
strata launch --list-presets

# 查看日志
strata logs
strata logs --follow

# 只卸载模型，保留服务（腾显存给游戏等）
curl -X POST http://127.0.0.1:8080/v1/unload \
  -H "Content-Type: application/json" -d '{}'

# 检查更新（需要代理）
strata update --check
```

### Monitor 界面

不带 `--no-tui` 启动会进入 Monitor，7 个视图：

`1` Overview · `2` Serving · `3` Requests · `4` Engine · `5` Hardware · `6` Logs · `7` Connect

按 `q` 退出时会问：保持后台服务，还是停止。

### 停止服务的几种方式

| 方式 | 效果 | 建议 |
| --- | --- | --- |
| `strata-preset.ps1 -Stop` | 停服务 + 恢复 GPU 功耗 | ✅ **最完整** |
| `strata launch --stop` | 停进程 + 卸载模型 + 释放显存 | ✅ 推荐（提权时也恢复功耗） |
| Monitor 里按 `q` 选 stop | 同上 | 用 TUI 启动时可用 |
| `POST /v1/unload` | 只卸模型，服务继续跑 | 想临时腾显存时用 |
| `taskkill /PID <pid> /F` | 强杀 | ⚠️ 最后手段，可能留锁文件 |

查 PID：
```bash
netstat -ano | findstr ":8080" | findstr LISTENING
```

> **注意**：用 `--no-tui` 启动后，服务是独立后台进程。**关掉终端窗口不会停止服务**，必须显式 `--stop`。

---

## 十、常见问题

**`strata: command not found`**

新开一个终端窗口。PATH 是安装时写进用户环境变量的，当前窗口读不到。
Git Bash 里用 `strata.cmd`。

**启动卡在 "Reading the signed update feed"**

代理没开。确认 7890 端口可用，或直接用 `strata-launch.cmd`。

**请求返回 415**

`/v1/unload` 这类管理端点必须带 `Content-Type: application/json`。这是防跨站调用的检查。

**请求返回 UTF-8 解码错误**

Windows Git Bash 的 `curl -d '中文'` 会按 GBK 编码发送。改用文件传：

```bash
curl ... --data-binary "@request.json"
```
文件要存成 UTF-8。

**只返回 thinking，没有正文**

`max_tokens` 太小被思考内容吃光了。调大到 100 以上。

**第一次请求慢**

模型要加载，约 30 秒。之后正常。

**显存不够 / 想玩游戏**

```bash
curl -X POST http://127.0.0.1:8080/v1/unload -H "Content-Type: application/json" -d '{}'
```
下次请求会自动重新加载。

---

## 十一、还想装别的模型

源码目录 `$env:STRATA_HOME\sourcecode` 里有完整的模型清单和安装脚本。可选的档位（本机 64GB RAM + 16GB VRAM 均能装）：

| 模型 | 权重 | 内存需求 | 相对速度 | 质量 |
| --- | ---: | ---: | --- | --- |
| Q2_0 | 37.6 GB | ~48 GB | 最快 | good |
| **IQ2_XS**（当前） | 39.2 GB | ~48 GB | 快 | better |
| IQ3_XXS | 47.0 GB | ~60 GB | 较慢 | great |
| IQ3_S | 54.8 GB | ~62 GB | 最慢 | best |
| DeepSeek V4.1-Flash 2.00bpw | 257 GB | 46-64 GB | 约 5-7 tok/s | 大模型 |

```bash
strata launch --family qwen --model iq3_xxs --plan    # 先看计划，不下载
```

DeepSeek 需要约 265 GB 磁盘，参考机器的模型盘当时只剩约 230 GB，**装不下**。

文档：`$env:STRATA_HOME\sourcecode\docs\MODELS.md`

---

## 十二、卸载

```bash
strata launch --stop
```

然后手动删除：

- `$env:STRATA_HOME\terminal`
- `$env:STRATA_HOME\models`
- `%LOCALAPPDATA%\Strata`（引擎，按需留在用户目录）
- `$env:STRATA_HOME\sourcecode`（源码，可选）
- `$env:STRATA_HOME\strata-launch.cmd`、`$env:STRATA_HOME\strata-launch.log`（启动脚本和旧日志）
- `$env:STRATA_HOME\strata-preset.ps1`、`$env:STRATA_HOME\patches\`（档位脚本和补丁）
- 从用户 PATH 里移除 `$env:STRATA_HOME\terminal\current\bin`

---

## 参考

### 本机文件

| 文件 | 用途 |
| --- | --- |
| **`strata-preset.ps1`** | **选上下文档位并启动（推荐入口）** |
| **`patches/apply.ps1`** | **Terminal 升级后恢复本机改动** |
| `patches/README.md` | 补丁系统完整说明 |
| `strata-launch.cmd` | **备用入口**：纯命令行选档，有 `--plan`（预览）和 `--`（透传） |
| `gpu-power.ps1` | GPU 功耗设置工具（`-Limit` / `-Restore` / `-Status`） |
| `gpu-power-flow.ps1` | 功耗流程端到端测试 |
| `usb-monitor.ps1` | USB 掉电监控，输出到 `usb-monitor.csv` |
| `usb-arrivals.ps1` | 列出所有 USB 设备的重枚举时间 |
| `pcie-map.ps1` | 查看 PCIe 拓扑 |
| `STRATA-快速入门.md` | 本文档 |

### 官方文档

`$env:STRATA_HOME\sourcecode\docs\`

- `AI_SETUP.md` — AI 代理安装指南
- `MODELS.md` — 模型清单和内存需求
- `TERMINAL_LAUNCH.md` — `strata launch` 完整参数
- `INSTALL.md` — 安装和存储位置
- `DEEPSEEK41.md` — DeepSeek 模型专页

### 日志

| 日志 | 路径 |
| --- | --- |
| 引擎日志 | `%LOCALAPPDATA%\Strata\launch\iq2_xs-32k.engine.log` |
| 服务日志 | `%LOCALAPPDATA%\Strata\launch\iq2_xs-32k.server.log` |
| USB 监控 | `$env:STRATA_HOME\usb-monitor.csv` |
| 功耗流程测试 | `$env:STRATA_HOME\gpu-power-flow.log` |

### 查看日志

```bash
strata logs
strata logs --follow        # 实时跟踪
```

---

## 变更记录

**2026-10-26**

1. **搬迁**：所有 Strata 文件集中到 `$env:STRATA_HOME\`，源码在 `sourcecode\`
2. **显存优化**：新增 `--prefill 2048` 和 `--expert-cache 4096`，显存 15.8 → 14.0 GiB
   （`--prefill` 后来于 2026-10-27 改为 8192，见下）
3. **GPU 功耗管理**（后已撤销，见第 13 条）：
   - `runner.py` 新增 `_cap_gpu_power()`——`strata launch` 自动限功耗
   - `cmd.py` 新增 `_restore_gpu_power()`——`strata launch --stop` 自动恢复
   - `gpu_power.py` 新增——权限不足时弹 UAC 提权（`Start-Process -Verb RunAs`）
   - 环境变量 `STRATA_GPU_POWER_LIMIT=200` 控制
4. **CLI 改进**：`cli.py` 新增 `_print_bare_help()`——裸敲 `strata` 显示常用命令
5. **USB 掉电排查**：最终记录 15 次事件；显存/内存/PCIe/功耗全部排除；换 USB 口观察中
6. **网络代理结论修正**：日常启动**不需要代理**（实测验证），只有下载/更新时需要
7. **上下文档位**：新增 4 档预设（32K/64K/128K/128K-Vision）+ `strata-preset.ps1` 选择脚本
8. **ccr-claude 修复**（已合并到上游仓库两个 PR）：
   - PR #1：`window_of()` 支持 `meta.n_ctx`——Strata/ninfer ring 构建的窗口字段
   - PR #2：`Format-WindowLabel` 变量名冲突——`$n` 是 `[string]$N`，导致字符串比较，
     所有窗口显示成 `~0.0M`
9. **补丁系统**：`patches/` 目录保存四处 Terminal 改动，升级后 `apply.ps1 -Apply` 一键恢复。
   只插入不改写、锚点精确匹配、幂等、全有或全无。已双向验证（apply/revert 均与目标一致）。
10. **256K 档验证成功**：`--context 256k --kv k8v4`，专家缓存保持 4292 槽不缩水，
    KV streaming 命中率 96.3%，显存反而比 128K 低（14819 vs 14593 MiB 同级别）。
11. **性能实测**：350 W 预热后稳定 **77.5 tok/s**（6 轮，73.6–81.4）。
    之前的 46–48 是 200 W 限制 + 冷启动双重拖累的假象。
12. **`strata tune auto` 结论**：当前配置已是最快。试了 `--kv-resident 65536`（更慢 4%）、
    `pcie-frac`（方差大不可重复）、`spec-min-p`（未超噪声），全部拒绝。
13. **撤销 GPU 功耗限制**：200 W 限制经 13 次掉电事件证明**无效**，已删除环境变量和脚本里的
    自动设限。显卡恢复 350 W 默认。
14. **冷启动现象记录**：首次请求 52.8 tok/s（命中率 75.7%），第 3 次起 77.5（83%）。
    原因是专家缓存需要学习实际路由，只影响第一条请求。

**2026-10-27**

15. **`--prefill` 2048 → 8192**：读 8K 提示词从 **998.8** 涨到 **2088.7 tok/s**（2.09 倍）。
    测了 4096（1.68x）、8192（2.09x）、16384（2.10x，无额外收益），8192 是实际最优。
    显存代价可忽略：prompt 缓冲是按需向专家缓存借用的，256K 档专家槽仍 4292，
    余量只差 66 MiB。四档预设全部更新并验证能启动。
    这是「调过头」的典型——当初为省显存把缓冲压到 2048，但省下的显存并不紧张，
    代价是读提示词慢一倍，而且当时没量这个成本。
16. **几个失败或无效的尝试**：
    - `STRATA_MMQ_DIRECT=1`：引擎明确拒绝，`this build has no pointer-table MMQ`
      （预编译版没有 `-DSTRATA_MMQ_TAB=ON`）。文档说它能加快"读取"，但用不了。
    - `STRATA_EMB_REUSE_ACCOUNT=1`：8192 下 2141 vs 2092（+2.4%，区间不重叠），
      但和 `PREFILL_EQUAL` 叠加反而降到 2082。单独用才有效。
    - `STRATA_PREFILL_EQUAL=1`：2104 vs 2092，在噪声内。
17. **请求形状决定复用率（最重要的一条）**：同样的 37K 上下文、同样的配置，
    - 单条增长的 `user` 消息：复用 **87.8%**，每轮重读 4.5K token，**2.6 s**
    - `user` / `assistant` 交替：复用 **99.9%**，每轮重读 **31** token，**0.3 s**

    **快 8.7 倍。** 原因是引擎识别出后者是"继续上一轮对话"，直接取回完整快照；
    前者被看成"一条不断变长的消息"，只能靠 16K 间隔的 checkpoint 匹配。

    结论：**agent 场景下你已经在享受 99.9% 复用，这块不需要优化。**
    这也说明 `--prefill` 只对首次读长文档有效，对多轮对话几乎无感。

    第一版测试脚本发错了形状（只发一条 user 消息），测出"复用率只有 55%"的假结论，
    还观察到 4 次 `reused_kv_bytes=0`。**是本机测量方法错了，不是引擎的问题。**
18. **`--prefill` 最终改为 `auto`**：`auto` 实测 2219.4 tok/s，比写死 8192 的 2089 更快，
    而且换档时引擎自己按显存余量算，不用维护四份配置。`tune auto` 也只认 `auto` 开头的值。
19. **长上下文 decode 不衰减**（176 次真实请求，取输出 >500 token 的）：

    | 上下文 | 样本 | decode 中位 |
    | --- | ---: | ---: |
    | 32–64K | 40 | 59.5 tok/s |
    | 64–128K | 31 | 56.6 tok/s |
    | 128K+ | 28 | **58.7 tok/s** |

    32K 到 176K 基本平坦。撑着它的是 KV streaming（95.2–97.2% 命中显存）
    和专家缓存自适应（命中率 78.3%→92.2%）。

    **"变慢"只来自首次读取**：56K 会话每轮只读 7K 要 3.3 s，完整重读要 23.3 s，
    170K 完整重读要 173 s。

20. **session files（会话存盘）在启动器下不可用**。引擎支持
    `POST /slots/0?action=save|restore`，理论上重启后能省掉 173 秒。三种传法全失败：
    - 放进预设 `extra` → 进了引擎 args，`strata.exe` 不认识，打印帮助退出
    - `--set slot_save_path=...` → 同样进了 args，同样报错
    - 手工改 run config 顶层字段 → **启动器每次启动重写配置，字段被抹掉**

    绕法是跳过启动器直接跑 `python -m serve.server --slot-save-path DIR`，
    但会失去 `strata launch --stop` 和状态管理。**判断为不值得**：
    只有"每天重启多次 + 每次接同一个长会话"才划算，日常一次启动用一天，173 秒可忽略。

21. **`--conversation-cache-mib 8192`（收益最大的一项）**：真实流量里 **42% 的请求
    完全没复用**（102/244），累计重读 138.6 分钟。根因不是"改写历史"，是
    **两个会话在交替**——一个约 180K、一个约 54K，每次切换都挤掉对方的 checkpoint。

    引擎默认会自动计算，但算出来是 0（关闭）：33 GiB 专家 arena 加载后只剩 4.6 GiB
    空闲，`(4710-2560)×0.4 = 860 MiB` 低于 1024 阈值。

    四种配置实测（两会话交替）：

    | 方案 | 预算 | 命中 |
    | --- | ---: | ---: |
    | 默认 auto | 0（关闭） | **0/8** |
    | auto + floor 1024 | 1536 MiB | 8/8 |
    | 固定 4096 | 4096 MiB | 8/8 |
    | **固定 8192** | **8192 MiB** | **8/8** |

    按真实尺寸（180K 每 token 23.3 KiB + 54K 每 token 31.9 KiB）合计需 **5.64 GiB**，
    所以 1536 MiB 的自动值差 3.7 倍，必须用固定 8192。真实尺寸实测 4/4 全命中，
    每轮从 36 秒降到 0.7 秒。**四档预设全部已加。**

    注意：这是**上限不是预分配**，引擎只在停放会话时按需占用，启动时不会吃掉 8 GiB。

22. **不加并发限制**：Strata 默认 `"parallel": 1`，本来就只跑一个请求。
    `--max-queue 0` 只会让后来的请求早点 429，不会让任何请求变快。
    真正的收益在上面第 21 条（两个会话各自 99.9% 复用）。
    如果 Claude Code 起了 subagent，限制并发反而会让子 agent 失败。

23. **`--conversation-cache-min-tokens` 是错误的方向（已撤）**：担心「短请求挤掉长会话」
    而加的阈值，实测反而有害：

    | 配置 | 长会话 | 短会话 | 浪费 |
    | --- | ---: | ---: | ---: |
    | 8192（不加阈值） | 99.9% | **99.9%** | **0 s** |
    | +min-tokens 8000 | 99.6% | **0%** | 4.1 s |
    | +min-tokens 20000 | 99.9% | **0%** | 9.1 s |

    实测峰值只用到 2.7 GiB，8 GiB 绰绰有余，LRU 本来就会保住常用会话，
    「短请求挤掉长会话」没有发生。**为一个不存在的问题引入有害参数。**

24. **两个 slot 概念别混**：`--batch N` / `--slots N` 是**同时解码**的请求数（真并行，
    需要多份显存）；`--conversation-cache-slots N` 是能**记住**的会话数（只是停放，
    任意时刻仍只跑一个）。16 GB 卡装不下两个并行的 180K 会话。


25. **实用建议**：与其追求重启后恢复，不如少重启——
    别在档位间来回切（每次 `--restart` 都清空 checkpoint）、固定用 256K 一档。

26. **`--pool-workers 10`：默认的 15 会让整个 Windows 界面卡死**（2026-10-28）：
    症状是一跑本地模型，打字、移动光标、滚动全部卡住，但内存还有 7.2 GiB 空闲。
    根因不是内存，是 **CPU 调度饥饿**——引擎默认按物理核数（16）分配 worker，
    占满 16 个逻辑核且全是 Normal 优先级，键盘和渲染线程排在队尾。

    实测：CPU 运行队列从 0 涨到 **131.7**，普通线程延迟 0.1 ms → **186.9 ms**（1771 倍）。

    扫描 4/6/8/10/12/15 个 worker：decode 都在 82.8-91.8（噪声内），
    唯一断崖是队列——12 个是 3.3，15 个是 **46.7**。
    **减少 worker 反而让 decode 快了 6%**（85.5 → 90.5）。

    四档预设都设成 10：队列 2.0，decode 90.5 tok/s。

    > 判据：**内存有余量但界面卡 → 查 `\System\Processor Queue Length`，不要查内存。**

27. **思考预算是最大的单项变量：`reasoning_effort: medium` 快 5.4 倍且结构更好**
    （2026-10-28，六组对照）。一次默认请求输出 27,959 token，其中代码只占 15%、
    思考占 85%——5 分半里有 4.5 分钟在「想」。

    | 配置 | 耗时 | 代码字符 | 函数数 | 动画相位 | 近/远端建模 |
    | --- | ---: | ---: | ---: | ---: | :---: |
    | **medium** | **57.4 s** | 8,231 | 7 | 3 | **✅** |
    | none | 37.4 s | 9,794 | 9 | **0** | ❌ |
    | budget 2048 | 68.7 s | 10,668 | 9 | 4 | ❌ |
    | budget 4096 | 87.5 s | 9,174 | 8 | 3 | ❌ |
    | budget 8192 | 126.1 s | 8,257 | 6 | 3 | ❌ |
    | default/high | 311.7 s | 7,925 | 4 | 3 | ❌ |

    `medium` 是唯一带「近/远端踏板建模」的（说明真的在规划动画）；`none` 函数最多
    但动画相位为 0（静态构图加整体位移）。**思考越多，代码反而越短、结构越弱。**

    建议：生成类任务用 `medium`；调试/分析保留 default；一次性原型用 `none`。

    **怎么用**：Claude Code 每次请求都带 `output_config.effort`（实测 1498/1498），
    所以直接敲 `/effort medium` 就生效。两条自动化尝试都失败了：
    - 服务端 run config 写 `reasoning_effort`：被请求里的 output_config 覆盖，实测无效
      （204.8 秒、4.7 万字符思考，完全是 high 的行为）
    - `MAX_THINKING_TOKENS` 环境变量：只对 Opus 4.6 / Sonnet 4.6 有效，且发的是
      `budget_tokens` 而不是 effort。而 budget 4096 实测 87.5 秒，比 medium 的
      57.4 秒慢 34%

    **结论：每次开本地会话手动敲一次 `/effort medium`，没有更好的自动化办法。**

    > 自我更正：曾从单次样本得出「关思考代码更多」，重复测后发现是随机波动
    > （同配置两次差 24%）。唯一稳定的大差异是速度。
