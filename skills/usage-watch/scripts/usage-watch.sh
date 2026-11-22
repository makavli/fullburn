#!/usr/bin/env bash
# Usage watch: the user's /usage readings, plus the helpers run since, give an estimate of each usage bar.
#   plan [pro|ultra]          print the plan, or set it (Max is not supported)
#   start <name> <model>      a helper (or this session) starts: model fable, opus, sonnet or haiku
#   stop <name> | --all       it ended (--all: every one still logged as running)
#   reading <bar>=<pct> ...   a /usage reading, such as weekly=31 fable=40; refits each bar's rate
#   estimate                  each bar now, what runs, and what to do
#   rates                     points per helper-hour by model and bar, to size a swarm
# State: $USAGE_WATCH_HOME, or ~/.claude/usage-watch: plan, log, scale-<plan> (per bar: points, weighted hours).
set -euo pipefail
dir=${USAGE_WATCH_HOME:-$HOME/.claude/usage-watch}
log="$dir/log"
die() { echo "usage-watch: $*" >&2; exit 1; }
mkdir -p "$dir" && touch "$log"
now=${USAGE_WATCH_NOW:-$(date +%s)}  # the override is for the self-test
plan=$(cat "$dir/plan" 2>/dev/null || true)
sf="$dir/scale-$plan"

# One awk pass over the log. A bar named after a model counts only that model; every other bar counts all of them.
# Weights are cost per helper-hour relative to Opus, from API price ratios: Fable 2.5, Sonnet 0.6, Haiku 0.2.
calc() {
  awk -v mode="$1" -v now="$now" -v sf="$sf" '
    function wt(m) { return m == "fable" ? 2.5 : m == "opus" ? 1 : m == "sonnet" ? 0.6 : m == "haiku" ? 0.2 : 0 }
    function model_bar(b) { return b == "fable" || b == "opus" || b == "sonnet" || b == "haiku" }
    function counts(bar, m) { return model_bar(bar) ? bar == m : 1 }
    function hours(a, b, bar,   i, s, e, h) {  # weighted helper-hours between a and b that count on bar
      h = 0
      for (i = 1; i <= n; i++) {
        if (!counts(bar, mod[i])) continue
        s = st[i] > a ? st[i] : a; e = en[i] ? en[i] : now; if (e > b) e = b
        if (e > s) h += (e - s) / 3600 * wt(mod[i])
      }
      return h
    }
    function burn(bar,   k, b) { b = 0; for (k in run) if (counts(bar, mod[run[k]])) b += wt(mod[run[k]]); return b }
    function rate(bar) { return H[bar] > 0 ? P[bar] / H[bar] : -1 }
    BEGIN { while ((getline line < sf) > 0) { split(line, f, " "); P[f[1]] = f[2]; H[f[1]] = f[3]; bars[f[1]] = 1 } }
    $2 == "start" { n++; st[n] = $1; nm[n] = $3; mod[n] = $4; en[n] = 0; run[$3] = n }
    $2 == "stop" && ($3 in run) { en[run[$3]] = $1; delete run[$3] }
    $2 == "plan" { lt = ""; for (k in last) delete last[k] }  # a new plan: the old readings say nothing of it
    $2 == "reading" {
      pt = lt; lt = $1
      for (k in prev) delete prev[k]
      for (k in last) { prev[k] = last[k]; delete last[k] }
      for (i = 3; i <= NF; i++) { split($i, kv, "="); last[kv[1]] = kv[2] }
    }
    END {
      if (mode == "running") { for (k in run) print k; exit }
      if (mode == "refit") {
        for (k in last) {
          if (!(k in prev)) { printf "%s: first reading, %s%%\n", k, last[k]; continue }
          d = last[k] - prev[k]; h = hours(pt, lt, k)
          if (d < 0) { printf "%s: reset since the last reading (%s%% -> %s%%), rate kept\n", k, prev[k], last[k]; continue }
          if (h < 0.25) { printf "%s: +%s over %.2f weighted helper-hours: too little to refit, rate kept\n", k, d, h; continue }
          P[k] += d; H[k] += h; bars[k] = 1
          printf "%s: +%s over %.2f weighted helper-hours; rate now %.2f points per Opus helper-hour\n", k, d, h, rate(k)
        }
        for (k in bars) printf "%s %.6f %.6f\n", k, P[k], H[k] > (sf ".tmp")
        exit
      }
      if (mode == "rates") {
        for (k in bars) {
          if (rate(k) < 0) continue
          split("fable opus sonnet haiku", ms, " ")
          for (i = 1; i <= 4; i++) if (counts(k, ms[i])) printf "%s on %s: %.2f points per helper-hour\n", ms[i], k, rate(k) * wt(ms[i])
        }
        exit
      }
      # estimate
      r = 0; for (k in run) { r++; i = run[k]; printf "running: %s (%s, %.1f h)\n", k, mod[i], (now - st[i]) / 3600 }
      if (lt == "") { print "no reading yet: ask for the /usage reading"; exit }
      age = int((now - lt) / 60)
      for (k in last) {
        s = rate(k); h = hours(lt, now, k)
        if (s < 0) { printf "%s: %s%% read %d min ago; rate not measured yet (the next reading with helpers running sets it)\n", k, last[k], age; continue }
        e = last[k] + s * h
        printf "%s: about %.0f%% (read %s%% %d min ago, +%.1f since)", k, e, last[k], age, s * h
        b = burn(k) * s
        if (b > 0) printf "; at this burn, 100%% in about %.1f h", (100 - e) / b
        printf "\n"
        if (model_bar(k) && e >= 90) printf "LIMIT %s at 90%% or more: launch no more %s helpers; at 100%% the running ones die mid-job\n", k, k
        if (!model_bar(k) && e >= 93) printf "LIMIT %s at 93%% or more: launch nothing more; this session stops at 100%% too\n", k
      }
      if (r > 0 && age >= 20) printf "reading due: the last one is %d min old\n", age
    }' "$log"
}

