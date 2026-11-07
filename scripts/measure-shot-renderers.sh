#!/bin/sh
# measure-shot-renderers.sh — what each of shot's renderers costs.
#
#   scripts/measure-shot-renderers.sh [CAPTURES]
#
#     CAPTURES  captures per arm, after one warm-up of every arm (default 20)
#
# Prints the median and p90 milliseconds of three arms at 1x and 2x on one
# live 1280x800 page (compositor-t3d.html): the compositor's image alone
# (presentation-update wait, CARenderer, readback), the compositor render
# stage as `shot` runs it (adding the <video> check), and the takeSnapshot
# fallback's render stage (snapshot, flattened-3D check, re-rasterize).
#
# Set SLEEPY_MEASURE_ORDER=snapshot to run the arms in reverse: they share
# one process, so order matters and a figure only means something when both
# orders agree (project/gotchas.md, 2026-08-29).
#
# It drives the opt-in `Shot renderer measurement` suite
# (Tests/SleepyHollowTests/ShotRendererMeasurementTests.swift), skipped by an
# ordinary `swift test`. A debug build, like every test run: absolute figures
# are an upper bound on a release `sleepy`. Needs the Claude Code sandbox off
# (WebKit cannot start inside it); cap the run at 5 minutes.
#
# Report the machine's load average with any figure: WebKit stretches 20-50x
# under parallel-agent load (project/2026-08-28-wait-test-timing.md).
set -eu

CAPTURES="${1:-20}"

echo "load average: $(uptime | sed 's/.*load averages*: //')"

SLEEPY_MEASURE=1 \
SLEEPY_MEASURE_CAPTURES="$CAPTURES" \
    swift test --filter 'ShotRendererMeasurementTests' 2>&1 |
    grep '^\[shot-renderers\]\|error'

echo "load average: $(uptime | sed 's/.*load averages*: //')"
