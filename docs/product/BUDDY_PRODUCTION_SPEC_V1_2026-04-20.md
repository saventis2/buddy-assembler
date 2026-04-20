# Buddy Production Spec v1

## Purpose

This document converts the Buddy Design Brief into a production-oriented
specification for implementation planning.

This is the **first follow-on document** after the design brief.

---

## 1. Product summary

Buddy is a **modular desktop companion** with three connected modes:

1. **Home module** — the buddy's home space, decor, routines, and
village/social presence
2. **Overlay module** — desktop presence, quick interaction, reactions, quests,
and encounters
3. **Companion module** — lightweight reactions, reminders, and later
AI-enhanced continuity

The buddy is a **persistent character** with:

* identity
* mood
* bond
* growth
* preferences
* items
* optional quests and battle systems

The core principle is:

**The user cares for the buddy, and the buddy cares for the user.**

---

## 2. Production goal

Build a usable, lovable **V1 core buddy loop** that proves the concept before
full village depth, heavy AI, or complex battle systems are added.

V1 must answer:

* does the buddy feel alive?
* does the user form attachment?
* does progression feel rewarding?
* does the product avoid becoming repetitive too quickly?

---

## 3. V1 product scope

## 3.1 In scope for V1

### Core buddy identity

* persistent buddy profile
* selectable base type
* name and initial personality seed
* mood state
* bond level
* likes/dislikes foundations

### Core care loop

* feeding
* resting
* play/training interaction
* light stat or need changes
* buddy response text/reactions

### Overlay presence

* visible desktop buddy
* movement/idling states
* click/hover interaction
* quick reaction lines
* basic reaction to user activity/state

### Life simulation foundations

* buddy performs small idle tasks while not directly interacted with
* simple “while you were away” reporting
* simple daily/periodic routines

### Reward foundations

* inventory
* basic item categories
* rarity tags
* simple reward sources
* crystal currency foundation
* theme-box reward concept, even if only a few themes exist initially

### Home foundations

* first home scene
* limited decor placement or decor slots
* visual signs of buddy activity

### Growth foundations

* growth stage tracking
* simple training influence
* first-pass stat model
* bond affecting some dialogue/behavior

### World foundations

* a very small initial NPC cast
* simple quest/event system
* village/world implied even if not fully explorable yet

### Settings foundations

* interaction intensity level
* notification/reaction frequency controls
* optional systems toggles where needed

---

## 3.2 Out of scope for V1

These can be prototyped, but should not block V1:

* deep AI autonomy
* full natural language memory architecture
* full village simulation
* advanced party combat
* complex equipment build optimization
* large-scale story campaign
* full phone/watch companion parity
* large-scale crafting economy
* heavy social multiplayer systems

---

## 4. V1 success criteria

V1 is successful if:

* the buddy feels persistent and alive
* the user can clearly identify its mood/state
* the user can care for it and see results
* the user can earn and use rewards
* the buddy shows some signs of self-directed activity
* the experience supports short repeat sessions without immediately feeling
stale
* the user can tune interaction intensity
* the product loop is understandable and pleasant without AI being the main
value

---

## 5. Core user experience requirements

## 5.1 Emotional requirements

The buddy must feel:

* present
* responsive
* personal
* non-intrusive
* capable of surprise

## 5.2 Functional requirements

The user must be able to:

* create or select a buddy type
* interact with the buddy quickly
* inspect current state
* influence mood/bond/growth through actions
* receive rewards
* see evidence of life and progression
* adjust intensity/settings

## 5.3 Anti-friction requirements

The buddy must not:

* spam prompts too often
* block normal desktop use
* feel like a chore by default
* repeat the same lines excessively
* require deep system understanding to enjoy basic use

---

## 6. System architecture at the feature level

## 6.1 Persistent state layer

Stores:

* buddy identity
* mood
* needs
* bond
* growth stage
* stats
* inventory
* currency
* unlocked items/decor
* settings
* event history summary

## 6.2 Presentation layer

Includes:

* overlay presentation
* home scene presentation
* UI panels for inventory, stats, and interactions
* event/quest prompts

## 6.3 Simulation layer

Responsible for:

* idle behavior
* timed state changes
* routines
* passive event triggers
* simple life reports

## 6.4 Progression layer

Responsible for:

* rewards
* item grants
* rarity roll logic
* crystals/currency
* growth thresholds
* unlock rules

## 6.5 Interaction layer

Responsible for:

* feed/play/rest/train actions
* NPC/event interaction
* simple quest triggers
* simple encounter resolution

## 6.6 Settings layer

Responsible for:

* intensity controls
* notification levels
* optional system toggles
* user comfort controls

---

## 7. V1 system breakdown

## 7.1 Buddy identity system

### V1 requirements

* multiple selectable base buddy types
* persistent name
* initial personality seed tag set
* mood value/state
* bond value/state
* basic likes/dislikes structure, even if partially hidden at first

### Acceptance criteria

* buddy can be created and loaded persistently
* mood and bond update based on interactions
* at least some buddy lines or behavior differ by state

---

## 7.2 Care system

### V1 requirements

* feed action
* rest/sleep action
* play/train action
* action cooldown or pacing rules if needed
* visible effect on needs/mood/bond

### Acceptance criteria

* user actions clearly change buddy state
* user receives readable feedback after each action
* care loop feels useful, not purely decorative

---

## 7.3 Overlay system

### V1 requirements

