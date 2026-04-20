# V1 Launch Docs + Exit Criteria

**PR:** PR-15  
**Date:** 2026-04-20  
**Status:** READY FOR RELEASE REHEARSAL (NOT YET TAGGED)

---

## V1 Exit Criteria

All criteria must be satisfied before the V1 tag is cut. Final tag/no-tag
authority is `RELEASE_CHECKLIST.md`.

### Functionality

| Criterion | Gate PR | Status |
|-----------|---------|--------|
| Buddy runs on Windows 11, stays on top, draggable, floor-locked | PR-00 | ✅ |
| Settings/profile persisted under `user://`; corruption recovery | PR-03 | ✅ |
| Pack validation + runtime fallback cascade | PR-04 | ✅ |
| RC scenario suite passes (9 scenarios) | PR-05 | ✅ |
| First-run welcome tooltip shows once | PR-08 | ✅ |
| Bond cadence (idle phrases per tier) | PR-09 | ✅ |
| Sleep immune to tick; drag returns to idle in 0.5 s | PR-10 | ✅ |
| `core_pack` 1.0.0 ship-ready; all 7 actions covered | PR-11 | ✅ |
| Non-Maple pack validates and loads | PR-14 | ✅ |

### Engineering

| Criterion | Gate PR | Status |
|-----------|---------|--------|
| CI: parse + headless smoke + Windows export pass on main | PR-02a | ✅ |
| Perf baseline captured (avg frame, mem drift) | PR-06 | ✅ |
| Windows export artifact + SHA256SUMS generated in CI | PR-07 | ✅ |
| `CONTENT_SCHEMA_VERSION = 1`; future packs rejected cleanly | PR-12 | ✅ |
| `core_pack` provenance manifest + promotion procedure | PR-13 | ✅ |

### IP / Provenance

| Criterion | Status |
|-----------|--------|
| No WZ/NX binaries committed | ✅ |
| All derived assets have provenance notes in `PROVENANCE.md` | ✅ |
| Runtime has zero WZ/NX awareness | ✅ |

---

## Temporary Maple83 dependency (accepted for current phase)

Current implementation intentionally uses MapleStory v83-derived references
and assets from local extracted folders for content/runtime behavior while V1
stabilizes.

Guardrails:

- This dependency is accepted for the current release phase and should not be
  broken by cleanup PRs.
- No proprietary WZ/NX binaries are committed to this repo.
- Provenance/transformation notes remain mandatory (`PROVENANCE.md`).
- Replacement of Maple83 dependency remains planned and must be executed as a
  scoped follow-up with explicit migration steps.

---

## Known Issues (ship-with)

These are known at V1 ship but do not block release:

1. **SmartScreen warning** — Windows may show an "Unknown publisher" warning on first run. User must click "More info → Run anyway". Path is documented in `docs/product/PACKAGING.md`. Deferred: code signing.
2. **No auto-update** — Users must re-download to update. Deferred post-V1.
3. **Perf baseline table** — `docs/product/PERF_BASELINE.md` baseline table is populated at release rehearsal, not before. CI flags if avg frame > 16 ms.
4. **Sleep Zz balloon** — Not in Effect.wz; deferred per `DEFERRED.md`.
5. **`hit` action** — No in-game source for damage events; deferred.

---

## Support / Debug

### Log locations

- Runtime logs: `user://` directory (Windows: `%APPDATA%\Roaming\Godot\app_userdata\Buddy Runtime\`)
- Perf profiles: `user://perf/idle_profile_<unix>.log`

### Debug keys (in running app)

| Key | Action |
|-----|--------|
| F6 | Toggle telemetry overlay |
| F7 | Cycle event frequency (off / low / normal / high) |
| F8 | Move to next monitor |
| F9 | Cycle content pack |
| F10 | Toggle emote debug panel |
| 1–0 | Trigger specific face emote |

### Common problems

**Buddy doesn't appear**
: Check that `BuddyRuntime.exe` and `BuddyRuntime.pck` are in the same directory.

**SmartScreen blocks launch**
: Click "More info" → "Run anyway". See `docs/product/PACKAGING.md`.

**Save file corrupted**
: Delete or rename the file under `user://`. The runtime regenerates defaults on next launch (PR-03 guarantees safe recovery).

**Wrong monitor**
: Press F8 to cycle to the next monitor. Position is saved on drag-release.

---

## Deferred Roadmap

The following scope is explicitly post-V1. See `DEFERRED.md` for the full list.

- Code signing / notarization
- Auto-update channel
- Cloud save
- Multi-character world simulation
- Free-form AI chat
- Cross-platform (macOS, Linux)
- Marketplace / user content hosting
- Combat actions (`hit`, `shoot1`)
- Sleep Zz balloon overlay

---

## Sign-off

V1 is ready to tag when:
1. `RELEASE_CHECKLIST.md` has no unchecked release gates.
2. RC scenario suite has been run against the **exported Windows build**
   (not editor) with recorded results.
3. SHA256SUMS artifact is verified for the final candidate build.
4. Previous known-good tag is recorded as rollback pointer.
