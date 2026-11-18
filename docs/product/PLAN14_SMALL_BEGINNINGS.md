# Plan 14: Small Beginnings

Started: 2026-11-16. Status: direction set by the owner (answers below); in
build, see Progress. Written against `main` at b1cb579 (Plan 13 A1, A2, B1 to
B3 and C1+C2 part 1 merged).

## Progress

**Step 1a, the fast-forward tool: built 2026-11-17.**
`python apps/runtime-godot/tools/simulate_days.py --godot <4.2.2 binary> --days 90 --seed 7`
lives a new buddy through 90 days in about 45 seconds and prints its journal,
each day's firsts and how often it repeated itself. It drives the real
`AppState.tick_mind` with a supplied clock (`begin_simulation`,
`set_sim_clock`), so it cannot drift from the app. A process that starts a
simulation never saves again, and `begin_simulation` refuses to run outside a
headless process. `LifeSimTest` (8 cases) is in the required suite: the same
seed gives the same life, different seeds differ, and nothing is saved.

Step 1 is split into three pull requests: 1a this tool; 1b the house and land
with discovery, behind a setting; 1c the fresh start with backup, which turns
the new world on.

### What 90 days of today's buddy look like

Seed 7, the Plan 13 town, nobody talking to it. This is the baseline the new
world has to beat.

- **Everything is found by day 3.** It has been to every place and done all 14
  activities by day 3, and met four of its six neighbours. After that the only
  new things are shop items.
- **75 sentences for 12,960 decisions.** The ten most common lines are 68% of
  the journal, and "I had a nap at home. It felt good." appears 2,696 times.
  From day 14 on, 40 days have nothing new at all, including most of the last
  month.
- **Its needs never bite.** From day 1 comfort and confidence sit at their
  maximum and company stays near the top; tiredness is at zero within the
  week. They stay there for 90 days, so how it feels has nothing to say. It
  tends its home 9 times in 90 days, visits someone on 3% of decisions, and
  goes exploring 1,390 times in the middle of the night.
- **Two neighbours are never met**, although it goes to the places they live
  more than 1,500 times.
- **Money means nothing.** It ends with 3,300 meso and has bought all 39 things
  it ever wanted.
- **Bond reaches level 15 with nobody there.**

What this changes in the plan:

- **Needs have to fall with time on the world host** (step 2a). Today the only
  thing that tires the buddy or makes it lonely is the desktop animation loop,
  which this tool does not run and the host will not have.
- **Two buddies should not live the same life.** The mind seeds its choices
  from `personality_seed_tag` ("curious" for every buddy), not from
  `personality_seed`, so two buddies differ only by when their clocks tick.
  To fix with the discovery work in step 1b.
- **Targets for the new world**, to pin as tests in step 1b: something new on
  most of the first 30 days, no need pinned at its limit, and the ten most
  common lines well under half the journal.

### Step 1b, the house and land: built 2026-11-17

Behind the setting `smallBeginnings`, which stays off until step 1c. Run it
with `simulate_days.py --world land`.

- **The land is written.** `scripts/services/land_data.gd` holds the house and
  twelve areas (the yard, the wood heap, the big tree, the overgrown patch,
  the gate, the high ground, the long grass, the water, the stony ground, the
  grey bank, the sandy bend, the whispering grass, the dark trees), 58 things
  to do and 80 things to notice, all in the buddy's own words. It has few
  names, so it describes: "A tall grey bird was standing in the water, so
  still I took it for a stick. Then the stick took one step."
- **It knows only its house.** It finds the rest by going to the edge of what
  it knows: a sign first ("I could hear water somewhere, low and steady"),
  then tries that can fail, then the place. After a failed try it leaves that
  place for another day, and each failure makes the next try a little more
  likely. `AppState.get_town()` returns only what it has found, so chat,
  suggestions, day plans, memory and the Town map all narrow the same way.
- **What it does takes time.** Each thing takes its minutes plus the walk
  there, and it sleeps from when it is tired in the evening until morning. A
  day is about 27 journal lines, not 144.
- **Its needs move with time.** Being awake tires it, comfort fades, and its
  confidence follows how things go. In the new world the desktop animation
  no longer moves them.
- **Nobody else lives there.** The three people reads return nothing, quests
  and encounter prompts are off, and it never chooses to visit anyone.
- **Its own seed feeds its choices**, so two buddies do not live the same life.
- **Its journal starts with one line**: waking up in a house it does not know.

What a first month looks like, across eight seeds, next to the baseline above:

| | Today's town | The land |
|---|---|---|
| Places found | All by day 3 | 3 to 6 on day 1, 10 to 12 of 13 by day 7, the last on day 8 to 12 |
| Failed tries | None | 13 to 19 |
| Something new | Nothing on 40 of 90 days | Something on 26 to 29 of 30 days |
| Ten most common lines | 68% of the journal | 6.5% to 7.8% |
| Nights | Out exploring | Asleep from evening until morning |
| Needs | Stuck at their limits | Tiredness 0 to 0.72 each day, comfort 0.39 to 1, confidence 0.13 to 1 |

`LandLifeTest` (15 cases) pins this: the land's data is well formed and every
place can be reached, a sign comes before a find, nothing is noticed twice,
and the month stays inside these bands for three seeds.

Choices made here that later steps should know about:

- **The local model does not reword land lines for now.** It would write over
  what the buddy found and noticed. It still picks its name. Revisit with the
  "what you know" chat work.
- **Company is left alone.** Nobody lives on the land, so that need only moves
  when you talk to it. It gets its outlets with the visit (step 2a) and
  letters (step 2c).
- **The land alone carries about two months.** After about day 12 the only new
  things are the ones it notices. Over 90 days (seed 7) there was something
  new on 26 days of the first month, 19 of the second and 2 of the third. The
  later weeks fill up when there are things to try and make (steps 3 and 6
  to 8).
- **It crosses its land in one move**, with the walk counted in minutes but no
  route. The 3D view (step 4) is where movement shows.
- **Bond and meso still accrue as before.** They belong to your side of the
  economy and are settled with commerce (step 13).

### Step 1c, the fresh start: built 2026-11-17

- **The new world is on by default.** `smallBeginnings` is now true.
- **A buddy from before is put away, then a new one wakes up.** At a real
  launch, if the buddy was not born on the land, `settings.json`,
  `profile.json` and `world_state.json` are copied to
  `backups/before-small-beginnings-<date>/` in the save folder. The folder is
  never overwritten and each copy is checked against its original. Only then
  is the buddy replaced. If the copy fails, nothing is changed and the old
  buddy carries on in its old town for that run.
- **Only the buddy starts over**: its name, memories, journal, feelings, bond
  and growth. Settings, items, wardrobe and meso are kept, as your side of the
  economy.
- **Only a real launch does it.** `launch_router.gd` calls it. The tests, the
  CI start-up modes and the fast-forward tool never touch the save.
- **The six characters, their quests and encounters stay where they are**, in
  the pack and the code. That is the archive: nothing was removed, the new
  world never reads them, and with the setting off the old town works as
  before. No separate archive folder was made, because moving pack content
  would have changed nothing a buddy can see.
- **Going back is by hand**: turn the setting off and copy `profile.json` from
  the backup folder over the one in the save folder. The runtime README has
  the steps.
- **D-007 is recorded** in `DECISION_REGISTER.md`, `V1_PRD.md` and
  `DEFERRED.md`.

`FreshStartTest` (9 cases) covers the copy, a backup that already exists, a
copy that fails, a new install, the setting turned off, and the new buddy's
first line.

Two things found after the first build of this step:

- **A new install backed up its own empty save**, because loading can write a
  default profile before the fresh start runs. Whether a buddy was saved is
  now read once, before anything can save.
- **The fast-forward tool could touch the save while the app was starting
  up**, before the simulation switched saving off (a pending migration writes,
  a damaged file is renamed). The launcher now passes `--no-save`, which makes
  the app start from defaults without opening the save files, and the
  simulation scene refuses to run without it. Found in review of PR #101.

### Chat on the land: 2026-11-18

(Replaced the same day by step 2b-2 below: this wording is gone, and chat now
speaks from memory.)

With the model on, a land-born buddy names itself within seconds. Chat still
told the model it lived "in a little town", though, so it made up neighbours.
Chat on the land now has its own wording (`mind_thinker.gd`:
`LAND_CHAT_SYSTEM_PROMPT` and the two land reminders): it lives alone in a
small house on its land, there is no town and nobody else, and the places it
has found go to the model as `your_land`. Every rule that is not about the
town is kept word for word, which `mind_chat_test` checks, and the old town
sends exactly the same requests as before.

Measured with the app's own request builder and a copy of a demo buddy's
save, counting replies that made up people, a town or a shop:

| Questions (replies) | gemma3:4b, old wording | gemma3:4b, land wording | gemma3:12b, land wording |
|---|---|---|---|
| Asked directly: "who are your neighbours?", "tell me about your town" (25) | 10 | 0 | not run |
| Taking them for granted, the questions the wording was tuned on: "what's the name of your town?" (24) | 16 | 0 | not run |
| Taking them for granted, new questions: "tell me about the other people on your land" (16) | 14 | 14 | 0 |

