"""Measure what alternating two conversations costs, and whether the
conversation cache stops the two from evicting each other.

The real traffic on this machine alternates between a ~180K conversation and a
~54K one (found in the engine log: 20 switches, every return re-read from 0).
This reproduces that with two smaller conversations so a run finishes in a
minute, and reports the reuse of every request.

  python -I probe-alternate.py <port> <rounds>
"""
import json
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 6
# the real traffic on this machine alternates ~180K with ~54K; these are the
# same ratio at a size a test can afford
LONG = int(sys.argv[3]) if len(sys.argv) > 3 else 18000
SHORT = int(sys.argv[4]) if len(sys.argv) > 4 else 5000
BASE = f"http://127.0.0.1:{PORT}"
FILLER = ("The quick brown fox jumps over the lazy dog. "
          "Pack my box with five dozen liquor jugs. ")


def chat(messages, max_tokens=16):
    body = json.dumps({"messages": messages, "max_tokens": max_tokens,
                       "temperature": 0, "stream": False}).encode()
    req = urllib.request.Request(f"{BASE}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.loads(r.read())
    t = d.get("timings") or {}
    return (int(t.get("prompt_n") or 0), int(t.get("cache_n") or 0),
            float(t.get("prompt_ms") or 0)), d


def seed(tokens, nonce, label):
    """A conversation of roughly `tokens` tokens, alternating user/assistant."""
    para = FILLER * (tokens * 4 // (len(FILLER) * 2))
    return [
        {"role": "user", "content": f"[{label} {nonce}]\n{para}"},
        {"role": "assistant", "content": "Understood."},
        {"role": "user", "content": "Summarise the passage."},
    ]


def turn(msgs, n):
    """Extend the conversation by one exchange."""
    return msgs + [{"role": "assistant", "content": f"Answer {n}."},
                   {"role": "user", "content": f"Turn {n}: one more sentence."}]


if __name__ == "__main__":
    nonce = time.time_ns()
    a = seed(LONG, nonce, "long")        # the "long" conversation
    b = seed(SHORT, nonce + 1, "short")   # the "short" conversation

    print(f"{'req':<6} {'conv':<5} {'total':>8} {'reused':>8} {'%':>6} {'read':>7} {'s':>6}")
    rows = []
    for n in range(1, ROUNDS + 1):
        for label, msgs in (("long", a), ("short", b)):
            msgs[:] = turn(msgs, n)
            (read, cached, ms), _ = chat(msgs)
            total = read + cached
            pct = cached * 100 / total if total else 0
            rows.append((label, total, cached, pct, read, ms))
            print(f"{n:<6} {label:<5} {total:>8} {cached:>8} {pct:>5.1f}% {read:>7} {ms/1000:>5.1f}")

    # after the first cycle every request should hit, if the two conversations
    # do not evict each other
    hit = [r for r in rows[2:] if r[3] >= 95]
    miss = [r for r in rows[2:] if r[3] < 50]
    print()
    print(f"after warm-up: {len(hit)}/{len(rows)-2} reused >=95%,  {len(miss)}/{len(rows)-2} near-zero")
    wasted = sum(r[5] for r in miss) / 1000
    print(f"time spent re-reading in near-zero requests: {wasted:.1f} s")
