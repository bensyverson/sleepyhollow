#!/bin/bash
# Runs the full suite N times (default 10) and collects every failure's
# identity, so intermittent tests get named instead of shrugged at.
#
#   scripts/flake-hunt.sh [iterations] [spinners]
#
# The second argument starts that many CPU spinners for the duration, which
# is how a quiet machine imitates the parallel-agent load the timing flakes
# were reported under (8 to 16 on an 8-core Mac stretches the suite 5-20x).
#
# Prints a green/red line per run and finishes with a tally of distinct
# "recorded an issue" lines across all runs. Exit 0 when every run was
# green, 1 otherwise. Requires the Claude Code sandbox to be off (swift
# builds refuse it — see project/gotchas.md).
set -u
cd "$(git rev-parse --show-toplevel)"

iterations="${1:-10}"
spinners="${2:-0}"
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
    if swift test --quiet > "$log" 2>&1; then
        echo "run $i: green"
    else
        red=$((red + 1))
        echo "run $i: RED"
    fi
done

echo
if grep -h "recorded an issue" "$logdir"/run*.log | sort | uniq -c | sort -rn; then
    :
else
    echo "no issues recorded in $iterations runs"
fi
echo "logs: $logdir"
[ "$red" -eq 0 ]
