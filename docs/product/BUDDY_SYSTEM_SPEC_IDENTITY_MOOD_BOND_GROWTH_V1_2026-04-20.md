# Buddy System Spec — Identity, Mood, Bond, and Growth

## Purpose

This document defines the core internal systems that make the buddy feel like a
persistent, developing character rather than a static desktop pet.

This is the **identity spine** of the project.

If this system works, the buddy feels alive.
If this system is weak, everything else feels decorative.

---

## 1. System goals

The identity system must ensure that the buddy:

* feels like one persistent individual over time
* begins partly shaped by the user but becomes more itself through play
* has visible emotional state
* forms a bond with the user
* changes through care, routine, rewards, quests, and training
* shows signs of growth both emotionally and mechanically
* avoids becoming predictable, robotic, or flat

---

## 2. High-level system structure

The system is made of four connected layers:

1. **Identity layer** — who the buddy is
2. **Mood layer** — how the buddy feels right now
3. **Bond layer** — how the relationship with the user develops
4. **Growth layer** — how the buddy changes over time

These should influence one another continuously.

---

## 3. Identity layer

## 3.1 Purpose

The identity layer defines the buddy as a character.

This includes:

* its base type
* its temperament seed
* its preferences
* its tendencies
* its evolving personality profile

Identity should be partly chosen, partly discovered, and partly shaped over
time.

---

## 3.2 Identity inputs at creation

At minimum, the user should be able to influence:

* **Base type/species**
* **Name**
* **Starting personality seed**
* **Initial visual profile**
* **Possibly a starting affinity or theme lean**

### Design rule

The user sets the starting direction.
The system creates the long-term individual.

---

## 3.3 Base types

The buddy should support **multiple starting base types**.

These do not need to be fully different classes at first, but they should
differ in:

* default flavor
* visual identity
* slight stat leaning
* possible personality tendencies
* some different dialogue flavor

### Example structure

Each base type may include:

* baseTypeId
* displayName
* description
* initial stat lean
* initial personality weights
* possible exclusive traits or future evolutions
* asset set references

### Design rule

Base types should create identity without locking the player into a narrow build
too early.

---

## 3.4 Personality seed

At creation, the buddy should receive a **personality seed**.

This seed gives the buddy an initial tendency profile, not a fixed personality.

### Example starting seeds

* curious
* gentle
* bold
* playful
* thoughtful
* stubborn
* supportive
* mischievous

### Use of the seed

The seed influences:

* early dialogue tone
* likely reactions
* preferred activities
* early trait drift direction
* starting likes/dislikes bias

### Design rule

The seed should matter immediately, but not permanently dominate the identity.

---

## 3.5 Identity variables

The following variables should exist in some form.

### Core identity fields

* id
* baseType
* name
* creationTimestamp
* personalitySeed
* currentPersonalityProfile
* likes
* dislikes
* interests
* activeGoals
* traitHistorySummary

### Personality profile concept

The personality profile may track weighted values such as:

* curiosity
* sociability
* bravery
* playfulness
* diligence
* independence
* empathy
* competitiveness

These values do not all need to be shown to the user directly.

---

## 3.6 Likes, dislikes, and interests

The buddy should gradually develop:

* liked item themes
* disliked item themes
* preferred activities
* favored NPCs or places
* preferred times or routines

### Examples

A buddy might start to like:

* cozy decor
* training often
* certain foods
* a specific village NPC
* one kind of quest theme

### Design rule

Preferences should emerge from play, not just be assigned at creation.

---

## 3.7 Identity evolution

Identity should evolve based on repeated influence.

Major influence sources:

* how the user treats the buddy
* what rewards/themes the user chooses
* what actions are most common
* which quests are completed
* what training the buddy receives
* what routines the buddy performs when idle
* what kinds of reactions the buddy has during real user activity

### Design rule

Identity drift should be gradual and cumulative, not chaotic.

---

## 4. Mood layer

## 4.1 Purpose

The mood layer represents the buddy’s **current emotional state**.

Mood should make the buddy feel alive in the moment.

Identity is long-term.
Mood is current.

---

## 4.2 Mood requirements

Mood should:

* update often enough to feel responsive
* be understandable through animation, dialogue, or UI
* influence reactions and choices
* recover or shift naturally over time
* be affected by needs, bond, context, and recent events

---

## 4.3 Mood model

V1 can start simple with one dominant mood plus modifiers.

