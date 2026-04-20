# Buddy Design Brief v1

## 1. Project definition

We are building a **modular desktop buddy companion**.

This is not just a desktop pet, and not just an assistant. It is a
**persistent buddy character** that lives alongside the user across multiple
modes, grows over time, develops preferences and opinions, reacts to the
user's activity, and can optionally take part in quests, rewards, training,
relationships, and battles.

The core idea is:

**The user cares for the buddy, and the buddy cares for the user.**

---

## 2. One-line vision

**A living desktop buddy that grows with the user, lives in a customizable
world, reacts to real activity, builds relationships, earns rewards, and can
optionally go on quests and battles.**

---

## 3. Core fantasy

The user should feel like:

* there is a little intelligent friend living alongside them in their digital
life
* the buddy has its own life even when the user is not directly interacting
* the buddy grows, changes, and becomes more personal over time
* the buddy is both emotionally rewarding and mechanically interesting
* the world around the buddy expands through items, NPCs, quests, decor,
training, and adventure

This should feel more like a **friend with a life** than a **pet with idle
animations**.

---

## 4. Product pillars

### 4.1 Living buddy

The buddy must feel alive even when idle.

This includes:

* routines
* self-directed tasks
* moods
* changing interests
* small reports about what it has been doing
* the ability to mirror aspects of the user's life or patterns

### 4.2 Modular existence

The buddy exists across multiple connected modules.

### 4.3 Bond and growth

The buddy should begin partly customizable, but gradually become more itself
over time.

### 4.4 Reward-rich progression

Items, rarity, themes, and rewards should be a major source of motivation and
personalization.

### 4.5 Optional depth

The experience should support different levels of user investment, from cozy
low-maintenance companionship through to quests, progression, and combat.

### 4.6 Variety over repetition

The experience must avoid feeling static, predictable, or repetitive.

---

## 5. Module definitions

## 5.1 Home module

The home module is where the buddy lives.

Purpose:

* create emotional attachment
* show the buddy's private life and routines
* provide a place for rest, decor, collections, and village life

Features:

* customizable room or home scene
* decor placement
* home objects with interaction hooks
* passive animations and routines
* signs of what the buddy has been doing while away
* visits from NPCs
* storage/display of certain items or trophies

Design goal:
The home should feel cozy, personal, and inhabited.

## 5.2 Overlay module

The overlay module is the buddy's active desktop presence.

Purpose:

* make the buddy feel present during daily computer use
* enable quick interaction
* support reactions, quests, encounters, and short-form systems

Features:

* wandering or anchored desktop presence
* click, hover, drag, and interaction states
* contextual reactions to user activity
* quick care interactions
* quest prompts
* encounters and battles
* short dialogue and event triggers

Design goal:
The overlay should feel alive, fun, and non-intrusive.

## 5.3 Companion module

The companion module is the lighter reactive layer.

Purpose:

* allow small reactions and continuity outside the full home/overlay loop
* eventually support deeper AI behavior and assistance

Features:

* quick reactions
* check-ins
* emotional continuity
* reminders and planning support
* lightweight status updates
* adaptive interaction intensity

Design goal:
The companion module should feel like a friend over the user's shoulder.

---

## 6. Core daily loop

The main loop is:

**User lives their day -> buddy lives alongside them -> interactions build bond
and stats -> buddy earns or unlocks rewards -> home/world expands ->
quests/events appear -> optional combat/training deepens progression -> buddy
personality and form evolve over time**

### Supporting loops

#### Care loop

* feed
* gift
* rest
* encourage
* maintain wellbeing

#### Bond loop

* talk
* react
* support user
* spend time together
* shared routines increase trust and attachment

#### Reward loop

* earn crystals or other currency
* open themed reward boxes
* collect items
* equip, place, gift, use, or save rewards

#### Growth loop

* train stats
* influence build path
* unlock evolutions or personality shifts
* change visual identity and capabilities over time

#### World loop

* meet NPCs
* visit village
* unlock services
* take quests
* trigger events

#### Adventure loop

* encounter monsters or hostile NPCs
* complete quests
* earn drops
* eventually use allies or party support

---

## 7. Buddy identity system

The buddy should have a structured identity model.

### 7.1 Starting identity

At creation, the user should be able to choose or influence:

* base type or species
* name
* initial temperament or personality seed
* appearance base
* starting affinities or theme leaning

