---
name: strata-tune
description: 把任意一台符合基本要求的机器上的 Strata 配置调到接近最优。按"请求参数 → 系统调度 → 缓存策略 → 引擎参数"的顺序排查，每步有量化判据。适用于用户抱怨"本地模型慢/卡/不如在线"、或要求"优化本地 AI 配置"时。
user_invocable: true
---

# Strata 自动调优

## 这个 Skill 解决什么

用户有了可用的 Strata 环境，但嫌慢、卡、或者体感远不如在线 API。
本 Skill 按一个**不会漏掉整类可能性**的顺序排查，每步有量化判据。

**它不提供固定答案**，因为每台机器的瓶颈不同。它提供的是搜索顺序和判据。

---

## 前置检查（不满足就停下）

| 项 | 要求 | 怎么查 |
| --- | --- | --- |
| 框架 | Strata | `strata --version` |
| GPU | NVIDIA，≥ 12 GB | `nvidia-smi --query-gpu=name,memory.total --format=csv` |
| 平台 | Windows 或 Linux | — |

**不适用**：AMD 卡、≤ 8 GB 显存、llama.cpp / Ollama / vLLM 等其它框架。

---

## 铁律（违反任何一条，结论就不可信）

1. **先测基线，再动任何参数。** 没有基线无法判断收益真假。
2. **至少 3 轮，交错测（A B A B），第一轮当预热丢弃。**
   成块测（A A A B B B）会把机器漂移全部算到最后那组头上。
3. **结论要建立在区间不重叠上。** 本机基线在半小时内能漂 30%。
4. **验收用端到端速度**（输出 token / 墙钟秒数），不是 decode 速度。
   用户体感对应的是端到端。
5. **区分三个指标，别混用**：decode tok/s、prefill tok/s、端到端 tok/s。

> 这些不是空话。本机调优时**三次**把噪声当成了收益：
> `ATTN_DAILY` 3 轮 +7.5%、6 轮回落到 +1.0%；单次样本"代码更多"重复测差 24%。

---

## 阶段 0：采集基线（必须）

```bash
# 版本与硬件
strata --version
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv

# 服务能起
strata launch --preset "<任一档位>"
curl http://127.0.0.1:8080/health
```

**测三个速度指标**（各 3 轮，取中位）：

| 指标 | 怎么测 | 读哪个字段 |
| --- | --- | --- |
| prefill | 发一个 8K token 的提示词 | `timings.prompt_per_second` |
| decode | 发一个 300 token 的请求 | `timings.predicted_per_second` |
| 端到端 | 同上 | `usage.completion_tokens / 墙钟秒数` |

**测系统健康**：

```powershell
# Windows
(Get-Counter '\System\Processor Queue Length' -SampleInterval 1 -MaxSamples 3).CounterSamples.CookedValue
(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
```
```bash
# Linux
cat /proc/loadavg
free -g
```

**填完这张表再继续**：

| 指标 | 基线 |
| --- | ---: |
| prefill tok/s | |
| decode tok/s | |
| 端到端 tok/s | |
| CPU 队列 | |
| 空闲内存 GB | |

---

## 阶段 1：请求参数（最高优先级，零成本）

**不改任何配置，只改请求。本机实测这一阶段贡献了 5.4 倍——是所有阶段里最大的。**

### 1.1 先测思考占比

发一个生成类任务（如"写一个单文件 HTML 画一只骑车的鹈鹕"），`max_tokens` 给大。
读响应：

```
usage.completion_tokens         总输出
message.reasoning_content       思考部分
message.content                 正文部分
```

| 思考字符占比 | 诊断 |
| --- | --- |
| **> 70%** | **思考过重——这是最大的优化点** |
| 30–70% | 有空间 |
| < 30% | 跳过本阶段 |

本机实测：默认配置 **85% 是思考**，正文代码只占 15%。

### 1.2 按任务选档位

| 档位 | 适用于 | 本机实测耗时 | 结构质量 |
| --- | --- | ---: | --- |
| `medium` | **生成类任务**（代码、画图、文档） | **57.4 s** | **最好** |
| `none` | 一次性原型 | 37.4 s | 无动画分层 |
| `high`（默认） | 调试 / 分析 / 数学 | 311.7 s | 比 medium 差 |

### 1.3 怎么传

| 场景 | 做法 |
| --- | --- |
| **Claude Code** | 让用户手动敲 `/effort medium` |
| 直接调 OpenAI 协议 | 请求体加 `"reasoning_effort": "medium"` |
| Anthropic 协议 | `"output_config": {"effort": "medium"}` |

> **不要在服务端配置上浪费时间是重要提醒。** `serve/server.py` 的逻辑是：
>
> ```python
> elif not req.get("thinking") and not req.get("output_config"):
>     req["output_config"] = {"effort": effort}
> ```
>
> 客户端只要带了 `output_config`（Claude Code 100% 都带），配置就被覆盖。
> 本机实测：config 写 `reasoning_effort: medium`，仍是 204.8 秒的 high 行为。
>
> `MAX_THINKING_TOKENS` 环境变量也不行：只对 Opus 4.6 / Sonnet 4.6 生效，
> 且发的是 `budget_tokens` 而非 `effort`（budget 4096 实测 87.5 秒，
> 比 medium 的 57.4 秒慢 34%）。