### Example dominant moods

* happy
* calm
* sleepy
* curious
* lonely
* frustrated
* focused
* excited
* proud
* worried

### Example hidden modifiers

* energy strain
* overstimulation
* social fulfillment
* comfort
* confidence

### Design rule

The mood model must stay readable. Do not make it mathematically deep at the
cost of clarity.

---

## 4.4 Mood inputs

Mood can be affected by:

* hunger/energy/care state
* recent interactions with user
* idle time
* successful or failed activities
* quest results
* battle outcomes
* room/home condition
* social interactions with NPCs
* real-user activity context
* bond state

### Example

If the user has been focused for a long time, the buddy may become:

* quiet and supportive
* curious about what the user is doing
* sleepy if little interaction occurs

If the buddy is frequently trained and rewarded, it may become:

* proud
* energized
* eager

---

## 4.5 Mood outputs

Mood should influence:

* lines of dialogue
* idle behavior
* animation choice
* interaction appetite
* event weighting
* training response flavor
* quest prompt style
* home behavior

### Design rule

Mood should change expression, not remove player control unless intentionally
designed.

---

## 4.6 Mood persistence and decay

Mood should not flip randomly.

Suggested behavior:

* recent events create temporary mood pushes
* dominant conditions reinforce mood directions
* time and care slowly normalize extreme states
* bond can soften negative mood outcomes

### Design rule

Mood should feel organic, not volatile.

---

## 5. Bond layer

## 5.1 Purpose

The bond layer represents the relationship between the user and the buddy.

This is one of the most emotionally important systems.

Bond should make the user feel:

* known
* trusted
* appreciated
* attached
* responsible in a meaningful way

---

## 5.2 Bond principles

Bond should grow through:

* time spent together
* care
* consistency
* helping the buddy
* letting the buddy help the user
* meaningful shared routines
* positive event outcomes

Bond should not be based only on repetitive clicking.

---

## 5.3 Bond variables

At minimum track:

* bondValue
* bondLevel
* trustValue
* recentAffectionMemory
* neglect/strain summary

### Possible bond levels

* stranger
* familiar
* friend
* close friend
* trusted companion
* bonded partner

These names can change, but the concept matters.

---

## 5.4 Bond growth sources

Bond should increase from:

* regular care
* gifts the buddy likes
* responding well to its mood
* training together
* quest completion
* showing up consistently
* using home and world features
* allowing the buddy to support the user successfully

Bond may decrease or stall from:

* long neglect
* repeated bad matches between mood and care
* harsh or contradictory treatment if such systems exist
* excessive forcing into disliked activities

### Design rule

Bond loss should be gentle unless the game intentionally supports relationship
damage.

---

## 5.5 Bond outputs

Bond should influence:

* dialogue tone
* trustful or vulnerable lines
* whether the buddy asks for certain things
* willingness to try hard activities
* confidence around the user
* supportiveness
* availability of deeper story or quest moments
* some growth or evolution gates

### Example

At low bond:

* generic reactions
* less expressive personal preference
* more reserved tone

At high bond:

* more specific commentary
* stronger emotional reactions
* more mutual care moments
* personalized goals or shared rituals

---

## 5.6 Mutual-care design

A defining part of this project is that the buddy should also care for the
user.

Bond should therefore also increase when:

* the user accepts the buddy’s help
* the buddy is allowed to participate in routines
* the user follows through on plans the buddy helped with
* the buddy is treated like a companion rather than just a mechanic

### Design rule

Bond should reward reciprocity, not just maintenance.

---

## 6. Growth layer

## 6.1 Purpose

The growth layer defines how the buddy develops over time.

Growth must happen on three connected tracks:

1. **evolution/form growth**
2. **mechanical growth**
3. **personality growth**

---

## 6.2 Growth principles

Growth should:

* be visible
* feel earned
* respond to user choices
* not depend on one single metric
* support different play styles
* create attachment and surprise

---

## 6.3 Evolution/form growth

The buddy should move through visible stages or meaningful visual changes.

### V1 requirement

At minimum:

* a growthStage variable
* stage-specific presentation changes
* stage advancement linked to interaction/progression rather than only time

### Long-term possibilities

* branching evolutions
* theme-driven visual changes
* personality-influenced appearance drift
* stat/build-influenced form changes

### Design rule

The buddy’s form should reflect its life, not just elapsed days.

---

