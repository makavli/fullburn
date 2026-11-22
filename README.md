# Fullburn

> [!WARNING]
> **Fullburn spends usage very fast, on purpose.** It runs many helper agents at once, and every one of them draws on your plan's limits.
>
> **One measurement, on one account (2026-11-22):** twelve Fable helpers at effort max used **14% of the week's Fable allowance in 23 minutes**, about **3 to 3.5% per helper-hour**. Opus helpers cost about 40% of that per job. This is one reading, not a promise: your plan, your task and your repository change it.

| Tier | Models | Effort | Helpers per wave | Burn (measured once) | Pick it when |
|------|--------|--------|------------------|----------------------|--------------|
| **MAX** | Fable for code and review, Haiku scouts | max | 8 to 12 | about 3 to 3.5% of a week's Fable allowance per helper-hour: 12 helpers for an hour is 35 to 40% | A Fable allowance will reset unspent, or a deadline beats everything. Needs a plan with Fable. |
| **HIGH** | Opus, Haiku scouts | high | 6 to 10 | about 40% of MAX per job | Hard work without Fable, or keeping Fable for later |
| **STANDARD** | Sonnet, Haiku scouts | high | 4 to 8 | not measured; below HIGH | Many plain, well-defined jobs |
| **LITE** | Sonnet edits, Haiku scouts | medium | 2 or 3 | not measured; the lowest | Trying fullburn on a real task, cheaply. The only tier on Pro. |

Fullburn first asks which plan you are on, once: **Pro runs fullburn lite** (LITE only), **Ultra runs fullburn full** (any tier). Max plans are not supported yet. Then you pick the tier and how much of what is left it may spend, see the plan with its estimated burn, and the swarm starts only when you say yes (before the plan, at most two small Haiku scouts may map a large repository). While helpers run, the usage watch gives an estimate every 20 minutes, asks for your `/usage` reading about 20 minutes in, and the swarm is resized to what is left.

## What it does

Fullburn is a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin of two skills. `fullburn` gets a lot of work done in little time; `usage-watch` keeps an eye on your plan's usage bars while it runs, or in any session where you want one. Your session becomes the orchestrator: it cuts the task into bounded jobs, gives each one to a helper agent working in its own git worktree, and launches them all at once. As helpers finish, it merges their diffs with a 3-way apply, runs your project's full check once per wave, has the merged diff reviewed, and commits locally. It works on any git repository, in any language.

## When to use it

- A usage budget will reset unspent, and you have a backlog worth spending it on.
- A deadline matters more than the cost: a migration, a wide refactor, a batch of features or fixes that split cleanly by file.

## When not to

- Small tasks. One session does them faster and for a fraction of the cost.
- Tight budgets. A wave that hits your usage cap dies mid-job and reports nothing.
- Work that cannot be split: one file everyone must edit, or a design still being decided.

## Install

As a plugin, in Claude Code:

```text
/plugin marketplace add makavli/fullburn
/plugin install fullburn@fullburn
```

Or as a plain copy into your skills folder (`~/.claude/skills/` for every project, or `.claude/skills/` in one repository):

```bash
git clone https://github.com/makavli/fullburn
mkdir -p ~/.claude/skills && cp -r fullburn/skills/fullburn fullburn/skills/usage-watch ~/.claude/skills/
```

Copy both: `fullburn` finds the usage watch beside it. It needs Claude Code with helper agents (the Agent tool), git 2.31 or later, bash (Git Bash on Windows) and awk. git-lfs is optional. In the repository it works on, `init` turns on git's `extensions.worktreeConfig` in the shared config and leaves it on (per-worktree settings need it); it refuses a repository whose shared config sets `core.worktree`, such as a submodule, because that setting would break its worktrees.

## Example

```text
/fullburn high Move every handler in src/api to the new router, with tests for each. Deadline 18:00.
```