### 7.2 Persistent identity

Over time the buddy should track:

* mood
* bond level
* trust/friendship
* likes and dislikes
* interests
* habits
* current goals
* long-term growth path
* important memories

### 7.3 Personality development

The buddy should not remain fixed.

Its behavior can drift based on:

* how the user treats it
* what activities it does most
* what items/themes it is exposed to
* quest choices
* training style
* success/failure patterns
* user routines and lifestyle signals

This should result in the buddy feeling more like an individual over time.

---

## 8. Life simulation system

This is one of the most important systems in the product.

The buddy should have its own life when the user is not directly interacting.

### 8.1 Idle life examples

* cleaning or arranging its space
* exploring the village
* training lightly
* talking to NPCs
* finding a small item
* resting
* observing the user's activity quietly

### 8.2 Return/report behavior

When the user returns, the buddy can mention:

* what it has been doing
* how it feels
* what it found
* what it wants to do next
* what changed in the home or village

### 8.3 Mirroring the user

The buddy may lightly mirror the user in tone or behavior.

Examples:

* user is focused -> buddy keeps itself busy quietly
* user is idle -> buddy checks in or suggests something
* user is up late -> buddy comments on tiredness or changes behavior
* user is productive -> buddy feels motivated and earns small benefits

This must be configurable so it never feels invasive.

---

## 9. Item and reward system

Items should be split into separate categories.

## 9.1 Core item categories

* Food
* Gifts
* Gear
* Decor
* Training items
* Materials
* Quest items
* Evolution items
* Theme-box rewards

## 9.2 Item metadata

Each item should support at least:

* name
* category
* rarity
* theme
* stat effects or mechanical value
* affection/bond value if relevant
* usage context
* source
* visual identity

## 9.3 Rarity and themes

Rarity and theme tags are important for:

* collection goals
* reward anticipation
* progression pacing
* cosmetics
* quest logic
* themed builds or personality influence

## 9.4 Theme boxes and currency

A strong reward system is:

* player earns crystals or similar currency
* player chooses a themed box
* the box grants a random reward from that theme pool

Benefits:

* keeps randomness exciting
* gives player choice
* supports collecting
* allows multiple play styles
* creates a long-term reward loop

Possible theme examples:

* cozy
* magical
* heroic
* spooky
* silly
* nostalgic fantasy

---

## 10. Training and stat system

Training should support both cute moment-to-moment interaction and meaningful
long-term build decisions.

## 10.1 Core stats

Initial target stat set:

* Strength
* Dexterity
* Charisma
* Endurance
* Wisdom
* Knowledge

These can align with familiar RPG logic and can be adapted to fit available
data structures and content sources.

## 10.2 Training modes

### Light training

* short activities
* daily practice
* passive routines
* mini interactions

### Deep training

* strategic stat development
* gear synergy
* growth path influence
* evolution requirements
* quest gating or role specialization

## 10.3 Growth outcomes

Training should influence:

* performance in quests/battles
* dialogue flavor
* confidence or personality leaning
* accessible roles/builds
* visual growth or evolution tendencies

---

## 11. Growth and evolution

Growth should happen across three layers.

### 11.1 Evolution stages

The buddy should visually and mechanically develop over time.

### 11.2 Build changes

Different training and reward choices should create different strengths.

### 11.3 Personality changes

The buddy's emotional and social identity should change as it grows.

These systems should support each other rather than feeling disconnected.

---

## 12. Home, village, and NPC system

The buddy should exist in a wider social world.

## 12.1 Village concept

The user should eventually feel like there is a whole village or community
around the buddy.

This can include:

* friends
* mentors
* rivals
* shopkeepers
* quest givers
* visitors
* unusual or special NPCs

## 12.2 NPC roles

NPCs should:

* give quests
* visit or appear in events
* unlock shops or services
* create emotional story beats
* provide world flavor
* support training, crafting, battles, or social systems

## 12.3 Relationship system

NPCs can track:

* familiarity
* affinity
* trust
* rivalry
* story progression

This helps keep the world dynamic and supports future village depth.

---

## 13. Quest system

Quests should be a major engine of variety.

### 13.1 Quest categories

* daily life quests
* home improvement quests
* village errands
* friendship quests
* training quests
* item collection quests
* monster quests
* discovery/story quests
* user-linked quests connected to real routines or tasks

### 13.2 Quest goals

Quests should:

