"""Does a session file let a long conversation skip the re-read after a restart?

The claim to test: with `--slot-save-path`, a conversation saved to disk before
a stop can be restored after the engine restarts, so a 40K-token prompt is not
read again from scratch.

  python -I probe-session.py <port> <save-dir>

It reports, for each stage, how many prompt tokens the server had to read and
how long it took.
"""
import json
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
BASE = f"http://127.0.0.1:{PORT}"
FILLER = ("The quick brown fox jumps over the lazy dog. "
          "Pack my box with five dozen liquor jugs. ")
SEED_TOKENS = 40000


def post_chat(messages, max_tokens=30):
    body = json.dumps({
        "messages": messages, "max_tokens": max_tokens,
        "temperature": 0, "stream": False,
    }).encode()
    req = urllib.request.Request(f"{BASE}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.loads(r.read())
    t = d.get("timings") or {}
    return (int(t.get("prompt_n") or 0), int(t.get("cache_n") or 0),
            float(t.get("prompt_ms") or 0)), d


def slot(action, filename):
    body = json.dumps({"filename": filename}).encode()
    req = urllib.request.Request(f"{BASE}/slots/0?action={action}", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, r.read()[:200].decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300].decode("utf-8", "replace")


def show(label, tup):
    read, cached, ms = tup
    total = read + cached
    pct = cached * 100 / total if total else 0
    print(f"  {label:<28} total {total:>7}  reused {cached:>7} ({pct:>5.1f}%)  "
          f"read {read:>6}  {ms / 1000:>6.1f} s")


if __name__ == "__main__":
    nonce = time.time_ns()
    messages = [{"role": "user",
                 "content": f"[conv {nonce}]\n" + FILLER * (SEED_TOKENS * 4 // len(FILLER))}]

    print("1. first turn - nothing cached yet")
    t, d = post_chat(messages)
    show("cold read", t)
    reply = (d["choices"][0]["message"].get("content") or "").strip() or "ok"
    messages.append({"role": "assistant", "content": reply})
    messages.append({"role": "user", "content": "Turn 2: one short sentence."})

    print("\n2. second turn - should reuse the whole prefix")
    t, d = post_chat(messages)
    show("warm turn", t)

    print("\n3. save the conversation to disk")
    code, body = slot("save", "probe-session.bin")
    print(f"  HTTP {code}  {body[:120]}")

    print("\n  now stop the engine, start it again, then run stage 4.")
    print("  (the caller does that; this script's job ends with the save)")
