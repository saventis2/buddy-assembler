# PLAN11_MAPLE_V83_UI_REBUILD.md

> **Direction change, 2026-11-15 (owner decision).** Menus keep the Maple feel and this plan's
> interactions (icon slot grid, hover tooltips, tabs, compact windows) but are drawn in code by
> `scripts/ui/maple_theme.gd` instead of using the original v83 window pictures and button art.
> Reasons: the pictures carry fixed labels and sizes that did not line up with Buddy's controls,
> they only exist on a machine with extracted Maple files, and a shipped build may only contain
> tracked assets. The "WZ Method-Parity Rules" and asset lists below are kept for reference and
> are no longer requirements. Item icons still come from the Maple files when present.
>
> Landed in that pass: shared theme on every window; main menu with plain labels (Chat, Journal,
> Stats, Inventory, Wardrobe, Pause, Settings, Quit); settings grouped under headings with
> switches for autonomy and the thinking model and developer tools behind a toggle; inventory and
> wardrobe slot grid with tooltips, selection, worn marker, empty states and a detail panel.
> Still open from this plan: paper-doll equip slots, compact/expanded inventory, drag and drop.

## Goal
Rebuild runtime menus to match MapleStory v83 UI behavior first, then reattach Buddy features.

No hybrid list-style fallback UI. Inventory and equip must be icon-slot based with hover tooltip behavior.

## Source Of Truth (v83 assets)
Primary UI atlas root:
- `C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz\UI\UI.wz\UIWindow.img.*`

Key extracted panel assets:
- Inventory compact: `UIWindow.img\Item\backgrnd.png` (175x289)
- Inventory expanded: `UIWindow.img\Item\FullBackgrnd.png` (603x289)
- Equip compact: `UIWindow.img\Equip\backgrnd.png` (175x304)
- Equip expanded: `UIWindow.img\Equip\FullBackgrnd.png` (208x291)
- Stat: `UIWindow.img\Stat\backgrnd.png` (175x347)
- Game menu: `UIWindow.img\GameMenu\backgrnd.png` (93x140)
- System options: `UIWindow.img\SysOpt\backgrnd.png` (299x366)
- Memo/chat panel: `UIWindow.img\Memo\backgrnd.png` (295x240)

Key control/icon assets:
- Inventory active slot frame: `UIWindow.img\Item\activeIcon.png` (36x36)
- Inventory disabled slot mask: `UIWindow.img\Item\disabled.png` (32x32)
- Inventory tab strips: `UIWindow.img\Item\Tab\enabled\*.png`, `...\disabled\*.png`
- Inventory controls: `UIWindow.img\Item\BtGather`, `BtSort`, `BtSmall`, `BtFull`, `BtCoin`, `BtCashshop`
- Equip controls: `UIWindow.img\Equip\BtDetail`, `BtPet1/2/3`, `BtPetEquipShow/Hide`, `BtCashshop`
- Stat controls: `UIWindow.img\Stat\BtApUp`, `BtAuto*`, `BtDetail`
- Main menu controls: `UIWindow.img\GameMenu\BtGameOpt`, `BtSysOpt`, `BtChannel`, `BtSkin`, `BtQuit`

Tooltip glyph atlas exists under:
- `UIWindow.img\ToolTip\Equip\...` (requirement/job/category/property text glyphs, stat label art, etc.)

## WZ Method-Parity Rules (Required)
Implement UI behavior using the same interaction methods implied by v83 WZ assets wherever possible:

1. Use v83 control state sets (`normal`, `mouseOver`, `pressed`, `disabled`) for all mapped buttons.
2. Use v83 slot-frame methods:
   - inventory slot frames from `Item\New\inventory\*.png`
   - active slot from `Item\activeIcon.png`
   - unavailable overlay from `Item\disabled.png`
3. Use v83 panel mode methods:
   - compact vs expanded inventory via `Item\backgrnd.png` and `Item\FullBackgrnd.png`
   - equip compact/expanded assets where applicable (`Equip\backgrnd.png`, `Equip\FullBackgrnd.png`)
4. Use v83 tab-strip methods:
   - `Item\Tab\enabled|disabled\*.png` and relevant `New\Tab*` variants for tab visuals/state changes.
5. Use v83 tooltip composition methods:
   - primary tooltip content from runtime data
   - label/glyph enhancement from `UIWindow.img\ToolTip\Equip\...` when available.
