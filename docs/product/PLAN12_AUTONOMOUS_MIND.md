# Plan 12: Autonomous Mind

Started: 2026-11-15

## Direction

The buddy should live its own life: decide for itself what to do, do it in its
own world, form its own tastes from how things felt, and let the user read
about it afterwards. Reference point supplied by the owner: `pinos.world`
(an unprompted AI character in a small town that visitors can leave things
for). Publicly that project documents only the framing, not the mechanism, so
nothing here is copied from it.

## Plan 12A (landed): the offline mind

`apps/runtime-godot/scripts/services/mind_service.gd`

- **Unprompted decisions.** Every 10 minutes the buddy picks one of
  `rest`, `visit`, `explore`, `tend_home`, `reflect`.
- **Driven by how it feels.** The drives are the mood modifiers the mood
  service already maintains (`energy_strain`, `social_fulfillment`, `comfort`,
  `confidence`) plus a `restlessness` value that builds until it explores.
  Night time and the top personality trait tilt the choice.
- **A world to act in.** Visits go to the world layer's NPCs. Exploring goes
  to five places (pond, old library, market lane, hill path, garden).
- **Taste that develops.** Each visit or outing has a valence; it is folded
  into a per-subject feeling in `[-1, 1]`. Liked subjects are chosen more
  often, disliked ones less, never zero.
- **In its own time.** Decisions that came due while the app was closed are
  played out on the next launch (capped at 8, spread over the time away).
- **A journal.** Every decision writes a first-person entry (last 40 kept in
  `profile.mind.journal`). `/journal` in chat shows the latest five.
- **Expression.** The latest decision is acted out through the existing
  animation actions (`sleep`, `visitor`, `happy`, `sit`, `idle`) and spoken in
  the chat balloon. In quiet hours it is journalled but not spoken. A paused
  buddy makes no decisions.
- **Off switch.** `autonomyEnabled` in settings (default `true`).
- **Deterministic.** Decisions are seeded from the profile and decision time,
  so tests replay exactly. Covered by `MindServiceTest` (8 cases) in the
  required headless suite.

No network, no model, no new dependency. `DEFERRED.md` still holds: there is
no LLM integration in the runtime.

## Not yet built

- **A thinking model.** Thoughts are templates. Swapping in a language model
  for the journal voice and for choosing among intents is the step that makes
  this feel like a mind rather than a schedule. It reopens the "no LLM in V1"
  fence in `DEFERRED.md` and needs an owner decision on where the model runs
  (local Ollama on the LAN vs a hosted API), plus prompt-injection handling
  for anything the user leaves for the buddy to read.
- **Leaving things for the buddy.** Notes or pictures the buddy reads later,
  on its own clock, and remembers the giver by.
- **A visible world.** Places are names only; the home scene does not change
  with where the buddy went.
- **Settings UI** for `autonomyEnabled` (file-only today).
- **Journal in the manual checklist** (`tests/SCENARIO_CHECKLIST.md`).
