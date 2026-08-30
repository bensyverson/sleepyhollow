#!/bin/sh
# measure-host-group.sh — what a shared WKWebsiteDataStore buys a group of PageHosts.
#
#   scripts/measure-host-group.sh [LOADS] [SCRIPT_BYTES]
#
#     LOADS         how many page loads each arrangement performs   (default 6)
#     SCRIPT_BYTES  the size of the page's one script, in bytes     (default 3400000,
#                   the figure the Woodcase harness reported)
#
# Prints two tables:
#
#   1. how many times the server is asked for a script two loads both reference,
#      for each store-and-process arrangement — this is the table in
#      project/2026-08-29-host-group-cache.md;
#   2. per-load milliseconds and script fetches for LOADS fresh PageHosts against
#      LOADS members of one HostGroup.
#
# Set SLEEPY_MEASURE_ORDER=group to run the grouped arm first: the two arms run
# in one process, so order matters and the figure only means something when both
# orders agree. A throwaway warm-up load runs before either arm.
#
# It drives the opt-in `HostGroup measurement` suite (Tests/SleepyHollowTests/
# HostGroupMeasurementTests.swift), which is skipped by an ordinary `swift test`.
#
# Report the machine's load average with any figure: WebKit stretches 20-50x
# under parallel-agent load (project/2026-08-28-wait-test-timing.md), so an
# absolute number from a busy machine is an upper bound, and only the ratio
# between the two arrangements travels.
set -eu

LOADS="${1:-6}"
SCRIPT_BYTES="${2:-3400000}"

echo "load average: $(uptime | sed 's/.*load averages*: //')"
echo

SLEEPY_MEASURE=1 \
SLEEPY_MEASURE_LOADS="$LOADS" \
SLEEPY_MEASURE_SCRIPT_BYTES="$SCRIPT_BYTES" \
    swift test --filter 'HostGroupMeasurementTests' 2>&1 |
    grep -v '^􀄵\|^Test Suite\|^	 Executed'
