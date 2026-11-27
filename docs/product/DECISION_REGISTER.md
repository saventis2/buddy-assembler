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

## D-007: Small beginnings

Recorded on: 2026-11-17 (owner direction of 2026-11-16, Plan 14)

- Decision: a buddy starts with a house and the land around it, alone, and
  builds its own town as it learns. There are no townspeople for now; the
  only people in its life are real people. The Plan 13 town, its six
  characters, their quests and encounters stay in the pack and the code as an
  archive, switched off for a buddy that starts small. A buddy from before is
  backed up, then a new one starts.
- Status: locked
- Why: the owner wants it to start out knowing very little and have everything
  develop over time, not to start in a town full of people. See
  `PLAN14_SMALL_BEGINNINGS.md`.

## D-009: The 2.5D world

Recorded on: 2026-11-20 (owner direction of 2026-11-16, Plan 14)

- Decision: the buddy's world is shown as a small low-poly 3D diorama of its
  land, with the buddy as its existing 2D character on a card that faces the
  camera; a modelled, rigged 3D buddy is its own later plan, and the world is
  built so the card can be swapped for one. The desktop Town window is this
  view (2026-11-20); the website gets the same scene in step 5.
- Status: locked
- Why: the owner wants to watch its world in 3D and keep the character and
  animations it already has.

## D-010: The world host

Recorded on: 2026-11-18 (owner direction of 2026-11-16 and 2026-11-18, Plan 14)

- Decision: the buddy's world runs in a background world host, and the desktop
  app is the buddy visiting you. It is on by default. The buddy is in one place
  at a time, and only the program it is in writes it.
- Status: locked
- Why: the owner wants it always active, its world going on whether or not it
  is on the desktop.
- Note: GGPC hosts it for now, without a watchdog; a scheduled task that keeps
  it running comes with the move to Nexus. See `PLAN14_SMALL_BEGINNINGS.md`.

## D-012: The buddy is told nothing about its world

Recorded on: 2026-11-18 (owner direction of 2026-11-18, Plan 14)

- Decision: the buddy is told nothing about its world. Everything it knows lives
  in its own memory (short-term and long-term, its second brain), never in the
  model. Whatever it says is checked against that memory before it goes out. You
  will talk to it by letter through its console (step 2c).
- Status: locked
- Why: the owner wants it to learn everything for itself, and a small model
  fills gaps from its training ("Mr. Henderson next door"). See
  `PLAN14_SMALL_BEGINNINGS.md`, Memory.
