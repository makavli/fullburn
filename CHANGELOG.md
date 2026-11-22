# Changelog

## Unreleased

- The evals keep usage-watch's state inside their test repository (their scaffold writes a project
  `.claude/settings.json` that sets `USAGE_WATCH_HOME`), so a run never writes to the real `~/.claude/usage-watch`.
- README: Fullburn is also listed in Fewkit; one marketplace, not both.

## 1.1.0 (2026-11-22)

- **Two strikes.** A job whose check failed gets at most one relaunch, briefed with the failure (expected and saw), its Owns and the approaches already tried; the same failure twice stops it and goes to the user. A merged job is never rerun. At a wave's close, the same check failing the same way twice reverts the job that broke it instead of a third fix.

## 1.0.0 (2026-11-22)

- First release: the `fullburn` skill (Pro runs it lite, Ultra in full; tiers MAX, HIGH, STANDARD, LITE; plan, budget
  and yes before launch, asked again on resume; one brief; one worktree per job; budget control; 3-way merge with
  each patch checked against the job's files; one check, review and local commit per wave; a state file to resume).
- The `usage-watch` skill: asks the plan once (Pro or Ultra), logs the helpers, turns /usage readings into estimates
  every 20 minutes while helpers run, refits its rates from each reading, and warns before a bar caps.
- `scripts/fullburn.sh`: `init`, `add`, `patch`, `apply`, `clean`, safe under the user's own git and diff settings,
  refusing submodules, nested repositories, stale or repeated patches and unapplied work; with its self-test.
- `scripts/usage-watch.sh`: `plan`, `start`, `stop`, `reading`, `estimate`, `rates`, with its self-test.