6. Prefer v83 UI primitives over custom widgets:
   - scroll/slider/tab controls from `Basic.img`/`UIWindow.img` assets when needed.
7. Do not invent substitute controls if a v83 method exists in extracted assets; only fallback when no source asset/method is present.

## What Is Wrong Right Now
- Inventory and wardrobe still rely on scroll/list semantics.
- Item UX is list rows instead of slot-grid icon interaction.
- Hover tooltip behavior is not using Maple-style tooltip panel flow.
- Window theming is partially Maple but layout composition is still generic.

## Target Behavior (must match)
1. Inventory is slot-grid first (icon boxes), not list first.
2. Hovering a slot shows tooltip near pointer with item details.
3. Tabs switch category panes like Maple tab strips (enabled/disabled assets).
4. Compact/expanded inventory states via `BtSmall` / `BtFull`.
5. Equip pane is paper-doll slot panel first; inventory feed secondary.
6. Drag/drop or click-to-select + equip semantics mapped to slot interactions.
7. Windows are movable non-resizable, pixel-anchored to skin layout.

## Rebuild Strategy
### Phase A: Hard UI shell reset (no behavior changes)
- Remove list-first composition from Inventory/Wardrobe windows.
- Build fixed pixel containers per panel using the exact panel backgrounds.
- Keep existing hotkeys and open/close behavior.

Deliverables:
- `InventoryWindow` and `WardrobeWindow` no longer show ItemList as primary content.
- `603x289` expanded inventory shell rendered correctly.
- Compact inventory shell toggles correctly.

### Phase B: Inventory slot-grid renderer
- Implement `MapleSlotGrid` control:
  - 36x36 slot cell visuals from Item assets.
  - icon centered in slot cell.
  - selected/active frame states.
  - optional disabled/empty states.
- Populate from runtime inventory snapshot.

Deliverables:
- Items visible as icons in slot boxes.
- Selection state visualized in-grid.

### Phase C: Tooltip system
- Implement `MapleItemTooltip` popup:
  - anchored near cursor
  - title, rarity/theme, stat/effect lines, price/meso, source metadata
- Start with text-driven tooltip using runtime item data.
- Optional polish pass: mix in v83 glyph art from `ToolTip\Equip` for labels.

Deliverables:
- Hover any occupied slot -> tooltip appears.
- Tooltip hides on leave and updates with hovered slot.

### Phase D: Equip panel parity
- Convert wardrobe/equip from list interactions to slot interactions:
  - paper-doll slot click targets
  - compatible item filtering by equip slot
  - equip/unequip from slot actions
- Keep assembler render pipeline untouched.

Deliverables:
- Equip slots are explicit clickable boxes.
- Equipping updates both state and visual preview.

### Phase E: Maple controls parity
- Wire buttons to original UX meaning where possible:
  - `BtGather`, `BtSort`, `BtSmall`, `BtFull`, `BtCoin`
  - Equip-specific buttons (`BtDetail`, pet tabs)
- Add fallback behavior only when no equivalent exists.

Deliverables:
- Buttons use correct asset states and expected actions.

## Technical Notes
- Keep all Buddy logic/services unchanged in this pass.
- UI refactor should be isolated to overlay UI layer (`buddy_overlay.gd` + scene nodes/helpers).
- Do not block on tooltip glyph perfection; functional tooltip first.
- Preserve existing item icon resolution pipeline (already fixed for item-specific icons).
- When behavior details are ambiguous, inspect matching `UIWindow.img.xml` sections first and mirror control intent.

## Acceptance Criteria
1. Inventory default view displays icon boxes, not text rows.
2. Hovering slot shows tooltip with matching item name/icon context.
3. Compact/expanded inventory toggle works and preserves selection.
4. Equip panel uses slot boxes and equips by slot interaction.
5. No repeated/stamped text artifacts from background misuse.
6. Manual check can be done without hidden debug knowledge.

## Execution Order
1. Phase A shell reset
2. Phase B slot-grid
3. Phase C tooltip
4. Phase D equip slot interactions
5. Phase E controls parity/polish

## Out Of Scope For This Plan
- Deep tooltip art text rendering fidelity beyond functional parity.
- New economy/progression features.
- Home module UI rework.
