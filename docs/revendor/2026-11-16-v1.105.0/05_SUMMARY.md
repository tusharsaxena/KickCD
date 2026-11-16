# 05 Summary

- Tag moved v1.93.0 -> v1.105.0 (local tag, commit 79b1d9c4), base taken from the CLAUDE.md provenance line. Kit revision 53 -> 57. Files that moved a minor: see 01_DELTA.md 3b/3c.
- Span bundle: none owed. Base correction: none.
- Delivered for free (class A): skin color floors (#82, #84), header marks on library windows (#86), the console footer and plain Copy (#79, #90), library tooltips through the placers (#92 part B), the sim panel default title (#78), the slider junk fix.
- Contract blockers: none.
- LibKa0s icons: line kept as written (14 names, `settings` already present). Prune: kept 15 files (14 Open Iconic icons and the license), removed 5825 icon files and 362 sound files (no `LibKa0s sounds:` line). Provenance split: none. README credits unchanged (Open Iconic only, as before). Dead stub mirrors: none.
- Fixes in the re-vendor commit, all made because the gate went red after the copy:
  - core/DebugLogSetup.lua: the library-absent DebugLog stub gains `Report` (streams the report to chat, no pointer, answers the line count) and `Serialize` (one line), in the shape the DebugLog 23.11.1.5 API document gives.
  - settings/OptionsSetup.lua: the Options stub's no-op list gains `SideTabs` (OptionsNav 7, v1.100.0).
  - tests/test_surface_parity.lua: the Compat case records the four character-identity readers of Compat 4 (v1.94.0), `CharacterKey`, `RealmKey`, `RegionalNames` and `UnitCharacterName`, as members this host does not wire, with the reason. This is the decision the case's own header asks for ("a member the major gains later ... fails here until the host decides").
  - tests/test_options_panel.lua: the Options major's file count pin moves 21 -> 22 (OptionsSkinPickerQueue, v1.105.0); the per-file `d.L` scan still covers every file.
  - docs/test-cases.md regenerated and the README Tests badge moved 1675 -> 1678. Both had been left behind when `test_client_globals.lua` joined at the v1.93.0 re-vendor; the count did not move in this commit.
- Adopted: nothing. Declined: nothing. Owed in phase [3]: LibKa0s#79, #88, #92 (sites in 02_CANDIDATES.md); #86, #87, #89 checked, no host site today.
- Gate (Retail-only addon, `## Interface: 120105`): `ka0s-bounded lua tests/run.lua` default and `KA0S_KIT_CLIENT=retail` both 1678 passed, 0 failed, 1 skipped (1679); before the fixes 1674 passed, 4 failed. `ka0s-bounded luacheck .` 0 warnings / 0 errors in 158 files. Largest host file 1057 lines (tests/test_schema.lua), under the 1500 cap.