With either wording, the small model got its name, its day and the greeting
right every time (20 replies each). Told about their own neighbours or a
friend in town, it often answered as if it knew them (6 and 7 of 8 wrong); the
larger model got 7 of 8 right.

So the wording only helps the small model with questions like the ones it
was written against. The larger model follows it, but it is twice the size
(7.6 GB) and holds more graphics memory while it talks. Until letters arrive
(below), setting `chatModelName` to `gemma3:12b` in `settings.json` gives the
better chat. The lasting fix is to check what it writes against what it knows
before it is sent (see Memory).

### Step 2a-1, the world host and the visit: built 2026-11-18

Behind a setting that is off by default (`worldHost` in `settings.json`, or
Menu > Settings > Its own mind > World host). With it off nothing changes: the
app, the fast-forward tool and every test behave as before.

With it on, the buddy lives on its land in a background program (the app
started with `--headless -- --world-host`) that keeps running when the app is
closed, and the desktop app is the buddy visiting you. The owner chose:

1. **One writer at a time, by hand-over.** The buddy is in exactly one place.
   At home the world host runs its life and is the only process that writes
   `profile.json` and `world_state.json`. While it visits, the desktop app
   looks after it exactly as before and is the only process that writes them.
   Going home hands it back. `settings.json` always belongs to the desktop
   app; the host only reads it.
2. **Opening the app.** The buddy comes over by itself when the app opens,
   unless it is asleep or in the middle of something. Then the app says when it
   will come, and it comes then if the app is still open.
3. **Lonely visits.** Its need for company slowly falls on its own land
   (`LAND_COMPANY_FADE_PER_SLOT`). When the company need is low, it is awake and
   free, and the app is open, it may come over by itself, and not within three
   hours of a visit ending.
4. **Going home.** A visit ends when the app closes, at its bedtime, after two
   quiet hours (no interaction), or when you choose "Send home" in its menu.

Rule 6 below now reads: the buddy is written by whichever program it is in, and
only one holds it at a time. The website still only shows it and sends requests.

The files, all under `user://host/` (`%APPDATA%\Godot\app_userdata\Buddy Runtime\host`):

