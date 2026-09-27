#!/bin/zsh
# Shows WebKit throttling an idle session's content process, and whether a
# verb still answers once it has.
#
#   scripts/idle-throttle-probe.sh [idle-seconds] [verb]
#
# Opens a session on a fixture page, runs one eval, then prints the web
# content process's per-thread priorities (`ps -M`) every half second for the
# idle period, and finally runs `<verb> --session` (default `shot`) with a
# 20 s budget, printing its exit status and wall time. Measured 2026-09-26
# (job leaf 116NLb): the priority reads 31-47 for about a second after the
# eval, then 4 (some runs settle at 20); on a loaded machine an unheld shot/pdf/archive then timed out,
# and with `PageHost.holdingForeground` it answers in ~0.1 s.
#
# Needs a built `sleepy` (`swift build`) and the Claude Code sandbox off
# (`sleepy` binds a Unix socket; `log show` reads the system log). Record the
# load average with any figure you quote from it.
set -u
cd "$(git rev-parse --show-toplevel)"

idle="${1:-3}"
verb="${2:-shot}"
sleepy=".build/debug/sleepy"
home="$(mktemp -d)"
export SLEEPYHOLLOW_HOME="$home"
name="probe$$"
url="file://$PWD/Tests/TestSupport/Fixtures/form.html"

now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

"$sleepy" open "$url" --name "$name" --budget 60000 > /dev/null || exit 1
helper="$(pgrep -f "_host --name $name")"
content="$(/usr/bin/log show --last 1m --style compact --predicate "processID == $helper" 2>/dev/null \
    | grep -o 'WebContent\[[0-9]*\]' | head -1 | tr -dc 0-9)"
echo "helper $helper, web content $content; $(uptime | sed 's/.*load/load/')"

"$sleepy" eval --session "$name" --js 'return 1;' > /dev/null
start="$(now)"
while (( $(now) - start < idle )); do
    printf "+%5.2fs  priorities:" "$(( $(now) - start ))"
    ps -M -p "$content" | awk 'NR > 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+[A-Z]+$/) { print $i; break } }' | sort -n | uniq -c | awk '{ printf " %s×%s", $1, $2 }'
    echo
    sleep 0.5
done

start="$(now)"
"$sleepy" "$verb" --session "$name" --out "$home/out.bin" --budget 20000 > /dev/null 2>&1
code=$?
printf "%s --session after %ss idle: exit %s in %.2fs\n" "$verb" "$idle" "$code" "$(( $(now) - start ))"
"$sleepy" close "$name" > /dev/null 2>&1
rm -rf "$home"