## 6.4 Mechanical growth

Mechanical growth includes:

* stat changes
* unlocked abilities or actions
* improved performance in training or encounters
* new interactions or preferences
* access to more complex quest or world content

### Suggested starting stat set

* Strength
* Dexterity
* Charisma
* Endurance
* Wisdom
* Knowledge

These can later map into:

* battle effectiveness
* social influence
* curiosity/discovery
* task efficiency
* support behaviors

---

## 6.5 Personality growth

Personality growth is how the buddy becomes more itself.

This can include:

* stronger interests
* clearer likes/dislikes
* increased courage or confidence
* greater warmth or independence
* social habits
* worldview flavor in dialogue

### Design rule

Personality growth should emerge from repeated behavior patterns.

---

## 6.6 Growth drivers

Growth should draw from multiple sources.

### Major growth drivers

* care consistency
* bond level
* training patterns
* item and theme exposure
* quest style
* village/social interactions
* encounters and outcomes
* real-user routine mirroring

### Design rule

No single system should completely dominate growth.

---

## 6.7 Growth presentation

Growth must be visible to the user.

Possible signals:

* new animations
* changed dialogue tone
* reports about confidence/interests
* visible stat milestones
* evolution or appearance changes
* new home behaviors
* unlocked activities or preferences

### Design rule

The user should be able to feel the buddy developing, not just see a hidden
number go up.

---

## 7. Inter-system influence rules

These four layers should affect each other.

### Identity -> Mood

A bold buddy may react to uncertainty differently than a gentle buddy.

### Mood -> Bond

Responding appropriately to the buddy’s mood can strengthen bond.

### Bond -> Mood

High bond can make recovery from bad moods faster or make supportive reactions
stronger.

### Growth -> Identity

As the buddy grows, identity becomes richer and more individualized.

### Growth -> Mood

More mature or confident buddies may regulate mood differently.

### Bond -> Growth

High trust and consistency can unlock deeper growth states.

---

## 8. V1 implementation model

## 8.1 V1 minimum viable version

V1 does not need the full final complexity.

It should include:

* base type selection
* personality seed
* mood state
* bond value + level
* growthStage
* simple stat values
* first likes/dislikes foundation
* state changes from care and time
* simple while-away report
* a few differences in dialogue/behavior based on state

---

## 8.2 V1 acceptance criteria

This system is working for V1 if:

* the buddy feels different over time
* the buddy’s mood is understandable
* bond feels like more than a hidden bar
* growth can be noticed
* users can sense that their choices influence who the buddy becomes

---

## 9. Anti-repetition rules for this system

## 9.1 Identity must drift

Do not let the buddy remain permanently static.

## 9.2 Mood must vary without chaos

Do not let the buddy always feel the same, but do not let it become
inconsistent.

## 9.3 Bond must reward consistency and reciprocity

Do not reduce bond to pure spam interaction.

## 9.4 Growth must be multi-source

Do not gate all development behind one narrow action.

## 9.5 Expression must change over time

Dialogue, reactions, and behavior must gradually feel more personal.

---

## 10. Data model foundation

### BuddyIdentity

* id
* baseType
* name
* personalitySeed
* personalityProfile
* likes
* dislikes
* interests
* goals

### BuddyMood

* dominantMood
* moodModifiers
* lastMoodChangeReason
* moodStability

### BuddyBond

* bondValue
* bondLevel
* trustValue
* recentPositiveInteractions
* recentNeglectSummary

### BuddyGrowth

* growthStage
* stats
* milestoneFlags
* traitShifts
* unlockedBehaviors

---

## 11. Open design questions for the next pass

These should be resolved later in implementation planning.

1. How many base types should exist in V1?
2. Which personality seed options should be player-facing?
3. Which variables are visible to the user versus hidden?
4. How aggressive should preference drift be?
5. How much can bond decay?
6. Which growth milestones are cosmetic versus mechanical?
7. How strongly should real-user activity affect mood and growth?

---

## 12. Implementation recommendation

Build this system in the following order:

1. persistent buddy identity object
2. mood model and update rules
3. bond value and level rules
4. growthStage and stat foundation
5. simple likes/dislikes tracking
6. response text differences by state
7. while-away report generation
8. first visible growth expressions

---

## 13. Internal guidance statement

**Identity, mood, bond, and growth are the systems that make the buddy feel
alive. All other systems should reinforce these, not replace them.**
