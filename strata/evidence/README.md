# 证据索引

本目录存放**可复核的原始证据**：README 与文档里的关键数字，都能在这里找到逐字对应的日志行。

> 全部文件已脱敏：个人路径写成 `C:\Users\<user>\...`，安装路径写成 `$env:STRATA_HOME`
> 或 `<工作目录>`。

---

## 文件清单

| 文件 | 内容 |
|---|---|
| `iq2_xs-256k.engine.log` | **引擎启动日志摘录**（IQ2_XS 256K 档，脱敏） |
| `strata-launch.log` | `strata launch` 启动过程（56 行，脱敏） |
| `tune-256k.log` | 官方调优器原始输出（13 分钟，结论「已经最快」） |
| `llamacpp-load-ista-iq2xs.log` | llama.cpp 加载模型的关键行（73 KV 对、1224 张量） |
| `kvmem-startup-failure.log` | KV 显存启动失败记录 |
| `usb-disconnect-events.csv` | USB 小屏幕掉电事件（15 次重新枚举） |
| `extract-ninfer-stats.py` / `inspect-gguf.py` | 从日志 / GGUF 提取数据的脚本 |

---

## `iq2_xs-256k.engine.log` 的关键行

**来源**：`%LOCALAPPDATA%\Strata\launch\iq2_xs-256k.engine.log`（原始 13,588 行，
本目录只存证据摘录，不存全文——全文含 21 处个人路径且无必要）

| 数字 | 逐字原文（已验证 9/9 命中） |
|---|---|
| 33.02 GiB | `strata generate: loaded 33.02 GiB at 5.55 GiB/s` |
| 4292 槽 / 5.76 GiB | `strata generate: expert cache 4292 slots, 5.76 GiB of VRAM; policy is` |
| KV 32768/262144 | `strata generate: KV streaming: 32768 of 262144 cells per QSA layer in VRAM, the K/V in 2.39 GiB of pinned RAM` |
| 15 workers | `strata generate: CPU pool: 15 workers by default (16 physical cores, 24 logical processors; bounded by every physical core but the host's)` |
| 48 tasks/phase | `strata generate: CPU pool tasks/phase: 48 (automatic), participating threads: 16` |
| 1319 槽借用 | `strata serve: the prompt path borrows 1319 CUDA0 cache slots (1.76 GiB)` |
| 显存余量 | `strata serve: 2376 MiB of VRAM free with everything loaded` |
| 缓存命中 60.9% | `strata serve: decode expert cache hit rate: 60.9% (182 hits / 299 lookups)` |
| `--prefill 2048` | 启动参数行（**已脱敏，非逐字**） |

## `strata-launch.log` 的关键行

```
Checking the engine for this computer…
Downloading the model files: 6.9 of 68.9 GB
Checking that the model files are complete: 37.6 of 39.2 GB
Preparing your model for Strata (one time)
Loading the model… 15 s
Loading the model… 30 s
The model is loaded and answering.
Ready: http://127.0.0.1:8080
Strata is serving.
```

---

## 引用规则

1. **逐字**：文档里引用的日志行必须与这里一字不差，不得改写、不得拼接
2. **区分来源**：`strata-launch.log` 是启动器输出，`iq2_xs-256k.engine.log` 是引擎输出，
   两者不要混称「引擎日志」
3. **脱敏**：新增证据先跑 `grep -cE "<user-id>|C:\\\\Users|[A-Za-z]:\\\\"`，非 0 必须先把
   用户名和绝对路径换成占位符再入库（`<user>`、`$env:STRATA_HOME`、`<工作目录>`）
4. **不要把整份引擎日志提交进来**：摘录即可，全文在 `%LOCALAPPDATA%` 下，需要时重新导出
