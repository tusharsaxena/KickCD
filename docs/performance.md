# Measuring the addon's performance

Two harnesses answer two different questions, and neither substitutes for the other.

| | Question | How | Where the output lands |
|---|---|---|---|
| **Offline** ([`tests/perf.lua`](../tests/perf.lua)) | Does a hot path allocate more than it used to? | `lua tests/perf.lua`, under the headless mock | the run bundle, `docs/automated-tests/<run>/perf.txt` + `perf.json` |
| **In-game** (`/kcd perf`) | What does this addon actually cost a live client, and is that cost even ours? | a guided A/B in a real client | a frozen bundle under [`docs/perf-analysis/`](perf-analysis/) |

WoW's built-in Addon Profiler cannot answer the second one. It bills a **shared** library's dispatch
frame to whichever addon created it, so enabling and disabling addons moves the blame around and the
first-alphabetical Ace addon in an install absorbs cost belonging to its siblings. The only
trustworthy answer is an A/B on the **same fight** with load order and shared-frame ownership held
fixed — which is what the `perf` verb's suspend/resume contract provides.

## Where the cost actually is

Worth saying plainly, because a bucket list is easy to misread as a claim that everything in it is
expensive. KickCD has almost no hot path. There is exactly one true 60 Hz handler — the cast bar's
`OnUpdate`, and it only runs *during* a cast — no combat-log parsing, and the per-unit dispatch
frames are `RegisterUnitEvent`-filtered so a raid does not spray them.

The measurable cost lives in `iconApply`, and its rate is forced by an **API constraint** rather than
by frame rate. `C_Spell.GetSpellCooldownDuration` mints a **fresh handle per call**
([midnight-quirks.md](midnight-quirks.md)), so `Cooldowns:StateChanged` compares unequal on every
poll for any spell parked on cooldown. That is ~10 polls/second per spell on cooldown, multiplied by
enabled units — roughly 100 applies/second with a seven-spell list mid-fight, each doing three curve
evaluations and a cooldown write. If a capture shows anything, it shows there.

## The buckets

Declared once, in [`core/PerfSetup.lua`](../core/PerfSetup.lua), with their nesting **on the
descriptor** rather than left as prose — a reader comparing two captures months apart cannot be
expected to know which totals overlap, and a parent must never be summed with its children.

| Bucket | Inside | What it brackets |
|---|---|---|
| `spellPoll` | — | `Cooldowns:Refresh`, the coalesced pass over the whole watched set |
| `pollSpell` | `spellPoll` | `Cooldowns:PollSpell`, per watched spell — **both** exits instrumented |
| `spellState` | `spellPoll` | `IconGrid:OnSpellState` — `SendMessage` dispatches inline, so it really does run inside the poll |
| `iconApply` | `spellState` | `Icon:Apply`, per icon per unit |
| `cdText` | — | the 0.1 s cooldown-text ticker pass |
| `castEvent` | — | `IconGrid:OnUnitCastEvent` |
| `visibility` | — | `IconGrid:RefreshVisibility` — deliberately **not** nested, see below |
| `castTick` | — | the cast bar's `OnUpdate`, per frame while a cast is running |

`visibility` used to declare `within = "castEvent"`, taken from its dominant in-combat caller.
`RefreshVisibility` has seven call sites and six of them are not cast events, so out of combat the
declared parent may not run at all and the report would indent a bucket under something that never
executed. That is worse than declaring nothing: nesting exists to tell a reader which totals overlap.

`glowGate` (`IconGrid:RefreshAllGlows`) is deliberately **not declared**. `Note()` records an
undeclared key anyway, so it can be added ad hoc the moment a capture points at it.

## 1. Offline

```sh
lua tests/perf.lua                                    # print the table
lua tests/perf.lua --out /tmp/kcd.json --label wip    # also emit a record
```

**Outside the green gate** (`performance-§9`). `lua tests/run.lua` does not invoke it and no commit
depends on it. The vendored runner drives it as its `perf` suite and keeps the output in the run
bundle; the suite is recorded, never gating.

It asserts on the **deterministic** half only — WoW API calls and bytes allocated per iteration,
isolated by a full collect either side of the measured loop. Never on wall-clock time: timings move
with the machine, the CPU governor and whatever else is running, and an assertion on them is a flake
generator that trains people to ignore the suite.

### Scenarios

