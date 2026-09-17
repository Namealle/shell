#!/usr/bin/env python3
"""Fire one supernova and capture its whole life cycle, frames and cost.

    sn_capture.py TAG OUTDIR [--secs 90] [--screen tablet]
                  [--overrides '{"precursor":6}'] [--perf t0:t1,t2:t3]
                  [--no-fire] [--every 1.0]

One frame per second through the episode with absolute deadlines (a grim call
takes 60-300 ms, so a naive sleep(1) drifts a whole phase over 90 frames), plus
a perf window over each `--perf` interval so the cost of the shell phase and
the cost of the remnant are two separate numbers rather than one average that
hides both.

Traps this encodes so nobody rediscovers them:
  * the sky PAUSES on an output covered by a fullscreen window (rules.js
    `runningFor`), so only an uncovered output draws or measures anything;
  * `starfield-shell perf dump` RESTARTS the window, so a dump is the interval
    since the previous dump, never a running average;
  * every qs/grim call must run unsandboxed or it kills his shell.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import time

SHELL = os.environ.get("STARFIELD_SHELL", os.path.expanduser("~/namealle/scripts/starfield-shell"))


def sh(*args, check=False):
    return subprocess.run(args, capture_output=True, text=True, check=check)


def perf(cmd="dump"):
    out = sh(SHELL, "perf", cmd).stdout.strip()
    try:
        return json.loads(out[out.index("{"):])
    except (ValueError, json.JSONDecodeError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("outdir")
    ap.add_argument("--secs", type=float, default=90)
    ap.add_argument("--every", type=float, default=1.0)
    ap.add_argument("--screen", default="tablet")
    ap.add_argument("--overrides", default="")
    ap.add_argument("--family", default="supernova")
    ap.add_argument("--no-fire", action="store_true")
    ap.add_argument("--perf", default="", help="comma list of t0:t1 windows, seconds from fire")
    args = ap.parse_args()

    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob(f"{args.tag}-*.png"):
        old.unlink()

    windows = []
    for part in filter(None, args.perf.split(",")):
        a, b = part.split(":")
        windows.append([float(a), float(b), None])

    log = {"tag": args.tag, "screen": args.screen, "overrides": args.overrides,
           "every": args.every, "secs": args.secs, "frames": [], "perf": {}}

    sh(SHELL, "perf", "on")
    perf("dump")  # zero the accumulator

    if not args.no_fire:
        r = sh(SHELL, "fire", args.family, args.screen, args.overrides)
        log["fire"] = (r.stdout + r.stderr).strip()
    t0 = time.time()

    n = int(args.secs / args.every)
    pending = list(windows)
    for i in range(n):
        deadline = t0 + i * args.every
        now = time.time()
        if deadline > now:
            time.sleep(deadline - now)
        elapsed = time.time() - t0
        # A perf window opens by zeroing the accumulator and closes by dumping.
        for w in pending:
            if w[2] is None and elapsed >= w[0]:
                perf("dump")
                w[2] = "open"
        for w in pending:
            if w[2] == "open" and elapsed >= w[1]:
                log["perf"][f"{w[0]:g}-{w[1]:g}s"] = perf("dump")
                w[2] = "done"
        name = out / f"{args.tag}-{i:03d}.png"
        sh("grim", "-o", args.screen, str(name))
        log["frames"].append({"i": i, "t": round(elapsed, 3), "file": name.name})

    for w in pending:
        if w[2] == "open":
            log["perf"][f"{w[0]:g}-{w[1]:g}s"] = perf("dump")
    (out / f"{args.tag}.json").write_text(json.dumps(log, indent=1))
    print(f"{args.tag}: {n} frames in {out}")
    for k, v in log["perf"].items():
        s = (v or {}).get(args.screen, {})
        print(f"  perf {k}: core {s.get('corePct')}% frame {s.get('msFrame')}ms "
              f"worst {s.get('worstMs')}ms alive {s.get('alive')} transient {s.get('transient')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
