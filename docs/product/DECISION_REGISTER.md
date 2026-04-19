# Decision Register

Recorded on: 2026-04-15

## D-001: Runtime stack

- Decision: Use Godot 4 runtime for the desktop buddy core.
- Status: locked
- Why: Better fit for animated, always-present companion behavior than
  webview-first stacks.

## D-002: Platform strategy

- Decision: Windows-first for V1.
- Status: locked
- Why: fastest path to stable overlay behavior and shipping.

## D-003: Behavior model

- Decision: deterministic event-driven loop with weighted action selection.
- Status: locked
- Why: predictable debugging and tunable charm without AI dependency.

## D-004: AI sequencing

- Decision: AI is optional later, not foundational.
- Status: locked
- Why: avoid early complexity and retention risk.

## D-005: Repository strategy

- Decision: keep one repo now with clear runtime/content/tooling boundaries.
- Status: locked
- Why: low coordination overhead for early product build-out.

## D-006: Mod/pack strategy

- Decision: data-only content packs for V1.
- Status: locked
- Why: reduces security and maintenance burden.

