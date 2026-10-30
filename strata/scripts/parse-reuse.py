"""Report prompt reuse per turn from a Strata engine log, for the LAST run only.

The engine appends to its log across restarts, so a naive scan mixes runs: an
earlier version of this analysis read three different runs and reported their
identical numbers as three experimental arms. This splits on the
`engine started:` lines and keeps only the final run.
"""
import os
import re
import sys

_DEFAULT = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"),
                        "Strata", "launch", "bench-reuse.engine.log")
PATH = sys.argv[1] if len(sys.argv) > 1 else _DEFAULT

START = re.compile(r"^\[strata\] .*engine started:")
PROMPT = re.compile(
    r"prompt (\d+) tokens = (\d+) reused \+ (\d+) read in (\d+) ms "
    r"\(([\d.]+) tok/s\).*?(\d+) checkpoints"
)

runs = []
current = None
for line in open(PATH, encoding="utf-8", errors="replace"):
    if START.match(line):
        current = {"start": line.strip()[:40], "rows": []}
        runs.append(current)
    elif current is not None:
        m = PROMPT.search(line)
        if m:
            n, reuse, read, ms, tps, ck = m.groups()
            current["rows"].append(
                (int(n), int(reuse), int(read), int(ms), float(tps), int(ck)))

print(f"runs found: {len(runs)}")
if not runs:
    sys.exit(1)

last = runs[-1]
print(f"using the last one: {last['start']}")
print()
print(f"{'prompt':>9} {'reused':>9} {'%':>6} {'read':>7} {'s':>7} {'ckpt':>5}")
tot_n = tot_r = tot_ms = 0
for n, reuse, read, ms, tps, ck in last["rows"]:
    if n < 1000:
        continue                      # warm-up chatter
    tot_n += n
    tot_r += reuse
    tot_ms += ms
    print(f"{n:>9} {reuse:>9} {reuse * 100 / n:>5.1f}% {read:>7} {ms / 1000:>7.1f} {ck:>5}")

if tot_n:
    print()
    print(f"TOTAL reused {tot_r * 100 / tot_n:.1f}% ({tot_r:,} of {tot_n:,}), "
          f"read time {tot_ms / 1000:.1f} s")
