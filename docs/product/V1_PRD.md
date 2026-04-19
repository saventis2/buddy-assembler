# V1 Product Spec

Recorded on: 2026-04-15

## Product Intent

Deliver a lovable desktop buddy that can live on screen for months without
becoming noisy or distracting.

## Target User

Desktop users who work or study for long sessions and want ambient
companionship.

## V1 Must-Have Features

- transparent always-on-top companion overlay
- drag/pet/click interactions
- idle and reaction state machine
- deterministic weighted behavior loop with cooldown budget
- local settings and profile persistence
- bond progression (minimal version)
- event frequency controls and quiet behavior defaults

## V1 Explicit Non-Goals

- free-form AI chat
- cross-platform parity
- marketplace/plugin scripting runtime
- large multi-character world simulation

## Performance and Quality Targets

- startup under 2 seconds on a normal desktop profile
- idle CPU under 2 percent target
- stable long-running session (3+ hours) without visible drift
- no severe interaction conflict with normal desktop use

## Ship Criteria

1. Vertical slice acceptance list in `EXECUTION_PLAN.md` is fully satisfied.
2. Basic crash-free persistence and restore works.
3. Internal dogfood confirms non-intrusive default behavior.

