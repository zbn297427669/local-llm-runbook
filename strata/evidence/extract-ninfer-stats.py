"""Extract every measurable fact from ninfer run logs.

Usage:
    python -I extract-ninfer-stats.py
    NINFER_LOGS=<dir> python -I extract-ninfer-stats.py

Reads every run-*.log in the folder and prints: per-log totals, speed by
prompt-length bucket, cache-hit versus speed, and the fastest/slowest requests.
"""
import os
import re
from pathlib import Path

LOGS = Path(os.environ.get(
    "NINFER_LOGS",
    "logs",
))

REQ = re.compile(
    r"(?P<ts>[\d-]+ [\d:.]+)\s+INFO\s+req#(?P<n>\d+) done \| (?P<api>\w+)"
    r"(?: \| (?P<finish>[^|]+?))? \| prompt (?P<prompt>[\d,]+) \| output (?P<out>[\d,]+)"
    r" \| cache (?P<cache>[\d,]+) \((?P<cachepct>[\d.]+)%[^)]*\)"
    r" \| TTFT (?P<ttft>[^|]+?) \| total (?P<total>[^|]+?) \| queue [?.\d]+ ms"
    r" \| prefill (?P<prefill>[\d.]+k?) tok/s \| decode (?P<decode>[\d.]+) tok/s"
)

print("=" * 78)
print("每个日志：请求数、速度范围")
print("=" * 78)

all_reqs = []
for log in sorted(LOGS.glob("run-*.log")):
    txt = log.read_text(encoding="utf-8", errors="replace")
    reqs = []
    for m in REQ.finditer(txt):
        try:
            reqs.append({
                "file": log.name,
                "n": int(m.group("n")),
                "ts": m.group("ts"),
                "prompt": int(m.group("prompt").replace(",", "")),
                "out": int(m.group("out").replace(",", "")),
                "cache_pct": float(m.group("cachepct")),
                "ttft": m.group("ttft").strip(),
                "decode": float(m.group("decode")),
                "prefill": m.group("prefill"),
            })
        except ValueError:
            pass
    if not reqs:
        continue
    all_reqs.extend(reqs)
    dec = [r["decode"] for r in reqs]
    prm = [r["prompt"] for r in reqs]
    print(f"\n{log.name}")
    print(f"  请求 {len(reqs):3d}  |  提示词 {min(prm):>7,} – {max(prm):>7,}"
          f"  |  decode {min(dec):.1f} – {max(dec):.1f} tok/s (中位 {sorted(dec)[len(dec)//2]:.1f})")

print()
print("=" * 78)
print(f"总计 {len(all_reqs)} 个请求")
print("=" * 78)

# 按提示词长度分桶，看长上下文下的速度衰减
buckets = [(0, 8000), (8000, 32000), (32000, 64000), (64000, 999999)]
print("\n按提示词长度分组：")
print(f"  {'区间':>16}  {'请求':>4}  {'decode 中位':>11}  {'cache 中位':>10}")
for lo, hi in buckets:
    sel = [r for r in all_reqs if lo <= r["prompt"] < hi]
    if not sel:
        continue
    dec = sorted(r["decode"] for r in sel)
    cac = sorted(r["cache_pct"] for r in sel)
    label = f"{lo//1000}K–{hi//1000}K" if hi < 999999 else f"{lo//1000}K+"
    print(f"  {label:>16}  {len(sel):>4}  {dec[len(dec)//2]:>10.1f}  {cac[len(cac)//2]:>9.1f}%")

# 缓存命中与速度的关系
hot = [r["decode"] for r in all_reqs if r["cache_pct"] >= 90]
cold = [r["decode"] for r in all_reqs if r["cache_pct"] < 10]
if hot:
    print(f"\n  缓存命中 ≥90%: {len(hot)} 个, decode 中位 {sorted(hot)[len(hot)//2]:.1f} tok/s")
if cold:
    print(f"  缓存命中 <10%: {len(cold)} 个, decode 中位 {sorted(cold)[len(cold)//2]:.1f} tok/s")

# 最慢的请求 —— 看看那次 11.6 tok/s 是什么
print("\n最慢的 5 个请求：")
for r in sorted(all_reqs, key=lambda x: x["decode"])[:5]:
    print(f"  {r['ts'][11:19]}  prompt {r['prompt']:>7,}  output {r['out']:>5,}"
          f"  decode {r['decode']:>5.1f}  cache {r['cache_pct']:>5.1f}%  TTFT {r['ttft']}")

print("\n最快的 5 个请求：")
for r in sorted(all_reqs, key=lambda x: -x["decode"])[:5]:
    print(f"  {r['ts'][11:19]}  prompt {r['prompt']:>7,}  output {r['out']:>5,}"
          f"  decode {r['decode']:>5.1f}  cache {r['cache_pct']:>5.1f}%  TTFT {r['ttft']}")
