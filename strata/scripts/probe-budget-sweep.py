"""Find the best thinking budget for this machine: how much structure does each
level buy, and what does it cost?

Judges structure on things that separate a planned implementation from a
flat one, not on raw length:
  - animation layers: how many independent time-driven parameters
  - kinematics: near/far pedal or leg positions computed separately
  - function split: how many drawing helpers the page defines
  - rhythm: distinct sin() phases (a single wobble is not animation)

  python -I probe-budget-sweep.py [port]
"""
import json
import os
import re
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
OUT = os.environ.get("PELICAN_OUT", os.path.join("out", "pelican"))
PROMPT = ("Write a complete single-file HTML page with canvas: a pelican riding "
          "a bicycle, animated. All code in one file, no explanation.")

ARMS = [
    ("none", {"reasoning_effort": "none"}),
    ("budget 2048", {"reasoning_budget_tokens": 2048}),
    ("budget 4096", {"reasoning_budget_tokens": 4096}),
    ("budget 8192", {"reasoning_budget_tokens": 8192}),
    ("medium", {"reasoning_effort": "medium"}),
    ("default/high", {}),
]


def ask(extra, max_tokens=32768):
    body = {"messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": max_tokens, "temperature": 0, "stream": False}
    body.update(extra)
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.loads(r.read())
    wall = time.time() - t0
    m = d["choices"][0]["message"]
    return {
        "content": m.get("content") or "",
        "reasoning": m.get("reasoning_content") or "",
        "wall": wall,
        "tokens": d.get("usage", {}).get("completion_tokens") or 0,
        "tps": (d.get("timings") or {}).get("predicted_per_second") or 0,
        "finish": d["choices"][0].get("finish_reason"),
    }


def strip_fence(s):
    c = s.strip()
    if c.startswith("```"):
        c = c[c.find("\n") + 1:]
        if c.rstrip().endswith("```"):
            c = c.rstrip()[:-3]
    return c


def score(html):
    """Signals of a planned implementation rather than a flat one."""
    # distinct animation phases: sin(t * K) with different K
    phases = {m.group(1) for m in re.finditer(r"sin\(\s*\w+\s*\*\s*([\d.]+)", html)}
    fns = len(set(re.findall(r"\bfunction\s+(\w+)", html)))
    near_far = 1 if re.search(r"(near|far).*(pedal|leg|foot)", html, re.I) else 0
    layers = 0
    for w in ("bob", "flap", "wag", "sway", "lean", "nod", "blink"):
        if re.search(w, html, re.I):
            layers += 1
    checks = {
        "canvas": "canvas" in html.lower(),
        "pelican": "pelican" in html.lower(),
        "bike": bool(re.search(r"bicycle|bike", html, re.I)),
        "animation": "requestAnimationFrame" in html,
    }
    return {
        "phases": len(phases),
        "functions": fns,
        "near_far": near_far,
        "layers": layers,
        "all_ok": all(checks.values()),
        "chars": len(html),
    }


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for name, extra in ARMS:
        try:
            r = ask(extra)
        except Exception as exc:
            print(f"{name:<14} FAILED {exc}")
            continue
        html = strip_fence(r["content"])
        safe = name.replace("/", "-").replace(" ", "-")
        with open(os.path.join(OUT, f"pelican-{safe}.html"), "w", encoding="utf-8") as f:
            f.write(html)
        s = score(html)
        rows.append((name, r, s))
        print(f"{name:<14} {r['wall']:>6.1f}s  tok {r['tokens']:>6}  "
              f"think {len(r['reasoning']):>6}  code {s['chars']:>6}  "
              f"fn {s['functions']:>2}  phases {s['phases']:>2}  "
              f"layers {s['layers']:>2}  near/far {'y' if s['near_far'] else '-'}  "
              f"{'OK' if s['all_ok'] else 'INCOMPLETE'}")

    print("\n--- ranked by structure per second ---")
    print(f"{'arm':<14} {'wall':>7} {'structure':>10} {'struct/s':>10}")
    for name, r, s in sorted(rows, key=lambda x: -(
            (x[2]['phases'] + x[2]['functions'] / 2 + x[2]['layers'] +
             x[2]['near_far'] * 2) / max(1, x[1]['wall']))):
        struct = s['phases'] + s['functions'] / 2 + s['layers'] + s['near_far'] * 2
        print(f"{name:<14} {r['wall']:>6.1f}s {struct:>10.1f} {struct / max(1, r['wall']):>10.4f}")
