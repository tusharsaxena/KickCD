# Summary (KickCD)

LibKa0s v1.70.0 -> v1.71.0 from the local annotated tag (`cb274a4`, via `git archive`). The base
comes from the CLAUDE.md provenance line and matches the payload bytes, so there is no base
correction. Six library files moved (WidgetsLineChart 3, WidgetsAutocomplete 2, Slash 20 /
SlashParse 2, Env 2, OptionsIdList 4); no file was added or removed and no floor rose. The kit moves
from revision 37 to 38 (`framework.lua`, `inventory.lua`, `README.md`, new `secrets.lua`).

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls v1.70.0 -> v1.71.0;
- `docs/testing.md`'s version-now sentence is de-tagged: it no longer names the tag `../LibKa0s`
  sits on, and states instead that the checkout and the CLAUDE.md tag agree only between a
  re-vendor and the library's next tag, so it cannot go stale on the next re-vendor (`KC-A-01`);
- `docs/test-cases.md` is regenerated with `lua tests/run.lua --list` (`KC-A-07`);
- `tests/test_list_mode.lua`'s Totals case follows the kit 38 contract (the one mechanical blocker,
  `01_DELTA.md` "Blockers");
- the span bundle `../2026-10-07-v1.69.0-v1.70.0/` records the two unrecorded re-vendors (`KC-A-01`).

- **Delivered free (class A):** Slash `ParseValue` refuses non-finite numbers on `/kcd set`; the kit
  38 Totals put the inventory Total equal to the badge with a `Skipped` row; Env and OptionsIdList
  drop their dead bare-global rungs.
- **Adoption candidates:** `Kit.secret` and the opt-in `issecretvalue` installer, LineChart
  clipping/hover, the Autocomplete re-hook guard. Each **not adopted in this run** (owner scope
  ruling 5).
- **Adopted:** none. **Declined:** none, so no issue filed. **Unreached:** none.

Gate after the copy:

- tests (`ka0s-bounded lua5.1 tests/run.lua`): 1302 passed, 0 failed, 1 skipped, 1303 total.
- `docs/test-cases.md`: `| Skipped | 1 |`, `| **Total** | **1302** |`, equal to the README badge
  (1302/1302), which does not move.
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 127 files.
- lizard (`-x "./libs/*" -x "./tests/_kit/*"`, `-C 15 -w`): no function above CCN 15.
- 1500-line cap: largest authored `.lua` is `modules/IconGrid.lua` at 996 lines.
- both payloads `diff -r` clean against the tag after the copy; `tests/_kit/run-automated-tests.sh`
  stays executable.
