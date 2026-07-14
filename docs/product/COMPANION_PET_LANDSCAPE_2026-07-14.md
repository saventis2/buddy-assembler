# Companion-Pet Landscape: Claude & Codex Pets — What's Applicable to Buddy

Research pass, 2026-07-14. Companion to
`BUDDY_INFLUENCE_RESEARCH_BACKLOG_2026-04-20.md` (this fills part of its
"friendly assistant ergonomics" track with the 2026 crop of AI-coding-agent
pets). Research only — no feature commitments; anything adopted goes
through the normal backlog.

Source confidence: entries marked **[official]** were read from the
project's own repo/README; **[press]** is secondary coverage (feature
behavior likely right, implementation details less certain).

---

## 1. The landscape

Four distinct things shipped in 2026 that people call "Claude/Codex pets":

### 1.1 Codex Pets (OpenAI, in the Codex app) [press]

- Optional animated companion in a **small floating overlay** (bottom-right
  by default), toggled with `/pet`. The pet is a **status layer** for the
  agent: it shows the active thread, and its thought bubble shows a small
  **red clock** when the agent is blocked waiting for approval and a
  **green check** when a task is done and ready for review.
- **8 built-in pets, 3 states** (roughly: working / needs-input / ready).
  Deliberately minimal state machine — legibility over richness.
- Custom pets via a `hatch-pet` skill: the model **generates a pet package**
  (a `pet.json` manifest + one horizontal spritesheet) from a text prompt;
  packages are shareable files and appear in a Pets selector.

### 1.2 Claude Buddy (Anthropic, in Claude Code terminal) [press]

- `/buddy` in Claude Code ≥2.1.89: an **ASCII terminal pet** — 18 species,
  5 rarities, **deterministically generated from the user ID** (everyone
  keeps the same buddy; scarcity without a gacha).
- Tamagotchi mechanics (care/interaction via `/buddy pet`, stats via
  `/buddy card`), described as a full pet simulation in the runtime with
  anti-cheat and LLM-driven personality, reacting to the development
  workflow rather than button presses.

### 1.3 Claude Desktop Buddy (Anthropic, open-source hardware) [official]

`github.com/anthropics/claude-desktop-buddy` — ESP32/M5StickC desk pet
driven by a **local BLE API** in Claude Desktop/Cowork (developer-mode,
opt-in). The interesting part is the tiny, well-chosen **state vocabulary**
broadcast over Nordic UART as JSON:

`sleep` (disconnected) / `idle` / `busy` (sessions running) /
`attention` (approval pending — pet gets visibly impatient, LED blinks) /
`celebrate` (milestone) / `dizzy` (device shaken) / `heart` (approval
granted in <5s).

The device can send back `approve` / `deny` (physical buttons) plus
gesture events. Character packs are GIF bundles with a `manifest.json`
mapping **states → GIF(s)** (arrays allowed for idle variety), pushed to
the device by drag-and-drop. 18 ASCII species × 7 animations each ship
built in.

### 1.4 Third-party overlay pets: Clawd on Desk & OpenPets [official]

- **Clawd on Desk** (`rullerzhou-afk/clawd-on-desk`, Electron): a pixel pet
  in a transparent always-on-top window — transparent areas pass clicks
  through, **only the pet's body is interactive** (same technique as our
  overlay). Watches Claude Code, Codex CLI, Copilot CLI, Gemini CLI etc.
  via a *layered* detection stack: agent **hook files** where supported →
  **HTTP permission hooks** → **session-log polling** (`~/.codex/sessions/`)
  → **process monitoring** to clean up orphaned sessions. **12 animation
  states**, including idle-with-eye-tracking (follows your cursor),
  thinking, typing, error, sleeping, and — notably — **one-subagent groove
  vs multi-subagent juggling** (state = highest-priority state across all
  concurrent sessions, with subagent counts feeding the animation).
  Permission bubble UI with global hotkeys + auto-dismiss. Can import
  Codex Pet packages as themes.
