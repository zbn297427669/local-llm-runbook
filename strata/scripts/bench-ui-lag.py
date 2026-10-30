"""Measure how responsive the machine stays while the model is busy.

The complaint: typing, the cursor and scrolling stall while a local request
runs, even though RAM is not full. The suspect is CPU contention - the engine
binds a worker per physical core, leaving the UI thread competing for the rest.

This records, during a heavy decode, the system's own scheduling health:
  - % Total Processor Time           (is everything saturated?)
  - Processor Queue Length           (are runnable threads waiting?)
  - Page Faults/sec                  (soft faults cost CPU too)
  - a wall-clock probe: how long a trivial thread takes to get scheduled

A lower worker count should show up as a shorter queue and a quicker probe.

  python -I bench-ui-lag.py <label> [port]
"""
import json
import statistics
import subprocess
import sys
import threading
import time
import urllib.request

LABEL = sys.argv[1] if len(sys.argv) > 1 else "run"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"

PROMPT = ("Write a complete single-file HTML page with canvas: a pelican riding "
          "a bicycle, animated. All code in one file, no explanation.")


def ps_counter(path, samples=1):
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             f"(Get-Counter '{path}' -SampleInterval 1 -MaxSamples {samples})."
             f"CounterSamples.CookedValue"],
            capture_output=True, text=True, timeout=30).stdout
        vals = [float(x) for x in out.split() if x.replace('.', '', 1).isdigit()]
        return statistics.mean(vals) if vals else None
    except Exception:
        return None


def probe_latency(n=25):
    """How long a trivial Python thread takes to be scheduled and finish.

    Not a precise scheduler measurement, but it moves in the same direction as
    UI responsiveness: if the engine occupies every core, this stretches.
    """
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        th = threading.Thread(target=lambda: sum(range(2000)))
        th.start()
        th.join()
        times.append((time.perf_counter() - t0) * 1000)   # ms
    return statistics.median(times), max(times)


def main():
    print(f"=== {LABEL} ===")
    idle_q = ps_counter(r'\System\Processor Queue Length')
    idle_lat, idle_max = probe_latency()
    print(f"  idle:   queue {idle_q}  probe median {idle_lat:.1f} ms  max {idle_max:.1f} ms")

    body = json.dumps({"messages": [{"role": "user", "content": PROMPT}],
                       "max_tokens": 6000, "temperature": 0, "stream": False,
                       "reasoning_effort": "none"}).encode()

    result = {}

    def call():
        req = urllib.request.Request(URL, data=body,
                                     headers={"Content-Type": "application/json"})
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=900) as r:
            d = json.loads(r.read())
        result["wall"] = time.time() - t0
        t = d.get("timings") or {}
        result["tps"] = t.get("predicted_per_second")
        result["tokens"] = (d.get("usage") or {}).get("completion_tokens")

    th = threading.Thread(target=call)
    th.start()
    time.sleep(4)                       # let the engine get into steady decode

    cpu = ps_counter(r'\Processor(_Total)\% Processor Time', samples=3)
    queue = ps_counter(r'\System\Processor Queue Length', samples=3)
    lat, mx = probe_latency()

    th.join()

    print(f"  busy:   queue {queue}  probe median {lat:.1f} ms  max {mx:.1f} ms")
    print(f"  cpu total {cpu:.0f}%   decode {result.get('tps') or 0:.1f} tok/s  "
          f"({result.get('tokens')} tok in {result.get('wall', 0):.1f} s)")
    print()
    print(f"  latency inflation: {lat / idle_lat:.1f}x   "
          f"queue delta: {(queue - idle_q) if (queue is not None and idle_q is not None) else '?'}")


if __name__ == "__main__":
    main()