### 1.4 检查请求形状

```bash
grep "prompt .* tokens = .* reused" <engine.log> | tail -20
```

| 复用率 | 诊断 |
| --- | --- |
| > 95% | 正常 |
| 50–95% | 部分失效，看阶段 3 |
| **< 50% 且成串** | **请求形状问题** |

**规则**：`user` / `assistant` 交替的 messages 复用 99.9%；
单条不断增长的 `user` 消息只有 87.8%。**差 8.7 倍。**

---

## 阶段 2：系统调度（可用性问题，1 分钟）

**这一步解决的不是速度，是"机器还能不能正常用"。**

### 判据

在推理进行时试打字。卡的话：

| CPU 队列 | 诊断 |
| ---: | --- |
| < 5 | 正常 |
| 5–20 | 开始有感觉 |
| **> 50** | **界面会卡死** |

本机默认配置：队列 **131.7**，普通线程延迟 **186.9 ms**。

### 处理

```
--pool-workers <N>
```

**扫描法**：从物理核数一半开始，每次 +2，测 decode 和队列。

本机结果：

| workers | 队列 | decode |
| ---: | ---: | ---: |
| 4 | 0.3 | 82.8 |
| 6 | 1.3 | 88.9 |
| **10** | **2.7** | **90.0** |
| 12 | 3.3 | 91.8 |
| **15（默认）** | **46.7** | 91.1 |

**判据：decode 几乎不变，唯一断崖是队列。** 选"N = 队列 < 5 且 decode 不掉"。

> 反直觉：减少 worker 有时让 decode **更快**（本机 +6%）。
> 线程争抢和内存带宽竞争本身就是开销。

---

## 阶段 3：缓存策略（多会话场景）

### 判据

```bash
# 零复用的请求数
grep -c "prompt .* tokens = 0 reused" <engine.log>
```

**成串出现、且长度在两个值之间反复跳变**（如 `178780` ↔ `54333`）
= 多个会话在交替，checkpoint 互相挤掉。

本机实测：244 个请求里 102 个（42%）零复用，累计重读 **138.6 分钟**。

### 处理

```
--conversation-cache-mib <N>
```

**N 怎么算**：快照约 **23–32 KiB/token**。

| 最大会话 | 需要 |
| ---: | ---: |
| 50K | 约 1.2 GiB |
| 120K | 约 2.8 GiB |
| 200K | 约 4.7 GiB |

**多个大会话则相加。** 这是上限不是预分配，设大不会立即占满。

> 默认是自动计算的，但**通常算出 0（关闭）**——模型加载后引擎看到的
> 空闲内存已经很少。**必须显式指定。**
>
> **不要加** `--conversation-cache-min-tokens`：实测让短会话完全失去缓存，更慢。

---

## 阶段 4：引擎参数

### 4.1 prefill 分块

```
--prefill auto
```

| 值 | 本机实测 |
| --- | ---: |
| 2048 | 998.8 tok/s |
| 4096 | 1,682.7 |
| **auto** | **2,219.4** |
| 16384 | 2,094.9 |

**用 `auto` 而非写死值**：引擎按当时显存余量选最大可行分块，换档自动适配。

> 如果发现配置里有写死的 `--prefill`（尤其 2048），**这多半是调过头的**。
> 实测 `strata tune auto` 的规则表里明确禁止非 auto 值：
> `"smaller prompt chunks made long prompts 11% to 75% slower"`。

### 4.2 专家缓存

```
--expert-cache 4096
```

这是**下限**。引擎按可用显存自动扩（本机 4292 或 6295 槽）。
**手动往上调无效**，实测确认过。

---

## 阶段 5：内核开关（通常无功而返）

### 先检查能不能用

```
STRATA_MMQ_DIRECT=1 <启动>
```

日志出现下面这句就**直接放弃本阶段**：

```
STRATA_MMQ_DIRECT=1 is ignored: this build has no pointer-table MMQ
```

### 其它内核开关

查引擎文档的架构支持表。**如果目标卡的 compute capability 不在表内
（例如 sm_89 / RTX 40 不在任何表里），这些开关大概率无效。**

本机实测：`STRATA_ATTN_DAILY=1` 6 轮后 +1.0%，在噪声内。

---

## 阶段 6：验收

**速度和质量必须一起验。只测速度会调出"很快但答错"的配置。**

### 6.1 用内置基准做数量验证（首选）

Strata 自带 `strata bench`，它的 `standard-v1` 套件**设计上就是干这个的**——
既有性能阶段，也有 12 个带标准答案的 sanity 检查。

```bash
# 改造前
strata bench run --profile "<档位>" --track default --track-notes "before"

# 改造后
strata bench run --profile "<档位>" --track default --track-notes "after"

# 对比（会做 workload 校验，工作量不一致就拒绝比较）
strata bench compare <run1目录> <run2目录>
```

