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

Plan 12A on its own needs no network, no model and no new dependency.

## Plan 12B (landed): thinking model via local Ollama

`apps/runtime-godot/scripts/services/mind_thinker.gd`, owner decision
2026-11-15: the model runs in a local Ollama server.

- **What the model does.** After each live decision the buddy sends a small
  fact sheet (what it did, with whom or where, how it felt, its favourite so
  far, its last few journal lines) to Ollama `POST /api/chat`. The reply is
  `{"thought": ..., "want": ...}`. The thought replaces the template wording
  in the journal and is what the buddy says. `want` is one of the five
  intents and gives that intent a one-off bonus in the next decision, so the
  model steers what the buddy does next without being able to do anything
  the mind service could not already do.
- **Always optional.** If Ollama is not running, times out (45 s), answers
  with an error, or sends something unusable, the buddy uses the built-in
  wording. `/journal` ends with a status line such as
  `Thinking model: gemma3:4b, unreachable (result 2)`.
- **Settings** (`user://settings.json`):
  - `mindModelEnabled` (default `true`)
  - `mindModelUrl` (default `http://127.0.0.1:11434`; only the scheme, host
    and port are used)
  - `mindModelName` (default `gemma3:4b`)
- **Setup.** Install Ollama, then `ollama pull gemma3:4b`. On a CPU-only
  machine use `gemma3:1b` and set `mindModelName` to match.
- **Why `gemma3:4b`.** About 3.4 GB and not a "thinking" model, so there is
  no reasoning text that can leak into the reply. Most small models released
  in 2026 are thinking models. This choice is from published model listings,
  not from our own side-by-side testing. Gemma has its own terms of use; the
  app only names the model, it does not ship it.
- **Reply handling.** The reply is treated as untrusted text. The request
  asks Ollama to enforce a JSON schema, and the reply is validated again on
  arrival: size capped at 64 KB, `thought` reduced to one plain line of at
  most 160 characters with brackets, angle brackets, control characters and
  invisible or direction-changing characters removed, `want` dropped unless
  it is a known intent. Redirects are not followed.
- **What leaves the machine.** Nothing, with the default URL. The fact sheet
  holds only the buddy's own state and NPC names from the content pack; it
  never includes user notes or anything typed in chat.
- **Tests.** `MindThinkerTest` (9 cases) in the required headless suite, and
  a manual end-to-end run of the real overlay against a stand-in server
  (good reply, garbage reply, server error, no server).
- **Not yet verified against a real Ollama.** No Ollama server was reachable
  when this was built, so the wording quality of `gemma3:4b` and its
  response time on the target machines are untested.

## Not yet built

- **Side-by-side model comparison** on the real machines.
- **Leaving things for the buddy.** Notes or pictures the buddy reads later,
  on its own clock, and remembers the giver by.
- **A visible world.** Places are names only; the home scene does not change
  with where the buddy went.
- **Settings UI** for `autonomyEnabled` (file-only today).
- **Journal in the manual checklist** (`tests/SCENARIO_CHECKLIST.md`).
