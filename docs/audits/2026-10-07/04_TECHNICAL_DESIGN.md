# KickCD — Technical design (2026-10-07)

Remediation for the seven roots in `02_DEVIATIONS.md`. None of them touches runtime behavior a player
can see. Six are documents, comments, records or a GitHub comment. One (`D-01`) renames a constant in
`core/Database.lua`. Every change here is small, and every Lua change keeps the green gate:
`lua tests/run.lua`, `luacheck .` (0/0), and the sighted complexity suite with no function above
CCN 15.

## KICKCD-C-01 — the two unrecorded re-vendors

**Shape.** Write one consolidated span bundle, as `audit-review-history` defines it:

```
docs/revendor/<YYYY-MM-DD>-v1.68.1-v1.70.0/
  01_DELTA.md     line 1 exactly: Delta: LibKa0s v1.68.1 -> v1.70.0 (span: v1.68.1 v1.69.0 v1.70.0)
  05_SUMMARY.md   one line per tag
```

- **v1.69.0** (`da8a8b8`) adds `WidgetsLineChart.lua` (Widgets `LineChart`, `LINE_CHART`,
  `ChartMath`) and kit revision 37 (`mock_lines.lua`). KickCD draws no chart, so the summary line is
  *carried by sweep, nothing adopted*.
- **v1.70.0** (`9d4a10b`) adds `WidgetsAutocomplete.lua` (Widgets `Autocomplete`, `AUTOCOMPLETE`).
  The Spells page's *Add a spell* box is the obvious candidate. It is a registered-two-consumer member
  upstream, but adopting it here is a feature decision, not a compliance one. Record it as
  *carried, nothing adopted; Autocomplete noted as a candidate for the Spells add box*, and leave the
  adoption to the owner.
- Base the delta on `git diff 7b29045 9d4a10b -- libs/LibKa0s tests/_kit`, which is the v1.68.1
  re-vendor commit to the v1.70.0 one.

**Risk.** None. The bundle is frozen once written. The base tag (v1.68.1) has its own bundle, so the
span's base is not in doubt.

**Process fix.** Both commits were made outside `/dev-copilot:wow-revendor-libka0s`, which is the
path that writes the bundle. Future re-vendors go through the command.

## KICKCD-C-08 — four stale statements

| Site | Today | Fix |
|---|---|---|
| `docs/ARCHITECTURE.md:79-83` | "Eight do … The other thirty-six" | Add `settings/OptionsSetup.lua` (the Options descriptor's `addonName`, v2.75.0) to the list. Say "nine" and "the other forty-one", or better, drop the counts and keep the list, which is self-checking |
| `.luacheckrc:25-29` | "Eight files … thirty-three authored files" | This is a historical note about `M4c-06`. Re-word it to "at the time" and point at the hub's list, so the comment stops asserting a current count |
| `docs/compat-layer.md:34` | "Called only by that file's bootstrap `CreateFrame`" | "Called only by that file's combat listener, an AceEvent target (`core/State.lua`), on …" |
| `.pkgmeta:22-23` | "Seven files, 7.5M" | Re-measure (`git ls-files media/screenshots CLAUDE.md DEPENDENCIES.md \| xargs du -cb`), or drop the figure and keep the reason |

**Guard.** `tests/test_doc_structure.lua` already scans docs. Optionally add one case that derives the
`addonName`-reader list from the tree and asserts `docs/ARCHITECTURE.md` names every file in it. That
would turn this recurring finding into a red test. It is not required; the list form alone stops the
count drifting.

## KICKCD-C-15 — seventeen bare `§N` sites

Mechanical: qualify each one.

- `tests/test_flow_traces.lua`: 12 sites, `§8` → `debug-logging-§8` and `§9` → `debug-logging-§9`.
  These are comments, so no case title changes and `docs/test-cases.md` does not move. Re-run
  `--list` and confirm the diff is empty.
- `tests/test_library_lines.lua:97`: `§8` → `debug-logging-§8`.
- `docs/settings-panel.md:62`: `§7` → `options-ui-§7`. `:203`: `` `§14` `` → `` `options-ui-§14` ``.
- `docs/slash-dispatch.md:70` and `:97`: `§7` → `slash-commands-§7`.

**Guard (optional).** Add a `tests/test_source_style.lua` case scanning authored `*.lua` and live
`docs/*.md`, with E4's scope, for `§[0-9]` not preceded by `[a-z]-`. Exclude `docs/smoke-tests.md`'s
legacy-section table explicitly, by path and by its `the old §` / `| … | §` shape, so the exclusion is
visible rather than silent.

## KICKCD-D-01 — `NS.SCHEMA_VERSION`

**Shape.**

```lua
-- core/Database.lua
NS.SCHEMA_VERSION = 5          -- the runner's target: the highest step's `to` (savedvariables-§1)
local CURRENT_DB_VERSION = NS.SCHEMA_VERSION
Database.CURRENT_DB_VERSION = CURRENT_DB_VERSION   -- keep only while a caller needs it
```

- `core/Database_Migrations.lua:18` reads the target off `Database.CURRENT_DB_VERSION`. Point it at
  `NS.SCHEMA_VERSION`.
- `modules/Diagnostics.lua:103-104` prints `code=%s` from `NS.Database.CURRENT_DB_VERSION`. Point it at
  `NS.SCHEMA_VERSION`. The report's text is unchanged, so no smoke check moves.
- Grep the tests for `CURRENT_DB_VERSION` and repoint them. Then delete the `Database.` alias unless
  something still needs it.
- Add one case to `tests/test_database.lua`: `NS.SCHEMA_VERSION` equals `#migrations + 1`, the highest
  step's `to`. Expose the step count through the existing test seam, or assert by running a fresh
  profile and reading the stamp.

**Risk.** Low. The value is unchanged, so no stored data moves and no migration is added. The only
failure mode is a reader left pointing at a deleted alias, which raises at load in the headless
suite. The suite catches it.

**Not in scope.** The shape-driven migrators stay as they are, under the register's first row.

## KICKCD-D-02 — #11's contradicted decline

Add a GitHub comment on #11: *Superseded. The Spells list renders through `H.RenderGrid` since
`e0da04c` (KickCD#10), and a General-page row does too (`settings/General.lua`). Kept closed as a
record.* No code, no register row. Space the write per the throttle rule.

## KICKCD-D-03 — the kit's folded total

**Upstream, LibKa0s `testkit`.** The `--list` renderer counts every registered case, including one
the host's configuration always skips. Two shapes would work:

- (a) The kit's diagnostics contract registers its opt-out case only when
  `Kit.diagnostics.enablesLogging == false`, so the default host lists 1302.
- (b) The renderer prints `Total` and a separate `of which skip here` count.

(a) is simpler and keeps every consumer's badge and inventory in agreement. File it against LibKa0s,
then re-vendor. **No local edit**, because the file is generated and an edit would be overwritten.

## KICKCD-B-04 — the stale, unsighted record

No code change. At the next release, `/dev-copilot:wow-automated-tests` writes a bundle on kit 37,
which emits `suites.complexity.blindFiles`. The release gate requires it to be `0`; today's
`--no-bundle` run shows 0 warnings and max CCN 15. The new watch list regenerates with an empty band.

## Ordering constraints

- `C-15` and `D-01` touch Lua and tests. Land each with the green gate.
- `C-08` touches `.luacheckrc` comments and `.pkgmeta` comments. Neither changes lint scope or the
  package, but re-run `luacheck .` anyway.
- `C-01` is independent. Write it in a commit of its own, so the frozen bundle has a clean history.
- `D-03` waits on LibKa0s. `B-04` waits on the next release.
