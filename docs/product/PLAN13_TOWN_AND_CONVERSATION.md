# Plan 13: A Town to Live In, and Talking to the Buddy

Drafted: 2026-11-16. Status: **proposal, not started**. Builds on
`PLAN12_AUTONOMOUS_MIND.md`.

## Goal

Two things the owner asked for, with `pinos.world` as the reference point:

1. **A town** the buddy actually lives in: places it goes, things that are
   there, a world that changes a little over time.
2. **Talking to the buddy like a person**: free conversation in the chat
   window, where it remembers you, what you told it, and what it has been
   doing.

What is publicly known about the reference is thin: an unprompted AI bird in
a small town, places it visits, visitors can leave it messages or pictures
that it reads "in its own time", and it remembers the visitor. No mechanism
is documented. This plan is our own design toward that feel.

## Where we are today

| Area | Today | Gap |
|---|---|---|
| Mind | Decides every 10 min (rest, visit, explore, tend home, reflect), learns likes and dislikes, keeps a journal, optional local model words its thoughts | Decisions are about names, not a place it is in |
| World | 6 NPCs, quests and encounters as pop-up prompts, a `home`/`overlay` flag | No map, no locations, nothing to see |
| Places | Five place names inside `mind_service.gd` | Not data, not visible, nothing happens there |
| Chat | Slash commands and a few keyword intents. Any other text gets "I did not catch that. Try /help." | No conversation |
| Memory | `/remember` notes and topic counters held in memory for the session only | Nothing about you survives a restart; nothing feeds the mind |
| Model | Local Ollama (`gemma3:4b`), replies in ~0.4 s once loaded, strict reply handling | Only used for one-line thoughts |

## Part A: The town

### A1. Town as data (no visuals yet)

Move places out of code into the content pack as a `town` block in the
manifest, validated by the schema:

- **Places**: `id`, `name`, `kind` (home, shop, park, library, cafe, square),
  `opens`/`closes` hours, `activities` (what can be done there and which
  drive it satisfies), `residents` (NPC ids usually found there), `neighbours`
  (which places connect, for travel time).
- **Starting town**: home, the square, the pond, the old library, the market
  lane, the hill path, the garden, a cafe. The existing six NPCs each get a
  usual place and hours.
- **Town state** in the save: where the buddy is now, where each NPC is this
  hour, a short list of recent town events, per-place visit counts.

The mind service changes from "explore a name" to "go to a place, do an
activity there, maybe meet whoever is there". Feelings attach to places,
activities and NPCs separately. Travel takes time, so a far place costs more.

