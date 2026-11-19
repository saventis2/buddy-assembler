extends RefCounted

# The look of every Buddy menu window, drawn entirely in code: navy panels,
# a Maple-blue frame, blue buttons, beige item slots. Nothing here loads an
# image, so the menus look the same in a shipped build as on a dev machine.

const BODY := Color(0.10, 0.13, 0.21)
const BODY_RAISED := Color(0.14, 0.18, 0.28)
const FRAME := Color(0.36, 0.60, 0.90)
const FRAME_DIM := Color(0.23, 0.34, 0.52)
const TEXT := Color(0.96, 0.92, 0.82)
const TEXT_DIM := Color(0.66, 0.70, 0.78)
const HEADING := Color(1.0, 0.84, 0.42)
const BUTTON := Color(0.20, 0.40, 0.68)
const BUTTON_HOVER := Color(0.27, 0.50, 0.82)
const BUTTON_PRESSED := Color(0.14, 0.30, 0.54)
const BUTTON_DISABLED := Color(0.18, 0.21, 0.28)
const DANGER := Color(0.62, 0.24, 0.24)
const DANGER_HOVER := Color(0.76, 0.30, 0.30)
const SLOT := Color(0.87, 0.84, 0.76)
const SLOT_BORDER := Color(0.55, 0.52, 0.45)
const SELECTION := Color(1.0, 0.78, 0.30)

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func flat(fill: Color, border: Color, radius: int = 5, border_width: int = 1, pad_x: int = 10, pad_y: int = 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


# The backdrop behind a whole window.
static func window_panel() -> StyleBoxFlat:
	return flat(BODY, FRAME, 0, 2, 0, 0)


# A lighter inset area that groups related controls.
static func section_panel() -> StyleBoxFlat:
	return flat(BODY_RAISED, FRAME_DIM, 6, 1, 10, 8)


static func slot(selected: bool = false) -> StyleBoxFlat:
	return flat(SLOT, SELECTION if selected else SLOT_BORDER, 3, 2 if selected else 1, 2, 2)


# Recolours one button for an action that cannot be undone.
static func make_danger(button: Button) -> void:
	button.add_theme_stylebox_override("normal", flat(DANGER, DANGER_HOVER))
	button.add_theme_stylebox_override("hover", flat(DANGER_HOVER, TEXT))
	button.add_theme_stylebox_override("pressed", flat(DANGER.darkened(0.2), DANGER_HOVER))


static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING)
	label.add_theme_font_size_override("font_size", 15)
	return label


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	t.set_stylebox("normal", "Button", flat(BUTTON, FRAME))
	t.set_stylebox("hover", "Button", flat(BUTTON_HOVER, TEXT))
	t.set_stylebox("pressed", "Button", flat(BUTTON_PRESSED, FRAME))
	t.set_stylebox("disabled", "Button", flat(BUTTON_DISABLED, FRAME_DIM))
	t.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), SELECTION, 5, 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.25))

	for kind in ["OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.set_stylebox(state, kind, t.get_stylebox(state, "Button"))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2, 2))

	var field := flat(Color(0.06, 0.08, 0.13), FRAME_DIM, 4, 1, 8, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", flat(Color(0.06, 0.08, 0.13), FRAME, 4, 2, 8, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", TEXT)

	t.set_stylebox("panel", "PanelContainer", section_panel())
	t.set_stylebox("panel", "Panel", window_panel())

	t.set_stylebox("panel", "ItemList", flat(Color(0.06, 0.08, 0.13), FRAME_DIM, 4, 1, 4, 4))
	t.set_stylebox("focus", "ItemList", flat(Color(0, 0, 0, 0), FRAME, 4, 1, 4, 4))
	t.set_stylebox("selected", "ItemList", flat(BUTTON, SELECTION, 3, 1, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", flat(BUTTON_HOVER, SELECTION, 3, 1, 4, 2))
	t.set_stylebox("hovered", "ItemList", flat(BODY_RAISED, FRAME_DIM, 3, 1, 4, 2))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.05, 0.06, 0.10, 0.97), SELECTION, 4, 1, 8, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_stylebox("panel", "PopupMenu", flat(BODY_RAISED, FRAME, 4, 1, 6, 6))
	t.set_stylebox("hover", "PopupMenu", flat(BUTTON_HOVER, FRAME, 3, 0, 4, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	t.set_stylebox("slider", "HSlider", flat(Color(0.06, 0.08, 0.13), FRAME_DIM, 3, 1, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", flat(BUTTON, BUTTON, 3, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(BUTTON_HOVER, BUTTON_HOVER, 3, 0, 0, 3))

	var scroll := flat(Color(0.06, 0.08, 0.13), Color(0, 0, 0, 0), 4, 0, 4, 4)
	var grabber := flat(FRAME_DIM, Color(0, 0, 0, 0), 4, 0, 4, 4)
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", kind, scroll)
		t.set_stylebox("grabber", kind, grabber)
		t.set_stylebox("grabber_highlight", kind, flat(FRAME, Color(0, 0, 0, 0), 4, 0, 4, 4))
		t.set_stylebox("grabber_pressed", kind, flat(FRAME, Color(0, 0, 0, 0), 4, 0, 4, 4))
	return t
