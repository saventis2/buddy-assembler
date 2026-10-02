extends Node2D
class_name ChatBalloon

signal bubble_drawn(bounds: Rect2, line_count: int)

# Generic repository-owned chat balloon. The body and pointer are drawn with
# Godot primitives so packaged speech does not depend on excluded UI artwork.

const EDGE_PX := 6
const BORDER_PX := 2
const CORNER_RADIUS_PX := 6
const ARROW_WIDTH := 14
const ARROW_HEIGHT := 10
const PAD_X := 6
const PAD_Y := 3
const MIN_INNER_W := 24
const MIN_INNER_H := 12
const MAX_INNER_W := 220
const FONT_SIZE := 10
const BUBBLE_FILL := Color(0.98, 0.96, 0.88, 0.98)
const BUBBLE_BORDER := Color(0.14, 0.12, 0.10, 1.0)
const TEXT_COLOR := Color(0.05, 0.05, 0.05, 1.0)

var _text: String = ""
var _visible_text: bool = false


func show_text(text: String) -> void:
	_text = text
	_visible_text = true
	queue_redraw()


func hide_bubble() -> void:
	_visible_text = false
	queue_redraw()


func _draw() -> void:
	if not _visible_text or _text == "":
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var wrapped_lines := _wrap_lines(font, _text, MAX_INNER_W - PAD_X * 2)
	if wrapped_lines.is_empty():
		wrapped_lines.append("")
	var line_h := maxf(1.0, font.get_height(FONT_SIZE))
	var max_line_w := 0.0
	for line in wrapped_lines:
		var line_w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
		if line_w > max_line_w:
			max_line_w = line_w

	var inner_w: int = clampi(max(MIN_INNER_W, int(ceil(max_line_w)) + PAD_X * 2), MIN_INNER_W, MAX_INNER_W)
	var text_block_h := line_h * wrapped_lines.size()
	var inner_h: int = max(MIN_INNER_H, int(ceil(text_block_h)) + PAD_Y * 2)
	var outer_w: int = inner_w + EDGE_PX * 2
	var outer_h: int = inner_h + EDGE_PX * 2

	# Bubble sits above the anchor (local origin) with the arrow pointing
	# down at it. Leave ARROW_HEIGHT between the bubble bottom and origin.
	var top_left_x: int = -int(outer_w / 2)
	var top_left_y: int = -outer_h - ARROW_HEIGHT
	var bubble_rect := Rect2(top_left_x, top_left_y, outer_w, outer_h)
	draw_style_box(_bubble_style(), bubble_rect)
	_draw_arrow(float(top_left_y + outer_h))

	# Text — wrapped inside inner area.
	var text_x: int = top_left_x + EDGE_PX + PAD_X
	var ascent: float = maxf(1.0, font.get_ascent(FONT_SIZE))
	var text_y: float = float(top_left_y + EDGE_PX + PAD_Y) + ascent
	for i in range(wrapped_lines.size()):
		draw_string(
			font,
			Vector2(text_x, text_y + (line_h * i)),
			wrapped_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			FONT_SIZE,
			TEXT_COLOR
		)
	bubble_drawn.emit(
		Rect2(top_left_x, top_left_y, outer_w, outer_h + ARROW_HEIGHT),
		wrapped_lines.size()
	)


func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_FILL
	style.border_color = BUBBLE_BORDER
	style.border_width_left = BORDER_PX
	style.border_width_top = BORDER_PX
	style.border_width_right = BORDER_PX
	style.border_width_bottom = BORDER_PX
	style.corner_radius_top_left = CORNER_RADIUS_PX
	style.corner_radius_top_right = CORNER_RADIUS_PX
	style.corner_radius_bottom_left = CORNER_RADIUS_PX
	style.corner_radius_bottom_right = CORNER_RADIUS_PX
	return style


func _draw_arrow(bubble_bottom_y: float) -> void:
	var half_width := float(ARROW_WIDTH) / 2.0
	var outer := PackedVector2Array([
		Vector2(-half_width, bubble_bottom_y - BORDER_PX),
		Vector2(half_width, bubble_bottom_y - BORDER_PX),
		Vector2.ZERO,
	])
	draw_colored_polygon(outer, BUBBLE_BORDER)
	var inner := PackedVector2Array([
		Vector2(-half_width + BORDER_PX * 1.5, bubble_bottom_y - BORDER_PX),
		Vector2(half_width - BORDER_PX * 1.5, bubble_bottom_y - BORDER_PX),
		Vector2(0.0, -BORDER_PX),
	])
	draw_colored_polygon(inner, BUBBLE_FILL)


func _wrap_lines(font: Font, text: String, max_line_px: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var paragraphs := text.split("\n", false)
	for paragraph in paragraphs:
		var raw := paragraph.strip_edges()
		if raw == "":
			lines.append("")
			continue

		var words := raw.split(" ", false)
		var current := ""
		for word in words:
			var token := word.strip_edges()
			if token == "":
				continue
			var candidate := token if current == "" else "%s %s" % [current, token]
			var candidate_w := font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
			if candidate_w <= max_line_px:
				current = candidate
				continue
			if current != "":
				lines.append(current)
				current = ""
			var split_word_lines := _split_long_word(font, token, max_line_px)
			for idx in range(split_word_lines.size()):
				var part := split_word_lines[idx]
				if idx == split_word_lines.size() - 1:
					current = part
				else:
					lines.append(part)
		if current != "":
			lines.append(current)
	return lines


func _split_long_word(font: Font, token: String, max_line_px: int) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	for i in range(token.length()):
		var c := token.substr(i, 1)
		var candidate := current + c
		var candidate_w := font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
		if candidate_w <= max_line_px or current == "":
			current = candidate
		else:
			out.append(current)
			current = c
	if current != "":
		out.append(current)
	return out
