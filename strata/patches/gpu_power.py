"""Ask Windows for the administrator rights that `nvidia-smi -pl` needs.

A local addition (not upstream). `nvidia-smi -pl` is an administrator operation on Windows:
from a normal terminal it fails with "Insufficient Permissions". There is no way to raise a
process's own rights, so this starts a *separate* elevated process through the normal UAC
prompt. The person sees the Windows dialog, names the program, and can cancel it; nothing is
started silently and nothing is persisted (no scheduled task, no service, no registry).

Only `nvidia-smi` is ever run this way, and only with a numeric power limit: the executable is
fixed here and the arguments are built from integers, so no caller can hand this an arbitrary
command line.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

EXE = "nvidia-smi"


def available() -> bool:
    return shutil.which(EXE) is not None


def read_limits() -> list[tuple[int, float, float]]:
    """[(index, current, default)] in watts. Empty when nvidia-smi cannot answer."""
    try:
        q = subprocess.run([EXE, "--query-gpu=power.limit,power.default_limit",
                            "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return []
    if q.returncode != 0:
        return []
    out = []
    for i, line in enumerate(q.stdout.strip().splitlines()):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 2:
            continue
        try:
            out.append((i, float(parts[0]), float(parts[1])))
        except ValueError:
            continue
    return out


def set_limit(want: int, index: int | None = None) -> tuple[bool, str]:
    """Try `nvidia-smi -pl` in this process. (ok, the tool's own words)."""
    argv = [EXE] + (["-i", str(index)] if index is not None else []) + ["-pl", str(int(want))]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    text = " ".join(((r.stderr or "") + " " + (r.stdout or "")).split())
    return r.returncode == 0, text


def _needs_admin(text: str) -> bool:
    low = text.lower()
    return "permission" in low or "access is denied" in low or "拒绝访问" in text


def ask_for_admin(want: int, index: int | None = None) -> tuple[bool, str]:
    """Run the same `nvidia-smi -pl` in an elevated process, via the Windows UAC prompt.

    Returns (ok, why). The result is judged by reading the limit back, not by the child's exit
    code: an UAC cancel, a driver refusal and a successful set all end differently, and only
    the card's own answer is authoritative.
    """
    if os.name != "nt":
        return False, "elevation is only implemented on Windows"
    if not available():
        return False, f"{EXE} is not on PATH"
    if not (sys.stdin and sys.stdin.isatty()):
        return False, "no terminal to show the UAC prompt on"

    args = ["-i", str(index)] if index is not None else []
    args += ["-pl", str(int(want))]
    # -i and -pl are integers from the caller; the executable is fixed above.
    quoted = ",".join(f"'{a}'" for a in args)
    ps = (f"$p = Start-Process -FilePath '{EXE}' -ArgumentList {quoted} "
          f"-Verb RunAs -Wait -PassThru -WindowStyle Hidden; exit $p.ExitCode")
    try:
        subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
                       capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)

    limits = read_limits()
    if index is None:
        ok = bool(limits) and all(cur <= want + 1 for _, cur, _ in limits)
    else:
        ok = any(i == index and cur <= want + 1 for i, cur, _ in limits)
    return (ok, "" if ok else "the UAC prompt was cancelled or the driver refused")


def cap(want: int) -> tuple[bool, str, bool]:
    """Make sure every card is at or below `want` watts.

    Returns (ok, message, elevated). Tries this process first; when the driver says it needs
    administrator rights, asks for them once through UAC.
    """
    limits = read_limits()
    if not limits:
        return False, f"{EXE} could not be read", False
    if all(cur <= want + 1 for _, cur, _ in limits):
        return True, "already at or below the cap", False

    ok, text = set_limit(want)
    if ok:
        return True, "", False

    if not _needs_admin(text):
        return False, text or f"{EXE} refused", False

    ok, why = ask_for_admin(want)
    return ok, why, ok


def restore() -> tuple[bool, list[int], bool]:
    """Put every card back at its default limit. Returns (ok, defaults, elevated)."""
    limits = read_limits()
    capped = [(i, cur, dflt) for i, cur, dflt in limits if cur < dflt]
    if not capped:
        return True, [], False

    promoted = False
    for i, _cur, dflt in capped:
        ok, text = set_limit(int(dflt), i)
        if not ok and _needs_admin(text):
            ok, _ = ask_for_admin(int(dflt), i)
            promoted = promoted or ok
        if not ok:
            return False, [int(d) for _, _, d in capped], promoted

    return True, [int(d) for _, _, d in capped], promoted
