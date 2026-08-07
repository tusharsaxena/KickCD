# Perf analysis — the in-game capture store

**In-game captures only.** A human runs `/kcd perf` in a live client and copies the result out; a
script cannot produce one, which is why this store exists at all (`performance-§8`). **Offline**
scenario runs come from `tests/perf.lua`, are driven by `tests/_kit/run-automated-tests.sh`, and live
in the bundle for the run that produced them, under [`../automated-tests/`](../automated-tests/).
The two harnesses answer different questions and their outputs are deliberately not merged: an
offline run says nothing about frame time, and an in-game capture says nothing about allocation.

See [docs/performance.md](../performance.md) for which paths are bracketed and why, and how to read
a report.

This directory is **standing and cumulative** rather than tied to one investigation, so captures
compare across addon versions. Bundles are committed as **evidence**: the raw capture outlives the
write-up that interprets it, and an interpretation without its record is an assertion
(`performance-§8`).

**The store is currently empty.** No in-game capture has been committed yet. That is a real gap, not
an oversight in the tooling — and it is why `core/PerfSetup.lua` no longer quotes figures from the
early uncommitted capture its two nesting decisions were taken off. The first committed bundle here
is what makes those decisions citable.

## Bundle naming

```
docs/perf-analysis/<YYYYMMDD-HHMMSS>/
```

One directory per capture. The stamp is **local time**, rendered from the record's own `timestamp`
field (epoch seconds) — **when the capture happened**, not when it was written up, so a run analysed
a week later still sorts against its neighbours. A bundle is never renamed to match a later
convention; a frozen directory stays as it was written.

A stamp that had to be reconstructed (a record with no usable `timestamp`) is said to be one, in that
bundle's `ANALYSIS.md`.

## The three artifacts

Each bundle carries exactly three files, and nothing else:

| File | What it is |
|---|---|
| `report.md` | The human-readable report the client printed, plus the run's lifecycle log lines (`run started`, `armed`, `RECORDING`, `ENDED`, `SUSPENDED`, `RESUMED`) |
| `dump.json` | The schema-2 JSON record, committed **verbatim** |
| `ANALYSIS.md` | The write-up, following the uniform prompt in the root `PERF_ANALYSIS.md` playbook |

The lifecycle lines are kept on purpose: they are the capture's provenance. They are how a later
reader confirms that both arms were combat-gated, that arm B really was suspended, and that no
`/reload` landed between the arms — the three conditions `performance-§7` puts on a comparable pair,
none of which the report itself records.

**`dump.json` is the emitted line byte for byte** — one line, keys as sorted, figures as encoded. Not
pretty-printed, not re-keyed, not rounded, not stripped of a field that looks wrong. The library
emits sorted keys precisely so two records diff cleanly, and the encoder's quirks are part of the
record's identity. Read it with `jq`; never write it with one.

Bundles are **frozen once written** and are **never pruned**. If a reading turns out to be wrong, the
*next* capture's `ANALYSIS.md` says so — the frozen one is not corrected.

## Schema

One shape for both sources, so a single reader handles either. `schema` is the version stamp;
KickCD emits **schema 2** — `LibKa0s-Perf-1.0`'s own, defined and versioned in the library, not here.
Full field-by-field contract:
[LibKa0s docs/record-schema.md](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/record-schema.md).
The sketch below is for orientation; that document is the source of truth.

```jsonc
{
  "schema": 2,
  "addon": "KickCD",
  "source": "ingame",           // or "offline" for a tests/perf.lua record
  "version": "1.2.1",           // addon version, read from the TOC manifest
  "interface": 0,               // the CLIENT's build TOC — see the field note below
  "timestamp": 1785110400,      // epoch seconds — the bundle's directory stamp comes from here
  "label": "dummy-mm-hunter",

  // Who / where / what, stamped once at the start of an in-game run. Absent offline.
  "context": { "character": "...", "realm": "...", "level": 80,
               "class": "Hunter", "spec": "Marksmanship",
               "zone": "...", "subZone": "...", "group": "solo" },

  // Per-bucket totals. In-game buckets are the probe's brackets; offline buckets are the
  // runner's scenarios. In-game buckets MAY NEST — see `within`. Never sum a parent with
  // its children. Offline buckets never nest: each scenario is driven directly and times
  // only its own loop, so a missing `within` there means exactly that.
  "buckets": {
    "spellPoll": { "calls": 000, "totalMs": 0.0, "maxMs": 0.0 },
    "pollSpell": { "calls": 000, "totalMs": 0.0, "maxMs": 0.0, "within": "spellPoll" },
    "iconApply": { "calls": 000, "totalMs": 0.0, "maxMs": 0.0, "within": "spellState",
                   "apiPerIter": 0.0, "bytesPerIter": 0.0 }     // last two: offline only
  },

  // Frame sampling. Offline runs carry the fixed zeroed shape (no frames to sample).
  "fps": {
    "active":    { "seconds": 0, "frames": 0, "avgFps": 0, "msPerFrame": 0 },
    "suspended": { "seconds": 0, "frames": 0, "avgFps": 0, "msPerFrame": 0 },
    "deltaMsPerFrame": 0
  },

  "watched": 6,        // offline only — how many spells the poll scenario walked
  "failures": []       // offline only — assertion failures, empty on a clean run
}
```

Every number in that block is zeroed on purpose: it is a **shape**, not a capture. Nothing in this
file is citable evidence until a real bundle sits beside it.