case ${1:-} in
  plan)
    case ${2:-} in
      '') [ -z "$plan" ] || echo "$plan" ;;
      pro|ultra)
        if [ "$2" != "$plan" ]; then echo "$2" > "$dir/plan"; echo "$now plan $2" >> "$log"; fi
        # Seeds, Ultra only (one account's measurement, 2026-11-22): Opus 0.7 weekly points per helper-hour, Fable
        # 3.5 of its own bar; each worth one weighted hour, so the first real readings outweigh them fast.
        if [ "$2" = ultra ] && [ ! -s "$dir/scale-ultra" ]; then printf 'weekly 0.7 1\nfable 1.4 1\n' > "$dir/scale-ultra"; fi
        echo "$2" ;;
      max) die "Max is not supported: Pro or Ultra" ;;
      *) die "the plan is pro or ultra: $2" ;;
    esac ;;
  start)
    [[ "${2:-}" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "name: lowercase letters, digits and dashes: ${2:-}"
    case ${3:-} in fable|opus|sonnet|haiku) ;; *) die "model: fable, opus, sonnet or haiku: ${3:-}" ;; esac
    if calc running | grep -xF -- "$2" > /dev/null; then die "$2 is already running"; fi
    echo "$now start $2 $3" >> "$log" ;;
  stop)
    [ -n "${2:-}" ] || die "stop <name> or stop --all"
    if [ "$2" = --all ]; then names=$(calc running); else names=$(calc running | grep -xF "$2" || true); [ -n "$names" ] || die "$2 is not running"; fi
    for n in $names; do echo "$now stop $n" >> "$log"; done ;;
  reading)
    [ -n "$plan" ] || die "set the plan first: plan pro|ultra"
    shift; [ $# -gt 0 ] || die "give the bars, such as: reading weekly=31 fable=40"
    for r in "$@"; do
      [[ "$r" =~ ^[a-z][a-z0-9-]*=[0-9]{1,3}(\.[0-9]+)?$ ]] || die "not a bar=percent pair: $r"
      v=${r#*=}; [ "${v%%.*}" -le 100 ] || die "a percent is 0 to 100: $r"
    done
    echo "$now reading $*" >> "$log"
    rm -f "$sf.tmp"; calc refit
    if [ -f "$sf.tmp" ]; then mv "$sf.tmp" "$sf"; fi ;;
  estimate) [ -n "$plan" ] || die "no plan set: plan pro|ultra"; echo "plan: $plan"; calc estimate ;;
  rates) [ -n "$plan" ] || die "no plan set: plan pro|ultra"; calc rates ;;
  *) die "usage: usage-watch.sh plan [pro|ultra] | start <name> <model> | stop <name>|--all | reading <bar>=<pct>... | estimate | rates" ;;
esac
