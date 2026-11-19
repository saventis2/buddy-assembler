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

- **Needs have to fall with time on the world host** (step 2). Today the only
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
  when you talk to it. It gets its outlets with the visit (step 2) and the
  console (step 9).
- **The land alone carries about two months.** After about day 12 the only new
  things are the ones it notices. Over 90 days (seed 7) there was something
  new on 26 days of the first month, 19 of the second and 2 of the third. The
  later weeks fill up when there are things to try and make (steps 3 and 6
  to 8).
- **It crosses its land in one move**, with the walk counted in minutes but no
  route. The 3D view (step 4) is where movement shows.
- **Bond and meso still accrue as before.** They belong to your side of the
  economy and are settled with commerce (step 13).

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
6. **One world, one writer.** The world host owns the save. The desktop app
   and the website only show it and send requests.
7. **Its world is public; you are private.** Nothing you said, nothing it
   remembers about you and nothing you left is ever published.
8. **No other characters for now.** The only people in its life are real
   people: you, and later visitors.
9. **The internet is a book, not a voice.** Encyclopedia text is cleaned,
   capped and stored as notes. It becomes a belief in a fixed form. It is
   data, never instructions, and it cannot change the rules.
10. **Nothing else is downloaded.** 3D models come from the building kit and a
    bundled, labelled model library.

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

- **A self-sheet** of six to ten starting lines saying who it is, not what to
  do. Every line it gains carries a date and a source.
- **Nightly rules**, run in code:
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
- It chooses its own name on the first night (already built in B1).

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

On the first launch after this ships, the current profile save is copied to a
dated backup (kept, never overwritten). The six existing characters, their
quests and encounters are copied to an archive in the content pack and
switched off. A new buddy starts with the house and land, in the world host's
data folder. The old save can be restored by hand. A test covers the copy and
the fresh start.

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
| Chat (`mind_thinker.gd`, the `town` field) | Becomes "what you know", with things given in its own words. It says it doesn't know anything outside that. |
| B2 memory graph | Things, materials and beliefs become nodes with stage, its own name and source; things you teach it are stored with source "you" and never published. |
| B3 talk changes the buddy | Suggestions can be building ideas; it may agree, put it off or decline. |
| C1 + C2 part 1, wants and plans (#96) | Checked 2026-11-16 in a world with only home, no people, plans on, a saved-up want and 500 meso: no errors; six catch-up decisions all at home; the want stays "saving" because there is no shop; no new wants appear, since they are only noticed at a place of kind `shop`; the day plan is empty; unknown places are answered "you have not heard of it". To change: wants come from needs, interests and projects instead of shop windows; add a typed `source` field and a `dropped` status to match "things on its mind". |
| C4 nightly reflection | Uses the nightly rules above. |
| C5 making things | Uses the world's rules; feeds the market. |
| Existing economy (`economy_service.gd`), items, reward boxes | Stay as your side: you earn crystals and reward boxes, and spend them through the console (section 8). |
| `DECISION_REGISTER.md`, `V1_PRD.md`, `DEFERRED.md` | D-007 (starts small, builds its own town, no townspeople for now) in step 1; D-010 (an always-on world host; the desktop app is a visit) in step 2; D-009 (2.5D world) in step 4; D-011 (public world, private you) in step 5; D-008 (read-only encyclopedia research) in step 11. |

## Order of work

Each step is its own pull request, passes the full 4.2.2 suite and the
shipping-inventory check, and ships behind a setting until its done-gate is
met.

| Step | What | Done when |
|---|---|---|
| 1a | Fast-forward tool (built 2026-11-17) | A 90-day run prints a timeline; the same seed gives the same life; nothing is saved |
| 1b | The house and land with discovery, behind a setting (built 2026-11-17): land areas, exploring the edge of what it knows, the known filter at `get_town()` and the three people reads; characters, quests and encounters off in the new world | The first 30 days meet the novelty targets in fast-forward, across seeds |
| 1c | Fresh start with backup; characters, quests and encounters archived; the new world on by default; D-007 | The old save is backed up and a fresh buddy starts |
| 2 | World host: the world runs headless on GGPC with a watchdog; the desktop app becomes the visit and sends requests; calling it over; D-010 | Close the desktop app for a day; the journal shows it kept living |
| 3 | The world's rules and the things on the land: materials and properties, ways of working, building needs, outcomes with reasons; noticing and naming | First own names appear in week 1 in fast-forward; the basics check passes |
| 4 | The 3D view on the desktop: land diorama, the buddy as a card, time of day and weather, mist over unexplored land; D-009 | You can open it and watch the buddy move around its land |
| 5 | Hardlight: the publish step with the privacy filter, snapshot push to Stratos, the web export of the 3D view; D-011 | Anyone can watch its land on Hardlight; the planted-fact test finds nothing about you |
| 6 | Learning by trying: beliefs in the fixed form, study time by difficulty, tries with outcomes and reasons, adjusting, skills; learning from you | A failed try changes the belief and a later try succeeds, in simulation |
| 7 | Tools and making things; workbench | First tool lands in its band in simulation |
| 8 | Designing and building: purpose, design, multi-day work, judged by the rules; the modular kit assembles it in 3D; you suggest and it decides | A dry shelter by day 21 in simulation, shown in 3D, built from its own materials |
| 9 | The console: learning to use it, messages to you, asking for materials, sending materials paid with your crystals and reward boxes | It asks for something it lacks and uses what you send |
| 10 | Self-sheet nightly rules, things on its mind, interests, beliefs about itself | A habit, a belief and an interest appear by day 21, each with its source |
| 11 | Notes shelf, library, encyclopedia research (Simple English first, full later; daily cap; search, follow links, read into beliefs, name matching); offline article set for tests; D-008; hostile-text tests | Research leads to a belief that trying then confirms; planted instructions in article text do nothing |
| 12 | Labelled model library for objects, search by name, user-added models with licences | A learned object appears as a model, or as the closest match with the buddy saying so |
| 13 | Commerce: trade ideas, making things to sell, the market it runs | You can buy something it made at its stall |
| 14 | Mind view and library shelves, on the desktop and (filtered) on Hardlight | Visible in both; matches the save |
| 15 | Things you leave appear on the land | Found on its rounds, remembered by who left it |
| Later | Move the host to Nexus once it is reachable; a fully 3D buddy; other characters; visitors leaving things through the website | Their own plans |

## Fable's part

Fable 5.2 builds, it does not run. Its share:

- **Writes the world's rules**: material properties, ways of working, tools,
  what buildings need, outcomes and reasons, study costs, and the basics
  check. This is small but has to be right, because everything the buddy
  achieves comes out of it.
- **Writes the reading step**: how an article becomes a belief in the fixed
  form, the list of other names for materials, and the offline article set.
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
- **The model uses names it doesn't know.** Chat must only ever see what it
  knows, and a check can catch names it hasn't learned in a reply. Test with
  leading questions ("how's the library?" on day one).
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
- **Save growth.** Knowledge, notes, the research log and published snapshots
  need caps and a test, like the journal.
- **Copying.** Take the principles from the reference only, never its
  character, art, town, names or text.

## Still open

None of the owner questions remain open. Smaller design choices that are
recommended above and can be changed when their step comes up:

- The console is in the house from day one and has to be learned (section 8).
- When you call it over, it comes unless it is asleep or busy with something
  it cares about (section 7).
- The website shows the same scene through a Godot web export, not a separate
  web renderer (section 9).
