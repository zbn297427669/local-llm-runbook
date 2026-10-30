"""Generate the pelican page with thinking on and off, save both, and look for
a concrete reason one comes out longer than the other.

Reports structure (tags, functions, repeated lines) rather than just lengths,
because "longer" can mean more features, more padding, or duplicated code.
"""
import collections
import json
import os
import re
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8080/v1/chat/completions"
OUT = os.environ.get("PELICAN_OUT", os.path.join("out", "pelican"))
PROMPT = ("Write a complete single-file HTML page with canvas: a pelican riding "
          "a bicycle, animated. All code in one file, no explanation.")


def ask(extra):
    body = {"messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": 32768, "temperature": 0, "stream": False}
    body.update(extra)
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.loads(r.read())
    wall = time.time() - t0
    m = d["choices"][0]["message"]
    t = d.get("timings") or {}
    return {
        "content": m.get("content") or "",
        "reasoning": m.get("reasoning_content") or "",
        "wall": wall,
        "tokens": d.get("usage", {}).get("completion_tokens"),
        "tps": t.get("predicted_per_second") or 0,
        "finish": d["choices"][0].get("finish_reason"),
    }


def strip_fence(s):
    c = s.strip()
    if c.startswith("```"):
        c = c[c.find("\n") + 1:]
        if c.rstrip().endswith("```"):
            c = c.rstrip()[:-3]
    return c


def profile(name, html):
    lines = [l for l in html.split("\n")]
    nonblank = [l.strip() for l in lines if l.strip()]
    dup = [l for l, n in collections.Counter(nonblank).items() if n > 1 and len(l) > 20]
    return {
        "chars": len(html),
        "lines": len(lines),
        "nonblank": len(nonblank),
        "avg_line": sum(len(l) for l in nonblank) / max(1, len(nonblank)),
        "functions_js": len(re.findall(r"\bfunction\s+\w+", html)),
        "arrow_fns": len(re.findall(r"=>", html)),
        "css_rules": len(re.findall(r"\{[^{}]*:[^{}]*\}", html)),
        "canvas_calls": len(re.findall(r"ctx\.\w+\(", html)),
        "dup_lines": len(dup),
        "longest_line": max((len(l) for l in lines), default=0),
    }


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    results = {}
    for name, extra in [("default", {}), ("nothink", {"reasoning_effort": "none"})]:
        print(f"--- {name} ---")
        r = ask(extra)
        html = strip_fence(r["content"])
        path = os.path.join(OUT, f"pelican-{name}.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(html)
        p = profile(name, html)
        results[name] = p
        print(f"  finish {r['finish']}  tokens {r['tokens']}  wall {r['wall']:.1f}s  "
              f"decode {r['tps']:.1f} t/s")
        print(f"  thinking chars {len(r['reasoning']):,}")
        print(f"  -> {path}")

    print("\n--- structure ---")
    keys = ["chars", "lines", "nonblank", "avg_line", "functions_js", "arrow_fns",
            "css_rules", "canvas_calls", "dup_lines", "longest_line"]
    print(f"{'':<14}" + "".join(f"{k:>13}" for k in keys))
    for name in results:
        row = "".join(f"{results[name][k]:>13}" for k in keys)
        print(f"{name:<14}{row}")