**套件内容**：

| 阶段 | 内容 | 请求数 | 计分 |
| --- | --- | ---: | :---: |
| Warm-up | 短提示词 | 1 | ❌ |
| **Performance** | short / prompt-4k / prompt-16k × 3 轮 | 9 | ✅ |
| **Sanity** | **I1–I4 / R1–R4 / T1–T4** | 12 | ✅ |
| 可选并发 | 4 路 × 3 轮 | 12 | 单独计 |

**Sanity 那 12 项是质量判据**，有冻结的期望答案：

| 类别 | 测什么 | 例子 |
| --- | --- | --- |
| **I**（指令遵循） | 能否严格遵守输出格式 | `I1`: 只返回 `{"ok":true,"count":3}`，不许有别的键 |
| **R**（长上下文检索） | 4K–16K 里能否找到指定信息 | `R1`: 4K 记录里插入 `access_code = ORBIT-731`，问它是什么 |
| **T**（工具调用） | 能否正确发起工具调用 | — |

**判据：性能阶段提速，同时 12 项 sanity 全部仍通过。** 有一项不过就是"调坏了"。

> **注意**：`--profile` 走服务端配置，所以**只能验证引擎参数**
> （`--prefill` / `--pool-workers` / `--conversation-cache-mib`）。
> 请求级改动（`reasoning_effort`）bench 覆盖不到，见 6.2。

### 6.2 请求级改动要盲评

`/effort` 这类改动基准测不到，只能人工评。但**必须盲评**，否则结论不可信。

**为什么**：知道哪个是自己想证明的那个版本，评价就有偏见。本机调优时，
我明知 `pelican-medium.html` 是 medium 生成的，说它"结构最好"时无法排除这层偏向。

**做法**：

```
1. 同一提示词，每个配置生成 3 次（不同 seed）
2. 用脚本打乱重命名成 A1..F6，隐藏对应关系
3. 只看文件名打分（或者让另一个不知道背景的 Agent 评）
4. 最后揭示
```

### 6.3 稳定性：同一配置跑 3 次

**单次结果不能比较。** 本机实测：同一配置两次生成差 **24%** 字符
（11,239 vs 9,048）。

要求：

- 同一配置跑 3 次，看波动范围
- 两个配置的**区间不重叠**才算有差异
- 第一轮永远作为预热丢弃

### 6.4 速度的端到端验收

**用端到端速度（输出 token / 墙钟秒数），不是 decode。**

本机结果：

| 项 | 改造前 | 改造后 | 倍数 |
| --- | ---: | ---: | ---: |
| 画图任务端到端 | 311.7 s | **57.4 s** | **5.4x** |
| 读 8K 提示词 | 998.8 tok/s | 2219.4 | 2.2x |
| 两会话交替复用 | 0/8 | 8/8 | — |
| CPU 队列 | 131.7 | 2.0 | — |

### 6.5 报告时必须说清的三种边界

只给数字不算完成，还要说明：

| 边界 | 说明 |
| --- | --- |
| **硬件上限** | 显存带宽、模型装不下的部分——软件改不动 |
| **未验证项** | 哪些改动没做盲评、哪些只测了一次 |
| **失效条件** | 例如 `/effort medium` 只在生成类任务上成立，调试要调回去 |

---

## 不要做（已排除的弯路）

| 不要 | 原因 |
| --- | --- |
| 装 CUDA Toolkit | 预编译引擎自带运行时 |
| 开 `STRATA_MMQ_DIRECT` | 预编译版不支持，引擎明确拒绝 |
| 手动开架构内核开关 | sm_89 等不在支持表内，实测在噪声内 |
| 加 `--conversation-cache-min-tokens` | 短会话失去缓存，更慢 |
| 加 `--max-queue 0` | 引擎本来只跑一个请求，限制只让后来的早点失败 |
| 用 session files 存盘恢复 | 启动器重写 run config，字段被抹掉 |
| 改 GPU 功耗限制解决 USB 掉电 | 实测 13 次无效 |
| 为省显存把 `--prefill` 压到 2048 | 省下的显存不紧张，代价是慢一倍 |
| 在服务端配置 `reasoning_effort` | 被请求的 `output_config` 覆盖 |
| 用 `budget_tokens` 代替 `effort` | 本机实测慢 34% 且结构更差 |

---

## 报告格式

调优完成后，给用户这份表格（**每行都要有实测数字，不要写"更快"**）：

| 项 | 改造前 | 改造后 | 倍数/效果 |
| --- | ---: | ---: | ---: |
| 端到端（典型任务） | | | |
| prefill tok/s | | | |
| decode tok/s | | | |
| CPU 队列 | | | |
| 会话复用率 | | | |

并说明：

1. **哪些改动需要每次手动做**（如 `/effort medium`），哪些是持久配置
2. **哪些是这台机器的硬件上限**，软件改不动
3. **哪些尝试过但无效**，避免下次重复
