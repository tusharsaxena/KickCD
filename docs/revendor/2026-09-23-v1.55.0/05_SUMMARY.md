# 05 - Summary

LibKa0s **v1.54.2 -> v1.55.0**, re-vendored in 523d05a (bundle renamed to its tag in a07076c), then
Steps 5-8 in this run. Branch `suite/2026-09-22-standards-sweep`. Nothing pushed, and the addon version
was not bumped.

## Per-file minors

No existing file's LibStub minor moved. Three files arrived as new majors: `Compat.lua` (Compat 1),
`Bus.lua` (Bus 1) and `Schema.lua` (Schema 1). The full table is `01_DELTA.md` section 3c. Test kit
revision 24 -> 25.

## Delivered by the copy (class A)

- Kit revision 25: the layout-section-1 cap census gate, the `.gitattributes` body case in `test_eol`,
  suite declarations keyed by (basename, directory), and the commit SHA in the automated-test record.
  Wired and green in 523d05a.
- The three new library files load through the XML-derived list (`tests/run.lua:53`) with no edit.

## Contract blockers

None (`01_DELTA.md` section 3g).

## Adopted

| Candidate | Commit | What moved | Tests added |
|---|---|---|---|
| C1 `LibKa0s-Compat-1.0` | 45cc03f | `core/Compat.lua` wires `GetSpellCooldown`, `GetSpellTexture`, `GetSpellInfo`, `GetSpecialization`, `GetSpecializationInfo` and the new seam `IsSecret` from the major (reader arm and guard arm). The 12 inline `_G.issecretvalue(` calls in `core/Compat.lua` and four modules go through `NS.Compat.IsSecret`. `tests/run.lua` surface source gains the major's row. | 12: two characterization pins written green before the change (five-value arity, typed-name position 6), then the legacy rank remap, legacy `isEnabled == 0`, `GetSpellTexture` arity, `GetSpecializationInfo(nil)`, `IsSecret` is the library's and strict, a source scan for `issecretvalue` outside the seam, two library-less load cases (reader arm, guard arm) and a by-name surface-parity case. One fixture corrected (`tests/test_compat_api.lua`, the legacy `GetSpellInfo` shape). |
| C2 `LibKa0s-Bus-1.0` (Catalog only), part 1 | c0ea075 | `NS.MSG` is declared once in `core/Constants.lua`, and the 23 literal call lines across 8 files read it. Wire strings unchanged. | 3: the subscription map each module holds after enable, pinned on the literal tree first; the key-to-wire pin; a source scan for a literal outside the catalog. Nine test files moved from literals to constants. |
| C2 `LibKa0s-Bus-1.0` (Catalog only), part 2 | ae286ce | The five wire names go to PascalCase (`Ka0s_KickCD_SpellState`, `_ConfigChanged`, `_ProfileChanged`, `_GridLayout`, `_CombatState`), and the table is wrapped in `Bus.Catalog`, with the plain table when the library is absent. Live docs and comments follow. | 2: the strict read raises with the payload present; a library-less load publishes the plain table with the same keys and values. The pins from part 1 moved to the new names. |

Behavior changes, all deliberate and none on a path a 12.x client with the payload present takes. The
legacy `GetSpellInfo` rung drops the rank. A legacy `isEnabled` of 0 reads disabled.
`GetSpellTexture` answers one value. `GetSpecializationInfo(nil)` answers nil without a client call. A
library-less load answers the readers' absent values: no spell names, icons, cooldowns or spec. That is
the reader arm the Compat API document prescribes. The bus wire names changed, and nothing outside
KickCD listens for them.

## Declined

| Candidate | Decision | Issue | Why |
|---|---|---|---|
| C3 `LibKa0s-Schema-1.0` | not now (`state:triaged`, `severity:medium`) | [#22](https://github.com/tusharsaxena/KickCD/issues/22) | The spec prescribes no KickCD delta (`schema.md:465-603`). The host's `Helpers.Set(path, section, value)` has special-path tables in front of the write and the master-switch hook in the same turn. Mapping that onto the library needs a design survey first. |

## Skipped or unreached

Nothing unreached. Within the adopted candidates, these were deliberately left out:

- `CanAccess`, `IsSafeKey`, `GetSpellName` are not wired. KickCD has no caller for any of them, and they
  are on the parity case's ignore list with the reason.
- Bus's tracked record (`New` / `NewTarget` / `StandDown` / `StandUp`) is not used. The spec says
  KickCD's receivers need no record.
- The by-name `assertSurfaceParity` case for Bus is not added. The host takes one member inline and
  keeps no stub table to measure. The library-less case pins the degraded `NS.MSG` instead.

## Suite results

Every command was run from the repo root through `/home/tushar/.claude/wow-addon/bin/ka0s-bounded`.
The lint column is the bounded lint run over `.`.

| Point | `lua tests/run.lua` | lint |
|---|---|---|
| Baseline (a07076c) | 1033 passed, 0 failed, 0 skipped | 0 warnings / 0 errors in 101 files |
| C1 characterization only, old code | 1035 passed, 0 failed | - |
| C1 code, before the fixture fix | 1034 passed, 1 failed (the legacy `GetSpellInfo` fixture the spec corrects) | - |
| 45cc03f | 1045 passed, 0 failed, 0 skipped | 0 / 0 in 101 files |
| C2 characterization only, literal tree | 1046 passed, 0 failed | - |
| c0ea075 | 1048 passed, 0 failed, 0 skipped | 0 / 0 in 101 files |
| ae286ce | 1050 passed, 0 failed, 0 skipped | 0 / 0 in 101 files |

`docs/test-cases.md` was regenerated from `lua tests/run.lua --list` in each commit, and the README
Tests badge moved with it (1045, 1048, 1050).

## Open, for the owner

- **Past-participle SHOULD not taken.** The naming cheatsheet says `<Event>` SHOULD name what happened,
  preferably as a past participle. `SpellState`, `GridLayout` and `CombatState` do not. The rename used
  the mechanical PascalCase of the existing suffix because that is what the spec prescribes. It is a
  SHOULD, so this is not a MUST deviation and there is no register row. A second rename
  (`SpellStateChanged`, `CombatStateChanged`, ...) is a one-table change if wanted.
- **Dated design history keeps the old names.** `docs/superpowers/plans/` and `docs/superpowers/specs/`
  still quote the SCREAMING_SNAKE wire names: 21 occurrences, counted with `git grep -o 'Ka0s_KickCD_[A-Z_]*[A-Z]\b' -- docs/superpowers | wc -l`. They record what was true on their dates
  and were not rewritten.
- **In-game checks owed.** A 12.x client should confirm that cooldown icons, the secret-charge path
  and the Spells page refresh are unchanged with the library routing. The Compat API document also
  asks for an in-game check that the modern `isEnabled` is a plain value.
