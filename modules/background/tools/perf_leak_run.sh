#!/usr/bin/env bash
# Is the sky's per-frame cost FLAT or RISING? Restart it clean, then take a
# 30-second sample at 1, 5, 30 and 60 minutes with nothing fired by hand. A
# rising ms/frame, or a rising alive/transient/kick/event count, is a leak; a
# flat line is a cost, and a cost is what the optimisation work is for.
#
#   perf_leak_run.sh <outfile> [label]
#
# `perf dump` restarts the rolling window, so each sample is its own interval
# rather than a running average that would hide a slope.
set -u

OUT="${1:?usage: perf_leak_run.sh <outfile> [label]}"
LABEL="${2:-leak run}"
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HOME/namealle/scripts/starfield-shell" kill >/dev/null 2>&1
sleep 2
"$HOME/namealle/scripts/starfield-shell" start >/dev/null 2>&1
sleep 5
start=$(date +%s)

{
    printf '########## %s\n' "$LABEL"
    printf 'fresh start at %s\n' "$(date -Is)"
    printf 'no events fired by hand; meteors, comets and satellites are enabled in his starfield.json and fire on their own\n\n'
} >> "$OUT"

for minute in 1 5 30 60; do
    target=$((start + minute * 60))
    now=$(date +%s)
    while [ "$now" -lt "$target" ]; do
        sleep 10
        now=$(date +%s)
    done
    bash "$HERE/perf_sample.sh" "T+${minute} min" 30 "$OUT" >/dev/null 2>&1
done

printf 'leak run finished %s\n\n' "$(date -Is)" >> "$OUT"
