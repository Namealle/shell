#!/usr/bin/env bash
# One performance sample of the desktop as a whole: both Quickshell processes
# thread by thread, the GPU, the CPU package temperature, and -- the part no
# outside tool can see -- the sky's own per-frame timings per output.
#
#   perf_sample.sh <label> [window_seconds] [outfile]
#
# It measures over a WINDOW rather than instantaneously, because a 30 fps
# renderer's cost is bursty: `top` with one iteration reports whatever the
# scheduler happened to be doing. The per-thread averages and the renderer's
# rolling averages cover the SAME window, so the two halves can be added up
# and compared.
#
# The renderer's half arrives through `starfield perf dump` on the sky's own
# IPC socket (see services/Starfield.qml). `dump` also restarts the window, so
# consecutive samples are consecutive intervals and a rising line is a leak
# rather than an average creeping up.
#
# NEVER pgrep -f here: this script's own command line contains the pattern and
# a -f match kills or counts the script itself. Match by NAME and read
# /proc/<pid>/cmdline instead.
set -u

LABEL="${1:-sample}"
WINDOW="${2:-20}"
OUT="${3:-}"

QML="${CAELESTIA_SHELL_DIR:-$HOME/.config/quickshell/caelestia}/starfield.qml"

sky=""
shell=""
for pid in $(pgrep -x qs); do
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    case "$cmd" in
        *starfield.qml*) sky="$pid" ;;
        *"-c caelestia"*) shell="$pid" ;;
    esac
done

pids=""
[ -n "$sky" ] && pids="$sky"
[ -n "$shell" ] && pids="${pids:+$pids,}$shell"
if [ -z "$pids" ]; then
    echo "perf_sample: no qs process found" >&2
    exit 1
fi

# Start the renderer's window at the same moment as top's.
[ -n "$sky" ] && qs -p "$QML" ipc call starfield perf on >/dev/null 2>&1

# top -n2 -d WINDOW: the first iteration is since-boot noise, the second is the
# average over exactly WINDOW seconds. -H = one row per thread.
raw=$(top -H -b -n2 -d "$WINDOW" -w 512 -p "$pids" 2>/dev/null)

dump=""
[ -n "$sky" ] && dump=$(qs -p "$QML" ipc call starfield perf dump 2>/dev/null)

gpu=$(nvidia-smi --query-gpu=utilization.gpu,clocks.gr,clocks.mem,power.draw,temperature.gpu \
      --format=csv,noheader,nounits 2>/dev/null | head -1)

tctl=""
for d in /sys/class/hwmon/hwmon*; do
    [ -r "$d/name" ] || continue
    read -r n < "$d/name" || continue
    [ "$n" = k10temp ] || continue
    for f in "$d"/temp*_label; do
        [ -r "$f" ] || continue
        IFS= read -r label < "$f"
        if [ "$label" = "Tctl" ] || [ "$label" = "Tdie" ]; then
            read -r milli < "${f%_label}_input" && tctl="$label $((milli / 1000)).$(( (milli % 1000) / 100 )) C"
            break 2
        fi
    done
done

emit() {
    printf '===== %s =====\n' "$LABEL"
    printf 'at        %s\n' "$(date -Is)"
    printf 'window    %ss\n' "$WINDOW"
    printf 'host      load %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
    [ -n "$gpu" ] && printf 'gpu       util/grMHz/memMHz/W/C  %s\n' "$gpu"
    [ -n "$tctl" ] && printf 'cpu temp  %s\n' "$tctl"
    for pid in $sky $shell; do
        [ -n "$pid" ] || continue
        name=sky
        [ "$pid" = "$shell" ] && name=shell
        up=$(ps -o etimes= -p "$pid" | tr -d ' ')
        rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)
        printf '\n-- %s (pid %s, up %ss, rss %s kB)\n' "$name" "$pid" "$up" "${rss:-?}"
        # Second top iteration only, threads of this pid, busiest first, and
        # only those that actually did something.
        # Fixed columns, NOT NF-relative: a thread called "Thread (pooled)"
        # has a space in COMMAND, and counting back from the end then reads
        # %MEM as %CPU. That silently inflated a process total by every idle
        # pooled thread in it.
        #   1=PID 2=USER 3=PR 4=NI 5=VIRT 6=RES 7=SHR 8=S 9=%CPU 10=%MEM 11=TIME+ 12..=COMMAND
        # top -H -p a,b prints every thread of BOTH processes with no column
        # saying which one owns it; the thread ids of this pid come from /proc.
        mine=$(ls "/proc/$pid/task" 2>/dev/null | tr '\n' ' ')
        printf '%s\n' "$raw" | awk -v pid="$pid" -v mine="$mine" '
            BEGIN{ n=split(mine, a, " "); for (i=1;i<=n;++i) own[a[i]]=1 }
            /^top - /{++iter}
            iter==2 && $1 ~ /^[0-9]+$/ && own[$1] {
                cmd=$12; for (f=13;f<=NF;++f) cmd=cmd"_"$f;
                total+=$9;
                if ($9+0 > 0.05 || $1 == pid) printf "%8.1f %s %s %s\n", $9+0, $1, cmd, $11
            }
            END{ printf "%8.1f %s %s %s\n", -1, "TOTAL", "process-total", total }' |
            sort -rn | awk '
                $2 == "TOTAL" { total=$4; next }
                shown++ < 12 { printf "   %-8s %-18s %6.1f%% of a core   cpu-time %s\n", $2, $3, $1, $4 }
                END { printf "   process total %.1f%% of one core\n", total }'
    done
    if [ -n "$dump" ]; then
        printf '\n-- sky per-frame, per output (ms on the main thread)\n'
        printf '%s' "$dump" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception as e:
    print("   (no dump: %s)" % e); raise SystemExit
if not isinstance(d, dict) or not d:
    print("   (no outputs registered)"); raise SystemExit
keys = ["sec","frames","fps","msFrame","msAdvance","msPhysics","msPublish","msEvents",
        "msParts","msRender","msBin","msLayout","msPaint","msPack","msUpload",
        "msAtlasTotal","msBinClear","msBinWalk","msBinGrid","msBinInsert",
        "msPackClear","msPackGrid","msPackInst","worstMs","corePct","atlases","paints","alive","live",
        "transient","kicks","glows","items","atlasH","events","pendingEvents",
        "entries","hashes","publications","missed","sentinel"]
names = [n for n in d if d[n]]
if not names:
    print("   (probe not running)"); raise SystemExit
w = max(len(k) for k in keys) + 2
print("   %-*s%s" % (w, "output", "".join("%14s" % n for n in names)))
print("   %-*s%s" % (w, "size", "".join("%14s" % ("%dx%d@%g" % (d[n]["w"], d[n]["h"], d[n]["dpr"])) for n in names)))
for k in keys:
    row = "".join("%14s" % d[n].get(k, "") for n in names)
    print("   %-*s%s" % (w, k, row))
tot = sum(d[n]["corePct"] for n in names)
print("   %-*s%14.1f" % (w, "SUM corePct", tot))
'
    fi
    printf '\n'
}

if [ -n "$OUT" ]; then
    emit | tee -a "$OUT"
else
    emit
fi
