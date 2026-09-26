# Summary (KickCD)

LibKa0s v1.61.0 -> v1.62.0 from the local tag (`5dc9f5d`): Options 25 -> 26, OptionsWidgets 31 -> 32,
OptionsTabs 5 -> 6, and four new files at minor 1 (OptionsRegistry, OptionsIds, OptionsIdList,
OptionsCombat); Options key `26.1.32.1.1.6.1.7.4.1`. `tests/_kit` moves from kit revision 27 to 31,
with three new files (`inventory.lua`, `prose_coverage.lua`, `prose_selftests.lua`) and the runner
fixes for ATS-20 and ATS-21. Both content diffs are empty after the copy, and nothing was deleted. No
blockers, no candidates, no adoption.

Host changes: the `CLAUDE.md` provenance line and `docs/testing.md`'s version-now line roll to
v1.62.0, and the descriptor-L tripwire counts the Options major's ten files. `docs/test-cases.md` is
already in sync with `lua tests/run.lua --list` (no case added, removed or renamed), so it and the
README `Tests` badge do not move.

Gate after the copy:

- tests: 1201 passed, 0 failed, 0 skipped, 1201 total (1201 before the copy)
- luacheck: 0 warnings / 0 errors in 111 files
- lizard (`-x ./libs/* -x ./tests/_kit/*`, CCN 15): 0 warnings
- no authored file over 1500 lines (largest source: `modules/Castbar.lua`, 1440)