- **OpenPets** (`alvinunreal/openpets`, Electron/TypeScript): a general
  desktop-pet *platform* — manifest-based pet bundles, a sandboxed plugin
  SDK (plugins declare UI; the host renders it — no raw HTML injection),
  and an **MCP server** as the agent bridge exposing three capabilities:
  status checks, animation reactions (thinking/editing/success/error), and
  speech bubbles. Dynamic speech is **locally redacted** (paths, URLs,
  secrets, multiline code) before display.

---

## 2. What this validates about Buddy's current design

- **The overlay approach is right, and ours is cheaper.** Every software
  pet above is an Electron app (a full Chromium per pet); our Godot
  runtime with per-pixel transparency + body-only mouse passthrough does
  the same trick at a fraction of the footprint. Same architecture,
  lighter engine — worth stating in positioning.
- **Content packs as manifest + assets is the industry pattern.** Codex
  `pet.json` + spritesheet, Desktop Buddy `manifest.json` + GIFs, OpenPets
  manifest bundles — all are small siblings of our (richer) pack schema in
  `CONTENT_SCHEMA.md`. Our schema-semver work (backlog #59) and zip pack
  format (#63) line up with where everyone else already is (single-file
  shareable packages).
- **"Not just idle animations" is the differentiator gap.** All four are
  status indicators or shallow tamagotchi; none has Buddy's
  bond/mood/growth/world model (design brief §3). The landscape confirms
  the vision doc's bet — but also shows the *one* feature they all have
  that we lack (next section).

## 3. What's applicable — candidate backlog items

Ordered by leverage-per-effort against the existing codebase; **A** items
are small, **B** medium, **C** large/gated. None are commitments.

### A1. Status-glyph thought bubble (Codex's 3-glyph legibility)

The red-clock / green-check thought bubble is the best UX idea in the set:
a *glanceable* state cue that works at pet scale without reading text. We
already render speech/thought content in the overlay; adding a tiny glyph
state to the bubble (busy / needs-you / done — mapped initially to our own
events: active encounter, waiting-on-user choice, quest complete) is
almost pure content-pack + small runtime work. Also gives any later agent
integration (A3) its display surface for free.

### A2. Idle eye-tracking (Clawd)

Buddy's eyes (or head tilt) following the cursor during idle. Cheap in
Godot (we already know cursor position for passthrough), big
"alive companion" payoff — directly answers the influence backlog's
research question "which UI/feedback patterns communicate 'alive
companion' best?". Needs care with our composed MapleStory faces —
likely a face-swap variant per gaze direction rather than free pupil
movement; the renderer's face-composition path already supports face
variants.

### A3. Coding-agent awareness mode (the whole category's reason to exist)

"Reacts to the user's activity" is core fantasy §3, and *the* activity to
react to in 2026 is an AI agent working on your behalf. A **local status
adapter** — file-watcher/hook receiver feeding the buddy a tiny state
vocabulary — would let Buddy do what Clawd does, but with our richer
character. Two design decisions worth stealing outright:
- **Claude Desktop Buddy's 7-state vocabulary** (sleep/idle/busy/attention/
  celebrate + reaction states) as the *interface contract* — small enough
  to keep every content pack's animation set finite, and proven on
  hardware with 18 species.
- **Clawd's layered detection** (hooks where the agent supports them,
  log-tail fallback, process liveness for cleanup) rather than betting on
  one mechanism.
Scope note: this is a new runtime service (autoload) + schema additions →
sequence behind #59 (schema semver) and treat as its own backlog entry
with a design pass; the Claude Code hooks side is well-documented and the
BLE reference shows Anthropic is deliberately exposing this integration
surface.

### A4. Milestone celebrations (`celebrate`, `heart`)

