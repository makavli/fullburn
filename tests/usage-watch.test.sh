#!/usr/bin/env bash
# Self-test of scripts/usage-watch.sh in a throwaway state folder, with a fake clock: the plan, the helper log,
# estimates from the seeds, a refit from a reading, the limits, a reset, and Pro with no seeds.
set -uo pipefail

uw="$(cd "$(dirname "$0")/.." && pwd)/skills/usage-watch/scripts/usage-watch.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export USAGE_WATCH_HOME="$tmp/state"
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
t0=1800000000
at() { local t=$1; shift; USAGE_WATCH_NOW=$((t0 + t)) bash "$uw" "$@"; }  # at <seconds after t0> <command...>
has() { grep -qF -- "$1" <<< "$2"; }

check "no plan prints nothing" "[ -z \"\$(at 0 plan)\" ]"
check "Max is refused" "! at 0 plan max >/dev/null 2>&1"
check "a reading needs the plan" "! at 0 reading weekly=10 >/dev/null 2>&1"
check "Ultra is recorded with its seeds" "[ \"\$(at 0 plan ultra)\" = ultra ] && [ \"\$(at 0 plan)\" = ultra ] && grep -qx 'weekly 0.7 1' \"$tmp/state/scale-ultra\""
# shellcheck disable=SC2034  # read inside check's eval; awk -v would read this backslash as an escape
bs="$tmp\\bs"
check "a backslash in the state path" "USAGE_WATCH_HOME=\"\$bs\" bash \"$uw\" plan ultra >/dev/null && [ -n \"\$(USAGE_WATCH_HOME=\"\$bs\" bash \"$uw\" rates)\" ]"
check "a bad model is refused" "! at 0 start alpha gpt >/dev/null 2>&1"
check "a bad reading is refused" "! at 0 reading weekly=abc >/dev/null 2>&1 && ! at 0 reading weekly=140 >/dev/null 2>&1 && ! at 0 reading weekly=100.9 >/dev/null 2>&1"

at 0 start alpha fable && at 0 start beta opus
check "a helper cannot start twice" "! at 0 start alpha fable >/dev/null 2>&1"
check "the first reading is recorded" "has 'fable: first reading, 20%' \"\$(at 0 reading weekly=10 fable=20)\""

# Two hours of one Fable and one Opus helper, from the seeds: Fable bar 20 + 3.5 x 2 = 27; weekly 10 + (1.75 + 0.7) x 2 = 14.9.
# shellcheck disable=SC2034  # e and r are read inside check's eval
e=$(at 7200 estimate)
check "estimate from the seeds" "has 'fable: about 27%' \"\$e\" && has 'weekly: about 15%' \"\$e\""
check "estimate lists what runs" "has 'running: alpha (fable, 2.0 h)' \"\$e\" && has 'running: beta (opus, 2.0 h)' \"\$e\""
check "estimate says a reading is due" "has 'reading due' \"\$e\""
check "estimate gives the time to the cap" "has '100% in about' \"\$e\""

# The reading refits: Fable bar +10 over 5 weighted hours, plus the seed (1.4 over 1) = 11.4 / 6 = 1.9 per Opus hour.
# shellcheck disable=SC2034
r=$(at 7200 reading weekly=16 fable=30)
check "a reading refits each bar" "has 'fable: +10 over 5.00 weighted helper-hours; rate now 1.90' \"\$r\""
check "rates follow the refit" "has 'fable on fable: 4.75 points per helper-hour' \"\$(at 7200 rates)\""
check "the Fable bar counts only Fable" "! has 'opus on fable' \"\$(at 7200 rates)\""

at 7200 stop alpha
check "stop ends one helper" "! has 'running: alpha' \"\$(at 7300 estimate)\" && has 'running: beta' \"\$(at 7300 estimate)\""
check "stopping a helper not running is refused" "! at 7300 stop alpha >/dev/null 2>&1"
at 7300 stop --all
check "stop --all ends the rest" "! has 'running:' \"\$(at 7400 estimate)\""

check "too little helper time does not refit" "has 'too little to refit' \"\$(at 7400 reading weekly=20 fable=31)\""
check "near the caps, the limits" "e=\$(at 7400 reading weekly=94 fable=91 >/dev/null; at 7400 estimate); has 'LIMIT fable' \"\$e\" && has 'LIMIT weekly' \"\$e\""
check "a reset keeps the rate" "has 'weekly: reset since the last reading' \"\$(at 9000 reading weekly=5 fable=2)\" && has 'fable on fable: 4.75' \"\$(at 9000 rates)\""

at 9000 plan pro >/dev/null
check "Pro starts with no seeds" "[ ! -s \"$tmp/state/scale-pro\" ] && [ -z \"\$(at 9000 rates)\" ]"
at 9000 start gamma sonnet
check "a new plan starts its readings afresh" "has 'weekly: first reading' \"\$(at 9000 reading session=10 weekly=5)\""
check "Pro says the rate is not measured yet" "has 'rate not measured yet' \"\$(at 10800 estimate)\""
at 10800 reading session=13 weekly=6 >/dev/null
check "Pro's first readings with a helper set the rate" "has 'sonnet on session: 6.00 points per helper-hour' \"\$(at 10800 rates)\""
check "switching back to Ultra keeps its rates" "at 10800 plan ultra >/dev/null && has 'fable on fable: 4.75' \"\$(at 10800 rates)\""

if [ "$fails" -eq 0 ]; then echo "usage-watch.test.sh: all passed"; else echo "usage-watch.test.sh: $fails failed"; exit 1; fi
