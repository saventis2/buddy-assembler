extends Node2D

const BUDDY_RADIUS := 34.0
const FALLBACK_HIT_RADIUS := 44.0
const IDLE_SWAY_SPEED := 0.9
const IDLE_SWAY_DISTANCE_X := 0.0
const IDLE_SWAY_DISTANCE_Y := 0.0
const FLOOR_PADDING := 14.0
const SPRITE_VIEW_MARGIN := 4.0
const DESKTOP_FLOOR_CONTACT_OFFSET_Y := 10.0
const CHARACTER_FLOOR_OFFSET_PX := 15.0
const ACTION_EXTRA_FLOOR_OFFSET := {
    "sleep": 15.0,
}
const DEFAULT_ROAM_SPEED_PX_PER_SEC := 96.0
const FLOOR_SETTLE_SPEED_PX_PER_SEC := 720.0
const SETTINGS_WINDOW_OFFSET := Vector2i(56, 56)
const SETTINGS_WINDOW_MIN_SIZE := Vector2i(320, 380)
const SETTINGS_WINDOW_DEFAULT_SIZE := Vector2i(360, 460)
const INVENTORY_WINDOW_MIN_SIZE := Vector2i(320, 300)
const INVENTORY_WINDOW_DEFAULT_SIZE := Vector2i(420, 430)
const WARDROBE_WINDOW_MIN_SIZE := Vector2i(360, 320)
const WARDROBE_WINDOW_DEFAULT_SIZE := Vector2i(520, 460)
const CHAT_TRANSCRIPT_MAX_LINES := 120
const CHAT_SEPARATOR_IDLE_SECONDS := 600
const CHAT_RECENT_REPLY_MAX := 20
const CHAT_FOLLOW_UP_MIN_TURNS := 3
const CHAT_MEMORY_MAX_NOTES := 10
# Memory (Plan 13 B2): a failed talk-to-memory request is retried after ten
# minutes, and let go after three failures in a row.
const MEMORY_RETRY_SECONDS := 600
const MAPLE_LAYOUT_TOWN := {
    "base_size": Vector2i(580, 560),
    "min_size": Vector2i(460, 440),
    "offset": Vector2i(72, 40),
    "margins": [12, 10, 12, 10],
}
# Tile colours on the town map, by kind of place.
const TOWN_TILE_COLOURS := {
    "home": Color(0.55, 0.36, 0.22),
    "square": Color(0.40, 0.40, 0.50),
    "cafe": Color(0.60, 0.38, 0.30),
    "shop": Color(0.56, 0.46, 0.20),
    "library": Color(0.36, 0.32, 0.56),
    "park": Color(0.24, 0.48, 0.30),
}
# Half an hour without a word ends a talk: the next line starts a new one
# (fresh context for the model, and a hello when the chat is opened again).
const CHAT_CONVERSATION_GAP_SECONDS := 1800
const MEMORY_MAX_FAILURES := 3
const MAPLE_LAYOUT_MEMORY := {
    "base_size": Vector2i(460, 480),
    "min_size": Vector2i(360, 320),
    "offset": Vector2i(72, 48),
    "margins": [14, 12, 14, 12],
}
const CHAT_FONT_SIZE_M := 13
const CHAT_FONT_SIZE_L := 16
const SETTINGS_CHANGE_HISTORY_MAX := 20
const RESTART_VERIFY_MAX_AGE_SEC := 120
const MAPLE_WINDOW_SKIN_SETTINGS := "UIWindow.img/SysOpt/backgrnd.png"
const MAPLE_WINDOW_SKIN_SETTINGS_MAIN := "UIWindow.img/GameMenu/backgrnd.png"
const MAPLE_WINDOW_SKIN_STATS := "UIWindow.img/Stat/backgrnd.png"
const MAPLE_WINDOW_SKIN_CHAT := "UIWindow.img/Memo/backgrnd.png"
const MAPLE_WINDOW_SKIN_INVENTORY := "UIWindow.img/Item/backgrnd.png"
const MAPLE_WINDOW_SKIN_WARDROBE := "UIWindow.img/Equip/backgrnd.png"
const MAPLE_LAYOUT_SETTINGS := {
    "base_size": Vector2i(500, 660),
    "min_size": Vector2i(460, 560),
    "offset": Vector2i(56, 56),
    "margins": [14, 12, 14, 14],
}
const MAPLE_LAYOUT_SETTINGS_MAIN := {
    "base_size": Vector2i(250, 530),
    "min_size": Vector2i(250, 530),
    "offset": Vector2i(56, 56),
    "margins": [14, 12, 14, 14],
}
const MAPLE_LAYOUT_STATS := {
    "base_size": Vector2i(360, 400),
    "min_size": Vector2i(360, 400),
    "offset": Vector2i(84, 84),
    "margins": [14, 12, 14, 14],
}
const MAPLE_LAYOUT_CHAT := {
    "base_size": Vector2i(460, 340),
    "min_size": Vector2i(380, 280),
    "offset": Vector2i(72, 72),
    "margins": [12, 12, 12, 12],
}
const MAPLE_LAYOUT_INVENTORY := {
    "base_size": Vector2i(603, 289),
    "min_size": Vector2i(603, 289),
    "offset": Vector2i(96, 96),
    "margins": [0, 0, 0, 0],
}
const MAPLE_INVENTORY_CANVAS_SIZE := Vector2i(603, 289)
const MAPLE_LAYOUT_WARDROBE := {
    "base_size": Vector2i(420, 300),
    "min_size": Vector2i(340, 230),
    "offset": Vector2i(112, 112),
    "margins": [12, 12, 12, 10],
    "max_screen_fraction": [0.34, 0.62],
}
const MAPLE_LAYOUT_REBUILD_MENU := {
    "base_size": Vector2i(660, 490),
    "min_size": Vector2i(660, 490),
    "offset": Vector2i(96, 96),
    "margins": [12, 10, 12, 12],
}
const INVENTORY_SLOT_PX := 40
const INVENTORY_COMPACT_SIZE := Vector2i(400, 490)
const PAPER_DOLL_SLOTS := [
    {"id": "hat", "label": "Hat", "pos": Vector2(0, 0)},
    {"id": "face_accessory", "label": "Face", "pos": Vector2(0, 44)},
    {"id": "eye_accessory", "label": "Eyes", "pos": Vector2(0, 88)},
    {"id": "earrings", "label": "Ears", "pos": Vector2(0, 132)},
    {"id": "cape", "label": "Cape", "pos": Vector2(196, 0)},
    {"id": "top", "label": "Top", "pos": Vector2(196, 44)},
    {"id": "bottom", "label": "Legs", "pos": Vector2(196, 88)},
    {"id": "gloves", "label": "Hands", "pos": Vector2(196, 132)},
    {"id": "weapon", "label": "Weapon", "pos": Vector2(0, 176)},
    {"id": "shield", "label": "Shield", "pos": Vector2(49, 176)},
    {"id": "overall", "label": "Outfit", "pos": Vector2(98, 176)},
    {"id": "shoes", "label": "Shoes", "pos": Vector2(147, 176)},
    {"id": "pendant1", "label": "Neck", "pos": Vector2(196, 176)},
]
const INVENTORY_SLOT_COLUMNS := 8
const INVENTORY_MIN_SLOTS := 48
const RARITY_COLORS := {
    "common": "#F4E9CF",
    "uncommon": "#8FE39B",
    "rare": "#7FC4FF",
    "epic": "#D7A1FF",
    "legendary": "#FFB45E",
}
const PACK_SCALE_PRESETS := [2.35, 2.0, 1.72]
const DEFAULT_SPRITE_ANCHOR := Vector2(0.5, 1.0)
const NO_PIVOT := Vector2(-1.0, -1.0)
const SLEEP_PIVOT_OVERFLOW_BLEND := 1.0
const SIT_PIVOT_OVERFLOW_BLEND := 1.0
const DEFAULT_EMOTE_MANIFEST_PATH := "character/emotes/manifest.json"
const SIT_CHAIR_FRAME_PATH := "effects/chair_basic/frames/000.png"
const SIT_CHAIR_EFFECT_PATH := "effects/chair_basic/effect.json"
const ASSEMBLER_SCRIPT_REL_PATH := "res://../../tools/importers/render_character_frame.py"
const ASSEMBLER_STATE_ACTION_MAP := {
    "idle": "stand1",
    "wander": "walk1",
    "happy": "alert",
    "gift": "alert",
    # The buddy walks across the screen in this state, so it needs the walk
    # cycle, not a standing pose.
    "visitor": "walk1",
    "sit": "sit",
    "sleep": "prone",
}
# Frames per source action and how long each is held, as in the source data.
const ASSEMBLER_ACTION_FRAME_COUNT := {"stand1": 3, "walk1": 4, "alert": 3, "sit": 1, "prone": 1}
const ASSEMBLER_ACTION_FRAME_SECONDS := {"stand1": 0.5, "walk1": 0.18, "alert": 0.5}
# These play forwards then backwards (0 1 2 1 0 ...) rather than looping.
const ASSEMBLER_PING_PONG_ACTIONS := ["stand1", "alert"]
# Floor height below the navel anchor; matches floor_world_ref in the pack's
# exported animations so assembled and pack frames stand on the same line.
const ASSEMBLER_FLOOR_WORLD_REF := 35.0
# The character art is drawn facing left. _facing_sign is +1 when the buddy
# should face right, so the sprite is mirrored whenever the two differ.
const SPRITE_ART_FACING := -1
const WZ_ICON_ROOT_CANDIDATES := [
    "C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz",
    "C:/Users/%s/OneDrive/Desktop/83 complete/Base.wz",
]
const ITEM_ICON_BY_ID := {
    "cozy-lamp": "effects/chair_basic/frames/000.png",
    "plush-heart": "effects/happy_sparkle/frames/000.png",
    "warm-tea": "effects/gift_box/frames/000.png",
    "hero-ribbon": "effects/levelup/frames/000.png",
    "focus-badge": "effects/levelup/frames/001.png",
    "victory-banner": "effects/visitor_arrival/frames/000.png",
    "wz-rocky-mask-doll": "effects/chair_basic/frames/000.png",
    "wz-ridleys-stone": "effects/levelup/frames/000.png",
    "wz-green-halloween-stick-candy": "effects/gift_box/frames/000.png",
    "wz-tri-colored-dango": "effects/gift_box/frames/000.png",
    "wz-fruity-candy": "effects/happy_sparkle/frames/000.png",
    "wz-stone-golem-rubble": "effects/levelup/frames/000.png",
}
const ITEM_ICON_BY_CATEGORY := {
    "food": "effects/gift_box/frames/000.png",
    "gifts": "effects/gift_box/frames/000.png",
    "gear": "effects/happy_sparkle/frames/000.png",
    "training_items": "effects/gift_box/frames/000.png",
    "evolution_items": "effects/levelup/frames/000.png",
    "materials": "effects/levelup/frames/000.png",
    "decor": "effects/chair_basic/frames/000.png",
}
const EQUIP_SLOT_DRAW_OFFSET := {
    "gear": Vector2(-8.0, -66.0),
    "charm": Vector2(20.0, -46.0),
    "relic": Vector2(-28.0, -42.0),
    "weapon": Vector2(28.0, -48.0),
    "shield": Vector2(-24.0, -48.0),
    "hat": Vector2(0.0, -84.0),
    "face_accessory": Vector2(0.0, -68.0),
    "eye_accessory": Vector2(0.0, -70.0),
    "earrings": Vector2(10.0, -66.0),
    "overall": Vector2(0.0, -56.0),
    "top": Vector2(0.0, -56.0),
    "bottom": Vector2(0.0, -40.0),
    "shoes": Vector2(0.0, -18.0),
    "gloves": Vector2(18.0, -56.0),
    "cape": Vector2(-18.0, -54.0),
    "belt": Vector2(0.0, -44.0),
    "medal": Vector2(-10.0, -58.0),
    "badge": Vector2(12.0, -56.0),
    "emblem": Vector2(14.0, -58.0),
    "shoulder": Vector2(-14.0, -64.0),
    "pocket": Vector2(-10.0, -50.0),
    "pendant1": Vector2(0.0, -62.0),
    "pendant2": Vector2(6.0, -62.0),
    "ring1": Vector2(20.0, -40.0),
    "ring2": Vector2(16.0, -40.0),
    "ring3": Vector2(12.0, -40.0),
    "ring4": Vector2(8.0, -40.0),
}
const EQUIP_SLOT_DRAW_SCALE := {
    "weapon": 0.62,
    "shield": 0.56,
    "cape": 0.72,
    "hat": 0.64,
    "face_accessory": 0.36,
    "eye_accessory": 0.34,
    "earrings": 0.32,
    "overall": 0.56,
    "top": 0.54,
    "bottom": 0.52,
    "shoes": 0.48,
    "gloves": 0.44,
    "belt": 0.42,
    "medal": 0.34,
    "badge": 0.34,
    "emblem": 0.34,
    "shoulder": 0.38,
    "pocket": 0.30,
    "pendant1": 0.34,
    "pendant2": 0.34,
    "ring1": 0.26,
    "ring2": 0.26,
    "ring3": 0.26,
    "ring4": 0.26,
    "gear": 0.45,
    "charm": 0.42,
    "relic": 0.42,
}
const EQUIP_SLOT_DRAW_LAYER := {
    "cape": "back",
    "shield": "back",
}
const PAPER_DOLL_GROUPS := {
    "combat": ["weapon", "shield", "overall", "top", "bottom", "shoes", "gloves", "cape"],
    "style": ["hat", "face_accessory", "eye_accessory", "earrings", "belt", "shoulder", "pocket"],
    "accessory": ["pendant1", "pendant2", "ring1", "ring2", "ring3", "ring4", "medal", "badge", "emblem"],
}
const SLOT_DISPLAY_NAMES := {
    "weapon": "Weapon",
    "shield": "Shield",
    "overall": "Overall",
    "top": "Top",
    "bottom": "Bottom",
    "shoes": "Shoes",
    "gloves": "Gloves",
    "cape": "Cape",
    "hat": "Hat",
    "face_accessory": "Face",
    "eye_accessory": "Eye",
    "earrings": "Earrings",
    "belt": "Belt",
    "shoulder": "Shoulder",
    "pocket": "Pocket",
    "pendant1": "Pendant1",
    "pendant2": "Pendant2",
    "ring1": "Ring1",
    "ring2": "Ring2",
    "ring3": "Ring3",
    "ring4": "Ring4",
    "medal": "Medal",
    "badge": "Badge",
    "emblem": "Emblem",
}
const INVENTORY_SORT_MODES := ["newest", "rarity", "name", "category", "equipped"]
const INVENTORY_RARITY_RANK := {
    "common": 1,
    "uncommon": 2,
    "rare": 3,
    "epic": 4,
    "legendary": 5,
    "mythic": 6,
}
const DEFAULT_STATE_EMOTES := {
    "idle": "default",
    "wander": "default",
    "sit": "default",
    "sleep": "blink",
    "happy": "smile",
    "gift": "love",
    "visitor": "wink",
}
const DEBUG_EMOTE_KEYS := {
    KEY_1: "happy",
    KEY_2: "sad",
    KEY_3: "angry",
    KEY_4: "surprised",
    KEY_5: "love",
    KEY_6: "wink",
    KEY_7: "sleepy",
    KEY_8: "sick",
    KEY_9: "pain",
    KEY_0: "default",
}
const EMOTE_DRAW_OFFSETS := {
    "love": Vector2(0.0, -4.0),
}

const BehaviorEngine = preload("res://scripts/behavior/behavior_engine.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const EncounterScheduler = preload("res://scripts/encounters/encounter_scheduler.gd")
const ChatCommandRouter = preload("res://scripts/interaction/chat_command_router.gd")
const UnlockTable = preload("res://scripts/progression/unlock_table.gd")
const ProductivityTracker = preload("res://scripts/utility/productivity_tracker.gd")
const PromptCadence = preload("res://scripts/utility/prompt_cadence.gd")
const ManualVerificationReport = preload("res://scripts/utility/manual_verification_report.gd")
const PortableBuddyFallback = preload("res://scripts/visual/portable_buddy_fallback.gd")
const MindThinker = preload("res://scripts/services/mind_thinker.gd")
const MapleTheme = preload("res://scripts/ui/maple_theme.gd")
const VisitController = preload("res://scripts/visit_controller.gd")
const PORTABLE_FALLBACK_TEXTURE := preload("res://content/core_pack/character/idle.png")

@onready var tick_timer: Timer = $TickTimer
@onready var telemetry_timer: Timer = $TelemetryTimer
@onready var telemetry_label: Label = $Telemetry/Label
@onready var settings_window: Window = $SettingsWindow
@onready var settings_label: RichTextLabel = $SettingsWindow/MarginContainer/SettingsVBox/SettingsLabel
@onready var settings_btn_pause: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnPause
@onready var settings_btn_event_freq: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnEventFreq
@onready var settings_btn_prompt_freq: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnPromptFreq
@onready var settings_btn_quiet: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnQuietStrict
@onready var settings_btn_dnd_15: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDnd15
@onready var settings_btn_dnd_30: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDnd30
@onready var settings_btn_dnd_off: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDndOff
@onready var settings_btn_intensity: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnIntensity
@onready var settings_btn_mode: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnMode
@onready var settings_btn_pack: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnPack
@onready var settings_btn_demo_support: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDemoSupport
@onready var settings_btn_demo_world: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDemoWorld
@onready var settings_btn_reward: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnReward
@onready var settings_btn_seed_inventory: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnSeedInventory
@onready var settings_btn_repair_inventory: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnRepairInventory
@onready var settings_btn_clear_inventory: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnClearInventory
@onready var settings_btn_telemetry: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnTelemetry
@onready var settings_btn_restart: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnRestart
@onready var settings_btn_quit: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnQuit
@onready var settings_btn_chat: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnChat
@onready var settings_btn_stats: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnStats
@onready var settings_btn_inventory: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnInventory
@onready var settings_btn_wardrobe: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnWardrobe
@onready var settings_floor_slider: HSlider = $SettingsWindow/MarginContainer/SettingsVBox/FloorAdjustBox/FloorAdjustRow/FloorAdjustSlider
@onready var settings_floor_value: Label = $SettingsWindow/MarginContainer/SettingsVBox/FloorAdjustBox/FloorAdjustRow/FloorAdjustValue
@onready var settings_margin_container: MarginContainer = $SettingsWindow/MarginContainer
@onready var settings_vbox: VBoxContainer = $SettingsWindow/MarginContainer/SettingsVBox
@onready var stats_window: Window = $StatsWindow
@onready var stats_label: RichTextLabel = $StatsWindow/MarginContainer/StatsVBox/StatsLabel
@onready var stats_btn_strength: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnStrength
@onready var stats_btn_dexterity: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnDexterity
@onready var stats_btn_charisma: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnCharisma
@onready var stats_btn_endurance: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnEndurance
@onready var stats_btn_wisdom: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnWisdom
@onready var stats_btn_knowledge: Button = $StatsWindow/MarginContainer/StatsVBox/StatsGrid/BtnKnowledge
@onready var stats_btn_close: Button = $StatsWindow/MarginContainer/StatsVBox/StatsActions/BtnStatsClose
@onready var inventory_window: Window = $InventoryWindow
@onready var inventory_header: RichTextLabel = $InventoryWindow/MarginContainer/InventoryVBox/InventoryHeader
@onready var inventory_tab_all: Button = $InventoryWindow/MarginContainer/InventoryVBox/TabRow/BtnInvTabAll
@onready var inventory_tab_equip: Button = $InventoryWindow/MarginContainer/InventoryVBox/TabRow/BtnInvTabEquip
@onready var inventory_tab_use: Button = $InventoryWindow/MarginContainer/InventoryVBox/TabRow/BtnInvTabUse
@onready var inventory_tab_etc: Button = $InventoryWindow/MarginContainer/InventoryVBox/TabRow/BtnInvTabEtc
@onready var inventory_tab_decor: Button = $InventoryWindow/MarginContainer/InventoryVBox/TabRow/BtnInvTabDecor
@onready var inventory_category_filter: OptionButton = $InventoryWindow/MarginContainer/InventoryVBox/FilterRow/CategoryFilter
@onready var inventory_list: ItemList = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/InventoryList
@onready var inventory_detail_scroll: ScrollContainer = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll
@onready var paper_slot_gear_label: Label = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotGearRow/PaperSlotGearLabel
@onready var paper_slot_charm_label: Label = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotCharmRow/PaperSlotCharmLabel
@onready var paper_slot_relic_label: Label = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotRelicRow/PaperSlotRelicLabel
@onready var paper_doll_title_label: Label = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperDollTitle
@onready var paper_btn_unequip_gear: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotGearRow/BtnPaperUnequipGear
@onready var paper_btn_unequip_charm: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotCharmRow/BtnPaperUnequipCharm
@onready var paper_btn_unequip_relic: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/PaperDollPanel/PaperSlotRelicRow/BtnPaperUnequipRelic
@onready var inventory_detail: RichTextLabel = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryDetail
@onready var inventory_btn_use: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryActions/BtnInventoryUse
@onready var inventory_btn_equip: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryActions/BtnInventoryEquip
@onready var inventory_btn_unequip: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryActions/BtnInventoryUnequip
@onready var inventory_btn_close: Button = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryActions/BtnInventoryClose
@onready var inventory_icon_preview: TextureRect = $InventoryWindow/MarginContainer/InventoryVBox/BodySplit/DetailVBox/DetailScroll/DetailContent/InventoryIconRow/InventoryIconPreview
@onready var wardrobe_window: Window = $WardrobeWindow
@onready var wardrobe_header: RichTextLabel = $WardrobeWindow/MarginContainer/WardrobeVBox/WardrobeHeader
@onready var wardrobe_list: ItemList = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeList
@onready var wardrobe_preview: RichTextLabel = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/WardrobePreview
@onready var wardrobe_btn_toggle: Button = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/WardrobeActions/BtnWardrobeDraftToggle
@onready var wardrobe_btn_clear_slot: Button = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/WardrobeActions/BtnWardrobeClearDraft
@onready var wardrobe_btn_equip_draft: Button = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/WardrobeActions/BtnWardrobeEquipDraft
@onready var wardrobe_btn_revert: Button = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/WardrobeActions/BtnWardrobeRevert
@onready var wardrobe_btn_close: Button = $WardrobeWindow/MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox/BtnWardrobeClose
@onready var chat_window: Window = $ChatWindow
@onready var chat_log: RichTextLabel = $ChatWindow/MarginContainer/ChatVBox/ChatLog
@onready var chat_input: LineEdit = $ChatWindow/MarginContainer/ChatVBox/ChatInputRow/ChatInput
@onready var chat_send: Button = $ChatWindow/MarginContainer/ChatVBox/ChatInputRow/ChatSend
@onready var chat_balloon: Node2D = $ChatBalloon
@onready var welcome_label: Label = $WelcomeLayer/WelcomeLabel

var _engine := BehaviorEngine.new()
var _encounters := EncounterScheduler.new()
var _chat_router := ChatCommandRouter.new()
var _productivity := ProductivityTracker.new()
var _prompt_cadence := PromptCadence.new()
var _manual_verification_report := ManualVerificationReport.new()
var _state := "idle"
var _is_paused := false
var _mind_http: HTTPRequest = null
var _mind_pending := {}
var _chat_http: HTTPRequest = null
var _chat_pending := {}          # {"kind": "chat" | "name" | "memory"}
var _chat_turns: Array = []      # {"who": "you" | "them", "text": String}
var _chat_last_turn_unix := 0
var _mind_model_status := "not tried yet"
var _dragging := false
var _drag_offset := Vector2i.ZERO
var _bob_time := 0.0
var _allowed_actions := []
var _active_manifest := {}
var _active_pack_id := "core_pack"
var _last_event_id := ""
var _draw_center := Vector2.ZERO
var _floor_padding := FLOOR_PADDING
var _telemetry_enabled := false
var _action_animations: Dictionary = {}
var _action_textures: Dictionary = {}
var _current_texture: Texture2D = null
var _sprite_scale: float = 2.35
var _sprite_anchor := DEFAULT_SPRITE_ANCHOR
var _current_frame_anchor := DEFAULT_SPRITE_ANCHOR
var _ground_enabled := false
var _ground_texture: Texture2D = null
var _ground_tile_x := true
var _ground_scale := 1.0
var _ground_alpha := 1.0
var _ground_align := "top"
var _ground_floor_offset_y := 0.0
var _ground_x_offset := 0.0
var _ground_source_path := ""
var _current_sprite_path := ""
var _current_visual_action := ""
var _current_animation_frames: Array = []
var _current_animation_durations: Array = []
var _current_animation_anchors: Array = []
var _current_animation_pivots: Array = []
var _current_animation_loop := true
var _current_animation_index := 0
var _current_animation_elapsed := 0.0
var _current_frame_pivot_px := NO_PIVOT
var _max_loaded_pivot_px_y := 0.0
var _current_sprite_rect := Rect2()
var _ground_surface_y_px := 0.0
var _state_emote_map: Dictionary = {}
var _face_emote_manifest: Dictionary = {}
var _face_overlay_frames: Array = []
var _face_texture_cache: Dictionary = {}
var _active_emote_semantic := "default"
var _active_face_variant := "default"
var _settings_menu_open := false
var _settings_menu_advanced := false
var _stats_menu_open := false
var _inventory_menu_open := false
var _wardrobe_menu_open := false
var _chat_window_open := false
var _manual_emote_until_unix := 0
var _last_face_texture_path := ""
var _roam_speed_px_per_sec := DEFAULT_ROAM_SPEED_PX_PER_SEC
var _roam_direction := 1
var _roam_subpixel_x := 0.0
var _floor_settle_active := false
var _bond_phrase_active := false
var _last_idle_phrase_unix := 0
var _away_report_shown := false
var _continuity_hint_shown := false
var _last_auto_prompt_unix := 0
var _last_auto_prompt_by_source := {}
var _deferred_world_prompt := {}
var _desktop_floor_offset_adjust := 0.0
var _settings_main_menu_box: VBoxContainer = null
var _main_menu_status: Label = null
var _main_menu_btn_pause: Button = null
var _main_menu_btn_chat: Button = null
var _main_menu_btn_stats: Button = null
var _main_menu_btn_inventory: Button = null
var _main_menu_btn_wardrobe: Button = null
var _main_menu_btn_call: Button = null
var _main_menu_health: Label = null
var _settings_btn_world_host: Button = null
# The world host (Plan 14 step 2a). Only in role "desktop": this app is then the
# buddy visiting, and while it is at home the overlay shows a panel instead.
var _visit: Node = null
var _visit_health := ""
var _visit_answer := {}
var _away_panel_rect := Rect2()
var _away_button_rect := Rect2()
var _settings_btn_autonomy: Button = null
var _settings_btn_model: Button = null
var _settings_btn_chat_model: Button = null
var _settings_btn_memory: Button = null
var _settings_debug_box: Control = null
var _settings_btn_debug_toggle: Button = null
var _inventory_maple_canvas: Control = null
var _inventory_slot_scroll: ScrollContainer = null
var _inventory_slot_grid: GridContainer = null
var _inventory_slot_buttons_by_instance := {}
var _sit_chair_texture: Texture2D = null
var _sit_chair_origin_px := Vector2.ZERO
var _chat_turn_user_count := 0
var _chat_turn_buddy_count := 0
var _chat_cmd_ok_count := 0
var _chat_cmd_fail_count := 0
var _chat_cmd_reason_counts := {}
var _chat_cmd_last_key_by_action := {}
var _chat_last_command_id := ""
var _chat_last_reason_code := ""
var _chat_last_line_unix := 0
var _chat_recent_buddy_norm_lines: Array = []
var _chat_last_followup_turn := -100
var _chat_memory_pending_forget_id := -1
var _chat_memory_pending_forget_until := 0
var _memory_next_attempt_unix := 0
var _memory_failures := 0
var _memory_window: Window = null
var _memory_rows: VBoxContainer = null
var _memory_intro: Label = null
var _memory_btn_toggle: Button = null
var _memory_btn_forget_all: Button = null
var _memory_forget_all_armed_until := 0
var _town_window: Window = null
var _town_map: Control = null
var _town_heading: Label = null
var _town_info: Label = null
var _town_selected := ""
var _town_tiles: Dictionary = {}
var _chat_unread_prompt_count := 0
var _chat_cmd_latency_last_ms := 0
var _chat_cmd_latency_total_ms := 0
var _chat_cmd_latency_samples := 0
var _chat_cmd_latency_recent_ms: Array = []
var _dnd_until_unix := 0
var _settings_undo_snapshot := {}
var _settings_undo_until_unix := 0
var _settings_change_history: Array = []
var _inventory_rows_cache: Array = []
var _inventory_visible_instance_ids: Array = []
var _inventory_selected_instance_id := -1
var _wardrobe_rows_cache: Array = []
var _wardrobe_visible_instance_ids: Array = []
var _wardrobe_slot_scroll: ScrollContainer = null
var _wardrobe_slot_grid: GridContainer = null
var _wardrobe_slot_buttons_by_instance := {}
var _wardrobe_selected_instance_id := -1
var _inventory_active_tab := "all"
var _inventory_sort_mode := "newest"
var _equipped_visual_items := {}
var _wardrobe_draft_slots := {}
var _assembled_state_texture_overrides := {}
var _assembler_default_parts := {}
var _assembler_last_error := ""
var _assembler_cache_manifest := {}
var _assembler_active_key := ""
var _assembler_pending_key := ""
var _assembler_pending_part_ids := {}
var _assembler_pending_reason := ""
var _assembler_thread: Thread = null
var _assembler_thread_result: Dictionary = {}
var _assembler_last_status_unix := 0
var _facing_sign := SPRITE_ART_FACING
var _equipped_visual_signature := ""
var _inventory_icon_cache := {}
var _generated_item_icon_cache := {}
var _inventory_icon_last_source := ""
var _inventory_icon_last_cache_hit := false
var _pack_scale_override := -1.0
var _wz_icon_root := ""
var _stats_session_baseline := {}
var _menu_rebuild_enabled := true
var _menu_rebuild_open := false
var _menu_rebuild_mode := "inventory"
var _menu_rebuild_window: Window = null
var _menu_rebuild_header: RichTextLabel = null
var _menu_rebuild_slot_grid: GridContainer = null
var _menu_rebuild_detail: RichTextLabel = null
var _menu_rebuild_icon: TextureRect = null
var _menu_rebuild_btn_use: Button = null
var _menu_rebuild_btn_equip: Button = null
var _menu_rebuild_btn_unequip: Button = null
var _menu_rebuild_btn_close: Button = null
var _menu_rebuild_tabs := {}
var _menu_rebuild_empty_label: Label = null
var _menu_rebuild_slot_buttons_by_instance := {}
var _menu_rebuild_selected_instance_id := -1
var _menu_rebuild_doll: Control = null
var _menu_rebuild_doll_preview: TextureRect = null
var _menu_rebuild_doll_slots := {}      # slot id -> Button
var _menu_rebuild_slot_filter := ""     # slot id the item grid is filtered to, or ""
var _menu_rebuild_detail_panel: Control = null
var _menu_rebuild_btn_compact: Button = null


func _ready() -> void:
    position = Vector2.ZERO
    _desktop_floor_offset_adjust = _read_floor_offset_adjust_setting()
    _ensure_wz_icon_root_setting()
    _draw_center = _floor_point()
    _configure_window()
    _restore_window_state()
    _load_content_pack()

    _engine.configure(int(AppState.profile.get("personality_seed", 0)))
    _encounters.configure(
        _active_manifest.get("eventRules", []),
        int(AppState.profile.get("personality_seed", 0))
    )

    tick_timer.timeout.connect(_on_tick_timer_timeout)
    telemetry_timer.timeout.connect(_on_telemetry_timer_timeout)
    set_process(true)
    set_process_input(true)
    _productivity.note_session_reset(int(Time.get_unix_time_from_system()))
    telemetry_label.visible = false
    _configure_settings_window()
    _configure_stats_window()
    _configure_inventory_window()
    _configure_wardrobe_window()
    _configure_menu_rebuild_window()
    _configure_chat_window()
    _chat_turns = AppState.memory_live_turns()
    _chat_last_turn_unix = int(Time.get_unix_time_from_system())
    _capture_stats_session_baseline()
    _refresh_equipped_visual_state()
    _load_assembler_default_parts()
    _refresh_assembled_state_overrides("startup")
    _refresh_telemetry()
    if AppState.is_first_run():
        _show_welcome_once()
    else:
        _show_while_away_report_once()
    _show_restart_verification_once()
    _start_visit_controller()


func _exit_tree() -> void:
    _drain_assembler_thread()


func _configure_window() -> void:
    # Force subwindows (like F10 settings) to become real OS windows,
    # not embedded UI panels inside the transparent overlay viewport.
    get_viewport().gui_embed_subwindows = false
    get_viewport().transparent_bg = true
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    DisplayServer.window_set_title("Buddy Runtime")
    _update_mouse_region()


func _update_mouse_region() -> void:
    # Avoid shaped passthrough regions; some Windows setups render them as a visible bubble.
    DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


func _toggle_sleep_state() -> void:
    if _is_away():
        return
    # Shared by the right-click-on-sprite gesture and the settings popout's
    # Pause/Resume button so both entry points stay in sync.
    _state = "sleep" if _state != "sleep" else "idle"
    # _is_paused tracks an explicit user-initiated pause, independent of
    # `_state == "sleep"` (which can also be reached via natural/forced
    # home-mode behavior). While paused, _on_tick_timer_timeout() must not
    # let a forced_action (productivity nudge, home-mode action, encounter)
    # silently un-pause the buddy; only this toggle may clear it.
    _is_paused = _state == "sleep"
    _set_emote_from_state(_state)
    _set_visual_for_state(_state)
    AppState.record_interaction("toggle_sleep")
    _note_visit_interaction()
    _productivity.note_user_activity(int(Time.get_unix_time_from_system()))
    queue_redraw()


func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.pressed and not key_event.echo:
            if key_event.keycode == KEY_F6:
                _telemetry_enabled = not _telemetry_enabled
                _refresh_telemetry()
            elif key_event.keycode == KEY_F1:
                _export_manual_verification_snapshot()
            elif key_event.keycode == KEY_F2:
                if key_event.shift_pressed:
                    _show_auto_prompt("Demo support prompt (Shift+F2).", "support")
                else:
                    _cycle_prompt_frequency()
            elif key_event.keycode == KEY_F5:
                _cycle_home_mode()
            elif key_event.keycode == KEY_F7:
                if key_event.shift_pressed:
                    _show_world_prompt(
                        {
                            "type": "encounter",
                            "npcName": "Demo",
                            "text": "Demo world prompt for cadence check.",
                        }
                    )
                else:
                    _cycle_event_frequency()
            elif key_event.keycode == KEY_F4:
                _cycle_interaction_intensity()
            elif key_event.keycode == KEY_F3:
                _cycle_quiet_strictness()
            elif key_event.keycode == KEY_F8:
                _move_to_next_monitor()
            elif key_event.keycode == KEY_F9:
                _cycle_pack()
            elif key_event.keycode == KEY_F10:
                if key_event.shift_pressed:
                    _toggle_stats_menu()
                else:
                    _toggle_settings_menu()
            elif key_event.keycode == KEY_F11:
                _open_debug_reward_box()
            elif key_event.keycode == KEY_F12:
                _resolve_world_prompt(not key_event.shift_pressed)
            elif key_event.keycode == KEY_I:
                _toggle_inventory_menu()
            elif key_event.keycode == KEY_W:
                _toggle_wardrobe_menu()
            elif DEBUG_EMOTE_KEYS.has(key_event.keycode):
                var semantic := str(DEBUG_EMOTE_KEYS[key_event.keycode])
                _set_emote_from_semantic(semantic, true, 12.0)
                _refresh_telemetry()
            elif _inventory_menu_open:
                if key_event.keycode == KEY_TAB:
                    _cycle_inventory_sort_mode()
                elif key_event.keycode == KEY_E:
                    _activate_selected_inventory_item()
                elif key_event.keycode == KEY_U:
                    _use_selected_inventory_item()
                elif key_event.keycode == KEY_Q:
                    _unequip_selected_inventory_item()

    if event is InputEventMouseButton and _is_away():
        # At home: only the panel answers to the mouse (nothing here may pet or move it).
        var away_event := event as InputEventMouseButton
        if away_event.button_index == MOUSE_BUTTON_LEFT and away_event.pressed:
            if _away_button_rect.has_point(away_event.position):
                _visit.call_over()
                _note_visit_interaction()
            elif away_event.double_click and _hit_test(away_event.position) and not _settings_menu_open:
                _toggle_settings_menu()
        return

    if event is InputEventMouseButton:
        var button_event := event as InputEventMouseButton
        if button_event.button_index == MOUSE_BUTTON_LEFT:
            if button_event.pressed and button_event.double_click and _hit_test(button_event.position):
                # The menu holds chat, stats, inventory, wardrobe and pause;
                # without this the only way in is the F10 hotkey.
                _dragging = false
                if not _settings_menu_open:
                    _toggle_settings_menu()
            elif button_event.pressed and _hit_test(button_event.position):
                var before := AppState.get_telemetry_snapshot()
                _dragging = true
                _drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
                _state = "happy"
                _set_emote_from_state(_state)
                _set_visual_for_state(_state)
                AppState.record_interaction("pet")
                _note_visit_interaction()
                var after := AppState.get_telemetry_snapshot()
                _show_progress_feedback(before, after)
                _productivity.note_user_activity(int(Time.get_unix_time_from_system()))
                queue_redraw()
            elif not button_event.pressed:
                _dragging = false
                AppState.set_window_state(
                    DisplayServer.window_get_current_screen(),
                    DisplayServer.window_get_position()
                )
                _floor_settle_active = true
                _return_to_idle_after_drag()
        elif button_event.button_index == MOUSE_BUTTON_RIGHT and button_event.pressed:
            if _hit_test(button_event.position):
                _toggle_sleep_state()

    if event is InputEventMouseMotion and _dragging:
        var mouse_pos := DisplayServer.mouse_get_position()
        var next_pos := mouse_pos - _drag_offset
        var screen_index := _screen_for_point(mouse_pos)
        if screen_index < 0:
            screen_index = DisplayServer.window_get_current_screen()
        next_pos = _clamp_window_to_screen(next_pos, screen_index)
        DisplayServer.window_set_current_screen(screen_index)
        DisplayServer.window_set_position(next_pos)


func _process(delta: float) -> void:
    _poll_assembler_thread()
    _bob_time += delta
    _update_window_roam(delta)
    var base_center := _floor_point()
    if not _dragging and _state != "sleep":
        _draw_center = base_center + Vector2(
            sin(_bob_time * IDLE_SWAY_SPEED) * IDLE_SWAY_DISTANCE_X,
            sin(_bob_time * IDLE_SWAY_SPEED) * IDLE_SWAY_DISTANCE_Y
        )
    elif _state == "sleep":
        _draw_center = base_center
    else:
        _draw_center = base_center
    _advance_animation(delta)
    queue_redraw()


func _configure_settings_window() -> void:
    if settings_window == null:
        return
    settings_window.transient = false
    settings_window.exclusive = false
    settings_window.borderless = false
    settings_window.visible = false
    settings_window.unresizable = true
    var settings_layout_init := _layout_with_skin_size(MAPLE_LAYOUT_SETTINGS_MAIN, MAPLE_WINDOW_SKIN_SETTINGS_MAIN)
    settings_window.min_size = settings_layout_init["min_size"]
    settings_window.size = settings_layout_init["base_size"]
    settings_window.title = "Buddy Menu"
    settings_window.wrap_controls = true
    settings_window.always_on_top = true
    settings_window.close_requested.connect(func() -> void:
        settings_window.hide()
        _settings_menu_open = false
        _set_settings_menu_mode(false)
    )
    settings_btn_pause.pressed.connect(func() -> void:
        _toggle_sleep_state()
        _refresh_telemetry()
    )
    settings_btn_pause.tooltip_text = "Pauses your buddy in place (same as right-click). Click again to resume."
    settings_btn_event_freq.pressed.connect(func() -> void:
        _cycle_event_frequency()
    )
    settings_btn_event_freq.tooltip_text = "Controls world-event cadence. Low is calmer; high is busier."
    settings_btn_prompt_freq.pressed.connect(func() -> void:
        _cycle_prompt_frequency()
    )
    settings_btn_prompt_freq.tooltip_text = "Controls support-prompt cadence. Low reduces interruptions."
    settings_btn_quiet.pressed.connect(func() -> void:
        _cycle_quiet_strictness()
    )
    settings_btn_quiet.tooltip_text = "Strict suppresses almost all non-critical prompts."
    settings_btn_dnd_15.pressed.connect(func() -> void:
        _set_dnd_minutes(15)
        _buddy_say("DND enabled for 15 minutes.")
    )
    settings_btn_dnd_15.tooltip_text = "Suppress support/world auto-prompts for 15 minutes."
    settings_btn_dnd_30.pressed.connect(func() -> void:
        _set_dnd_minutes(30)
        _buddy_say("DND enabled for 30 minutes.")
    )
    settings_btn_dnd_30.tooltip_text = "Suppress support/world auto-prompts for 30 minutes."
    settings_btn_dnd_off.pressed.connect(func() -> void:
        _set_dnd_off()
        _buddy_say("DND disabled.")
    )
    settings_btn_dnd_off.tooltip_text = "Re-enable support/world auto-prompts immediately."
    settings_btn_intensity.pressed.connect(func() -> void:
        _cycle_interaction_intensity()
    )
    settings_btn_intensity.tooltip_text = "Cozy/Deep tune activity; Idle runs autopilot and auto-assigns stats."
    settings_btn_mode.pressed.connect(func() -> void:
        _cycle_home_mode()
    )
    settings_btn_mode.tooltip_text = "Switch between Home behavior and Overlay behavior."
    settings_btn_pack.pressed.connect(func() -> void:
        _cycle_pack()
    )
    settings_btn_pack.tooltip_text = "Cycles active content pack for visuals/content mappings."
    settings_btn_demo_support.pressed.connect(func() -> void:
        _show_auto_prompt("Demo support prompt (menu).", "support")
    )
    settings_btn_demo_support.tooltip_text = "Manual support prompt trigger for cadence verification."
    settings_btn_demo_world.pressed.connect(func() -> void:
        _show_world_prompt(
            {
                "type": "encounter",
                "npcName": "Demo",
                "text": "Demo world prompt from menu.",
            }
        )
    )
    settings_btn_demo_world.tooltip_text = "Manual world prompt trigger for cadence verification."
    settings_btn_reward.pressed.connect(func() -> void:
        _open_debug_reward_box()
    )
    settings_btn_reward.tooltip_text = "Opens a debug reward box using current economy state."
    settings_btn_seed_inventory.pressed.connect(func() -> void:
        _seed_test_inventory_ui()
    )
    settings_btn_seed_inventory.tooltip_text = "Adds one sample item per core category for UI/icon verification."
    settings_btn_repair_inventory.pressed.connect(func() -> void:
        _repair_inventory_ui()
    )
    settings_btn_repair_inventory.tooltip_text = "Repairs inventory rows from catalog and keeps unresolved rows quarantined."
    settings_btn_clear_inventory.pressed.connect(func() -> void:
        _clear_inventory_ui()
    )
    settings_btn_clear_inventory.tooltip_text = "DEBUG: clears inventory and unequips all slots while preserving meso."
    settings_btn_telemetry.pressed.connect(func() -> void:
        _telemetry_enabled = not _telemetry_enabled
        _refresh_telemetry()
    )
    settings_btn_telemetry.tooltip_text = "Toggles runtime telemetry overlay."
    settings_btn_restart.pressed.connect(func() -> void:
        _restart_runtime()
    )
    settings_btn_restart.tooltip_text = "Restarts runtime process/scene and preserves saved state."
    settings_btn_quit.pressed.connect(func() -> void:
        _quit_runtime()
    )
    settings_btn_quit.tooltip_text = "Closes runtime process."
    settings_btn_chat.pressed.connect(func() -> void:
        _toggle_chat_window()
    )
    settings_btn_chat.tooltip_text = "Opens/closes the Buddy Chat popout window."
    settings_btn_stats.pressed.connect(func() -> void:
        _toggle_stats_menu()
    )
    settings_btn_stats.tooltip_text = "Opens/closes the Stats popout window."
    settings_btn_inventory.pressed.connect(func() -> void:
        _toggle_inventory_menu()
    )
    settings_btn_inventory.tooltip_text = "Opens/closes the Inventory popout window."
    settings_btn_wardrobe.pressed.connect(func() -> void:
        _toggle_wardrobe_menu()
    )
    settings_btn_wardrobe.tooltip_text = "Opens/closes the Wardrobe popout window."
    _ensure_settings_main_menu_ui()
    _build_settings_sections()
    _set_settings_menu_mode(false)
    _apply_settings_maple_theme()
    _layout_maple_window_chrome(settings_window, MAPLE_LAYOUT_SETTINGS_MAIN)
    if settings_floor_slider != null:
        settings_floor_slider.value_changed.connect(func(value: float) -> void:
            _set_floor_offset_adjust(value)
        )
        settings_floor_slider.set_value_no_signal(_desktop_floor_offset_adjust)


func _ensure_settings_main_menu_ui() -> void:
    if settings_margin_container == null:
        return
    if _settings_main_menu_box == null:
        _settings_main_menu_box = VBoxContainer.new()
        _settings_main_menu_box.name = "MapleGameMenu"
        _settings_main_menu_box.size_flags_horizontal = Control.SIZE_FILL
        _settings_main_menu_box.size_flags_vertical = Control.SIZE_FILL
        _settings_main_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
        _settings_main_menu_box.add_theme_constant_override("separation", 6)
        settings_margin_container.add_child(_settings_main_menu_box)
        settings_margin_container.move_child(_settings_main_menu_box, 1)
    if _settings_main_menu_box.get_child_count() > 0:
        return
    _settings_main_menu_box.alignment = BoxContainer.ALIGNMENT_BEGIN
    _settings_main_menu_box.add_theme_constant_override("separation", 7)
    if AppState.role() == "desktop":
        _main_menu_health = Label.new()
        _main_menu_health.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _main_menu_health.custom_minimum_size = Vector2(220, 0)
        _main_menu_health.add_theme_color_override("font_color", MapleTheme.TEXT_DIM)
        _main_menu_health.add_theme_font_size_override("font_size", 12)
        _settings_main_menu_box.add_child(_main_menu_health)
    _main_menu_status = Label.new()
    _main_menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _main_menu_status.custom_minimum_size = Vector2(220, 0)
    _main_menu_status.add_theme_color_override("font_color", MapleTheme.TEXT_DIM)
    _main_menu_status.add_theme_font_size_override("font_size", 12)
    _settings_main_menu_box.add_child(_main_menu_status)
    _main_menu_btn_chat = _add_main_menu_button("Chat", "Talk to your buddy and see what it has said.", _toggle_chat_window)
    if AppState.role() == "desktop":
        _main_menu_btn_call = _add_main_menu_button("Call over", "Ask your buddy to come and visit.", _call_or_send_home)
    _add_main_menu_button("Journal", "Read what your buddy has been doing on its own.", _open_journal)
    _add_main_menu_button("Memory", "What your buddy remembers about you. You can make it forget anything.", _toggle_memory_window)
    _add_main_menu_button("Town", "Where your buddy is, and the town it lives in.", _toggle_town_window)
    _main_menu_btn_stats = _add_main_menu_button("Stats", "Level, bond and stat points.", _toggle_stats_menu)
    _main_menu_btn_inventory = _add_main_menu_button("Inventory", "Items your buddy has collected.", _toggle_inventory_menu)
    _main_menu_btn_wardrobe = _add_main_menu_button("Wardrobe", "Change what your buddy wears.", _toggle_wardrobe_menu)
    _main_menu_btn_pause = _add_main_menu_button("Pause", "Put your buddy to sleep, or wake it up.", func() -> void:
        _toggle_sleep_state()
        _refresh_settings_menu()
    )
    _add_main_menu_button("Settings", "How busy and how talkative your buddy is.", func() -> void:
        _set_settings_menu_mode(true)
        _layout_settings_window()
        _refresh_settings_menu()
    )
    var quit_button := _add_main_menu_button("Quit", "Close Buddy.", _quit_runtime)
    MapleTheme.make_danger(quit_button)


func _add_main_menu_button(label: String, tooltip: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = label
    button.tooltip_text = tooltip
    button.custom_minimum_size = Vector2(0, 36)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.pressed.connect(action)
    _settings_main_menu_box.add_child(button)
    return button


# Shows the buddy's recent journal in the chat window, opening it if needed.
func _open_journal() -> void:
    if not _chat_window_open:
        _toggle_chat_window(false)
    _append_chat_line("Journal", "\n" + _build_journal_summary(), "#FFD77A")


# Regroups the settings buttons (which the scene keeps in one flat grid) under
# plain-language headings, adds switches for the buddy's own mind, and tucks
# the developer tools behind a toggle.
func _build_settings_sections() -> void:
    var controls_grid := settings_window.get_node_or_null("MarginContainer/SettingsVBox/ControlsGrid") as GridContainer
    if controls_grid == null or settings_vbox.get_node_or_null("SettingsSections") != null:
        return
    var sections := VBoxContainer.new()
    sections.name = "SettingsSections"
    sections.add_theme_constant_override("separation", 8)
    settings_vbox.add_child(sections)
    settings_vbox.move_child(sections, controls_grid.get_index())

    var back := Button.new()
    back.text = "< Back to menu"
    back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    back.pressed.connect(func() -> void:
        _set_settings_menu_mode(false)
        _layout_settings_window()
        _refresh_settings_menu()
    )
    settings_vbox.add_child(back)
    settings_vbox.move_child(back, 0)

    _settings_btn_autonomy = Button.new()
    _settings_btn_autonomy.tooltip_text = "When on, your buddy decides for itself what to do every ten minutes and keeps a journal."
    _settings_btn_autonomy.pressed.connect(func() -> void:
        _toggle_bool_setting("autonomyEnabled")
    )
    _settings_btn_model = Button.new()
    _settings_btn_model.tooltip_text = "When on, a local Ollama model puts your buddy's thoughts into its own words. Needs Ollama running at the address in settings (this PC by default)."
    _settings_btn_model.pressed.connect(func() -> void:
        _toggle_bool_setting("mindModelEnabled")
    )
    _settings_btn_chat_model = Button.new()
    _settings_btn_chat_model.tooltip_text = "When on, anything you type in chat that is not a command is sent to the Ollama server in settings (this PC by default) so your buddy can answer in its own words. Needs the thinking model on."
    _settings_btn_chat_model.pressed.connect(func() -> void:
        _toggle_bool_setting("chatModelEnabled")
    )
    _settings_btn_memory = Button.new()
    _settings_btn_memory.tooltip_text = "When on, your buddy remembers what you tell it from one day to the next: a few facts and a line about each talk, kept in this PC's save. To pick those out, each finished talk is sent once more to the Ollama server in settings (this PC by default). Menu > Memory shows everything it remembers."
    _settings_btn_memory.pressed.connect(_toggle_memory_setting)
    _settings_btn_world_host = Button.new()
    _settings_btn_world_host.tooltip_text = "When on, your buddy lives on its own land in a background program that keeps running when this app is closed. This app is your buddy visiting you: it comes over when you open the app (unless it is asleep or busy) and goes home at bedtime, after two quiet hours, when you send it home, or when you close the app. Takes effect the next time the app starts."
    _settings_btn_world_host.pressed.connect(func() -> void:
        _set_setting_with_audit("worldHost", not bool(AppState.settings.get("worldHost", false)), "menu")
        AppState.flush()
        _refresh_settings_menu()
    )

    _add_settings_section(sections, "How busy your buddy is", [
        settings_btn_event_freq, settings_btn_prompt_freq, settings_btn_intensity, settings_btn_quiet,
    ])
    _add_settings_section(sections, "Do not disturb", [settings_btn_dnd_15, settings_btn_dnd_30, settings_btn_dnd_off], 3)
    _add_settings_section(sections, "Its own mind", [_settings_btn_autonomy, _settings_btn_model, _settings_btn_chat_model, _settings_btn_memory, _settings_btn_world_host])
    _add_settings_section(sections, "Look and place", [settings_btn_mode, settings_btn_pack])

    _settings_btn_debug_toggle = Button.new()
    _settings_btn_debug_toggle.flat = false
    _settings_btn_debug_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _settings_btn_debug_toggle.pressed.connect(func() -> void:
        _settings_debug_box.visible = not _settings_debug_box.visible
        _refresh_settings_menu()
    )
    sections.add_child(_settings_btn_debug_toggle)
    _settings_debug_box = _add_settings_section(sections, "Developer tools", [
        settings_btn_demo_support, settings_btn_demo_world, settings_btn_reward, settings_btn_telemetry,
        settings_btn_seed_inventory, settings_btn_repair_inventory, settings_btn_restart, settings_btn_clear_inventory,
    ])
    _settings_debug_box.visible = false
    MapleTheme.make_danger(settings_btn_clear_inventory)

    # These live on the main menu now.
    for moved in [
        settings_btn_pause, settings_btn_chat, settings_btn_stats,
        settings_btn_inventory, settings_btn_wardrobe, settings_btn_quit,
    ]:
        moved.visible = false
    controls_grid.visible = false


func _add_settings_section(parent: Control, title: String, buttons: Array, columns: int = 2) -> Control:
    var panel := PanelContainer.new()
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 6)
    panel.add_child(box)
    box.add_child(MapleTheme.heading(title))
    var grid := GridContainer.new()
    grid.columns = columns
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 6)
    box.add_child(grid)
    for button_variant in buttons:
        var button := button_variant as Button
        if button == null:
            continue
        if button.get_parent() != null:
            button.get_parent().remove_child(button)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size = Vector2(0, 32)
        grid.add_child(button)
    parent.add_child(panel)
    return panel


func _toggle_bool_setting(key: String) -> void:
    _set_setting_with_audit(key, not bool(AppState.settings.get(key, true)), "menu")
    AppState.flush()
    _refresh_settings_menu()


func _set_settings_menu_mode(advanced: bool) -> void:
    _settings_menu_advanced = advanced
    if _settings_main_menu_box != null:
        _settings_main_menu_box.visible = not advanced
    if settings_vbox != null:
        settings_vbox.visible = advanced
    settings_window.title = "Buddy Settings" if advanced else "Buddy Menu"
    if advanced:
        _apply_settings_maple_theme()
        _layout_maple_window_chrome(settings_window, MAPLE_LAYOUT_SETTINGS)
    else:
        _ensure_maple_window_background(settings_window, MAPLE_WINDOW_SKIN_SETTINGS_MAIN)
        _layout_maple_window_chrome(settings_window, MAPLE_LAYOUT_SETTINGS_MAIN)


func _configure_chat_window() -> void:
    if chat_window == null:
        return
    chat_window.transient = false
    chat_window.exclusive = false
    chat_window.borderless = false
    chat_window.visible = false
    chat_window.always_on_top = true
    chat_window.unresizable = true
    var chat_layout_init := _layout_with_skin_size(MAPLE_LAYOUT_CHAT, MAPLE_WINDOW_SKIN_CHAT)
    chat_window.min_size = chat_layout_init["min_size"]
    chat_window.size = chat_layout_init["base_size"]
    chat_window.title = _chat_window_title()
    if chat_input != null:
        chat_input.max_length = MindThinker.MAX_USER_TEXT_CHARS
    chat_window.close_requested.connect(func() -> void:
        chat_window.hide()
        _chat_window_open = false
    )
    if chat_send != null:
        chat_send.pressed.connect(func() -> void:
            _send_chat_input()
        )
    if chat_input != null:
        chat_input.text_submitted.connect(func(_submitted: String) -> void:
            _send_chat_input()
        )
    _apply_chat_maple_theme()
    _layout_maple_window_chrome(chat_window, MAPLE_LAYOUT_CHAT)
    _apply_chat_text_size()


func _configure_stats_window() -> void:
    if stats_window == null:
        return
    if (
        stats_label == null
        or stats_btn_strength == null
        or stats_btn_dexterity == null
        or stats_btn_charisma == null
        or stats_btn_endurance == null
        or stats_btn_wisdom == null
        or stats_btn_knowledge == null
        or stats_btn_close == null
    ):
        push_warning("stats_window: missing expected nodes; stats UI wiring skipped")
        return
    stats_window.transient = false
    stats_window.exclusive = false
    stats_window.borderless = false
    stats_window.visible = false
    stats_window.unresizable = true
    var stats_layout_init := _layout_with_skin_size(MAPLE_LAYOUT_STATS, MAPLE_WINDOW_SKIN_STATS)
    stats_window.min_size = stats_layout_init["min_size"]
    stats_window.size = stats_layout_init["base_size"]
    stats_window.title = "Buddy Stats"
    stats_label.fit_content = true
    stats_label.scroll_active = false
    stats_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    stats_label.custom_minimum_size = Vector2(320, 0)
    stats_window.wrap_controls = true
    stats_window.always_on_top = true
    stats_window.close_requested.connect(func() -> void:
        stats_window.hide()
        _stats_menu_open = false
    )
    stats_btn_strength.pressed.connect(func() -> void:
        _allocate_stat_point_ui("strength")
    )
    stats_btn_dexterity.pressed.connect(func() -> void:
        _allocate_stat_point_ui("dexterity")
    )
    stats_btn_charisma.pressed.connect(func() -> void:
        _allocate_stat_point_ui("charisma")
    )
    stats_btn_endurance.pressed.connect(func() -> void:
        _allocate_stat_point_ui("endurance")
    )
    stats_btn_wisdom.pressed.connect(func() -> void:
        _allocate_stat_point_ui("wisdom")
    )
    stats_btn_knowledge.pressed.connect(func() -> void:
        _allocate_stat_point_ui("knowledge")
    )
    stats_btn_close.pressed.connect(func() -> void:
        _stats_menu_open = false
        _layout_stats_window()
    )
    _apply_stats_maple_theme()
    _layout_maple_window_chrome(stats_window, MAPLE_LAYOUT_STATS)
    _refresh_stats_menu()


func _configure_inventory_window() -> void:
    if inventory_window == null:
        return
    if (
        inventory_header == null
        or inventory_tab_all == null
        or inventory_tab_equip == null
        or inventory_tab_use == null
        or inventory_tab_etc == null
        or inventory_tab_decor == null
        or inventory_category_filter == null
        or inventory_list == null
        or paper_slot_gear_label == null
        or paper_slot_charm_label == null
        or paper_slot_relic_label == null
        or paper_btn_unequip_gear == null
        or paper_btn_unequip_charm == null
        or paper_btn_unequip_relic == null
        or inventory_detail == null
        or inventory_btn_use == null
        or inventory_btn_equip == null
        or inventory_btn_unequip == null
        or inventory_btn_close == null
        or inventory_icon_preview == null
        or inventory_detail_scroll == null
    ):
        push_warning("inventory_window: missing expected nodes; inventory UI wiring skipped")
        return
    inventory_window.transient = false
    inventory_window.exclusive = false
    inventory_window.borderless = false
    inventory_window.visible = false
    inventory_window.unresizable = true
    var inv_layout_init := _layout_with_skin_size(MAPLE_LAYOUT_INVENTORY, MAPLE_WINDOW_SKIN_INVENTORY)
    inventory_window.min_size = inv_layout_init["min_size"]
    inventory_window.size = inv_layout_init["base_size"]
    inventory_window.title = "Maple Buddy Inventory"
    inventory_window.wrap_controls = true
    inventory_window.always_on_top = true
    _apply_inventory_maple_theme()
    _layout_maple_window_chrome(inventory_window, MAPLE_LAYOUT_INVENTORY)
    _configure_inventory_fixed_maple_layout()
    inventory_list.icon_mode = ItemList.ICON_MODE_LEFT
    inventory_list.fixed_icon_size = Vector2i(24, 24)
    inventory_list.max_columns = 1
    inventory_list.same_column_width = false
    inventory_detail_scroll.follow_focus = true
    inventory_detail_scroll.scroll_deadzone = 32
    paper_slot_gear_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    paper_slot_charm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    paper_slot_relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    if paper_doll_title_label != null:
        paper_doll_title_label.text = "Equipped Slots"
    paper_btn_unequip_gear.text = "Unequip Group"
    paper_btn_unequip_charm.text = "Unequip Group"
    paper_btn_unequip_relic.text = "Unequip Group"
    paper_btn_unequip_gear.tooltip_text = "Unequip first equipped Combat-slot item."
    paper_btn_unequip_charm.tooltip_text = "Unequip first equipped Style-slot item."
    paper_btn_unequip_relic.tooltip_text = "Unequip first equipped Accessory-slot item."
    inventory_window.close_requested.connect(func() -> void:
        inventory_window.hide()
        _inventory_menu_open = false
    )
    inventory_tab_all.pressed.connect(func() -> void:
        _set_inventory_tab("all")
    )
    inventory_tab_equip.pressed.connect(func() -> void:
        _set_inventory_tab("equip")
    )
    inventory_tab_use.pressed.connect(func() -> void:
        _set_inventory_tab("use")
    )
    inventory_tab_etc.pressed.connect(func() -> void:
        _set_inventory_tab("etc")
    )
    inventory_tab_decor.pressed.connect(func() -> void:
        _set_inventory_tab("decor")
    )
    inventory_category_filter.item_selected.connect(func(_index: int) -> void:
        # Keep as optional sub-filter if needed later; currently tabs drive main filter.
        _refresh_inventory_menu()
    )
    inventory_list.item_selected.connect(func(index: int) -> void:
        if index < 0 or index >= _inventory_visible_instance_ids.size():
            _inventory_selected_instance_id = -1
        else:
            _inventory_selected_instance_id = int(_inventory_visible_instance_ids[index])
        _refresh_inventory_menu()
    )
    inventory_list.item_activated.connect(func(index: int) -> void:
        if index >= 0 and index < _inventory_visible_instance_ids.size():
            _inventory_selected_instance_id = int(_inventory_visible_instance_ids[index])
        _activate_selected_inventory_item()
    )
    inventory_btn_use.pressed.connect(func() -> void:
        _use_selected_inventory_item()
    )
    inventory_btn_equip.pressed.connect(func() -> void:
        _equip_selected_inventory_item()
    )
    inventory_btn_unequip.pressed.connect(func() -> void:
        _unequip_selected_inventory_item()
    )
    paper_btn_unequip_gear.pressed.connect(func() -> void:
        _unequip_first_paper_group_slot("combat")
    )
    paper_btn_unequip_charm.pressed.connect(func() -> void:
        _unequip_first_paper_group_slot("style")
    )
    paper_btn_unequip_relic.pressed.connect(func() -> void:
        _unequip_first_paper_group_slot("accessory")
    )
    inventory_btn_close.pressed.connect(func() -> void:
        _inventory_menu_open = false
        _layout_inventory_window()
    )

    inventory_category_filter.clear()
    for category in _inventory_filter_categories():
        inventory_category_filter.add_item(_inventory_category_display(category))
    inventory_category_filter.select(0)
    _inventory_active_tab = "all"
    _refresh_inventory_menu()


func _configure_inventory_fixed_maple_layout() -> void:
    if inventory_window == null:
        return
    var margin := inventory_window.get_node_or_null("MarginContainer") as MarginContainer
    var legacy_vbox := inventory_window.get_node_or_null("MarginContainer/InventoryVBox") as Control
    if margin == null or legacy_vbox == null:
        return
    if _inventory_maple_canvas == null:
        _inventory_maple_canvas = Control.new()
        _inventory_maple_canvas.name = "MapleInventoryCanvas"
        _inventory_maple_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
        _inventory_maple_canvas.anchor_left = 0.0
        _inventory_maple_canvas.anchor_top = 0.0
        _inventory_maple_canvas.anchor_right = 1.0
        _inventory_maple_canvas.anchor_bottom = 1.0
        _inventory_maple_canvas.offset_left = 0.0
        _inventory_maple_canvas.offset_top = 0.0
        _inventory_maple_canvas.offset_right = 0.0
        _inventory_maple_canvas.offset_bottom = 0.0
        margin.add_child(_inventory_maple_canvas)
    if legacy_vbox.visible:
        legacy_vbox.visible = false
    _place_inventory_control_fixed(inventory_header, Vector2(16, 8), Vector2(330, 26))
    _place_inventory_control_fixed(inventory_tab_all, Vector2(18, 42), Vector2(54, 22))
    _place_inventory_control_fixed(inventory_tab_equip, Vector2(76, 42), Vector2(58, 22))
    _place_inventory_control_fixed(inventory_tab_use, Vector2(138, 42), Vector2(48, 22))
    _place_inventory_control_fixed(inventory_tab_etc, Vector2(190, 42), Vector2(46, 22))
    _place_inventory_control_fixed(inventory_tab_decor, Vector2(240, 42), Vector2(60, 22))
    _place_inventory_control_fixed(inventory_category_filter, Vector2(306, 42), Vector2(120, 22))
    _place_inventory_control_fixed(inventory_list, Vector2(16, 72), Vector2(292, 200))
    inventory_list.visible = false
    _ensure_inventory_slot_grid_ui()
    _place_inventory_control_fixed(inventory_icon_preview, Vector2(328, 78), Vector2(52, 52))
    _place_inventory_control_fixed(inventory_detail_scroll, Vector2(386, 72), Vector2(200, 168))
    _place_inventory_control_fixed(inventory_btn_use, Vector2(328, 248), Vector2(60, 24))
    _place_inventory_control_fixed(inventory_btn_equip, Vector2(392, 248), Vector2(60, 24))
    _place_inventory_control_fixed(inventory_btn_unequip, Vector2(456, 248), Vector2(64, 24))
    _place_inventory_control_fixed(inventory_btn_close, Vector2(524, 248), Vector2(64, 24))


func _place_inventory_control_fixed(ctrl: Control, pos: Vector2, size: Vector2) -> void:
    if ctrl == null or _inventory_maple_canvas == null:
        return
    var parent := ctrl.get_parent()
    if parent != _inventory_maple_canvas:
        if parent != null:
            parent.remove_child(ctrl)
        _inventory_maple_canvas.add_child(ctrl)
    ctrl.anchor_left = 0.0
    ctrl.anchor_top = 0.0
    ctrl.anchor_right = 0.0
    ctrl.anchor_bottom = 0.0
    ctrl.offset_left = pos.x
    ctrl.offset_top = pos.y
    ctrl.offset_right = pos.x + size.x
    ctrl.offset_bottom = pos.y + size.y


func _ensure_inventory_slot_grid_ui() -> void:
    if _inventory_maple_canvas == null:
        return
    if _inventory_slot_scroll == null:
        _inventory_slot_scroll = ScrollContainer.new()
        _inventory_slot_scroll.name = "InventorySlotScroll"
        _inventory_slot_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
        _inventory_slot_scroll.follow_focus = true
        _inventory_slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        _inventory_slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
        _inventory_maple_canvas.add_child(_inventory_slot_scroll)
    if _inventory_slot_grid == null:
        _inventory_slot_grid = GridContainer.new()
        _inventory_slot_grid.name = "InventorySlotGrid"
        _inventory_slot_grid.columns = 8
        _inventory_slot_grid.add_theme_constant_override("h_separation", 2)
        _inventory_slot_grid.add_theme_constant_override("v_separation", 2)
        _inventory_slot_scroll.add_child(_inventory_slot_grid)
    _inventory_slot_scroll.anchor_left = 0.0
    _inventory_slot_scroll.anchor_top = 0.0
    _inventory_slot_scroll.anchor_right = 0.0
    _inventory_slot_scroll.anchor_bottom = 0.0
    _inventory_slot_scroll.offset_left = 16.0
    _inventory_slot_scroll.offset_top = 72.0
    _inventory_slot_scroll.offset_right = 16.0 + 292.0
    _inventory_slot_scroll.offset_bottom = 72.0 + 200.0
    _inventory_slot_grid.custom_minimum_size = Vector2(288.0, 200.0)


func _configure_wardrobe_window() -> void:
    if wardrobe_window == null:
        return
    if (
        wardrobe_header == null
        or wardrobe_list == null
        or wardrobe_preview == null
        or wardrobe_btn_toggle == null
        or wardrobe_btn_clear_slot == null
        or wardrobe_btn_equip_draft == null
        or wardrobe_btn_revert == null
        or wardrobe_btn_close == null
    ):
        push_warning("wardrobe_window: missing expected nodes; wardrobe UI wiring skipped")
        return

    wardrobe_window.transient = false
    wardrobe_window.exclusive = false
    wardrobe_window.borderless = false
    wardrobe_window.visible = false
    wardrobe_window.unresizable = true
    var wardrobe_layout_init := _layout_with_skin_size(MAPLE_LAYOUT_WARDROBE, MAPLE_WINDOW_SKIN_WARDROBE)
    wardrobe_window.min_size = wardrobe_layout_init["min_size"]
    wardrobe_window.size = wardrobe_layout_init["base_size"]
    wardrobe_window.title = "Maple Buddy Wardrobe"
    wardrobe_window.wrap_controls = false
    wardrobe_window.always_on_top = true
    _apply_wardrobe_maple_theme()
    _layout_maple_window_chrome(wardrobe_window, MAPLE_LAYOUT_WARDROBE)
    wardrobe_list.icon_mode = ItemList.ICON_MODE_LEFT
    wardrobe_list.fixed_icon_size = Vector2i(24, 24)
    wardrobe_list.max_columns = 1
    wardrobe_list.same_column_width = false
    wardrobe_list.visible = false
    _ensure_wardrobe_slot_grid_ui()
    wardrobe_window.close_requested.connect(func() -> void:
        _wardrobe_menu_open = false
        _layout_wardrobe_window()
        _sync_wardrobe_draft_from_equipped()
    )
    wardrobe_list.item_selected.connect(func(index: int) -> void:
        if index < 0 or index >= _wardrobe_visible_instance_ids.size():
            _wardrobe_selected_instance_id = -1
        else:
            _wardrobe_selected_instance_id = int(_wardrobe_visible_instance_ids[index])
        _refresh_wardrobe_menu()
    )
    wardrobe_list.item_activated.connect(func(index: int) -> void:
        if index >= 0 and index < _wardrobe_visible_instance_ids.size():
            _wardrobe_selected_instance_id = int(_wardrobe_visible_instance_ids[index])
        _toggle_selected_wardrobe_draft_slot()
    )
    wardrobe_btn_toggle.pressed.connect(func() -> void:
        _toggle_selected_wardrobe_draft_slot()
    )
    wardrobe_btn_clear_slot.pressed.connect(func() -> void:
        _clear_selected_wardrobe_slot()
    )
    wardrobe_btn_equip_draft.pressed.connect(func() -> void:
        _equip_wardrobe_draft()
    )
    wardrobe_btn_revert.pressed.connect(func() -> void:
        _sync_wardrobe_draft_from_equipped()
        _refresh_wardrobe_menu()
        _refresh_equipped_preview_from_draft()
        _buddy_say("Wardrobe draft reverted.")
    )
    wardrobe_btn_close.pressed.connect(func() -> void:
        _wardrobe_menu_open = false
        _layout_wardrobe_window()
        _sync_wardrobe_draft_from_equipped()
        _refresh_equipped_visual_state()
    )
    _sync_wardrobe_draft_from_equipped()
    _refresh_wardrobe_menu()


func _configure_menu_rebuild_window() -> void:
    if not _menu_rebuild_enabled:
        return
    if _menu_rebuild_window != null:
        return
    var window := Window.new()
    window.name = "MapleRebuildWindow"
    window.title = "Inventory"
    window.visible = false
    window.always_on_top = true
    window.unresizable = true
    window.wrap_controls = true
    add_child(window)
    _menu_rebuild_window = window
    window.close_requested.connect(func() -> void:
        _menu_rebuild_open = false
        _inventory_menu_open = false
        _wardrobe_menu_open = false
        window.hide()
        _refresh_settings_menu()
    )

    var margin := MarginContainer.new()
    margin.name = "MarginContainer"
    margin.anchor_right = 1.0
    margin.anchor_bottom = 1.0
    window.add_child(margin)

    var root := VBoxContainer.new()
    root.name = "RootVBox"
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)

    var header_row := HBoxContainer.new()
    header_row.name = "HeaderRow"
    root.add_child(header_row)

    var header := RichTextLabel.new()
    header.name = "Header"
    header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.fit_content = true
    header.scroll_active = false
    header.bbcode_enabled = true
    header.autowrap_mode = TextServer.AUTOWRAP_OFF
    header_row.add_child(header)
    _menu_rebuild_header = header

    var compact_btn := Button.new()
    compact_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
    compact_btn.focus_mode = Control.FOCUS_NONE
    header_row.add_child(compact_btn)
    _menu_rebuild_btn_compact = compact_btn
    compact_btn.pressed.connect(_toggle_inventory_compact)

    var tab_row := HBoxContainer.new()
    tab_row.name = "TabRow"
    tab_row.add_theme_constant_override("separation", 4)
    root.add_child(tab_row)
    _menu_rebuild_tabs.clear()
    var tab_labels := {"all": "All", "equip": "Gear", "use": "Usable", "etc": "Other", "decor": "Decor", "wardrobe": "Wardrobe"}
    for tab_id in ["all", "equip", "use", "etc", "decor", "wardrobe"]:
        var btn := Button.new()
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.toggle_mode = true
        btn.text = str(tab_labels[tab_id])
        tab_row.add_child(btn)
        _menu_rebuild_tabs[tab_id] = btn
        btn.pressed.connect(func() -> void:
            _set_rebuild_menu_tab(tab_id)
        )

    var split := HBoxContainer.new()
    split.name = "BodySplit"
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_theme_constant_override("separation", 10)
    root.add_child(split)

    var left_panel := PanelContainer.new()
    split.add_child(left_panel)
    var left_box := VBoxContainer.new()
    left_box.add_theme_constant_override("separation", 6)
    left_panel.add_child(left_box)

    var left_scroll := ScrollContainer.new()
    left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_scroll.custom_minimum_size = Vector2(
        INVENTORY_SLOT_COLUMNS * (INVENTORY_SLOT_PX + 3) + 12, 6 * (INVENTORY_SLOT_PX + 3)
    )
    left_box.add_child(left_scroll)
    left_scroll.set_drag_forwarding(Callable(), _rebuild_can_drop_on_grid, _rebuild_drop_on_grid)

    var slot_grid := GridContainer.new()
    slot_grid.columns = INVENTORY_SLOT_COLUMNS
    slot_grid.add_theme_constant_override("h_separation", 3)
    slot_grid.add_theme_constant_override("v_separation", 3)
    left_scroll.add_child(slot_grid)
    _menu_rebuild_slot_grid = slot_grid

    _menu_rebuild_empty_label = Label.new()
    _menu_rebuild_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _menu_rebuild_empty_label.custom_minimum_size = Vector2(320, 0)
    _menu_rebuild_empty_label.add_theme_color_override("font_color", MapleTheme.TEXT_DIM)
    _menu_rebuild_empty_label.add_theme_font_size_override("font_size", 12)
    left_box.add_child(_menu_rebuild_empty_label)

    var detail_panel := PanelContainer.new()
    detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(detail_panel)
    _menu_rebuild_detail_panel = detail_panel
    var detail_vbox := VBoxContainer.new()
    detail_vbox.name = "DetailVBox"
    detail_vbox.add_theme_constant_override("separation", 8)
    detail_panel.add_child(detail_vbox)

    var icon_frame := PanelContainer.new()
    icon_frame.add_theme_stylebox_override("panel", MapleTheme.slot(false))
    icon_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    detail_vbox.add_child(icon_frame)
    var icon := TextureRect.new()
    icon.custom_minimum_size = Vector2(64, 64)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    icon_frame.add_child(icon)
    _menu_rebuild_icon = icon

    _menu_rebuild_doll = Control.new()
    _menu_rebuild_doll.custom_minimum_size = Vector2(236, 216)
    _menu_rebuild_doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _menu_rebuild_doll.visible = false
    detail_vbox.add_child(_menu_rebuild_doll)
    var doll_preview := TextureRect.new()
    doll_preview.position = Vector2(44, 0)
    doll_preview.size = Vector2(148, 172)
    doll_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    doll_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    doll_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    doll_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _menu_rebuild_doll.add_child(doll_preview)
    _menu_rebuild_doll_preview = doll_preview
    _menu_rebuild_doll_slots.clear()
    for entry_variant in PAPER_DOLL_SLOTS:
        var entry: Dictionary = entry_variant
        var doll_slot_id: String = str(entry.get("id", ""))
        var doll_btn := Button.new()
        doll_btn.position = entry.get("pos", Vector2.ZERO)
        doll_btn.size = Vector2(40, 40)
        doll_btn.custom_minimum_size = Vector2(40, 40)
        doll_btn.expand_icon = true
        doll_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        doll_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        doll_btn.clip_text = true
        doll_btn.add_theme_font_size_override("font_size", 9)
        for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
            doll_btn.add_theme_color_override(color_name, Color(0.35, 0.32, 0.27))
        doll_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        _menu_rebuild_doll.add_child(doll_btn)
        _menu_rebuild_doll_slots[doll_slot_id] = doll_btn
        doll_btn.pressed.connect(func() -> void:
            _on_paper_doll_slot_pressed(doll_slot_id)
        )
        doll_btn.set_drag_forwarding(
            _rebuild_doll_drag_data.bind(doll_btn, doll_slot_id),
            _rebuild_can_drop_on_doll.bind(doll_slot_id),
            _rebuild_drop_on_doll.bind(doll_slot_id)
        )

    var detail := RichTextLabel.new()
    detail.custom_minimum_size = Vector2(0, 76)
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    detail.bbcode_enabled = true
    detail.fit_content = false
    detail.scroll_active = true
    detail_vbox.add_child(detail)
    _menu_rebuild_detail = detail

    var action_row := GridContainer.new()
    action_row.columns = 2
    action_row.add_theme_constant_override("h_separation", 6)
    action_row.add_theme_constant_override("v_separation", 6)
    detail_vbox.add_child(action_row)

    _menu_rebuild_btn_use = Button.new()
    _menu_rebuild_btn_use.text = "Use"
    _menu_rebuild_btn_use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    action_row.add_child(_menu_rebuild_btn_use)
    _menu_rebuild_btn_use.pressed.connect(func() -> void:
        _inventory_selected_instance_id = _menu_rebuild_selected_instance_id
        _use_selected_inventory_item()
        _refresh_rebuild_menu()
    )

    _menu_rebuild_btn_equip = Button.new()
    _menu_rebuild_btn_equip.text = "Wear"
    _menu_rebuild_btn_equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    action_row.add_child(_menu_rebuild_btn_equip)
    _menu_rebuild_btn_equip.pressed.connect(func() -> void:
        _inventory_selected_instance_id = _menu_rebuild_selected_instance_id
        _equip_selected_inventory_item()
        _refresh_rebuild_menu()
    )

    _menu_rebuild_btn_unequip = Button.new()
    _menu_rebuild_btn_unequip.text = "Take off"
    _menu_rebuild_btn_unequip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    action_row.add_child(_menu_rebuild_btn_unequip)
    _menu_rebuild_btn_unequip.pressed.connect(func() -> void:
        _inventory_selected_instance_id = _menu_rebuild_selected_instance_id
        _unequip_selected_inventory_item()
        _refresh_rebuild_menu()
    )

    _menu_rebuild_btn_close = Button.new()
    _menu_rebuild_btn_close.text = "Close"
    _menu_rebuild_btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    action_row.add_child(_menu_rebuild_btn_close)
    _menu_rebuild_btn_close.pressed.connect(func() -> void:
        _menu_rebuild_open = false
        _layout_rebuild_menu_window()
        _refresh_settings_menu()
    )

    _apply_maple_window_theme(
        window,
        [_menu_rebuild_btn_use, _menu_rebuild_btn_equip, _menu_rebuild_btn_unequip, _menu_rebuild_btn_close],
        [_menu_rebuild_header, _menu_rebuild_detail],
        [detail_vbox],
        [],
        MAPLE_WINDOW_SKIN_INVENTORY,
        true,
        true
    )
    _layout_maple_window_chrome(window, MAPLE_LAYOUT_REBUILD_MENU)


func _set_rebuild_menu_tab(tab_id: String) -> void:
    var tab := tab_id.to_lower().strip_edges()
    if tab == "wardrobe":
        _menu_rebuild_mode = "wardrobe"
    else:
        _menu_rebuild_mode = "inventory"
        _set_inventory_tab(tab)
    _layout_rebuild_menu_window()
    _refresh_rebuild_menu()


func _is_inventory_compact() -> bool:
    return _menu_rebuild_mode == "inventory" and bool(AppState.settings.get("inventoryCompact", false))


func _toggle_inventory_compact() -> void:
    _set_setting_with_audit("inventoryCompact", not bool(AppState.settings.get("inventoryCompact", false)), "menu")
    AppState.flush()
    _layout_rebuild_menu_window()
    _refresh_rebuild_menu()


func _toggle_rebuild_menu(mode: String) -> void:
    if not _menu_rebuild_enabled:
        return
    var normalized := mode.to_lower().strip_edges()
    if normalized not in ["inventory", "wardrobe"]:
        normalized = "inventory"
    if _menu_rebuild_open and _menu_rebuild_mode == normalized:
        _menu_rebuild_open = false
        _inventory_menu_open = false
        _wardrobe_menu_open = false
    else:
        _menu_rebuild_open = true
        _menu_rebuild_mode = normalized
        _inventory_menu_open = normalized == "inventory"
        _wardrobe_menu_open = normalized == "wardrobe"
    _layout_rebuild_menu_window()
    _refresh_rebuild_menu()
    _refresh_settings_menu()


func _layout_rebuild_menu_window() -> void:
    if _menu_rebuild_window == null:
        return
    if not _menu_rebuild_open:
        _menu_rebuild_window.hide()
        return
    inventory_window.hide()
    wardrobe_window.hide()
    var layout: Dictionary = MAPLE_LAYOUT_REBUILD_MENU.duplicate(true)
    if _is_inventory_compact():
        layout["base_size"] = INVENTORY_COMPACT_SIZE
        layout["min_size"] = INVENTORY_COMPACT_SIZE
    if _menu_rebuild_detail_panel != null:
        _menu_rebuild_detail_panel.visible = not _is_inventory_compact()
    _layout_popup_window(_menu_rebuild_window, true, layout)
    _menu_rebuild_window.title = "Inventory" if _menu_rebuild_mode == "inventory" else "Wardrobe"


func _on_paper_doll_slot_pressed(slot_id: String) -> void:
    var snapshot := AppState.get_inventory_snapshot()
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    var worn_id: int = int(equipped_slots.get(slot_id, -1))
    if worn_id > 0:
        _menu_rebuild_selected_instance_id = worn_id
        _inventory_selected_instance_id = worn_id
        _menu_rebuild_slot_filter = ""
    else:
        _menu_rebuild_slot_filter = "" if _menu_rebuild_slot_filter == slot_id else slot_id
    _refresh_rebuild_menu()


func _refresh_rebuild_paper_doll(equipped_slots: Dictionary) -> void:
    if _menu_rebuild_doll == null:
        return
    var is_wardrobe := _menu_rebuild_mode == "wardrobe"
    _menu_rebuild_doll.visible = is_wardrobe
    if _menu_rebuild_icon != null and _menu_rebuild_icon.get_parent() != null:
        _menu_rebuild_icon.get_parent().visible = not is_wardrobe
    if not is_wardrobe:
        return
    if _menu_rebuild_doll_preview != null:
        var preview_tex: Texture2D = null
        var idle_variant = _assembled_state_texture_overrides.get("idle")
        if typeof(idle_variant) == TYPE_DICTIONARY:
            var frames_variant = (idle_variant as Dictionary).get("frames", [])
            if typeof(frames_variant) == TYPE_ARRAY and not (frames_variant as Array).is_empty():
                preview_tex = (frames_variant as Array)[0] as Texture2D
        if preview_tex == null:
            preview_tex = _current_texture
        if preview_tex == null:
            preview_tex = PORTABLE_FALLBACK_TEXTURE
        _menu_rebuild_doll_preview.texture = preview_tex
    for entry_variant in PAPER_DOLL_SLOTS:
        var entry: Dictionary = entry_variant
        var slot_id: String = str(entry.get("id", ""))
        var label: String = str(entry.get("label", ""))
        var button := _menu_rebuild_doll_slots.get(slot_id) as Button
        if button == null:
            continue
        var worn_id: int = int(equipped_slots.get(slot_id, -1))
        var row: Dictionary = _inventory_item_by_instance(worn_id) if worn_id > 0 else {}
        var occupied := not row.is_empty()
        if occupied:
            var item_name: String = str(row.get("name", row.get("id", "Item")))
            var icon_tex := _resolve_item_overlay_texture(row)
            button.icon = icon_tex
            button.text = "" if icon_tex != null else item_name.substr(0, 1).to_upper()
            button.tooltip_text = "%s: %s\nClick to select it, then Take off." % [label, item_name]
            button.modulate = Color(1, 1, 1, 1)
        else:
            button.icon = null
            button.text = label
            button.tooltip_text = "%s: empty\nClick to show items that fit here." % label
            button.modulate = Color(1, 1, 1, 0.7)
        var highlight: bool = (worn_id > 0 and worn_id == _menu_rebuild_selected_instance_id) or _menu_rebuild_slot_filter == slot_id
        if highlight:
            button.add_theme_stylebox_override("normal", MapleTheme.slot(true))
            button.add_theme_stylebox_override("hover", MapleTheme.slot(true))
            button.add_theme_stylebox_override("pressed", MapleTheme.slot(true))
        else:
            button.add_theme_stylebox_override("normal", MapleTheme.slot(false))
            button.add_theme_stylebox_override("hover", MapleTheme.flat(MapleTheme.SLOT.lightened(0.25), MapleTheme.FRAME, 3, 2, 2, 2))
            button.add_theme_stylebox_override("pressed", MapleTheme.slot(true))
        button.add_theme_stylebox_override("focus", MapleTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 0, 2, 2))


func _refresh_rebuild_menu() -> void:
    if not _menu_rebuild_enabled:
        return
    if _menu_rebuild_window == null or _menu_rebuild_slot_grid == null:
        return
    if not _menu_rebuild_open:
        return
    if _menu_rebuild_mode != "wardrobe":
        _menu_rebuild_slot_filter = ""
    if _menu_rebuild_btn_use != null:
        _menu_rebuild_btn_use.visible = _menu_rebuild_mode != "wardrobe"
    var snapshot := AppState.get_inventory_snapshot()
    var inv_variant = snapshot.get("inventory", [])
    var inventory: Array = inv_variant if typeof(inv_variant) == TYPE_ARRAY else []
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    # The detail panel and the use/wear actions look items up in this cache;
    # without refreshing it here a newly gained item could not be selected.
    _inventory_rows_cache = inventory.duplicate(true)

    _menu_rebuild_slot_buttons_by_instance.clear()
    for child in _menu_rebuild_slot_grid.get_children():
        child.queue_free()

    var visible_ids: Array = []
    var allowed_categories := _inventory_categories_for_tab(_inventory_active_tab)
    for row_variant in _sort_inventory_rows(inventory, equipped_slots):
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var category := str(row.get("category", "")).to_lower()
        var is_equippable := _is_item_equippable(row)
        if _menu_rebuild_mode == "wardrobe":
            if not is_equippable:
                continue
            if _menu_rebuild_slot_filter != "" and _item_equip_slot_id(row) != _menu_rebuild_slot_filter:
                continue
        else:
            if not allowed_categories.has(category):
                continue
        var instance_id := int(row.get("instance_id", -1))
        if instance_id <= 0:
            continue
        visible_ids.append(instance_id)
        var btn := _make_inventory_slot(row, _equipped_slot_for_instance(equipped_slots, instance_id) != "")
        _menu_rebuild_slot_grid.add_child(btn)
        _menu_rebuild_slot_buttons_by_instance[instance_id] = btn
        btn.pressed.connect(func() -> void:
            _menu_rebuild_selected_instance_id = instance_id
            _refresh_rebuild_menu()
        )
        btn.gui_input.connect(func(event: InputEvent) -> void:
            if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and mb.pressed:
                    _menu_rebuild_selected_instance_id = instance_id
                    _inventory_selected_instance_id = instance_id
                    if _menu_rebuild_mode == "wardrobe":
                        _wardrobe_selected_instance_id = instance_id
                        _toggle_selected_wardrobe_draft_slot()
                    else:
                        _activate_selected_inventory_item()
                    _refresh_rebuild_menu()
        )

    if visible_ids.is_empty():
        _menu_rebuild_selected_instance_id = -1
    elif _menu_rebuild_selected_instance_id <= 0 or not visible_ids.has(_menu_rebuild_selected_instance_id):
        _menu_rebuild_selected_instance_id = int(visible_ids[0])

    for id_variant in _menu_rebuild_slot_buttons_by_instance.keys():
        var b := _menu_rebuild_slot_buttons_by_instance[id_variant] as Button
        if b == null:
            continue
        if int(id_variant) == _menu_rebuild_selected_instance_id:
            b.add_theme_stylebox_override("normal", MapleTheme.slot(true))
            b.add_theme_stylebox_override("hover", MapleTheme.slot(true))

    # Pad with empty slots so the grid always reads as an inventory.
    var slot_total := maxi(INVENTORY_MIN_SLOTS, int(ceil(float(visible_ids.size()) / INVENTORY_SLOT_COLUMNS)) * INVENTORY_SLOT_COLUMNS)
    for _i in range(slot_total - visible_ids.size()):
        var empty_slot := Panel.new()
        empty_slot.custom_minimum_size = Vector2(INVENTORY_SLOT_PX, INVENTORY_SLOT_PX)
        empty_slot.add_theme_stylebox_override("panel", MapleTheme.slot(false))
        empty_slot.modulate = Color(1, 1, 1, 0.55)
        empty_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _menu_rebuild_slot_grid.add_child(empty_slot)
    if _menu_rebuild_empty_label != null:
        if _menu_rebuild_mode == "wardrobe" and _menu_rebuild_slot_filter != "":
            if not visible_ids.is_empty():
                _menu_rebuild_empty_label.text = "Showing items for one slot. Click that slot again to show everything."
            else:
                _menu_rebuild_empty_label.text = "Nothing fits that slot yet. Click the slot again to show everything."
        elif _menu_rebuild_mode == "wardrobe" and not visible_ids.is_empty():
            _menu_rebuild_empty_label.text = "Drag an item onto a body slot to wear it, or drag a worn item back here to take it off."
        elif not visible_ids.is_empty():
            _menu_rebuild_empty_label.text = "Click an item to see it. Double-click to use or wear it."
        elif _menu_rebuild_mode == "wardrobe":
            _menu_rebuild_empty_label.text = "Nothing to wear yet. Gear your buddy finds will show up here."
        elif inventory.is_empty():
            _menu_rebuild_empty_label.text = "Empty for now. Your buddy brings things back from encounters and reward boxes."
        else:
            _menu_rebuild_empty_label.text = "Nothing in this tab. Try All."

    var selected := _inventory_item_by_instance(_menu_rebuild_selected_instance_id)
    if _menu_rebuild_header != null:
        var meso := int(snapshot.get("meso", snapshot.get("crystals", 0)))
        var mode_label := "Inventory" if _menu_rebuild_mode == "inventory" else "Wardrobe"
        _menu_rebuild_header.text = "[b][color=#FFD77A]%s[/color][/b]   [color=#A8E8FF]%d meso[/color]   [color=#9AA3B5]%d shown[/color]" % [mode_label, meso, visible_ids.size()]
    _refresh_rebuild_menu_tab_buttons()
    if _menu_rebuild_detail_panel != null:
        _menu_rebuild_detail_panel.visible = not _is_inventory_compact()
    if _menu_rebuild_btn_compact != null:
        _menu_rebuild_btn_compact.visible = _menu_rebuild_mode == "inventory"
        _menu_rebuild_btn_compact.text = "Expand" if _is_inventory_compact() else "Compact"
        _menu_rebuild_btn_compact.tooltip_text = "Show item details beside the grid." if _is_inventory_compact() else "Show only the item grid."
    _refresh_rebuild_paper_doll(equipped_slots)
    if _menu_rebuild_detail == null or _menu_rebuild_icon == null:
        return
    if selected.is_empty():
        _menu_rebuild_detail.text = "[color=#9AA3B5]No item selected.[/color]"
        _menu_rebuild_icon.texture = null
        if _menu_rebuild_btn_use != null:
            _menu_rebuild_btn_use.disabled = true
        if _menu_rebuild_btn_equip != null:
            _menu_rebuild_btn_equip.disabled = true
        if _menu_rebuild_btn_unequip != null:
            _menu_rebuild_btn_unequip.disabled = true
        return

    _inventory_selected_instance_id = _menu_rebuild_selected_instance_id
    var name := str(selected.get("name", selected.get("id", "Item")))
    var category := str(selected.get("category", "misc"))
    var rarity := str(selected.get("rarity", "common"))
    var desc := str(selected.get("description", "")).strip_edges()
    _menu_rebuild_icon.texture = _resolve_item_overlay_texture(selected)
    var equipped_slot := _equipped_slot_for_instance(equipped_slots, int(selected.get("instance_id", -1)))
    var rarity_color := str(RARITY_COLORS.get(rarity.to_lower(), "#F4E9CF"))
    var detail_text := "[b][color=%s]%s[/color][/b]\n[color=#9AA3B5]%s, %s[/color]" % [
        rarity_color, name, rarity.capitalize(), category.replace("_", " ")
    ]
    if equipped_slot != "":
        detail_text += "\n[color=#8FE39B]Wearing now (%s)[/color]" % equipped_slot
    if desc != "":
        detail_text += "\n\n%s" % desc
    _menu_rebuild_detail.text = detail_text
    if _menu_rebuild_btn_use != null:
        _menu_rebuild_btn_use.disabled = not _is_item_usable(selected)
    if _menu_rebuild_btn_equip != null:
        _menu_rebuild_btn_equip.disabled = not _is_item_equippable(selected) or equipped_slot != ""
    if _menu_rebuild_btn_unequip != null:
        _menu_rebuild_btn_unequip.disabled = equipped_slot == ""


func _refresh_rebuild_menu_tab_buttons() -> void:
    for key_variant in _menu_rebuild_tabs.keys():
        var key := str(key_variant)
        var btn := _menu_rebuild_tabs[key_variant] as Button
        if btn == null:
            continue
        var active := false
        if key == "wardrobe":
            active = _menu_rebuild_mode == "wardrobe"
        else:
            active = _menu_rebuild_mode == "inventory" and _inventory_active_tab == key
        btn.set_pressed_no_signal(active)
        if active:
            btn.add_theme_stylebox_override("normal", MapleTheme.flat(MapleTheme.BUTTON_HOVER, MapleTheme.SELECTION, 5, 2))
            btn.add_theme_stylebox_override("pressed", MapleTheme.flat(MapleTheme.BUTTON_HOVER, MapleTheme.SELECTION, 5, 2))
        else:
            btn.remove_theme_stylebox_override("normal")
            btn.remove_theme_stylebox_override("pressed")


# One occupied inventory slot: a beige square with the item's icon, its name
# and rarity as a tooltip, and a green corner mark when it is being worn.
func _make_inventory_slot(row: Dictionary, is_equipped: bool) -> Button:
    var btn := Button.new()
    btn.custom_minimum_size = Vector2(INVENTORY_SLOT_PX, INVENTORY_SLOT_PX)
    btn.icon = _resolve_item_overlay_texture(row)
    btn.expand_icon = true
    btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    btn.add_theme_stylebox_override("normal", MapleTheme.slot(false))
    btn.add_theme_stylebox_override("hover", MapleTheme.flat(MapleTheme.SLOT.lightened(0.25), MapleTheme.FRAME, 3, 2, 2, 2))
    btn.add_theme_stylebox_override("pressed", MapleTheme.slot(true))
    btn.add_theme_stylebox_override("focus", MapleTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 0, 2, 2))
    var item_name := str(row.get("name", row.get("id", "item")))
    btn.tooltip_text = "%s\n%s %s%s" % [
        item_name,
        str(row.get("rarity", "common")).capitalize(),
        str(row.get("category", "item")).replace("_", " "),
        "\nWearing now" if is_equipped else "",
    ]
    if btn.icon == null:
        # No picture for this item on this machine: show its initial instead.
        btn.text = item_name.substr(0, 1).to_upper()
        btn.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18))
        btn.add_theme_color_override("font_hover_color", Color(0.25, 0.22, 0.18))
    if is_equipped:
        var mark := ColorRect.new()
        mark.color = Color(0.30, 0.78, 0.42)
        mark.size = Vector2(9, 9)
        mark.position = Vector2(3, 3)
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(mark)
    var slot_instance_id: int = int(row.get("instance_id", -1))
    btn.set_drag_forwarding(_rebuild_item_drag_data.bind(btn, slot_instance_id), _rebuild_can_drop_on_grid, _rebuild_drop_on_grid)
    return btn


func _rebuild_drag_preview(texture: Texture2D, label: String) -> Control:
    if texture != null:
        var rect := TextureRect.new()
        rect.texture = texture
        rect.size = Vector2(36, 36)
        rect.custom_minimum_size = Vector2(36, 36)
        rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        return rect
    var lbl := Label.new()
    lbl.text = label.substr(0, 1).to_upper()
    return lbl


func _rebuild_item_drag_data(_at_position: Vector2, source: Control, instance_id: int) -> Variant:
    var row := _inventory_item_by_instance(instance_id)
    if row.is_empty():
        return null
    source.set_drag_preview(_rebuild_drag_preview(_resolve_item_overlay_texture(row), str(row.get("name", "?"))))
    return {"kind": "buddy_item", "instance_id": instance_id}


func _rebuild_doll_drag_data(_at_position: Vector2, source: Control, slot_id: String) -> Variant:
    var snapshot_variant: Variant = AppState.get_inventory_snapshot()
    var snapshot: Dictionary = snapshot_variant if snapshot_variant is Dictionary else {}
    var equipped_variant: Variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if equipped_variant is Dictionary else {}
    var worn_id: int = int(equipped_slots.get(slot_id, -1))
    if worn_id <= 0:
        return null
    var row := _inventory_item_by_instance(worn_id)
    source.set_drag_preview(_rebuild_drag_preview(_resolve_item_overlay_texture(row), str(row.get("name", "?"))))
    return {"kind": "buddy_worn", "slot_id": slot_id, "instance_id": worn_id}


func _rebuild_can_drop_on_doll(_at_position: Vector2, data: Variant, slot_id: String) -> bool:
    if not (data is Dictionary):
        return false
    if str(data.get("kind", "")) != "buddy_item":
        return false
    var row := _inventory_item_by_instance(int(data.get("instance_id", -1)))
    return _item_equip_slot_id(row) == slot_id


func _rebuild_drop_on_doll(_at_position: Vector2, data: Variant, slot_id: String) -> void:
    if not _rebuild_can_drop_on_doll(_at_position, data, slot_id):
        return
    var dragged_id: int = int(data.get("instance_id", -1))
    _menu_rebuild_selected_instance_id = dragged_id
    _inventory_selected_instance_id = dragged_id
    _equip_selected_inventory_item()
    _refresh_rebuild_menu()


func _rebuild_can_drop_on_grid(_at_position: Vector2, data: Variant) -> bool:
    if not (data is Dictionary):
        return false
    if str(data.get("kind", "")) != "buddy_worn":
        return false
    return int(data.get("instance_id", -1)) > 0


func _rebuild_drop_on_grid(_at_position: Vector2, data: Variant) -> void:
    if not _rebuild_can_drop_on_grid(_at_position, data):
        return
    var dragged_id: int = int(data.get("instance_id", -1))
    _menu_rebuild_selected_instance_id = dragged_id
    _inventory_selected_instance_id = dragged_id
    _unequip_selected_inventory_item()
    _refresh_rebuild_menu()


func _ensure_wardrobe_slot_grid_ui() -> void:
    var host := wardrobe_window.get_node_or_null("MarginContainer/WardrobeVBox/BodySplit") as Control
    if host == null:
        return
    if _wardrobe_slot_scroll == null:
        _wardrobe_slot_scroll = ScrollContainer.new()
        _wardrobe_slot_scroll.name = "WardrobeSlotScroll"
        _wardrobe_slot_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
        _wardrobe_slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        _wardrobe_slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
        host.add_child(_wardrobe_slot_scroll)
    if _wardrobe_slot_grid == null:
        _wardrobe_slot_grid = GridContainer.new()
        _wardrobe_slot_grid.name = "WardrobeSlotGrid"
        _wardrobe_slot_grid.columns = 4
        _wardrobe_slot_grid.add_theme_constant_override("h_separation", 2)
        _wardrobe_slot_grid.add_theme_constant_override("v_separation", 2)
        _wardrobe_slot_scroll.add_child(_wardrobe_slot_grid)
    _wardrobe_slot_scroll.anchor_left = 0.0
    _wardrobe_slot_scroll.anchor_top = 0.0
    _wardrobe_slot_scroll.anchor_right = 0.0
    _wardrobe_slot_scroll.anchor_bottom = 1.0
    _wardrobe_slot_scroll.offset_left = 8.0
    _wardrobe_slot_scroll.offset_top = 8.0
    _wardrobe_slot_scroll.offset_right = 8.0 + 178.0
    _wardrobe_slot_scroll.offset_bottom = -8.0
    _wardrobe_slot_grid.custom_minimum_size = Vector2(176.0, 220.0)


func _apply_wardrobe_maple_theme() -> void:
    var detail_vbox := wardrobe_window.get_node_or_null("MarginContainer/WardrobeVBox/BodySplit/WardrobeDetailVBox") as VBoxContainer
    _apply_maple_window_theme(
        wardrobe_window,
        [wardrobe_btn_toggle, wardrobe_btn_clear_slot, wardrobe_btn_equip_draft, wardrobe_btn_revert, wardrobe_btn_close],
        [wardrobe_header, wardrobe_preview],
        [detail_vbox],
        [],
        MAPLE_WINDOW_SKIN_WARDROBE,
        true,
        false
    )
    if wardrobe_list != null:
        wardrobe_list.add_theme_color_override("font_color", Color(0.96, 0.91, 0.81, 0.98))


func _apply_settings_maple_theme() -> void:
    if settings_window == null:
        return
    if not _settings_menu_advanced:
        _ensure_maple_window_background(settings_window, MAPLE_WINDOW_SKIN_SETTINGS_MAIN)
        return
    var controls_grid := settings_window.get_node_or_null("MarginContainer/SettingsVBox/ControlsGrid") as GridContainer
    var floor_box := settings_window.get_node_or_null("MarginContainer/SettingsVBox/FloorAdjustBox") as VBoxContainer
    _apply_maple_window_theme(
        settings_window,
        [
            settings_btn_event_freq, settings_btn_prompt_freq, settings_btn_quiet, settings_btn_dnd_15,
            settings_btn_dnd_30, settings_btn_dnd_off, settings_btn_intensity, settings_btn_mode,
            settings_btn_pack, settings_btn_demo_support, settings_btn_demo_world, settings_btn_reward,
        settings_btn_seed_inventory, settings_btn_repair_inventory, settings_btn_clear_inventory,
        settings_btn_telemetry, settings_btn_restart, settings_btn_quit, settings_btn_chat,
            settings_btn_stats, settings_btn_inventory, settings_btn_wardrobe,
        ],
        [settings_label],
        [controls_grid, floor_box],
        [],
        MAPLE_WINDOW_SKIN_SETTINGS,
        true,
        false
    )


func _apply_stats_maple_theme() -> void:
    if stats_window == null:
        return
    var stats_grid := stats_window.get_node_or_null("MarginContainer/StatsVBox/StatsGrid") as GridContainer
    _apply_maple_window_theme(
        stats_window,
        [
            stats_btn_strength, stats_btn_dexterity, stats_btn_charisma,
            stats_btn_endurance, stats_btn_wisdom, stats_btn_knowledge, stats_btn_close,
        ],
        [stats_label],
        [stats_grid],
        [],
        MAPLE_WINDOW_SKIN_STATS,
        true,
        false
    )


func _apply_chat_maple_theme() -> void:
    if chat_window == null:
        return
    var input_row := chat_window.get_node_or_null("MarginContainer/ChatVBox/ChatInputRow") as HBoxContainer
    _apply_maple_window_theme(
        chat_window,
        [chat_send],
        [chat_log],
        [input_row],
        [chat_input],
        MAPLE_WINDOW_SKIN_CHAT,
        true,
        false
    )
    if chat_input != null:
        chat_input.add_theme_color_override("font_color", Color(0.97, 0.90, 0.78, 0.98))
        chat_input.add_theme_color_override("font_placeholder_color", Color(0.68, 0.60, 0.50, 0.88))
        chat_input.add_theme_color_override("font_selected_color", Color(1.0, 0.95, 0.84, 0.98))


func _apply_maple_window_theme(
    target_window: Window,
    _buttons: Array,
    _rich_labels: Array,
    _panel_nodes: Array,
    _text_inputs: Array = [],
    window_skin_rel: String = "",
    _style_buttons: bool = true,
    _style_panels: bool = true
) -> void:
    # Every control picks its look up from the shared theme on the window.
    _ensure_maple_window_background(target_window, window_skin_rel)


func _ensure_maple_window_background(target_window: Window, _window_skin_rel: String = "") -> void:
    if target_window == null:
        return
    target_window.theme = MapleTheme.theme()
    target_window.transparent = false
    target_window.transparent_bg = false
    var bg := target_window.get_node_or_null("MapleWindowBG") as Panel
    if bg == null:
        bg = Panel.new()
        bg.name = "MapleWindowBG"
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        target_window.add_child(bg)
        target_window.move_child(bg, 0)


func _layout_maple_window_chrome(target_window: Window, layout_config: Dictionary) -> void:
    if target_window == null:
        return
    var margin := target_window.get_node_or_null("MarginContainer") as MarginContainer
    if margin == null:
        return
    var margins_variant = layout_config.get("margins", [18, 28, 18, 16])
    var margins: Array = margins_variant if typeof(margins_variant) == TYPE_ARRAY else [18, 28, 18, 16]
    while margins.size() < 4:
        margins.append(16)
    var left := int(margins[0])
    var top := int(margins[1])
    var right := int(margins[2])
    var bottom := int(margins[3])
    margin.offset_left = float(left)
    margin.offset_top = float(top)
    margin.offset_right = -float(right)
    margin.offset_bottom = -float(bottom)
    margin.add_theme_constant_override("margin_left", 0)
    margin.add_theme_constant_override("margin_top", 0)
    margin.add_theme_constant_override("margin_right", 0)
    margin.add_theme_constant_override("margin_bottom", 0)


func _layout_with_skin_size(layout_config: Dictionary, _skin_rel: String) -> Dictionary:
    # Windows used to be sized from the Maple window pictures. They are drawn
    # in code now, so the configured size is the size.
    return layout_config.duplicate(true)


func _apply_inventory_maple_theme() -> void:
    var detail_vbox := inventory_window.get_node_or_null("MarginContainer/InventoryVBox/BodySplit/DetailVBox") as VBoxContainer
    var button_nodes: Array = [
        inventory_tab_all,
        inventory_tab_equip,
        inventory_tab_use,
        inventory_tab_etc,
        inventory_tab_decor,
        paper_btn_unequip_gear,
        paper_btn_unequip_charm,
        paper_btn_unequip_relic,
        inventory_btn_use,
        inventory_btn_equip,
        inventory_btn_unequip,
        inventory_btn_close,
    ]
    _apply_maple_window_theme(
        inventory_window,
        button_nodes,
        [inventory_header, inventory_detail],
        [detail_vbox],
        [],
        MAPLE_WINDOW_SKIN_INVENTORY,
        true,
        false
    )
    if inventory_list != null:
        inventory_list.add_theme_color_override("font_color", Color(0.96, 0.91, 0.81, 0.98))
    if inventory_category_filter != null:
        inventory_category_filter.add_theme_color_override("font_color", Color(0.97, 0.90, 0.78, 0.98))
    if inventory_detail_scroll != null:
        inventory_detail_scroll.add_theme_color_override("scroll_focus", Color(1, 1, 1, 0))


func _draw() -> void:
    if _is_away():
        _draw_away_panel()
        return
    var center := _draw_center
    _draw_sit_chair(center)
    _draw_equipped_item_overlays(center, "back")
    if _draw_character_sprite(center, _presentation_texture()):
        _draw_equipped_item_overlays(center, "front")


func _center_point() -> Vector2:
    var viewport_size: Vector2 = get_viewport_rect().size
    return viewport_size * 0.5


func _floor_point() -> Vector2:
    var viewport_size: Vector2 = get_viewport_rect().size
    return Vector2(
        viewport_size.x * 0.5,
        viewport_size.y - SPRITE_VIEW_MARGIN + DESKTOP_FLOOR_CONTACT_OFFSET_Y + _desktop_floor_offset_adjust
    )


func _base_floor_reference_y(viewport_size: Vector2) -> float:
    return viewport_size.y - _floor_padding + _ground_floor_offset_y


func _ground_draw_size() -> Vector2:
    if _ground_texture == null:
        return Vector2.ZERO
    return _ground_texture.get_size() * maxf(0.05, _ground_scale)


func _ground_draw_y(viewport_size: Vector2, draw_size: Vector2) -> float:
    var draw_y := _base_floor_reference_y(viewport_size)
    if _ground_align == "center":
        draw_y -= draw_size.y * 0.5
    elif _ground_align == "bottom":
        draw_y -= draw_size.y
    return draw_y


func _ground_surface_y(viewport_size: Vector2) -> float:
    if _ground_texture == null:
        return _base_floor_reference_y(viewport_size)
    var scale := maxf(0.05, _ground_scale)
    var draw_size := _ground_draw_size()
    var draw_y := _ground_draw_y(viewport_size, draw_size)
    return draw_y + (_ground_surface_y_px * scale)


func _hit_test(point: Vector2) -> bool:
    if _is_away():
        return _away_panel_rect.grow(8.0).has_point(point)
    var texture := _presentation_texture()
    if texture != null:
        var hit_rect := _presentation_rect(_draw_center, texture).grow(8.0)
        _current_sprite_rect = hit_rect
        return hit_rect.has_point(point)
    if _current_sprite_rect.size.x > 0.0 and _current_sprite_rect.size.y > 0.0:
        return _current_sprite_rect.grow(8.0).has_point(point)
    return point.distance_to(_draw_center) <= FALLBACK_HIT_RADIUS


func _on_tick_timer_timeout() -> void:
    # At home the host lives its life: nothing here runs (the timers stay alive).
    if _is_away():
        return
    var now_unix := Time.get_unix_time_from_system()
    _flush_deferred_world_prompt(int(now_unix))
    var context := AppState.get_behavior_context(_allowed_actions)
    var activity_context := _productivity.get_context(now_unix, AppState.settings)
    for key in activity_context.keys():
        context[key] = activity_context[key]
    var home_mode := str(context.get("home_mode", "overlay"))

    # While the user has explicitly paused the buddy, no forced_action may be
    # computed or applied to context: doing so would both silently un-pause
    # the buddy on the next tick and pollute engine/tracker cooldown state
    # (e.g. mark a productivity event as "sent" or consume an encounter's
    # event budget) for an action the user never actually saw play out.
    if not _is_paused:
        var productivity_event := _productivity.tick(now_unix, AppState.settings)
        if not productivity_event.is_empty():
            var prod_event_id := str(productivity_event.get("id", ""))
            var prod_action := str(productivity_event.get("action", "happy"))
            context["forced_action"] = prod_action
            _last_event_id = prod_event_id
            AppState.record_event_trigger(prod_event_id, prod_action)
            _show_support_hint(productivity_event)

        if home_mode == "home":
            if not context.has("forced_action"):
                context["forced_action"] = _select_home_mode_action(now_unix)
        else:
            var selected_event := _encounters.tick(now_unix, context)
            if not selected_event.is_empty():
                var event_id := str(selected_event.get("id", ""))
                var action_id := str(selected_event.get("action", "gift"))
                var per_hour := int(selected_event.get("per_hour", 1))
                var per_day := int(selected_event.get("per_day", 4))
                if not context.has("forced_action") and AppState.try_consume_event_budget(event_id, per_hour, per_day):
                    context["forced_action"] = action_id
                    _last_event_id = event_id
                    AppState.record_event_trigger(event_id, action_id)

    if not _is_paused:
        _apply_mind_events(AppState.tick_mind(int(now_unix)), context)

    var action := _engine.tick(now_unix, context)
    var new_state := str(action.get("id", "idle"))
    if _is_paused:
        new_state = "sleep"
    _state = new_state
    _set_emote_from_state(_state)
    _set_visual_for_state(_state)
    AppState.apply_behavior(_state)
    var world_prompt := AppState.tick_world_events(int(now_unix))
    if not world_prompt.is_empty():
        if not _show_world_prompt(world_prompt):
            _deferred_world_prompt = world_prompt.duplicate(true)
            _manual_verification_report.record_prompt_metric("world", "deferred")
    _refresh_telemetry()
    if _state == "idle":
        _maybe_show_bond_phrase()
    _maybe_consolidate_memory()


# The buddy's own decisions. The latest one is acted out (unless something
# more urgent already claimed this tick) and spoken, except in quiet hours
# where it only goes in the journal.
func _apply_mind_events(events: Array, context: Dictionary) -> void:
    if events.is_empty():
        return
    if _town_window != null and _town_window.visible:
        _refresh_town_window()
    for event_variant in events:
        if typeof(event_variant) == TYPE_DICTIONARY and (event_variant as Dictionary).has("buy_want"):
            # It may have put on something it bought.
            _refresh_equipped_visual_state()
            break
    var latest_variant = events[events.size() - 1]
    if typeof(latest_variant) != TYPE_DICTIONARY:
        return
    var latest: Dictionary = latest_variant
    var action_id := str(latest.get("action", ""))
    # forced_action bypasses the engine's own filters, so apply both here:
    # the pack must be able to draw it and progression must have unlocked it.
    var action_allowed := _allowed_actions.is_empty() or _allowed_actions.has(action_id)
    var unlocked_variant = context.get("unlocked_actions", [])
    var unlocked: Array = unlocked_variant if typeof(unlocked_variant) == TYPE_ARRAY else []
    var action_unlocked := unlocked.is_empty() or unlocked.has(action_id)
    if action_id != "" and action_allowed and action_unlocked and not context.has("forced_action"):
        context["forced_action"] = action_id
    var suffix := ""
    if events.size() > 1:
        suffix = " (I did %d things while you were away. /journal has the rest.)" % events.size()
    if latest.has("buy_want"):
        # It just bought something it saved for: say that, in plain words,
        # rather than have the model word the shop visit and leave it out.
        var bought: Array = AppState.get_mind_journal(1)
        if not bought.is_empty() and typeof(bought[0]) == TYPE_DICTIONARY and str((bought[0] as Dictionary).get("kind", "")) == "purchase":
            _say_mind_line(str((bought[0] as Dictionary).get("text", "")), suffix)
            return
    if _request_mind_thought(latest, suffix):
        return
    _say_mind_line(str(latest.get("text", "")), suffix)


func _say_mind_line(line: String, suffix: String) -> void:
    if line == "" or AppState.is_quiet_hours_now() or _is_dnd_active():
        return
    _buddy_say(line + suffix)


# Asks the local thinking model to put the decision into the buddy's own
# words. Returns false when no request was started (model off, bad URL, or
# one already in flight); the caller then speaks the built-in wording.
func _request_mind_thought(event: Dictionary, suffix: String) -> bool:
    if AppState.small_beginnings():
        # The land's lines are written by hand and carry what it found and
        # noticed, so the model does not word over them. It still picks a name.
        _maybe_choose_name()
        return false
    if not bool(AppState.settings.get("mindModelEnabled", true)):
        _mind_model_status = "off"
        return false
    var url := MindThinker.endpoint(str(AppState.settings.get("mindModelUrl", MindThinker.DEFAULT_URL)))
    if url == "":
        _mind_model_status = "invalid mindModelUrl"
        return false
    if not _mind_pending.is_empty():
        return false
    if _mind_http == null:
        _mind_http = HTTPRequest.new()
        _mind_http.timeout = MindThinker.REQUEST_TIMEOUT_SECONDS
        _mind_http.body_size_limit = MindThinker.MAX_REPLY_BYTES
        _mind_http.max_redirects = 0
        _mind_http.request_completed.connect(_on_mind_thought_completed)
        add_child(_mind_http)
    var recent: Array = []
    for entry_variant in AppState.get_mind_journal(5):
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        if int(entry.get("t", 0)) != int(event.get("t", 0)):
            recent.append(str(entry.get("text", "")))
    var favourite: String = str(_mind_favourites().get("favourite", ""))
    var thought_model := str(AppState.settings.get("mindModelName", MindThinker.DEFAULT_MODEL))
    # With a different model for chat, unload the thought model straight away:
    # two models loaded at once can overflow graphics memory next to a game or
    # stream, and both then crawl (measured: 0.5 tokens a second).
    var keep_alive := "0s" if MindThinker.model_name(thought_model) != MindThinker.model_name(_chat_model_name()) else MindThinker.KEEP_ALIVE
    var body := MindThinker.build_request(thought_model, event, recent, favourite, keep_alive)
    var error := _mind_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
    if error != OK:
        _mind_model_status = "could not start request (%d)" % error
        return false
    _mind_pending = {"t": int(event.get("t", 0)), "fallback": str(event.get("text", "")), "suffix": suffix}
    return true


func _on_mind_thought_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var pending := _mind_pending
    _mind_pending = {}
    var line := str(pending.get("fallback", ""))
    if result != HTTPRequest.RESULT_SUCCESS:
        _mind_model_status = "unreachable (result %d)" % result
    elif response_code != 200:
        _mind_model_status = "server answered HTTP %d" % response_code
    else:
        var reply := MindThinker.parse_reply(body.get_string_from_utf8())
        if bool(reply.get("ok", false)):
            _mind_model_status = "ok"
            line = str(reply.get("thought", ""))
            AppState.apply_mind_thought(int(pending.get("t", 0)), line, str(reply.get("want", "")))
            # The journal line just changed to the buddy's own words; an open
            # Town window shows it under "Last time".
            if _town_window != null and _town_window.visible:
                _refresh_town_window()
            _maybe_choose_name()
        else:
            _mind_model_status = "unusable reply (%s)" % str(reply.get("reason", ""))
    _say_mind_line(line, str(pending.get("suffix", "")))


func _chat_model_name() -> String:
    return str(AppState.settings.get("chatModelName", AppState.settings.get("mindModelName", MindThinker.DEFAULT_MODEL)))


func _buddy_name() -> String:
    var mind: Variant = AppState.profile.get("mind", {})
    if typeof(mind) != TYPE_DICTIONARY:
        return ""
    return str((mind as Dictionary).get("name", ""))


func _chat_about() -> Dictionary:
    var snapshot := AppState.get_telemetry_snapshot()
    var favourites := _mind_favourites()
    var about := {}
    var buddy_name: String = _buddy_name()
    if buddy_name != "":
        about["name"] = buddy_name
    about["mood"] = str(snapshot.get("mood", "calm"))
    about["doing_now"] = _state
    about["favourite_so_far"] = str(favourites.get("favourite", ""))
    about["least_favourite"] = str(favourites.get("least", ""))
    var mind_variant = AppState.profile.get("mind", null)
    if typeof(mind_variant) == TYPE_DICTIONARY:
        var here: String = _place_display_name(str((mind_variant as Dictionary).get("location", "")))
        if here != "":
            about["where_you_are"] = here
    return about


func _town_places() -> Array:
    var places_variant = AppState.get_town().get("places", [])
    return places_variant if typeof(places_variant) == TYPE_ARRAY else []


func _town_place_names() -> Array:
    var names: Array = []
    for place_variant in _town_places():
        if typeof(place_variant) == TYPE_DICTIONARY:
            var place_name: String = str((place_variant as Dictionary).get("name", "")).strip_edges()
            if place_name != "":
                names.append(place_name)
    return names


func _place_display_name(place_id: String) -> String:
    if place_id == "":
        return ""
    for place_variant in _town_places():
        if typeof(place_variant) == TYPE_DICTIONARY and str((place_variant as Dictionary).get("id", "")) == place_id:
            return str((place_variant as Dictionary).get("name", place_id))
    return ""


func _town_npcs() -> Array:
    if AppState.small_beginnings():
        return []
    var world_variant = AppState.world_state.get("world", null)
    if typeof(world_variant) != TYPE_DICTIONARY:
        return []
    var npcs_variant = (world_variant as Dictionary).get("npcs", [])
    return npcs_variant if typeof(npcs_variant) == TYPE_ARRAY else []


# "Mira the mentor" style entries for every town character.
func _town_people() -> Array:
    var people: Array = []
    for npc_variant in _town_npcs():
        if typeof(npc_variant) != TYPE_DICTIONARY:
            continue
        var npc: Dictionary = npc_variant
        var npc_name: String = str(npc.get("name", "")).strip_edges()
        if npc_name == "":
            continue
        var role: String = str(npc.get("role", "")).strip_edges()
        people.append("%s the %s" % [npc_name, role] if role != "" else npc_name)
    return people


# Display name for a feelings key such as "place:pond" or "npc:mira".
func _subject_display_name(subject_id: String) -> String:
    if subject_id.begins_with("place:"):
        return _place_display_name(subject_id.trim_prefix("place:"))
    if subject_id.begins_with("npc:"):
        var npc_id: String = subject_id.trim_prefix("npc:")
        for npc_variant in _town_npcs():
            if typeof(npc_variant) == TYPE_DICTIONARY and str((npc_variant as Dictionary).get("id", "")) == npc_id:
                return str((npc_variant as Dictionary).get("name", npc_id))
    return ""


# The place or person it likes most and least, by name. Activities and home
# are left out: "my favourite is skip_stones" is not something it would say.
func _mind_favourites() -> Dictionary:
    var feelings: Dictionary = {}
    var mind_variant = AppState.profile.get("mind", null)
    if typeof(mind_variant) == TYPE_DICTIONARY and typeof((mind_variant as Dictionary).get("feelings", null)) == TYPE_DICTIONARY:
        feelings = (mind_variant as Dictionary)["feelings"]
    var best := ""
    var worst := ""
    for key_variant in feelings.keys():
        var key := str(key_variant)
        if key == "place:home" or _subject_display_name(key) == "":
            continue
        var value := float(feelings[key_variant])
        if best == "" or value > float(feelings[best]):
            best = key
        if worst == "" or value < float(feelings[worst]):
            worst = key
    var result := {"favourite": "", "least": ""}
    if best != "" and float(feelings[best]) > 0.0:
        result["favourite"] = _subject_display_name(best)
    if worst != "" and float(feelings[worst]) < 0.0:
        result["least"] = _subject_display_name(worst)
    return result


func _ensure_chat_http() -> void:
    if _chat_http != null:
        return
    _chat_http = HTTPRequest.new()
    _chat_http.timeout = MindThinker.REQUEST_TIMEOUT_SECONDS
    _chat_http.body_size_limit = MindThinker.MAX_REPLY_BYTES
    _chat_http.max_redirects = 0
    _chat_http.request_completed.connect(_on_chat_http_completed)
    add_child(_chat_http)


func _chat_model_ready_url(for_conversation: bool = true) -> String:
    if not bool(AppState.settings.get("mindModelEnabled", true)):
        return ""
    if for_conversation and not bool(AppState.settings.get("chatModelEnabled", true)):
        return ""
    # Only the local Ollama backend exists so far. Any other value turns
    # conversation off rather than sending text somewhere unexpected.
    if str(AppState.settings.get("chatBackend", "ollama")) != "ollama":
        return ""
    return MindThinker.endpoint(str(AppState.settings.get("mindModelUrl", MindThinker.DEFAULT_URL)))


func _start_chat_request(user_text: String) -> bool:
    if str(_chat_pending.get("kind", "")) == "greeting" and _chat_http != null:
        # Their words come first: drop a hello that has not arrived yet.
        _chat_http.cancel_request()
        _chat_pending = {}
    _end_stale_conversation()
    var url: String = _chat_model_ready_url()
    if url == "" or not _chat_pending.is_empty():
        return false
    _ensure_chat_http()
    var town := {"places": _town_place_names(), "people": _town_people()}
    var memory: Dictionary = AppState.memory_recall(user_text)
    if _chat_turns.is_empty():
        # Start of a talk: code picks one thing it remembers about you that
        # it may ask after, so remembering does not wait for you to bring it up.
        var bring_up: String = _pick_bring_up(memory)
        if bring_up != "":
            memory["bring_up"] = bring_up
    # Asked to go somewhere or see someone: the buddy decides now (code), and
    # the reply only puts that decision into words (model).
    var decision: Dictionary = {}
    var target: Dictionary = AppState.mind_find_suggestion(user_text)
    if not target.is_empty():
        decision = _decision_for(target, AppState.mind_consider(target))
    var body: String = MindThinker.build_chat_request(
        _chat_model_name(), _chat_about(), _recent_journal_texts(4), _chat_turns, user_text, town, memory,
        str(decision.get("fact", "")), str(decision.get("say", "")), AppState.small_beginnings()
    )
    var error: int = _chat_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
    if error != OK:
        return false
    _chat_turns.append({"who": "them", "text": user_text})
    _trim_chat_turns()
    AppState.memory_note_turn("them", user_text)
    _chat_pending = {"kind": "chat", "url": url, "body": body, "retried": false}
    return true


func _recent_journal_texts(limit: int) -> Array:
    var recent: Array = []
    for entry_variant in AppState.get_mind_journal(limit):
        if typeof(entry_variant) == TYPE_DICTIONARY:
            recent.append(str((entry_variant as Dictionary).get("text", "")))
    return recent


# One thing it remembers about you to ask after: a fact about you, not a note
# you asked it to keep and not your name.
func _pick_bring_up(memory: Dictionary) -> String:
    var facts_variant = memory.get("facts", [])
    if typeof(facts_variant) != TYPE_ARRAY:
        return ""
    for line_variant in facts_variant:
        var line: String = str(line_variant)
        if line.begins_with("they ") and not line.begins_with("they asked you to remember") and not line.begins_with("they are called"):
            return line
    return ""


# The decision about a suggestion: a fact with the reason, and the one thing
# the reply must say. Both models turned a soft "yes, next" into "maybe
# tomorrow", so the answer is spelled out where the model reads it last.
func _decision_for(target: Dictionary, considered: Dictionary) -> Dictionary:
    var target_name: String = str(target.get("name", ""))
    var is_npc: bool = str(target.get("kind", "")) == "npc"
    var asked: String = ("They suggested you go and see %s." if is_npc else "They suggested you go to %s.") % target_name
    var going: String = ("going to see %s" if is_npc else "going to %s") % target_name
    var reason: String = str(considered.get("reason", ""))
    match str(considered.get("answer", "")):
        "yes":
            return {
                "fact": "%s You said yes, because %s." % [asked, reason],
                "say": "Tell them yes: you are %s in a few minutes, not later." % going,
            }
        "later":
            return {
                "fact": "%s You said not yet, because %s." % [asked, reason],
                "say": "Tell them not yet, and why.",
            }
        "no":
            return {
                "fact": "%s You said no, because %s." % [asked, reason],
                "say": "Tell them no, kindly, and why.",
            }
    return {}


# Opening the chat after a while: the buddy says hello first and shares one
# thing from its day. Code picks the news and the memory; the model words them.
func _maybe_greet() -> void:
    # At home it is the host's buddy: no hello from here.
    if _is_away():
        return
    _end_stale_conversation()
    if not _chat_turns.is_empty() or not _chat_pending.is_empty():
        return
    if AppState.is_quiet_hours_now() or _is_dnd_active():
        return
    var url: String = _chat_model_ready_url()
    if url == "":
        return
    var news: Dictionary = AppState.mind_pick_news()
    var memory: Dictionary = AppState.memory_recall("")
    var bring_up: String = _pick_bring_up(memory)
    if bring_up != "":
        memory["bring_up"] = bring_up
    if news.is_empty() and bring_up == "":
        return
    _ensure_chat_http()
    var town := {"places": _town_place_names(), "people": _town_people()}
    var body: String = MindThinker.build_greeting_request(
        _chat_model_name(), _chat_about(), _recent_journal_texts(4), town, memory, str(news.get("text", "")),
        AppState.small_beginnings()
    )
    if _chat_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) == OK:
        _chat_pending = {"kind": "greeting", "news_t": int(news.get("t", 0))}


# Called after every line added to the talk, so it also notes when the talk
# last moved.
func _trim_chat_turns() -> void:
    _chat_last_turn_unix = int(Time.get_unix_time_from_system())
    while _chat_turns.size() > 16:
        _chat_turns.pop_front()


func _end_stale_conversation() -> void:
    if not _chat_turns.is_empty() and int(Time.get_unix_time_from_system()) - _chat_last_turn_unix >= CHAT_CONVERSATION_GAP_SECONDS:
        _chat_turns.clear()


func _town_character_names() -> Array:
    var names: Array = []
    var world_variant = AppState.world_state.get("world", null)
    if typeof(world_variant) != TYPE_DICTIONARY:
        return names
    var npcs_variant = (world_variant as Dictionary).get("npcs", [])
    if typeof(npcs_variant) != TYPE_ARRAY:
        return names
    for npc_variant in npcs_variant:
        if typeof(npc_variant) == TYPE_DICTIONARY:
            var npc_name: String = str((npc_variant as Dictionary).get("name", "")).strip_edges()
            if npc_name != "":
                names.append(npc_name)
    return names


func _maybe_choose_name() -> void:
    if _buddy_name() != "":
        return
    var url: String = _chat_model_ready_url(false)
    if url == "" or not _chat_pending.is_empty():
        return
    _ensure_chat_http()
    var about: Dictionary = _chat_about()
    about["names_already_taken"] = ", ".join(_town_character_names())
    var body: String = MindThinker.build_name_request(_chat_model_name(), about)
    var error: int = _chat_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
    if error == OK:
        _chat_pending = {"kind": "name"}


func _retry_chat_request() -> void:
    if _chat_http == null or str(_chat_pending.get("kind", "")) != "chat":
        return
    var url: String = str(_chat_pending.get("url", ""))
    var body: String = str(_chat_pending.get("body", ""))
    if url == "" or _chat_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
        _chat_pending = {}
        _buddy_say("I can't find my words right now. My thinking model isn't answering. /help lists what I understand without it.")


func _on_chat_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var pending := _chat_pending
    _chat_pending = {}
    var kind := str(pending.get("kind", ""))
    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        if kind == "memory":
            _on_memory_request_failed(pending)
            return
        if kind == "greeting":
            return
        # Ollama occasionally answers one request with a server error. Try a
        # chat line once more before telling the user something is wrong.
        var transient := result != HTTPRequest.RESULT_SUCCESS or response_code >= 500
        if kind == "chat" and transient and not bool(pending.get("retried", false)):
            pending["retried"] = true
            _chat_pending = pending
            _retry_chat_request.call_deferred()
            return
        if kind == "chat":
            if result == HTTPRequest.RESULT_SUCCESS and response_code == 404:
                _buddy_say("I can't find my words: the model %s isn't installed in Ollama. /help lists what I understand without it." % _chat_model_name())
            else:
                _buddy_say("I can't find my words right now. My thinking model isn't answering. /help lists what I understand without it.")
        return
    if kind == "chat":
        var reply: Dictionary = MindThinker.parse_chat_reply(body.get_string_from_utf8())
        if bool(reply.get("ok", false)):
            var reply_text: String = str(reply.get("reply", ""))
            _chat_turns.append({"who": "you", "text": reply_text})
            _trim_chat_turns()
            AppState.memory_note_turn("you", reply_text)
            _buddy_say(reply_text)
        else:
            _buddy_say("I lost my train of thought. Say that again?")
    elif kind == "memory":
        _on_memory_reply(pending, body.get_string_from_utf8())
    elif kind == "greeting":
        var greeting: Dictionary = MindThinker.parse_chat_reply(body.get_string_from_utf8())
        if bool(greeting.get("ok", false)):
            var hello: String = str(greeting.get("reply", ""))
            _chat_turns.append({"who": "you", "text": hello})
            _trim_chat_turns()
            AppState.memory_note_turn("you", hello)
            AppState.mind_mark_shared(int(pending.get("news_t", 0)))
            _buddy_say(hello)
    elif kind == "name":
        var named: Dictionary = MindThinker.parse_name_reply(body.get_string_from_utf8())
        if bool(named.get("ok", false)):
            var chosen: String = str(named.get("name", ""))
            for taken in _town_character_names():
                if str(taken).to_lower() == chosen.to_lower():
                    # Someone in town already has that name; try again later.
                    return
            if typeof(AppState.profile.get("mind", null)) != TYPE_DICTIONARY:
                AppState.profile["mind"] = {}
            AppState.profile["mind"]["name"] = chosen
            AppState.flush()
            _refresh_settings_menu()
            if chat_window != null:
                chat_window.title = _chat_window_title()
            if not AppState.is_quiet_hours_now() and not _is_dnd_active():
                _buddy_say("I've been thinking about what to call myself. I'm %s." % chosen)


# --- Memory (Plan 13 B2) ----------------------------------------------------
# When a talk has ended (five quiet minutes, or the chat window closed), one
# request turns it into a short summary and a few facts about the person. It
# shares the chat request slot, so it never runs while a reply is on its way.
func _maybe_consolidate_memory() -> void:
    if not _chat_pending.is_empty():
        return
    var now_unix := int(Time.get_unix_time_from_system())
    if now_unix < _memory_next_attempt_unix:
        return
    if not AppState.memory_should_consolidate(_chat_window_open):
        return
    var url: String = _chat_model_ready_url()
    if url == "":
        return
    var pending: Dictionary = AppState.memory_pending_turns()
    var turns_variant = pending.get("turns", [])
    var turns: Array = turns_variant if typeof(turns_variant) == TYPE_ARRAY else []
    var heard_them := false
    for turn_variant in turns:
        if typeof(turn_variant) == TYPE_DICTIONARY and str((turn_variant as Dictionary).get("who", "")) != "you":
            heard_them = true
            break
    if not heard_them:
        # Nothing of theirs worth reading (only lines that read like orders to
        # the buddy, which are never sent): let the talk go.
        AppState.memory_discard_turns(int(pending.get("upto", 0)))
        return
    _ensure_chat_http()
    var body: String = MindThinker.build_memory_request(_chat_model_name(), turns)
    if _chat_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
        return
    var lines: Array = []
    for turn_variant in turns:
        if typeof(turn_variant) == TYPE_DICTIONARY and str((turn_variant as Dictionary).get("who", "")) != "you":
            lines.append(str((turn_variant as Dictionary).get("text", "")))
    _chat_pending = {"kind": "memory", "upto": int(pending.get("upto", 0)), "lines": lines}
    # Set now, so a failed attempt waits before the same talk is tried again.
    _memory_next_attempt_unix = now_unix + MEMORY_RETRY_SECONDS


func _on_memory_reply(pending: Dictionary, body_text: String) -> void:
    var upto := int(pending.get("upto", 0))
    var parsed: Dictionary = MindThinker.parse_memory_reply(body_text)
    if not bool(parsed.get("ok", false)):
        _on_memory_request_failed(pending)
        return
    var facts_variant = parsed.get("facts", [])
    AppState.memory_apply_consolidation(
        facts_variant if typeof(facts_variant) == TYPE_ARRAY else [], str(parsed.get("summary", "")), upto
    )
    # The talk itself is an event in its day, and a place you mentioned may
    # become somewhere it wants to go.
    var lines_variant = pending.get("lines", [])
    AppState.mind_note_talk(str(parsed.get("summary", "")), lines_variant if typeof(lines_variant) == TYPE_ARRAY else [])
    _memory_failures = 0
    _memory_next_attempt_unix = 0
    _refresh_memory_window()


# After a few failed tries the talk is let go rather than retried forever.
func _on_memory_request_failed(pending: Dictionary) -> void:
    _memory_failures += 1
    if _memory_failures >= MEMORY_MAX_FAILURES:
        AppState.memory_discard_turns(int(pending.get("upto", 0)))
        _memory_failures = 0


# Forgetting has to win: the talk in progress is dropped from the model's view,
# and a request already sent with the old memories (a reply on its way, or a
# talk being sorted into memories) is cancelled, so its answer cannot bring
# them back.
func _after_memory_forgotten() -> void:
    _chat_turns.clear()
    # The unsaved part of the talk would otherwise teach it the same thing again.
    AppState.memory_discard_turns(int(AppState.memory_pending_turns().get("upto", 0)))
    var cancelled_kind := str(_chat_pending.get("kind", ""))
    if (cancelled_kind == "chat" or cancelled_kind == "memory" or cancelled_kind == "greeting") and _chat_http != null:
        _chat_http.cancel_request()
        _chat_pending = {}
        if cancelled_kind == "chat":
            _buddy_say("I've let that go. What were you saying?")
    _refresh_memory_window()


func _toggle_memory_setting() -> void:
    _toggle_bool_setting("memoryEnabled")
    # At home the buddy's memories are the host's to change: the talk in progress
    # is dropped when it next arrives instead (see _on_visit_arrived).
    if not AppState.memory_enabled() and not _is_away():
        # Off means nothing new is kept, including the talk in progress.
        AppState.memory_discard_turns(int(AppState.memory_pending_turns().get("upto", 0)))
    _refresh_memory_window()


func _toggle_memory_window() -> void:
    _ensure_memory_window()
    var opening := not _memory_window.visible
    if opening:
        _refresh_memory_window()
    _layout_popup_window(_memory_window, opening, MAPLE_LAYOUT_MEMORY)


func _ensure_memory_window() -> void:
    if _memory_window != null:
        return
    var window := Window.new()
    window.name = "MemoryWindow"
    window.title = "Memory"
    window.visible = false
    window.always_on_top = true
    window.wrap_controls = true
    add_child(window)
    _memory_window = window
    window.close_requested.connect(func() -> void:
        window.hide()
    )
    _ensure_maple_window_background(window)

    var margin := MarginContainer.new()
    margin.name = "MarginContainer"
    margin.anchor_right = 1.0
    margin.anchor_bottom = 1.0
    window.add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)

    _memory_intro = Label.new()
    _memory_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _memory_intro.custom_minimum_size = Vector2(300, 0)
    root.add_child(_memory_intro)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root.add_child(scroll)
    _memory_rows = VBoxContainer.new()
    _memory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _memory_rows.add_theme_constant_override("separation", 4)
    scroll.add_child(_memory_rows)

    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 8)
    root.add_child(buttons)
    _memory_btn_toggle = Button.new()
    _memory_btn_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _memory_btn_toggle.tooltip_text = "Off: nothing new is kept or used. What is already here stays until you forget it."
    _memory_btn_toggle.pressed.connect(_toggle_memory_setting)
    buttons.add_child(_memory_btn_toggle)
    _memory_btn_forget_all = Button.new()
    _memory_btn_forget_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _memory_btn_forget_all.tooltip_text = "Forget everything it knows about you. Click twice."
    _memory_btn_forget_all.pressed.connect(_on_forget_all_pressed)
    MapleTheme.make_danger(_memory_btn_forget_all)
    buttons.add_child(_memory_btn_forget_all)

    var note := Label.new()
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.custom_minimum_size = Vector2(300, 0)
    note.add_theme_color_override("font_color", MapleTheme.TEXT_DIM)
    note.add_theme_font_size_override("font_size", 12)
    note.text = "Kept only in this PC's save. To pick out what to keep, each finished talk is sent once to the thinking model at the address in settings."
    root.add_child(note)


func _refresh_memory_window() -> void:
    if _memory_window == null or _memory_rows == null:
        return
    _memory_window.title = "What %s remembers" % _speaker_name()
    for child in _memory_rows.get_children():
        _memory_rows.remove_child(child)
        child.queue_free()
    var rows: Array = AppState.memory_list()
    var enabled := AppState.memory_enabled()
    # What you said in a talk that has not been sorted into memories yet is
    # kept too, so it is listed (and can be forgotten) like everything else.
    var pending: Dictionary = AppState.memory_pending_turns()
    var pending_turns_variant = pending.get("turns", [])
    var pending_count: int = (pending_turns_variant as Array).size() if typeof(pending_turns_variant) == TYPE_ARRAY else 0
    if pending_count > 0:
        rows.push_front({
            "id": 0,
            "kind": "pending",
            "text": "Our talk in progress: %d line%s I haven't sorted into memories yet." % [pending_count, "" if pending_count == 1 else "s"],
        })
    if rows.is_empty():
        _memory_intro.text = (
            "Nothing yet. Talk to me in chat, or give me something to keep with /remember <note>."
            if enabled else "Remembering is off, and I'm not keeping anything about you."
        )
    else:
        _memory_intro.text = "What I remember about you. Forget removes one for good."
        if not enabled:
            _memory_intro.text += " Remembering is off, so nothing new is kept."
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var memory_id := int(row.get("id", 0))
        var line := HBoxContainer.new()
        line.add_theme_constant_override("separation", 6)
        var label := Label.new()
        label.text = str(row.get("text", ""))
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.custom_minimum_size = Vector2(240, 0)
        line.add_child(label)
        var forget := Button.new()
        forget.text = "Forget"
        forget.tooltip_text = "Forget this for good."
        forget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        # At home its memories are the host's: a forget here would not be saved.
        if _is_away():
            forget.disabled = true
            forget.tooltip_text = "%s is at home. Forget it when it visits." % _away_name()
        if str(row.get("kind", "")) == "pending":
            forget.pressed.connect(func() -> void:
                if _is_away():
                    return
                _after_memory_forgotten()
            )
        else:
            forget.pressed.connect(func() -> void:
                if _is_away():
                    return
                if AppState.memory_forget(memory_id):
                    _after_memory_forgotten()
            )
        line.add_child(forget)
        _memory_rows.add_child(line)
    _memory_btn_toggle.text = "Remembering: %s" % ("on" if enabled else "off")
    var armed := int(Time.get_unix_time_from_system()) <= _memory_forget_all_armed_until
    _memory_btn_forget_all.text = "Click again to forget all" if armed else "Forget everything"
    _memory_btn_forget_all.disabled = rows.is_empty() or _is_away()
    _memory_btn_forget_all.tooltip_text = (
        "%s is at home. Forget it when it visits." % _away_name() if _is_away()
        else "Forget everything it knows about you. Click twice."
    )


func _on_forget_all_pressed() -> void:
    if _is_away():
        return
    var now_unix := int(Time.get_unix_time_from_system())
    if now_unix <= _memory_forget_all_armed_until:
        _memory_forget_all_armed_until = 0
        AppState.memory_forget_all()
        _after_memory_forgotten()
        return
    _memory_forget_all_armed_until = now_unix + 5
    _refresh_memory_window()


# --- Town window (Plan 13 A2) -------------------------------------------------
# A map of the town drawn in code: places as tiles joined by paths, the
# buddy's marker where it is now, who is about at each open place, and a
# darker map at night. Click a place to read about it.
func _toggle_town_window() -> void:
    _ensure_town_window()
    var opening := not _town_window.visible
    if opening:
        _refresh_town_window()
    _layout_popup_window(_town_window, opening, MAPLE_LAYOUT_TOWN)


func _ensure_town_window() -> void:
    if _town_window != null:
        return
    var window := Window.new()
    window.name = "TownWindow"
    window.title = "Town"
    window.visible = false
    window.always_on_top = true
    window.wrap_controls = true
    add_child(window)
    _town_window = window
    window.close_requested.connect(func() -> void:
        window.hide()
    )
    _ensure_maple_window_background(window)
    var margin := MarginContainer.new()
    margin.name = "MarginContainer"
    margin.anchor_right = 1.0
    margin.anchor_bottom = 1.0
    window.add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)
    _town_heading = MapleTheme.heading("")
    root.add_child(_town_heading)
    _town_map = Control.new()
    _town_map.custom_minimum_size = Vector2(540, 340)
    _town_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _town_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _town_map.mouse_filter = Control.MOUSE_FILTER_STOP
    _town_map.draw.connect(_draw_town_map)
    _town_map.gui_input.connect(_on_town_map_input)
    root.add_child(_town_map)
    _town_info = Label.new()
    _town_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _town_info.custom_minimum_size = Vector2(300, 84)
    root.add_child(_town_info)


func _refresh_town_window() -> void:
    if _town_window == null:
        return
    _town_window.title = "%s's town" % _speaker_name()
    _town_heading.text = _where_is_it_now_line()
    if _town_selected == "":
        _town_info.text = "Click a place to see who is there and what %s thinks of it." % _speaker_name()
    else:
        _town_info.text = _town_place_details(_town_selected)
    _town_map.queue_redraw()


func _town_hour() -> int:
    return int(Time.get_datetime_dict_from_system().get("hour", 12))


func _town_place_open(place: Dictionary, hour: int) -> bool:
    return int(place.get("opens", 0)) <= hour and hour < int(place.get("closes", 24))


func _town_npc_name(npc_id: String) -> String:
    for npc_variant in _town_npcs():
        if typeof(npc_variant) == TYPE_DICTIONARY and str((npc_variant as Dictionary).get("id", "")) == npc_id:
            return str((npc_variant as Dictionary).get("name", npc_id))
    return npc_id.capitalize()


# Town characters about at a place now: its residents, while it is open and
# it is not the middle of the night.
func _town_people_at(place: Dictionary, hour: int) -> Array:
    var people: Array = []
    if not _town_place_open(place, hour) or hour < 7 or hour >= 22:
        return people
    var residents_variant = place.get("residents", [])
    if typeof(residents_variant) == TYPE_ARRAY:
        for npc_id in residents_variant:
            people.append(_town_npc_name(str(npc_id)))
    return people


func _buddy_location() -> String:
    var mind_variant = AppState.profile.get("mind", null)
    if typeof(mind_variant) != TYPE_DICTIONARY:
        return "home"
    return str((mind_variant as Dictionary).get("location", "home"))


func _where_is_it_now_line() -> String:
    var place_id := _buddy_location()
    var place_name := _place_display_name(place_id)
    if place_id == "home" or place_name == "":
        return "%s is at home." % _speaker_name()
    return "%s is at %s." % [_speaker_name(), place_name]


func _town_point(positions: Dictionary, inner: Rect2, place_id: String) -> Vector2:
    var unit: Vector2 = positions.get(place_id, Vector2(0.5, 0.5))
    return inner.position + unit * inner.size


func _draw_town_map() -> void:
    var map := _town_map
    var area := Rect2(Vector2.ZERO, map.size)
    var hour := _town_hour()
    var night := hour < 7 or hour >= 22
    map.draw_rect(area, Color(0.07, 0.09, 0.15) if night else Color(0.17, 0.27, 0.20))
    var layout: Dictionary = AppState.get_town_map()
    var positions_variant = layout.get("positions", {})
    var positions: Dictionary = positions_variant if typeof(positions_variant) == TYPE_DICTIONARY else {}
    var inner := area.grow(-48.0)
    var path_colour := Color(0.35, 0.36, 0.45) if night else Color(0.62, 0.55, 0.40)
    var paths_variant = layout.get("paths", [])
    if typeof(paths_variant) == TYPE_ARRAY:
        for path_variant in paths_variant:
            if typeof(path_variant) == TYPE_ARRAY and (path_variant as Array).size() == 2:
                map.draw_line(
                    _town_point(positions, inner, str(path_variant[0])), _town_point(positions, inner, str(path_variant[1])),
                    path_colour, 5.0, true
                )
    _town_tiles.clear()
    var font: Font = map.get_theme_default_font()
    var here := _buddy_location()
    for place_variant in _town_places():
        if typeof(place_variant) != TYPE_DICTIONARY:
            continue
        var place: Dictionary = place_variant
        var place_id := str(place.get("id", ""))
        if not positions.has(place_id):
            continue
        var centre := _town_point(positions, inner, place_id)
        var label := str(place.get("name", place_id))
        var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
        var tile := Rect2(centre - Vector2(text_width / 2.0 + 10.0, 14.0), Vector2(text_width + 20.0, 28.0))
        var open := _town_place_open(place, hour)
        var fill: Color = TOWN_TILE_COLOURS.get(str(place.get("kind", "")), MapleTheme.BUTTON)
        if not open:
            fill = fill.darkened(0.45)
        var selected := place_id == _town_selected
        map.draw_style_box(MapleTheme.flat(fill, MapleTheme.SELECTION if selected else MapleTheme.FRAME_DIM, 6, 2 if selected else 1, 0, 0), tile)
        map.draw_string(font, tile.position + Vector2(10.0, 19.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapleTheme.TEXT if open else MapleTheme.TEXT_DIM)
        _town_tiles[place_id] = tile
        # Who is about: a small rounded marker with their initial. (Map
        # markers are UI tiles; the overlay never draws the character itself.)
        var people := _town_people_at(place, hour)
        for index in range(people.size()):
            var dot := Vector2(tile.position.x + 12.0 + index * 18.0, tile.end.y + 10.0)
            map.draw_style_box(MapleTheme.flat(Color(0.86, 0.81, 0.70), Color(0.30, 0.28, 0.24), 8, 1, 0, 0), Rect2(dot - Vector2(8.0, 8.0), Vector2(16.0, 16.0)))
            map.draw_string(font, dot + Vector2(-4.0, 4.0), str(people[index]).substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.15, 0.15, 0.2))
        if place_id == here:
            var marker := Vector2(tile.get_center().x, tile.position.y - 12.0)
            map.draw_style_box(MapleTheme.flat(MapleTheme.HEADING, Color(0.45, 0.32, 0.08), 10, 1, 0, 0), Rect2(marker - Vector2(10.0, 10.0), Vector2(20.0, 20.0)))
            map.draw_string(font, marker + Vector2(-4.0, 5.0), _speaker_name().substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.15, 0.05))


func _on_town_map_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var click := event as InputEventMouseButton
    if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
        return
    for place_id in _town_tiles.keys():
        if (_town_tiles[place_id] as Rect2).has_point(click.position):
            _town_selected = str(place_id)
            _refresh_town_window()
            return


# Who is there, what the buddy thinks of it, and what happened there last.
func _town_place_details(place_id: String) -> String:
    var place: Dictionary = {}
    for place_variant in _town_places():
        if typeof(place_variant) == TYPE_DICTIONARY and str((place_variant as Dictionary).get("id", "")) == place_id:
            place = place_variant
    if place.is_empty():
        return ""
    var hour := _town_hour()
    var opens := int(place.get("opens", 0))
    var closes := int(place.get("closes", 24))
    var title := str(place.get("name", place_id))
    title = title.substr(0, 1).to_upper() + title.substr(1)
    var hours := "open all day" if opens <= 0 and closes >= 24 else "open %d:00 to %d:00, %s now" % [opens, closes, "open" if _town_place_open(place, hour) else "shut"]
    var lines: Array = ["%s: %s." % [title, hours]]
    var people := _town_people_at(place, hour)
    if not people.is_empty():
        lines.append("%s %s here." % [" and ".join(people), "is" if people.size() == 1 else "are"])
    var speaker := _speaker_name()
    var feelings: Dictionary = {}
    var mind_variant = AppState.profile.get("mind", null)
    if typeof(mind_variant) == TYPE_DICTIONARY and typeof((mind_variant as Dictionary).get("feelings", null)) == TYPE_DICTIONARY:
        feelings = (mind_variant as Dictionary)["feelings"]
    var key := "place:%s" % place_id
    if not feelings.has(key):
        lines.append("%s hasn't been yet." % speaker)
    else:
        var value := float(feelings[key])
        if value > 0.3:
            lines.append("%s loves it here." % speaker)
        elif value > 0.1:
            lines.append("%s likes it here." % speaker)
        elif value < -0.3:
            lines.append("%s doesn't like it much." % speaker)
        elif value < -0.1:
            lines.append("%s isn't keen on it." % speaker)
        else:
            lines.append("%s doesn't mind it." % speaker)
    var plan_items_variant = AppState.mind_day_plan().get("items", [])
    if typeof(plan_items_variant) == TYPE_ARRAY:
        for item_variant in plan_items_variant:
            if typeof(item_variant) == TYPE_DICTIONARY and str((item_variant as Dictionary).get("id", "")) == place_id and not bool((item_variant as Dictionary).get("done", false)):
                lines.append("It's on today's plan.")
    if str(place.get("kind", "")) == "shop":
        var saving: Array = []
        for want_variant in AppState.mind_wants():
            if typeof(want_variant) == TYPE_DICTIONARY:
                saving.append(str((want_variant as Dictionary).get("name", "")))
        if not saving.is_empty():
            lines.append("Saving up for: %s." % ", ".join(saving))
    var last_text := ""
    for entry_variant in AppState.get_mind_journal(40):
        if typeof(entry_variant) == TYPE_DICTIONARY and str((entry_variant as Dictionary).get("place_id", "")) == place_id:
            last_text = str((entry_variant as Dictionary).get("text", ""))
    if last_text != "":
        lines.append("Last time: \"%s\"" % last_text)
    return " ".join(lines)


func _build_wants_summary() -> String:
    var wants: Array = AppState.mind_wants()
    if wants.is_empty():
        return "I'm not saving up for anything right now."
    var parts: Array = []
    for want_variant in wants:
        if typeof(want_variant) == TYPE_DICTIONARY:
            var want: Dictionary = want_variant
            parts.append("%s, %d meso (%s)" % [str(want.get("name", "")), int(want.get("price", 0)), str(want.get("reason", ""))])
    return "I'm saving up for: %s. I have %d meso so far." % ["; ".join(parts), int(AppState.get_inventory_snapshot().get("meso", 0))]


func _build_journal_summary() -> String:
    var entries := AppState.get_mind_journal(5)
    if entries.is_empty():
        return "My journal is empty so far. Give me a little time. (Thinking model: %s)" % _mind_model_summary()
    var lines: Array[String] = []
    for entry_variant in entries:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        var stamp := Time.get_datetime_string_from_unix_time(int(entry.get("t", 0)), true)
        lines.append("%s UTC: %s" % [stamp.substr(5, 11), str(entry.get("text", ""))])
    lines.append("Thinking model: %s" % _mind_model_summary())
    return "\n".join(lines)


func _mind_model_summary() -> String:
    var model := MindThinker.model_name(str(AppState.settings.get("mindModelName", MindThinker.DEFAULT_MODEL)))
    return "%s, %s" % [model, _mind_model_status]


func _is_night() -> bool:
    var now := Time.get_datetime_dict_from_system()
    var hour := int(now.get("hour", 12))
    return hour < 7 or hour >= 22


func _load_content_pack() -> void:
    var selected_pack := str(AppState.settings.get("selectedPackId", "core_pack"))
    var allow_development := OS.get_cmdline_user_args().has("--allow-development-packs")
    var loaded := ContentLoader.load_with_fallback(selected_pack, "", allow_development)

    var source_tier := str(loaded.get("source_tier", "selected"))
    if source_tier != "selected":
        print(
            "content: pack fallback — tier=%s reason=%s errors_by_tier=%s"
            % [source_tier, loaded.get("fallback_reason", ""), loaded.get("errors_by_tier", {})]
        )

    _active_pack_id = str(loaded.get("pack_id", "core_pack"))
    _active_manifest = loaded.get("manifest", {})
    var ids := ContentLoader.list_cycleable_pack_ids()
    var slot_index := ids.find(_active_pack_id)
    if slot_index < 0:
        slot_index = ids.find(selected_pack)
    if slot_index < 0:
        slot_index = 0
    _pack_scale_override = _pack_scale_for_slot(slot_index)
    _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
    if _allowed_actions.is_empty():
        _allowed_actions = ["idle", "sit", "sleep", "wander", "happy", "gift", "visitor"]

    _load_visual_assets(_active_pack_id, _active_manifest)
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
    _refresh_equipped_visual_state()


func _restore_window_state() -> void:
    var state := AppState.get_window_state()
    var preferred_screen := _normalize_screen_index(int(state.get("preferredScreen", 0)))
    var preferred_pos: Vector2i = Vector2i(120, 120)
    var preferred_raw = state.get("position", Vector2i(120, 120))
    if typeof(preferred_raw) == TYPE_VECTOR2I:
        preferred_pos = preferred_raw

    DisplayServer.window_set_current_screen(preferred_screen)
    var clamped := _clamp_window_to_screen(preferred_pos, preferred_screen)
    DisplayServer.window_set_position(clamped)


func _normalize_screen_index(index: int) -> int:
    var count := DisplayServer.get_screen_count()
    if count <= 0:
        return 0
    if index < 0:
        return 0
    if index >= count:
        return count - 1
    return index


func _screen_rect(screen_index: int) -> Rect2i:
    var normalized := _normalize_screen_index(screen_index)
    return DisplayServer.screen_get_usable_rect(normalized)


func _screen_for_point(point: Vector2i) -> int:
    var count := DisplayServer.get_screen_count()
    for i in range(count):
        var rect := _screen_rect(i)
        if rect.has_point(point):
            return i
    return -1


func _clamp_window_to_screen(next_pos: Vector2i, screen_index: int) -> Vector2i:
    var rect := _screen_rect(screen_index)
    var window_size := DisplayServer.window_get_size()
    var max_x: int = rect.position.x + maxi(0, rect.size.x - window_size.x)
    var max_y: int = rect.position.y + maxi(0, rect.size.y - window_size.y)
    return Vector2i(
        clampi(next_pos.x, rect.position.x, max_x),
        clampi(next_pos.y, rect.position.y, max_y)
    )


func _cycle_event_frequency() -> void:
    var current := str(AppState.settings.get("eventFrequency", "normal"))
    var values := ["low", "normal", "high"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("eventFrequency", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("eventFrequency", values[index])
    _update_balloon_position()
    _buddy_say(
        "Event frequency: %s. %s"
        % [values[index], _build_cadence_hint_compact()]
    )
    _refresh_telemetry()


func _cycle_prompt_frequency() -> void:
    var current := str(AppState.settings.get("promptFrequency", "normal"))
    var values := ["low", "normal", "high"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("promptFrequency", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("promptFrequency", values[index])
    _update_balloon_position()
    _buddy_say(
        "Prompt frequency: %s. %s"
        % [values[index], _build_cadence_hint_compact()]
    )
    _refresh_telemetry()


func _cycle_interaction_intensity() -> void:
    var current := str(AppState.settings.get("interactionIntensity", "balanced"))
    var values := ["cozy", "balanced", "deep", "idle"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("interactionIntensity", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("interactionIntensity", values[index])
    _update_balloon_position()
    var line: String = "Interaction intensity: %s" % values[index]
    if values[index] == "idle":
        line += " (autopilot + auto stat assignment)"
    _buddy_say(line)
    _refresh_telemetry()


func _cycle_quiet_strictness() -> void:
    var current := str(AppState.settings.get("quietModeStrictness", "balanced"))
    var values := ["lenient", "balanced", "strict"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("quietModeStrictness", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("quietModeStrictness", values[index])
    _update_balloon_position()
    _buddy_say("Quiet strictness: %s. %s" % [values[index], _build_cadence_hint_compact()])
    _refresh_telemetry()


func _move_to_next_monitor() -> void:
    var count := DisplayServer.get_screen_count()
    if count <= 1:
        return
    var current := _normalize_screen_index(DisplayServer.window_get_current_screen())
    var next_screen: int = (current + 1) % count
    DisplayServer.window_set_current_screen(next_screen)
    var current_pos := DisplayServer.window_get_position()
    var clamped := _clamp_window_to_screen(current_pos, next_screen)
    DisplayServer.window_set_position(clamped)
    AppState.set_window_state(next_screen, clamped)
    _refresh_telemetry()


func _update_window_roam(delta: float) -> void:
    if _dragging:
        return

    var roam_state := _state == "wander" or _state == "visitor"
    var current_screen := _normalize_screen_index(DisplayServer.window_get_current_screen())
    var screen_rect := _screen_rect(current_screen)
    var window_size := DisplayServer.window_get_size()
    var floor_y := screen_rect.position.y + maxi(0, screen_rect.size.y - window_size.y)

    var current_pos := DisplayServer.window_get_position()

    if not roam_state:
        if _state == "sleep":
            _facing_sign = SPRITE_ART_FACING
        var floor_locked := _clamp_window_to_screen(current_pos, current_screen)
        if floor_locked.y != floor_y and (_floor_settle_active or current_pos.y != floor_y):
            var dir := 1 if floor_locked.y < floor_y else -1
            var step := int(round(FLOOR_SETTLE_SPEED_PX_PER_SEC * delta)) * dir
            if step == 0:
                step = dir
            floor_locked.y += step
            if (dir > 0 and floor_locked.y > floor_y) or (dir < 0 and floor_locked.y < floor_y):
                floor_locked.y = floor_y
        else:
            floor_locked.y = floor_y
        if floor_locked.y == floor_y:
            _floor_settle_active = false
        if floor_locked != DisplayServer.window_get_position():
            DisplayServer.window_set_position(floor_locked)
            AppState.set_window_state(current_screen, floor_locked)
        return

    var speed := maxf(12.0, _roam_speed_px_per_sec)
    var move_px := (float(_roam_direction) * speed * delta) + _roam_subpixel_x
    var step := int(round(move_px))
    _roam_subpixel_x = move_px - float(step)
    if step == 0:
        step = _roam_direction
    if step != 0:
        _facing_sign = 1 if step > 0 else -1

    var min_x := screen_rect.position.x
    var max_x := screen_rect.position.x + maxi(0, screen_rect.size.x - window_size.x)
    var next_x := current_pos.x + step
    if next_x <= min_x:
        next_x = min_x
        _roam_direction = 1
        _facing_sign = 1
    elif next_x >= max_x:
        next_x = max_x
        _roam_direction = -1
        _facing_sign = -1

    var next_pos := Vector2i(next_x, floor_y)
    if next_pos != DisplayServer.window_get_position():
        DisplayServer.window_set_position(next_pos)
        AppState.set_window_state(current_screen, next_pos)


func _cycle_pack() -> void:
    var allow_development := OS.get_cmdline_user_args().has("--allow-development-packs")
    var ids := ContentLoader.list_cycleable_pack_ids("", allow_development)
    if ids.is_empty():
        _update_balloon_position()
        _buddy_say("No valid content packs found.")
        return
    if ids.size() == 1:
        var only_pack := str(ids[0])
        var loaded_only := ContentLoader.load_with_fallback(only_pack, "", allow_development)
        var only_manifest_variant = loaded_only.get("manifest", null)
        if typeof(only_manifest_variant) != TYPE_DICTIONARY:
            _update_balloon_position()
            _buddy_say("Pack load failed: %s" % only_pack)
            return
        _active_pack_id = str(loaded_only.get("pack_id", only_pack))
        _active_manifest = only_manifest_variant as Dictionary
        _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
        _pack_scale_override = float(PACK_SCALE_PRESETS[0])
        _encounters.configure(
            _active_manifest.get("eventRules", []),
            int(AppState.profile.get("personality_seed", 0))
        )
        _load_visual_assets(_active_pack_id, _active_manifest)
        AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
        _update_balloon_position()
        _buddy_say(
            "Only valid pack available: %s (size %.2f)."
            % [_active_pack_id, _pack_scale_override]
        )
        _refresh_telemetry()
        return

    var current := str(AppState.settings.get("selectedPackId", "core_pack"))
    var index := ids.find(current)
    if index < 0:
        index = 0
    else:
        index = (index + 1) % ids.size()

    var next_pack := str(ids[index])
    var loaded := ContentLoader.load_with_fallback(next_pack, "", allow_development)
    var manifest_variant = loaded.get("manifest", null)
    if typeof(manifest_variant) != TYPE_DICTIONARY:
        _update_balloon_position()
        _buddy_say("Pack load failed: %s" % next_pack)
        return

    _active_pack_id = str(loaded.get("pack_id", next_pack))
    _active_manifest = manifest_variant as Dictionary
    var slot_index := ids.find(_active_pack_id)
    if slot_index < 0:
        slot_index = index
    _pack_scale_override = _pack_scale_for_slot(slot_index)
    _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
    _encounters.configure(
        _active_manifest.get("eventRules", []),
        int(AppState.profile.get("personality_seed", 0))
    )
    _load_visual_assets(_active_pack_id, _active_manifest)
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
    _update_balloon_position()
    var slot := slot_index + 1
    if slot <= 0:
        slot = index + 1
    _buddy_say(
        "Active pack: %s (slot %d/%d, size %.2f)."
        % [_active_pack_id, slot, ids.size(), _sprite_scale]
    )
    _refresh_telemetry()


func _pack_scale_for_slot(slot_index: int) -> float:
    if PACK_SCALE_PRESETS.is_empty():
        return -1.0
    var clamped := clampi(slot_index, 0, PACK_SCALE_PRESETS.size() - 1)
    return maxf(0.2, float(PACK_SCALE_PRESETS[clamped]))


func _on_telemetry_timer_timeout() -> void:
    _refresh_telemetry()


func _refresh_telemetry() -> void:
    telemetry_label.visible = _telemetry_enabled
    if not telemetry_label.visible:
        _refresh_settings_menu()
        _refresh_stats_menu()
        _refresh_inventory_menu()
        return

    var snapshot := AppState.get_telemetry_snapshot()
    var cozy_open_count := 0
    var heroic_open_count := 0
    var box_stats_variant = snapshot.get("box_open_stats", {})
    if typeof(box_stats_variant) == TYPE_DICTIONARY:
        var box_stats: Dictionary = box_stats_variant
        if box_stats.has("cozy") and typeof(box_stats["cozy"]) == TYPE_DICTIONARY:
            cozy_open_count = int((box_stats["cozy"] as Dictionary).get("opens", 0))
        if box_stats.has("heroic") and typeof(box_stats["heroic"]) == TYPE_DICTIONARY:
            heroic_open_count = int((box_stats["heroic"] as Dictionary).get("opens", 0))
    var prompt_metrics := _manual_verification_report.get_prompt_metrics()
    var lines: Array[String] = [
        "state: %s" % _state,
        "emote: %s -> %s" % [_active_emote_semantic, _active_face_variant],
        "face src: %s" % _last_face_texture_path,
        "level: %d  xp: %d" % [int(snapshot.get("bond_level", 1)), int(snapshot.get("bond_xp", 0))],
        "mood: %s  growth: %d  trust: %.2f" % [
            str(snapshot.get("mood", "calm")),
            int(snapshot.get("growth_stage", 1)),
            float(snapshot.get("trust_value", 0.2)),
        ],
        "meso: %d  items: %d" % [
            int(snapshot.get("meso", snapshot.get("crystals", 0))),
            int(snapshot.get("inventory_count", 0)),
        ],
        "dup recycle meso: %d" % int(snapshot.get("duplicate_recycle_total", 0)),
        "theme opens: cozy=%d heroic=%d" % [cozy_open_count, heroic_open_count],
        "pack: %s" % str(snapshot.get("active_pack", "core_pack")),
        "freq: %s  quiet: %s" % [
            str(AppState.settings.get("eventFrequency", "normal")),
            "on" if AppState.is_quiet_hours_now() else "off"
        ],
        "prompt freq: %s" % str(AppState.settings.get("promptFrequency", "normal")),
        "prompt metrics: s+%d s-%d w+%d w-%d wd%d" % [
            int(prompt_metrics.get("support_shown", 0)),
            int(prompt_metrics.get("support_suppressed", 0)),
            int(prompt_metrics.get("world_shown", 0)),
            int(prompt_metrics.get("world_suppressed", 0)),
            int(prompt_metrics.get("world_deferred", 0)),
        ],
        "chat turns: you=%d buddy=%d" % [_chat_turn_user_count, _chat_turn_buddy_count],
        "chat cmd: ok=%d fail=%d last=%s (%s)" % [
            _chat_cmd_ok_count,
            _chat_cmd_fail_count,
            _chat_last_command_id,
            _chat_last_reason_code,
        ],
        "chat cmd latency: last=%dms avg=%dms" % [
            _chat_cmd_latency_last_ms,
            int(round(float(_chat_cmd_latency_total_ms) / max(1, _chat_cmd_latency_samples))),
        ],
        "settings recent: %s" % _recent_settings_change_summary(3),
        "intensity: %s  quiet strict: %s" % [
            str(snapshot.get("interaction_intensity", "balanced")),
            str(snapshot.get("quiet_strictness", "balanced")),
        ],
        "continuity entries: %d" % int(snapshot.get("continuity_digest_count", 0)),
        "focus mins: %d  prod: %s" % [
            _productivity.focus_minutes(int(Time.get_unix_time_from_system())),
            "on" if bool(AppState.settings.get("productivityOptIn", false)) else "off"
        ],
        "screen: %d" % DisplayServer.window_get_current_screen(),
        "pack id: %s" % _active_pack_id,
        "sprite: %s" % _sprite_debug_label(),
        "ground: disabled",
        "last event: %s" % _last_event_id,
        "mode: %s  wall decor: %s" % [
            str(snapshot.get("home_mode", "overlay")),
            str(snapshot.get("home_wall_decor", "")),
        ],
        "home: %s" % str(snapshot.get("home_scene_id", "cozy_starter_room")),
        "pending quest: %s" % str(snapshot.get("pending_quest_id", "")),
        "pending encounter: %s" % str(snapshot.get("pending_encounter_id", "")),
        "world event: %s" % str(snapshot.get("last_world_event_id", "")),
        "F1 export snapshot  F2 prompt freq  F3 quiet strict  F4 intensity",
        "F5 mode  F6 telemetry",
        "F7 freq (Shift+F7 demo)  F8 monitor",
        "F9 pack  F10 settings  Shift+F10 stats  I inventory  F11 reward  F12 world",
        "Shift+F2 demo support prompt  Shift+F7 demo world prompt",
    ]
    telemetry_label.text = "\n".join(lines)
    _refresh_settings_menu()
    _refresh_stats_menu()
    _refresh_inventory_menu()
    _refresh_rebuild_menu()


func _toggle_settings_menu() -> void:
    _settings_menu_open = not _settings_menu_open
    if _settings_menu_open:
        _note_visit_interaction()
    if _settings_menu_open:
        _set_settings_menu_mode(false)
    _layout_settings_window()
    _refresh_settings_menu()


func _toggle_stats_menu() -> void:
    _stats_menu_open = not _stats_menu_open
    _layout_stats_window()
    _refresh_stats_menu()
    _refresh_settings_menu()


func _toggle_inventory_menu() -> void:
    if _is_away():
        return
    if _menu_rebuild_enabled:
        _toggle_rebuild_menu("inventory")
        return
    _inventory_menu_open = not _inventory_menu_open
    _layout_inventory_window()
    _refresh_inventory_menu()
    _refresh_settings_menu()


func _toggle_wardrobe_menu() -> void:
    if _is_away():
        return
    if _menu_rebuild_enabled:
        _toggle_rebuild_menu("wardrobe")
        return
    _wardrobe_menu_open = not _wardrobe_menu_open
    if _wardrobe_menu_open:
        _sync_wardrobe_draft_from_equipped()
        _refresh_wardrobe_menu()
        _refresh_equipped_preview_from_draft()
    else:
        _sync_wardrobe_draft_from_equipped()
        _refresh_equipped_visual_state()
    _layout_wardrobe_window()
    _refresh_settings_menu()


func _toggle_chat_window(greet: bool = true) -> void:
    _chat_window_open = not _chat_window_open
    _layout_chat_window()
    if _chat_window_open:
        _chat_unread_prompt_count = 0
        _refresh_settings_menu()
    if _chat_window_open and chat_input != null:
        chat_input.grab_focus()
    if _chat_window_open and greet:
        _maybe_greet()


func _layout_settings_window() -> void:
    var settings_layout := MAPLE_LAYOUT_SETTINGS if _settings_menu_advanced else MAPLE_LAYOUT_SETTINGS_MAIN
    settings_layout = _layout_with_skin_size(
        settings_layout,
        MAPLE_WINDOW_SKIN_SETTINGS if _settings_menu_advanced else MAPLE_WINDOW_SKIN_SETTINGS_MAIN
    )
    _layout_popup_window(settings_window, _settings_menu_open, settings_layout)


func _layout_stats_window() -> void:
    _layout_popup_window(
        stats_window,
        _stats_menu_open,
        _layout_with_skin_size(MAPLE_LAYOUT_STATS, MAPLE_WINDOW_SKIN_STATS)
    )


func _layout_inventory_window() -> void:
    _layout_popup_window(inventory_window, _inventory_menu_open, MAPLE_LAYOUT_INVENTORY)


func _layout_wardrobe_window() -> void:
    _layout_popup_window(
        wardrobe_window,
        _wardrobe_menu_open,
        _layout_with_skin_size(MAPLE_LAYOUT_WARDROBE, MAPLE_WINDOW_SKIN_WARDROBE)
    )


func _layout_chat_window() -> void:
    _layout_popup_window(
        chat_window,
        _chat_window_open,
        _layout_with_skin_size(MAPLE_LAYOUT_CHAT, MAPLE_WINDOW_SKIN_CHAT)
    )


func _layout_popup_window(target_window: Window, is_open: bool, layout_config: Dictionary) -> void:
    if target_window == null:
        return
    if not is_open:
        target_window.hide()
        return
    var main_screen := DisplayServer.window_get_current_screen()
    var usable := DisplayServer.screen_get_usable_rect(main_screen)
    var base_size: Vector2i = layout_config.get("base_size", Vector2i(420, 320))
    var min_size: Vector2i = layout_config.get("min_size", Vector2i(320, 220))
    var offset: Vector2i = layout_config.get("offset", Vector2i(72, 72))
    var max_fraction_variant = layout_config.get("max_screen_fraction", [])
    var max_fraction: Array = max_fraction_variant if typeof(max_fraction_variant) == TYPE_ARRAY else []
    var effective_min := _effective_min_size_for_screen(min_size, usable.size)
    var target_size: Vector2i = _fit_maple_window_size(base_size, min_size, usable.size, max_fraction)
    target_window.min_size = effective_min
    target_window.size = target_size
    _layout_maple_window_chrome(target_window, layout_config)

    var main_pos: Vector2i = DisplayServer.window_get_position()
    var target_pos: Vector2i = main_pos + offset
    var max_x: int = usable.position.x + maxi(0, usable.size.x - target_size.x)
    var max_y: int = usable.position.y + maxi(0, usable.size.y - target_size.y)
    target_pos.x = clampi(target_pos.x, usable.position.x, max_x)
    target_pos.y = clampi(target_pos.y, usable.position.y, max_y)
    target_window.position = target_pos
    target_window.show()
    target_window.grab_focus()


func _effective_min_size_for_screen(min_size: Vector2i, usable_size: Vector2i) -> Vector2i:
    var screen_margin := 24
    var avail_w := maxi(220, usable_size.x - (screen_margin * 2))
    var avail_h := maxi(180, usable_size.y - (screen_margin * 2))
    return Vector2i(
        clampi(min_size.x, 120, avail_w),
        clampi(min_size.y, 120, avail_h)
    )


func _fit_maple_window_size(base_size: Vector2i, min_size: Vector2i, usable_size: Vector2i, max_screen_fraction: Array = []) -> Vector2i:
    var screen_margin := 24
    var avail_w := maxi(220, usable_size.x - (screen_margin * 2))
    var avail_h := maxi(180, usable_size.y - (screen_margin * 2))
    if max_screen_fraction.size() >= 2:
        var width_frac := clampf(float(max_screen_fraction[0]), 0.20, 1.0)
        var height_frac := clampf(float(max_screen_fraction[1]), 0.20, 1.0)
        avail_w = maxi(220, int(floor(float(usable_size.x) * width_frac)))
        avail_h = maxi(180, int(floor(float(usable_size.y) * height_frac)))
    var effective_min := Vector2i(
        clampi(min_size.x, 120, avail_w),
        clampi(min_size.y, 120, avail_h)
    )
    var max_w := avail_w
    var max_h := avail_h
    var scale_w := float(avail_w) / float(maxi(1, base_size.x))
    var scale_h := float(avail_h) / float(maxi(1, base_size.y))
    var scale := minf(1.0, minf(scale_w, scale_h))
    var out := Vector2i(
        clampi(int(round(float(base_size.x) * scale)), effective_min.x, max_w),
        clampi(int(round(float(base_size.y) * scale)), effective_min.y, max_h)
    )
    return out


func _refresh_wardrobe_menu() -> void:
    if wardrobe_window == null or wardrobe_preview == null:
        return
    var snapshot := AppState.get_inventory_snapshot()
    var inventory_variant = snapshot.get("inventory", [])
    var inventory: Array = inventory_variant if typeof(inventory_variant) == TYPE_ARRAY else []
    _wardrobe_rows_cache.clear()
    _wardrobe_visible_instance_ids.clear()
    if _wardrobe_slot_grid != null:
        for child in _wardrobe_slot_grid.get_children():
            child.queue_free()
    _wardrobe_slot_buttons_by_instance.clear()

    for row_variant in inventory:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if not _is_item_equippable(row):
            continue
        _wardrobe_rows_cache.append(row.duplicate(true))
    _wardrobe_rows_cache.sort_custom(func(a: Variant, b: Variant) -> bool:
        var da: Dictionary = a
        var db: Dictionary = b
        var sa := _normalize_inventory_slot_name(str(da.get("equipSlot", "")))
        var sb := _normalize_inventory_slot_name(str(db.get("equipSlot", "")))
        if sa != sb:
            return sa < sb
        return str(da.get("name", da.get("id", ""))).to_lower() < str(db.get("name", db.get("id", ""))).to_lower()
    )

    for row_variant in _wardrobe_rows_cache:
        var row: Dictionary = row_variant
        var instance_id := int(row.get("instance_id", -1))
        if instance_id <= 0:
            continue
        var slot := _normalize_inventory_slot_name(str(row.get("equipSlot", "")))
        var draft_instance := int(_wardrobe_draft_slots.get(slot, -1))
        _wardrobe_visible_instance_ids.append(instance_id)
        var icon_tex := _resolve_item_overlay_texture(row)
        if _wardrobe_slot_grid != null:
            var btn := TextureButton.new()
            btn.ignore_texture_size = false
            btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
            btn.custom_minimum_size = Vector2(36, 36)
            btn.texture_normal = icon_tex
            btn.texture_hover = icon_tex
            btn.texture_pressed = icon_tex
            btn.tooltip_text = "%s\nSlot: %s%s" % [
                str(row.get("name", row.get("id", "Item"))),
                _display_inventory_slot(slot),
                " | DRAFT" if draft_instance == instance_id else "",
            ]
            btn.pressed.connect(func() -> void:
                _wardrobe_selected_instance_id = instance_id
                _refresh_wardrobe_menu()
            )
            btn.gui_input.connect(func(event: InputEvent) -> void:
                if event is InputEventMouseButton:
                    var mb := event as InputEventMouseButton
                    if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and mb.pressed:
                        _wardrobe_selected_instance_id = instance_id
                        _toggle_selected_wardrobe_draft_slot()
            )
            _wardrobe_slot_grid.add_child(btn)
            _wardrobe_slot_buttons_by_instance[instance_id] = btn

    if _wardrobe_visible_instance_ids.is_empty():
        _wardrobe_selected_instance_id = -1
    elif _wardrobe_selected_instance_id <= 0 or not _wardrobe_visible_instance_ids.has(_wardrobe_selected_instance_id):
        _wardrobe_selected_instance_id = int(_wardrobe_visible_instance_ids[0])
    for instance_key in _wardrobe_slot_buttons_by_instance.keys():
        var id := int(instance_key)
        var button := _wardrobe_slot_buttons_by_instance[instance_key] as TextureButton
        if button == null:
            continue
        var row := _wardrobe_item_by_instance(id)
        var slot := _normalize_inventory_slot_name(str(row.get("equipSlot", ""))) if not row.is_empty() else ""
        var is_draft := int(_wardrobe_draft_slots.get(slot, -1)) == id
        if id == _wardrobe_selected_instance_id:
            button.self_modulate = Color(1.0, 0.92, 0.72, 1.0)
        elif is_draft:
            button.self_modulate = Color(0.85, 1.0, 0.85, 1.0)
        else:
            button.self_modulate = Color(1.0, 1.0, 1.0, 1.0)

    wardrobe_header.bbcode_enabled = true
    wardrobe_header.text = "[b][color=#FFD77A]Wardrobe[/color][/b]  [color=#E7D9B4]%d equip items[/color]\n[color=#A7B8C8]W toggle draft | Equip Draft commits all slots[/color]" % [
        _wardrobe_visible_instance_ids.size()
    ]
    _refresh_wardrobe_preview_text()


func _refresh_wardrobe_preview_text() -> void:
    if wardrobe_preview == null:
        return
    var selected := _wardrobe_item_by_instance(_wardrobe_selected_instance_id)
    var text := "[b][color=#FFD77A]Draft Slots[/color][/b]\n"
    if _wardrobe_draft_slots.is_empty():
        text += "[color=#E7D9B4](empty)[/color]\n"
    else:
        var keys: Array = _wardrobe_draft_slots.keys()
        keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
        for slot_variant in keys:
            var slot := str(slot_variant)
            var instance_id := int(_wardrobe_draft_slots.get(slot_variant, -1))
            var row := _wardrobe_item_by_instance(instance_id)
            var name := "(missing)"
            if not row.is_empty():
                name = str(row.get("name", row.get("id", "item")))
            text += "[color=#F4E9CF]%s:[/color] %s\n" % [_display_inventory_slot(slot), name]
    if not selected.is_empty():
        var selected_slot := _normalize_inventory_slot_name(str(selected.get("equipSlot", "")))
        text += "\n[b][color=#FFD77A]Selected[/color][/b]\n"
        text += "[color=#F4E9CF]Name:[/color] %s\n" % str(selected.get("name", selected.get("id", "item")))
        text += "[color=#F4E9CF]Slot:[/color] %s\n" % _display_inventory_slot(selected_slot)
        text += "[color=#F4E9CF]Rarity:[/color] %s\n" % str(selected.get("rarity", "common"))
    wardrobe_preview.bbcode_enabled = true
    wardrobe_preview.text = text


func _sync_wardrobe_draft_from_equipped() -> void:
    var snapshot := AppState.get_inventory_snapshot()
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    _wardrobe_draft_slots.clear()
    for slot_variant in equipped_slots.keys():
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        var instance_id := int(equipped_slots.get(slot_variant, -1))
        if slot != "" and instance_id > 0:
            _wardrobe_draft_slots[slot] = instance_id


func _wardrobe_item_by_instance(instance_id: int) -> Dictionary:
    if instance_id <= 0:
        return {}
    for row_variant in _wardrobe_rows_cache:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if int(row.get("instance_id", -1)) == instance_id:
            return row
    var inv: Array = AppState.get_inventory_snapshot().get("inventory", [])
    if typeof(inv) == TYPE_ARRAY:
        for row_variant in inv:
            if typeof(row_variant) != TYPE_DICTIONARY:
                continue
            var row: Dictionary = row_variant
            if int(row.get("instance_id", -1)) == instance_id:
                return row
    return {}


func _toggle_selected_wardrobe_draft_slot() -> void:
    var row := _wardrobe_item_by_instance(_wardrobe_selected_instance_id)
    if row.is_empty():
        _buddy_say("Select an equippable item first.")
        return
    var slot := _normalize_inventory_slot_name(str(row.get("equipSlot", "")))
    if slot == "":
        _buddy_say("Selected item has no equip slot.")
        return
    var instance_id := int(row.get("instance_id", -1))
    if int(_wardrobe_draft_slots.get(slot, -1)) == instance_id:
        _wardrobe_draft_slots.erase(slot)
        _buddy_say("Draft slot cleared: %s." % _display_inventory_slot(slot))
    else:
        _wardrobe_draft_slots[slot] = instance_id
        _buddy_say("Draft set: %s -> %s." % [_display_inventory_slot(slot), str(row.get("name", row.get("id", "item")))])
    _refresh_wardrobe_menu()
    _refresh_equipped_preview_from_draft()


func _clear_selected_wardrobe_slot() -> void:
    var row := _wardrobe_item_by_instance(_wardrobe_selected_instance_id)
    if row.is_empty():
        _buddy_say("Select an item first.")
        return
    var slot := _normalize_inventory_slot_name(str(row.get("equipSlot", "")))
    if slot == "":
        _buddy_say("Selected item has no equip slot.")
        return
    _wardrobe_draft_slots.erase(slot)
    _refresh_wardrobe_menu()
    _refresh_equipped_preview_from_draft()
    _buddy_say("Draft slot cleared: %s." % _display_inventory_slot(slot))


func _equip_wardrobe_draft() -> void:
    if _wardrobe_draft_slots.is_empty():
        _buddy_say("Wardrobe draft is empty.")
        return
    var snapshot := AppState.get_inventory_snapshot()
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    var touched_slots: Array = _wardrobe_draft_slots.keys()
    touched_slots.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
    for slot_variant in touched_slots:
        var slot := str(slot_variant)
        if int(equipped_slots.get(slot, -1)) > 0:
            AppState.unequip_inventory_slot(slot)
    for slot_variant in touched_slots:
        var slot := str(slot_variant)
        var instance_id := int(_wardrobe_draft_slots.get(slot_variant, -1))
        if instance_id <= 0:
            continue
        var result := AppState.equip_inventory_item(instance_id)
        if not bool(result.get("ok", false)):
            _buddy_say("Equip failed for %s (%s)." % [_display_inventory_slot(slot), str(result.get("reason", "unknown"))])
    _refresh_equipped_visual_state()
    _refresh_assembled_state_overrides("equip_commit")
    _sync_wardrobe_draft_from_equipped()
    _refresh_wardrobe_menu()
    _refresh_inventory_menu()
    _refresh_settings_menu()
    _buddy_say("Wardrobe equipped. Rendering confirmed look...")


func _refresh_equipped_preview_from_draft() -> void:
    if not _wardrobe_menu_open:
        return
    var next_equipped := {}
    for slot_variant in _wardrobe_draft_slots.keys():
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        var instance_id := int(_wardrobe_draft_slots.get(slot_variant, -1))
        var row := _wardrobe_item_by_instance(instance_id)
        if slot == "" or row.is_empty():
            continue
        var clone := row.duplicate(true)
        if str(clone.get("equipSlot", "")).strip_edges() == "":
            clone["equipSlot"] = slot
        next_equipped[slot] = clone
    _equipped_visual_items = next_equipped
    _refresh_assembled_state_overrides("wardrobe_preview")
    queue_redraw()


func _refresh_settings_menu() -> void:
    if settings_label == null:
        return

    var snapshot := AppState.get_telemetry_snapshot()
    var prompt_metrics := _manual_verification_report.get_prompt_metrics()
    var lock_remaining := maxi(0, _manual_emote_until_unix - int(Time.get_unix_time_from_system()))

    var now_unix := int(Time.get_unix_time_from_system())
    var dnd_line := "off"
    if _is_dnd_active(now_unix):
        dnd_line = "on, %d min left" % _dnd_minutes_remaining(now_unix)
    var text := ""
    text += "[color=#F4E9CF]Mood:[/color] %s   [color=#F4E9CF]Bond:[/color] level %d   [color=#F4E9CF]Doing:[/color] %s\n" % [
        str(snapshot.get("mood", "calm")), int(snapshot.get("bond_level", 1)), _state
    ]
    text += "[color=#F4E9CF]Quiet hours:[/color] %s   [color=#F4E9CF]Do not disturb:[/color] %s\n" % [
        "now" if AppState.is_quiet_hours_now() else "not now", dnd_line
    ]
    text += "[color=#F4E9CF]Thinking model:[/color] %s" % _mind_model_summary()
    if _settings_debug_box != null and _settings_debug_box.visible:
        text += "\n\n[color=#9AA3B5]Pack %s / economy %s, catalogue %d, inventory %d (+%d quarantined). " % [
            str(snapshot.get("visual_pack_id", snapshot.get("active_pack", "core_pack"))),
            str(snapshot.get("economy_pack_id", "core_pack")),
            int(snapshot.get("catalog_size", 0)),
            int(snapshot.get("inventory_count", 0)),
            int(snapshot.get("inventory_quarantine_count", 0)),
        ]
        text += "Cadence %s. Prompts s+%d s-%d w+%d w-%d wd%d. Emote lock %ds. " % [
            _build_cadence_hint_compact(),
            int(prompt_metrics.get("support_shown", 0)),
            int(prompt_metrics.get("support_suppressed", 0)),
            int(prompt_metrics.get("world_shown", 0)),
            int(prompt_metrics.get("world_suppressed", 0)),
            int(prompt_metrics.get("world_deferred", 0)),
            lock_remaining,
        ]
        text += "Hotkeys: F2 prompts, F3 quiet, F4 intensity, F5 home, F6 telemetry, F7 events, F8 monitor, F9 pack, F11 reward, F12 world, 1-0 emotes.[/color]"
    settings_label.bbcode_enabled = true
    settings_label.fit_content = true
    settings_label.scroll_active = false
    settings_label.custom_minimum_size = Vector2(460, 0)
    settings_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    settings_label.text = text

    settings_btn_pause.text = "Resume Buddy" if _state == "sleep" else "Pause Buddy"
    if _main_menu_btn_pause != null:
        _main_menu_btn_pause.text = "Wake up" if _state == "sleep" else "Pause"
    if _main_menu_status != null:
        var status_text: String = "%s, bond level %d.\nDouble-click your buddy to open this menu." % [
            str(snapshot.get("mood", "calm")).capitalize(), int(snapshot.get("bond_level", 1))
        ]
        status_text = "%s\n%s" % [_where_is_it_now_line(), status_text]
        _main_menu_status.text = status_text
    if _main_menu_btn_chat != null:
        _main_menu_btn_chat.text = "Chat (%d new)" % _chat_unread_prompt_count if _chat_unread_prompt_count > 0 else "Chat"
    if _main_menu_btn_stats != null:
        var spare_points := int(snapshot.get("stat_points_unspent", 0))
        _main_menu_btn_stats.text = "Stats (%d points to spend)" % spare_points if spare_points > 0 else "Stats"
    if _settings_btn_autonomy != null:
        _settings_btn_autonomy.text = "Acts on its own: %s" % ("on" if bool(AppState.settings.get("autonomyEnabled", true)) else "off")
    if _settings_btn_world_host != null:
        _settings_btn_world_host.text = "World host: %s" % ("on" if bool(AppState.settings.get("worldHost", false)) else "off")
    _refresh_visit_menu()
    if _settings_btn_model != null:
        _settings_btn_model.text = "Thinking model: %s" % ("on" if bool(AppState.settings.get("mindModelEnabled", true)) else "off")
    if _settings_btn_chat_model != null:
        _settings_btn_chat_model.text = "Talks back: %s" % ("on" if bool(AppState.settings.get("chatModelEnabled", true)) else "off")
    if _settings_btn_memory != null:
        _settings_btn_memory.text = "Remembers you: %s" % ("on" if AppState.memory_enabled() else "off")
    if _settings_btn_debug_toggle != null and _settings_debug_box != null:
        _settings_btn_debug_toggle.text = "Hide developer tools" if _settings_debug_box.visible else "Show developer tools"
    settings_btn_event_freq.text = "World events: %s" % str(AppState.settings.get("eventFrequency", "normal"))
    settings_btn_prompt_freq.text = "Check-ins: %s" % str(AppState.settings.get("promptFrequency", "normal"))
    settings_btn_quiet.text = "Quiet hours: %s" % str(AppState.settings.get("quietModeStrictness", "balanced"))
    var dnd_remaining := _dnd_minutes_remaining()
    if _is_dnd_active():
        settings_btn_dnd_15.text = "15 min (%d left)" % dnd_remaining
        settings_btn_dnd_30.text = "30 min (%d left)" % dnd_remaining
        settings_btn_dnd_off.text = "Turn off"
    else:
        settings_btn_dnd_15.text = "15 minutes"
        settings_btn_dnd_30.text = "30 minutes"
        settings_btn_dnd_off.text = "Off"
    settings_btn_dnd_off.disabled = not _is_dnd_active()
    settings_btn_intensity.text = "Energy: %s" % str(AppState.settings.get("interactionIntensity", "balanced"))
    settings_btn_mode.text = "Lives in: %s" % str(snapshot.get("home_mode", "overlay"))
    settings_btn_pack.text = "Character pack: %s" % str(snapshot.get("visual_pack_id", snapshot.get("active_pack", "core_pack")))
    settings_btn_demo_support.text = "Demo check-in"
    settings_btn_demo_world.text = "Demo world event"
    settings_btn_reward.text = "Open reward box"
    settings_btn_seed_inventory.text = "Add test items"
    settings_btn_repair_inventory.text = "Repair inventory (%d)" % int(snapshot.get("inventory_quarantine_count", 0))
    settings_btn_clear_inventory.text = "Clear inventory"
    settings_btn_telemetry.text = "Telemetry: %s" % ("on" if _telemetry_enabled else "off")
    settings_btn_restart.text = "Restart Buddy"
    settings_btn_quit.text = "Quit Runtime"
    var unread_suffix := ""
    if _chat_unread_prompt_count > 0:
        unread_suffix = " (%d new)" % _chat_unread_prompt_count
    var dnd_suffix := ""
    if _is_dnd_active():
        dnd_suffix = " | DND %dm" % _dnd_minutes_remaining()
    settings_btn_chat.text = "Chat: %s%s%s" % [("Open" if _chat_window_open else "Closed"), unread_suffix, dnd_suffix]
    settings_btn_stats.text = "Stats (Shift+F10): %s pts" % int(snapshot.get("stat_points_unspent", 0))
    settings_btn_inventory.text = "Inventory (I): %d items" % int(snapshot.get("inventory_count", 0))
    settings_btn_wardrobe.text = "Wardrobe (W): %s" % ("Open" if _wardrobe_menu_open else "Closed")
    if settings_floor_slider != null:
        settings_floor_slider.set_value_no_signal(_desktop_floor_offset_adjust)
    if settings_floor_value != null:
        settings_floor_value.text = _format_floor_adjust_text(_desktop_floor_offset_adjust)


func _read_floor_offset_adjust_setting() -> float:
    var raw = AppState.settings.get("desktopFloorOffsetAdjust", 0.0)
    return clampf(float(raw), -20.0, 20.0)


func _set_floor_offset_adjust(raw_value: float) -> void:
    var next_value := clampf(roundf(raw_value), -20.0, 20.0)
    if is_equal_approx(next_value, _desktop_floor_offset_adjust):
        return
    _desktop_floor_offset_adjust = next_value
    AppState.settings["desktopFloorOffsetAdjust"] = _desktop_floor_offset_adjust
    AppState.flush()
    _draw_center = _floor_point()
    _update_balloon_position()
    queue_redraw()
    if settings_floor_value != null:
        settings_floor_value.text = _format_floor_adjust_text(_desktop_floor_offset_adjust)
    _refresh_telemetry()


func _format_floor_adjust_text(value: float) -> String:
    var rounded := int(roundf(value))
    var sign := "+" if rounded >= 0 else ""
    return "%s%d px" % [sign, rounded]


func _buddy_say(line: String, source_kind: String = "") -> void:
    if line == "":
        return
    # Unprompted lines (check-ins, world prompts, idle remarks) are dropped if
    # they were said recently. Replies to the user are always said as they are.
    if source_kind in ["support", "world", "idle"] and _was_said_recently(line):
        return
    _remember_buddy_line(line)
    _chat_turn_buddy_count += 1
    if not _chat_window_open and (source_kind == "support" or source_kind == "world"):
        _chat_unread_prompt_count += 1
        _refresh_settings_menu()
    _update_balloon_position()
    chat_balloon.show_text(line)
    _append_chat_line(_speaker_name(), line, "#F4E9CF")


func _remember_buddy_line(line: String) -> void:
    var normalized := _normalize_for_repeat(line)
    if normalized == "":
        return
    _chat_recent_buddy_norm_lines.append(normalized)
    if _chat_recent_buddy_norm_lines.size() > CHAT_RECENT_REPLY_MAX:
        _chat_recent_buddy_norm_lines.remove_at(0)


func _was_said_recently(line: String) -> bool:
    var normalized := _normalize_for_repeat(line)
    return normalized != "" and _chat_recent_buddy_norm_lines.has(normalized)


func _speaker_name() -> String:
    var buddy_name: String = _buddy_name()
    return buddy_name if buddy_name != "" else "Buddy"


func _chat_window_title() -> String:
    var buddy_name: String = _buddy_name()
    return "Chat with %s" % buddy_name if buddy_name != "" else "Buddy Chat"


func _append_chat_line(speaker: String, text: String, color_hex: String) -> void:
    if chat_log == null:
        return
    var now_unix := int(Time.get_unix_time_from_system())
    if _chat_last_line_unix > 0 and now_unix - _chat_last_line_unix >= CHAT_SEPARATOR_IDLE_SECONDS:
        chat_log.append_text("[color=#6A7D8F]---------- session pause ----------[/color]\n")
    _chat_last_line_unix = now_unix
    var safe_speaker := speaker.replace("[", "").replace("]", "")
    var safe_text := text.replace("[", "\\[").replace("]", "\\]")
    var row := "[color=%s][b]%s:[/b][/color] %s\n" % [color_hex, safe_speaker, safe_text]
    chat_log.append_text(row)
    var line_count := chat_log.get_line_count()
    if line_count > CHAT_TRANSCRIPT_MAX_LINES:
        var full_text := chat_log.text
        var parts := full_text.split("\n")
        var keep_from: int = maxi(0, parts.size() - CHAT_TRANSCRIPT_MAX_LINES)
        var trimmed := "\n".join(parts.slice(keep_from, parts.size()))
        chat_log.text = trimmed
    chat_log.scroll_to_line(chat_log.get_line_count())


func _send_chat_input() -> void:
    if chat_input == null:
        return
    var raw := chat_input.text.strip_edges()
    if raw == "":
        return
    chat_input.text = ""
    _chat_turn_user_count += 1
    _append_chat_line("You", raw, "#9FD9FF")
    _note_visit_interaction()
    if _is_away():
        # At home it is the host's buddy: nothing here may reach the model or the memory.
        _append_chat_line(_away_name(), "%s is at home. Use Call over to bring it here." % _away_name(), "#F4E9CF")
        return
    AppState.record_interaction("chat_reply")
    _productivity.note_user_activity(int(Time.get_unix_time_from_system()))

    var started_ms := Time.get_ticks_msec()
    var resolved := _chat_router.resolve(raw)
    var outcome := _execute_resolved_chat(raw, resolved)
    outcome["elapsed_ms"] = Time.get_ticks_msec() - started_ms
    _record_chat_command_outcome(outcome)
    var reply := str(outcome.get("message", ""))
    if reply != "":
        _buddy_say(reply)
    _refresh_telemetry()


func _generate_chat_reply(user_text: String) -> String:
    var msg := user_text.to_lower()
    var snap := AppState.get_telemetry_snapshot()
    var mood := str(snap.get("mood", "calm"))
    var bond_level := int(snap.get("bond_level", 1))
    var world := AppState.get_world_snapshot()
    var tone := _tone_prefix(mood, bond_level)

    if msg.find("hello") >= 0 or msg.find("hi") >= 0 or msg.find("hey") >= 0:
        return "%sHey. I am here with you." % tone
    if msg.find("help") >= 0:
        return "%sI can do quick things: rewards (F11), world prompts (F12), and mode toggle (F5)." % tone
    if msg.find("quest") >= 0 or msg.find("world") >= 0:
        var pending_q := str(world.get("pending_quest_id", ""))
        var pending_e := str(world.get("pending_encounter_id", ""))
        if pending_q != "" or pending_e != "":
            return "%sWe have something pending. Press F12 and we can resolve it." % tone
        return "%sNo pending quest right now. I can ping one when events roll." % tone
    if msg.find("reward") >= 0 or msg.find("box") >= 0:
        return "%sOpen a reward box with F11 and I will call out what we get." % tone
    if msg.find("sleep") >= 0 or msg.find("tired") >= 0:
        return "%sIf you want quiet mode, right-click me to sleep and I will keep calm." % tone
    if msg.find("mode") >= 0 or msg.find("home") >= 0 or msg.find("overlay") >= 0:
        var home_mode := str(world.get("home_mode", "overlay"))
        return "%sCurrent mode is %s. Press F5 to switch." % [tone, home_mode]
    if msg.find("thanks") >= 0 or msg.find("thank you") >= 0:
        var max_level := UnlockTable.max_level()
        if bond_level >= max_level:
            return "%sAlways. Bond level is %d (max)." % [tone, bond_level]
        return "%sAlways. Bond level is %d and climbing." % [tone, bond_level]
    if _should_ask_follow_up(msg):
        _chat_last_followup_turn = _chat_turn_user_count
        return "%sCan you tell me a bit more so I can help better?" % tone

    if mood == "sleepy":
        return "%sI am a bit sleepy, but I am still listening." % tone
    if mood == "curious":
        return "%sTell me more. I am curious." % tone
    if mood == "happy":
        return "%sNice. I like chatting with you." % tone
    return "%sGot it. Want to do rewards, quests, or just hang out?" % tone


func _execute_resolved_chat(raw_text: String, resolved: Dictionary) -> Dictionary:
    var ok := bool(resolved.get("ok", false))
    var kind := str(resolved.get("kind", "unknown"))
    var action_id := str(resolved.get("action_id", ""))
    var params_variant = resolved.get("params", {})
    var params: Dictionary = params_variant if typeof(params_variant) == TYPE_DICTIONARY else {}
    var reason := str(resolved.get("reason_code", "unknown"))
    var confidence := float(resolved.get("confidence", 0.0))

    if kind == "command":
        if not ok:
            return _action_result(
                false,
                "command.%s" % action_id,
                "I could not run that command (%s). Use /help." % reason,
                reason
            )
        if confidence < 0.60:
            return _action_result(false, "command.%s" % action_id, "I am not confident enough to run that command.", "low_confidence")
        var throttle := _throttle_command(action_id)
        if not bool(throttle.get("ok", false)):
            return throttle
        return _execute_chat_command(action_id, params)

    if kind == "intent" and ok:
        # A word or three ("hi", "thanks", "tired?") gets the instant built-in
        # reply. A whole sentence that happens to contain one of those words
        # ("I got home late", "I'm tired after work") is conversation, and is
        # what the buddy needs to hear to remember anything about you.
        if raw_text.strip_edges().split(" ", false).size() > 3:
            _ensure_chat_http()
            if _start_chat_request(raw_text):
                return _action_result(true, "chat.pending", "", "ok")
        return _action_result(true, "intent.%s" % action_id, _generate_chat_reply(raw_text), "ok")

    _ensure_chat_http()
    if _start_chat_request(raw_text):
        return _action_result(true, "chat.pending", "", "ok")
    if not _chat_pending.is_empty():
        if str(_chat_pending.get("kind", "")) == "memory":
            return _action_result(true, "chat.busy", "One moment, I'm just tucking our last chat away. Say that again?", "ok")
        return _action_result(true, "chat.busy", "One moment, I'm still thinking.", "ok")
    return _action_result(false, "intent.unknown", "I did not catch that. Try /help.", "unknown_intent")


func _execute_chat_command(command: String, params: Dictionary) -> Dictionary:
    if command == "help":
        return _action_result(
            true,
            "command.help",
            "Commands: /help /status /pending /mode home|overlay /reward /world engage|skip|complete /quiet lenient|balanced|strict /freq low|normal|high /dnd <minutes|off> /chat close|clear [confirm]|text m|l /memory /journal /wants /remember <note> /forget <id> [confirm] /snapshot /cadence /debug chat /settings-check /preset cozy|balanced|deep|idle /settings reset [confirm]|undo",
            "ok"
        )
    if command == "status":
        var snap := AppState.get_telemetry_snapshot()
        var world := AppState.get_world_snapshot()
        var bond_level := int(snap.get("bond_level", 1))
        var bond_xp := int(snap.get("bond_xp", 0))
        var max_level := UnlockTable.max_level()
        var xp_segment := _xp_segment_for_level(bond_xp, bond_level, max_level)
        var next_unlock := _next_unlock_hint(bond_level)
        var job_name := str(snap.get("job_name", "Explorer Buddy"))
        var msg := "Status: Lv %d%s %s Mood %s Mode %s Meso %d" % [
            bond_level,
            " (MAX)" if bond_level >= max_level else "",
            xp_segment,
            str(snap.get("mood", "calm")),
            str(world.get("home_mode", "overlay")),
            int(snap.get("meso", snap.get("crystals", 0))),
        ]
        msg += " Job %s" % job_name
        if next_unlock != "":
            msg += " | next %s" % next_unlock
        else:
            msg += " | unlocks maxed"
        var now_unix := int(Time.get_unix_time_from_system())
        if _is_dnd_active(now_unix):
            msg += " | DND %dm" % _dnd_minutes_remaining(now_unix)
        else:
            msg += " | DND off"
        var recent := _recent_settings_change_summary(5)
        if recent != "":
            msg += " | settings: %s" % recent
        return _action_result(true, "command.status", msg, "ok")
    if command == "pending":
        var world_pending := AppState.get_world_snapshot()
        var q := str(world_pending.get("pending_quest_id", ""))
        var e := str(world_pending.get("pending_encounter_id", ""))
        if q == "" and e == "":
            return _action_result(true, "command.pending", "No pending quest or encounter. Suggestion: /reward", "ok")
        var suggestion := "/world complete"
        if e != "":
            suggestion = "/world engage (or /world skip)"
        return _action_result(
            true,
            "command.pending",
            "Pending: quest=%s encounter=%s | suggestion: %s" % [q, e, suggestion],
            "ok"
        )
    if command == "mode":
        var mode := str(params.get("mode", "overlay"))
        _set_home_mode_explicit(mode)
        return _action_result(true, "command.mode", "Mode set to %s." % mode, "ok")
    if command == "reward":
        _open_debug_reward_box()
        return _action_result(true, "command.reward", "", "ok")
    if command == "world":
        var decision := str(params.get("decision", "complete"))
        if decision == "skip":
            _resolve_world_prompt(false)
        else:
            _resolve_world_prompt(true)
        return _action_result(true, "command.world", "", "ok")
    if command == "quiet":
        var level := str(params.get("level", "balanced"))
        _set_setting_with_audit("quietModeStrictness", level, "command")
        AppState.flush()
        _emit_setting_feedback("quietModeStrictness", level)
        return _action_result(true, "command.quiet", "Quiet strictness set to %s." % level, "ok")
    if command == "freq":
        var value := str(params.get("value", "normal"))
        _set_setting_with_audit("promptFrequency", value, "command")
        _set_setting_with_audit("eventFrequency", value, "command")
        AppState.flush()
        _emit_setting_feedback("freq", value)
        return _action_result(true, "command.freq", "Prompt/Event frequency set to %s." % value, "ok")
    if command == "dnd":
        if bool(params.get("off", false)):
            _set_dnd_off()
            return _action_result(true, "command.dnd", "DND disabled.", "ok")
        var minutes := int(params.get("minutes", 0))
        if minutes <= 0:
            return _action_result(false, "command.dnd", "Use /dnd <1-240|off>", "invalid_arg")
        _set_dnd_minutes(minutes)
        return _action_result(true, "command.dnd", "DND enabled for %d minutes." % minutes, "ok")
    if command == "chat":
        var action := str(params.get("action", ""))
        if action == "close":
            _chat_window_open = false
            _layout_chat_window()
            return _action_result(true, "command.chat", "Chat window closed.", "ok")
        if action == "clear":
            var confirm := bool(params.get("confirm", false))
            if not confirm:
                return _action_result(false, "command.chat", "Confirm with /chat clear confirm", "confirm_required")
            if chat_log != null:
                chat_log.clear()
            return _action_result(true, "command.chat", "Chat transcript cleared.", "ok")
        if action == "text":
            var size := str(params.get("size", "m"))
            _set_setting_with_audit("chatTextSize", size, "command")
            AppState.flush()
            _apply_chat_text_size()
            return _action_result(true, "command.chat", "Chat text size set to %s." % size.to_upper(), "ok")
        return _action_result(false, "command.chat", "Unknown chat action.", "invalid_arg")
    if command == "memory":
        return _action_result(true, "command.memory", _build_memory_summary(), "ok")
    if command == "journal":
        return _action_result(true, "command.journal", _build_journal_summary(), "ok")
    if command == "wants":
        return _action_result(true, "command.wants", _build_wants_summary(), "ok")
    if command == "remember":
        var note := str(params.get("note", "")).strip_edges()
        if note == "":
            return _action_result(false, "command.remember", "Missing note text. Use /remember <note>", "missing_arg")
        return _remember_note(note)
    if command == "forget":
        var note_id := int(params.get("id", -1))
        var confirm := bool(params.get("confirm", false))
        return _forget_note(note_id, confirm)
    if command == "cadence":
        return _action_result(true, "command.cadence", _build_cadence_summary(), "ok")
    if command == "snapshot":
        var export_result := _export_manual_verification_snapshot(false)
        if bool(export_result.get("ok", false)):
            return _action_result(
                true,
                "command.snapshot",
                "Manual snapshot exported: %s" % str(export_result.get("path", "")),
                "ok"
            )
        return _action_result(
            false,
            "command.snapshot",
            "Snapshot export failed (%s)." % str(export_result.get("reason", "unknown")),
            "export_failed"
        )
    if command == "debug":
        var area := str(params.get("area", ""))
        if area == "chat":
            return _action_result(true, "command.debug", _build_chat_debug_summary(), "ok")
        return _action_result(false, "command.debug", "Unknown debug area.", "invalid_arg")
    if command == "settings-check":
        return _action_result(true, "command.settings-check", _run_settings_check(), "ok")
    if command == "preset":
        var preset := str(params.get("preset", "balanced"))
        return _apply_settings_preset(preset)
    if command == "settings":
        var settings_action := str(params.get("action", ""))
        if settings_action == "reset":
            var confirm := bool(params.get("confirm", false))
            return _reset_settings_with_undo(confirm)
        if settings_action == "undo":
            return _undo_settings_reset()
        return _action_result(false, "command.settings", "Unknown settings action.", "invalid_arg")

    return _action_result(false, "command.%s" % command, "Unsupported command.", "unsupported_command")


func _tone_prefix(mood: String, bond_level: int) -> String:
    var bond_band := 0
    if bond_level >= 12:
        bond_band = 2
    elif bond_level >= 6:
        bond_band = 1
    if mood == "sleepy":
        return ["", "Hey... ", "Hey friend, "][bond_band]
    if mood == "happy":
        return ["", "Nice! ", "Nice! I am glad you are here. "][bond_band]
    if mood == "curious":
        return ["", "Hmm. ", "Hmm, tell me more. "][bond_band]
    if mood == "frustrated":
        return ["", "Okay. ", "Okay, we can handle this. "][bond_band]
    if mood == "focused":
        return ["", "On it. ", "On it, teammate. "][bond_band]
    if mood == "worried":
        return ["", "Got it. ", "Got it, we can take this one step at a time. "][bond_band]
    if mood == "excited":
        return ["", "Great! ", "Great! Let us keep that momentum. "][bond_band]
    if mood == "proud":
        return ["", "Solid. ", "Solid work. I am proud of this pace. "][bond_band]
    if mood == "calm":
        return ["", "Alright. ", "Alright, teammate. "][bond_band]
    return ""


func _should_ask_follow_up(msg: String) -> bool:
    var compact := msg.strip_edges()
    if compact == "":
        return false
    if compact.begins_with("/"):
        return false
    if _is_dnd_active():
        return false
    if _chat_turn_user_count - _chat_last_followup_turn < CHAT_FOLLOW_UP_MIN_TURNS:
        return false
    var noisy_keywords := [
        "reward",
        "world",
        "quest",
        "mode",
        "help",
        "quiet",
        "freq",
        "sleep",
        "tired",
    ]
    for key in noisy_keywords:
        if compact.find(key) >= 0:
            return false
    var words := compact.split(" ", false)
    return words.size() <= 3


func _normalize_for_repeat(text: String) -> String:
    var normalized := text.strip_edges().to_lower()
    var punctuation := [".", ",", "!", "?", ":", ";", "(", ")", "[", "]"]
    for token in punctuation:
        normalized = normalized.replace(token, "")
    return normalized


func _build_memory_summary() -> String:
    var rows: Array = AppState.memory_list()
    var enabled := AppState.memory_enabled()
    if rows.is_empty():
        if not enabled:
            return "I'm not keeping memories right now (Settings: Remembers you)."
        return "I don't remember anything about you yet. Tell me about yourself, or use /remember <note>."
    var parts: Array = []
    for row_variant in rows:
        if parts.size() >= 6:
            break
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        parts.append("#%d %s" % [int(row.get("id", 0)), str(row.get("text", ""))])
    var more := ""
    if rows.size() > parts.size():
        more = " (+%d more)" % (rows.size() - parts.size())
    var off_note := "" if enabled else " Remembering is off, so nothing new is kept."
    return "I remember %d things: %s%s. Menu > Memory shows them all; /forget <id> removes one.%s" % [
        rows.size(), "; ".join(parts), more, off_note
    ]


func _remember_note(note_text: String) -> Dictionary:
    var result: Dictionary = AppState.memory_add_note(note_text)
    if bool(result.get("ok", false)):
        _refresh_memory_window()
        return _action_result(true, "command.remember", "Saved note #%d. I'll remember that." % int(result.get("id", 0)), "ok")
    var reason: String = str(result.get("reason", ""))
    if reason == "memory_full":
        return _action_result(false, "command.remember", "Memory notes are full (%d). Forget one first." % CHAT_MEMORY_MAX_NOTES, "memory_full")
    if reason == "memory_off":
        return _action_result(false, "command.remember", "I'm not keeping memories right now (Settings: Remembers you).", "memory_off")
    return _action_result(false, "command.remember", "I couldn't keep that note.", "invalid_arg")


func _forget_note(note_id: int, confirm: bool) -> Dictionary:
    if note_id <= 0:
        return _action_result(false, "command.forget", "Invalid note id.", "invalid_arg")
    if not confirm:
        _chat_memory_pending_forget_id = note_id
        _chat_memory_pending_forget_until = int(Time.get_unix_time_from_system()) + 10
        return _action_result(
            false,
            "command.forget",
            "Confirm with /forget %d confirm (within 10s)." % note_id,
            "confirm_required"
        )
    var now_unix := int(Time.get_unix_time_from_system())
    if _chat_memory_pending_forget_id != note_id or now_unix > _chat_memory_pending_forget_until:
        return _action_result(false, "command.forget", "Forget confirmation expired. Run /forget <id> again.", "confirm_expired")
    _chat_memory_pending_forget_id = -1
    _chat_memory_pending_forget_until = 0
    if AppState.memory_forget(note_id):
        _after_memory_forgotten()
        return _action_result(true, "command.forget", "Forgot #%d." % note_id, "ok")
    return _action_result(false, "command.forget", "I don't have a memory #%d. /memory lists them." % note_id, "missing_note")


func _apply_chat_text_size() -> void:
    if chat_log == null:
        return
    var mode := str(AppState.settings.get("chatTextSize", "m")).to_lower()
    var size := CHAT_FONT_SIZE_L if mode == "l" else CHAT_FONT_SIZE_M
    chat_log.add_theme_font_size_override("normal_font_size", size)
    if chat_input != null:
        chat_input.add_theme_font_size_override("font_size", size)
    if chat_send != null:
        chat_send.add_theme_font_size_override("font_size", size)


func _build_cadence_summary() -> String:
    var now_unix := int(Time.get_unix_time_from_system())
    var quiet_mode := AppState.is_quiet_hours_now()
    var info_variant = _prompt_cadence.debug_snapshot(now_unix, AppState.settings, quiet_mode)
    if typeof(info_variant) != TYPE_DICTIONARY:
        return "Cadence diagnostics unavailable."
    var info: Dictionary = info_variant
    var pieces := []
    for source in ["support", "world", "chat"]:
        var source_variant = info.get(source, {})
        if typeof(source_variant) != TYPE_DICTIONARY:
            continue
        var source_data: Dictionary = source_variant
        pieces.append(
            "%s c=%d/%d min=%ss" % [
                source,
                int(source_data.get("recent_count", 0)),
                int(source_data.get("burst_cap", 0)),
                int(source_data.get("min_interval_s", 0)),
            ]
        )
    var suffix := "DND off"
    if _is_dnd_active(now_unix):
        suffix = "DND on (%dm)" % _dnd_minutes_remaining(now_unix)
    return "Cadence: %s | %s" % [" | ".join(pieces), suffix]


func _build_cadence_hint_compact() -> String:
    var now_unix := int(Time.get_unix_time_from_system())
    var quiet_mode := AppState.is_quiet_hours_now()
    var info_variant = _prompt_cadence.debug_snapshot(now_unix, AppState.settings, quiet_mode)
    if typeof(info_variant) != TYPE_DICTIONARY:
        return "Cadence unavailable."
    var info: Dictionary = info_variant
    var support_variant = info.get("support", {})
    var world_variant = info.get("world", {})
    var support_data: Dictionary = support_variant if typeof(support_variant) == TYPE_DICTIONARY else {}
    var world_data: Dictionary = world_variant if typeof(world_variant) == TYPE_DICTIONARY else {}
    var s_min := int(support_data.get("min_interval_s", 0))
    var w_min := int(world_data.get("min_interval_s", 0))
    var s_cap := int(support_data.get("burst_cap", 0))
    var w_cap := int(world_data.get("burst_cap", 0))
    var s_count := int(support_data.get("recent_count", 0))
    var w_count := int(world_data.get("recent_count", 0))
    var s_last := int(_last_auto_prompt_by_source.get("support", 0))
    var w_last := int(_last_auto_prompt_by_source.get("world", 0))
    var s_next := _seconds_until_next_prompt(now_unix, s_last, s_min)
    var w_next := _seconds_until_next_prompt(now_unix, w_last, w_min)
    return "s %d/%d in %ss | w %d/%d in %ss" % [s_count, s_cap, s_next, w_count, w_cap, w_next]


func _seconds_until_next_prompt(now_unix: int, last_unix: int, min_interval_s: int) -> int:
    if min_interval_s <= 0 or last_unix <= 0:
        return 0
    return maxi(0, min_interval_s - (now_unix - last_unix))


func _build_chat_debug_summary() -> String:
    var reason_pairs := []
    var fail_pairs := []
    for reason_key in _chat_cmd_reason_counts.keys():
        var reason := str(reason_key)
        var count := int(_chat_cmd_reason_counts.get(reason_key, 0))
        reason_pairs.append("%s=%d" % [reason, count])
        if reason != "ok":
            fail_pairs.append({"reason": reason, "count": count})
    reason_pairs.sort()
    var reasons := ", ".join(reason_pairs)
    if reasons == "":
        reasons = "none"
    var avg_latency := int(round(float(_chat_cmd_latency_total_ms) / max(1, _chat_cmd_latency_samples)))
    var p95_latency := _percentile_latency(95)
    var total_cmd := _chat_cmd_ok_count + _chat_cmd_fail_count
    var fail_rate_pct := int(round((float(_chat_cmd_fail_count) / max(1, total_cmd)) * 100.0))
    var top_fail := "none"
    if not fail_pairs.is_empty():
        fail_pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return int(a.get("count", 0)) > int(b.get("count", 0))
        )
        var lead: Dictionary = fail_pairs[0]
        top_fail = "%s=%d" % [str(lead.get("reason", "")), int(lead.get("count", 0))]
    var budget_state := "ok" if fail_rate_pct <= 2 else "over"
    return "Chat debug: turns(y/b)=%d/%d cmd(ok/fail)=%d/%d fail=%d%% budget=%s latency(last/avg/p95)=%d/%d/%d topFail[%s] reasons[%s]" % [
        _chat_turn_user_count,
        _chat_turn_buddy_count,
        _chat_cmd_ok_count,
        _chat_cmd_fail_count,
        fail_rate_pct,
        budget_state,
        _chat_cmd_latency_last_ms,
        avg_latency,
        p95_latency,
        top_fail,
        reasons,
    ]


func _percentile_latency(percentile: int) -> int:
    if _chat_cmd_latency_recent_ms.is_empty():
        return 0
    var sorted := _chat_cmd_latency_recent_ms.duplicate()
    sorted.sort()
    var idx := int(ceil((float(percentile) / 100.0) * float(sorted.size()))) - 1
    idx = clampi(idx, 0, sorted.size() - 1)
    return int(sorted[idx])


func _run_settings_check() -> String:
    var issues := []
    var freq := str(AppState.settings.get("promptFrequency", "normal"))
    var event_freq := str(AppState.settings.get("eventFrequency", "normal"))
    var quiet := str(AppState.settings.get("quietModeStrictness", "balanced"))
    var intensity := str(AppState.settings.get("interactionIntensity", "balanced"))
    var chat_text_size := str(AppState.settings.get("chatTextSize", "m")).to_lower()
    if freq not in ["low", "normal", "high"]:
        issues.append("promptFrequency invalid")
    if event_freq not in ["low", "normal", "high"]:
        issues.append("eventFrequency invalid")
    if quiet not in ["lenient", "balanced", "strict"]:
        issues.append("quietModeStrictness invalid")
    if intensity not in ["cozy", "balanced", "deep", "idle"]:
        issues.append("interactionIntensity invalid")
    if chat_text_size not in ["m", "l"]:
        issues.append("chatTextSize invalid")
    if issues.is_empty():
        return "Settings check passed."
    return "Settings check warnings: %s" % ", ".join(issues)


func _apply_settings_preset(preset: String) -> Dictionary:
    var chosen := preset.to_lower()
    var preset_values := {}
    if chosen == "cozy":
        preset_values = {
            "eventFrequency": "low",
            "promptFrequency": "low",
            "interactionIntensity": "cozy",
            "quietModeStrictness": "strict",
        }
    elif chosen == "idle":
        preset_values = {
            "eventFrequency": "low",
            "promptFrequency": "low",
            "interactionIntensity": "idle",
            "quietModeStrictness": "strict",
        }
    elif chosen == "deep":
        preset_values = {
            "eventFrequency": "high",
            "promptFrequency": "high",
            "interactionIntensity": "deep",
            "quietModeStrictness": "lenient",
        }
    else:
        chosen = "balanced"
        preset_values = {
            "eventFrequency": "normal",
            "promptFrequency": "normal",
            "interactionIntensity": "balanced",
            "quietModeStrictness": "balanced",
        }

    _capture_settings_undo_snapshot()
    for key in preset_values.keys():
        _set_setting_with_audit(key, preset_values[key], "preset:%s" % chosen)
    AppState.flush()
    _refresh_settings_menu()
    _refresh_telemetry()
    return _action_result(
        true,
        "command.preset",
        "Preset applied: %s (use /settings undo within 10s)." % chosen,
        "ok"
    )


func _reset_settings_with_undo(confirm: bool) -> Dictionary:
    if not confirm:
        return _action_result(false, "command.settings", "Confirm with /settings reset confirm", "confirm_required")
    _capture_settings_undo_snapshot()
    _set_setting_with_audit("eventFrequency", "normal", "settings_reset")
    _set_setting_with_audit("promptFrequency", "normal", "settings_reset")
    _set_setting_with_audit("interactionIntensity", "balanced", "settings_reset")
    _set_setting_with_audit("quietModeStrictness", "balanced", "settings_reset")
    _set_setting_with_audit("chatTextSize", "m", "settings_reset")
    AppState.flush()
    _apply_chat_text_size()
    _refresh_settings_menu()
    _refresh_telemetry()
    return _action_result(
        true,
        "command.settings",
        "Settings reset to defaults (use /settings undo within 10s).",
        "ok"
    )


func _undo_settings_reset() -> Dictionary:
    var now_unix := int(Time.get_unix_time_from_system())
    if _settings_undo_snapshot.is_empty():
        return _action_result(false, "command.settings", "No settings undo snapshot available.", "missing_undo")
    if now_unix > _settings_undo_until_unix:
        _settings_undo_snapshot.clear()
        _settings_undo_until_unix = 0
        return _action_result(false, "command.settings", "Settings undo window expired.", "undo_expired")
    for key in _settings_undo_snapshot.keys():
        _set_setting_with_audit(key, _settings_undo_snapshot[key], "settings_undo")
    AppState.flush()
    _apply_chat_text_size()
    _refresh_settings_menu()
    _refresh_telemetry()
    _settings_undo_snapshot.clear()
    _settings_undo_until_unix = 0
    return _action_result(true, "command.settings", "Settings restored from undo snapshot.", "ok")


func _capture_settings_undo_snapshot() -> void:
    _settings_undo_snapshot = {
        "eventFrequency": str(AppState.settings.get("eventFrequency", "normal")),
        "promptFrequency": str(AppState.settings.get("promptFrequency", "normal")),
        "interactionIntensity": str(AppState.settings.get("interactionIntensity", "balanced")),
        "quietModeStrictness": str(AppState.settings.get("quietModeStrictness", "balanced")),
        "chatTextSize": str(AppState.settings.get("chatTextSize", "m")),
    }
    _settings_undo_until_unix = int(Time.get_unix_time_from_system()) + 10


func _set_setting_with_audit(key: String, value: Variant, source: String) -> bool:
    var old_value = AppState.settings.get(key, null)
    if old_value == value:
        return false
    AppState.settings[key] = value
    _record_settings_change(key, old_value, value, source)
    return true


func _capture_stats_session_baseline() -> void:
    var snap := AppState.get_stats_snapshot()
    var stats_variant = snap.get("stats", {})
    if typeof(stats_variant) != TYPE_DICTIONARY:
        _stats_session_baseline = {}
        return
    _stats_session_baseline = (stats_variant as Dictionary).duplicate(true)


func _stats_session_delta(current_stats: Dictionary) -> Dictionary:
    var out := {
        "strength": 0,
        "dexterity": 0,
        "charisma": 0,
        "endurance": 0,
        "wisdom": 0,
        "knowledge": 0,
    }
    for key in out.keys():
        out[key] = int(current_stats.get(key, 0)) - int(_stats_session_baseline.get(key, 0))
    return out


func _record_settings_change(key: String, old_value: Variant, new_value: Variant, source: String) -> void:
    _settings_change_history.append(
        {
            "ts": int(Time.get_unix_time_from_system()),
            "key": key,
            "old": str(old_value),
            "new": str(new_value),
            "source": source,
        }
    )
    if _settings_change_history.size() > SETTINGS_CHANGE_HISTORY_MAX:
        _settings_change_history.remove_at(0)


func _recent_settings_change_summary(max_items: int) -> String:
    if _settings_change_history.is_empty():
        return ""
    var start := maxi(0, _settings_change_history.size() - max_items)
    var entries: Array = _settings_change_history.slice(start, _settings_change_history.size())
    var parts := []
    for entry_variant in entries:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        parts.append("%s=%s" % [str(entry.get("key", "")), str(entry.get("new", ""))])
    return ", ".join(parts)


func _action_result(ok: bool, action_id: String, message: String, reason_code: String) -> Dictionary:
    return {
        "ok": ok,
        "action_id": action_id,
        "message": message,
        "reason_code": reason_code,
    }


func _record_chat_command_outcome(outcome: Dictionary) -> void:
    var action_id := str(outcome.get("action_id", ""))
    var reason_code := str(outcome.get("reason_code", "unknown"))
    var ok := bool(outcome.get("ok", false))
    _chat_last_command_id = action_id
    _chat_last_reason_code = reason_code
    if ok:
        _chat_cmd_ok_count += 1
    else:
        _chat_cmd_fail_count += 1
    var count := int(_chat_cmd_reason_counts.get(reason_code, 0))
    _chat_cmd_reason_counts[reason_code] = count + 1
    var elapsed_ms := int(outcome.get("elapsed_ms", 0))
    if elapsed_ms > 0:
        _chat_cmd_latency_last_ms = elapsed_ms
        _chat_cmd_latency_total_ms += elapsed_ms
        _chat_cmd_latency_samples += 1
        _chat_cmd_latency_recent_ms.append(elapsed_ms)
        if _chat_cmd_latency_recent_ms.size() > 120:
            _chat_cmd_latency_recent_ms.remove_at(0)


func _throttle_command(action_id: String) -> Dictionary:
    var now_ms := Time.get_ticks_msec()
    var key := "command:%s" % action_id
    var last_ms := int(_chat_cmd_last_key_by_action.get(key, 0))
    if now_ms - last_ms < 300:
        return _action_result(false, "command.%s" % action_id, "That was too fast. Try again.", "throttled")
    _chat_cmd_last_key_by_action[key] = now_ms
    return _action_result(true, "command.%s" % action_id, "", "ok")


func _set_home_mode_explicit(mode: String) -> void:
    var next_mode := "home" if mode == "home" else "overlay"
    AppState.set_home_mode(next_mode)
    if next_mode == "home":
        _state = _select_home_mode_action(int(Time.get_unix_time_from_system()))
    else:
        _state = "idle"
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_balloon_position()
    _refresh_telemetry()


func _emit_setting_feedback(key: String, value: String) -> void:
    _append_chat_line("System", "Applied %s=%s" % [key, value], "#B8F8C6")


func _set_dnd_minutes(minutes: int) -> void:
    var clamped := clampi(minutes, 1, 240)
    _dnd_until_unix = int(Time.get_unix_time_from_system()) + (clamped * 60)
    _emit_setting_feedback("dnd", "%dm" % clamped)
    _refresh_settings_menu()


func _refresh_stats_menu() -> void:
    if stats_label == null:
        return
    var snapshot := AppState.get_stats_snapshot()
    var stats_variant = snapshot.get("stats", {})
    var stats: Dictionary = stats_variant if typeof(stats_variant) == TYPE_DICTIONARY else {}
    var unspent := int(snapshot.get("stat_points_unspent", 0))
    var spent := int(snapshot.get("stat_points_spent", 0))
    var level := int(snapshot.get("bond_level", 1))
    var bond_xp := int(snapshot.get("bond_xp", 0))
    var xp_into := int(snapshot.get("xp_into_level", 0))
    var xp_need := int(snapshot.get("xp_to_next", 0))
    var xp_is_max := bool(snapshot.get("xp_is_max", false))
    var growth := int(snapshot.get("growth_stage", 1))
    var job_name := str(snapshot.get("job_name", "Explorer Buddy"))
    var primary := str(snapshot.get("job_primary_stat", "charisma"))
    var auto_assign := bool(snapshot.get("auto_assign_stats", false))
    var next_unlock := _next_unlock_hint(level)
    var upcoming_unlocks := _upcoming_unlocks(level, 3)

    var text := ""
    text += "[b][color=#FFCF6E]Progression[/color][/b]\n"
    text += "[color=#F4E9CF]Bond Level:[/color] %d   [color=#F4E9CF]Growth:[/color] %d\n" % [level, growth]
    if xp_is_max:
        text += "[color=#F4E9CF]Bond XP:[/color] %d   [color=#9DE0A9]MAX[/color]\n" % bond_xp
    else:
        text += "[color=#F4E9CF]Bond XP:[/color] %d   [color=#F4E9CF]Progress:[/color] %d/%d\n" % [bond_xp, xp_into, xp_need]
    text += "[color=#F4E9CF]Job:[/color] %s   [color=#F4E9CF]Primary:[/color] %s\n" % [job_name, primary]
    if next_unlock != "":
        text += "[color=#F4E9CF]Next Unlock:[/color] %s\n" % next_unlock
    else:
        text += "[color=#F4E9CF]Next Unlock:[/color] all unlocked\n"
    if not upcoming_unlocks.is_empty():
        text += "[color=#F4E9CF]Soon:[/color] %s\n" % ", ".join(upcoming_unlocks)
    text += "[color=#F4E9CF]Allocation:[/color] %s\n" % ("AUTO (idle mode)" if auto_assign else "MANUAL")
    text += "[color=#F4E9CF]Unspent Points:[/color] %d   [color=#F4E9CF]Spent:[/color] %d\n\n" % [unspent, spent]
    var deltas := _stats_session_delta(stats)
    var gained: Array[String] = []
    for stat_key in ["strength", "dexterity", "charisma", "endurance", "wisdom", "knowledge"]:
        if int(deltas.get(stat_key, 0)) != 0:
            gained.append("%s %+d" % [stat_key.substr(0, 3).to_upper(), int(deltas.get(stat_key, 0))])
    if not gained.is_empty():
        text += "[color=#F4E9CF]This session:[/color] %s\n\n" % ", ".join(gained)
    text += "[b][color=#FFCF6E]Stats[/color][/b]\n"
    if unspent > 0:
        text += "[color=#9DE0A9]You have %d points to spend.[/color] Click a stat below to add 1." % unspent
    else:
        text += "[color=#9AA3B5]No points to spend right now.[/color]"
    stats_label.bbcode_enabled = true
    stats_label.text = text

    _update_stat_button_text(stats_btn_strength, "STR", int(stats.get("strength", 1)), unspent)
    _update_stat_button_text(stats_btn_dexterity, "DEX", int(stats.get("dexterity", 1)), unspent)
    _update_stat_button_text(stats_btn_charisma, "CHA", int(stats.get("charisma", 1)), unspent)
    _update_stat_button_text(stats_btn_endurance, "END", int(stats.get("endurance", 1)), unspent)
    _update_stat_button_text(stats_btn_wisdom, "WIS", int(stats.get("wisdom", 1)), unspent)
    _update_stat_button_text(stats_btn_knowledge, "KNO", int(stats.get("knowledge", 1)), unspent)
    stats_btn_close.text = "Close"
    for stat_button in [
        stats_btn_strength, stats_btn_dexterity, stats_btn_charisma,
        stats_btn_endurance, stats_btn_wisdom, stats_btn_knowledge,
    ]:
        stat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        stat_button.custom_minimum_size = Vector2(0, 34)


func _update_stat_button_text(btn: Button, short_name: String, value: int, unspent: int) -> void:
    if btn == null:
        return
    var full_names := {"STR": "Strength", "DEX": "Dexterity", "CHA": "Charisma", "END": "Endurance", "WIS": "Wisdom", "KNO": "Knowledge"}
    btn.text = "%s  %d%s" % [str(full_names.get(short_name, short_name)), value, "   +" if unspent > 0 else ""]
    btn.disabled = unspent <= 0 or _is_away()
    if _is_away():
        btn.tooltip_text = "%s is at home." % _away_name()
    elif unspent <= 0:
        btn.tooltip_text = "No unspent stat points. Level up to earn more."
    else:
        btn.tooltip_text = "Spend 1 point on %s." % short_name


func _allocate_stat_point_ui(stat_id: String) -> void:
    var result := AppState.allocate_stat_point(stat_id, 1)
    if bool(result.get("ok", false)):
        var stat_name := str(result.get("stat_id", stat_id))
        var new_value := int(result.get("new_value", 0))
        _buddy_say("%s increased to %d." % [stat_name.capitalize(), new_value])
        _refresh_telemetry()
        _refresh_stats_menu()
        _refresh_settings_menu()
    else:
        var reason := str(result.get("reason", "unknown"))
        if reason == "no_points":
            _buddy_say("No stat points available. Level up first.")
        elif reason == "unknown_stat":
            _buddy_say("That stat is not recognized.")
        else:
            _buddy_say("Could not allocate stat point (%s)." % reason)
    _refresh_telemetry()


func _refresh_inventory_menu() -> void:
    if (
        inventory_header == null
        or inventory_category_filter == null
        or inventory_list == null
        or inventory_detail == null
        or inventory_btn_use == null
        or inventory_btn_equip == null
        or inventory_btn_unequip == null
    ):
        return

    var snapshot := AppState.get_inventory_snapshot()
    var inventory_variant = snapshot.get("inventory", [])
    var equipped_variant = snapshot.get("equipped_slots", {})
    var inventory: Array = inventory_variant if typeof(inventory_variant) == TYPE_ARRAY else []
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}

    _inventory_rows_cache = inventory.duplicate(true)
    _refresh_equipped_visual_state_from_snapshot(snapshot)
    var allowed_categories := _inventory_categories_for_tab(_inventory_active_tab)
    var sorted_inventory := _sort_inventory_rows(inventory, equipped_slots)
    _inventory_visible_instance_ids.clear()
    if _inventory_slot_grid != null:
        for child in _inventory_slot_grid.get_children():
            child.queue_free()
    _inventory_slot_buttons_by_instance.clear()

    for row_variant in sorted_inventory:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var category := str(row.get("category", "")).to_lower()
        if not allowed_categories.has(category):
            continue
        var instance_id := int(row.get("instance_id", -1))
        if instance_id <= 0:
            continue
        _inventory_visible_instance_ids.append(instance_id)
        var icon_tex := _resolve_item_overlay_texture(row)
        if _inventory_slot_grid != null:
            var btn := TextureButton.new()
            btn.ignore_texture_size = false
            btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
            btn.custom_minimum_size = Vector2(36, 36)
            btn.texture_normal = icon_tex
            btn.texture_hover = icon_tex
            btn.texture_pressed = icon_tex
            var equipped_label := _equipped_slot_for_instance(equipped_slots, instance_id)
            var base_name := str(row.get("name", str(row.get("id", "item"))))
            btn.tooltip_text = "%s\n%s | %s%s" % [
                base_name,
                category if category != "" else "misc",
                str(row.get("rarity", "common")),
                " | Equipped: %s" % equipped_label if equipped_label != "" else "",
            ]
            btn.pressed.connect(func() -> void:
                _inventory_selected_instance_id = instance_id
                _refresh_inventory_menu()
            )
            btn.gui_input.connect(func(event: InputEvent) -> void:
                if event is InputEventMouseButton:
                    var mb := event as InputEventMouseButton
                    if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and mb.pressed:
                        _inventory_selected_instance_id = instance_id
                        _activate_selected_inventory_item()
            )
            _inventory_slot_grid.add_child(btn)
            _inventory_slot_buttons_by_instance[instance_id] = btn

    if _inventory_visible_instance_ids.is_empty():
        _inventory_selected_instance_id = -1
    elif _inventory_selected_instance_id <= 0 or not _inventory_visible_instance_ids.has(_inventory_selected_instance_id):
        _inventory_selected_instance_id = int(_inventory_visible_instance_ids[0])

    for instance_key in _inventory_slot_buttons_by_instance.keys():
        var id := int(instance_key)
        var button := _inventory_slot_buttons_by_instance[instance_key] as TextureButton
        if button == null:
            continue
        if id == _inventory_selected_instance_id:
            button.modulate = Color(1.0, 1.0, 1.0, 1.0)
            button.self_modulate = Color(1.0, 0.92, 0.72, 1.0)
        else:
            button.modulate = Color(1.0, 1.0, 1.0, 0.92)
            button.self_modulate = Color(1.0, 1.0, 1.0, 1.0)

    var meso := int(snapshot.get("meso", snapshot.get("crystals", 0)))
    inventory_header.bbcode_enabled = true
    inventory_header.text = "[b][color=#FFD77A]Inventory[/color][/b]  [color=#E7D9B4]%d items[/color]  [color=#A8E8FF]%d meso[/color]  [color=#F4E9CF]Sort:[/color] %s\n[color=#A7B8C8]Tab sort | E activate | U use | Q unequip | Double-click activate[/color]" % [
        int(snapshot.get("inventory_count", 0)),
        meso,
        _inventory_sort_mode,
    ]
    _refresh_inventory_tab_buttons()
    _refresh_paper_doll(equipped_slots)

    var selected_item := _inventory_item_by_instance(_inventory_selected_instance_id)
    if selected_item.is_empty():
        inventory_detail.bbcode_enabled = true
        inventory_detail.text = "[color=#E7D9B4]Select an item to view details.[/color]"
        inventory_icon_preview.texture = null
        inventory_btn_use.disabled = true
        inventory_btn_equip.disabled = true
        inventory_btn_unequip.disabled = true
        return

    _render_inventory_detail(selected_item, equipped_slots)
    _refresh_inventory_action_buttons(selected_item, equipped_slots)


func _render_inventory_detail(item: Dictionary, equipped_slots: Dictionary) -> void:
    var name := str(item.get("name", str(item.get("id", "Item"))))
    var category := str(item.get("category", "misc"))
    var rarity := str(item.get("rarity", "common"))
    var item_id := str(item.get("id", ""))
    var instance_id := int(item.get("instance_id", -1))
    var source_type := str(item.get("sourceType", ""))
    var primary_theme := str(item.get("primaryTheme", item.get("theme", "")))
    var description := str(item.get("description", "")).strip_edges()
    var wz_id := str(item.get("wzId", "")).strip_edges()
    var icon_asset := str(item.get("iconAsset", item.get("assetRef", ""))).strip_edges()
    var wz_icon_path := str(item.get("wzIconPath", "")).strip_edges()
    var price := int(item.get("price", 0))
    var slot_max := int(item.get("slotMax", 0))
    var equipped_slot := _equipped_slot_for_instance(equipped_slots, instance_id)
    var effect_variant = item.get("effectProfile", {})
    var effect: Dictionary = effect_variant if typeof(effect_variant) == TYPE_DICTIONARY else {}
    var slot_hint := _normalize_inventory_slot_name(str(item.get("equipSlot", "")))
    var icon_tex := _resolve_item_overlay_texture(item)
    inventory_icon_preview.texture = icon_tex

    var text := ""
    text += "[b][color=#FFD77A]%s[/color][/b]\n" % name
    text += "[color=#F4E9CF]Category:[/color] %s\n" % category
    text += "[color=#F4E9CF]Rarity:[/color] %s\n" % rarity
    if primary_theme != "":
        text += "[color=#F4E9CF]Theme:[/color] %s\n" % primary_theme
    if source_type != "":
        text += "[color=#F4E9CF]Source:[/color] %s\n" % source_type
    text += "[color=#F4E9CF]Icon Resolved:[/color] %s\n" % ("yes" if icon_tex != null else "no")
    text += "[color=#F4E9CF]Icon Source:[/color] %s\n" % _inventory_icon_last_source
    text += "[color=#F4E9CF]Icon Cache:[/color] %s\n" % ("hit" if _inventory_icon_last_cache_hit else "miss")
    if icon_asset != "":
        text += "[color=#F4E9CF]Icon Asset:[/color] %s\n" % icon_asset
    if wz_icon_path != "":
        text += "[color=#F4E9CF]WZ Icon:[/color] %s\n" % wz_icon_path
    if description != "":
        text += "[color=#F4E9CF]Description:[/color] %s\n" % description
    if wz_id != "":
        text += "[color=#F4E9CF]WZ ID:[/color] %s\n" % wz_id
    if price > 0:
        text += "[color=#F4E9CF]Price:[/color] %d\n" % price
    if slot_max > 0:
        text += "[color=#F4E9CF]Stack Max:[/color] %d\n" % slot_max
    text += "[color=#F4E9CF]Item ID:[/color] %s\n" % item_id
    text += "[color=#F4E9CF]Instance:[/color] #%d\n" % instance_id
    if slot_hint != "":
        text += "[color=#F4E9CF]Equip Slot:[/color] %s\n" % slot_hint
    if equipped_slot != "":
        text += "[color=#9DE0A9]Equipped in slot:[/color] %s\n" % equipped_slot
    text += "\n[b][color=#FFCF6E]Effect Profile[/color][/b]\n"
    if effect.is_empty():
        text += "[color=#E7D9B4]No explicit effect profile.[/color]\n"
    else:
        for key_variant in effect.keys():
            var key := str(key_variant)
            text += "[color=#F4E9CF]%s:[/color] %s\n" % [key, str(effect.get(key_variant))]

    inventory_detail.bbcode_enabled = true
    inventory_detail.text = text


func _refresh_inventory_action_buttons(item: Dictionary, equipped_slots: Dictionary) -> void:
    var category := str(item.get("category", "")).to_lower()
    var equippable := _is_item_equippable(item)
    var equipped_slot := _equipped_slot_for_instance(equipped_slots, int(item.get("instance_id", -1)))
    var usable := _is_item_usable(item)

    inventory_btn_use.disabled = not usable
    inventory_btn_equip.disabled = not equippable
    inventory_btn_unequip.disabled = equipped_slot == ""
    inventory_btn_use.tooltip_text = "Consume/use this item."
    inventory_btn_equip.tooltip_text = "Equip this item if it supports an equipment slot."
    inventory_btn_unequip.tooltip_text = "Unequip selected item's slot."


func _activate_selected_inventory_item() -> void:
    var item := _inventory_item_by_instance(_inventory_selected_instance_id)
    if item.is_empty():
        _buddy_say("Select an inventory item first.")
        return
    if _is_item_equippable(item):
        _equip_selected_inventory_item()
        return
    if _is_item_usable(item):
        _use_selected_inventory_item()
        return
    _buddy_say("That item has no quick action. Try inspect/equip/place.")


func _selected_inventory_category() -> String:
    if inventory_category_filter == null:
        return "all"
    var idx := inventory_category_filter.selected
    if idx < 0:
        return "all"
    var categories := _inventory_filter_categories()
    if idx >= categories.size():
        return "all"
    return str(categories[idx])


func _set_inventory_tab(tab_id: String) -> void:
    var normalized := tab_id.to_lower().strip_edges()
    if normalized not in ["all", "equip", "use", "etc", "decor"]:
        normalized = "all"
    _inventory_active_tab = normalized
    _refresh_inventory_menu()


func _cycle_inventory_sort_mode() -> void:
    var idx := INVENTORY_SORT_MODES.find(_inventory_sort_mode)
    if idx < 0:
        idx = 0
    idx = (idx + 1) % INVENTORY_SORT_MODES.size()
    _inventory_sort_mode = str(INVENTORY_SORT_MODES[idx])
    _buddy_say("Inventory sort: %s" % _inventory_sort_mode)
    _refresh_inventory_menu()


func _inventory_categories_for_tab(tab_id: String) -> Dictionary:
    var tab := tab_id.to_lower().strip_edges()
    var rows := ["food", "gifts", "gear", "decor", "training_items", "materials", "quest_items", "evolution_items"]
    if tab == "equip":
        rows = ["gear", "training_items", "evolution_items"]
    elif tab == "use":
        rows = ["food", "gifts"]
    elif tab == "etc":
        rows = ["materials", "quest_items"]
    elif tab == "decor":
        rows = ["decor"]
    var out := {}
    for row in rows:
        out[str(row)] = true
    return out


func _refresh_inventory_tab_buttons() -> void:
    _set_inventory_tab_button_state(inventory_tab_all, "all")
    _set_inventory_tab_button_state(inventory_tab_equip, "equip")
    _set_inventory_tab_button_state(inventory_tab_use, "use")
    _set_inventory_tab_button_state(inventory_tab_etc, "etc")
    _set_inventory_tab_button_state(inventory_tab_decor, "decor")


func _set_inventory_tab_button_state(btn: Button, tab_id: String) -> void:
    if btn == null:
        return
    var active := _inventory_active_tab == tab_id
    var base := ""
    if tab_id == "all":
        base = "All"
    elif tab_id == "equip":
        base = "Equip"
    elif tab_id == "use":
        base = "Use"
    elif tab_id == "etc":
        base = "Etc"
    elif tab_id == "decor":
        base = "Decor"
    btn.text = "[%s]" % base if active else base


func _refresh_paper_doll(equipped_slots: Dictionary) -> void:
    var combat_slots: Array = PAPER_DOLL_GROUPS.get("combat", [])
    var style_slots: Array = PAPER_DOLL_GROUPS.get("style", [])
    var accessory_slots: Array = PAPER_DOLL_GROUPS.get("accessory", [])
    _render_paper_slot_label(
        paper_slot_gear_label,
        "Combat",
        _paper_group_text(equipped_slots, combat_slots)
    )
    _render_paper_slot_label(
        paper_slot_charm_label,
        "Style",
        _paper_group_text(equipped_slots, style_slots)
    )
    _render_paper_slot_label(
        paper_slot_relic_label,
        "Accessories",
        _paper_group_text(equipped_slots, accessory_slots)
    )
    if paper_btn_unequip_gear != null:
        paper_btn_unequip_gear.disabled = _first_equipped_slot(equipped_slots, combat_slots) == ""
    if paper_btn_unequip_charm != null:
        paper_btn_unequip_charm.disabled = _first_equipped_slot(equipped_slots, style_slots) == ""
    if paper_btn_unequip_relic != null:
        paper_btn_unequip_relic.disabled = _first_equipped_slot(equipped_slots, accessory_slots) == ""


func _render_paper_slot_label(label_node: Label, slot_name: String, item_name: String) -> void:
    if label_node == null:
        return
    var value := "(empty)" if item_name == "" else item_name
    label_node.text = "%s: %s" % [slot_name, value]


func _paper_group_text(equipped_slots: Dictionary, slots: Array) -> String:
    var chips: Array = []
    for slot_variant in slots:
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        if slot == "":
            continue
        var item_name := _paper_doll_item_name(equipped_slots, slot)
        chips.append(_paper_slot_chip(slot, item_name))
    return "\n".join(chips)


func _paper_slot_chip(slot_id: String, item_name: String) -> String:
    var slot_name := _display_inventory_slot(slot_id)
    if item_name == "":
        return "%s: -" % slot_name
    return "%s: %s" % [slot_name, item_name]


func _paper_doll_item_name(equipped_slots: Dictionary, slot_id: String, fallback_slot: String = "") -> String:
    var instance_id := _paper_doll_equipped_id(equipped_slots, slot_id, fallback_slot)
    if instance_id <= 0:
        return ""
    var row := _inventory_item_by_instance(instance_id)
    if row.is_empty():
        return ""
    return str(row.get("name", row.get("id", "")))


func _paper_doll_equipped_id(equipped_slots: Dictionary, slot_id: String, fallback_slot: String = "") -> int:
    var primary := _normalize_inventory_slot_name(slot_id)
    var fallback := _normalize_inventory_slot_name(fallback_slot)
    var instance_id := int(equipped_slots.get(primary, -1))
    if instance_id > 0:
        return instance_id
    if fallback != "":
        return int(equipped_slots.get(fallback, -1))
    return -1


func _first_equipped_slot(equipped_slots: Dictionary, slots: Array) -> String:
    for slot_variant in slots:
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        if slot == "":
            continue
        if int(equipped_slots.get(slot, -1)) > 0:
            return slot
    return ""


func _display_inventory_slot(slot_id: String) -> String:
    var slot := _normalize_inventory_slot_name(slot_id)
    if slot == "":
        return ""
    if SLOT_DISPLAY_NAMES.has(slot):
        return str(SLOT_DISPLAY_NAMES.get(slot))
    return slot.replace("_", " ").capitalize()


func _inventory_filter_categories() -> Array:
    return [
        "all",
        "food",
        "gifts",
        "gear",
        "decor",
        "training_items",
        "materials",
        "quest_items",
        "evolution_items",
    ]


func _inventory_category_display(category: String) -> String:
    if category == "all":
        return "All"
    return category.replace("_", " ").capitalize()


func _inventory_item_by_instance(instance_id: int) -> Dictionary:
    if instance_id <= 0:
        return {}
    for row_variant in _inventory_rows_cache:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if int(row.get("instance_id", 0)) == instance_id:
            return row.duplicate(true)
    return {}


func _sort_inventory_rows(inventory: Array, equipped_slots: Dictionary) -> Array:
    var rows: Array = inventory.duplicate(true)
    rows.sort_custom(func(a_variant: Variant, b_variant: Variant) -> bool:
        var a: Dictionary = a_variant if typeof(a_variant) == TYPE_DICTIONARY else {}
        var b: Dictionary = b_variant if typeof(b_variant) == TYPE_DICTIONARY else {}
        var mode := _inventory_sort_mode
        if mode == "name":
            var an := str(a.get("name", a.get("id", ""))).to_lower()
            var bn := str(b.get("name", b.get("id", ""))).to_lower()
            if an == bn:
                return int(a.get("instance_id", 0)) > int(b.get("instance_id", 0))
            return an < bn
        if mode == "category":
            var ac := str(a.get("category", "")).to_lower()
            var bc := str(b.get("category", "")).to_lower()
            if ac == bc:
                var an2 := str(a.get("name", a.get("id", ""))).to_lower()
                var bn2 := str(b.get("name", b.get("id", ""))).to_lower()
                return an2 < bn2
            return ac < bc
        if mode == "rarity":
            var ar := int(INVENTORY_RARITY_RANK.get(str(a.get("rarity", "common")).to_lower(), 0))
            var br := int(INVENTORY_RARITY_RANK.get(str(b.get("rarity", "common")).to_lower(), 0))
            if ar == br:
                return int(a.get("instance_id", 0)) > int(b.get("instance_id", 0))
            return ar > br
        if mode == "equipped":
            var ae := _equipped_slot_for_instance(equipped_slots, int(a.get("instance_id", -1))) != ""
            var be := _equipped_slot_for_instance(equipped_slots, int(b.get("instance_id", -1))) != ""
            if ae != be:
                return ae and not be
            return int(a.get("instance_id", 0)) > int(b.get("instance_id", 0))
        # newest
        return int(a.get("instance_id", 0)) > int(b.get("instance_id", 0))
    )
    return rows


func _equipped_slot_for_instance(equipped_slots: Dictionary, instance_id: int) -> String:
    if instance_id <= 0:
        return ""
    for slot_variant in equipped_slots.keys():
        var slot := str(slot_variant)
        if int(equipped_slots.get(slot_variant, -1)) == instance_id:
            return slot
    return ""


func _is_item_equippable(item: Dictionary) -> bool:
    var slot_hint := _normalize_inventory_slot_name(str(item.get("equipSlot", "")))
    if slot_hint != "":
        return true
    var category := str(item.get("category", "")).to_lower()
    return category in ["gear", "training_items", "evolution_items"]


func _item_equip_slot_id(row: Dictionary) -> String:
    return _normalize_inventory_slot_name(str(row.get("equipSlot", "")))


func _is_item_usable(item: Dictionary) -> bool:
    var category := str(item.get("category", "")).to_lower()
    return category in ["food", "gifts", "training_items", "materials"]


func _normalize_inventory_slot_name(slot_id: String) -> String:
    var slot := slot_id.to_lower().strip_edges().replace(" ", "_")
    if slot == "":
        return ""
    var aliases := {
        "face": "face_accessory",
        "eye": "eye_accessory",
        "ear": "earrings",
        "earring": "earrings",
        "glove": "gloves",
        "shoe": "shoes",
        "boots": "shoes",
        "pendant": "pendant1",
        "necklace": "pendant1",
        "ring": "ring1",
    }
    if aliases.has(slot):
        return str(aliases.get(slot))
    return slot


func _use_selected_inventory_item() -> void:
    var item := _inventory_item_by_instance(_inventory_selected_instance_id)
    if item.is_empty():
        _buddy_say("Select an inventory item first.")
        return
    var result := AppState.use_inventory_item(_inventory_selected_instance_id)
    if bool(result.get("ok", false)):
        var summary_parts: Array = []
        var effect_summary_variant = result.get("effect_summary", [])
        if typeof(effect_summary_variant) == TYPE_ARRAY:
            for entry_variant in (effect_summary_variant as Array):
                var part := str(entry_variant).strip_edges()
                if part == "" or part == "category=%s" % str(item.get("category", "")).to_lower():
                    continue
                summary_parts.append(part)
        var detail := ""
        if not summary_parts.is_empty():
            detail = " (%s)" % ", ".join(summary_parts)
        _buddy_say("Used %s%s." % [str(item.get("name", "item")), detail])
    else:
        var reason := str(result.get("reason", "unknown"))
        if reason == "equip_only":
            _buddy_say("That item is equippable, not consumable.")
        elif reason == "not_usable_category":
            _buddy_say("This item cannot be consumed. Try equip/place instead.")
        else:
            _buddy_say("Could not use item (%s)." % reason)
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_equipped_visual_state()
    _refresh_inventory_menu()
    _refresh_settings_menu()
    _refresh_stats_menu()


func _seed_test_inventory_ui() -> void:
    var result := AppState.seed_test_inventory()
    if bool(result.get("ok", false)):
        var added := int(result.get("added", 0))
        var cats_variant = result.get("categories", [])
        var cats := []
        if typeof(cats_variant) == TYPE_ARRAY:
            for c_variant in (cats_variant as Array):
                cats.append(str(c_variant))
        _buddy_say("Seeded %d test items (%s). Open Inventory (I) and check {icon:ok} rows." % [added, ", ".join(cats)])
    else:
        var snapshot := AppState.get_telemetry_snapshot()
        _buddy_say(
            "Could not seed test inventory (%s, visual=%s, economy=%s, catalog=%d)." % [
                str(result.get("reason", "unknown")),
                str(snapshot.get("visual_pack_id", snapshot.get("active_pack", "core_pack"))),
                str(snapshot.get("economy_pack_id", "core_pack")),
                int(snapshot.get("catalog_size", 0)),
            ]
        )
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_inventory_menu()
    _refresh_settings_menu()


func _repair_inventory_ui() -> void:
    var result := AppState.repair_inventory_catalog()
    if bool(result.get("ok", false)):
        var recovered := int(result.get("recovered_count", 0))
        var remaining := int(result.get("remaining_quarantine_count", 0))
        if recovered > 0:
            _buddy_say("Inventory repaired: %d restored, %d still quarantined." % [recovered, remaining])
        else:
            _buddy_say("Inventory repair complete. No recoverable rows found.")
    else:
        _buddy_say("Inventory repair failed (%s)." % str(result.get("reason", "unknown")))
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_inventory_menu()
    _refresh_settings_menu()


func _clear_inventory_ui() -> void:
    var result := AppState.clear_inventory_debug()
    if bool(result.get("ok", false)):
        var removed := int(result.get("removed_count", 0))
        var unequipped := int(result.get("unequipped_count", 0))
        _buddy_say("Inventory cleared for debug (%d removed, %d unequipped)." % [removed, unequipped])
    else:
        _buddy_say("Could not clear inventory (%s)." % str(result.get("reason", "unknown")))
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_equipped_visual_state()
    _refresh_assembled_state_overrides("equip_commit")
    queue_redraw()
    _refresh_inventory_menu()
    _refresh_settings_menu()


func _equip_selected_inventory_item() -> void:
    var item := _inventory_item_by_instance(_inventory_selected_instance_id)
    if item.is_empty():
        _buddy_say("Select an inventory item first.")
        return
    var result := AppState.equip_inventory_item(_inventory_selected_instance_id)
    if bool(result.get("ok", false)):
        _buddy_say("Equipped %s to %s." % [str(item.get("name", "item")), str(result.get("slot", "slot"))])
    else:
        var reason := str(result.get("reason", "unknown"))
        if reason == "not_equippable":
            _buddy_say("This item cannot be equipped.")
        else:
            _buddy_say("Could not equip item (%s)." % reason)
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_equipped_visual_state()
    _refresh_assembled_state_overrides("equip_commit")
    queue_redraw()
    _refresh_inventory_menu()


func _unequip_selected_inventory_item() -> void:
    var snapshot := AppState.get_inventory_snapshot()
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    var slot := _equipped_slot_for_instance(equipped_slots, _inventory_selected_instance_id)
    if slot == "":
        _buddy_say("Selected item is not equipped.")
        return
    var result := AppState.unequip_inventory_slot(slot)
    if bool(result.get("ok", false)):
        _buddy_say("Unequipped slot %s." % slot)
    else:
        _buddy_say("Could not unequip slot (%s)." % str(result.get("reason", "unknown")))
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_equipped_visual_state()
    _refresh_assembled_state_overrides("equip_commit")
    queue_redraw()
    _refresh_inventory_menu()


func _unequip_inventory_slot_ui(slot_id: String) -> void:
    var result := AppState.unequip_inventory_slot(slot_id)
    if bool(result.get("ok", false)):
        _buddy_say("Unequipped slot %s." % slot_id)
    else:
        _buddy_say("Could not unequip %s (%s)." % [slot_id, str(result.get("reason", "unknown"))])
    _refresh_telemetry()
    _invalidate_inventory_icon_cache()
    _refresh_equipped_visual_state()
    _refresh_assembled_state_overrides("equip_commit")
    queue_redraw()
    _refresh_inventory_menu()


func _unequip_first_paper_group_slot(group_id: String) -> void:
    var slots: Array = PAPER_DOLL_GROUPS.get(group_id, [])
    if slots.is_empty():
        _buddy_say("No slots configured for %s." % group_id)
        return
    var snapshot := AppState.get_inventory_snapshot()
    var equipped_variant = snapshot.get("equipped_slots", {})
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    var slot := _first_equipped_slot(equipped_slots, slots)
    if slot == "":
        _buddy_say("No equipped items in %s group." % group_id)
        return
    _unequip_inventory_slot_ui(slot)


func _refresh_equipped_visual_state() -> void:
    _refresh_equipped_visual_state_from_snapshot(AppState.get_inventory_snapshot())


func _refresh_equipped_visual_state_from_snapshot(snapshot: Dictionary) -> void:
    var inventory_variant = snapshot.get("inventory", [])
    var equipped_variant = snapshot.get("equipped_slots", {})
    var inventory: Array = inventory_variant if typeof(inventory_variant) == TYPE_ARRAY else []
    var equipped_slots: Dictionary = equipped_variant if typeof(equipped_variant) == TYPE_DICTIONARY else {}
    var by_instance := {}
    for row_variant in inventory:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var instance_id := int(row.get("instance_id", -1))
        if instance_id > 0:
            by_instance[instance_id] = row.duplicate(true)
    var next_equipped := {}
    for slot_variant in equipped_slots.keys():
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        if slot == "":
            slot = str(slot_variant)
        var instance_id := int(equipped_slots.get(slot_variant, -1))
        if instance_id <= 0 or not by_instance.has(instance_id):
            continue
        var row: Dictionary = (by_instance[instance_id] as Dictionary).duplicate(true)
        if str(row.get("equipSlot", "")).strip_edges() == "":
            row["equipSlot"] = slot
        next_equipped[slot] = row
    var next_signature := _build_equipped_visual_signature(next_equipped)
    if next_signature == _equipped_visual_signature:
        _equipped_visual_items = next_equipped
        return
    _equipped_visual_items = next_equipped
    _equipped_visual_signature = next_signature
    _refresh_assembled_state_overrides("equipped_sync")
    queue_redraw()


func _build_equipped_visual_signature(items: Dictionary) -> String:
    if items.is_empty():
        return ""
    var keys := items.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
    var pairs: Array[String] = []
    for slot_variant in keys:
        var slot := str(slot_variant)
        var row_variant = items.get(slot_variant, {})
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        pairs.append(
            "%s:%d:%d" % [slot, int(row.get("instance_id", -1)), int(row.get("wzId", -1))]
        )
    return "|".join(pairs)


func _load_assembler_default_parts() -> void:
    var defaults := {
        "body_id": 2000,
        "head_id": 12000,
        "face_id": 20204,
        "hair_id": 30167,
        "coat_id": 1042164,
        "pants_id": 1062085,
        "shoes_id": 1072121,
        "weapon_id": 1312007,
        "longcoat_id": -1,
        "cap_id": -1,
        "cape_id": -1,
    }
    var meta_path := ProjectSettings.globalize_path("res://content/core_pack/character/meta/idle.json")
    if FileAccess.file_exists(meta_path):
        var raw := FileAccess.get_file_as_string(meta_path)
        var parsed = JSON.parse_string(raw)
        if typeof(parsed) == TYPE_DICTIONARY:
            var action_resolution_variant = (parsed as Dictionary).get("action_resolution", [])
            if typeof(action_resolution_variant) == TYPE_ARRAY:
                for row_variant in (action_resolution_variant as Array):
                    if typeof(row_variant) != TYPE_DICTIONARY:
                        continue
                    var row: Dictionary = row_variant
                    var kind := str(row.get("asset_kind", "")).to_lower().strip_edges()
                    var part_id := int(row.get("part_id", -1))
                    if part_id <= 0:
                        continue
                    if kind == "body":
                        defaults["body_id"] = part_id
                    elif kind == "head":
                        defaults["head_id"] = part_id
                    elif kind == "face":
                        defaults["face_id"] = part_id
                    elif kind == "hair":
                        defaults["hair_id"] = part_id
                    elif kind == "coat":
                        defaults["coat_id"] = part_id
                    elif kind == "pants":
                        defaults["pants_id"] = part_id
                    elif kind == "shoes":
                        defaults["shoes_id"] = part_id
                    elif kind == "weapon":
                        defaults["weapon_id"] = part_id
                    elif kind == "longcoat":
                        defaults["longcoat_id"] = part_id
                    elif kind == "cap":
                        defaults["cap_id"] = part_id
                    elif kind == "cape":
                        defaults["cape_id"] = part_id
    _assembler_default_parts = defaults


func _refresh_assembled_state_overrides(reason: String = "refresh") -> void:
    var script_path := ProjectSettings.globalize_path(ASSEMBLER_SCRIPT_REL_PATH)
    var base_wz := _wz_icon_root.strip_edges()
    if not FileAccess.file_exists(script_path) or base_wz == "" or not DirAccess.dir_exists_absolute(base_wz):
        _assembled_state_texture_overrides.clear()
        _assembler_active_key = ""
        return
    _request_assembled_refresh_for_part_ids(_build_part_ids_from_equipped_items(_equipped_visual_items), reason)


func _build_part_ids_from_equipped_items(items: Dictionary) -> Dictionary:
    var part_ids := _assembler_default_parts.duplicate(true)
    if part_ids.is_empty():
        _load_assembler_default_parts()
        part_ids = _assembler_default_parts.duplicate(true)
    for slot_variant in items.keys():
        var slot := _normalize_inventory_slot_name(str(slot_variant))
        var row_variant = items.get(slot_variant, {})
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var wz_id := _resolve_row_wz_id(row)
        if wz_id <= 0:
            continue
        if slot == "weapon":
            part_ids["weapon_id"] = wz_id
        elif slot == "hat":
            part_ids["cap_id"] = wz_id
        elif slot == "overall":
            part_ids["longcoat_id"] = wz_id
            part_ids["coat_id"] = -1
            part_ids["pants_id"] = -1
        elif slot == "top":
            part_ids["coat_id"] = wz_id
            if int(part_ids.get("longcoat_id", -1)) > 0:
                part_ids["longcoat_id"] = -1
        elif slot == "bottom":
            part_ids["pants_id"] = wz_id
            if int(part_ids.get("longcoat_id", -1)) > 0:
                part_ids["longcoat_id"] = -1
        elif slot == "shoes":
            part_ids["shoes_id"] = wz_id
        elif slot == "cape":
            part_ids["cape_id"] = wz_id
    return part_ids


func _resolve_row_wz_id(row: Dictionary) -> int:
    var raw_id := int(row.get("wzId", -1))
    if raw_id > 0:
        return raw_id
    var item_id := str(row.get("id", "")).strip_edges()
    var digit_run := ""
    for i in range(item_id.length() - 1, -1, -1):
        var ch := item_id.substr(i, 1)
        if ch >= "0" and ch <= "9":
            digit_run = ch + digit_run
        elif digit_run != "":
            break
    if digit_run.length() >= 4:
        return int(digit_run)
    return -1


func _request_assembled_refresh_for_part_ids(part_ids: Dictionary, reason: String = "refresh") -> void:
    var key := _assemble_cache_key(part_ids)
    if key == "":
        return
    if key == _assembler_active_key and not _assembled_state_texture_overrides.is_empty():
        return
    if _assembler_cache_manifest.has(key):
        var manifest_variant = _assembler_cache_manifest.get(key, {})
        if typeof(manifest_variant) == TYPE_DICTIONARY and _apply_assembled_cache_manifest(manifest_variant as Dictionary, key):
            return
    _assembler_pending_key = key
    _assembler_pending_part_ids = part_ids.duplicate(true)
    _assembler_pending_reason = reason
    _start_assembler_thread_if_idle()


func _assemble_cache_key(part_ids: Dictionary) -> String:
    var pairs: Array[String] = []
    var keys := part_ids.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
    for key_variant in keys:
        var key := str(key_variant)
        pairs.append("%s=%d" % [key, int(part_ids.get(key, -1))])
    pairs.append("pack=%s" % _active_pack_id)
    pairs.append("ver=3")
    return String("|".join(pairs)).sha256_text()


func _assembled_cache_dir_for_key(cache_key: String) -> String:
    return ProjectSettings.globalize_path("user://assembled_runtime/cache_%s" % cache_key.substr(0, 16))


func _start_assembler_thread_if_idle() -> void:
    if _assembler_thread != null:
        if _assembler_thread.is_alive():
            return
        _assembler_thread.wait_to_finish()
        _assembler_thread = null
    if _assembler_pending_key == "" or _assembler_pending_part_ids.is_empty():
        return
    var script_path := ProjectSettings.globalize_path(ASSEMBLER_SCRIPT_REL_PATH)
    var base_wz := _wz_icon_root.strip_edges()
    var payload := {
        "script_path": script_path,
        "base_wz": base_wz,
        "cache_key": _assembler_pending_key,
        "part_ids": _assembler_pending_part_ids.duplicate(true),
        "cache_dir": _assembled_cache_dir_for_key(_assembler_pending_key),
    }
    _assembler_thread_result = {}
    _assembler_thread = Thread.new()
    var err := _assembler_thread.start(Callable(self, "_assembler_thread_main").bind(payload))
    if err != OK:
        _assembler_last_error = "assembler thread start failed (%d)" % err
        _assembler_thread = null
        return


func _poll_assembler_thread() -> void:
    if _assembler_thread == null:
        return
    if _assembler_thread.is_alive():
        return
    var result_variant = _assembler_thread.wait_to_finish()
    _assembler_thread = null
    if typeof(result_variant) != TYPE_DICTIONARY:
        _assembler_last_error = "assembler returned invalid result"
    else:
        _assembler_thread_result = result_variant
        if bool(_assembler_thread_result.get("ok", false)):
            var cache_key := str(_assembler_thread_result.get("cache_key", ""))
            var manifest_variant = _assembler_thread_result.get("manifest", {})
            if cache_key != "" and typeof(manifest_variant) == TYPE_DICTIONARY:
                _assembler_cache_manifest[cache_key] = (manifest_variant as Dictionary).duplicate(true)
                _apply_assembled_cache_manifest(manifest_variant as Dictionary, cache_key)
                if _assembler_pending_reason == "equip_commit":
                    _announce_assembler_status_once("Look render updated.")
            else:
                _assembler_last_error = "assembler produced incomplete manifest"
        else:
            _assembler_last_error = str(_assembler_thread_result.get("error", "assembler failed"))
    if _assembler_pending_key != "" and _assembler_pending_key != _assembler_active_key:
        _start_assembler_thread_if_idle()


func _drain_assembler_thread() -> void:
    if _assembler_thread == null:
        return
    if _assembler_thread.is_alive():
        _assembler_thread.wait_to_finish()
    else:
        _assembler_thread.wait_to_finish()
    _assembler_thread = null


func _announce_assembler_status_once(line: String, cooldown_seconds: int = 10) -> void:
    var now_unix := int(Time.get_unix_time_from_system())
    if now_unix - _assembler_last_status_unix < maxi(1, cooldown_seconds):
        return
    _assembler_last_status_unix = now_unix
    _buddy_say(line)


func _assembler_thread_main(payload: Dictionary) -> Dictionary:
    var script_path := str(payload.get("script_path", ""))
    var base_wz := str(payload.get("base_wz", ""))
    var cache_key := str(payload.get("cache_key", ""))
    var cache_dir := str(payload.get("cache_dir", ""))
    var part_ids_variant = payload.get("part_ids", {})
    var part_ids: Dictionary = part_ids_variant if typeof(part_ids_variant) == TYPE_DICTIONARY else {}
    if script_path == "" or base_wz == "" or cache_key == "" or cache_dir == "":
        return {"ok": false, "error": "invalid_payload", "cache_key": cache_key}
    if not DirAccess.dir_exists_absolute(cache_dir):
        var mk := DirAccess.make_dir_recursive_absolute(cache_dir)
        if mk != OK:
            return {"ok": false, "error": "cache_dir_failed", "cache_key": cache_key}

    var key_to_flag := {
        "body_id": "--base-id",
        "head_id": "--head-id",
        "face_id": "--face-id",
        "hair_id": "--hair-id",
        "cap_id": "--cap-id",
        "coat_id": "--coat-id",
        "longcoat_id": "--longcoat-id",
        "pants_id": "--pants-id",
        "shoes_id": "--shoes-id",
        "cape_id": "--cape-id",
        "weapon_id": "--weapon-id",
    }
    var manifest := {}
    for state_variant in ASSEMBLER_STATE_ACTION_MAP.keys():
        var state_id := str(state_variant)
        var action_id := str(ASSEMBLER_STATE_ACTION_MAP.get(state_variant, "stand1"))
        var frame_rows: Array = []
        for frame_index in range(int(ASSEMBLER_ACTION_FRAME_COUNT.get(action_id, 1))):
            var frame_error := _assembler_render_frame(
                script_path, base_wz, cache_dir, state_id, action_id, frame_index, part_ids, key_to_flag, frame_rows
            )
            if frame_error != "":
                return {"ok": false, "error": frame_error, "cache_key": cache_key}
        manifest[state_id] = {"action": action_id, "frames": frame_rows}
    return {"ok": true, "cache_key": cache_key, "manifest": manifest}


# Renders one frame with the wardrobe renderer. Runs on the assembler thread.
# Appends {"png", "json"} to frame_rows and returns "" on success.
func _assembler_render_frame(
    script_path: String,
    base_wz: String,
    cache_dir: String,
    state_id: String,
    action_id: String,
    frame_index: int,
    part_ids: Dictionary,
    key_to_flag: Dictionary,
    frame_rows: Array
) -> String:
    var output_png := cache_dir.path_join("%s_%d.png" % [state_id, frame_index])
    var output_json := cache_dir.path_join("%s_%d.json" % [state_id, frame_index])
    var args := PackedStringArray()
    args.append(script_path)
    args.append("--base-wz")
    args.append(base_wz)
    args.append("--action")
    args.append(action_id)
    args.append("--frame")
    args.append(str(frame_index))
    args.append("--output-png")
    args.append(output_png)
    args.append("--output-json")
    args.append(output_json)
    args.append("--hair-mode")
    args.append("auto")
    for key_variant in key_to_flag.keys():
        var key := str(key_variant)
        var value := int(part_ids.get(key, -1))
        if value <= 0:
            continue
        args.append(str(key_to_flag.get(key, "")))
        args.append(str(value))
    var output_lines: Array = []
    var exit_code := OS.execute("python", args, output_lines, true)
    if exit_code != OK:
        output_lines.clear()
        exit_code = OS.execute("py", args, output_lines, true)
    if exit_code != OK:
        return "state:%s frame:%d code:%d details:%s" % [state_id, frame_index, exit_code, "\n".join(output_lines)]
    frame_rows.append({"png": output_png, "json": output_json})
    return ""


func _apply_assembled_cache_manifest(manifest: Dictionary, cache_key: String) -> bool:
    var next_overrides := {}
    for state_variant in ASSEMBLER_STATE_ACTION_MAP.keys():
        var state_id := str(state_variant)
        var row_variant = manifest.get(state_id, null)
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var textures: Array = []
        var pivots: Array = []
        for frame_variant in row.get("frames", []):
            if typeof(frame_variant) != TYPE_DICTIONARY:
                return false
            var tex := _load_texture_from_file(str((frame_variant as Dictionary).get("png", "")))
            if tex == null:
                return false
            textures.append(tex)
            pivots.append(_assembled_frame_pivot(str((frame_variant as Dictionary).get("json", ""))))
        if textures.is_empty():
            continue
        next_overrides[state_id] = {"action": str(row.get("action", "")), "frames": textures, "pivots": pivots}
    if next_overrides.is_empty():
        return false
    _assembled_state_texture_overrides = next_overrides
    _assembler_active_key = cache_key
    queue_redraw()
    return true


func _draw_equipped_item_overlays(center: Vector2, draw_layer: String = "front") -> void:
    return


func _resolve_item_overlay_texture(item: Dictionary) -> Texture2D:
    var item_id := str(item.get("id", ""))
    var icon_asset_key := str(item.get("iconAsset", item.get("assetRef", item.get("iconPath", item.get("icon", ""))))).strip_edges()
    var wz_icon_key := str(item.get("wzIconPath", "")).strip_edges()
    var economy_pack_id := str(AppState.world_state.get("activeEconomyPackId", "core_pack"))
    var cache_key := "%s|%s|%s|%s|%s|%s" % [
        str(item.get("instance_id", -1)),
        item_id,
        icon_asset_key,
        wz_icon_key,
        _active_pack_id,
        economy_pack_id,
    ]
    if _inventory_icon_cache.has(cache_key):
        var cached = _inventory_icon_cache[cache_key]
        if cached == null or cached is Texture2D:
            _inventory_icon_last_cache_hit = true
            _inventory_icon_last_source = "cache:%s" % cache_key
            return cached
    _inventory_icon_last_cache_hit = false
    _inventory_icon_last_source = "none"
    var icon_paths: Array = []
    for key in ["iconAsset", "assetRef", "iconPath", "icon"]:
        var p := str(item.get(key, "")).strip_edges()
        if p != "":
            icon_paths.append(p)
    var wz_icon_rel := str(item.get("wzIconPath", "")).strip_edges()
    if wz_icon_rel != "":
        var wz_root := _wz_icon_root
        if wz_root != "":
            var candidates := _wz_icon_candidate_paths(wz_root, wz_icon_rel)
            for abs_wz_variant in candidates:
                var abs_wz := str(abs_wz_variant)
                if abs_wz == "":
                    continue
                var fs_tex := _load_texture_from_filesystem(abs_wz)
                if fs_tex != null:
                    _inventory_icon_cache[cache_key] = fs_tex
                    _inventory_icon_last_source = "wz:%s" % abs_wz
                    return fs_tex
    if ITEM_ICON_BY_ID.has(item_id):
        icon_paths.append(str(ITEM_ICON_BY_ID[item_id]))
    var category := str(item.get("category", "")).to_lower()
    if ITEM_ICON_BY_CATEGORY.has(category):
        icon_paths.append(str(ITEM_ICON_BY_CATEGORY[category]))
    var resolved: Texture2D = null
    for rel_path in icon_paths:
        resolved = _resolve_texture(rel_path, _active_pack_id)
        if resolved == null and _active_pack_id != "core_pack":
            resolved = _resolve_texture(rel_path, "core_pack")
        if resolved != null:
            _inventory_icon_last_source = "asset:%s" % rel_path
            break
    if resolved == null:
        resolved = _generate_fallback_item_icon(item)
        _inventory_icon_last_source = "generated_fallback:%s" % item_id
    _inventory_icon_cache[cache_key] = resolved
    return resolved


func _invalidate_inventory_icon_cache() -> void:
    _inventory_icon_cache.clear()
    _inventory_icon_last_source = "none"
    _inventory_icon_last_cache_hit = false


func _load_texture_from_filesystem(abs_path: String) -> Texture2D:
    if abs_path == "":
        return null
    var normalized := abs_path.replace("\\", "/")
    if not FileAccess.file_exists(normalized) and not FileAccess.file_exists(abs_path):
        return null
    var probe := normalized if FileAccess.file_exists(normalized) else abs_path
    var bytes := FileAccess.get_file_as_bytes(probe)
    if bytes.is_empty():
        return null

    var image := Image.new()
    var err := image.load_png_from_buffer(bytes)
    if err != OK:
        err = image.load_webp_from_buffer(bytes)
    if err != OK:
        err = image.load_jpg_from_buffer(bytes)
    if err != OK:
        # Last resort path loader.
        err = image.load(probe)
    if err != OK:
        return null
    return ImageTexture.create_from_image(image)


func _wz_icon_candidate_paths(root: String, rel_path: String) -> Array:
    var out: Array = []
    var cleaned_root := root.replace("\\", "/").trim_suffix("/")
    var cleaned_rel := rel_path.replace("\\", "/").trim_prefix("/")
    var rel_without_item := cleaned_rel
    if rel_without_item.begins_with("Item/"):
        rel_without_item = rel_without_item.substr(5)

    # Root points directly at extracted Base.wz.
    out.append(cleaned_root.path_join(cleaned_rel))
    out.append(cleaned_root.path_join(rel_without_item))

    # Root points at parent folder ("83 complete") rather than ".../Base.wz".
    out.append(cleaned_root.path_join("Base.wz").path_join(cleaned_rel))
    out.append(cleaned_root.path_join("Base.wz").path_join(rel_without_item))

    # Root points at Item subtree.
    out.append(cleaned_root.path_join("Item").path_join(rel_without_item))
    out.append(cleaned_root.path_join("Base.wz").path_join("Item").path_join(rel_without_item))

    var dedup := {}
    var final_paths: Array = []
    for p_variant in out:
        var p := str(p_variant).replace("\\", "/")
        if p == "" or dedup.has(p):
            continue
        dedup[p] = true
        final_paths.append(p)
    return final_paths


func _ensure_wz_icon_root_setting() -> void:
    _wz_icon_root = str(AppState.settings.get("wzIconRoot", "")).strip_edges()
    if _wz_icon_root != "" and DirAccess.dir_exists_absolute(_wz_icon_root):
        return

    var detected := _detect_wz_icon_root()
    if detected == "":
        if _wz_icon_root != "":
            # Keep user-provided path even when currently unavailable.
            return
        return

    _wz_icon_root = detected
    AppState.settings["wzIconRoot"] = detected
    AppState.flush()


func _detect_wz_icon_root() -> String:
    var user_name := OS.get_environment("USERNAME").strip_edges()
    for candidate_variant in WZ_ICON_ROOT_CANDIDATES:
        var candidate := str(candidate_variant)
        if "%s" in candidate and user_name != "":
            candidate = candidate % user_name
        if DirAccess.dir_exists_absolute(candidate):
            return candidate
    return ""


func _wz_icon_root_exists() -> bool:
    if _wz_icon_root == "":
        return false
    return DirAccess.dir_exists_absolute(_wz_icon_root)


func _generate_fallback_item_icon(item: Dictionary) -> Texture2D:
    var item_id := str(item.get("id", "item"))
    if _generated_item_icon_cache.has(item_id):
        var cached = _generated_item_icon_cache[item_id]
        if cached is Texture2D:
            return cached
    var hash := item_id.hash()
    var r := float((hash >> 16) & 0xFF) / 255.0
    var g := float((hash >> 8) & 0xFF) / 255.0
    var b := float(hash & 0xFF) / 255.0
    var base := Color(0.25 + (r * 0.65), 0.25 + (g * 0.65), 0.25 + (b * 0.65), 1.0)

    var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
    image.fill(base)
    for x in range(24):
        image.set_pixel(x, 0, Color.BLACK)
        image.set_pixel(x, 23, Color.BLACK)
    for y in range(24):
        image.set_pixel(0, y, Color.BLACK)
        image.set_pixel(23, y, Color.BLACK)
    # small center marker
    for y in range(10, 14):
        for x in range(10, 14):
            image.set_pixel(x, y, Color.WHITE)
    var tex := ImageTexture.create_from_image(image)
    _generated_item_icon_cache[item_id] = tex
    return tex


func _set_dnd_off() -> void:
    _dnd_until_unix = 0
    _emit_setting_feedback("dnd", "off")
    _refresh_settings_menu()
    _refresh_telemetry()


func _is_dnd_active(now_unix: int = -1) -> bool:
    var ts := now_unix
    if ts < 0:
        ts = int(Time.get_unix_time_from_system())
    return _dnd_until_unix > ts


func _dnd_minutes_remaining(now_unix: int = -1) -> int:
    var ts := now_unix
    if ts < 0:
        ts = int(Time.get_unix_time_from_system())
    if _dnd_until_unix <= ts:
        return 0
    return maxi(1, int(ceil(float(_dnd_until_unix - ts) / 60.0)))


func _build_restart_checkpoint() -> Dictionary:
    var snap := AppState.get_telemetry_snapshot()
    return {
        "ts": int(Time.get_unix_time_from_system()),
        "bond_level": int(snap.get("bond_level", 1)),
        "bond_xp": int(snap.get("bond_xp", 0)),
        "growth_stage": int(snap.get("growth_stage", 1)),
        "meso": int(snap.get("meso", snap.get("crystals", 0))),
    }


func _show_restart_verification_once() -> void:
    var cp_variant = AppState.settings.get("restartCheckpoint", {})
    if typeof(cp_variant) != TYPE_DICTIONARY:
        return
    var cp: Dictionary = cp_variant
    if cp.is_empty():
        return
    AppState.settings["restartCheckpoint"] = {}
    AppState.flush()
    var ts := int(cp.get("ts", 0))
    var now_unix := int(Time.get_unix_time_from_system())
    if ts <= 0 or now_unix - ts > RESTART_VERIFY_MAX_AGE_SEC:
        return
    var snap := AppState.get_telemetry_snapshot()
    var same_progress := (
        int(snap.get("bond_level", 1)) == int(cp.get("bond_level", 1))
        and int(snap.get("bond_xp", 0)) == int(cp.get("bond_xp", 0))
        and int(snap.get("growth_stage", 1)) == int(cp.get("growth_stage", 1))
        and int(snap.get("meso", snap.get("crystals", 0))) == int(cp.get("meso", cp.get("crystals", 0)))
    )
    var message := ""
    if same_progress:
        message = "Restart verified: progression persisted (Lv %d XP %d Growth %d Meso %d)." % [
            int(snap.get("bond_level", 1)),
            int(snap.get("bond_xp", 0)),
            int(snap.get("growth_stage", 1)),
            int(snap.get("meso", snap.get("crystals", 0))),
        ]
    else:
        message = "Restart warning: progression mismatch detected. Use /status to compare values."
    _update_balloon_position()
    _buddy_say(message)


func _restart_runtime() -> void:
    call_deferred("_restart_runtime_deferred")


func _restart_runtime_deferred() -> void:
    AppState.settings["restartCheckpoint"] = _build_restart_checkpoint()
    AppState.flush()
    if settings_window != null:
        settings_window.hide()
    _settings_menu_open = false
    get_tree().reload_current_scene()


# --- World host: the buddy visiting (Plan 14 step 2a) -----------------------

func _is_away() -> bool:
    return _visit != null and not _visit.is_visiting()


func _away_name() -> String:
    var buddy_name: String = _buddy_name()
    return buddy_name if buddy_name != "" else "Your buddy"


func _note_visit_interaction() -> void:
    if _visit != null:
        _visit.note_interaction()


func _start_visit_controller() -> void:
    if AppState.role() != "desktop":
        return
    _visit = VisitController.new()
    _visit.arrived.connect(_on_visit_arrived)
    _visit.left.connect(_on_visit_left)
    _visit.answer.connect(_on_visit_answer)
    _visit.health.connect(_on_visit_health)
    add_child(_visit)
    _visit.start()
    _refresh_settings_menu()


func _call_or_send_home() -> void:
    if _visit == null:
        return
    if _visit.is_visiting():
        _visit.send_home()
    else:
        _visit.call_over()
    _note_visit_interaction()
    _refresh_settings_menu()


func _on_visit_arrived(reason: String) -> void:
    _visit_answer = {}
    # The item catalogue is rebuilt from the content pack and is not in the save.
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
    _refresh_equipped_visual_state()
    var lines := {
        "opened": "I saw your light on, so I came over.",
        "called": "You called? Here I am.",
        "lonely": "It was too quiet at home. Can I stay a while?",
        "pending": "I finished what I was doing. Here I am.",
    }
    _update_balloon_position()
    _buddy_say(str(lines.get(reason, lines["called"])))
    if _buddy_name() == "":
        # Names are otherwise only chosen from mind events, and a visit has none.
        _maybe_choose_name()
    if not AppState.memory_enabled():
        # Remembering was turned off while it was at home: the talk in progress goes now.
        AppState.memory_discard_turns(int(AppState.memory_pending_turns().get("upto", 0)))
    _refresh_memory_window()
    _refresh_settings_menu()
    queue_redraw()


func _on_visit_left(reason: String) -> void:
    var lines := {
        "bedtime": "I'm getting sleepy. I'm going home to bed. Goodnight!",
        "quiet": "It's gone quiet, so I'll go home and see to my things. Call me over if you want me.",
        "sent": "Off home, then. See you soon.",
    }
    if lines.has(reason):
        _buddy_say(str(lines[reason]))
    _visit_answer = {}
    _refresh_memory_window()
    _refresh_settings_menu()
    queue_redraw()


func _on_visit_answer(come: String, at: int, why: String) -> void:
    _visit_answer = {"come": come, "at": at, "why": why}
    queue_redraw()


func _on_visit_health(state: String) -> void:
    _visit_health = state
    _refresh_settings_menu()


func _away_answer_line() -> String:
    if _visit_answer.is_empty():
        return ""
    var buddy_name := _away_name()
    var come := str(_visit_answer.get("come", ""))
    var at := int(_visit_answer.get("at", 0))
    if come == "later":
        # Activity labels are past tense ("had a nap"), so they are not used here.
        var minutes := maxi(1, int(ceil(float(at - int(Time.get_unix_time_from_system())) / 60.0)))
        return "%s is in the middle of something. It will come in about %d minutes." % [buddy_name, minutes]
    if come == "asleep":
        var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
        var local := Time.get_datetime_dict_from_unix_time(at + bias_minutes * 60)
        return "%s is asleep. It will come when it wakes, at about %02d:%02d." % [buddy_name, int(local.get("hour", 0)), int(local.get("minute", 0))]
    if come == "now":
        return "%s is on the way." % buddy_name
    return ""


func _draw_away_panel() -> void:
    var font: Font = ThemeDB.fallback_font
    var font_size := 14
    var width := 260.0
    var pad := 10.0
    var lines: Array = ["%s is at home." % _away_name()]
    var journal: Array = AppState.get_mind_journal(1)
    if not journal.is_empty() and typeof(journal[journal.size() - 1]) == TYPE_DICTIONARY:
        var latest := str((journal[journal.size() - 1] as Dictionary).get("text", ""))
        if latest != "":
            lines.append(latest)
    var answer_line := _away_answer_line()
    var heights: Array = []
    var total := pad
    for line_variant in lines:
        var size := font.get_multiline_string_size(str(line_variant), HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
        heights.append(size.y)
        total += size.y + 6.0
    var answer_height := 0.0
    if answer_line != "":
        answer_height = font.get_multiline_string_size(answer_line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
        total += answer_height + 6.0
    var button_height := 28.0
    total += button_height + pad
    var anchor := _floor_point()
    var panel := Rect2(Vector2(anchor.x - (width + pad * 2.0) * 0.5, anchor.y - total), Vector2(width + pad * 2.0, total))
    _away_panel_rect = panel
    draw_rect(panel, Color(0.07, 0.09, 0.15, 0.88))
    draw_rect(panel, Color(0.85, 0.75, 0.45, 0.9), false, 1.5)
    var y := panel.position.y + pad
    var x := panel.position.x + pad
    for index in range(lines.size()):
        var colour := Color(0.96, 0.91, 0.81) if index == 0 else Color(0.78, 0.82, 0.9)
        draw_multiline_string(font, Vector2(x, y + font_size), str(lines[index]), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, colour)
        y += float(heights[index]) + 6.0
    if answer_line != "":
        draw_multiline_string(font, Vector2(x, y + font_size), answer_line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, Color(1.0, 0.84, 0.48))
        y += answer_height + 6.0
    _away_button_rect = Rect2(Vector2(x, y), Vector2(width, button_height))
    draw_rect(_away_button_rect, Color(0.22, 0.3, 0.45))
    draw_rect(_away_button_rect, Color(0.85, 0.75, 0.45, 0.9), false, 1.0)
    draw_string(font, Vector2(x, y + 19.0), "Call over", HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color(0.96, 0.91, 0.81))


# Keeps the main menu in step with where the buddy is.
func _refresh_visit_menu() -> void:
    if _visit == null and _main_menu_health == null:
        return
    var away := _is_away()
    if _main_menu_health != null:
        var health_text := {
            "running": "Its world is running.",
            "starting": "Starting its world\u2026",
            "not_running": "Its world isn't running, so it's staying with you for now.",
        }
        _main_menu_health.text = str(health_text.get(_visit_health, ""))
    if _main_menu_btn_call != null:
        _main_menu_btn_call.text = "Call over" if away else "Send home"
        _main_menu_btn_call.tooltip_text = "Ask your buddy to come and visit." if away else "Send your buddy home."
    var tooltip := "%s is at home." % _away_name()
    for entry in [
        [_main_menu_btn_inventory, "Items your buddy has collected."],
        [_main_menu_btn_wardrobe, "Change what your buddy wears."],
        [_main_menu_btn_pause, "Put your buddy to sleep, or wake it up."],
    ]:
        var button := entry[0] as Button
        if button != null:
            button.disabled = away
            button.tooltip_text = tooltip if away else str(entry[1])


func _quit_runtime() -> void:
    if _visit != null:
        # The buddy goes home before the app closes, so the host can have it back.
        _visit.close_app()
    AppState.flush()
    get_tree().quit()


func _load_visual_assets(pack_id: String, manifest: Dictionary) -> void:
    _action_animations.clear()
    _action_textures.clear()
    _current_texture = null
    _ground_enabled = false
    _ground_texture = null
    _ground_tile_x = true
    _ground_scale = 1.0
    _ground_alpha = 1.0
    _ground_align = "top"
    _floor_padding = FLOOR_PADDING
    _ground_floor_offset_y = 0.0
    _ground_x_offset = 0.0
    _ground_surface_y_px = 0.0
    _ground_source_path = ""
    _current_sprite_path = ""
    _current_visual_action = ""
    _reset_current_animation()
    _sprite_scale = 2.35
    _sprite_anchor = DEFAULT_SPRITE_ANCHOR
    _max_loaded_pivot_px_y = 0.0
    _face_emote_manifest.clear()
    _face_overlay_frames.clear()
    _face_texture_cache.clear()
    _state_emote_map = DEFAULT_STATE_EMOTES.duplicate()
    _active_emote_semantic = "default"
    _active_face_variant = "default"
    _manual_emote_until_unix = 0
    _last_face_texture_path = ""
    _sit_chair_texture = null
    _sit_chair_origin_px = Vector2.ZERO
    _inventory_icon_cache.clear()

    var visual_variant = manifest.get("visual", {})
    if typeof(visual_variant) == TYPE_DICTIONARY:
        var visual: Dictionary = visual_variant
        var scale_raw = visual.get("scale", 1.45)
        if typeof(scale_raw) == TYPE_INT or typeof(scale_raw) == TYPE_FLOAT:
            _sprite_scale = maxf(0.2, float(scale_raw))

        var anchor_raw = visual.get("anchor", [])
        if typeof(anchor_raw) == TYPE_ARRAY and (anchor_raw as Array).size() >= 2:
            var anchor_array: Array = anchor_raw
            _sprite_anchor = Vector2(
                clampf(float(anchor_array[0]), 0.0, 1.0),
                clampf(float(anchor_array[1]), 0.0, 1.0)
            )

        var animations_variant = visual.get("animations", {})
        if typeof(animations_variant) == TYPE_DICTIONARY:
            var animations: Dictionary = animations_variant
            for action_key in animations.keys():
                var action_id := str(action_key)
                var rel_path := str(animations[action_key])
                if action_id == "" or rel_path == "":
                    continue
                var animation := _load_animation_spec(rel_path, pack_id)
                if not animation.is_empty():
                    _action_animations[action_id] = animation
                    var max_pivot_variant = animation.get("max_pivot_y", 0.0)
                    if typeof(max_pivot_variant) == TYPE_INT or typeof(max_pivot_variant) == TYPE_FLOAT:
                        _max_loaded_pivot_px_y = maxf(_max_loaded_pivot_px_y, float(max_pivot_variant))

        var emote_manifest_rel := ""
        var emotes_variant = visual.get("emotes", {})
        if typeof(emotes_variant) == TYPE_DICTIONARY:
            var emotes: Dictionary = emotes_variant
            emote_manifest_rel = str(emotes.get("manifest", ""))
            var state_map_variant = emotes.get("state_map", {})
            if typeof(state_map_variant) == TYPE_DICTIONARY:
                _state_emote_map = (state_map_variant as Dictionary).duplicate()
        if emote_manifest_rel == "":
            emote_manifest_rel = DEFAULT_EMOTE_MANIFEST_PATH
        _face_emote_manifest = _load_emote_manifest(emote_manifest_rel, pack_id)

        var sprites_variant = visual.get("sprites", {})
        if typeof(sprites_variant) == TYPE_DICTIONARY:
            var sprites: Dictionary = sprites_variant
            for action_key in sprites.keys():
                var action_id := str(action_key)
                var rel_path := str(sprites[action_key])
                if action_id == "" or rel_path == "":
                    continue

                var texture := _resolve_texture(rel_path, pack_id)
                if texture != null:
                    _action_textures[action_id] = texture

    if _pack_scale_override > 0.0:
        _sprite_scale = maxf(0.2, _pack_scale_override)

    _load_sit_chair_assets(pack_id)
    _ground_enabled = false
    _ground_texture = null
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_mouse_region()


func _draw_sit_chair(center: Vector2) -> void:
    if _state != "sit":
        return
    if _sit_chair_texture == null:
        return
    var tex_size := _sit_chair_texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return
    var scale := maxf(0.2, _sprite_scale)
    var draw_size := tex_size * scale
    var top_left := center - (_sit_chair_origin_px * scale)
    if _facing_sign != SPRITE_ART_FACING:
        # Mirror the chair with the sitter, or the buddy ends up sitting on
        # it back to front.
        draw_set_transform(center, 0.0, Vector2(-1.0, 1.0))
        draw_texture_rect(_sit_chair_texture, Rect2(top_left - center, draw_size), false)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    else:
        draw_texture_rect(_sit_chair_texture, Rect2(top_left, draw_size), false)


func _load_sit_chair_assets(pack_id: String) -> void:
    _sit_chair_texture = _resolve_texture(SIT_CHAIR_FRAME_PATH, pack_id)
    var origin := _load_sit_chair_origin(pack_id)
    if _sit_chair_texture == null and pack_id != "core_pack":
        _sit_chair_texture = _resolve_texture(SIT_CHAIR_FRAME_PATH, "core_pack")
        origin = _load_sit_chair_origin("core_pack")
    if _sit_chair_texture == null:
        return
    var tex_size := _sit_chair_texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return
    if origin == Vector2.ZERO:
        origin = Vector2(tex_size.x * 0.5, tex_size.y)
    _sit_chair_origin_px = origin


func _load_sit_chair_origin(pack_id: String) -> Vector2:
    var raw := _resolve_text(SIT_CHAIR_EFFECT_PATH, pack_id)
    if raw == "":
        return Vector2.ZERO
    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector2.ZERO
    var effect: Dictionary = parsed
    var frames_variant = effect.get("frames", [])
    if typeof(frames_variant) != TYPE_ARRAY or (frames_variant as Array).is_empty():
        return Vector2.ZERO
    var first_variant = (frames_variant as Array)[0]
    if typeof(first_variant) != TYPE_DICTIONARY:
        return Vector2.ZERO
    var first: Dictionary = first_variant
    var origin_variant = first.get("origin_px", [])
    if typeof(origin_variant) != TYPE_ARRAY or (origin_variant as Array).size() < 2:
        return Vector2.ZERO
    var values: Array = origin_variant
    return Vector2(float(values[0]), float(values[1]))


func _set_visual_for_state(action_id: String, force_reset: bool = false) -> void:
    var selected_animation_action := action_id
    var animation_variant = _action_animations.get(selected_animation_action, {})
    var use_animation := false
    if typeof(animation_variant) == TYPE_DICTIONARY and not (animation_variant as Dictionary).is_empty():
        use_animation = true
    else:
        selected_animation_action = "idle"
        animation_variant = _action_animations.get(selected_animation_action, {})
        if typeof(animation_variant) == TYPE_DICTIONARY and not (animation_variant as Dictionary).is_empty():
            use_animation = true

    if use_animation:
        var animation_data: Dictionary = animation_variant
        if force_reset or selected_animation_action != _current_visual_action:
            _apply_animation(selected_animation_action, animation_data)
        return

    var found = _action_textures.get(action_id, null)
    var source_action := action_id
    if found == null:
        found = _action_textures.get("idle", null)
        source_action = "idle"

    _reset_current_animation()
    _face_overlay_frames.clear()
    _current_visual_action = source_action
    if found is Texture2D:
        _current_texture = found
        _current_frame_anchor = _sprite_anchor
        _current_frame_pivot_px = NO_PIVOT
        _current_sprite_path = source_action
    else:
        _current_texture = null
        _current_frame_anchor = _sprite_anchor
        _current_frame_pivot_px = NO_PIVOT
        _current_sprite_path = ""


func _apply_animation(action_id: String, animation_data: Dictionary) -> void:
    _reset_current_animation()
    _face_overlay_frames.clear()
    _current_visual_action = action_id
    _current_animation_loop = bool(animation_data.get("loop", true))

    var frames_variant = animation_data.get("frames", [])
    if typeof(frames_variant) == TYPE_ARRAY:
        _current_animation_frames = (frames_variant as Array).duplicate()
    var durations_variant = animation_data.get("durations", [])
    if typeof(durations_variant) == TYPE_ARRAY:
        _current_animation_durations = (durations_variant as Array).duplicate()
    var anchors_variant = animation_data.get("anchors", [])
    if typeof(anchors_variant) == TYPE_ARRAY:
        _current_animation_anchors = (anchors_variant as Array).duplicate()
    var pivots_variant = animation_data.get("pivots", [])
    if typeof(pivots_variant) == TYPE_ARRAY:
        _current_animation_pivots = (pivots_variant as Array).duplicate()
    var face_overlays_variant = animation_data.get("face_overlays", [])
    if typeof(face_overlays_variant) == TYPE_ARRAY:
        _face_overlay_frames = (face_overlays_variant as Array).duplicate()

    if _current_animation_frames.is_empty():
        _current_texture = null
        _current_frame_anchor = _sprite_anchor
        _current_sprite_path = ""
        return

    if _current_animation_durations.is_empty():
        _current_animation_durations.resize(_current_animation_frames.size())
        for i in range(_current_animation_durations.size()):
            _current_animation_durations[i] = 0.12
    while _current_animation_durations.size() < _current_animation_frames.size():
        _current_animation_durations.append(0.12)
    while _current_animation_anchors.size() < _current_animation_frames.size():
        _current_animation_anchors.append(_sprite_anchor)
    while _current_animation_pivots.size() < _current_animation_frames.size():
        _current_animation_pivots.append(NO_PIVOT)

    _current_animation_index = 0
    _current_animation_elapsed = 0.0
    var first_frame = _current_animation_frames[0]
    if first_frame is Texture2D:
        _current_texture = first_frame
    else:
        _current_texture = null
    _current_frame_anchor = _anchor_for_current_animation_frame()
    _current_frame_pivot_px = _pivot_for_current_animation_frame()
    _current_sprite_path = "%s (anim %d/%d)" % [action_id, _current_animation_index + 1, _current_animation_frames.size()]


func _reset_current_animation() -> void:
    _current_animation_frames.clear()
    _current_animation_durations.clear()
    _current_animation_anchors.clear()
    _current_animation_pivots.clear()
    _face_overlay_frames.clear()
    _current_animation_index = 0
    _current_animation_elapsed = 0.0
    _current_animation_loop = true
    _current_frame_anchor = _sprite_anchor
    _current_frame_pivot_px = NO_PIVOT


func _advance_animation(delta: float) -> void:
    if _current_animation_frames.size() <= 1:
        return
    _current_animation_elapsed += delta

    var guard := 0
    while guard < 16:
        guard += 1
        var frame_duration := _duration_for_current_animation_frame()
        if _current_animation_elapsed < frame_duration:
            break
        _current_animation_elapsed -= frame_duration

        if _current_animation_index + 1 < _current_animation_frames.size():
            _current_animation_index += 1
        elif _current_animation_loop:
            _current_animation_index = 0
        else:
            _current_animation_index = _current_animation_frames.size() - 1
            _current_animation_elapsed = 0.0
            break

        var tex_variant = _current_animation_frames[_current_animation_index]
        if tex_variant is Texture2D:
            _current_texture = tex_variant
        _current_frame_anchor = _anchor_for_current_animation_frame()
        _current_frame_pivot_px = _pivot_for_current_animation_frame()
        _current_sprite_path = "%s (anim %d/%d)" % [
            _current_visual_action,
            _current_animation_index + 1,
            _current_animation_frames.size(),
        ]


func _anchor_for_current_animation_frame() -> Vector2:
    if _current_animation_anchors.is_empty():
        return _sprite_anchor
    var index := mini(_current_animation_index, _current_animation_anchors.size() - 1)
    var raw = _current_animation_anchors[index]
    if raw is Vector2:
        return raw
    if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
        var values: Array = raw
        return Vector2(float(values[0]), float(values[1]))
    return _sprite_anchor


func _pivot_for_current_animation_frame() -> Vector2:
    if _current_animation_pivots.is_empty():
        return NO_PIVOT
    var index := mini(_current_animation_index, _current_animation_pivots.size() - 1)
    var raw = _current_animation_pivots[index]
    if raw is Vector2:
        return raw
    if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
        var values: Array = raw
        return Vector2(float(values[0]), float(values[1]))
    return NO_PIVOT


func _duration_for_current_animation_frame() -> float:
    if _current_animation_durations.is_empty():
        return 0.12
    var index := mini(_current_animation_index, _current_animation_durations.size() - 1)
    var raw = _current_animation_durations[index]
    if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
        return maxf(0.03, float(raw))
    return 0.12


func _sprite_debug_label() -> String:
    if _current_sprite_path != "":
        return _current_sprite_path
    return "fallback"


func _ground_debug_label() -> String:
    if not _ground_enabled:
        return "off"
    if _ground_texture == null:
        return "missing"
    if _ground_source_path != "":
        return _ground_source_path
    return "on"


func _auto_adjust_floor_padding_to_loaded_pivots() -> void:
    if _max_loaded_pivot_px_y <= 0.0:
        return

    var floor_y := _floor_point().y
    var max_pivot_scaled := _max_loaded_pivot_px_y * _sprite_scale
    var top_y := floor_y - max_pivot_scaled
    if top_y >= SPRITE_VIEW_MARGIN:
        return

    var required_delta := SPRITE_VIEW_MARGIN - top_y
    _floor_padding = maxf(2.0, _floor_padding - required_delta)


# Where the floor contact point sits inside a rendered frame, from the
# renderer's metadata. Every frame is placed by this point, so frames of
# different sizes (a wide swing, a narrow step) do not jump around.
func _assembled_frame_pivot(json_path: String) -> Vector2:
    var parsed: Variant = JSON.parse_string(_read_text_file(json_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return NO_PIVOT
    var bounds_variant = (parsed as Dictionary).get("frame_bounds_world", null)
    if typeof(bounds_variant) != TYPE_DICTIONARY:
        return NO_PIVOT
    var bounds: Dictionary = bounds_variant
    return Vector2(-float(bounds.get("left", 0.0)), ASSEMBLER_FLOOR_WORLD_REF - float(bounds.get("top", 0.0)))


func _assembled_override() -> Dictionary:
    var override_variant = _assembled_state_texture_overrides.get(_state, null)
    if typeof(override_variant) != TYPE_DICTIONARY:
        return {}
    var entry: Dictionary = override_variant
    var frames: Array = entry.get("frames", [])
    if frames.is_empty():
        return {}
    var count := frames.size()
    var action_id := str(entry.get("action", ""))
    var seconds := float(ASSEMBLER_ACTION_FRAME_SECONDS.get(action_id, 0.5))
    var step := int(_bob_time / maxf(0.05, seconds))
    var index := step % count
    if count > 2 and ASSEMBLER_PING_PONG_ACTIONS.has(action_id):
        var cycle := (count * 2) - 2
        index = step % cycle
        if index >= count:
            index = cycle - index
    var pivots: Array = entry.get("pivots", [])
    var pivot := NO_PIVOT
    if index < pivots.size() and pivots[index] is Vector2:
        pivot = pivots[index]
    return {"texture": frames[index], "pivot": pivot}


func _selected_texture() -> Texture2D:
    var override := _assembled_override()
    if override.get("texture", null) is Texture2D:
        return override["texture"]
    return _current_texture


func _selected_pivot() -> Vector2:
    var override := _assembled_override()
    if override.get("pivot", null) is Vector2:
        return override["pivot"]
    return NO_PIVOT


func _presentation_texture() -> Texture2D:
    var selected := _selected_texture()
    var selected_size := Vector2.ZERO
    if selected != null:
        selected_size = selected.get_size()
    var fallback_size := Vector2.ZERO
    if PORTABLE_FALLBACK_TEXTURE != null:
        fallback_size = PORTABLE_FALLBACK_TEXTURE.get_size()
    var mode := PortableBuddyFallback.presentation_mode(selected_size, fallback_size)
    if mode == PortableBuddyFallback.PRESENTATION_SELECTED_ASSET:
        return selected
    if mode == PortableBuddyFallback.PRESENTATION_FALLBACK_ASSET:
        return PORTABLE_FALLBACK_TEXTURE
    return null


func _presentation_rect(center: Vector2, texture: Texture2D) -> Rect2:
    if texture == _selected_texture():
        return _sprite_rect_for_texture(center, texture, _selected_pivot())
    return PortableBuddyFallback.fitted_asset_rect(
        get_viewport_rect().size,
        texture.get_size(),
        _sprite_scale,
        SPRITE_VIEW_MARGIN
    )


func _draw_character_sprite(center: Vector2, texture: Texture2D) -> bool:
    if texture == null:
        return false

    var tex_size: Vector2 = texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return false

    _current_sprite_rect = _presentation_rect(center, texture)
    if _facing_sign != SPRITE_ART_FACING:
        var local_rect := Rect2(_current_sprite_rect.position - center, _current_sprite_rect.size)
        draw_set_transform(center, 0.0, Vector2(-1.0, 1.0))
        draw_texture_rect(texture, local_rect, false)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    else:
        draw_texture_rect(texture, _current_sprite_rect, false)
    return true


func _draw_face_overlay() -> bool:
    if _current_texture == null:
        return false
    if _face_overlay_frames.is_empty():
        return false
    if _current_animation_index < 0 or _current_animation_index >= _face_overlay_frames.size():
        return false

    var frame_overlay_variant = _face_overlay_frames[_current_animation_index]
    if typeof(frame_overlay_variant) != TYPE_DICTIONARY:
        return false
    var frame_overlay: Dictionary = frame_overlay_variant
    if frame_overlay.is_empty():
        return false

    var face_texture := _resolve_face_texture_for_overlay(frame_overlay)
    if face_texture == null:
        return false

    var local_pos_variant = frame_overlay.get("local_top_left", [])
    if typeof(local_pos_variant) != TYPE_ARRAY or (local_pos_variant as Array).size() < 2:
        return false
    var local_pos_arr: Array = local_pos_variant
    var local_top_left := Vector2(float(local_pos_arr[0]), float(local_pos_arr[1]))
    var emote_offset = EMOTE_DRAW_OFFSETS.get(_active_emote_semantic, Vector2.ZERO)
    if emote_offset is Vector2:
        local_top_left += emote_offset

    var source_size: Vector2 = _current_texture.get_size()
    if source_size.x <= 0.0 or source_size.y <= 0.0:
        return false

    var scale_x := _current_sprite_rect.size.x / source_size.x
    var scale_y := _current_sprite_rect.size.y / source_size.y
    var face_size := face_texture.get_size()
    var draw_rect := Rect2(
        _current_sprite_rect.position + Vector2(local_top_left.x * scale_x, local_top_left.y * scale_y),
        Vector2(face_size.x * scale_x, face_size.y * scale_y)
    )
    if _facing_sign != SPRITE_ART_FACING:
        var center := _draw_center
        var local_rect := Rect2(draw_rect.position - center, draw_rect.size)
        draw_set_transform(center, 0.0, Vector2(-1.0, 1.0))
        draw_texture_rect(face_texture, local_rect, false)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    else:
        draw_texture_rect(face_texture, draw_rect, false)
    return true


func _draw_ground() -> void:
    if not _ground_enabled:
        return
    if _ground_texture == null:
        return

    var draw_size := _ground_draw_size()
    if draw_size.x <= 0.0 or draw_size.y <= 0.0:
        return

    var viewport_size: Vector2 = get_viewport_rect().size
    var draw_y := _ground_draw_y(viewport_size, draw_size)

    var modulate := Color(1.0, 1.0, 1.0, clampf(_ground_alpha, 0.0, 1.0))
    if _ground_tile_x:
        var start_x := fmod(_ground_x_offset, draw_size.x)
        if start_x > 0.0:
            start_x -= draw_size.x
        var draw_x := start_x
        var guard := 0
        while draw_x < viewport_size.x and guard < 256:
            guard += 1
            draw_texture_rect(
                _ground_texture,
                Rect2(Vector2(draw_x, draw_y), draw_size),
                false,
                modulate
            )
            draw_x += draw_size.x
    else:
        var centered_x := ((viewport_size.x - draw_size.x) * 0.5) + _ground_x_offset
        draw_texture_rect(
            _ground_texture,
            Rect2(Vector2(centered_x, draw_y), draw_size),
            false,
            modulate
        )


func _set_emote_from_state(state_id: String) -> void:
    if int(Time.get_unix_time_from_system()) < _manual_emote_until_unix:
        return
    var semantic := str(_state_emote_map.get(state_id, "default"))
    _set_emote_from_semantic(semantic, false, 0.0)


func _set_emote_from_semantic(semantic: String, lock_manual: bool = false, lock_seconds: float = 0.0) -> void:
    var next_semantic := semantic.strip_edges().to_lower()
    if next_semantic == "":
        next_semantic = "default"
    if lock_manual:
        _manual_emote_until_unix = int(Time.get_unix_time_from_system() + maxf(0.0, lock_seconds))
    _active_emote_semantic = next_semantic
    _active_face_variant = str(_face_emote_manifest.get(next_semantic, next_semantic))
    if _active_face_variant == "":
        _active_face_variant = "default"


func _load_emote_manifest(path_spec: String, pack_id: String) -> Dictionary:
    var fallback := {
        "default": "default",
        "happy": "smile",
        "sad": "cry",
        "angry": "angry",
        "surprised": "bewildered",
        "love": "love",
        "wink": "wink",
        "sleepy": "blink",
        "sick": "vomit",
        "pain": "pain",
    }
    var raw := _resolve_text(path_spec, pack_id)
    if raw == "":
        return fallback

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) == TYPE_DICTIONARY:
        return parsed as Dictionary
    return fallback


func _resolve_face_texture_for_overlay(frame_overlay: Dictionary) -> Texture2D:
    var default_path := str(frame_overlay.get("default_png", ""))
    if not PortableBuddyFallback.is_repository_asset_path(default_path):
        _last_face_texture_path = "rejected non-repository face path"
        return null
    var cache_key := "%s|%s" % [_active_face_variant, default_path]
    if _face_texture_cache.has(cache_key):
        var cached = _face_texture_cache[cache_key]
        if cached is Texture2D:
            _last_face_texture_path = "%s (cached)" % cache_key
            return cached
        _last_face_texture_path = "missing (cached): %s" % cache_key
        return null

    var resolved: Texture2D = null
    for candidate in _face_variant_candidates(default_path, _active_face_variant):
        resolved = _resolve_texture(candidate, _active_pack_id)
        if resolved != null:
            _last_face_texture_path = candidate
            break

    _face_texture_cache[cache_key] = resolved
    if resolved == null:
        _last_face_texture_path = "missing: %s" % cache_key
    return resolved


func _face_variant_candidates(default_path: String, variant: String) -> Array[String]:
    var candidates: Array[String] = []
    if variant == "" or variant == "default":
        candidates.append(default_path)
        return candidates

    if default_path.find("/default/face.png") >= 0:
        candidates.append(default_path.replace("/default/face.png", "/%s/0/face.png" % variant))
        candidates.append(default_path.replace("/default/face.png", "/%s/face.png" % variant))
    if default_path.find("\\default\\face.png") >= 0:
        candidates.append(default_path.replace("\\default\\face.png", "\\%s\\0\\face.png" % variant))
        candidates.append(default_path.replace("\\default\\face.png", "\\%s\\face.png" % variant))
    if default_path.find("/default/0/face.png") >= 0:
        candidates.append(default_path.replace("/default/0/face.png", "/%s/0/face.png" % variant))
        candidates.append(default_path.replace("/default/0/face.png", "/%s/face.png" % variant))
    if default_path.find("\\default\\0\\face.png") >= 0:
        candidates.append(default_path.replace("\\default\\0\\face.png", "\\%s\\0\\face.png" % variant))
        candidates.append(default_path.replace("\\default\\0\\face.png", "\\%s\\face.png" % variant))

    candidates.append(default_path)
    return candidates


func _sprite_rect_for_texture(center: Vector2, texture: Texture2D, pivot_override: Vector2 = NO_PIVOT) -> Rect2:
    var tex_size: Vector2 = texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return Rect2(center, Vector2.ZERO)

    var viewport_size: Vector2 = get_viewport_rect().size
    var scale := _fit_scale_for_viewport(tex_size, viewport_size)
    var draw_size: Vector2 = tex_size * scale
    var frame_pivot := pivot_override if pivot_override.y >= 0.0 else _current_frame_pivot_px
    var use_pivot := frame_pivot.y >= 0.0
    var top_left := Vector2.ZERO
    var effective_pivot_y := tex_size.y
    if use_pivot:
        var pivot_to_use := frame_pivot
        if pivot_to_use.y > tex_size.y:
            var overflow := pivot_to_use.y - tex_size.y
            var overflow_blend := _pivot_overflow_blend_for_action(_current_visual_action)
            pivot_to_use.y = tex_size.y + (overflow * overflow_blend)
        var extra_offset := float(ACTION_EXTRA_FLOOR_OFFSET.get(_current_visual_action, 0.0))
        effective_pivot_y = clampf(
            pivot_to_use.y - CHARACTER_FLOOR_OFFSET_PX - extra_offset,
            0.0,
            tex_size.y
        )
        var effective_pivot := Vector2(pivot_to_use.x, effective_pivot_y)
        top_left = center - (effective_pivot * scale)
        # Keep floor contact exact across state/animation changes to prevent
        # cumulative visible drift on the desktop overlay.
        var contact_y := top_left.y + (effective_pivot_y * scale)
        top_left.y += center.y - contact_y
    else:
        var anchor := _current_frame_anchor
        anchor.x = clampf(anchor.x, -3.0, 3.0)
        anchor.y = clampf(anchor.y, -3.0, 3.0)
        top_left = center - Vector2(draw_size.x * anchor.x, draw_size.y * anchor.y)
    var min_x := SPRITE_VIEW_MARGIN
    var min_y := SPRITE_VIEW_MARGIN
    var max_x := viewport_size.x - draw_size.x - SPRITE_VIEW_MARGIN
    var max_y := viewport_size.y - draw_size.y - SPRITE_VIEW_MARGIN
    top_left.x = clampf(top_left.x, min_x, maxf(min_x, max_x))
    if not use_pivot:
        top_left.y = clampf(top_left.y, min_y, maxf(min_y, max_y))
    return Rect2(top_left, draw_size)


func _pivot_overflow_blend_for_action(action_id: String) -> float:
    if action_id == "sleep":
        # Keep prone between floating and over-sunk.
        return SLEEP_PIVOT_OVERFLOW_BLEND
    if action_id == "sit":
        # Preserve full chair-height offset exported in sit metadata.
        return SIT_PIVOT_OVERFLOW_BLEND
    # Use exported per-frame pivot metadata to keep a consistent floor anchor
    # across idle/walk/happy/etc animations.
    return 1.0


func _fit_scale_for_viewport(tex_size: Vector2, viewport_size: Vector2) -> float:
    var max_width := maxf(32.0, viewport_size.x - (SPRITE_VIEW_MARGIN * 2.0))
    var max_height := maxf(32.0, viewport_size.y - (SPRITE_VIEW_MARGIN * 2.0))
    var width_scale := max_width / tex_size.x
    var height_scale := max_height / tex_size.y
    return minf(_sprite_scale, minf(width_scale, height_scale))


func _effective_hit_radius() -> float:
    var texture := _presentation_texture()
    if texture != null:
        var tex_size: Vector2 = texture.get_size() * _sprite_scale
        return maxf(FALLBACK_HIT_RADIUS, maxf(tex_size.x, tex_size.y) * 0.28)
    return FALLBACK_HIT_RADIUS


func _resolve_texture(path_spec: String, pack_id: String) -> Texture2D:
    if not PortableBuddyFallback.is_repository_asset_path(path_spec):
        return null
    if not path_spec.begins_with("res://") and not PortableBuddyFallback.is_pack_id(pack_id):
        return null
    var res_candidates: Array[String] = []
    if path_spec.begins_with("res://"):
        res_candidates.append(path_spec)
    else:
        res_candidates.append("res://content/%s/%s" % [pack_id, path_spec])

    for res_path in res_candidates:
        if ResourceLoader.exists(res_path):
            var resource = load(res_path)
            if resource is Texture2D:
                return resource

        var fs_path := ProjectSettings.globalize_path(res_path)
        var loaded_fs_bytes := _load_texture_from_filesystem(fs_path)
        if loaded_fs_bytes != null:
            return loaded_fs_bytes
        var loaded_fs := _load_texture_from_file(fs_path)
        if loaded_fs != null:
            return loaded_fs

    return null


func _load_texture_from_file(fs_path: String) -> Texture2D:
    if fs_path == "":
        return null
    var normalized := fs_path.replace("\\", "/")
    if not FileAccess.file_exists(normalized) and not FileAccess.file_exists(fs_path):
        return null
    var probe := normalized if FileAccess.file_exists(normalized) else fs_path
    var bytes := FileAccess.get_file_as_bytes(probe)
    if bytes.is_empty():
        return null
    var image := Image.new()
    var err := image.load_png_from_buffer(bytes)
    if err != OK:
        err = image.load_webp_from_buffer(bytes)
    if err != OK:
        err = image.load_jpg_from_buffer(bytes)
    if err != OK:
        err = image.load(probe)
    if err != OK:
        return null
    return ImageTexture.create_from_image(image)


func _load_animation_spec(path_spec: String, pack_id: String) -> Dictionary:
    var text_bundle := _resolve_text_with_source(path_spec, pack_id)
    var raw := str(text_bundle.get("text", ""))
    if raw == "":
        return {}
    var animation_source_path := str(text_bundle.get("source", ""))

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var animation_data: Dictionary = parsed
    var sheet_path := str(animation_data.get("sheet", ""))
    if sheet_path == "":
        return {}
    var sheet_pack_id := pack_id
    if animation_source_path.begins_with("res://content/"):
        var source_relative := animation_source_path.trim_prefix("res://content/")
        sheet_pack_id = source_relative.get_slice("/", 0)
    var sheet_texture := _resolve_texture(sheet_path, sheet_pack_id)
    if sheet_texture == null:
        return {}

    var frames_variant = animation_data.get("frames", [])
    if typeof(frames_variant) != TYPE_ARRAY:
        return {}

    var frames: Array = []
    var durations: Array = []
    var anchors: Array = []
    var pivots: Array = []
    var face_overlays: Array = []
    var max_pivot_y := 0.0
    for frame_variant in frames_variant:
        if typeof(frame_variant) != TYPE_DICTIONARY:
            continue
        var frame_data: Dictionary = frame_variant
        var rect_variant = frame_data.get("rect", [])
        if typeof(rect_variant) != TYPE_ARRAY or (rect_variant as Array).size() < 4:
            continue
        var rect_values: Array = rect_variant
        var rect_x := int(rect_values[0])
        var rect_y := int(rect_values[1])
        var rect_w := int(rect_values[2])
        var rect_h := int(rect_values[3])
        if rect_w <= 0 or rect_h <= 0:
            continue

        var atlas := AtlasTexture.new()
        atlas.atlas = sheet_texture
        atlas.region = Rect2(rect_x, rect_y, rect_w, rect_h)
        frames.append(atlas)
        # Per-frame face metadata is excluded from shipping. Keep the runtime
        # overlay array aligned without reading those development-only files.
        face_overlays.append({})

        var duration_ms_raw = frame_data.get("duration_ms", 120)
        var duration_seconds := 0.12
        if typeof(duration_ms_raw) == TYPE_FLOAT or typeof(duration_ms_raw) == TYPE_INT:
            duration_seconds = maxf(0.03, float(duration_ms_raw) / 1000.0)
        durations.append(duration_seconds)

        var frame_anchor := _sprite_anchor
        var frame_pivot := NO_PIVOT
        var pivot_variant = frame_data.get("pivot_px", [])
        if typeof(pivot_variant) == TYPE_ARRAY and (pivot_variant as Array).size() >= 2:
            var pivot_array: Array = pivot_variant
            var pivot_x := float(pivot_array[0])
            var pivot_y := float(pivot_array[1])
            frame_pivot = Vector2(pivot_x, pivot_y)
            max_pivot_y = maxf(max_pivot_y, pivot_y)
            if rect_w > 0 and rect_h > 0:
                frame_anchor = Vector2(pivot_x / float(rect_w), pivot_y / float(rect_h))

        anchors.append(frame_anchor)
        pivots.append(frame_pivot)

    if frames.is_empty():
        return {}

    return {
        "frames": frames,
        "durations": durations,
        "anchors": anchors,
        "pivots": pivots,
        "face_overlays": face_overlays,
        "max_pivot_y": max_pivot_y,
        "loop": bool(animation_data.get("loop", true)),
    }


func _resolve_text(path_spec: String, pack_id: String) -> String:
    var bundle := _resolve_text_with_source(path_spec, pack_id)
    return str(bundle.get("text", ""))


func _resolve_text_with_source(path_spec: String, pack_id: String) -> Dictionary:
    if not PortableBuddyFallback.is_repository_asset_path(path_spec):
        return {}
    if not path_spec.begins_with("res://") and not PortableBuddyFallback.is_pack_id(pack_id):
        return {}
    var res_candidates: Array[String] = []
    if path_spec.begins_with("res://"):
        res_candidates.append(path_spec)
    else:
        res_candidates.append("res://content/%s/%s" % [pack_id, path_spec])

    for res_path in res_candidates:
        var from_res := _read_text_file(res_path)
        if from_res != "":
            return {"text": from_res, "source": res_path}

        var fs_path := ProjectSettings.globalize_path(res_path)
        var from_fs := _read_text_file(fs_path)
        if from_fs != "":
            return {"text": from_fs, "source": fs_path}

    return {}


func _read_text_file(path: String) -> String:
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var content := file.get_as_text()
    file.close()
    return content


const IDLE_PHRASE_MIN_GAP_SECONDS := 300


func _maybe_show_bond_phrase() -> void:
    # With its own mind on, the buddy speaks for itself (a thought every ten
    # minutes). Canned idle lines on top of that read as a script on repeat.
    if bool(AppState.settings.get("autonomyEnabled", true)):
        return
    if AppState.is_quiet_hours_now() or _is_dnd_active():
        return
    var now_unix := int(Time.get_unix_time_from_system())
    if _bond_phrase_active:
        return
    if now_unix - _last_idle_phrase_unix < IDLE_PHRASE_MIN_GAP_SECONDS:
        return
    var tier := AppState.get_bond_tier()
    var phrases: Variant = tier.get("idle_phrases", null)
    if typeof(phrases) != TYPE_ARRAY or (phrases as Array).is_empty():
        return
    var phrase := str((phrases as Array)[randi() % (phrases as Array).size()])
    if phrase == "" or phrase == "...":
        return
    _bond_phrase_active = true
    _last_idle_phrase_unix = now_unix
    _update_balloon_position()
    _buddy_say(phrase, "idle")
    await get_tree().create_timer(4.0).timeout
    chat_balloon.hide_bubble()
    _bond_phrase_active = false


func _update_balloon_position() -> void:
    var head_y := _current_sprite_rect.position.y if _current_sprite_rect.size.y > 0.0 else _draw_center.y - 80.0
    chat_balloon.position = Vector2(_draw_center.x, head_y)


func _return_to_idle_after_drag() -> void:
    await get_tree().create_timer(0.5).timeout
    if not _dragging:
        _state = "idle"
        _set_emote_from_state(_state)
        _set_visual_for_state(_state)
        queue_redraw()


func _show_welcome_once() -> void:
    welcome_label.visible = true
    AppState.mark_first_run_seen()
    await get_tree().create_timer(6.0).timeout
    welcome_label.visible = false


func _show_while_away_report_once() -> void:
    if _away_report_shown:
        return
    _away_report_shown = true
    var summary := AppState.get_last_active_summary()
    if summary == "":
        return
    _update_balloon_position()
    _buddy_say(summary)
    await get_tree().create_timer(5.0).timeout
    chat_balloon.hide_bubble()
    AppState.clear_last_active_summary()
    _show_continuity_hint_once()


func _show_continuity_hint_once() -> void:
    if _continuity_hint_shown or not bool(AppState.settings.get("supportHintsEnabled", true)):
        return
    _continuity_hint_shown = true
    var hint := AppState.get_continuity_hint()
    if hint == "":
        return
    _update_balloon_position()
    _buddy_say(hint)
    await get_tree().create_timer(4.0).timeout
    chat_balloon.hide_bubble()


func _open_debug_reward_box() -> void:
    var box_ids := AppState.get_reward_box_ids()
    if box_ids.is_empty():
        _update_balloon_position()
        _buddy_say("No reward boxes configured.")
        return
    var preferred := "cozy_box" if box_ids.has("cozy_box") else str(box_ids[0])
    var result := AppState.open_reward_box(preferred)
    _update_balloon_position()
    if bool(result.get("ok", false)):
        var item_name := str(result.get("item_name", "item"))
        var item_rarity := str(result.get("item_rarity", "common"))
        if bool(result.get("duplicate", false)):
            var recycle := int(result.get("recycle_meso", result.get("recycle_crystals", 0)))
            _buddy_say(
                "Opened %s: %s [%s] (duplicate +%d meso)"
                % [preferred, item_name, item_rarity, recycle]
            )
        else:
            _buddy_say("Opened %s: %s [%s]" % [preferred, item_name, item_rarity])
    else:
        var reason := str(result.get("reason", "unavailable"))
        _buddy_say("Could not open %s (%s)" % [preferred, reason])


func _show_world_prompt(prompt: Dictionary) -> bool:
    var prompt_type := str(prompt.get("type", ""))
    var npc_name := str(prompt.get("npcName", "Villager"))
    var text := str(prompt.get("text", ""))
    if text == "":
        return false
    var line := ""
    if prompt_type == "encounter":
        line = "%s: %s (F12 engage / Shift+F12 skip)" % [npc_name, text]
    else:
        line = "%s: %s (F12 complete)" % [npc_name, text]
    return _show_auto_prompt(line, "world")


func _resolve_world_prompt(engage_encounter: bool) -> void:
    var world_snapshot := AppState.get_world_snapshot()
    var pending_encounter := str(world_snapshot.get("pending_encounter_id", ""))
    var pending_quest := str(world_snapshot.get("pending_quest_id", ""))
    _update_balloon_position()
    if pending_encounter != "":
        var encounter_result := AppState.resolve_pending_encounter(engage_encounter)
        if bool(encounter_result.get("ok", false)):
            var npc := str(encounter_result.get("npc_name", "Villager"))
            var meso := int(encounter_result.get("meso", encounter_result.get("crystals", 0)))
            var item_name := str(encounter_result.get("item_name", ""))
            var drop_item_name := str(encounter_result.get("drop_item_name", ""))
            var action_word := "engaged" if engage_encounter else "skipped"
            var reward_text := "+%d meso" % meso
            if item_name != "":
                reward_text += " + %s" % item_name
            if drop_item_name != "":
                reward_text += " + drop:%s" % drop_item_name
            _buddy_say("%s encounter %s: %s" % [npc, action_word, reward_text])
        else:
            _buddy_say("No encounter to resolve.")
        _refresh_telemetry()
        return

    if pending_quest != "":
        var quest_result := AppState.complete_pending_quest()
        if bool(quest_result.get("ok", false)):
            var npc_name := str(quest_result.get("npc_name", "Villager"))
            var meso_value := int(quest_result.get("meso", quest_result.get("crystals", 0)))
            var reward_line := "+%d meso" % meso_value
            var item := str(quest_result.get("item_name", ""))
            if item != "":
                reward_line += " + %s" % item
            _buddy_say("%s quest complete: %s" % [npc_name, reward_line])
        else:
            _buddy_say("No quest to complete.")
        _refresh_telemetry()
        return

    _buddy_say("No pending world prompt.")


func _cycle_home_mode() -> void:
    var snapshot := AppState.get_world_snapshot()
    var current_mode := str(snapshot.get("home_mode", "overlay"))
    var next_mode := "home" if current_mode != "home" else "overlay"
    AppState.set_home_mode(next_mode)
    if next_mode == "home":
        _state = _select_home_mode_action(int(Time.get_unix_time_from_system()))
    else:
        _state = "idle"
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_balloon_position()
    var home_name := str(snapshot.get("home_scene_id", "cozy_starter_room"))
    if next_mode == "home":
        var wall_decor := str(snapshot.get("home_wall_decor", ""))
        var suffix := ""
        if wall_decor != "":
            suffix = " wall decor: %s" % wall_decor
        _buddy_say("Home mode active (%s)%s" % [home_name, suffix])
    else:
        _buddy_say("Overlay mode active.")
    _refresh_telemetry()


func _select_home_mode_action(now_unix: int) -> String:
    var dt := Time.get_datetime_dict_from_system()
    var hour := int(dt.get("hour", 12))
    if (hour < 6 or hour >= 22) and _allowed_actions.has("sleep"):
        return "sleep"
    if _allowed_actions.has("sit") and int(now_unix / 12) % 2 == 0:
        return "sit"
    if _allowed_actions.has("happy") and int(now_unix / 18) % 3 == 0:
        return "happy"
    if _allowed_actions.has("idle"):
        return "idle"
    return "default"


func _show_support_hint(productivity_event: Dictionary) -> void:
    if not bool(AppState.settings.get("supportHintsEnabled", true)):
        return
    var event_id := str(productivity_event.get("id", ""))
    var line := ""
    if event_id == "focus-celebration":
        line = "You are focused. Nice momentum."
    elif event_id == "break-suggestion":
        line = "Quick stretch break could help."
    elif event_id == "late-session-checkin":
        line = "It is getting late. Want to wind down?"
    if line == "":
        return
    _show_auto_prompt(line, "support")


func _show_progress_feedback(before: Dictionary, after: Dictionary) -> void:
    if typeof(before) != TYPE_DICTIONARY or typeof(after) != TYPE_DICTIONARY:
        return
    var before_xp := int(before.get("bond_xp", 0))
    var after_xp := int(after.get("bond_xp", 0))
    var before_level := int(before.get("bond_level", 1))
    var after_level := int(after.get("bond_level", 1))
    var before_growth := int(before.get("growth_stage", 1))
    var after_growth := int(after.get("growth_stage", 1))
    var before_points := int(before.get("stat_points_unspent", 0))
    var after_points := int(after.get("stat_points_unspent", 0))
    var before_unlocks := int(before.get("unlock_count", 0))
    var after_unlocks := int(after.get("unlock_count", 0))
    var max_level := UnlockTable.max_level()
    var msg := ""
    if after_level >= max_level:
        msg = "Bond Lv %d (MAX) XP capped Growth %d" % [after_level, after_growth]
    else:
        msg = "Bond Lv %d %s Growth %d" % [after_level, _xp_segment_for_level(after_xp, after_level, max_level), after_growth]
    if after_level > before_level:
        msg += " level up!"
        if after_points > before_points:
            msg += " +%d stat pts" % (after_points - before_points)
    if after_growth > before_growth:
        msg += " growth up!"
    if after_unlocks > before_unlocks:
        msg += " unlock +%d" % (after_unlocks - before_unlocks)
    var next_unlock := _next_unlock_hint(after_level)
    if next_unlock == "":
        msg += " all unlocks unlocked"
    else:
        msg += " next %s" % next_unlock
    _update_balloon_position()
    _buddy_say(msg)


func _next_unlock_hint(level: int) -> String:
    var rows := UnlockTable.all_unlock_rows()
    var best_level := 9999
    var best_value := ""
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var unlock_level := int(row.get("level", 9999))
        if unlock_level <= level:
            continue
        if unlock_level < best_level:
            best_level = unlock_level
            best_value = str(row.get("value", row.get("id", "unlock")))
    if best_value == "":
        return ""
    return "L%d:%s" % [best_level, best_value]


func _upcoming_unlocks(level: int, limit: int = 3) -> Array:
    var out: Array = []
    var rows := UnlockTable.all_unlock_rows()
    var pending: Array = []
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var unlock_level := int(row.get("level", 9999))
        if unlock_level <= level:
            continue
        pending.append(row)
    pending.sort_custom(func(a_variant: Variant, b_variant: Variant) -> bool:
        var a: Dictionary = a_variant if typeof(a_variant) == TYPE_DICTIONARY else {}
        var b: Dictionary = b_variant if typeof(b_variant) == TYPE_DICTIONARY else {}
        return int(a.get("level", 9999)) < int(b.get("level", 9999))
    )
    var cap := maxi(0, limit)
    for row_variant in pending:
        if out.size() >= cap:
            break
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        out.append("L%d:%s" % [int(row.get("level", 0)), str(row.get("value", row.get("id", "unlock")))])
    return out


func _xp_segment_for_level(total_xp: int, level: int, max_level: int) -> String:
    if level >= max_level:
        return "XP max (total %d)" % total_xp
    var curve := UnlockTable.xp_curve()
    if curve.size() >= 2 and level >= 1 and level < curve.size():
        var current_floor := int(curve[level - 1])
        var next_floor := int(curve[level])
        var into: int = maxi(0, total_xp - current_floor)
        var need: int = maxi(1, next_floor - current_floor)
        return "XP %d/%d" % [into, need]
    var xp_per_level := UnlockTable.xp_per_level()
    return "XP %d/%d" % [total_xp % xp_per_level, xp_per_level]


func _show_auto_prompt(line: String, source_kind: String) -> bool:
    if line == "":
        return false
    var now_unix := int(Time.get_unix_time_from_system())
    if _is_dnd_active(now_unix) and source_kind in ["support", "world"]:
        _manual_verification_report.record_prompt_metric(source_kind, "suppressed")
        return false
    var quiet_mode := AppState.is_quiet_hours_now()
    var source_last := int(_last_auto_prompt_by_source.get(source_kind, 0))
    if not _prompt_cadence.can_emit(
        _last_auto_prompt_unix,
        now_unix,
        AppState.settings,
        quiet_mode,
        source_kind,
        source_last
    ):
        _manual_verification_report.record_prompt_metric(source_kind, "suppressed")
        return false
    _update_balloon_position()
    _buddy_say(line, source_kind)
    _last_auto_prompt_unix = now_unix
    _last_auto_prompt_by_source[source_kind] = now_unix
    _prompt_cadence.note_emit(now_unix, source_kind)
    _manual_verification_report.record_prompt_metric(source_kind, "shown")
    return true


func _flush_deferred_world_prompt(now_unix: int) -> void:
    if _deferred_world_prompt.is_empty():
        return
    if _is_dnd_active(now_unix):
        return
    var quiet_mode := AppState.is_quiet_hours_now()
    var source_last := int(_last_auto_prompt_by_source.get("world", 0))
    if _prompt_cadence.can_emit(
        _last_auto_prompt_unix,
        now_unix,
        AppState.settings,
        quiet_mode,
        "world",
        source_last
    ):
        var queued: Dictionary = _deferred_world_prompt.duplicate(true)
        _deferred_world_prompt.clear()
        _show_world_prompt(queued)


func _export_manual_verification_snapshot(announce_in_chat: bool = true) -> Dictionary:
    var now_unix := int(Time.get_unix_time_from_system())
    var snapshot := _manual_verification_report.build_snapshot(
        AppState.settings,
        AppState.get_telemetry_snapshot(),
        AppState.get_world_snapshot(),
        now_unix,
        _last_auto_prompt_unix,
        not _deferred_world_prompt.is_empty()
    )
    var user_dir := "user://manual_verification"
    var absolute_dir := ProjectSettings.globalize_path(user_dir)
    var mkdir_code := DirAccess.make_dir_recursive_absolute(absolute_dir)
    if mkdir_code != OK:
        if announce_in_chat:
            _update_balloon_position()
            _buddy_say("Snapshot export failed (mkdir).")
        return {"ok": false, "reason": "mkdir"}
    var dt := Time.get_datetime_dict_from_unix_time(now_unix)
    var filename := "plan5_snapshot_%04d%02d%02d_%02d%02d%02d.json" % [
        int(dt.get("year", 1970)),
        int(dt.get("month", 1)),
        int(dt.get("day", 1)),
        int(dt.get("hour", 0)),
        int(dt.get("minute", 0)),
        int(dt.get("second", 0)),
    ]
    var user_path := "%s/%s" % [user_dir, filename]
    var file := FileAccess.open(user_path, FileAccess.WRITE)
    if file == null:
        if announce_in_chat:
            _update_balloon_position()
            _buddy_say("Snapshot export failed (write).")
        return {"ok": false, "reason": "write"}
    file.store_string(JSON.stringify(snapshot, "\t"))
    file.close()
    if announce_in_chat:
        _update_balloon_position()
        _buddy_say("Manual snapshot exported: %s" % user_path)
    return {"ok": true, "path": user_path, "reason": "ok"}