* create reasons to interact
* introduce NPCs and systems
* reward items or currency
* help variety
* influence bond and growth
* make the world feel alive

---

## 14. Encounter and battle system

Battle content should be optional and scalable.

### 14.1 Core idea

The buddy may encounter enemies or hostile events and can optionally fight
them.

### 14.2 Early implementation goal

Start with a lightweight battle shell:

* short encounters
* basic enemy data
* simple resolution rules
* reward drops
* optional ally support later

### 14.3 Long-term possibilities

* overlay encounters
* separate battle panel or scene
* text/event card resolution for simple cases
* more visual battle modes later
* solo buddy combat early, party support later

### 14.4 Tone

The tone should remain consistent with the buddy concept and feel fun,
charming, and expandable rather than overly grim.

---

## 15. Real activity reaction system

This is one of the strongest future differentiators.

The buddy should react like a friend noticing what the user is doing.

Possible reaction types:

* support
* commentary
* companionship
* gameplay triggers

Examples:

* noticing focused work
* noticing breaks or inactivity
* noticing lateness or fatigue
* noticing repeated habits
* noticing achievements or completion of tasks
* suggesting small next actions
* celebrating progress

This system must include intensity controls.

---

## 16. User intensity settings

The product should support multiple levels of user investment.

### Suggested modes

#### Cozy mode

* low maintenance
* fewer prompts
* mostly companionship and passive progression

#### Balanced mode

* moderate care and rewards
* regular check-ins
* optional quests and training

#### Deep mode

* stronger progression systems
* more events, quests, training, and encounters
* more involved relationship management

Users should be able to adjust how much attention the buddy needs and how often
it reacts.

---

## 17. Anti-repetition rules

This is a critical section.

The project must avoid becoming too predictable or repetitive.

### 17.1 Never rely on one narrow loop

Do not reduce the experience to repeating feed, play, sleep forever.

### 17.2 Rotate events and reactions

Dialogue, events, idle tasks, and quest prompts must vary.

### 17.3 Let preferences evolve

The buddy should not always want the same things forever.

### 17.4 Use multiple reward sources

Crystals, items, progress, and emotional rewards should come from different
types of activity.

### 17.5 Allow different user styles

Some users want cozy companionship. Others want deep progression. The design
must support both.

### 17.6 Preserve surprise

Small discoveries, changing behavior, and world events are important for
keeping the buddy interesting.

---

## 18. Roadmap

## Phase 1: Soul of the buddy

Goal: make the buddy feel alive.

Build:

* persistent buddy profile
* multiple base types
* mood state
* likes/dislikes
* bond level
* simple life simulation
* return/report behavior
* interaction intensity settings

## Phase 2: Stuff and rewards

Goal: make interaction satisfying.

Build:

* inventory
* separate item categories
* rarity model
* theme tags
* crystal currency
* theme boxes
* reward sources tied to different activities

## Phase 3: Home and village

Goal: make the world feel inhabited.

Build:

* home scene
* decor placement
* first NPC cast
* village structure
* shops/services
* recurring events

## Phase 4: Growth and paths

Goal: make long-term progression meaningful.

Build:

* stat system
* training activities
* build tendencies
* evolution stages
* personality shifts
* visual progression

## Phase 5: Quests and encounters

Goal: make adventure real.

Build:

* quest board or quest flow
* enemy encounters
* simple battle shell
* reward drops
* ally support foundations

## Phase 6: Reactive companion depth

Goal: make it truly buddy-like.

Build:

* stronger real-activity reactions
* planning/helpfulness systems
* schedule awareness
* richer memory and AI behavior
* deeper mutual-care loop

---

## 19. Immediate design tasks

Before major implementation continues, define these clearly:

1. buddy base types
2. identity variables and personality model
3. item category schema
4. rarity and theme model
5. crystal and reward economy
6. home and village first-pass layout
7. first NPC cast and roles
8. quest categories and first event pool
9. stat and training model
10. interaction intensity settings
11. anti-repetition content rules

---

## 20. Internal direction statement

**We are building a modular buddy companion that lives alongside the user
across home, overlay, and reactive companion modes. It is a persistent
character with its own life, relationships, preferences, growth, and goals. The
user cares for it, and it cares for the user. Progression comes through
bonding, rewards, customization, quests, village life, and optional combat. The
experience must remain varied, tunable, and non-repetitive.**
