# Analysis — 20260807-114618

- **Addon:** KickCD 1.2.1
- **Verdict:** green
- **Commit:** 56e80892ce90640d0a16cbd232b7c142aef49ea2 (master), clean
- **Previous run:** [`20260807-110522`](../20260807-110522/)

## Headline

All four suites passed: lint clean over 33 files, 756 tests passed with zero failures and zero
skips, five perf scenarios ran, and `lizard` warned on nothing. Every structural figure is
identical to the previous run — same NLOC, same function count, same averages, same ceiling — which
is expected, because the only thing that changed between the two runs is the commit they were taken
on: `20260807-110522` was taken **dirty**, midway through the LibKa0s v1.8.2 / test-kit revision 10
re-vendor, and this one is taken **clean** on `56e8089` with that work committed. Nothing to act on
in the suites themselves. The one thing worth recording is that this is the first bundle written by
test-kit revision 10, and its `normalize_eol` pass landed — every artifact in this directory carries
CRLF, matching the repo's `.gitattributes` pin, where every earlier bundle was written LF.

## Suites

Every row links its artifact, so a reader can get from a figure to the evidence in one click.

| Suite | Status | Result | Artifact | Moved since `20260807-110522` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 33 files | [`lint.txt`](lint.txt) | No change |
| tests | pass | 756 passed, 0 skipped, 0 failed, 756 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | No change |
| perf | pass | 5 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | Same five scenarios; timings up 12–70%, machine noise (see below) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | No change in any field |

**Complexity is reported in full**, because a single figure cannot be compared across a change in
size. Every value below comes from [`manifest.json`](manifest.json)'s `suites.complexity`, which
records all eight of `lizard`'s footer fields; the footer itself is at the bottom of
[`complexity.txt`](complexity.txt).

| Metric | Value |
|---|---|
| Total NLOC | 15533 |
| Functions | 2059 |
| Avg NLOC / function | 6.5 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 48.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

Every suite is a clean pass, so there is no per-suite failure paragraph to write. Two notes that are
not failures but should not be silent:

- **`tests` reports its skip figure explicitly as `0`.** The harness line in
  [`tests.txt`](tests.txt) reads `756 passed, 0 failed, 0 skipped, 756 total`. This is stated rather
  than assumed, because a run that folds a skip into a pass claims coverage it did not exercise
  (`automated-tests-§4`).
- **No suite was skipped and none was deselected.** `lua` 5.1.5, `luacheck` 1.2.0 and `lizard`
  1.23.0 were all present — see `host` in [`manifest.json`](manifest.json) — and this was a full
  four-suite run with no `--suite` filter.

## What moved

- **lint** — 0/0 over 33 files, unchanged from `20260807-110522` and from `20260807-022824` before
  it. Three consecutive runs at the same file count.
- **tests** — 756/756, unchanged for the third consecutive run. The count last moved on
  `20260807-022824` (737 to 756).
- **perf** — the same five scenarios, all passing, for the third consecutive run. Every timing rose:
  `spellPoll` 0.01678 to 0.01920 ms/iter, `spellState` 0.00635 to 0.00767, `iconApply` 0.00262 to
  0.00333, `probeOverheadOff` 0.00266 to 0.00299, `probeOverheadOn` 0.00262 to 0.00445. **This is
  not a regression signal.** Not one line of addon source changed between the two runs — the diff is
  the vendored kit and `.gitattributes` — and the derived quantities that would show a real change
  did not move: `spellPoll` still makes 18.0 API calls per iteration, and the per-iteration byte
  figures are identical across all five scenarios. The suite's own duration rose in step (160 ms to
  212 ms), which is the signature of a busier host, not a slower addon. The playbook's own
  instruction applies — compare scenarios **within** a run, never across runs on a shared machine.
- **complexity** — every field identical: 15533 NLOC, 2059 functions, avg NLOC 6.5, avg CCN 2.1, max
  CCN 15, avg tokens 48.8, 0 warnings, 4 band files, 0 over cap. Both the totals **and** the
  averages held, which is the pair that matters: the addon neither grew nor got denser.
- **Bundle line endings** — the one thing that genuinely changed. This bundle's seven artifacts each
  carry equal `\r` and `\n` counts (`complexity.txt` 2158/2158, `tests.txt` 758/758,
  `test-cases.md` 965/965, `lint.txt` 35/35, `perf.txt` 12/12, `manifest.json` 19/19, `perf.json`
  1/1), so the runner honored the repo's `* text=auto eol=crlf` pin. Revision 9 and earlier wrote LF
  unconditionally and left every bundle to be corrected by git's filters on staging.

## Complexity watch list

### Functions `lizard` warned on

**None.** The footer of [`complexity.txt`](complexity.txt) reads `No thresholds exceeded`, and
`suites.complexity.warnings` in [`manifest.json`](manifest.json) is `0`. Fourth consecutive run at
zero.

Five functions sit exactly **on** the CCN 15 line — not over it, so none is an entry on this list —
and they are the same five as on the previous four runs, in [`complexity.txt`](complexity.txt)
order: `State.ApplyInterruptibleAlpha` (`core/State.lua:99-118`), `buildSpecNameMaps`
(`core/Util.lua:232-269`), `StateChanged` (`modules/Cooldowns.lua:250-279`), `Layout.layoutBlock`
(`modules/IconGrid_Layout.lua:145-249`) and `OnAccept` (`settings/Spells.lua:480-503`). They are
named so that a future run reporting a warning has five obvious places to look, and so whoever next
edits one knows there is exactly one line of headroom. `lizard` scores every `and`/`or`
short-circuit as a decision, so in Lua these read as dense **defaulting and guarding** rather than
tangled control flow — four of the five carry a token count under 200 against their CCN of 15, which
is the shape of a function setting many fields, not one branching many ways.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Castbar.lua` | 1305 | **Already tracked as `A-2`.** Unchanged since `20260807-022824`. Watch, no action. |
| 1000–1500 (on notice) | `settings/Spells.lua` | 1171 | **Already tracked as `A-2`.** Unchanged. The in-file peel is spent; the next reduction has to be a file split. |
| 1000–1500 (on notice) | `modules/IconGrid.lua` | 1153 | **Already tracked as `A-2`.** Unchanged. Watch, no action. |
| 1000–1500 (on notice) | `tests/wow_mock.lua` | 1101 | **Already tracked as `KCD-30`.** Unchanged. Not covered by `A-2`, which lists source files only; the whole file is the deviation, and the tracked fix rebuilds the mock as a thin extender rather than trimming it. `luacheck` never sees it. |

Nothing newly crossed a band boundary, nothing is over the 1500 cap, and the band has held at four
files for six runs. No entry in either table is carried as a bare **Accepted** — all four point at a
tracked deviation (`A-2`, `KCD-30`) and the functions table is empty — so `automated-tests-§4`'s
three-release shelf-life rule has nothing outstanding against this record. None of the six runs in
`RESULTS.md` is a release run (`release: null` in every manifest), so that clock has not started.

## Actions

1. **`docs/automated-tests/20260807-110522/` has no `ANALYSIS.md`.** That run's numbers are carried
   forward and diffed here, so nothing is lost, but the gap is recorded rather than quietly filled:
   a frozen bundle is evidence and is not edited after the fact (`automated-tests-§1`).
   `automated-tests-§5` makes `ANALYSIS.md` a MUST only at a release, and that run was not one — so
   this is a SHOULD that went unwritten, not a violated MUST. It is new here and has no owner in the
   addon's own tracking.
