extends Node

# Idle burn-in profiler. Spawns one BuddyActor, lets it sit idle for
# DURATION_SECONDS, then writes a summary (frame-time + memory) to
# user://perf/idle_profile_<unix>.log and exits.
#
# Duration can be overridden via CLI:
#   godot --headless --path . res://tests/IdleProfile.tscn -- --duration=600
#
# Use the PowerShell wrapper `tests/run_burn_in.ps1` for the standard
# 10-min and multi-hour recipes.

const BuddyActorScene = preload("res://scenes/vertical_slice/BuddyActor.tscn")
const DEFAULT_DURATION := 60
const WARMUP_FRAMES := 30
const SAMPLE_INTERVAL_SECONDS := 5.0

var _frame_deltas: Array[float] = []
var _mem_samples: Array[int] = []
var _duration_seconds: int = DEFAULT_DURATION
var _elapsed := 0.0
var _warmup_remaining := WARMUP_FRAMES
var _next_sample_at := 0.0
var _log_lines: Array[String] = []


func _ready() -> void:
    _duration_seconds = _parse_duration_arg()
    _log("idle_profile: spawning 1 actor; duration=%d s" % _duration_seconds)
    var actor: CharacterBody2D = BuddyActorScene.instantiate()
    add_child(actor)
    actor.global_position = Vector2(200.0, 200.0)
    _next_sample_at = SAMPLE_INTERVAL_SECONDS


func _process(delta: float) -> void:
    if _warmup_remaining > 0:
        _warmup_remaining -= 1
        return
    _frame_deltas.append(delta)
    _elapsed += delta
    if _elapsed >= _next_sample_at:
        _sample_memory()
        _next_sample_at += SAMPLE_INTERVAL_SECONDS
    if _elapsed >= float(_duration_seconds):
        _report_and_exit()


func _sample_memory() -> void:
    var bytes := int(OS.get_static_memory_usage())
    _mem_samples.append(bytes)
    _log("sample t=%.1fs mem=%d KB frames=%d"
        % [_elapsed, bytes / 1024, _frame_deltas.size()])


func _report_and_exit() -> void:
    if _frame_deltas.is_empty():
        _log("idle_profile: no frames recorded")
        _flush(false)
        get_tree().quit(1)
        return

    var total := 0.0
    var min_dt := _frame_deltas[0]
    var max_dt := _frame_deltas[0]
    for dt in _frame_deltas:
        total += dt
        if dt < min_dt: min_dt = dt
        if dt > max_dt: max_dt = dt
    var avg_dt := total / float(_frame_deltas.size())

    var mem_min := _mem_samples[0] if not _mem_samples.is_empty() else 0
    var mem_max := mem_min
    for m in _mem_samples:
        if m < mem_min: mem_min = m
        if m > mem_max: mem_max = m

    _log("")
    _log("=== Idle burn-in report ===")
    _log("Duration:   %d s" % _duration_seconds)
    _log("Frames:     %d" % _frame_deltas.size())
    _log("Min dt:     %.2f ms (%.1f fps)" % [min_dt * 1000.0, 1.0 / max(min_dt, 0.0001)])
    _log("Max dt:     %.2f ms (%.1f fps)" % [max_dt * 1000.0, 1.0 / max(max_dt, 0.0001)])
    _log("Avg dt:     %.2f ms (%.1f fps)" % [avg_dt * 1000.0, 1.0 / max(avg_dt, 0.0001)])
    _log("Mem min:    %d KB" % (mem_min / 1024))
    _log("Mem max:    %d KB" % (mem_max / 1024))
    _log("Mem drift:  %d KB" % ((mem_max - mem_min) / 1024))
    _log("===========================")

    _flush(true)
    get_tree().quit(0)


func _parse_duration_arg() -> int:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--duration="):
            var val := arg.substr("--duration=".length()).to_int()
            if val > 0:
                return val
    return DEFAULT_DURATION


func _log(line: String) -> void:
    print(line)
    _log_lines.append(line)


func _flush(ok: bool) -> void:
    var dir := "user://perf"
    DirAccess.make_dir_recursive_absolute(dir)
    var stamp := str(Time.get_unix_time_from_system())
    var path := "%s/idle_profile_%s%s.log" % [dir, stamp, "" if ok else ".fail"]
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("idle_profile: could not write %s" % path)
        return
    for line in _log_lines:
        f.store_line(line)
    f.close()
    print("idle_profile: wrote %s" % path)