| Scenario | What it drives | What is asserted |
|---|---|---|
| `spellPoll` | `Cooldowns:Refresh` over the watched set | exactly 3 WoW API calls per watched spell |
| `spellState` | `IconGrid:OnSpellState`, fanning out to every enabled unit | recorded only |
| `iconApply` | `Icon:Apply` in steady state — same logical state re-applied, so only the time-varying half runs | recorded only |
| `probeOverheadOff` / `probeOverheadOn` | the same `Icon:Apply` path with the brackets dormant, then armed | the **zero-overhead** assertions below |
| `castStart` | `Castbar:Start` / `Castbar:Stop`, one cast start and its teardown | that both starts install the **same** `OnUpdate` handler object, plus a byte ceiling (288 bytes/pair; measured 208.0) |

The `probeOverheadOff` / `probeOverheadOn` pair is the one `performance-§9` requires by name (it is
no longer the last row in that table), and it carries three assertions:

- the dormant arm stays under an **absolute byte ceiling** (900 bytes/pass; measured 848.0,
  re-verified over three runs on 2026-09-08 under `M4-22` and left where it stands). The relation
  alone is not enough — if a regression adds allocation to `Icon:Apply` itself, both arms rise
  together and `off <= on` still holds. The 52-byte margin is narrower than one empty table
  (64 bytes/pass on this path, measured), so the smallest realistic regression trips it. **A rise
  in that figure IS the finding**; raise the ceiling only with a recorded reason.
- the dormant arm allocates no more than the armed one, which is what `performance-§2`'s gating
  idiom (one upvalue read, one field read, one boolean test — no call, no allocation) buys.
- the probe does not change how many API calls a pass makes.

`castStart` is the odd one out and deliberately so. Cast starts are **event**-rate — one per cast —
so this scenario is not here because the path is hot; the per-frame half of the cast bar is
`castTick`, which only the in-game probe sees. It exists because `M4-22` would not let the
allocation fix land without a measurement of it, and because the property it pins is not really a
number: `Castbar:Start` used to build `function() onUpdate(inst) end` on every cast start, and
`EnsureFrame` now builds `inst.onUpdateScript` once per unit for the session. **The identity
assertion is the load-bearing one** — a handler object is the same on every interpreter and cannot
drift with the live heap. The byte ceiling is the backstop for a shape that caches the handler and
then allocates something else per cast; it is set at 288 against a measured 208.0, wide enough for
one added table (65 bytes/pass here) and still 16 bytes under the 304.0 the defect measured. The
same identity is pinned inside the green gate by `tests/test_castbar_frame.lua`'s "cast start
installs ONE cached OnUpdate handler, per unit, not one per cast", because this runner is not.

### Reading the output

Compare scenarios **within one run**. Never compare absolute numbers across machines — the header
says so and means it. `bytes/iter` is the load-bearing column: allocation in a path running at combat
frequency matters more than its wall time.

Exit code is non-zero on an assertion failure, so this is CI-usable even though nothing gates on it
today.

## 2. In-game

```
/kcd perf                      # usage
/kcd perf start [label]        # begin a run; zeroes the counters, stamps who/where you are
/kcd perf measure a            # arm Experiment A — addon ACTIVE; records for the next combat
/kcd perf measure b            # arm Experiment B — same, with the addon SUSPENDED first
/kcd perf finish               # end the run, save it to KickCDPerfDB, lift any suspend
/kcd perf report               # totals for the run
/kcd perf dump                 # the raw record, ready to paste
/kcd perf cancel               # abandon the run; nothing is saved
/kcd perf show | hide | toggle # the clickable step panel
```

The probe, the guided run, the record schema and the clickable step panel are
**`LibKa0s-Perf-1.0`'s** — vendored, not hand-rolled. `core/PerfSetup.lua` supplies only what this
addon can know: which paths are worth measuring, and what "inert" means here.

Output is **not** gated on `NS.State.debug`, unlike `NS.Debug`. That gate exists to keep the addon
free when idle; a perf run is explicit user action and none of it executes unless someone typed
`/kcd perf start`. Gating it once meant a user who started a run without first enabling debug logging
watched an empty console while a capture plainly ran.

### Suspend — one of two holds on the stand-down latch

The A/B's B-arm makes the addon inert **without a `/reload`**. Reloading, or disabling the addon
through the AddOns list, shifts shared-frame ownership — the exact confound that makes the built-in
profiler untrustworthy. So the flip happens in place, live, mid-session.

