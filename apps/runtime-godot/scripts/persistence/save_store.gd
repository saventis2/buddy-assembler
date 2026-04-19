extends RefCounted


static func read_json(path: String, fallback: Dictionary) -> Dictionary:
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return fallback.duplicate(true)

    var raw := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return fallback.duplicate(true)

    return parsed


static func write_json(path: String, data: Dictionary) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data, "  "))
    file.flush()
    file.close()
    return true

