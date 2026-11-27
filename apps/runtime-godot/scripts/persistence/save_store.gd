extends RefCounted

# Durable JSON save/settings layer for the buddy runtime.
#
# Guarantees:
#  * Atomic writes — write to "<path>.tmp" then rename. A crash mid-write
#    cannot corrupt the previous good file.
#  * Corruption recovery — a file that fails to open or parse is renamed
#    to "<path>.corrupt-<unix>.<reason>" (quarantined) and defaults are
#    returned so startup cannot be bricked by a bad save.
#  * Forward-version guard — a save whose schemaVersion is NEWER than
#    the runtime knows how to handle is quarantined rather than merged
#    (silently merging newer shapes is how subtle corruption starts).
#  * Backups: `backup_files` copies saves to a dated folder that is never overwritten.
#  * Migration hook — `load_versioned` runs a caller-supplied migrator
#    map to step an older save up to the current version before merge.
#
# See apps/runtime-godot/tests/save_store_test.gd for the test matrix.

const SCHEMA_VERSION_KEY := "schemaVersion"


static func read_json(path: String, fallback: Dictionary) -> Dictionary:
    # Legacy entrypoint — kept for compatibility. Prefer `load_versioned`
    # for anything with a schemaVersion field.
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("save_store: cannot open %s (err %d); quarantining" % [path, FileAccess.get_open_error()])
        _quarantine(path, "open_failed")
        return fallback.duplicate(true)

    var raw := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("save_store: %s is not a JSON object; quarantining" % path)
        _quarantine(path, "bad_json")
        return fallback.duplicate(true)

    return parsed


static func write_json(path: String, data: Dictionary) -> bool:
    # Atomic: write to "<path>.tmp" and rename over the target.
    var tmp_path := path + ".tmp"

    var dir_path := path.get_base_dir()
    if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
        DirAccess.make_dir_recursive_absolute(dir_path)

    var file := FileAccess.open(tmp_path, FileAccess.WRITE)
    if file == null:
        push_error("save_store: cannot open %s for write (err %d)" % [tmp_path, FileAccess.get_open_error()])
        return false
    file.store_string(JSON.stringify(data, "  "))
    file.flush()
    file.close()

    # Remove any previous target then rename. DirAccess.rename does not
    # guarantee overwrite on Windows, so remove-then-rename.
    # On Windows, AV/indexers can briefly lock the target; retry a few times.
    var attempts := 20
    for i in range(attempts):
        if FileAccess.file_exists(path):
            var rm := DirAccess.remove_absolute(path)
            if rm != OK and rm != ERR_FILE_NOT_FOUND:
                if i == attempts - 1:
                    push_error("save_store: cannot remove old %s (err %d)" % [path, rm])
                    return false
                OS.delay_msec(50)
                continue
        var rename_err := DirAccess.rename_absolute(tmp_path, path)
        if rename_err == OK:
            return true
        if i < attempts - 1:
            OS.delay_msec(50)
            continue
        push_error("save_store: cannot rename %s -> %s (err %d)" % [tmp_path, path, rename_err])
        return false
    return false


# Copies the given files into a new folder "<backup_root>/<label>" and returns
# that folder, or "" if anything failed. A backup is never overwritten: if the
# folder exists, "<label>-2", "<label>-3" and so on are used. Files that do not
# exist are skipped. Every copy is checked against its original.
static func backup_files(paths: Array, backup_root: String, label: String) -> String:
    var folder := "%s/%s" % [backup_root, label]
    var suffix := 2
    while DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder):
        folder = "%s/%s-%d" % [backup_root, label, suffix]
        suffix += 1
    var made := DirAccess.make_dir_recursive_absolute(folder)
    if made != OK:
        push_error("save_store: cannot create backup folder %s (err %d)" % [folder, made])
        return ""
    for path_variant in paths:
        var path := str(path_variant)
        if not FileAccess.file_exists(path):
            continue
        var dest := "%s/%s" % [folder, path.get_file()]
        var err := DirAccess.copy_absolute(path, dest)
        if err != OK or not FileAccess.file_exists(dest) or FileAccess.get_md5(dest) != FileAccess.get_md5(path):
            push_error("save_store: cannot back up %s to %s (err %d)" % [path, dest, err])
            return ""
    return folder


static func load_versioned(
    path: String,
    default_factory: Callable,
    current_version: int,
    migrators: Dictionary
) -> Dictionary:
    # `migrators` maps int(from_version) -> Callable(Dictionary) -> Dictionary.
    # Each migrator returns the dict shaped for from_version + 1.
    var defaults: Dictionary = default_factory.call()

    if not FileAccess.file_exists(path):
        return defaults

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("save_store: cannot open %s (err %d); quarantining" % [path, FileAccess.get_open_error()])
        _quarantine(path, "open_failed")
        return defaults

    var raw := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("save_store: %s is not a JSON object; quarantining" % path)
        _quarantine(path, "bad_json")
        return defaults

    var data: Dictionary = parsed
    var loaded_version := int(data.get(SCHEMA_VERSION_KEY, 1))

    if loaded_version > current_version:
        push_warning(
            "save_store: %s has schemaVersion %d > runtime %d; quarantining" %
            [path, loaded_version, current_version]
        )
        _quarantine(path, "newer_than_runtime")
        return defaults

    while loaded_version < current_version:
        if not migrators.has(loaded_version):
            push_warning(
                "save_store: no migrator from v%d for %s; quarantining" %
                [loaded_version, path]
            )
            _quarantine(path, "no_migrator_v%d" % loaded_version)
            return defaults
        var migrator: Callable = migrators[loaded_version]
        data = migrator.call(data)
        loaded_version += 1
        data[SCHEMA_VERSION_KEY] = loaded_version

    # Fill any newly-introduced default keys that migrators did not set.
    var merged := defaults.duplicate(true)
    for key in data.keys():
        merged[key] = data[key]
    merged[SCHEMA_VERSION_KEY] = current_version
    return merged


static func peek_versioned(
    path: String,
    default_factory: Callable,
    current_version: int,
    migrators: Dictionary
) -> Dictionary:
    # Like `load_versioned`, but never quarantines, renames or writes anything.
    # Returns {} for a missing, unreadable, unparseable, newer-than-runtime or
    # unmigratable file, so a process that does not own the file keeps what it had.
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var raw := file.get_as_text()
    file.close()
    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var data: Dictionary = parsed
    var loaded_version := int(data.get(SCHEMA_VERSION_KEY, 1))
    if loaded_version > current_version:
        return {}
    while loaded_version < current_version:
        if not migrators.has(loaded_version):
            return {}
        var migrator: Callable = migrators[loaded_version]
        data = migrator.call(data)
        loaded_version += 1
        data[SCHEMA_VERSION_KEY] = loaded_version
    var defaults: Dictionary = default_factory.call()
    var merged := defaults.duplicate(true)
    for key in data.keys():
        merged[key] = data[key]
    merged[SCHEMA_VERSION_KEY] = current_version
    return merged


static func _quarantine(path: String, reason: String) -> void:
    if not FileAccess.file_exists(path):
        return
    var stamp := int(Time.get_unix_time_from_system())
    var dest := "%s.corrupt-%d.%s" % [path, stamp, reason]
    var err := DirAccess.rename_absolute(path, dest)
    if err != OK:
        push_error("save_store: cannot quarantine %s -> %s (err %d)" % [path, dest, err])
