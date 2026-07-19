extends Node

const ChatBalloonScript = preload("res://runtime/ui/chat_balloon.gd")
const SAMPLE_TEXT := "This packaged speech bubble wraps long text without legacy artwork."
const LEGACY_SOURCE_MARKERS := [
    "res://content/core_pack/ui/chat_balloon/",
    "FileAccess",
    "ImageTexture",
    "nw.png",
    "n.png",
    "ne.png",
    "w.png",
    "c.png",
    "e.png",
    "sw.png",
    "s.png",
    "se.png",
    "arrow.png",
]

var _failures: Array[String] = []
var _draw_count := 0
var _draw_bounds := Rect2()
var _draw_line_count := 0


func _ready() -> void:
    _check_legacy_dependency_removed()
    await _check_code_drawn_bubble()
    if _failures.is_empty():
        print("chat_balloon_fallback_test: PASS (code-drawn bubble and arrow)")
        get_tree().quit(0)
        return
    for failure in _failures:
        push_error("chat_balloon_fallback_test: %s" % failure)
    get_tree().quit(1)


func _check_legacy_dependency_removed() -> void:
    var source := FileAccess.get_file_as_string("res://runtime/ui/chat_balloon.gd")
    if source == "":
        _failures.append("could not inspect shipping chat balloon source")
        return
    for marker in LEGACY_SOURCE_MARKERS:
        if source.contains(marker):
            _failures.append("legacy chat balloon dependency remains: %s" % marker)


func _check_code_drawn_bubble() -> void:
    var font: Font = ThemeDB.fallback_font
    if font == null:
        _failures.append("fallback font is unavailable")
        return
    var bubble := ChatBalloonScript.new()
    var wrapped: PackedStringArray = bubble._wrap_lines(
        font,
        SAMPLE_TEXT,
        ChatBalloonScript.MAX_INNER_W - ChatBalloonScript.PAD_X * 2
    )
    if wrapped.size() < 2:
        _failures.append("sample speech did not wrap across multiple lines")

    bubble.bubble_drawn.connect(_on_bubble_drawn)
    add_child(bubble)
    bubble.show_text(SAMPLE_TEXT)
    await get_tree().process_frame
    await get_tree().process_frame
    if _draw_count < 1:
        _failures.append("code-drawn bubble did not complete a draw callback")
    if _draw_line_count < 2:
        _failures.append("draw callback did not preserve wrapped text")
    if _draw_bounds.size.x <= 0.0 or _draw_bounds.size.y <= ChatBalloonScript.ARROW_HEIGHT:
        _failures.append("draw callback produced empty bubble bounds")
    if not is_equal_approx(_draw_bounds.end.y, 0.0):
        _failures.append("code-drawn arrow does not end at the actor anchor")
    bubble.queue_free()


func _on_bubble_drawn(bounds: Rect2, line_count: int) -> void:
    _draw_count += 1
    _draw_bounds = bounds
    _draw_line_count = line_count
