# Analysis — 20260807-131311

- **Addon:** KickCD 1.2.1 (record schema 2, client interface 120007)
- **Captured:** 2026-08-07 13:13 local, label `2026-08-07 13:09`
- **Who / where:** Lânfear-Frostmourne, level 90 Destruction Warlock · Silvermoon City — Falconwing Square · solo
- **Delta:** −0.17 ms/frame — **unresolved** (inside the ±0.3–0.5 ms/frame floor) **and sign-backwards**
- **Previous capture:** none — this is the first bundle in the store

The directory stamp is `dump.timestamp` = `1786088591` rendered local (`date -d @1786088591`), which is
the moment of the dump, 13:13:11 — about 3½ minutes after the run's `label` start of 13:09. Nothing
was reconstructed.

## Headline

Two combat-gated arms in a solo world fight in Falconwing Square. KickCD's own bracketed code cost
**6.30 ms per second of combat** if the declared bucket nesting is real, and at most **12.99 ms/s** if
it is not — **0.09 to 0.19 ms per rendered frame** against a ~14.5 ms frame. The frame-time delta came
out at **−0.17 ms/frame**: below the instrument's floor *and* pointing the wrong way (the suspended arm
read slower), so it says nothing about the addon and everything about the environment moving between
the arms. All eight declared buckets fired; none of the three declared parent relationships was
observed. Nothing here needs fixing — the addon's cost is roughly 0.6–1.3% of wall clock — but the
capture itself is weak evidence (unequal arms, a city square, arm A armed mid-fight) and the nesting
gap keeps the accounted total a range instead of a number.

## The arms

Both figures from [`dump.json`](dump.json)'s `fps` block; the rounded forms are in
[`report.md`](report.md).

| Arm | Seconds | Frames | Avg fps | ms/frame |
|---|---|---|---|---|
| active (addon running) | 25.6520 | 1772 | 69.0784 | 14.4763 |
| suspended (addon inert) | 39.7170 | 2711 | 68.2579 | 14.6503 |
| **delta** | +14.0650 | +939 | −0.8205 | **−0.1740** |

The delta is **unresolved**. `fps.deltaMsPerFrame` is a difference of two noisy aggregates with a
resolution floor near ±0.3 ms/frame on a 60–80 s arm; these arms are 25.7 s and 39.7 s, *shorter* than
the window that floor was measured on, so the effective floor here is wider, not narrower. −0.17 sits
comfortably inside it. This is a statement about the instrument, not about the addon — the buckets
below are what measured KickCD.

The sign is also **backwards**: the arm with the addon *suspended* rendered 0.17 ms/frame slower than
the arm with it active. An addon cannot make frames cheaper by running, so this is the tell that the
environment moved between the two windows. It is consistent with the arms being different fights
(`performance-§7`: combat gating equalizes duration, never environment) — and here it did not even
equalize duration: arm B ran **55% longer** than arm A.

Both arms landed within 1.2% of each other at ~68–69 fps / ~14.5 ms per frame. That is not a round
limiter figure (8.33, 16.67), so there is no visible sign of a pinned client, but two arms this close
in a scenario this variable is what an unresolved measurement looks like.

## The buckets — what the addon actually cost

Every figure from [`dump.json`](dump.json)'s `buckets`; `ms/s` is `totalMs` over the **active** arm's
25.6520 s, as [`report.md`](report.md) computes it. Ordered by `ms/s`. Buckets nest — **do not sum the
column**.

