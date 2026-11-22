# Tiers

## The dialog

**Pro runs fullburn lite** (LITE only); **Ultra runs fullburn full** (all four tiers). On Ultra, one AskUserQuestion with two questions, the tier and the budget; on Pro, the budget question alone.

The tier question: header "Tier", these four options in this order. Picking one also covers at most two Haiku scouts that map a large repository before the plan; nothing else starts before the go. Mark one "(Recommended)" only when the case is clear: LITE on a first run in this repository (no commit matches `git log --grep '^fullburn wave' -1`); MAX when the user wants a Fable allowance spent before it resets; otherwise none.

| Label | Description |
|-------|-------------|
| MAX: Fable at max | Fastest and costliest. Measured once: about 3 to 3.5% of a week's Fable allowance per helper-hour; 12 helpers for an hour is 35 to 40%. Needs a plan with Fable. |
| HIGH: Opus | About 40% of what a job costs at MAX, measured once. Up to 10 helpers. |
| STANDARD: Sonnet | Cheaper again; not measured, so the 20-minute reading sets its rate. Up to 8 helpers. |
| LITE: Haiku and Sonnet | 2 or 3 helpers: the cheap way to try fullburn on a real task, and the tier on Pro. |

The budget question: header "Budget", "How much of what is left before the reset may this run spend?", options **All of it**, **About half**, **About a quarter**, each described as that share of the points left; the user can type their own.

## What each tier launches

| Tier | Code helpers | Readers and the wave review | Scouts | Helpers per wave | Next tier down |
|------|--------------|-----------------------------|--------|------------------|----------------|
| MAX | `fable`, effort `max` | `fable`, `max` | `Explore`, `haiku` | 8 to 12 | HIGH |
| HIGH | `opus`, `high` | `opus`, `high` | `Explore`, `haiku` | 6 to 10 | STANDARD |
| STANDARD | `sonnet`, `high` | `sonnet`, `high` | `Explore`, `haiku` | 4 to 8 | LITE |
| LITE | `sonnet`, `medium` | `sonnet`, `medium` | `Explore`, `haiku` | 2 or 3 | none: stop and report |

- Code helpers and readers are `general-purpose` Agent calls with this `model` and `effort`. Scouts are `Explore` calls on `haiku` with no effort set (a `general-purpose` call on `haiku` where `Explore` is missing).
- The helper count is a ceiling. The budget sets the real number (below), and a job too small to fill a helper joins another job.
- **Next tier down** is the fallback: when the tier's model is not available, and when the burn outruns the plan (SKILL.md, step 5). Offer it, then show the plan again for a new go.

## Estimating the burn

Burn ≈ helpers × hours each helper runs × rate. A helper runs until its job is done or the deadline comes; plan with the shorter. Take the rate from `$WATCH rates`: it starts from the seeds below and each reading refits it.

| Tier | Rate |
|------|------|
| MAX | 3.5% of a week's Fable allowance per helper-hour (the cautious end of about 3 to 3.5%) |
| HIGH | about 0.4 × the MAX figure for the same jobs |
| STANDARD, LITE | not measured: give the helper-hours, and say the 20-minute reading sets the rate |

These come from one measurement on one account (2026-11-22: twelve Fable helpers at effort max used 14% of the week's Fable allowance in 23 minutes). Present them as that, never as a promise: the plan, the task and the repository change them.

## Sizing a wave by the budget

The budget question gave the share. Points left are 100 minus `$WATCH estimate` of the bar the tier's helpers count on that is nearest its cap (MAX: the Fable bar or the weekly; the other tiers: the weekly, or on Pro the highest bar). Then:

helpers ≈ (budget − margin) / (rate × hours to the deadline)

Keep a margin of about 15% for the merge, the checks, the wave's review and this session's own work. Before readings refit the rate, size by the seeds; after, by the refitted rate. The plan shows the estimate as points with the rate it used, for example "8 MAX helpers × 0.75 h × 3.5 ≈ 21% of the week's Fable allowance".
