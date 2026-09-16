# Analysis — 20260916-184417

- **Addon:** KickCD 1.3.0
- **Verdict:** green
- **Commit:** fac2411fc53c (master), clean
- **Previous run:** [`20260916-094252`](../20260916-094252/)

## Headline

Green on all four suites, zero functions above CCN 15, nothing skipped. This run measures the
launcher cycle — the minimap button and broker plugin as one object, LibDataBroker-1.1 and
LibDBIcon-1.0 vendored, LibKa0s re-vendored to v1.39.0 — plus two small tidy-ups committed hours
before the run: stale line citations corrected inside `.luacheckrc` and the deletion of the dead
`NS.MasterEnabled` export. Test cases rose 936 → 973 and lint scope 95 → 97 files, both from that
work; the complexity averages went *down* while the totals went up, which is growth in count rather
than in density. Nothing newly crossed a threshold. One thing to read rather than act on: two perf
allocation figures moved by more than an order of magnitude (see *What moved*).

## Suites

| Suite | Status | Result | Artifact | Moved since `20260916-094252` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 97 files | [`lint.txt`](lint.txt) | +2 files in scope, still 0/0 |
| tests | pass | 973 passed, 0 skipped, 0 failed, 973 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +37 cases |
| perf | pass | 6 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | scenario count unchanged; two allocation figures moved sharply, see below |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity metrics** (all from [`manifest.json`](manifest.json), footer in [`complexity.txt`](complexity.txt)):

| Metric | Value |
|---|---|
| Total NLOC | 19884 |
| Functions | 2494 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 51.4 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 0 |

Every suite ran to completion. No suite was skipped and no case reported a `Kit.skip`, so passed and
total agree at 973 and no figure here stands in for an unmeasured state. The toolchain is recorded in
[`manifest.json`](manifest.json)'s `host` block: Lua 5.1.5, `luacheck` 1.2.0, `lizard` 1.24.0. Run
duration 21985 ms.

## What moved

The previous run's snapshot was `880c80b`; this one is `fac2411`. Thirteen commits separate them, so
the deltas below are the whole launcher cycle and not only today's two tidy-ups.

- **lint** — 95 → 97 files in scope, still 0 warnings / 0 errors ([`lint.txt`](lint.txt)). The two
  extra files are `core/LauncherSetup.lua` and `tests/test_launcher.lua`; the vendored
  `libs/LibDataBroker-1.1/` and `libs/LibDBIcon-1.0/` that arrived with them add nothing to the
  count because `.luacheckrc` excludes `libs/`. Scope grew because the tree grew, not because the
  config changed. `138da68` touched `.luacheckrc`, but only its prose: two line citations that had
  been measured when the tree was smaller now read 97 files and 88 remaining after the nine
  single-file stanzas. No rule, no exclusion and no ignore moved.
- **tests** — 936 → 973 passed (+37), 0 skipped, 0 failed ([`tests.txt`](tests.txt)). The new
  `tests/test_launcher.lua` is the bulk of it, with additions in `tests/test_slash.lua`,
  `tests/test_options_panel.lua` and `tests/test_schema.lua`. `fac2411` deleted the
  `NS.MasterEnabled` export without costing a case, which is the point that commit makes: the slash
  tests reach the disabled-verb gate through the verbs, never through the predicate, so removing the
  published predicate left the suite whole. The inventory is [`test-cases.md`](test-cases.md).
- **perf** — 6 scenarios in both runs ([`perf.txt`](perf.txt)). Timings are orientation-only by the
  runner's own caveat and are within the usual spread, but two allocation figures moved by more than
  an order of magnitude: `spellPoll` 66.4 → 1662.1 bytes/iter and `spellState` 661.5 → 1440.9
  ([`perf.json`](perf.json) against [`../20260916-094252/perf.json`](../20260916-094252/perf.json)).
  `spellPoll`'s per-iteration API count is unchanged at 18.0 and `castStart`, `iconApply` and both
  `probeOverhead` buckets are byte-identical at 208.0 / 848.0 / 848.0 / 848.1, so no scenario is
  doing new API work. Read alongside the previous run — where the same pair inverted 528.1 → 66.4
  and 209.7 → 661.5 — these two buckets look like they trade allocation between them rather than
  trending, and the offline harness's byte accounting is the noisiest figure it reports. Recorded,
  not actioned; `perf` gates neither the run nor the commit, though it does gate the tag.
- **complexity** — NLOC 19345 → 19884 (+539) over 2390 → 2494 functions (+104). Both *averages* fell:
  avg NLOC / function 6.8 → 6.7 and avg tokens / function 51.8 → 51.4. That is the distinction worth
  drawing — the totals rose because the addon grew a launcher, while the per-function figures got
  slightly *smaller*, so the new code is more numerous and shorter than the existing average rather
  than denser. Avg CCN flat at 2.1, max CCN flat at 15 (at the line, not over it), warning count and
  both warning rates flat at 0.00. Four band files in both runs, none over the cap.

## Complexity watch list

Both tables are maintained in [`RESULTS.md`](../RESULTS.md), which the runner regenerates whole on
every run; the **Disposition** column there is the authored half and is current as of this run.

### Functions `lizard` warned on

None. Max CCN measured at 15 across 2494 functions — at `layout`'s line and not over it
([`complexity.txt`](complexity.txt) footer, `Warning cnt 0`). That zero is measured rather than
assumed: `lizard` 1.24.0 ran to completion and its own banner reads *No thresholds exceeded*.

### Files by `layout-§1` band

4 files in the 1000–1500 on-notice band, 0 over the 1500 cap. `modules/Castbar.lua` (1345),
`modules/IconGrid.lua` (1163) and `settings/Spells.lua` (1246) are all unchanged from the previous
run — `Spells.lua` is flat for the first time after last cycle's -66, holding the ground the
test-mode removal bought. `tests/wow_mock.lua` moved the other way, 1027 → 1060 (**+33**), because
the launcher work gave the mock a LibDataBroker/LibDBIcon surface to answer for. Nothing newly
crossed, and the band is not part of the release gate.

**Shelf life.** All four entries carry a tracked ID with an owner rather than a bare *Accepted* —
`modules/Castbar.lua`, `modules/IconGrid.lua` and `settings/Spells.lua` under `A-2`, and
`tests/wow_mock.lua` under `KCD-30`. The `automated-tests-§4` shelf-life rule is therefore satisfied
by the tracking and not by the repetition; no entry is owed a conversion this cycle. Re-check points
are unchanged: `settings/Spells.lua` at 1400, `modules/Castbar.lua` at 1450. `tests/wow_mock.lua`
gained 33 lines and still sits 440 below the cap, so its disposition stays *watch, no action* while
`KCD-30`'s rebuild-as-a-thin-extender fix remains the real answer.

## Actions

None.
