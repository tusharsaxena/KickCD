# Candidates (KickCD, LibKa0s v1.70.0 -> v1.71.0)

Sources: `git -C ../LibKa0s log --oneline v1.70.0..v1.71.0` (20 commits), the CHANGELOG `v1.71.0`
block, and the API documents of the majors whose minor moved:
`docs/api/Widgets/version-12.1.4.3.2-docs.md`, `docs/api/Slash/version-20.2-docs.md`,
`docs/api/Env/version-2-docs.md`, `docs/api/Options/version-28.2.34.2.4.8.1.7.4.2-docs.md` and
`docs/api/testkit/version-38-docs.md`.

Under the owner's scope ruling 5 for the 2026-10-07 remediation, re-vendoring is mechanical: every
candidate the plan does not already require is listed here as **not adopted in this run**. There is
no interview (Step 6), no `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`, and no GitHub issue is filed.

## A. Delivered on the re-vendor alone (not offered)

- **Slash 20.2**: `/kcd set <path> nan` (or `inf`, `-inf`, `1e400`) on a number row is refused with
  `ERR_NUMBER`.
- **Kit revision 38 `--list` Totals**: `docs/test-cases.md` Total equals the README badge, with a
  `Skipped` row for the diagnostics opt-out declared skip (closes `KC-A-07`).
- **Env 2, OptionsIdList 4**: the dead bare-global rungs are gone; no live-client difference.

## B. Host change required (candidates)

- **`Kit.secret` and its siblings** (`Kit.isSecret`, `Kit.reveal`, `Kit.SECRET_ERROR`), and the
  opt-in **`Kit.installSecretValue()`** installer for the global `issecretvalue`
  (`version-38-docs.md`). KickCD guards secret values through `NS.Compat.IsSecret`
  (`core/Compat.lua:43-47`) and its suites stub `issecretvalue` locally; those cases could be moved
  onto the shared simulator. **Not adopted in this run.**
- **WidgetsLineChart 3: segment clipping and hover re-sync.** KickCD draws no line chart, so this
  only matters if a chart is ever adopted. **Not adopted in this run.**
- **WidgetsAutocomplete 2: the re-hook guard** (a re-call re-installs the box's hooks; `maxRows`
  floored). KickCD has no autocomplete box; the Spells add-box remains the one possible host, noted
  in `../2026-10-07-v1.69.0-v1.70.0/01_DELTA.md`. **Not adopted in this run.**

## C. Whole-module adoption

None offered. `LibKa0s-Item-1.0` stays declined, settled (issue #14, `state:will-not-do`); `Item.lua`
did not move in this range.
