# Addendum: the kit re-copied from the re-cut v1.105.0 tag

Written after this bundle was recorded, which stays as it was. During the run's re-vendor sweep,
LootHistory's leak gate showed that the first cut of kit revision 57 (tag commit `79b1d9c`)
added two closures to every mock frame. LibKa0s `LK-FIX-1` (`8209c104`) moved the frame hold
into the frame stub's own methods, and the local tag `v1.105.0` was re-cut there.

- Re-copied: `tests/_kit/mock_base.lua` and `tests/_kit/mock_events.lua`, from the re-cut tag.
  Nothing else in either payload differs between the two tag commits, and the kit revision stays 57.
- Gate after the re-copy: retail: 1678 passed, 0 failed, 1 skipped, 1679 total; luacheck `0 warnings / 0 errors in 158 files`.
- Item `RV-KC` of Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/`.
