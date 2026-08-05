# Performance run records

**In-game captures only.** A human runs `/kcd perf` in a live client and exports the record; a script
cannot produce one, which is why this store exists at all (`automated-tests-§7`). **Offline**
scenario runs come from `tests/perf.lua`, are driven by `tests/_kit/run-automated-tests.sh`, and live
in the bundle for the run that produced them, under [`../automated-tests/`](../automated-tests/).

See [docs/performance.md](../performance.md) for how to produce a capture and how to read one.

This directory is **standing and cumulative** rather than tied to one investigation, so runs compare
across addon versions. Records are committed as **evidence**: the raw capture outlives the write-up
that interprets it, and an interpretation without its record is an assertion (`performance-§8`).

**The directory is currently empty.** No in-game capture has been committed yet. That is a real gap,
not an oversight in the tooling — and it is why `core/PerfSetup.lua` no longer quotes figures from
the early uncommitted capture its two nesting decisions were taken off. The first committed record
here is what makes those decisions citable.

## Naming

```
<YYYY-MM-DD>-ingame-<label>.json
```

`label` says what was measured, not what was concluded — `dummy-mm-hunter`, `raid-nerubar-p2`.
A record is never renamed to match a later convention; a frozen file stays as it was written.

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
  "interface": 0,               // see the field note below
  "timestamp": 1785110400,      // epoch seconds
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
file is citable evidence until a real record sits beside it.

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
- **`interface`** reads `0`. `GetAddOnMetadata` does not expose the `Interface` TOC field, so the
  lookup returns nil and the record stamps 0; offline runs have no client at all, so 0 is correct
  there. Do not read this field as the client version.
- **Frame limiters are not recorded**, and a pinned client produces an unusable delta the record
  cannot flag. Judge that from the arms: two arms at the same frame time, or at a round one like
  8.33 ms, means the client was capped.

## Reading captures off disk

In-game runs persist to the `KickCDPerfDB` global — a ring of the last 10 runs — inside the addon's
SavedVariables file:

```
_retail_/WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua
```

Note the filename: WoW names the file after the **addon**, not after the saved-variable globals it
declares, so both `KickCDDB` and `KickCDPerfDB` live in `KickCD.lua`. `/reload` (or a clean logout)
is what flushes a finished run to disk.

The perf ring is deliberately a separate top-level global rather than part of the AceDB tree, so it
is never cloned by "copy profile", wiped by "reset profile", or swapped out by a profile switch —
see [saved-variables.md](../saved-variables.md).