Desktop Buddy celebrates every 50K tokens and has a special "heart" for
fast approvals. The generalizable idea: **tiny deterministic milestones
with visible one-off reactions**, cheap dopamine that needs no economy.
Ours could hook existing counters (bond level-ups already planned; petting
streaks, quest counts). Pairs naturally with tuning tables (#23).

### B1. Deterministic identity + rarity flavor (Claude Buddy)

Deterministic generation from a stable seed ("your buddy, not a re-roll")
is a strong identity mechanic and dirt cheap. We have deeper
customization plans, but a **deterministic default buddy** (species/palette
/trait seeded from machine or profile ID) for first-run — before the user
customizes anything — would give day-zero attachment and word-of-mouth
("mine hatched as a rare"). Fits FIRST_RUN_ONBOARDING.md; no economy
needed.

### B2. Pet-package import (interop as acquisition)

Clawd imports Codex Pet packages as themes. Our importer toolchain
(`tools/importers/`, freshly consolidated on `wz_shared`) could grow a
small **`import_codex_pet.py`**: pet.json + horizontal spritesheet → a
generated Buddy content pack (one costume/companion with N states). Cheap
because it's exactly the shape of tooling we already build and test
(synthetic fixtures, golden images), and it makes the whole hatch-pet
ecosystem's output usable as Buddy content. Licensing note: only user-local
files, user-initiated — same provenance rules as all imported content
(promotion log applies).

### B3. Speech-content redaction rule (OpenPets)

If/when any dynamic text (agent status, activity snippets) reaches Buddy's
speech bubbles, adopt OpenPets' rule: **locally redact paths, URLs,
secrets, and multiline code before display**. Costless to adopt as a
stated constraint now (one paragraph in CONTENT_SCHEMA.md/security notes)
so it's never retrofitted.

### C1. Actionable pet: approve/deny from the buddy

Desktop Buddy's best trick: the pet is not just a display — a pending
approval makes it impatient and the user can approve/deny *at the pet*.
For us: a small interaction on the buddy (click bubble → approve/deny
buttons, global hotkey like Clawd's) once A3 exists and the agent's hook
supports responding. Strictly gated on A3; also the first feature where
the buddy takes real actions on the user's behalf → needs its own
safety/consent design pass.

### C2. AI-generated custom buddies (hatch-pet's lesson)

`/hatch` shows demand for "make me a pet from a prompt." Our equivalent is
far richer (full composed characters) but heavier. The cheap first step is
B2 (import what hatch-pet makes); a native "describe a buddy → generated
pack" pipeline is post-V1 territory and stays behind the DEFERRED.md
fence with the other generative items.

## 4. What NOT to copy

- **Electron.** Confirmed heavyweight; our Godot base is an advantage.
- **Pure status-pet minimalism as the product.** It's a feature (A1/A3),
  not the product — the design brief explicitly positions Buddy beyond it.
- **Codex's 3-state ceiling for our own content.** Fine as a *bubble glyph*
  vocabulary; our packs already model more expressive action sets. Keep the
  interface vocabulary small (A3) without flattening pack expressiveness.
- **Gacha-style hatching randomness on re-roll.** Claude Buddy's
  determinism is the tasteful version; keep scarcity deterministic.

## 5. Suggested next steps (when picked up)

1. Add A1, A2, A4 as concrete backlog entries (Wave 3 flavor tier — A1/A4
   pair with #23's tuning tables; A2 is standalone runtime work).
2. Write the A3 design one-pager (state vocabulary, adapter architecture,
   which agents' hook formats to support first) before any code — same
   "plan before invasive work" rule as the Godot upgrade.
3. B2 (`import_codex_pet.py`) is a good self-contained importer-toolchain
   task once a real pet.json sample is in hand for a fixture.
4. Adopt B3's redaction rule as a written constraint now.

## Sources

- https://github.com/anthropics/claude-desktop-buddy (official README)
- https://github.com/rullerzhou-afk/clawd-on-desk (official README)
- https://github.com/alvinunreal/openpets / https://openpets.dev (official README)
- https://github.com/alvinunreal/claude-pets (archived; folded into OpenPets)
- Codex Pets press coverage: engadget.com "OpenAI introduces AI-generated
  pets for its Codex app"; fonearena.com "OpenAI Codex gets Pets feature
  with real-time task overlay"; pcworld.com; hongkiat.com; explainx.ai
  (pet.json + spritesheet format, /pet & hatch-pet flow)
- Claude Buddy press coverage: claudefa.st, decodethefuture.org,
  mindwiredai.com (18 species / 5 rarities / deterministic generation)
- Anthropic ESP32 pet coverage: xda-developers.com, cnx-software.com
