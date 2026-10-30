"""Time N sequential chat completions against a local OpenAI-compatible server
and report prompt/decode speeds from the server's own timings block.

The first request warms the expert routing, so it is reported separately and
excluded from the median.

  python -I bench-api.py                # llama.cpp on 8091
  python -I bench-api.py 6 8080         # Strata on 8080

Both servers expose the same `timings` object, which is what makes the two
numbers directly comparable.
"""
import json
import statistics
import sys
import time
import urllib.request

PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8091
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
PROMPT = (
    "Write a Python function that merges two sorted lists into one sorted list, "
    "then explain its time and space complexity in two sentences."
)


def once(timeout=600):
    body = json.dumps({
        "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": 300,
        "temperature": 0,
        "stream": False,
    }).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read())
    wall = time.time() - t0
    t = data.get("timings", {})
    return {
        "wall_s": wall,
        "prompt_tps": t.get("prompt_per_second"),
        "decode_tps": t.get("predicted_per_second"),
        "prompt_n": t.get("prompt_n"),
        "predicted_n": t.get("predicted_n"),
        "content_len": len(data["choices"][0]["message"].get("content") or ""),
    }


def main(rounds=6):
    results = []
    for i in range(rounds):
        try:
            r = once()
        except Exception as exc:
            print(f"round {i + 1}: FAILED {exc}")
            continue
        results.append(r)
        print(f"round {i + 1}: prompt {r['prompt_tps']:.1f} t/s  "
              f"decode {r['decode_tps']:.1f} t/s  "
              f"({r['predicted_n']} tok in {r['wall_s']:.1f}s, content {r['content_len']} chars)")

    if len(results) < 2:
        print("not enough rounds")
        return
    warm, rest = results[0], results[1:]
    dec = [r["decode_tps"] for r in rest if r["decode_tps"]]
    pre = [r["prompt_tps"] for r in rest if r["prompt_tps"]]
    if dec:
        print(f"\nwarm-up round: decode {warm['decode_tps']:.1f} t/s (excluded)")
        print(f"decode  median {statistics.median(dec):.1f}  "
              f"range {min(dec):.1f}-{max(dec):.1f}  n={len(dec)}")
    if pre:
        print(f"prompt  median {statistics.median(pre):.1f}  "
              f"range {min(pre):.1f}-{max(pre):.1f}  n={len(pre)}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 6)