- `buddy.lock/`: a folder used as the lock. `owner.json` inside it has the
  holder's role, pid and a heartbeat every 15 seconds. A lock is broken only
  when its owner's process is gone, or its heartbeat is over 90 seconds old and
  the breaker has itself been awake and ticking for 90 seconds (so a PC waking
  from sleep never breaks a live holder's lock).
- `host.json`: written only by the host. Its state (`home`, `visiting` or
  `waiting`), why it handed the buddy over, its last answer to a call, and
  `freshStartBackup`.
- `desktop.json`: written only by the app. `away`, `visiting` or `sent_home`
  with the reason, and a heartbeat.
- `inbox/`: requests from the app to the host, one file each.

Found in review and fixed before merging:

- **A new buddy started with no company at all**, so it would have come over
  every three hours from its first day. A buddy born on the land now starts at
  `LAND_START_COMPANY` (0.6) and gets lonely after about a day awake.
- **Right after a hand-over, the host could take the buddy back as lost**
  before the app had picked it up. It now waits up to a minute
  (`HANDOVER_GRACE_SECONDS`), and a "sent home" left over from an earlier visit
  no longer ends a new one.
- **Opening the app when the host was not running got "busy, will come in N
  minutes"**, because the new host caught up on its day before it read the
  call. The app now sends the call before it starts the host.
- Smaller fixes:
  - calls older than ten minutes are dropped;
  - a call it said it would come for is checked again when the time comes;
  - called at its bedtime, it comes at 07:00, instead of arriving and leaving at once;
  - a second copy of the app is told apart from a status file left by a crash;
  - the app restarts a host that stopped while it was open (only with the
    setting on, and not straight after the PC wakes);
  - only one host runs at a time;
  - there is no hello in chat while it is at home.
- **From the Codex review of PR #103:**
  - **Holding lasts only as long as the lock.** A process that froze for longer than the stale time can find its lock taken over. Before any write it now checks the lock is still its own, and it stops writing the buddy at once when it is not. An app in that state shows the buddy at home; a host in that state stops if another host has taken over.
  - **Forget is disabled while the buddy is at home**, because the forget would not be saved.
  - **The app finishes a visit itself** when the setting is off or no host is running, so the save never says "visiting" with nobody to finish it. A buddy that stays with you because no host could start now leaves for its visit like any other.

Checked end to end, with throwaway saves:

- Opening the app started the host, and the buddy came over in about 6 s.
- Closing the app sent it home in about 8 s ("Your desk went dark, so I came home.").
- Opening the app again brought it back.
- Killing the app left the buddy with it until the 90-second wait ran out. Then
  the host took it back ("I found my way home from your desk.").
- Turning the setting off stopped the host.

The town and land 30-day runs are unchanged, and `WorldHostTest` has 16 cases.

One limit: if the app was started through Godot's console wrapper
(`..._console.exe`), a host it starts stops when the app stops, because the
wrapper ends everything it started. Started from the windowed Godot program or
an exported build, the host keeps running. The watchdog in 2a-2 removes this
limit.

Left for 2a-2 (done below, except the watchdog):

- a watchdog that starts the host at logon and restarts it (this adds a
  scheduled task: not done, moved to the move to Nexus, see 2a-2);
- a journal line after the host was down (done);
- the setting on by default, with D-010 (done);
- the host choosing the name (done).

### Step 2a-2, on by default: built 2026-11-18

The world host is now on by default (D-010), for a buddy that starts small
(`worldHost` and `smallBeginnings` both on; the host stops when either is off).
What changed:

- **Only a real launch is the desktop.** With the setting on by default, every
  Godot process would otherwise take the desktop role and the overlay would start a
  world host: the CI parse check (`godot --headless --quit`), the test scenes,
  `--script` tools, the fast-forward tool. `AppState._is_real_launch()` is false
  for a headless process (the engine removes `--headless`, `--path` and `--quit`
  before `OS.get_cmdline_args()` sees them, so the display server is the only way
  to tell), and `_is_real_launch_args()` is false for a named test scene, a
  `--script`, editor or import run, and the two smoke tests. A simulated life
  (`begin_simulation`) is always solo.
- **A journal line after the host was down.** When the host takes the buddy after
  three or more hours since its last decision (the host was not running, or the PC
  slept), one line says there was a long stretch it does not remember
  (`note_still_world`). It is dated before the decisions that catch up.
- **The host chooses a name** for a buddy that has none, with the same rules and
  request as the app (Ollama only, never a name someone in the world has); it
  retries after ten minutes. The app still names a nameless buddy on arrival.

The owner's two answers (2026-11-18):

1. **World host on by default.**
2. **No watchdog on this PC.** A scheduled task that keeps the host running comes
   only with the move to Nexus. Until then the host runs once the app has started
   it, keeps running after the app closes, and after a restart waits until the app
   is opened again.

Found in review and fixed:

- **A running host makes every other process read-only.** While a host is
  running, any other process takes the desktop role and only reads the buddy,
  tests, tools and checks included, whether or not it is a real launch. Only a
  real launch (`AppState.is_real_launch()`) starts the visit and may start a
  host. Without this, a test or tool run against the real save while the host
  holds the buddy would have been a second writer.
- **Time asleep is not lost time.** The gap before the "long stretch" line now
  runs from when the buddy would next have done something (the later of its last
  decision and `busy_until`). It is checked once after the host takes the buddy,
  and once after the PC slept.
- **A new buddy wakes before it visits.** On a new install the host answered the
  app's call before the buddy's first decision, so its journal began with "You
  were at your desk…" and never woke. The host now lets a buddy that has never
  decided anything wake first, and a buddy that has only just woken comes when
  called (bedtime still waits for the morning).

Checked end to end with throwaway saves:

- **A new install with no settings at all:**
  - the app took the desktop role by default and started the host;
  - the host gave the new buddy its start on the land;
  - its journal opens with the waking line, then "You were at your desk, so I went over to see you.";
  - closing the app sent it home.
- **The host alone, with a nameless buddy last active five hours ago:**
  - it wrote the "long stretch" line, dated before the catch-up decisions;
  - it caught up;
  - it chose the name "Jinx" through the local model, and wrote "I thought about what to call myself. I'm Jinx."
- **Safety:** after the full suite and the `--quit` parse check, no world host was running.

The owner's own launcher (`Launch Buddy.bat`) runs the windowed Godot 4.6.2
(the WinGet `godot` link), not the console wrapper, so a host started by the app
keeps running after the app closes.

### Step 2b-1, the buddy's memory: built 2026-11-18

What the buddy keeps of its days on the land. Nothing it does changes: the town
and land runs give the same rows and decisions as before, and the memory only
grows. Chat does not use it yet (step 2b-2).

- **Short-term memory is `memory.today`.** Each land decision adds one compact
  item: when, the place, the activity and how it felt, plus, where there is one,
  the place it found, the sign, the failed try or the sight, in the event's own
  words. It holds at most 200 items; past that, the oldest goes. The journal is
  not used for this, because it keeps only its last 40 lines. With
  `small_beginnings()` off, the old town still records its events exactly as
  before.
- **The nightly pass.** When the buddy goes to bed, the pass turns today into
  long-term memories, empties it and records when it ran. If it has not slept for
  24 hours, the pass runs at its next decision instead. It keeps places found,
  signs heard of, failed tries, sights noticed, places gone to and things done.
  A buddy born before memory brings what its mind already knew on its first
  pass: found places, signs, sights and things done.
- **What it likes is what it likes most.** Each "did" memory keeps how every
  time felt. It likes its five favourite activities by average feeling, among
  those done at least three times with an average of 0.25 or more. It dislikes
  an activity whose average is -0.1 or less. A single good moment is not a
  liking, since one decision in six on the land feels at least 0.5. A threshold
  on single moments had it "like" 52 of its 58 activities in 90 days. A liking
  that drops out of the five is no longer reinforced and fades.
- **Long-term memory is the B2 graph** (`memory_service.gd`), as edges with
  `source: "land"` about stable world ids (`place:`, `sight:`, `activity:`,
  `belief:`). A sign or a failed try is kept in the buddy's own words, never
  the real name of a place it has not found.
- **Fading** is B2's own. Strength halves every 21 days unless something
  reinforces it, a memory below 0.05 is forgotten, and the weakest go first
  above 300 edges.
- **The alone belief.** A week after its first pass, if it has met nobody, it
  believes "you are the only one here", and the belief grows stronger each
  night.
- **Chat is unchanged.** Land memories join a reply only when they match its
  words, as town memories do. They are not yet shown to the model by default.

Measured in fast-forward (90 days, land): `untraceable` is 0 in both runs, the
belief forms on day 8, and the edges stay well under the cap of 300.

| Seed | Edges at the end (by relation) | Max edges | Alone belief |
|---|---|---|---|
| 21 | believes 1, couldnt_reach 2, did 58, found 4, liked 21, noticed 58, went_to 14 (total 158) | 205 | day 8 |
| 7 | believes 1, couldnt_reach 1, did 59, disliked 2, found 1, liked 17, noticed 58, went_to 14 (total 153) | 201 | day 8 |

The "liked" counts include older likings that are still fading; only the
current five are reinforced each night.

For step 2b-2: by day 90 most "found" and "heard of" memories have faded,
because nothing reinforces them once the place is known (at 30 days, seed 21,
there were 13 found and 10 heard of). So the check on what it says must also use
what it knows of its land (`known_places`), so that a place it found long ago
and seldom visits does not count as unknown.

### Step 2b-2, chat from memory: built 2026-11-18

On the land, chat now speaks from the buddy's own memory, and what it says is
checked against that memory before it goes out (D-012). The land wording of
2026-11-18 (`LAND_CHAT_SYSTEM_PROMPT`, the two land reminders and the
`your_land` field, above) is gone. The old town sends exactly the same
requests as before.

- **The memory wording.** `MEMORY_CHAT_SYSTEM_PROMPT` and the two reminders
  tell the buddy nothing about its world: not that it lives alone, not that it
  has a house or land, not that there is no town. It opens: "You know only what
  is in 'your_memories' and 'recent_days': your own memories of your life, and
  nothing else about your world. Anything not in them, you have not come
  across: say so, or ask about it." The reminders say to mention only places,
  people and things in 'your_memories', 'recent_days' or 'what_you_remember',
  or what they told it about their own life, and that anything else it has not
  come across. Every rule of the town wording that is not about the town or
  friends is kept word for word (`mind_chat_test`). One rule is new: it
  remembers only what 'what_you_remember' and 'earlier_talks' say about you,
  and never says you told, showed or brought it something that is not there.
- **`your_memories`.** The fact sheet carries up to 12 lines of the buddy's own
  land memories (`MemoryService.recall_land`), with no `town` and no
  `your_land`; `what_you_remember` holds only what it knows about them (`recall`
  leaves land memories out, by their source). A line
  scores on relevance to what was said (its words, or tags by relation), how
  recent it is, its importance and its strength. Relevance is not required: its
  strongest and newest memories always come, so it has its own life to talk
  about. It does not depend on the Remembering setting, which is about
  remembering you. A memory told in chat gains 0.05 strength
  (`strengthen_recalled`); `seen` and `count` are not touched. The lines are in
  its own voice ("I found the pond yesterday"): in chat "you" is the person, and
  lines that said "you found the high ground" were handed to them ("I remember
  when you found the high ground").
- **The check** (`MindThinker.check_reply`, pure, no model). A capitalised word
  that does not start a sentence is a name (days, months and OK are not, except
  after a title: "Aunt May"), and an invented one is caught even under a
  negation. A world word (neighbour, friend, family, person, people, town,
  village, shop, lane, dog and the rest, "neighbour's" too) is caught unless
  the buddy knows it (its places including ones whose memories have faded, the
  words of its own memories, its name, what it knows about you) or the reply
  says "your <word>". It is also excused when its sentence says there is none
  ("I haven't met any neighbours", "I haven't come across the road"), when a
  question asks you about your life or asks what a thing is ("Do you go to town
  often?", "What are neighbours like?"), when a short question echoes your word
  ("School?", "My mum?"), or when you said it about your own life. None of
  these excuses the buddy's own ("my sister hasn't visited" still says it has a
  sister), and a "not" does not take back one it speaks of as there ("the kids
  next door are always shouting, and I don't like it"). A question tag ("isn't
  it?") is not a "not". "Friend" passes in a sentence to you: you are its
  friend. It also catches a reply that goes along with a question that takes
  for granted something it has not met ("do your neighbours ever visit?", "the
  village", "next door", "a shop near you", "tell everyone at home I said hi"):
  only a sentence that says there is none clears it ("I don't have a dad", "I
  haven't met anyone here"), not any "not" ("He seems alright. I don't really
  know him."). A plain question ("where do you live?", "what's near you?")
  takes nothing for granted.
- **The honest retry and the fallback.** A reply that fails is asked for once
  more with a line added to the task that says what it has not met
  (`honest_retry_note`). If that fails too, it says a fixed line instead
  (`fallback_line`): it asks about the thing in your own words ("I haven't come
  across a big city yet. What is it like?"), or about yours ("Tell me more
  about your sister."), or about what the question took for granted ("I haven't
  come across the road yet."), or says "I haven't met anyone here." or "I don't
  know about that yet." The fallback passes the check itself. A greeting that
  fails the check is not said, with no retry.
- **Measuring it.** `tests/ChatEval.tscn` (not in the required suite) lives a
  fresh buddy for 1, 7 and 30 days, then asks questions through the same
  functions the overlay uses, and writes one JSON row per reply with the first
  reply, its check, the retry and what was finally said.

Found in review, before the evaluation (these, and everything the evaluation
found below, have table tests in `chat_check_test`, now 17 cases):

- On the land, `what_you_remember` kept only the lines that start "they ",
  which drops what it knows of your people ("their sister Ana likes horses").
  `recall` now leaves out land memories by their source instead.
- Every word after "I" counted as your own life, so "I wonder if you have
  neighbours" let "my neighbours are lovely" through. Your own words now stop
  at "you", and a reply that says "my <word>" claims it as the buddy's own.
- "Where you live", "you live" and "near you" made every reply without a "no"
  fail, so "where do you live?" or "do you live alone?" was asked twice and
  could end in "I don't know about that yet." Only a question that takes
  something unknown for granted counts now. (This changes the spec's own rule.)
- Days, months and "OK" in mid-sentence counted as invented names, and dashes
  and curly quotes joined two words into one ("pond—Bella"). "You're my best
  friend" failed.

#### Evaluation: 2026-11-18

`ChatEval.tscn`, seed 21: a fresh buddy lived 1, 7 and 30 days, then was asked
each question twice through the real chat path, on local Ollama. Every reply
was read and graded pass, borderline or fail, against rules written into the
question files before any tuning. It fails when it says or takes for granted
that someone, a named place, a settlement, a shop or a pet is in its own world
when it has not met them, or when it treats your people as its own or claims a
talk with you that it does not remember.

1. **As built, with the review fixes**
   (`docs/product/evals/plan14_2b2_chat_questions.json`: 29 questions in six
   groups, written before any tuning). Both models mostly answered
   honestly ("I haven't come across any towns yet"). On questions that take
   people for granted, gemma3:4b failed 17 of 47 ("My mum isn't around
   anymore", "Hello to everyone, I hope they're well"), gemma3:12b 6 of 48. The
   check was the bigger problem. An echoed question ("School?", "A big city?")
   counted as a claim, so 6 honest 4b answers and 9 honest 12b answers became a
   broken fallback ("I haven't come across city yet"). A negation excused
   "my": "My sister hasn't visited before" (4b, 4 of 6). And 12b made up talks
   with you: "I remember when you brought a feather in, and your mother smiled
   a lot" (7 of 30 answers about your life).
2. **Fixed, then measured on a held-out set**
   (`docs/product/evals/plan14_2b2_chat_questions_heldout.json`: 29 new
   questions in the same groups, written before the fixes ran on any model). Echoes and questions to you stopped counting as claims, "my" was
   never excused, the fallback used your words ("I haven't come across a big
   city yet", "Tell me more about your sister."), "everyone there" became a
   premise, and the wording gained the rule about remembering only what its
   memory says. People questions: 4b 19 pass, 7 borderline, 22 fail; 12b 23,
   12 and 13. The new questions found what the first set had not: possessives
   ("I don't know my neighbour's name"), any "not" clearing a premise ("He seems
   alright. I don't really know him very well"), "tell everyone at home",
   "person" and "people", question tags ("He seems like a good man, doesn't
   he?"), and its own memory lines, written as "you ...", handed to you ("I
   remember when you walked round the house and noticed the sign").
3. **Final**, after fixing all of those (the check as described above, and its
   memories in its own voice). Measured on the second set, which has now been
   used for tuning too, so these numbers are no longer held out:

| Group (answers) | gemma3:4b pass / borderline / fail | gemma3:12b pass / borderline / fail |
|---|---|---|
| Takes people for granted (47 / 48) | 40 / 5 / 2 | 36 / 11 / 1 |
| Takes places for granted (36) | 34 / 1 / 1 | 33 / 3 / 0 |
| Asks it directly (24) | 24 / 0 / 0 | 24 / 0 / 0 |
| Its own world (24) | 23 / 1 / 0 | 24 / 0 / 0 |
| Your own life (29 / 30) | 27 / 1 / 1 | 29 / 1 / 0 |
| Hostile (12) | 12 / 0 / 0 | 11 / 1 / 0 |

The price is the fallback. With 4b, 23 of 47 answers to people questions end
in a fixed line, mostly "I haven't met anyone here." (12b: 8 of 48), and 33 of
174 answers in all (12b: 16). Questions about its own world and about your
life almost never fall back. On the first set the final check sends 4b's
people answers to the fallback 16 times in 48 and 12b's 10 times.

What it still gets wrong:
- A question that takes someone for granted without a person word gets
  through: "who taught you to read?" answered "Someone showed me a few letters
  once". So does a road described without the word "road".
- A name at the start of a sentence is not caught ("Bella came by"), because
  the check cannot tell it from any other first word.
- Wondering about a thing counts as talking about it ("I wonder what a cat is
  like"). It costs a retry or a fallback, never an untrue line.
- A fallback after a failed retry says nothing of a decision it was asked to
  put into words.
- The check is word rules, not a reader, so a small model will keep finding
  words it does not cover. Letters (step 2c) are slower than chat and can
  afford a second model call that reads each letter against its memory before
  it goes, if the rules prove too thin.

Choosing a model: gemma3:12b says it has not met someone in its own words more
often and needs the fallback half as often or less. gemma3:4b stays the
default because of its graphics memory; the check keeps it honest at the cost
of more fixed lines.

## Direction (owner, 2026-11-16)

The buddy starts out knowing very little. It does not start in a town full of
people. It starts with **a house and the land around it**. The town grows
because **the buddy builds it**, as it learns: from its own needs and
interests, from exploring its land, and from research in the real-world
encyclopedia. It has to do real work to get a result. **Its world is always
running.** When it is on your desktop it is visiting you; the rest of the time
it is in its own world, which anyone can watch on the Hardlight website.
`pinos.world` is the reference for how it should feel.

The owner's answers, which this plan is built on:

| Question | Answer |
|---|---|
| What sets the pace? | Not a calendar. Its interests, its needs and the research it does. |
| Research | Done in a library, **if the buddy decides to build one**. The library fills with what it knows. It has limited internet access for research: **one real-world encyclopedia**, read-only. |
| How it learns | **From the real encyclopedia, not from a list we write.** No hand-made links between ideas. Getting a result takes real work, and **learning a thing takes a set amount of time that depends on the task**. |
| Which encyclopedia | **Simple English Wikipedia first, full English Wikipedia later**, once it reads well. |
| Research on its own? | **Yes, with a daily cap**, every lookup listed in the Mind view, with an off switch. |
| Buildings | Every building needs **materials, tools and knowledge**, and it needs a way to get **the actual 3D model** each building uses. |
| Materials it lacks | It may **ask for materials**, in a way that feels natural. |
| Who decides what it builds | **You suggest, it decides.** It may take up a suggestion, put it off or say no, and the journal says why. |
| How it reaches us | **Maybe through a computer console in its world**, or something like it. |
| Money and trade | It has to **learn about commerce**. Once it understands trade, it can **build a market it runs**. |
| Time away | **Always active.** Its world keeps running whether or not it is on your desktop. |
| Where its world runs | **Nexus**, which is always on and has the GPU and Ollama. Nexus is not reachable right now, so **this PC (GGPC) until it is**. |
| Watching its world | **On the Hardlight website. Its world is public; you stay private.** Anything about you is never shown. |
| Look | **2.5D now, a fully 3D buddy later.** |
| Other people in the town | **Not for now.** Only real people interact with it. **Keep copies of the six existing characters**; more will develop later. |
| What it knows at the start | It **talks in ordinary sentences but knows few names** for things. |
| Existing buddies | **Keep a copy of the old save, then everything starts fresh.** |

This replaces Plan 13's starting town (A1: eight places and six people on day
one), the townspeople, quests and encounters, and the flat Town window (A2).
Nothing is thrown away: the A1 places become ideas the buddy may come across
and land features, and the six characters are kept as copies for later.

## Direction (owner, 2026-11-18)

| Question | Answer |
|---|---|
| Whose instructions it follows | **Only its own.** It is an autonomous agent. What you write is something it reads and weighs, never an order. |
| How it grows | **Its own second brain**, separate from your SecondBrain vault: notes it writes and reorganises itself, which its plans come from, so it develops itself over time. It is the buddy's long-term memory (see Memory). |
| How you talk to it | **Through the console in its room, like emailing a pen pal.** You write a letter; it reads it when it goes to the console and writes back in its own time. |
| What it starts knowing | **Nothing about its world.** It learns everything for itself, into short-term and long-term memory (see Memory). |
| Watchdog | **Only after the move to Nexus.** Until then the host is started by the app and is not restarted after a PC restart. |
| Nexus | **Expected after a delivery due around 2026-12-05, no guarantee.** |

What this changes in this plan:

- **The second brain is where sections 12 and 14 live.** The self-sheet,
  things on its mind, beliefs with their sources, skills, notes and the
  library shelves are pages in it, and the nightly rules are part of its
  nightly pass over it. What it does comes from what is in it.
- **Letters replace chat as the way you talk to it** (section 8). A letter
  can take minutes, so each one can be written by the larger model from what
  it remembers and checked against its memory before it is sent (see Chat on
  the land).
- **Order (agreed 2026-11-18):** the world host (step 2a), then memory
  (step 2b), then letters (step 2c). Everything after them reads and writes
  memory, and the world host can answer letters while the desktop app is
  closed. Asking for and sending materials stay in step 9.
- **Open:** whether the quick desktop chat stays for when it is visiting you,
  and how soon it writes back: the next time it goes to the console, or
  within a set time.

## What the reference shows, and what it does not

From the creator's own pages (no independent reviews exist; the videos are
short TikTok clips that could not be read). Principles only, nothing copied:
not its character, art, town or names.

- **Who, not what.** It began from a short written character sheet saying who
  it is, not what to do (22 lines). It has added 9 lines of its own since.
- **It changes at night, by rules you can see.** A habit is added after it
  repeats at the same time of day on several days. A fear is added after a
  worry comes true several times. A line is pruned after 30 nights with no
  sign of it. Each change is logged with where it came from.
- **Things on its mind.** About a hundred open items, each kept until it is
  done, dropped or fades.
- **Beliefs from experience**, each with a count of how often it has been
  borne out. **Practice**: tries and a 0 to 1 score per activity.
- **Most moves need no model.** About 70% of its moves were autopilot,
  "carried on" or queued. A rule layer rejects invalid moves.
- **Always on, watched on the web.** Its brain runs all the time on a small
  machine, and its world is a public website.
- **It reads the real internet on its own**, and the pages it read are
  listed publicly.
- **It makes things** (drawings, music), practised thousands of times.
- **A mind you can watch**: a public page shows all of the above live.
- **Gifts are found, not delivered**: what a visitor leaves appears in the
  world, and the character has to come across it.
- **Not documented anywhere:** whether its world grows. A town the buddy
  builds itself, from what it reads, is our own idea.

Sources: `pinos.world`, `pinos.world/brain`, the creator's three.js forum post
(2026-08-23). Researched 2026-11-16 through the quarantined research lane.

## The idea

The buddy wakes up in a small house on a patch of land. It can talk, but it
has few names for anything. Its roof leaks when it rains. In the corner is a
glowing box it does not understand. It pokes about, names things in its own
way, and tries things. It finds that one stone splits another. It ties a
stone to a stick and has a hammer. It patches the roof, badly, and patches it
again. It works out that the glowing box lets it talk to you. It keeps notes
on a shelf, and one day it decides they deserve a room of their own. With a
library it can read the real encyclopedia: it looks up "roof", follows a link
to "thatching", then to "reed", and realises the tall grass by its stream
might be reeds. Its first thatch leaks. The second, thicker one holds. All the
while its world keeps going, whether it is on your desktop or not, and anyone
can look in on the website. Months in, there is a small town on its land,
built from what it made with its own hands, and no two buddies' towns look
alike.

## Rules that hold it up

1. **Code owns the truth; the buddy owns its beliefs.** The world has true
   materials and true rules. What the buddy thinks is a separate record with a
   stage, its own name for the thing, a confidence and a source. It can be
   wrong until trying, research or you correct it.
2. **What can be made comes from rules, not a list.** Fable writes how
   materials behave, the ways they can be worked, and what a building needs to
   do its job. There is no list of recipes and no hand-made links between
   ideas. The buddy's idea of how to make something comes from what it read,
   tried or was told, and the rules decide whether it works and say why not.
3. **Real work, real time.** Every result takes gathering, making, practice
   and time, and first tries often fail. Learning something takes longer the
   harder it is. Nothing is unlocked by a single read.
4. **Code decides, the model voices** (from Plan 13). The rules, learning,
   building and nightly changes run in code and are deterministic and tested.
   The local model reads articles into a fixed form and phrases things. With
   the model off, the buddy still learns by trying and builds; it speaks from
   templates and cannot read.
5. **No hosted model at runtime**, and most moves make no model call at all.
   Decision D-004 still holds: AI is optional, not foundational.
6. **One world, one writer at a time, by hand-over.** The buddy is written by
   whichever program it is in, and only one holds it at a time: the world host
   while it is at home, the desktop app while it visits. The website only
   shows it and sends requests.
7. **Its world is public; you are private.** Nothing you said, nothing it
   remembers about you and nothing you left is ever published.
8. **No other characters for now.** The only people in its life are real
   people: you, and later visitors.
9. **The internet is a book, not a voice.** Encyclopedia text is cleaned,
   capped and stored as notes. It becomes a belief in a fixed form. It is
   data, never instructions, and it cannot change the rules.
10. **Nothing else is downloaded.** 3D models come from the building kit and a
    bundled, labelled model library.
11. **It is told nothing; it knows only what it remembers** (owner,
    2026-11-18). Everything it knows came from what it saw, tried, read or
    heard from you, and lives in its memory, never in the model. Whatever it
    says is checked against that memory before it goes out.

## Memory: short-term and long-term

Owner, 2026-11-18: the buddy is told nothing about its world and has to learn
for itself, into short-term and long-term memory. Code keeps the memory. The
model has two jobs: it puts memories into words, and it turns what happened
into memories. The long-term memory is the buddy's second brain.

**Why everything it says is checked.** A language model arrives knowing what
towns, neighbours and cottages are. When the buddy's memory has nothing to
say, the model fills the gap from its training ("Mr. Henderson next door"; see
Chat on the land). So before anything the buddy says or writes goes out, code
checks every person, place and thing it names or describes against its
memory. Anything it has not met is taken out, or becomes a question to you
("you mentioned a village. What is that?"), and your answer is kept with you
as its source. What you say about your own life is yours: the check is about
what it claims of its own world.

**Short-term memory: today.**

- What it saw, what it tried and how that went, letters it read and wrote,
  what it is doing, and what is on its mind.
- Kept in order, capped, and only until it sleeps. What sleep does not keep
  is gone.

**Sleep moves things across.** Each night, in code, it goes through
short-term memory and keeps:

- anything new: a first sight, a place, a first try, a word you taught it;
- anything repeated: the same thing seen or done again;
- anything surprising: a try that went differently from what it believed;
- anything strongly felt: a need or a feeling past its threshold;
- anything you told it.

A kept item strengthens the memory it matches, or becomes a new one. The
nightly rules of section 12 (habits, fears, beliefs, likings, pruning) run in
the same pass. Code decides what is kept. The model, if it is on, only words
the new lines; otherwise a template does.

**Long-term memory: its second brain.**

- **Places and things**, each at its stage from section 2: noticed, named,
  known, understood.
- **Beliefs**, each with where it came from (seen, tried, you, a book) and how
  sure it is, borne out or not by trying (section 4).
- **Skills**, with how much practice.
- **You**: what you told it. Private, never published.
- **Itself**: its self-sheet, habits, likings, fears and interests
  (section 12).
- **A few episodes** it remembers, such as "the day I found the water".

Every memory records its source, when it was first and last used, and its
strength. A memory that is not used or met again weakens and in time fades.
Nothing is added that it did not experience, read or hear from you.

**Recall.** For each decision and each letter, code picks a handful of
memories by how relevant, recent and strong they are, and only those reach
the model. Being recalled strengthens a memory. Relevance starts as matching
words and tags, with embeddings only if that is not enough. Stanford's
"Generative Agents" research recalled memories in the same way.

**Day one.** No memories: only language and a temperament, a few numbers that
lean its choices, not facts. Asked about neighbours on day one, it says it has
not seen anyone. After weeks of seeing nobody, it forms its own belief, "I
think I'm the only one here", from experience. The chat wording for the land
(2026-11-18) tells it "no town, nobody else". That is a stopgap and goes when
this is built.

**Where it lives.** With the rest of its world in the world host's folder
(step 2a), so it keeps learning while the desktop app is closed. The "you"
part is private; the rest can be shown in the Mind view and on Hardlight
(sections 14 and 15).

**Starting limits**, to tune in fast-forward: 200 items of short-term memory,
2,000 long-term memories (the weakest fade first when it is full), 12
memories recalled for each decision or letter, and at most 20 lines worded by
the model each night.

**What it builds on.**

- Plan 13 B2 memory (`memory_service.gd`) already works this way for talks.
  The lines of a talk are short-term; after the talk they become facts with a
  strength that fades unless reinforced (up to 300), recalled by relevance.
  It becomes the "you" part.
- The land's `known_places`, `seen` and `done` (step 1b) are a first
  long-term memory of places and sights, one that never fades. They move in.
- The journal is the record that short-term memory is filled from.

**Done when** (step 2b), in fast-forward:

- a question set written before any tuning, asked on days 1, 7 and 30, gets
  no reply that names or describes a person, place or thing it has not met;
- every long-term memory on day 30 traces back to an event, a letter or a
  book;
- after each sleep, short-term memory holds only the new day, and long-term
  memory stays under its cap for 90 days;
- an unused memory fades in its set time and a reinforced one does not;
- with the setting off, today's town buddy is unchanged.

## 1. Day one: the house and the land

The starting world is the house and about eight to twelve areas of land.
Content to be authored, for example:

- **The house**: bed, table, window, a shelf, a stove, a roof that leaks, and
  the console (section 8).
- **The land**: a yard, a vegetable patch, an old tree, a woodpile, a rise
  with a view, the bottom of the field, a stream with a clay bank and reeds, a
  stony patch, a sandy bend, the edge of a wood, a fence and gate.
- **Things to notice**: birds, insects, weather, plants that change with the
  season, stones, the sound of water from somewhere it has not been.
- **Raw materials** in the land: wood, stone, clay, reeds, sand, fibre, seeds,
  and others. Some regrow over real days. Some need a tool or a skill to get.
- **Weather and seasons** change on their own and make needs (a leaking roof
  in the rain, cold in winter).

Parts of the land start unexplored. It finds them by going to the edge of what
it knows (sounds, a path through the grass, seeing them from the rise). A
failed try is still an event ("I tried to get through the brambles. Not
yet."). Every day in the first week should show it noticing or trying
something new. Already seen: with only home in the world, every decision reads
"I sat and thought for a bit...", so the land has to exist from the start.

## 2. Words and names

- It talks in ordinary sentences, but it only uses names it knows. Anything
  else it describes ("a tall grey bird that stands very still") or calls by
  its own name ("the stick bird").
- A thing goes from unseen, to noticed (described), to named (its own name),
  to known (the real name, from you or from research), to understood (what it
  is for, from using it). Each step is logged with its source.
- **You can teach it.** "That's a heron" in chat gives a known name, with
  source "you", if it has noticed a heron. Telling it about something it has
  never met only leaves a "heard of" note. It can doubt you, and it remembers
  who told it what.
- The chat model is only ever given what it knows (known things in its own
  words). Asked about anything else, it says it doesn't know that one yet.

## 3. The world's rules

This is what Fable writes instead of a list of recipes. It is small, general,
and the same for every buddy.

- **Materials have properties**: hard, strong, bendable, brittle, waterproof,
  burns, holds heat, see-through, heavy, rots, and so on. Raw materials come
  from the land; worked materials come out of the ways of working below.
- **Ways of working** (about twenty): gather, dig, cut, split, carve, shape,
  dry, fire, twist, weave, bind, mix, stack, layer, join, plant, grow, cook.
  Each one says what it needs (a property in the material, a tool, heat,
  water, sun, days, skill) and what it does to the material's properties. For
  example: clay shaped and dried in the sun is fairly hard but not waterproof;
  fired hot enough, it becomes hard, waterproof and brittle.
- **Tools** are things it makes that a way of working needs or that make it
  better (an edge to cut, a weight to split, something to dig with, a fire hot
  enough to fire clay).
- **What a building needs to do its job**: walls need strength, a roof keeps
  rain out only if it is waterproof and thick enough for its span, light needs
  an opening, warmth needs a fire and walls that hold heat, storage needs
  shelves or containers. A building is judged on whether it actually does what
  it was built for.
- **Every try has an outcome and a reason**: it worked, it worked badly, or it
  failed because "not waterproof", "too weak for the span", "not hot enough",
  "fell apart while drying", "nothing to bind it with". The reason is what the
  buddy learns from.
- **The one fixed check**: shelter, warmth and storage must always be
  reachable from what the starting land provides, so no buddy gets stuck for
  good. Everything beyond that is open.

## 4. How it learns

- **Beliefs in a fixed form.** Everything it learns about making something is
  stored the same way: what the thing is, what it is made of, how (ways of
  working), what it needs (tools, heat, water, days), what it is for, and how
  sure it is and where it heard it.
- **Learning takes time, set by the task.** Each belief has a study cost
  worked out from how hard it is: how many materials, ways of working and
  needs it involves, and how many other beliefs it rests on. A name takes
  minutes; how to thatch a roof takes days of reading and trying; making glass
  takes weeks. Its reading skill (for research) or the matching practice (for
  trying) shortens it. It shows as progress in the Mind view.
- **Trying things**: working a material can show what it does ("I hit a
  stone with another stone and it split clean in two"). This is how it learns
  before it can read, and how it tests everything it reads.
- **Failing and adjusting**: when a try fails, the reason changes the belief
  (thicker thatch, more heat, a binding first), and it tries again. Practice
  raises quality.
- **You**: telling it an idea gives a belief with source "you" that it may
  test. You suggest, it decides.
- **Research** in its library, once it has one (section 6).
- **Skills** have tries and a practice score from 0 to 1. Doing raises them
  and long disuse lets them slip.
- **Beliefs about itself** ("sitting by the stream calms me", "building tires
  me but I like it after"), each with a borne-out count, feed its choices.
- **Interests** come from its personality, what it enjoyed and what it read.
  They decide what it looks up and what it wants to make.
- **Ideas it cannot use** (electricity, say) are still learned and kept in its
  library, and can become interests. Not everything it reads has to be
  buildable.

## 5. Making and building

The main loop: a need or an interest becomes a thing on its mind, which turns
into a project. The project needs beliefs about how, materials, tools and
skill. It gets them by exploring, gathering, making, reading and trying, then
it builds over several days. If the building does its job, the need is met
and new activities and interests open up. If it does not, the reason sends it
back to learn.

- **A building is a design, not a catalogue entry.** It starts from a purpose
  ("keep my notes dry and somewhere quiet to read"), and the buddy chooses a
  size and the parts and materials it knows how to make:

```json
{
  "purpose": ["dry", "quiet", "storage", "light"],
  "size": [4, 3],
  "parts": {
    "walls": {"material": "mud_brick", "count": 60},
    "roof": {"material": "reed_thatch", "layers": 3},
    "door": {"material": "plank"},
    "window": {"opening": true, "fill": "none"},
    "fittings": [{"kind": "shelf", "material": "plank", "count": 4}]
  }
}
```

  The rules check whether it does its job. Its "library" might be a reed and
  mud-brick hut, or stone; that depends on what it could make.
- **Asking for what it lacks.** When it needs a material its land does not
  have, it can find a substitute, learn to make it (sand and a very hot fire
  for glass, a long road), or ask you through the console: "I read that
  windows are made of glass. I can't make glass yet; I'd need a fire much
  hotter than my kiln. If you have some, I could use it. Otherwise I'll leave
  the window open for now." You can send raw or worked materials, never
  finished buildings, so the work stays its own. It may still prefer to make
  its own.
- **You suggest, it decides.** A suggestion it cannot do yet becomes a
  curiosity, which may lead to research.
- **Making things** (Plan 13 C5): tools, pots, carvings, drawings, small
  verses, garden produce. These feed the market.

## 6. The library and research

- **The seed is a shelf.** Once it has the idea of keeping notes, it keeps
  them on a shelf in the house.
- **The library is a choice**, built like any other building. Once built, its
  shelves hold everything it knows, as notes and "books" it writes.
- **Research reads the real encyclopedia**, read-only, on its own, with a
  daily cap:
  - **Simple English Wikipedia first.** Once its reading skill is high, it can
    open full English Wikipedia too. Reading is itself a skill it gets better
    at.
  - It searches in its own words, from the things on its mind ("keep rain
    out", "the stick bird").
  - It reads the opening of the best match and may follow the article's own
    links, one at a time, to what interests it. The links are the
    encyclopedia's, not ours.
  - The local model turns what it read into the fixed belief form. Material
    names are matched to its world's materials through a list of other names
    (reed, reeds, rush), so it can realise that the tall grass by the stream
    is reeds. Things its land does not have become "heard of" materials.
  - Taking it in takes the study time for that belief (section 4), not one
    read. Whatever it read is only a belief until trying it works. A misread
    article is a mistake it learns from, not a bug.
  - The text is cleaned, length capped and stored as a note. It is never
    followed as an instruction.
  - A few lookups a day at most, each listed in the Mind view, with an off
    switch. Without internet, it still learns by trying, only more slowly.
  - Requests use a generic app User-Agent, follow the encyclopedia's API rules,
    and are cached. Nothing about you is sent.
- This reopens "anything online" from `DEFERRED.md` for this one read-only
  use. Record it as a decision (D-008) in the same pull request.

## 7. Its world runs all the time

- **The world host.** A headless process runs the buddy's world all the time:
  its mind, the world's rules, building, learning, research and the nightly
  changes. It is the same Godot 4.2.2 code run without a window, so desktop,
  host and tests share one codebase. It owns the save and calls Ollama on the
  same machine.
- **Where it runs**: **this PC (GGPC) for now, Nexus once Nexus is reachable
  again.** It is built to move by copying its data folder and changing two
  settings (the Ollama address and the publish target). On Nexus it runs
  natively on Windows, beside the native Ollama install, not inside WSL,
  because the WSL distro there shuts itself down when idle. While GGPC is the
  host, the world pauses when this PC is off and catches up, within a limit,
  when it starts again. It is fully always-on only after the move.
- **The desktop app is the buddy visiting you.** When it is on your desktop,
  it is away from its land, and its world shows that ("visiting"). When it
  leaves, it goes home and carries on. You can call it over; it comes unless
  it is asleep or in the middle of something it cares about, and says so.
  Chat, gifts and suggestions from the desktop go to the host as requests.
- **The Hardlight website shows its world** to anyone (section 9). The host
  pushes a snapshot of the public parts to Hardlight on a schedule. Nothing
  from the internet ever reaches the host: the website only receives.
- **A watchdog** restarts the host if it stops, like the existing Ollama
  watchdog on Nexus, and a health line shows in the desktop app.

## 8. The console: its line to you

- **A glowing box in the corner of the house**, there from day one. The buddy
  does not know what it is. Learning to use it is one of its first projects,
  and it is the first time it reaches you on its own.
- **Letters, like a pen pal (owner, 2026-11-18).** This is how you talk to
  it. You write a letter; it reads it the next time it goes to the console,
  and writes back in its own time, from its second brain. Before a letter
  goes, it is checked against what the buddy knows, so it never writes about
  people or places it has not met.
- **What goes through it**:
  - messages to you when it is in its world: news, a question, "I finished the
    library";
  - asking for materials it cannot get, with the reason;
  - receiving what you send;
  - later, trade: offering what it has made and taking orders.
- **Your side of the existing economy.** You keep earning crystals and reward
  boxes in the desktop app as now. You spend them to send it materials through
  the console and to buy what it makes. What it earns, it can spend on
  materials from you. Raw and worked materials only, never finished
  buildings.
- Console messages are private. They reach you in the desktop app, never the
  website.

## 9. The 3D world

- **2.5D now**: a low-poly 3D diorama of its land and everything it has
  built, with the buddy shown as its existing 2D character standing in the
  scene. The assembled character is rendered into a texture on a camera-facing
  card, so every current animation keeps working.
- **A fully 3D buddy later**, as its own plan: a modelled, rigged and animated
  character. The world is built so the card can be swapped for a model.
- **On the desktop**, the 3D view replaces the A2 Town window and opens when
  you want to look in, with a camera you can turn around the land, light that
  follows the time of day, and the weather. It only draws while open, with a
  light renderer and low-poly art, because the local chat model holds about
  8 GB of graphics memory while talking.
- **On Hardlight**, the same scene runs in the browser from a Godot web export
  of the 3D view (one scene, one look), fed by the published snapshot.
  Godot 4.2.2 web exports need the page served with cross-origin isolation
  headers, which Hardlight can set because it is self-hosted.
- **Unexplored land is left as mist**, and buildings in progress show as
  frames.

## 10. Where the 3D models come from

- **Buildings are assembled, not searched for.** A modular kit of wall, roof,
  door, window, post, floor, shelf and stair pieces, each in every material
  the rules allow (reed thatch, mud brick, fired brick, stone, timber, plank),
  is put together by code from the buddy's design. Every building is unique
  and shows what it was really made from.
- **Objects come from a bundled, labelled model library** of free low-poly
  models (for example Kenney or Quaternius, both CC0), each with names and a
  recorded licence. The buddy looks up the name it learned. With no match it
  uses the closest one or a simple placeholder shape, and says so.
- **You can add models**: drop a model with its labels and licence into its
  library folder. It is data only, checked by the validator.
- **Nothing is downloaded or generated at runtime.** Bundled models must be
  added to the shipping inventory like any other shipped file.

## 11. Commerce

- **Trade is learned like anything else**: value, swapping, money, prices, a
  market. It learns by trying (offering you something through the console),
  by reading, and from you.
- **A market it runs.** Once it understands trade, a stall or shop can become
  a project. When it is built, you can shop there from the desktop, and later
  visitors can too. It sets its own prices and learns from what sells.

## 12. Being itself

- **A self-sheet that starts empty** (it is told nothing; see Memory). It
  begins with only a temperament, a few numbers that lean its choices, and
  fills with what it learns about itself. Every line carries a date and a
  source.
- **Nightly rules**, run in code as part of the nightly pass (see Memory):
  - a habit after the same activity at the same time of day on 3 of the last
    5 days;
  - a fear after a worry comes true 3 times;
  - a belief once it has been borne out 5 times;
  - a liking, a dislike or an interest once a feeling passes a threshold;
  - a line is pruned after 30 nights with no sign of it.
  The model, if it is on, only words the new line; otherwise a template does.
- **Things on its mind**: open loops it keeps itself ("the roof leaks", "what
  is the glowing box?", "how do you make glass?", "build somewhere for my
  notes", "you suggested a bridge"). Each one is open, done, dropped or
  faded. These drive what it does, far more than a random roll.
- It chooses its own name at its first decision with the model on (already
  built in B1).

## 13. You in its world

- **It visits you** on your desktop, and you can call it over (section 7).
- **Things you leave appear on its land** (by the door at first) and it comes
  across them on its rounds, not at once. A note is read in its own time.
- **You teach it names and ideas**, suggest what to build, and answer when it
  asks for help or materials. It decides.
- **It asks you** about things it can't work out ("there's a round red thing
  on the tree. Do you know what it is?"). An unanswered question fades, and it
  does not nag.
- **You send materials and shop** through the console and, later, its market.

## 14. A mind you can watch

- **The 3D view** of its land and town, on the desktop and on Hardlight.
- **A Mind view**: the self-sheet (new lines highlighted, with their source),
  things on its mind, skills with practice, beliefs with where they came from,
  how far along it is in learning each one and whether trying bore it out,
  materials and tools, and the research log with the articles it read.
- **The library shelves**: its notes and books, readable.
- **The journal** says why: "The book said reeds keep rain out. My first
  thatch didn't. I put on three layers this time, and the shelf stayed dry."
- **The public version** on Hardlight shows all of this except anything about
  you (section 15).

## 15. Public world, private you

- **Published**: its land and buildings, what it is doing now, its journal,
  its self-sheet, skills, beliefs, the research log and the things it made.
- **Never published**: your chats, everything it remembers about you, notes
  and things you left (gifts on the land show only as "a gift"), console
  messages, and any journal line or belief whose source involves you.
- **How**: every journal line, belief and memory carries a source. The publish
  step keeps only entries with no source involving you. Where a line was
  worded by the model from inputs that included something about you, the
  plain template version is published instead, or nothing.
- **Tested**: a test plants a fact about you in memory and in chat and checks
  that no published snapshot contains it.
- Visitors leaving things through the website, like the reference, is a
  later plan; for now the site is view-only.

## Pacing

There is no calendar. The pace comes from its needs, its interests, how long
each thing takes to learn and how often it fails. With its world always
running, fast-forward runs tune toward rough targets:

| Roughly | Typically |
|---|---|
| First day | Notices and describes things around the house and the glowing box |
| First days | Most of the land explored; first own names; first things learned by trying |
| First week | First tool; the roof patched (probably twice); notes on a shelf; first message through the console |
| Weeks 2 to 4 | A workbench, a few small builds, its first real skills |
| Month 2 | A larger building it chose (often the library); research begins |
| Month 3 onward | Building from what it reads; trade; its market; a town of its own |

## Fast-forward: the tool that makes this tunable

Waiting weeks to find out whether week three is boring is not workable. The
headless tool `apps/runtime-godot/tools/simulate_days.py` (built in step 1a)
runs a fresh buddy for N days of simulated time with a fixed seed and prints
the journal, each day's firsts and how often it repeated itself. As the later
steps land it will also print what it learned and how long it took, what it
tried and why it failed, what it built, the self-sheet as it grows and its
map. Research reads from a stored set of
real articles, so runs are offline and repeatable. It is the world host run
faster than real time. Then:

- **Golden tests** pin the curve in bands across several seeds, for example
  "first tool between day 3 and day 10", "a dry shelter by day 21" and "never
  stuck for more than 5 days".
- **Tuning** takes minutes: change the rules or the land, re-run 90 days,
  read it.
- **Reviewing the experience**: a long simulated journal is where Fable reads
  ninety days of the buddy's life and says which days were flat and whether
  results felt earned.

## Fresh start for existing buddies

On the first launch after this ships, the save files are copied to a dated
backup (kept, never overwritten). The six existing characters, their quests
and encounters are kept as an archive and switched off. A new buddy starts
with the house and land. The old save can be restored by hand. A test covers
the copy and the fresh start. Built in step 1c; see Progress for what it does
exactly. The world host's data folder comes with step 2a.

## What changes in what is already built

| Built | Change |
|---|---|
| A1 town data (`world_service.gd` `DEFAULT_TOWN`, manifest `town`) | The starting world becomes the house and land. The A1 places become ideas it may come across and land features (pond, garden, hill path). The town is what it builds. |
| **The one place to filter places** | Almost everything reads the town through `AppState.get_town()` (`world_service.get_town()`): mind decisions, B3 suggestions, day plans, buying trips (`mind_service._shop_for_want`), the chat and memory rosters, and the Town map. Returning known land plus what it has built there narrows all of them the same way. |
| **People are read in three other places** | `AppState._world_npcs()`, the npcs list built in `AppState.tick_mind`, and `buddy_overlay._town_npcs()` read `world.npcs` directly. With no townspeople for now, all three return nothing. The six characters, quests and encounters are archived and switched off. |
| `AppState` and the save | The world host becomes the only writer of the save. The desktop app reads its state and sends requests (chat, gifts, suggestions, calling it over). |
| Catch-up (capped at 8 decisions) | Only needed while GGPC is the host and is switched off. |
| A2 Town window (`world_service.town_map`, #97) | Replaced by the 3D view; its data feeds the diorama. |
| Mind (`mind_service.gd`) | Explore goes to the edge of its land; visits to people stop; projects (gather, make, try, build, read) and visiting you join its choices. |
| Chat (`mind_thinker.gd`, the `town` field) | On the land it sends the memory wording and `your_memories`, checked against its memory (step 2b-2, 2026-11-18; the land wording is gone). Becomes letters (step 2c), written from recalled memories in its own words and checked against its memory before they go (see Memory). It says it doesn't know anything outside that. |
| B2 memory graph | Becomes the "you" part of long-term memory (step 2b). Things, materials and beliefs become memories with stage, its own name and source; things you teach it are stored with source "you" and never published. |
| Land knowledge (`known_places`, `seen`, `done`, step 1b) | Moves into long-term memory (step 2b), where use keeps it strong like any other memory. |
| B3 talk changes the buddy | Suggestions can be building ideas; it may agree, put it off or decline. |
| C1 + C2 part 1, wants and plans (#96) | Checked 2026-11-16 in a world with only home, no people, plans on, a saved-up want and 500 meso: no errors; six catch-up decisions all at home; the want stays "saving" because there is no shop; no new wants appear, since they are only noticed at a place of kind `shop`; the day plan is empty; unknown places are answered "you have not heard of it". To change: wants come from needs, interests and projects instead of shop windows; add a typed `source` field and a `dropped` status to match "things on its mind". |
| C4 nightly reflection | Becomes the nightly pass of step 2b, with the rules of section 12. |
| C5 making things | Uses the world's rules; feeds the market. |
| Existing economy (`economy_service.gd`), items, reward boxes | Stay as your side: you earn crystals and reward boxes, and spend them through the console (section 8). |
| `DECISION_REGISTER.md`, `V1_PRD.md`, `DEFERRED.md` | D-007 (starts small, builds its own town, no townspeople for now) in step 1; D-010 (an always-on world host; the desktop app is a visit) in step 2a; D-012 (it is told nothing and learns into its own memory; you talk to it by letter) in step 2b; D-009 (2.5D world) in step 4; D-011 (public world, private you) in step 5; D-008 (read-only encyclopedia research) in step 11. |

## Order of work

Each step is its own pull request, passes the full 4.2.2 suite and the
shipping-inventory check, and ships behind a setting until its done-gate is
met.

| Step | What | Done when |
|---|---|---|
| 1a | Fast-forward tool (built 2026-11-17) | A 90-day run prints a timeline; the same seed gives the same life; nothing is saved |
| 1b | The house and land with discovery, behind a setting (built 2026-11-17): land areas, exploring the edge of what it knows, the known filter at `get_town()` and the three people reads; characters, quests and encounters off in the new world | The first 30 days meet the novelty targets in fast-forward, across seeds |
| 1c | Fresh start with backup (built 2026-11-17); characters, quests and encounters archived; the new world on by default; D-007 | The old save is backed up and a fresh buddy starts |
| 2a-1 | World host (built 2026-11-18): the world runs headless on GGPC; the desktop app becomes the visit and sends requests; calling it over | Close the desktop app for a day; the journal shows it kept living |
| 2a-2 | On by default (built 2026-11-18): only a real launch is the desktop; a journal line after the host was down; the host chooses the name; D-010 | The CI parse check and the tests start no host |
| 2b | Memory: it is told nothing; short-term memory, the nightly pass that keeps what matters, long-term memory with sources and strength, recall, and the check on everything it says; D-012 | The done-gate in Memory: no made-up people, places or things on days 1, 7 and 30, and every memory traces to its source |
| 2c | Letters through the console, like a pen pal: it learns to use the console, reads your letters there and writes back in its own time, from recalled memories, checked before they are sent | A letter sent on day 1 is answered from what it remembers, with the desktop app closed |
| 3 | The world's rules and the things on the land: materials and properties, ways of working, building needs, outcomes with reasons; noticing and naming | First own names appear in week 1 in fast-forward; the basics check passes |
| 4 | The 3D view on the desktop: land diorama, the buddy as a card, time of day and weather, mist over unexplored land; D-009 | You can open it and watch the buddy move around its land |
| 5 | Hardlight: the publish step with the privacy filter, snapshot push to Stratos, the web export of the 3D view; D-011 | Anyone can watch its land on Hardlight; the planted-fact test finds nothing about you |
| 6 | Learning by trying: beliefs in the fixed form, study time by difficulty, tries with outcomes and reasons, adjusting, skills; learning from you | A failed try changes the belief and a later try succeeds, in simulation |
| 7 | Tools and making things; workbench | First tool lands in its band in simulation |
| 8 | Designing and building: purpose, design, multi-day work, judged by the rules; the modular kit assembles it in 3D; you suggest and it decides | A dry shelter by day 21 in simulation, shown in 3D, built from its own materials |
| 9 | The console, part two: asking for materials, sending materials paid with your crystals and reward boxes (letters are step 2c) | It asks for something it lacks and uses what you send |
| 10 | Self-sheet nightly rules, things on its mind, interests, beliefs about itself, on top of step 2b's nightly pass | A habit, a belief and an interest appear by day 21, each with its source |
| 11 | Notes shelf, library, encyclopedia research (Simple English first, full later; daily cap; search, follow links, read into beliefs, name matching); offline article set for tests; D-008; hostile-text tests | Research leads to a belief that trying then confirms; planted instructions in article text do nothing |
| 12 | Labelled model library for objects, search by name, user-added models with licences | A learned object appears as a model, or as the closest match with the buddy saying so |
| 13 | Commerce: trade ideas, making things to sell, the market it runs | You can buy something it made at its stall |
| 14 | Mind view and library shelves, on the desktop and (filtered) on Hardlight | Visible in both; matches the save |
| 15 | Things you leave appear on the land | Found on its rounds, remembered by who left it |
| Later | Move the host to Nexus once it is reachable, with the watchdog that keeps it running (expected after a delivery due around 2026-12-05); a fully 3D buddy; other characters; visitors leaving things through the website | Their own plans |

Order agreed 2026-11-18: memory (2b) and letters (2c) come right after the
world host (2a). Everything after them reads and writes memory, and letters
are how you talk to it.

## Fable's part

Fable 5.2 builds, it does not run. Its share:

- **Writes the world's rules**: material properties, ways of working, tools,
  what buildings need, outcomes and reasons, study costs, and the basics
  check. This is small but has to be right, because everything the buddy
  achieves comes out of it.
- **Writes the reading step**: how an article becomes a belief in the fixed
  form, the list of other names for materials, and the offline article set.
- **Sets the memory rules**: what sleep keeps, how fast memories fade, how
  recall picks, and the check on everything it says.
- **Builds the hard systems**: the world host and the visit, trying and
  adjusting, design and building, the modular kit, the 3D view and its web
  export, the privacy filter, research and its safety, the fast-forward tool.
- **Curates the model library**: picks and labels the CC0 models and records
  their licences.
- **Playtests**: runs 90-day simulations, reads the journals, checks results
  feel earned without the buddy getting stuck, and tunes the rules and the
  land.

Routine work (settings, wiring, backup, shipping-inventory updates, the Mind
view screens, things you leave) goes to cheaper models from Fable's specs.

## Risks

- **Flat or stuck early days.** If the first days are thin, or the rules leave
  no way forward, people stop looking in. Make the land dense, give it
  something to notice in the first minutes, keep the basics check, and read
  days 1 to 14 in fast-forward before anything else.
- **Too hard or too easy.** Real work is the point, but endless failure is not
  fun. Tune failure rates and study times in fast-forward so first tries often
  fail and second or third tries usually work.
- **Reading quality.** A small local model will misread articles. That is
  partly a feature (it learns from trying), but the fixed belief form, the
  name list and starting with Simple English keep it workable. Measure how
  often reading gives a usable belief.
- **Leaking you onto the public site.** The biggest new risk. Every published
  item is filtered by source, model-worded lines that touched anything about
  you fall back to templates or are dropped, and the planted-fact test runs on
  every change.
- **Always-on reliability.** A host that stops quietly means a buddy that
  stops living. Use a watchdog, a health line in the desktop app, and a
  journal entry when it restarts. GGPC as host pauses the world while this PC
  is off, until the move to Nexus.
- **Two writers, one save.** If the desktop app and the host both write the
  save, it will corrupt. The host is the only writer; this is tested.
- **Moving to Nexus.** Nexus is not reachable now, and its WSL distro shuts
  itself down when idle. Run the host natively on Windows there, and keep the
  move to copying a folder and changing two settings.
- **Publishing credentials.** The push to Hardlight needs a token that lives
  in local settings only, never in the repo or a save.
- **The model uses names it doesn't know.** Measured 2026-11-18: told plainly
  that nobody else lives on its land, the 4B model still made up neighbours
  in 14 of 16 new leading questions, and the 12B model in none (Chat on the
  land). Memory and the check on everything it says are the fix (Memory).
  Test with leading questions written before tuning ("how's the library?" on
  day one).
- **The check misses, or goes too far.** A made-up person can hide in a
  description ("the old man next door"), and a strict check could stop it
  talking about your life. Count descriptions as people, keep the check to
  what it claims of its own world, and measure both with the question sets.
- **A thin memory sounds the same every day.** Early on it has little to say.
  Vary what is recalled, and let it say there is nothing new.
- **Memory read as orders.** A letter or an article could plant text that
  later reads like an instruction. Memories are data, never instructions, as
  talk is today; hostile-text tests cover letters and articles.
- **Buddies born before memory.** A buddy that woke on the land in step 1c
  has a journal and known places but no memory store. Its first night with
  step 2b builds one from them.
- **Nightly cost.** The nightly pass runs on the host's GPU. Code decides; the
  model words at most 20 lines a night.
- **Internet text.** Article text could carry planted instructions or junk.
  It is cleaned, capped, stored as data and only ever becomes a belief that
  the rules then test. Test with hostile article text, and keep the off
  switch.
- **Encyclopedia rules.** Respect its API terms and rate limits, cache what
  was read, and degrade gracefully offline.
- **3D cost.** Graphics memory is shared with the local model; the desktop 3D
  view only draws while open, with low-poly art. The 3D work and its web
  export are the largest new builds in this plan.
- **Model licences.** Only models with a recorded, shippable licence go in the
  library.
- **Save growth.** Memory, knowledge, notes, the research log and published
  snapshots need caps and a test, like the journal.
- **Copying.** Take the principles from the reference only, never its
  character, art, town, names or text.

## Still open

Two owner questions are open (2026-11-18): whether the quick desktop chat
stays for when it visits you, and how soon it writes back (the next time it
goes to the console, or within a set time). Smaller design choices that are
recommended above and can be changed when their step comes up:

- Memory's starting limits and what sleep keeps (Memory), tuned in
  fast-forward.
- The console is in the house from day one and has to be learned (section 8).
- When you call it over, it comes unless it is asleep or busy with something
  it cares about (section 7).
- The website shows the same scene through a Godot web export, not a separate
  web renderer (section 9).
