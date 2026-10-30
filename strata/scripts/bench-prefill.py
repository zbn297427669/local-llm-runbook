"""Measure prompt (prefill) throughput of a running Strata server.

Each request carries a unique nonce so the server's prefix cache cannot serve
it - the number reported is a fresh read of the whole prompt.

  python -I bench-prefill.py <port> <tokens> [rounds]

The prompt is repeated filler text; `tokens` is approximate (the server reports
the exact count in its timings block).
"""
import json
import statistics
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WANT = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
ROUNDS = int(sys.argv[3]) if len(sys.argv) > 3 else 3
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"

# ~4 chars per token for English prose
FILLER = ("The quick brown fox jumps over the lazy dog. "
          "Pack my box with five dozen liquor jugs. ")


def build(nonce, want_tokens):
    body = FILLER * max(1, want_tokens * 4 // len(FILLER))
    return f"[run {nonce}]\n{body}\n\nReply with the single word OK."


def once(nonce, want_tokens, timeout=1800):
    payload = {
        "messages": [{"role": "user", "content": build(nonce, want_tokens)}],
        "max_tokens": 1,          # we only care about the prompt pass
        "temperature": 0,
        "stream": False,
    }
    req = urllib.request.Request(
        URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read())
    t = data.get("timings", {})
    return t.get("prompt_n"), t.get("prompt_per_second"), t.get("prompt_ms")


def main():
    speeds = []
    for i in range(ROUNDS):
        try:
            n, tps, ms = once(f"{time.time_ns()}", WANT)
        except Exception as exc:
            print(f"round {i + 1}: FAILED {exc}")
            continue
        if not tps:
            print(f"round {i + 1}: no timings block")
            continue
        speeds.append(tps)
        print(f"round {i + 1}: {n} tokens in {ms / 1000:.2f} s = {tps:.1f} tok/s")
    if speeds:
        print(f"\nprefill median {statistics.median(speeds):.1f} tok/s "
              f"(range {min(speeds):.1f}-{max(speeds):.1f}, n={len(speeds)})")


if __name__ == "__main__":
    main()