| Bucket | Calls | Total ms | ms/s | Max ms | Parent |
|---|---|---|---|---|---|
| `spellPoll` | 399 | 135.2610 | 5.273 | 1.7497 | — (top level) |
| `pollSpell` | 1596 | 67.1303 | 2.617 | 0.7148 | declares `spellPoll` — **not observed** |
| `spellState` | 1171 | 54.3927 | 2.120 | 1.4186 | declares `spellPoll` — **not observed** |
| `iconApply` | 2342 | 50.0322 | 1.950 | 1.3961 | declares `spellState` — **not observed** |
| `castTick` | 1262 | 11.6115 | 0.453 | 0.0560 | — (top level) |
| `cdText` | 225 | 11.4686 | 0.447 | 0.1739 | — (top level) |
| `visibility` | 21 | 1.6512 | 0.064 | 0.2628 | — (top level) |
| `castEvent` | 11 | 1.6358 | 0.064 | 0.3104 | — (top level) |

**Total accounted cost is a range, not a number**, and the reason is the nesting gap. Counting only
the four top-level buckets plus `spellPoll` — i.e. taking the declared tree at its word — the addon
cost **161.63 ms over 25.65 s = 6.30 ms/s = 0.091 ms/frame**. Summing all eight as if nothing nested
gives **333.18 ms = 12.99 ms/s = 0.188 ms/frame**. The truth is one of those, and this capture cannot
say which, because containment was never recorded.