**It is no longer this file's own teardown.** Since the LibKa0s v1.42.0 re-vendor the suspended arm takes the
`perf` **hold** on `LibKa0s-Lifecycle-1.0`, the same latch `/kcd disable` takes the `disabled` hold
on, and the host's own `standDown` / `standUp` (`core/LifecycleSetup.lua`) are what run on the edge.
`core/PerfSetup.lua` passes `lifecycle = NS.Lifecycle` and no longer carries `suspend` / `resume`
callbacks at all. The full picture is
[ARCHITECTURE.md → The stand-down](ARCHITECTURE.md#the-stand-down-disabled-is-total); what matters
here is the part that is about captures:

- **The addon is down while ANY hold is taken and comes back only when the LAST one is released.**
  `/kcd disable` is a live verb, so a player really can switch the addon off mid-capture — and
  `/kcd enable` there too. A `resume` that stood the addon up directly would resurrect it under a
  player who had just turned it off; a `disable` that stood it down on its way out would ruin the
  run. Both go through release-and-re-evaluate.
- **`NS.Perf.suspended` still answers and still means the same thing.** It is a **view** of the
  `perf` hold rather than a boolean beside it, and assigning to it raises — the second copy is
  precisely what made the bug above reachable.
- **The two holds have different lifetimes.** `perf` is session-only and is never persisted;
  `disabled` is the stored `enabled` path and surviving a `/reload` is the whole point of it.
- **`finish` releases its OWN hold rather than standing the addon up** (`performance-§6`). An addon
  the player left disabled at the end of a run stays disabled.

The two halves the teardown itself needs are unchanged, and both are still needed:

1. **The show decisions consult the latch as step 0** of their ladder — `IconGrid`'s
   `shouldBeVisible` and `Castbar`'s `isVisible` ask `NS.IsDown()`. Nothing (a combat transition, a
   target swap, a settings change) can re-show a grid behind the latch's back. It does **not** work
   by hiding frames from a setup file.
2. **Each module's `Suspend()` releases the work** — its game events, its bus subscriptions *and*
   its private per-unit dispatch frames, which AceEvent's `UnregisterAllEvents` cannot reach — and
   every timer it owns is canceled.

`standUp` rebuilds from **current** state, not from a snapshot: a unit toggled while suspended comes
back correctly (`performance-§6`). No `CONFIG_CHANGED` is published from the latch — the modules'
own resume paths re-anchor and re-render, so neither setup file becomes a sixth sender of a message
[message-bus.md](message-bus.md) governs.

### The A/B protocol

1. Pick a **repeatable** fight — a training dummy with a fixed rotation, not a raid pull. The two
   arms must be the same work, not the same clock.
2. Hold everything else fixed: same zone, same group state, same addons loaded and in the same order.
   Suspend is what holds shared-frame ownership fixed; you hold the rest.
3. `/kcd perf start <label>`, then `measure a`, fight, then `measure b`, fight the same fight. Each
   arm records **only** while combat is up, so the panel's steps and the pull are what pace the run
   — or just click through the step panel, which runs the identical code path.
4. `/kcd perf finish`, then `/kcd perf report` for totals and `/kcd perf dump` for the record.
   `/reload` to flush `KickCDPerfDB` to disk.
5. Press **Copy** on the debug-log window and commit the run as a bundle under
   [`docs/perf-analysis/`](perf-analysis/) if it is worth keeping. One paste carries the report, the
   dump and the run's lifecycle lines, which is all three of the bundle's artifacts.

Caveat worth knowing before you read a delta: `fps.deltaMsPerFrame` has a resolution floor. Treat a
delta below roughly 0.5 ms/frame as **unresolved** rather than as zero, and read the bucket figures
instead — those measure the addon directly and are unaffected by arm mismatch or frame pacing. A
client with a frame limiter pinned produces an unusable delta and the record cannot tell you so;
judge that from the arms (two arms at the same frame time, or at a round one like 8.33 ms).

## 3. Where the numbers go

- **In-game captures worth keeping** → [`docs/perf-analysis/`](perf-analysis/), standing and
  cumulative, so captures compare across addon versions. One **frozen bundle per capture** at
  `docs/perf-analysis/<YYYYMMDD-HHMMSS>/` — the stamp is local time taken from the record's own
  `timestamp`, so a capture written up a week later still sorts where it happened — holding exactly
  three artifacts: `report.md` (what the client printed, plus the run's lifecycle lines),
  `dump.json` (the record, verbatim, one line) and `ANALYSIS.md` (the write-up). That directory's
  `README.md` documents the naming, the artifacts and the schema, and indexes the captures taken so
  far.
- **Offline runs** → the bundle for the run that produced them, under
  [`docs/automated-tests/`](automated-tests/). They are reproducible from the repo, so they do not
  need a standing store.
- **An interpretation without its record is an assertion** (`performance-§8`). If a decision is taken
  off a capture, the capture gets committed and the decision cites its bundle. `core/PerfSetup.lua`
  carries a note saying exactly which of its decisions predate this rule and therefore quote no
  figures.

## 4. Complexity

Cyclomatic complexity is measured by the same runner, as its `complexity` suite:

```sh
lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
```

Recorded and compared, never thresholded into a build failure (`performance-§10`) — though a release
does gate on zero functions above CCN 15. See [testing.md](testing.md).