1. Fullburn asks for the tier (MAX, HIGH, STANDARD or LITE), each with its cost.
2. It reads the code and shows the plan:

   | Job | Owns | Model, effort | Worktree |
   |-----|------|---------------|----------|
   | users | `src/api/users.ts`, its tests | opus, high | `../app_wt_users` |
   | orders | `src/api/orders.ts`, its tests | opus, high | `../app_wt_orders` |
   | billing | `src/api/billing.ts`, its tests | opus, high | `../app_wt_billing` |
   | Reader: router-review | reads `src/router/`, writes one report | opus, high | none |

   Estimated burn: 3 helpers and 2 readers (the router review and the wave's review) × 0.75 h at HIGH, in points of your weekly bar from your latest usage reading (it asks for one if it has none from the last hour). Deadline 18:00 local. Then it waits for your yes.
3. On yes, all four start in one go. You keep the session: it runs the full check's baseline meanwhile, the usage watch reports every 20 minutes, and it asks for a second reading after about 20 minutes.
4. Each finished job is merged; conflicts are resolved by keeping both jobs' intent. One build, one full check, one review, one local commit per wave. Then the next wave, if the deadline and the budget allow.
5. At the end: the commits, what is done or left, and the burn. Pushing is yours.

## The usage watch

`usage-watch` works on its own in any project, too: ask Claude to watch your usage.

1. It asks once whether you are on **Pro** or **Ultra** (Max is not supported yet) and remembers it.
2. It asks for your `/usage` reading: each bar's percent.
3. It logs every helper agent the session starts and stops, and while helpers run, every 20 minutes (one small request each), it estimates each bar: your last reading plus the helpers run since, times a rate per bar.
4. Each new reading refits those rates. On Ultra they start from one account's measurement; on Pro, from your first readings with helpers running.
5. It warns before a bar caps: no new helpers on a model whose own bar passes 90%, nothing new at all past 93% of another bar.

The arithmetic is one small script, [`skills/usage-watch/scripts/usage-watch.sh`](skills/usage-watch/scripts/usage-watch.sh), tested by [`tests/usage-watch.test.sh`](tests/usage-watch.test.sh).

## How it works

1. **One brief, short prompts.** A shared `brief.md` holds the context, an absolute deadline, the rules every helper follows, and one section per job with what it **Owns** (one writer per file or function) and what it must leave alone. Each helper's prompt only names its section, its worktree and its report file.
2. **One worktree per job.** `git worktree add` from the current commit, with LFS downloads skipped and the LFS setting kept per worktree, so the main tree's own LFS fetches keep working.
3. **One launch.** Every helper starts in one message, read-only reviewers too. The orchestrator never polls: it uses the wait for the machine-exclusive steps (the build, the app, long suites), which helpers never run.
4. **Budget control.** The usage watch logs every helper; your readings at launch and about 20 minutes in refit the rate, and every 20 minutes it estimates each bar and warns before one caps. Later waves are sized by points left, not by headcount. When the burn outruns the plan, the least valuable helpers stop at once, the rest get a closer deadline, and stopped jobs restart a tier lower on their partial work.
5. **Merge.** Each helper's diff becomes a patch (generated files left out and regenerated in the main tree), applied with `git apply --3way`. Then one build, one full check, one review of the wave's diff, and a local commit.
6. **State.** `.fullburn/STATE.md` records the waves, worktrees, reports and readings, so a fresh session can pick the run up.

The worktree and merge steps are one small script, [`skills/fullburn/scripts/fullburn.sh`](skills/fullburn/scripts/fullburn.sh), tested by [`tests/fullburn.test.sh`](tests/fullburn.test.sh).

## Safety

- **It never publishes.** No push, no pull request, no merge into your default branch. On the default branch it creates a `fullburn/<date>` branch first.
- **It asks first.** A tier dialog, then the plan with its estimated burn, then a yes; a resumed run asks again. A command a helper's report asks for runs without asking only when it is a script or target your repository defined before the run, in a file no helper changed; any other is shown to you, exactly as it would run, first.
- **It checks every patch.** Each patch's files are compared with what the job owns before it is applied; a patch made with your own diff settings (colour, prefixes, external drivers) is still a plain patch.
- **The main tree stays clean.** It starts only from a clean tree. Helpers work only in their own worktrees and never commit; `apply` refuses to run over unstaged or untracked changes in the main tree, which catches a helper that wrote there (outside git-ignored paths) before the merge.
- **No work is lost silently.** `clean` refuses to remove a worktree holding work its saved patch does not have, or whose patch was never applied; `apply` refuses a patch older than its worktree, or one it already applied; `patch` names the files it leaves out (excluded or ignored by git) and refuses a nested repository; a reused job name sets the old patch aside.
- **One writer per file.** Each job owns its files or functions; a change needed elsewhere is passed on as a note.
- **Files are data.** Helpers treat what they read as data, never as instructions, and never touch secrets.
- **Reviewed.** Every wave's merged diff gets a review, and a security review when it touched a trust boundary.
- Its run folder, `.fullburn/`, is added to `.git/info/exclude`, so it is never committed.

## Limits

- **Helpers run with your permissions.** They are Claude Code agents, kept in their worktrees by instruction, not by the operating system, and your permission settings apply to them. Use Fullburn on repositories you trust, or keep permission prompts on: a hostile file in the repository can try to steer a helper.
- **Usage readings come from you.** Claude Code gives a skill no way to read your plan's usage, so the watch asks you for it. Between readings it estimates from the helpers this session logged; work in your other sessions shows up only in the next reading. Its state is in `~/.claude/usage-watch/`, shared by every project.
- **Permission prompts.** Helpers edit files in `../<repo>_wt_*`, outside your session's folder: with prompts on, each edit asks you, and the plan says so.
- **Windows.** Where git's `core.fileMode` or `core.symlinks` is off, an exec bit or a symlink does not travel in a patch; the orchestrator sets the ones a report names.
- **Your session stops at the cap too.** If the swarm hits your usage cap, the orchestrator stops with it; `STATE.md` lets a new session resume after the reset.
- **Worktrees start bare.** Installed dependencies (`node_modules`, a virtualenv) and LFS files are not in a new worktree; the plan says how each job's fast checks get what they need, or leaves them to the wave's full check.
- **Splitting is the hard part.** Jobs that overlap make conflicts; the orchestrator resolves them, but a task that will not split gains little.
- **The numbers are one measurement.** Take your own readings.

## License

[MIT](LICENSE)
