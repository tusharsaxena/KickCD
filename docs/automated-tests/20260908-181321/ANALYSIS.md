# Analysis — 20260908-181321

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** c8f9381 (`feat/2026-09-07-audit-review-remediation`), clean
- **Previous run:** [`20260825-103417`](../20260825-103417/)

## Headline

All four suites pass: lint 0/0 over 93 files, 860 cases with none failed and none skipped, six perf
scenarios, and **zero functions above CCN 15** across 2268 functions.

That last figure is the one that matters here, and it is not the same zero the previous run recorded.
Between the two runs `lizard` warned on one function — the anonymous case at
`tests/test_schema.lua:595-631`, 29 NLOC at CCN 18 — and `automated-tests-§3` gates a tag on
`suites.complexity.warnings == 0`. One test case with a second half in it was the only thing standing
between this addon and a passable release gate. `M4-25` split it on the seam its own comment at
`:613` already named, and this run is the measurement that says so.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260825-103417` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 93 files | [`lint.txt`](lint.txt) | 35 → 93 files; 0/0 unchanged |
| tests | pass | 860 passed, 0 skipped, 0 failed, 860 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 780 → 860 |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | 5 → 6; `spellPoll` allocation nearly halved |
| complexity | pass | 0 warnings, max CCN 15 | [`complexity.txt`](complexity.txt) | Totals up; averages flat; band still 4 files |

**Complexity in full.**

| Metric | `20260825-103417` | This run |
|---|---|---|
| Total NLOC | 15802 | 17805 |
| Functions | 2099 | 2268 |
| Avg NLOC / function | 6.5 | 6.6 |
| Avg CCN | 2.1 | 2.1 |
| Max CCN | 15 | 15 |
| Avg tokens / function | 48.7 | 50.4 |
| Warnings (CCN > 15) | 0 | 0 |
| Files 1000–1500 | 4 | 4 |
| Files over 1500 | 0 | 0 |

Totals up 13% and 8%, averages flat to within a decimal. Five functions sit at exactly CCN 15 and
none above: `Layout.layoutBlock` (`modules/IconGrid_Layout.lua@145-249`), `buildSpecNameMaps`
(`core/Util.lua@232-269`), `OnAccept` (`settings/Spells.lua@503-526`),
`State.ApplyInterruptibleAlpha` (`core/State.lua@109-128`) and `StateChanged`
(`modules/Cooldowns.lua@252-281`). Five functions with zero headroom is worth stating: one more `or`
on any of them warns, and a warning blocks a tag.

No suite was skipped: `lua 5.1.5`, `luacheck 1.2.0` and `lizard 1.24.0` all ran.

## What moved

- **lint** — 35 → 93 files at 0/0, `M4-11` bringing the test tree into scope. `tests/wow_mock.lua`
  is linted now and was not before.
- **tests** — 780 → 860. `docs/test-cases.md` and the README badge already read 860, and the
  bundle's [`test-cases.md`](test-cases.md) is byte-identical to `docs/test-cases.md` at HEAD, so no
  count claim moves in this commit.
- **perf** — 5 → 6 scenarios; `castStart` is new. `spellPoll` fell 978.1 → 526.3 bytes/iter and
  `spellState` 362.9 → 210.6, both roughly a 45% cut, with `api/iter` unchanged at 18.0 and 0.0.
  `iconApply` and the zero-overhead pair are identical at 848.0 / 848.0 / 848.1, and the pair still
  sits within noise of itself, which is what `performance-§2` wants. Every `ms/iter` rose by roughly
  a sixth; timings are not comparable across runs (`performance-§9`), so the allocation column is
  the one that carries meaning.
- **complexity** — a warning appeared and was cleared between the two runs; see *Headline*.
- **Band** — the same four files, and three of them moved. `settings/Spells.lua` grew the most:
  1171 → 1312, more than the other three together. `modules/Castbar.lua` 1305 → 1345,
  `tests/wow_mock.lua` 1128 → 1232, `modules/IconGrid.lua` 1153 → 1152. All four had dispositions
  reading "unchanged"; none of them was.

## What this run removed from the record, deliberately

The `RESULTS.md` this run replaced ended with a hand-written section, *A note on this record's own
line endings*, recording that `20260807-114618` was the first bundle written by test-kit revision
10's `normalize_eol` pass and that earlier bundles were written LF and left to git's filters. The
runner does not produce that section, so the regeneration dropped it. Its content is preserved here
rather than lost — and it has stopped being a note anybody needs to maintain, because the claim it
made by hand is now asserted on every run by two cases in the suite: *`--list` emits CRLF line
endings (matches the repo eol=crlf policy)* and *eol: every tracked file carries the terminator
`.gitattributes` declares for it*. A paragraph became a gate, which is the better place for it.

## The `ANALYSIS.md` gap, noted once

Three of eight bundles here carry no `ANALYSIS.md`: `20260807-110522`, `20260825-103417`, and until
this file, this one. The first two are not getting one. An analysis written today into a folder
stamped in August would date a reading to a day nobody took it, which is worse than a gap, because a
gap is legible. Fixed forward. Collection-wide the same gap stands at 37 of 95 bundles.

## Actions

None. The one thing this run was watching for — the complexity warning that blocked a tag — is gone,
and the four band files are all tracked already (`A-2` for the three source files, `KCD-30` for the
mock). No disposition is due for conversion; every manifest here carries `"release": null`, so the
three-consecutive-release-runs clock has not started.
