#!/bin/bash
# Samples the "shot straight after document.fonts.ready" race many times under
# CPU load, so the finding in project/2026-08-29-paint-after-fonts-ready.md is
# a count rather than an anecdote.
#
#   scripts/paint-race-hunt.sh [iterations] [spinners]
#
# Spinners default to 0, and that is usually right. This Mac normally carries
# several agents' suites at once, so the load is already ambient; adding
# synthetic spinners on top inflates every other agent's timings and has
# deadlocked WebKit session tests machine-wide (2026-08-29). Pass a spinner
# count only on a genuinely quiet machine.
#
# Each iteration runs only the two font suites, which is ten tests and eleven
# samples of the race — far more samples per minute than running the whole
# suite, at the cost of the in-process WebKit contention a full run adds. Use
# scripts/flake-hunt.sh for that half.
#
# Record the load average alongside any figure this produces: with ambient
# load it is what makes the run reproducible, and at a load average near 400
# WebKit's content processes are starved rather than stretched — observed
# 2026-08-29, a filtered run making no progress for minutes.
#
# Prints a green/red line per run, echoes every [paint] measurement, and
# finishes with a tally of distinct "recorded an issue" lines. Exit 0 when
# every run was green. Requires the Claude Code sandbox to be off.
set -u
cd "$(git rev-parse --show-toplevel)"

iterations="${1:-20}"
spinners="${2:-0}"
filters=(--filter CapturePaintAfterFontsReadyTests --filter WaitFontsStatusTests)
logdir="$(mktemp -d)"
red=0

loadpids=()
for _ in $(seq 1 "$spinners"); do
    yes > /dev/null &
    loadpids+=($!)
done
cleanup() {
    for pid in ${loadpids+"${loadpids[@]}"}; do kill "$pid" 2>/dev/null; done
}
trap cleanup EXIT

for i in $(seq 1 "$iterations"); do
    log="$logdir/run$i.log"
    if swift test "${filters[@]}" > "$log" 2>&1; then
        echo "run $i: green"
    else
        red=$((red + 1))
        echo "run $i: RED"
    fi
    grep -h "\[paint\]" "$log" | sed "s/^/  /"
done

echo
echo "runs: $iterations, red: $red, spinners: $spinners"
grep -h "recorded an issue" "$logdir"/run*.log | sort | uniq -c | sort -rn
echo "logs: $logdir"
[ "$red" -eq 0 ]
