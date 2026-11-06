#!/bin/zsh
# Measures whether a live hosted WKWebView's Core Animation layer tree can be
# rendered by CARenderer with true CSS 3D, and what that costs (job leaf
# B3dXgQ; findings in project/2026-11-06-compositor-capture.md).
#
#   scripts/compositor-probe.sh <mode> [args]
#
# Modes: tree t3d flat media fullpage readiness bench [N] anim idle controls spi
# (run with no mode to list them). Each prints its figures prefixed
# `[mode]` together with the load average, and writes its PNGs to
# .build/compositor-probe/out/.
#
# The probe is compiled together with Sources/SleepyHollow (one module, so it
# drives the real PageHost, ShotOperation and wait engine without touching the
# package manifest). It needs the Claude Code sandbox off: WebKit cannot start
# inside it. Cap a run at 5 minutes (project/gotchas.md).
set -eu
cd "$(git rev-parse --show-toplevel)"

build=".build/compositor-probe"
binary="$build/probe"
mkdir -p "$build/out"

sources=(Sources/SleepyHollow/**/*.swift scripts/compositor-probe/*.swift)
newest="$(ls -t $sources | head -1)"
if [[ ! -x "$binary" || "$newest" -nt "$binary" ]]; then
    echo "[build] compiling ${#sources} files…" >&2
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
    SDKROOT="$sdk" xcrun --sdk macosx swiftc -Onone -swift-version 6 -module-name CompositorProbe -sdk "$sdk" \
        -target "$(uname -m)-apple-macos13.0" \
        $sources -o "$binary"
fi

PROBE_OUT="$build/out" PROBE_FIXTURES="scripts/compositor-probe/fixtures" exec "$binary" "$@"
