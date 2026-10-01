Delta: LibKa0s v1.65.0 -> v1.66.0

Copied from the local tag `v1.66.0` (`e4c5ef7`) with `git -C ../LibKa0s archive v1.66.0 LibKa0s testkit`,
never from a working tree. The tag is local only. This re-vendor is item GI-KC-RV of the 2026-10-01
GitHub issue pass (`Ka0sAddonsCommonTasks/docs/2026-10-01-GITHUB_ISSUE_PASS/`, spec S4).

## 3a/3b. Claimed and actual version

`grep -n '[Bb]undles' CLAUDE.md` read v1.65.0 (line 42). The last commit to touch either payload
(`git log -1 --format=%H -- libs/LibKa0s tests/_kit`, `fa8aead`, DG-KC-01) left the same line. The
payload matched the library at v1.65.0 (`diff -rq` of both folders against `git archive v1.65.0`: no
output). No claim/fact disagreement. Base: v1.65.0.

Step 0 pre-flight: the newest single-tag bundle, `2026-09-29-v1.63.0/`, states v1.62.0 -> v1.63.0, which
the history agrees with (`0710ce8` rolled the line from v1.62.0). No base correction. Two tags this addon
vendored after it, v1.64.0 and v1.65.0, have no bundle; see 3h.

## 3c. Per-file minor delta (file list from the tag's `LibKa0s.xml`)

| File | v1.65.0 | v1.66.0 |
|---|---|---|
| `Slash.lua` (`MINOR`) | 18 | 19 |
| `SlashParse.lua` (`PARSE_MINOR`) | absent | 1 (new) |
| `Widgets.lua` (`MINOR`) | 11 | 12 |
| `WidgetsReorder.lua` (`REORDER_MINOR`) | absent | 1 (new) |
| `DebugLog.lua` (`MINOR`) | 18 | 19 |
| `OptionsWidgets.lua` (`WIDGETS_MINOR`) | 33 | 34 |
| `OptionsTabs.lua` (`TABS_MINOR`) | 7 | 8 |
| `Perf.lua` (`MINOR`) | 13 | 14 |
| `PerfSampler.lua` (`SAMPLER_MINOR`) | absent | 1 (new) |
| `PerfCommands.lua` (`COMMANDS_MINOR`) | absent | 1 (new) |

Every other file is unchanged (`git -C ../LibKa0s diff --stat v1.65.0 v1.66.0 -- LibKa0s testkit`). The
payload goes from 28 to 32 library files. No cross-major skew: every file moves with the whole-folder copy.

The TOC loads the library through `libs\LibKa0s\LibKa0s.xml` alone (`KickCD.toc:28`), and
`tests/run.lua` derives its library load list from the same XML (`Loader.xmlFiles`), so the four new files
need no TOC or runner line.

## 3d. Both diffs, before the copy

`diff -rq <tag>/LibKa0s libs/LibKa0s`: `DebugLog.lua`, `LibKa0s.xml`, `OptionsTabs.lua`,
`OptionsWidgets.lua`, `Perf.lua`, `Slash.lua` and `Widgets.lua` differ; only in the tag: `PerfCommands.lua`,
`PerfSampler.lua`, `SlashParse.lua`, `WidgetsReorder.lua`.

`diff -rq <tag>/testkit tests/_kit`: `README.md`, `asserts.lua`, `framework.lua`, `inventory.lua`,
`mock_base.lua`, `run-automated-tests.sh` and `test_eol.lua` differ; only in the tag: `lizard_sighted.lua`,
`test_lizard_sighted.lua`.

No `Only in libs/LibKa0s` or `Only in tests/_kit` line, so nothing is deleted. After the copy, `diff -r`
of both folders against the tag is empty, and `run-automated-tests.sh` stays recorded `100755`.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' core modules settings`: every moved major is
consumed. Slash (`settings/Slash.lua:55`), Widgets (`modules/Castbar_Handle.lua:41`,
`modules/IconGrid.lua:647`, `settings/Spells.lua:789` for `ReorderList`, `settings/Spells_Rows.lua:287`),
DebugLog (`core/DebugLogSetup.lua:43`), Options (`settings/OptionsSetup.lua:71`) and Perf
(`core/PerfSetup.lua:33`).

## 3f. Kit revision

`Kit.VERSION` 34 -> 35 (`tests/_kit/framework.lua:20`). Both payloads were copied whole, which keeps the
kit-revision pairing rule satisfied by construction. Kit 35 adds `test_lizard_sighted.lua`, which
`Kit.assertSuiteInventory` refuses until it is declared: wired in `tests/run.lua` as
`{ name = "test_lizard_sighted", dir = "tests/_kit/" }` (version 35 document, *Adoption*, step 1).

## 3g. Contract delta

No member, descriptor field or string that existed at the old minors changed: the moved code (Slash's
parser, Widgets' `ReorderList`, Perf's capture and command surface) moved unchanged into paired secondary
files, and every new field (`RenderGrid`'s `parent` and `opts.gap`, three `RenderTabbedSchema` opts, Perf
`budget`, the Slash `textOf` resolver) is opt-in. One behaviour moves under an unchanged signature:
`RenderGrid` now releases a wide item whose `make` raised or answered exactly `false` with no spacer. No
KickCD `make` answers `false` or raises in a passing case.

The kit's complexity suite now measures the sighted shadow with function-count parity, and its command
carries `-L 1500` (version 35 document, *What changed*).

### Blockers

None. After the copy alone the only failures were the two vendor-sync cases, which read the provenance line
(fixed by rolling it in the same commit), and the suite-inventory refusal for `test_lizard_sighted`
(fixed by wiring it). No consumer test broke from a library change, and nothing under `libs/` or
`tests/_kit/` was edited.

### What the sighted complexity suite found

`bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle` on the copy: `fail`, one blind file,
`tests/test_icongrid_curves.lua` (18 of 19 functions listed). The cause is the blind spot the version 35
document names: three function literals in a `for ... in ipairs({ ... })` header in the case
"CurveSignature covers exactly the three curve-shaping fields". Hoisted into a local `mutators` table in
the re-vendor commit (same case, same assertions). After it: `pass`, `blindFiles` 0, 3374 functions,
max CCN 46, 3 functions above CCN 15:

- `modules/Cooldowns.lua:439` `Cooldowns.Refresh`, CCN 46
- `modules/IconGrid.lua:488` `IconGrid.Layout`, CCN 29
- `tests/test_perfsetup.lua:916` (anonymous case body), CCN 19

All three were already there, unseen by the raw command. They are left for GI-KC-12 (spec S4) and block
the next release until then.

## 3h. Tags vendored and never recorded

The skill's listing (provenance-rolling `CLAUDE.md` commits plus payload commits since the store's first
bundle, against the tags the bundles record) printed `v1.64.0` and `v1.65.0`. Written as the span bundle
`docs/revendor/2026-10-01-v1.64.0-v1.65.0/`.
