# Buddy Economy Spec — Items, Rarity, Themes, Crystals, and Reward Boxes

## Purpose

This document defines the reward economy for the buddy project.

The economy is not just about loot. It is one of the main systems that makes
the buddy feel rewarding, personal, and varied over time.

A strong economy should:

* support care and growth
* support home and worldbuilding
* support collection and personalization
* support quest and encounter rewards
* create anticipation and surprise
* avoid becoming grindy, flat, or repetitive

---

## 1. System goals

The economy system must:

* give the user regular meaningful rewards
* make items feel distinct and useful
* support multiple play styles
* connect emotional reward and mechanical reward
* use rarity and themes to create excitement and identity
* support long-term collection goals
* stay readable and not become bloated too early

---

## 2. High-level structure

The economy has five main parts:

1. **Item system** — what items exist and what they do
2. **Rarity system** — how valuable or special items feel
3. **Theme system** — how items are grouped aesthetically and behaviorally
4. **Currency system** — how the user earns spending power
5. **Reward box system** — how the user converts earned currency into controlled
randomness

These systems should support one another.

---

## 3. Economy design principles

### 3.1 Reward should come from many activities

Do not tie all valuable progress to one loop.

Rewards should come from:

* care
* bonding
* training
* quests
* encounters
* NPC relationships
* passive buddy life reports
* user-linked real-world habits or productivity, if enabled

### 3.2 Categories should stay separate

Food, gifts, gear, decor, materials, and quest items should remain separate
categories.

This helps:

* balancing
* UI clarity
* content design
* decision making
* future expansion

### 3.3 Randomness should be guided

Pure randomness gets frustrating.

Themed reward boxes are good because they give:

* player agency
* surprise
* collection motivation
* consistent identity

### 3.4 Rewards should be both emotional and functional

Some rewards should help mechanically.
Some should feel special because they are cute, rare, or meaningful.
Both matter.

### 3.5 Economy should support optional depth

Casual users should still feel rewarded.
Deep users should still have meaningful long-term goals.

---

## 4. Item system

## 4.1 Core item categories

The item model should start with these categories.

### Food

Purpose:

* restore hunger or wellbeing
* influence mood
* possibly influence preferences over time

Examples:

* snacks
* meals
* rare treats
* themed foods

### Gifts

Purpose:

* increase bond
* trigger buddy reactions
* reinforce likes/dislikes
* support special moments or milestones

Examples:

* toys
* keepsakes
* flowers
* themed gifts

### Gear

Purpose:

* improve stats
* affect encounters or training
* unlock certain build directions
* provide cosmetic identity where appropriate

Examples:

* accessories
* charms
* light equipment
* role-themed gear

### Decor

Purpose:

* customize home
* affect mood or comfort
* express player style
* reinforce themes

Examples:

* furniture
* wall items
* lighting pieces
* trophies
* decorative objects

### Training items

Purpose:

* improve stat growth
* boost certain activities
* unlock temporary bonuses

Examples:

* manuals
* exercise tools
* practice props
* focus charms

### Materials

Purpose:

* crafting later
* evolution requirements
* quest requirements
* upgrading or combining systems later

Examples:

* crystals
* fragments
* cloth
* essence
* monster drops

### Quest items

Purpose:

* support world and event logic
* deliver story objectives
* unlock NPC progression

### Evolution items

Purpose:

* special progression gating
* rare transformation or milestone support
* high-value emotional/mechanical reward

### Theme-box rewards

Purpose:

* items distributed primarily from curated reward pools
* may overlap with the categories above

---

## 4.2 Item metadata

Every item should have structured data.

### Minimum fields

* id
* name
* category
* rarity
* theme
* description
* icon or asset reference
* stackability
* useEffect or effectProfile
* sourceType
* sellValue or shardValue if needed later

### Optional later fields

* affectionModifier
* preferredByBuddyTypes
* dislikedByCertainTraits
* homePlacementType
* equipSlot
* questTag
* encounterDropTableRef

---

## 4.3 Item functions by category

### Food can affect

* hunger
* mood
* comfort
* preference growth

### Gifts can affect

* bond
* trust
* dialogue moments
* affection memory

### Gear can affect

* stats
* training efficiency
* encounter performance
* visual identity

### Decor can affect

* home appearance
* room comfort
* home event weighting
* buddy mood tendencies

### Training items can affect

* stat gain multipliers
* success rates
* growth thresholds

### Materials can affect

* recipes
* milestones
* exchanges
* evolution prerequisites

---

## 5. Rarity system

## 5.1 Purpose