* overlay window works consistently
* buddy idles visibly
* buddy can be clicked and interacted with
* buddy can display short messages/reactions
* buddy can lightly react to user activity signals

### Acceptance criteria

* overlay feels stable and non-broken
* reactions appear without overwhelming the user
* user can understand that the buddy is “present” during normal desktop use

---

## 7.4 Life simulation system

### V1 requirements

* buddy has passive routines/tasks
* buddy can report something it was doing while idle
* system can trigger a small pool of passive events

### Acceptance criteria

* buddy does not feel frozen when ignored
* user can observe or read at least one passive-life outcome
* events vary enough to imply a living character

---

## 7.5 Inventory and reward system

### V1 requirements

* item storage
* item categories separated
* rarity field on items
* crystal currency tracked
* first theme-box mechanic or placeholder implementation

### Acceptance criteria

* user can earn at least one item and one currency reward
* user can inspect inventory
* items have meaningful category distinction
* rarity is visible or mechanically relevant

---

## 7.6 Home system

### V1 requirements

* one home scene
* visible buddy in home context
* limited decor usage or display slots
* indication of buddy routines in home

### Acceptance criteria

* user can enter/view home mode
* home looks meaningfully different from overlay mode
* at least one decor/reward object can appear there

---

## 7.7 Growth system

### V1 requirements

* growth stage variable
* simple stat model
* basic training input
* at least one visible or behavioral sign of progression

### Acceptance criteria

* buddy can progress over time
* progression is influenced by user interaction, not only raw time
* user can understand that the buddy is developing

---

## 7.8 NPC and quest system

### V1 requirements

* small set of NPCs
* first quest/event structure
* repeatable or rotating event pool

### Acceptance criteria

* user can encounter at least one named NPC
* user can complete at least one quest-like task
* reward delivery from quest flow works

---

## 7.9 Encounter system

### V1 requirements

* optional and lightweight
* first encounter event type
* simple resolution model
* reward output

### Acceptance criteria

* encounter does not break the core buddy loop
* user can skip or engage based on preference
* encounter rewards feel connected to progression

---

## 8. Content design rules

## 8.1 Variety rules

* do not rely on one repeating phrase set
* rotate passive reports
* rotate buddy wants/interests over time
* rotate event triggers
* rotate reward sources

## 8.2 Tone rules

* buddy should feel warm, charming, and alive
* humor is good, but should not flatten personality into constant jokes
* combat/adventure should not undermine the buddy tone

## 8.3 User respect rules

* minimize annoyance
* allow quiet modes
* avoid manipulative neediness
* support both light and deep engagement styles

---

## 9. Data model foundations

The following data entities should exist, even if initially simple.

### Buddy

* id
* baseType
* name
* personalitySeed
* mood
* bond
* growthStage
* stats
* likes
* dislikes
* currentNeeds
* lastActiveSummary

### Item

* id
* name
* category
* rarity
* theme
* effects
* icon/assetRef
* source

### NPC

* id
* name
* role
* affinity
* availability
* dialoguePool

### Quest/Event

* id
* type
* requirements
* rewards
* repeatability
* narrative text

### Settings

* interactionIntensity
* quietHours
* promptFrequency
* optionalSystemsEnabled

---

## 10. UX priorities

Order of importance:

1. buddy feels alive
2. interactions feel satisfying
3. progression feels visible
4. reward loop feels exciting
5. interface stays simple enough to use casually
6. optional depth remains available without burdening basic users

---

## 11. Production milestones

## Milestone 1 — Stable core buddy

Deliver:

* persistent buddy
* core state
* feed/play/rest interactions
* stable overlay
* basic reactions

## Milestone 2 — Life and reward loop

Deliver:

* passive routines
* while-away reporting
* inventory
* rarity
* crystals
* first reward box/theme

## Milestone 3 — Home and first world layer

Deliver:

* home scene
* first decor integration
* first NPC cast
* first quests/events

## Milestone 4 — Growth and optional encounters

Deliver:

* stat progression
* growth stage improvements
* training influence
* first optional encounter/battle shell

## Milestone 5 — Companion depth foundation

Deliver:

* stronger activity reactions
* user support touches
* better continuity across modules

---

## 12. Recommended implementation order

1. persistent buddy data model
2. stable state updates and save/load
3. overlay interaction polish
4. care loop feedback
5. life simulation basics
6. inventory and rewards
7. home scene
8. NPC/event layer
9. growth/training expansion
10. encounter shell

---

## 13. Risks

### Risk 1 — Repetition

If content variety is weak, the buddy will quickly feel shallow.

### Risk 2 — Feature sprawl

If too many systems are built before the core loop feels good, the project may
become wide but not compelling.

### Risk 3 — Intrusiveness

If reactions are too frequent or poorly timed, the buddy will become annoying
instead of lovable.

### Risk 4 — AI overreach too early

If AI becomes the defining layer before the non-AI loop is fun, the project may
feel unstable or unfocused.

---

## 14. Current recommendation

The immediate next docs after this should be:

1. **Buddy System Spec — Identity, Mood, Bond, and Growth**
2. **Buddy Economy Spec — Items, Rarity, Themes, Crystals, Reward Boxes**
3. **Buddy World Spec — Home, Village, NPCs, Quests, Encounters**
4. **Buddy V1 Build Plan — milestone-by-milestone implementation order**

---

## 15. Internal production statement

**V1 must prove that a buddy can feel alive, personal, rewarding, and
non-repetitive before the project expands into full AI depth, large-scale
combat, or a broad simulated world.**
