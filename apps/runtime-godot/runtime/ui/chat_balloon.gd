extends Node2D
class_name ChatBalloon

# MapleStory-style 9-slice chat balloon assembled from UI.wz/ChatBalloon.img/0
# (nw/n/ne/w/c/e/sw/s/se + arrow). Draws above the actor's head; text is
# centered inside the bubble with a small padding.

const TEX_ROOT := "res://content/core_pack/ui/chat_balloon/"
const CORNER_PX := 6
const CENTER_UNIT_W := 12   # c, n, s tile width
const CENTER_UNIT_H := 14   # c, e, w tile height
const ARROW_SIZE := 13
const PAD_X := 6
const PAD_Y := 3
const MIN_INNER_W := 24
const MIN_INNER_H := 12
const MAX_INNER_W := 220
const FONT_SIZE := 10

var _text: String = ""
var _visible_text: bool = false

var _tex_nw: Texture2D
var _tex_n: Texture2D
var _tex_ne: Texture2D
var _tex_w: Texture2D
var _tex_c: Texture2D
var _tex_e: Texture2D
var _tex_sw: Texture2D
var _tex_s: Texture2D
var _tex_se: Texture2D
var _tex_arrow: Texture2D


func _ready() -> void:
	# Load via Image rather than ResourceLoader — these PNGs are copied
	# directly from WZ and don't have Godot .import metadata.
	_tex_nw = _load_tex("nw.png")
	_tex_n = _load_tex("n.png")
	_tex_ne = _load_tex("ne.png")
	_tex_w = _load_tex("w.png")
	_tex_c = _load_tex("c.png")
	_tex_e = _load_tex("e.png")
	_tex_sw = _load_tex("sw.png")
	_tex_s = _load_tex("s.png")
	_tex_se = _load_tex("se.png")
	_tex_arrow = _load_tex("arrow.png")


func _load_tex(file_name: String) -> Texture2D:
	var res_path := TEX_ROOT + file_name
	var fs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(fs_path):
		return null
	var img := Image.new()
	if img.load(fs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)


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
	if _tex_c == null or _tex_arrow == null:
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
	var outer_w: int = inner_w + CORNER_PX * 2
	var outer_h: int = inner_h + CORNER_PX * 2

	# Bubble sits above the anchor (local origin) with the arrow pointing
	# down at it. Leave ARROW_SIZE between the bubble bottom and origin.
	var top_left_x: int = -int(outer_w / 2)
	var top_left_y: int = -outer_h - ARROW_SIZE

	# Corners
	draw_texture(_tex_nw, Vector2(top_left_x, top_left_y))
	draw_texture(_tex_ne, Vector2(top_left_x + outer_w - CORNER_PX, top_left_y))
	draw_texture(_tex_sw, Vector2(top_left_x, top_left_y + outer_h - CORNER_PX))
	draw_texture(_tex_se, Vector2(top_left_x + outer_w - CORNER_PX, top_left_y + outer_h - CORNER_PX))

	# Edges — tiled via draw_texture_rect(tile=true).
	draw_texture_rect(
		_tex_n,
		Rect2(top_left_x + CORNER_PX, top_left_y, inner_w, CORNER_PX),
		true
	)
	draw_texture_rect(
		_tex_s,
		Rect2(top_left_x + CORNER_PX, top_left_y + outer_h - CORNER_PX, inner_w, CORNER_PX),
		true
	)
	draw_texture_rect(
		_tex_w,
		Rect2(top_left_x, top_left_y + CORNER_PX, CORNER_PX, inner_h),
		true
	)
	draw_texture_rect(
		_tex_e,
		Rect2(top_left_x + outer_w - CORNER_PX, top_left_y + CORNER_PX, CORNER_PX, inner_h),
		true
	)
	# Center fill
	draw_texture_rect(
		_tex_c,
		Rect2(top_left_x + CORNER_PX, top_left_y + CORNER_PX, inner_w, inner_h),
		true
	)

	# Arrow centered below bubble, pointing at actor head.
	var arrow_pos := Vector2(-int(ARROW_SIZE / 2), -ARROW_SIZE)
	draw_texture(_tex_arrow, arrow_pos)

	# Text — wrapped inside inner area.
	var text_x: int = top_left_x + CORNER_PX + PAD_X
	var ascent: float = maxf(1.0, font.get_ascent(FONT_SIZE))
	var text_y: float = float(top_left_y + CORNER_PX + PAD_Y) + ascent
	for i in range(wrapped_lines.size()):
		draw_string(
			font,
			Vector2(text_x, text_y + (line_h * i)),
			wrapped_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			FONT_SIZE,
			Color(0.05, 0.05, 0.05, 1.0)
		)


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