**The declared tree is an unverified claim.** `core/PerfSetup.lua` declares `pollSpell` and
`spellState` within `spellPoll`, and `iconApply` within `spellState`, but every KickCD call site calls
`Perf.Note(key, ms)` with two arguments and no `parentKey`, so the library never populates
`observedWithin` — hence the report's three *"declares itself within … — not observed"* lines and its
`do not sum` footer. This is a known, documented property of KickCD's instrumentation
([`../README.md`](../README.md) → *KickCD declares nesting but never observes it*), not a surprise from
this run. It is reasoned (the `Ka0s_KickCD_SPELL_STATE` dispatch is inline through CallbackHandler, so
the spell-state handler really should run inside `Cooldowns:Refresh`'s frame) — but reasoning is not
observation, and no child is subtracted from a parent anywhere above.

**Call ratios**, which survive a change of combat duration in a way `totalMs` does not:

| Ratio | Value | Reading |
|---|---|---|
| `pollSpell` / `spellPoll` | **exactly 4.00** (1596 / 399) | one poll per watched spell per pass; the run log's rebuild line says `4 watched (19647,30283,6789,5782)` |
| `iconApply` / `spellState` | **exactly 2.00** (2342 / 1171) | two icons applied per state change — the target grid and the focus grid, which is the dual-tracking design working |
| `spellState` / `spellPoll` | 2.93 (1171 / 399) | ~3 of the 4 watched spells changed state per pass, matching the log's dominant `3/4 changed` lines |
| `spellPoll` per frame | **0.225** (399 / 1772) | the `SPELL_UPDATE_*` coalescer holds — the poll ran on 22.5% of frames, never the "many times per frame" the chatty events would otherwise cause (`modules/Cooldowns.lua:477-483`) |

**Per-call costs** are all small and none is a red flag: `spellPoll` 0.339 ms per pass (its 1.75 ms
worst pass is the run's largest single bracket), `spellState` 0.046 ms, `pollSpell` 0.042 ms,
`iconApply` 0.021 ms, `castTick` 0.009 ms. `spellPoll` is the addon's dominant cost at 84% of the
top-level accounted total, which is what an interrupt tracker should look like — the poll *is* the
addon.

**No bucket was absent.** All eight declared brackets fired, so this run exercised every instrumented
path: cooldown polling, icon state, icon render, cooldown text, cast ticking, cast events and
visibility. `visibility` fired 21 times against **14** visibility transitions logged inside the arm-A
window, so the bracket covers evaluations that resolved to no change as well as the ones that flipped
— worth knowing before reading that bucket as a transition count.

`interface` reads **120007**, a real client build rather than the legacy `0`, confirming the vendored
`LibKa0s-Perf-1.0` is minor 5 or later.

## What the capture did not hold constant

Almost nothing, and this is the capture's main weakness.

- **Arm durations differ by 55%** — 25.65 s active against 39.72 s suspended
  ([`dump.json`](dump.json) `fps`). Combat gating equalized nothing here because the two fights were
  not the same fight.
- **The venue is a populated capital**, Silvermoon City — Falconwing Square. `performance-§7` asks for
  a repeatable fight — a training dummy on a fixed rotation, somewhere with no other players. A world
  fight in a city square is neither repeatable nor isolated, and other players' spell effects land in
  both arms unequally.
- **Arm A was armed mid-combat.** The run log shows `[Combat] entered` at 13:11:09, the arm armed at
  13:11:11, and `RECORDING — combat started` fire immediately on arming. Arm A therefore begins ~2 s
  into a fight already underway. Arm B was armed at 13:12:15, *before* `[Combat] entered` at 13:12:23,
  so it captured its fight from the pull. The arms did not sample the same phase of a fight.
- **A 46-second gap sits between the arms** (A ended 13:11:37, B started recording 13:12:23), with the
  addon suspended at 13:12:15.
- **Arm B is unverifiable from the log**, inherently: a suspended KickCD emits nothing, so there is no
  `[Cooldowns]` or `[Combat]` output between 13:12:15 and 13:13:08 to say what the second fight
  actually was. This is a property of the suspend contract, not a defect of the run — but it means the
  only evidence the two arms are comparable is the player's memory of them.

**What the log does confirm:** both arms were combat-gated (each `RECORDING` follows a combat entry
and each `ENDED` follows `[Combat] left` / the arm's own close), arm B really was suspended
(`addon SUSPENDED — inert` at 13:12:15, `RESUMED` at 13:13:08), and **no `/reload` landed between the
arms** — the single `[Init] KickCD v1.2.1` line sits at 13:09:59, before the run, and never repeats.
Those are the three conditions `performance-§7` puts on a comparable pair, and all three hold.

## What moved

**First capture — nothing to diff against; every figure above is a baseline reading.** The store's
`README.md` said plainly that it was empty and that the gap was real; this bundle closes it. From here
on, compare on `ms/s` and the call ratios above rather than on `totalMs`, which is a function of how
long the fight ran.

One near-miss worth recording so the next capture does not have to rediscover it:
`modules/Cooldowns.lua:184` still carries a comment citing *"spellPoll totaled 125.02 ms"* from an
early **uncommitted** capture. `core/PerfSetup.lua` was scrubbed of those figures precisely because
they were not citable; that one was missed. This run's committed 135.26 ms is now the citable number,
and the two are not comparable anyway — different fight, different duration.

## Actions

1. **Thread `parentKey` through the four nested-bucket `Perf.Note` call sites** so containment is
   observed rather than declared: `modules/Cooldowns.lua:193` and `:201` (`pollSpell`, both exits),
   `modules/IconGrid.lua:815` (`spellState`) and `modules/IconGrid_Render.lua:746` (`iconApply`).
   The other seven sites bracket top-level buckets and are correctly two-argument. The declared tree
   they would confirm is `core/PerfSetup.lua:93-101`. Until this lands, every KickCD analysis has to
   report the accounted total as the 6.30–12.99 ms/s range above instead of a figure. This is an
   instrumentation gap this capture exposed and it is new here — the store's `README.md` documents the
   behaviour, but nothing in the issue store tracks closing it.
2. **Re-capture on a training dummy with a fixed rotation** if a resolved frame-time delta is wanted:
   equal-length arms, both armed *before* combat, back to back, somewhere quiet. Or accept the
   alternative reading — at 0.09–0.19 ms/frame the addon is an order of magnitude under the
   instrument's floor and the delta will *never* resolve, in which case stop capturing arm B for that
   purpose and read the buckets alone. Either is defensible; drifting between them is not.
3. **Correct the stale figure at `modules/Cooldowns.lua:184`** to cite this bundle, or drop the number
   from the comment. Comment-only, no behaviour change.

None of the three is a performance defect. The addon's measured cost in this run is roughly 0.6–1.3%
of wall clock, and no single bracket exceeded 1.75 ms.
