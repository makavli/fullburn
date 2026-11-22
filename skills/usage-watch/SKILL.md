---
name: usage-watch
description: Watch a Claude plan's usage bars during a session. Asks once whether the account is on Pro or Ultra, logs the helper agents the session runs, turns the user's /usage readings into an estimate every 20 minutes while helpers run, and warns before a bar caps. Use when the user asks to watch, track or estimate usage, before a swarm or a long run of helper agents, and from fullburn, which reads the plan from it.
argument-hint: "[start|reading <bars>|stop]"
license: MIT
---

# Usage watch

Claude Code gives a skill no way to read the plan's usage, so the user's `/usage` readings are the truth. This skill fills the time between them: the last reading, plus the helpers logged since, times a rate per bar that each new reading refits. Usage belongs to the account, so work in the user's other sessions shows up only in the readings.

- `$WATCH` is `bash "${CLAUDE_SKILL_DIR}/scripts/usage-watch.sh"` (`${CLAUDE_SKILL_DIR}` is this skill's base directory): `plan`, `start`, `stop`, `reading`, `estimate`, `rates`. Its state is in `~/.claude/usage-watch/` (or `$USAGE_WATCH_HOME`), shared by every project.
- Load `CronCreate`, `CronDelete` and `CronList` with ToolSearch when the harness lists them as deferred.

## 1. The plan

`$WATCH plan` prints `pro` or `ultra`. If it prints nothing: when the user has already named the plan, use that; otherwise one AskUserQuestion, header "Plan", question "Which Claude plan is this account on?", options **Pro** and **Ultra**. Record it: `$WATCH plan <pro|ultra>`. Max is not supported: if the user names it, say so and stop. When the user says their plan changed, record the new one: its readings start afresh, and each plan keeps its own rates.

Then `$WATCH estimate`. Helpers it lists as running from an earlier session died with it: `$WATCH stop --all`.

## 2. Readings

Ask in one line: "Send your /usage reading: each bar's percent, for example weekly 31%, Fable 40% (a screenshot works)." Record it: `$WATCH reading weekly=31 fable=40`, one lowercase word per bar as /usage names it. A bar named after a model (`fable`) counts only that model's helpers; every other bar counts all of them. It prints, per bar, the rate refitted from the helper time since the last reading.

Ask for one at the start, about 20 minutes after helpers launch, at each wave or each hour of helper work after that, after a reset, and whenever `estimate` says one is due. Record a reading the user sends unasked the same way.

## 3. Log the helpers

- Right before launching helper agents: `$WATCH start <name> <model>` for each one (model `fable`, `opus`, `sonnet` or `haiku`). When a swarm starts, also `$WATCH start session <your model>`: an orchestrating session costs about one more helper.
- When a helper finishes or is stopped: `$WATCH stop <name>`; `session` when the swarm ends.

## 4. Watch

While helpers run, keep one recurring CronCreate job (CronList first: one per session) every 20 minutes, off the hour (`7,27,47 * * * *`), with this prompt, the script's absolute path filled in:

```text
Usage watch: run bash "<absolute path of usage-watch.sh>" estimate, tell me its lines, and act on them as the usage-watch skill says.
```

Tell the user in one line: every 20 minutes while helpers run, one small request each, gone when the session ends.

At each run, give the user the estimate in at most three lines, then act:

- **LIMIT on a model's bar** (90%): launch no more helpers on that model. At 100% the running ones die mid-job with nothing reported: stop any whose report the "100% in about" time would not leave room for.
- **LIMIT on another bar** (93%): launch nothing more; this session stops at 100% too.
- **reading due**: ask for one.

When the last helper has stopped and none is planned, CronDelete the job; also when the user says stop.

## 5. Sizing

`$WATCH rates` prints points per helper-hour by model and bar, for a swarm's plan: points ≈ helpers × hours × rate. Say where the rates come from when you quote them. Until readings refit them they are seeds: on Ultra, one account's measurement of 2026-11-22 (a Fable helper at effort max about 3.5 points of the Fable bar an hour and 1.75 of the weekly; an Opus helper about 0.7 of the weekly), with Sonnet and Haiku from API price ratios (0.6 and 0.2 of Opus); on Pro, none, until the first readings with helpers running. The rates assume high or max effort; lower effort costs less, and the readings show it.
