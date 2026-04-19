extends RefCounted

# Central registry of persistence schemas and their migrators.
#
# When you bump a schema:
#  1. Increment the *_CURRENT_VERSION constant for that file.
#  2. Add a Callable under *_MIGRATORS keyed by the OLD version.
#     The Callable receives the old-shape Dictionary and returns the
#     dict shaped for (OLD + 1). The loader stamps the new
#     schemaVersion automatically; migrators do not need to.
#  3. Add a test case in tests/save_store_test.gd that writes a
#     fixture at the old version and verifies it loads to the new.
#
# Defaults live with the data owner (AppState) — this module is
# purely about versioning and migration.

const SETTINGS_CURRENT_VERSION := 1
const PROFILE_CURRENT_VERSION := 1
const WORLD_STATE_CURRENT_VERSION := 1

# v1 is the initial shape; no migrators yet.
const SETTINGS_MIGRATORS := {}
const PROFILE_MIGRATORS := {}
const WORLD_STATE_MIGRATORS := {}
