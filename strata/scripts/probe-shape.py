"""Compare two request shapes against a running Strata server and report how
much of the prompt the engine reused.

The question: does a multi-turn `messages` array (user/assistant alternating,
which is what ccr-claude and every agent sends) resume from the conversation
the previous request parked, when a single growing `user` message does not?

  python -I probe-shape.py            # 256K tier, 4 turns each
"""
import json
import statistics
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8080/v1/chat/completions"
FILLER = ("The quick brown fox jumps over the lazy dog. "
          "Pack my box with five dozen liquor jugs. ")
SEED_TOKENS = 40000
TURNS = 4


def post(messages, max_tokens=40):
    body = json.dumps({
        "messages": messages, "max_tokens": max_tokens,
        "temperature": 0, "stream": False,
    }).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.loads(r.read())


def report(label, timings):
    print(f"\n--- {label} ---")
    tot_n = tot_saved = 0
    for n, saved, ms in timings:
        tot_n += n
        tot_saved += saved
        print(f"  prompt {n:>7}  reused {saved:>7} ({saved * 100 / n:>5.1f}%)  "
              f"{ms / 1000:>6.1f} s")
    if tot_n:
        print(f"  TOTAL reused {tot_saved * 100 / tot_n:.1f}%")


def saved_tokens(t):
    """cache_n is the prefix the server did not have to read again."""
    return int(t.get("cache_n") or 0), int(t.get("prompt_n") or 0)


def run_single_message(nonce):
    """One growing user message - what my earlier bench did."""
    hist = FILLER * (SEED_TOKENS * 4 // len(FILLER))
    out = []
    for t in range(1, TURNS + 1):
        hist += f"\nTurn {t}: summarise in one short sentence."
        d = post([{"role": "user", "content": f"[conv {nonce}]\n{hist}"}])
        ms = (d.get("timings") or {}).get("prompt_ms") or 0
        cached, n = saved_tokens(d.get("timings") or {})
        out.append((n or 1, cached, ms))
    return out


def run_multi_turn(nonce):
    """user/assistant alternating - what an agent actually sends."""
    messages = [{"role": "user",
                 "content": f"[conv {nonce}]\n" + FILLER * (SEED_TOKENS * 4 // len(FILLER))}]
    out = []
    for t in range(1, TURNS + 1):
        d = post(messages)
        tim = d.get("timings") or {}
        ms = tim.get("prompt_ms") or 0
        cached, n = saved_tokens(tim)
        out.append((n or 1, cached, ms))
        reply = (d["choices"][0]["message"].get("content") or "").strip() or "ok"
        messages.append({"role": "assistant", "content": reply})
        messages.append({"role": "user",
                         "content": f"Turn {t}: summarise in one short sentence."})
    return out


if __name__ == "__main__":
    nonce = time.time_ns()
    report("single growing user message", run_single_message(nonce))
    report("user/assistant alternating", run_multi_turn(nonce + 1))
