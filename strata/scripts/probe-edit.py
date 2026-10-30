"""Does rewriting a few tokens in the middle of a conversation cost a full
re-read, and can --prompt-cache-tail / --prompt-cache-spread reduce it?

The scenario: a ~40K-token conversation is built and warmed, then a single
`user` turn near the END of the history is rewritten (the way an edited message
or a changed tool result looks to the engine). Everything after the edit has to
be recomputed; the only question is how far back the engine can resume.

  python -I probe-edit.py <port> <rounds>
"""
import json
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
BASE = f"http://127.0.0.1:{PORT}"
FILLER = ("The quick brown fox jumps over the lazy dog. "
          "Pack my box with five dozen liquor jugs. ")


def chat(messages, max_tokens=20):
    body = json.dumps({"messages": messages, "max_tokens": max_tokens,
                       "temperature": 0, "stream": False}).encode()
    req = urllib.request.Request(f"{BASE}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.loads(r.read())
    t = d.get("timings") or {}
    return (int(t.get("prompt_n") or 0), int(t.get("cache_n") or 0),
            float(t.get("prompt_ms") or 0)), d


def build_history(turns, seed_tokens):
    """An agent-like history: alternating user/assistant, one paragraph each."""
    para = FILLER * max(1, seed_tokens * 4 // (len(FILLER) * turns))
    msgs = []
    for i in range(turns):
        msgs.append({"role": "user", "content": f"Passage {i}:\n{para}"})
        msgs.append({"role": "assistant", "content": f"Noted passage {i}."})
    return msgs


def show(label, tup):
    read, cached, ms = tup
    total = read + cached
    pct = cached * 100 / total if total else 0
    print(f"  {label:<26} total {total:>7}  reused {cached:>7} ({pct:>5.1f}%)  "
          f"read {read:>6}  {ms / 1000:>6.1f} s")
    return read, cached, ms


if __name__ == "__main__":
    nonce = time.time_ns()
    hist = build_history(turns=8, seed_tokens=40000)

    # warm: one full pass so the engine holds the conversation
    t, d = chat(hist)
    show("warm-up (cold read)", t)

    # continue once, so the whole history is a live session
    reply = (d["choices"][0]["message"].get("content") or "").strip() or "ok"
    hist2 = hist + [{"role": "assistant", "content": reply},
                    {"role": "user", "content": "Summarise."}]
    t, _ = chat(hist2)
    show("plain continuation", t)

    print()
    print("now rewrite ONE user turn near the end, repeatedly:")
    rows = []
    for r in range(1, ROUNDS + 1):
        edited = [dict(m) for m in hist2]
        # rewrite the second-to-last user turn: a few tokens change, and
        # everything after it must be recomputed
        target = None
        for i in range(len(edited) - 1, -1, -1):
            if edited[i]["role"] == "user":
                if target is None:
                    target = i           # the last user turn: leave it
                else:
                    target = i           # the one before it
                    break
        edited[target]["content"] += f" [edit {r} of run {nonce}]"
        t, d = chat(edited)
        show(f"rewrite #{r}", t)
        rows.append(t)

    if rows:
        reads = [x[0] for x in rows]
        ms = [x[2] for x in rows]
        print()
        print(f"  re-read per rewrite: median {sorted(reads)[len(reads)//2]:,} tokens, "
              f"median {sorted(ms)[len(ms)//2] / 1000:.1f} s")