Object keys are emitted in sorted order so two records diff cleanly.

One encoding wart worth knowing: Lua has a single table type, so an **empty** list and an empty map
are indistinguishable to the encoder and both come out as `{}`. A run with no failures therefore
emits `"failures": {}`, not `[]`. Non-empty lists encode as proper arrays.

## Field notes

- **`fps.deltaMsPerFrame`** is the number the in-game harness exists to produce: the per-frame cost
  of the addon being active, with load order and shared-frame ownership held fixed by *suspend*
  rather than by disabling the addon. It has a resolution floor of roughly ±0.3 ms/frame on a 60–80 s
  A/B, so treat anything below about 0.5 ms/frame as **unresolved**, not as zero, and read the bucket
  figures instead. It reads `0` unless **both** arms were sampled — with one arm empty a subtraction
  would report the whole frame time as the addon's cost.
- **`buckets[*].totalMs`** is Lua execution time only.
- **`buckets[*].bytesPerIter`** (offline) is garbage produced per iteration, isolated by a full
  collect either side. Allocation in a path running at combat frequency matters more than wall time.
- **`interface`** is the **client's** build TOC number, from `GetBuildInfo`'s fourth return — not the
  addon's `## Interface` line. It used to read `0`: `GetAddOnMetadata` does not expose the `Interface`
  TOC field, so the old lookup returned nil and every record stamped 0. `LibKa0s-Perf-1.0` minor 5
  fixed that, and `tests/test_perfsetup.lua:733` pins it, so an in-game record from the vendored copy
  stamps a real build. **A capture reading `interface: 0` is either offline** (no client involved —
  `tests/perf.lua:263` hardcodes 0) **or was taken against a lib older than Perf 5**, and that is
  worth saying in its `ANALYSIS.md`.
- **Frame limiters are not recorded**, and a pinned client produces an unusable delta the record
  cannot flag. Judge that from the arms: two arms at the same frame time, or at a round one like
  8.33 ms, means the client was capped.

### KickCD declares nesting but never observes it

Worth knowing **before** you read a KickCD report, because it changes what one of its lines means.

Containment is supplied at the recording call — `Perf.Note(key, ms, parentKey)` — and the library
only reports a parent as *observed* when that third argument was passed. Every one of KickCD's eight
bracketed buckets calls `Perf.Note(key, ms)` with **two** arguments and no `parentKey`:

| Bucket | Call site |
|---|---|
| `spellPoll` | `modules/Cooldowns.lua:447` |
| `pollSpell` | `modules/Cooldowns.lua:193`, `:201` (both exits) |
| `spellState` | `modules/IconGrid.lua:815` |
| `visibility` | `modules/IconGrid.lua:934` |
| `castEvent` | `modules/IconGrid.lua:948` |
| `iconApply` | `modules/IconGrid_Render.lua:746` |
| `cdText` | `modules/IconGrid_Render.lua:841`, `:849` (both exits) |
| `castTick` | `modules/Castbar.lua:692`, `:713` (both exits) |

So `observedWithin` is **never populated** in a KickCD record, and every KickCD report prints the
*"`<bucket>` declares itself within `<parent>` — not observed"* form for its nested buckets.

The declared tree in `core/PerfSetup.lua:93-102` — `pollSpell` and `spellState` within `spellPoll`,
`iconApply` within `spellState` — is therefore an **unverified claim**. It is a reasoned one (the
`SendMessage` dispatch is inline through CallbackHandler, so the spell-state handler really should
run inside `Cooldowns:Refresh`'s frame), but reasoning is not observation. An `ANALYSIS.md` **must
say so** rather than presenting the declared tree as measured containment, and must not subtract a
declared child from its declared parent as though the overlap were confirmed. Closing that gap —
threading `parentKey` through the call sites — is a legitimate action for a capture's `ANALYSIS.md`
to raise.

## How a capture is taken

In the client, on a **repeatable** fight — a training dummy with a fixed rotation, not a raid pull —
holding zone, group state and the loaded addon set fixed:

```
/kcd perf start [label]     # label says what was measured: dummy-mm-hunter, raid-nerubar-p2
/kcd perf measure a         # arm A: addon active. Pull; the arm records only while combat is up
/kcd perf measure b         # arm B: addon suspended. Fight the same fight
/kcd perf finish
/kcd perf report            # the summary a human reads
/kcd perf dump              # one line of JSON — the record the summary is built from
```

Then press **Copy** on the debug-log window (`Ctrl+C`, `Esc`). One paste carries the report, the dump
and the run's lifecycle lines — all three artifacts' raw material. `/kcd` is the addon's slash
command; `/kickcd` is the long form and works identically.

The same record is also on disk after a `/reload`, in the `KickCDPerfDB` global — a ring of the last
10 runs — inside the addon's SavedVariables file:

```
_retail_/WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua
```

Note the filename: WoW names the file after the **addon**, not after the saved-variable globals it
declares, so both `KickCDDB` and `KickCDPerfDB` live in `KickCD.lua`. `/reload` (or a clean logout)
is what flushes a finished run to disk.

The perf ring is deliberately a separate top-level global rather than part of the AceDB tree, so it
is never cloned by "copy profile", wiped by "reset profile", or swapped out by a profile switch —
see [schema.md](../schema.md).

## Capture index

One row per bundle, newest last.

| Bundle | Addon version | Label | What it measured |
|---|---|---|---|
| _(none yet)_ | | | |