Rarity creates:

* excitement
* long-term chase goals
* meaningful differentiation
* specialness in rewards
* reasons to engage across time

---

## 5.2 Suggested rarity tiers

A simple starting model:

* Common
* Uncommon
* Rare
* Epic
* Legendary

Optional later:

* Mythic
* Event-only
* Unique

### Design rule

Do not overuse high rarity early.
If everything is special, nothing feels special.

---

## 5.3 What rarity should affect

Rarity can influence:

* drop chance
* visual treatment
* stat potency
* bond impact
* theme identity strength
* evolution relevance
* home prestige or display value

### Design rule

Not every rare item must be mechanically stronger.
Some rare items can be prized because they are beautiful, thematic, or
meaningful.

---

## 5.4 Rarity by category

### Food

Mostly common to rare, with special treats at epic or legendary.

### Gifts

Can range widely; some gifts should be emotionally special rather than
combat-strong.

### Gear

Strong fit for rarity progression.

### Decor

Rarity works well for collection, visual status, and home uniqueness.

### Materials

Rare materials can become long-term chase goals.

### Evolution items

Often should be rare or special-case.

---

## 6. Theme system

## 6.1 Purpose

Themes organize the emotional and visual identity of rewards.

Themes help:

* user agency
* curation
* personalization
* preference formation
* world flavor
* reward box structure

---

## 6.2 Theme examples

Initial examples:

* Cozy
* Magical
* Heroic
* Spooky
* Silly
* Nostalgic Fantasy
* Natural
* Academic
* Mechanical
* Royal

These are examples only. Final themes should match the visual/content pool
available.

---

## 6.3 Theme tagging

Each item can have:

* one primary theme
* optional secondary theme tags

Example:
A lamp could be:

* primary: Cozy
* secondary: Magical

A training ribbon could be:

* primary: Heroic
* secondary: Royal

---

## 6.4 Theme uses

Themes should influence:

* reward box contents
* buddy likes/dislikes development
* decor/home identity
* NPC flavor
* quest/event pools
* evolution tendencies later

### Design rule

Themes are not just cosmetic labels. They should reinforce the whole product
identity.

---

## 7. Currency system

## 7.1 Purpose

Currency gives the player control over rewards.

Primary currency should support:

* anticipation
* planning
* targeted randomness
* activity reward pacing

---

## 7.2 Primary currency: Crystals

Crystals are the main recommended currency for curated reward box spending.

Crystals should be:

* easy to understand
* earned from many activities
* paced according to effort
* valuable enough to matter

---

## 7.3 Crystal earn sources

Crystals can come from:

* daily interaction
* care streaks
* quest completion
* encounter wins
* training milestones
* village/NPC relationship milestones
* achievements
* passive buddy discoveries
* real-world productivity or habit actions, if enabled

### Design rule

Higher effort should usually yield more crystals, but low-effort users must
still feel included.

---

## 7.4 Suggested reward weighting model

Not strict numbers yet, but general principle:

### Small crystal gains

* quick care actions
* short check-ins
* light passive activities

### Medium crystal gains

* training completion
* normal quest completion
* routine consistency
* moderate village/event engagement

### Large crystal gains

* major milestones
* rare encounter wins
* relationship breakthroughs
* special events
* longer-term achievements

---

## 7.5 Optional secondary currencies later

Possible later additions:

* village tokens
* encounter medals
* seasonal/event currency
* friendship tokens
* crafting shards

### Design rule

Do not add many currencies in V1.
Start with crystals and only add more when they solve a clear design problem.

---

## 8. Reward box system

## 8.1 Purpose

Reward boxes should convert earned currency into exciting but partially
controlled rewards.

This system is one of the strongest ways to keep the reward loop fresh without
making it feel arbitrary.

---

## 8.2 Core loop

The user:

1. earns crystals from activities
2. chooses a theme box
3. receives a random reward from that theme pool
4. uses, equips, places, saves, or gifts the item

This creates:

* anticipation
* choice
* surprise
* collection goals
* emotional attachment to rewards

---

## 8.3 Reward box structure

Each box should define:

* boxId
* theme
* cost
* contained categories
* rarity table
* possible guaranteed rules if any
* special seasonal or event flags if any

### Example box rules

A Cozy Box might contain mostly:

* decor
* gifts
* food
* occasional rare comfort item

A Heroic Box might contain mostly:

* gear
* training items
* trophies
* rare stat-themed items

---

## 8.4 Box differentiation

Boxes should not feel like reskinned duplicates.

Different boxes should vary by:

* likely categories
* mood/theme identity
* rarity distribution
* possible exclusive items
* possible buddy reaction flavor

---

## 8.5 Duplicate handling

Duplicates will happen.

Possible duplicate strategies:

* allow duplicates for stackable or reusable items
* allow conversion to shards or partial crystals
* allow gifting/selling/recycling later
* allow duplicates to be useful in home collection sets

### Design rule

Duplicates should not feel completely dead.

---

## 8.6 Box economy rules

To keep boxes satisfying:

* costs must feel reachable
* common pulls must still have some value
* rare pulls must stay exciting
* themed choice must matter

### Design rule

The user should feel: “I chose the kind of surprise I wanted.”
Not: “I paid for total nonsense.”

---

## 9. Reward sources

## 9.1 Care rewards

Rewards from:

* feeding
* resting
* helping mood recovery
* showing consistency

These should usually be smaller but regular.

## 9.2 Bond rewards

Rewards from:

* trust milestones
* shared routines
* good gift matching
* accepting buddy support

These should feel more personal.

## 9.3 Training rewards

Rewards from:

* stat milestones
* completed sessions
* growth breakthroughs

## 9.4 Quest rewards

Rewards from:

* task completion
* NPC progress
* world discovery
* story beats

## 9.5 Encounter rewards

Rewards from:

* drops
* materials
* rare gear
* special tokens later

## 9.6 Passive life rewards

Rewards from:

* buddy finding something while idle
* buddy completing a self-task
* village interactions
* environmental/home events

### Design rule

Passive rewards should feel charming and supplemental, not replace active play
entirely.

---

## 10. Economy roles across the product

## 10.1 Emotional role

The economy should create feelings of:

* delight
* anticipation
* pride
* attachment
* “this suits my buddy” personalization

## 10.2 Mechanical role

The economy should support:

* care
* growth
* quests
* training
* encounters
* home customization

## 10.3 Long-term role

The economy should sustain:

* collection goals
* theme identity
* evolving buddy preferences
* home improvement
* milestone chasing

---

## 11. V1 implementation scope

## 11.1 V1 must include

* separated item categories
* item metadata foundation
* visible rarity field
* crystals as main currency
* at least a few theme tags
* at least one reward box flow
* at least one reward source from care, one from quests/events, and one from
passive or milestone progression

## 11.2 V1 does not need

* complex crafting
* auction/trading systems
* many currencies
* large duplicate-conversion economy
* very large box catalog

---

## 12. V1 acceptance criteria

The economy is working for V1 if:

* the user can earn crystals
* the user can receive and inspect items
* categories clearly matter
* rarity creates visible differentiation
* theme boxes feel distinct
* rewards come from more than one activity type
* the reward loop feels exciting enough to encourage return use

---

## 13. Anti-repetition rules for the economy

## 13.1 Rewards must come from varied sources

Do not make every meaningful reward come from one loop.

## 13.2 Themes must matter

Do not make theme boxes feel cosmetic only.

## 13.3 Commons must still be useful

Do not let the economy make most rewards feel like trash.

## 13.4 High rarity must stay rare enough to feel good

Do not flood the user with special items too quickly.

## 13.5 Duplicates need a plan

Do not let duplicate pulls feel totally wasted.

---

## 14. Data model foundation

### Item

* id
* name
* category
* rarity
* primaryTheme
* secondaryThemes
* description
* effectProfile
* assetRef
* sourceType
* stackable

### CurrencyWallet

* crystals
* optionalLaterCurrencies

### RewardBox

* id
* theme
* cost
* rarityTable
* possibleItems
* categoryBias
* eventFlags

### RewardTransaction

* sourceType
* sourceId
* itemRewards
* currencyRewards
* timestamp

---

## 15. Open questions for next pass

1. Which themes should exist in the first playable version?
2. How many reward boxes should V1 support?
3. Should certain buddy types prefer certain themes from the start?
4. How visible should drop rates be to the user?
5. What is the best duplicate conversion rule for V1?
6. Which rewards should be exclusive to quests or encounters?
7. Which categories should be allowed inside each theme box?

---

## 16. Recommended implementation order

1. item schema and category definitions
2. rarity and theme fields
3. inventory and item display
4. crystals wallet and reward transactions
5. reward-source hookups
6. first theme-box implementation
7. duplicate handling rule
8. tuning pass for drop feel and pacing

---

## 17. Internal guidance statement

**The reward economy should make the buddy feel richer, more personal, and more
alive. Items are not filler — they are one of the main engines of attachment,
surprise, progression, and identity.**