Done when: the journal reads as a life in one town ("Walked to the cafe.
Quill was there; we talked about the library."), deterministic tests cover
opening hours, travel and who-is-where, and nothing visual has changed.

### A2. A window onto the town

A new **Town** window (opened from the menu) drawn in the existing code-drawn
style:

- A simple map: places as labelled tiles with connecting paths, the buddy's
  marker on its current place, small NPC markers, time of day tint.
- Click a place to see who is there, what the buddy thinks of it, and its
  last few journal lines from there.
- A "Where is it now" line on the main menu.

Deliberately a map, not a walkable scene. A side-scrolling scene with the
character walking between buildings is the tempting version and is the single
largest cost in this plan (art for every place, pathing, a second render
path). It is listed under Later.

Done when: the map matches the journal at all times, including after the app
has been closed and decisions were caught up.

### A3. A town that changes

- **Daily rhythm**: shops open and close, NPCs move between places by hour,
  the buddy has a loose routine it can break.
- **Town events**: a small rotating set (market day, rain, a visitor in the
  square, something new on show at the library) that change what is on offer
  for a day and give the buddy something to have an opinion about.
- **Things you leave**: from the Town window or chat, leave a note or a small
  gift at a place. The buddy finds it the next time it goes there, on its own
  clock, journals it, and remembers who left it. This is the reference's
  signature interaction and the bridge to Part B.
- **Relationships**: NPC affinity (already stored) starts to matter. NPCs the
  buddy likes turn up in its plans; a few simple two-line exchanges get
  journalled.

Done when: two consecutive days read differently in the journal without any
user input, and a left note is found, journalled and referred to later.

## Part B: Talking to the buddy

### B1. Conversation

Any chat text that is not a command goes to the local model and comes back as
the buddy speaking, in character, in one to three sentences. Commands and the
existing keyword shortcuts keep working and never reach the model.

What the model is given each turn, in this order and within a fixed budget:

1. Who it is: name, personality traits, mood now, what it is doing and where.
2. What it knows about you (B2 profile).
3. The few memories most relevant to what you just said (B2 recall).
4. Its last few journal entries.
5. The last several turns of this conversation.
6. Your message.

Decided 2026-11-16: the chat backend is a setting. Ollama is the default and
the only backend built in this plan; the setting exists so a hosted model can
be added later without reworking the chat path. Chat and the ten-minute
thoughts can name different models, so a larger local model can be tried for
conversation while thoughts stay on `gemma3:4b`.

Replies are parsed and cleaned the same way thoughts are now: schema-shaped
reply, one plain block of text, length capped, markup and hidden characters
stripped. If Ollama is off or fails, the buddy says so plainly once and falls
back to the current command hints.

Done when: a ten-turn conversation stays in character, refers correctly to
something from the journal, and the failure path is tested.

### B2. Memory

Decided 2026-11-16: memory is a small **knowledge graph** kept inside the
buddy's own save, not an external database.

- **Nodes**: people, places, things and topics (you, Mira, the pond, tea,
  your job). The town's places and NPCs from Part A are nodes in the same
  graph, so what you say and where the buddy goes connect.
- **Edges**: relations between nodes (you *like* tea; buddy *met* Quill *at*
  the library; you *work late on* Thursdays). Each edge has a date, the line
  it came from, and a strength that fades if it is never mentioned again.
- **Conversation log**: recent turns for the session, summarised when long.
- **Episodes**: short summaries of past conversations and notable days,
  linked to the nodes they involved.

How it is filled: Part A writes town facts directly. After a conversation
ends, one extra model call extracts new facts as node-relation-node triples
in a fixed schema; anything outside the schema is dropped. A small model will
get some of these wrong, which is why every fact is visible and deletable.

How it is used: find the nodes mentioned in your message, take their
strongest and most recent connections (one or two steps out), and give the
model those few facts.

Why not the SecondBrain vault graph or the Qdrant server: the buddy would
then need the home network to remember anything and could not ship to anyone
else. A few hundred nodes need no database. The graph is capped in size.

Optional later: embeddings through Ollama so "my job" also finds "work".

You stay in control: a **Memory** view lists everything it remembers about
you, each item deletable; `/forget` works on any of it; one switch turns
remembering off. The existing `/remember` notes move into this store so they
finally survive a restart.

Done when: a fact stated on day one is used unprompted on day two, and
deleting it stops it being used.

### B3. Talk changes the buddy

- A conversation is an event in its life: it lifts social fulfilment, gets a
  journal entry, and can leave it wanting something ("you mentioned the pond,
  now I want to go").
- You can ask it to do things in the town ("go see Mira"). It may agree,
  put it off, or decline depending on mood and how it feels about the place.
  It is asked, not commanded.
- It can raise things itself when you open chat: something it found, a note
  you left, somewhere it now likes.

Done when: a request in chat visibly changes the next decision some of the
time and the journal explains why either way.

## Order of work

| Step | What | Depends on | Size |
|---|---|---|---|
| 1 | A1 town as data | none | medium |
| 2 | B1 conversation | none | medium |
| 3 | B2 graph memory | B1 (A1 for town nodes) | medium to large |
| 4 | A2 town window | A1 | medium |
| 5 | A3 changing town, things you leave | A1, B2 | large |
| 6 | B3 talk changes the buddy | A1, B1, B2 | medium |

Steps 1 and 2 are independent and give the most visible change for the least
work: after both, the buddy lives somewhere specific and you can talk to it.
Each step is its own pull request, passes the full gate, and ships behind a
setting that defaults on only once its done-gate is met.

## Rules that must change

- `DEFERRED.md` "Free-form AI chat": reopened fully by B1. Needs an explicit
  edit in the same pull request, with `V1_PRD.md`, per the re-entry rule.
- `DEFERRED.md` "Multi-character world simulation": A3 moves NPCs around by
  the hour. That is a schedule, not a simulation, but the line should be
  redrawn there so it does not creep.

## Risks

- **Your text reaches the model.** Until now the model only saw the buddy's
  own state. Conversation, notes left in town and stored memories are all
  text you (or anything you paste) wrote, and stored memories are replayed
  into later prompts. The model's reply can still only become cleaned text
  and a choice among the buddy's existing actions, never a command or a file
  or network action. That boundary has to hold and be tested with hostile
  input, including text planted in a memory.
- **Small model limits.** `gemma3:4b` has a short context and will drift or
  invent in long chats. Mitigations: tight per-section budgets, summaries,
  facts restated every turn, short replies. A larger model stays a setting.
- **Speed and memory use.** A chat keeps the model loaded (about 3 GB of GPU
  memory) for as long as you are talking, then unloads. First reply after a
  pause takes about 6 s. CPU-only machines are untested.
- **What it remembers about you.** Everything stays in local files and is
  only sent to the Ollama address in settings (this PC by default). Pointing
  that address at another machine would send conversations there; the
  settings screen has to say so.
- **Save growth.** Logs and episodes are capped and summarised, with a test,
  so the save stays small (it was 4.9 MB before and caused stutter).
- **Tone.** A character that talks back can say something off. Keep a short,
  firm persona prompt, cap length, and add a one-click "that was wrong"
  that drops the reply from memory.

## Later (not in this plan)

- A walkable side-view town with the character moving between buildings.
- Pictures left for the buddy (needs a vision-capable model).
- Voice in or out.
- Other people's buddies visiting, or anything online.
- A user-editable town.

## Decisions needed before starting

1. **Start with town or talk?** Recommended: steps 1 and 2 together, since
   they do not depend on each other.
2. **Map or walkable scene for the town?** Recommended: map now, scene later.
3. **Does memory default to on?** Recommended: on, with the Memory view and
   off switch shipped in the same step.
4. **Buddy's name and voice.** The persona prompt needs a name and two or
   three lines on how it talks. The profile has a personality seed
   (`curious`) but no name.
