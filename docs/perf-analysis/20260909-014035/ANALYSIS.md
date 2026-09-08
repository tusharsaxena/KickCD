# Analysis — 20260909-014035

- **Addon:** KickCD 1.2.1 (record schema 2, client interface 120100)
- **Captured:** 2026-09-09 01:40 local, label `2026-09-09 01:36`
- **Who / where:** Sacrìlege-Frostmourne, level 90 Protection Paladin · Nexus-Point Xenas (no subZone) · party (5) / party
- **Delta:** +0.04 ms/frame — **unresolved below the floor**
- **Previous capture:** [`../20260807-131311/`](../20260807-131311/)

> **Stamp note.** The directory is stamped from `timestamp: 1788898235` in
> [`dump.json`](dump.json), which is `2026-09-09 01:40:35` local — the moment the record was emitted,
> matching the `01:40:35` prefix on the dump line in [`report.md`](report.md). The run's **label** is
> `2026-09-09 01:36`, its start. A stamp of `20260909-013635` would have come from the label, not
> from `timestamp`, and the store's own rule in [`../README.md`](../README.md) is that the stamp is
> rendered from the record's `timestamp` field. This bundle follows the record.

## Headline

Two combat arms, 67.2 s active against 62.0 s suspended, in a party-of-five fight at Nexus-Point
Xenas. The addon's measured cost is **3.67 ms/s of combat**, the total of its five top-level
buckets — about **0.05 ms per frame** at this capture's 72.3 fps, roughly six times below the
±0.3 ms/frame the A/B instrument can resolve. The +0.04 ms/frame frame-time delta is therefore
**unresolved**, exactly as predicted by the bucket figures, and says nothing either way. The one
thing in this record that is not routine is `spellPoll`'s `maxMs` of **9.64 ms** — a single poll pass that consumed 70 % of a 13.83 ms frame, and
5.5× the worst pass in the previous capture.

## The arms

Both figures come from [`dump.json`](dump.json)'s `fps` block; the rounded forms are in
[`report.md`](report.md).

| Arm | Seconds | Frames | Avg fps | ms/frame |
|---|---|---|---|---|
| active (addon running) | 67.19 | 4859 | 72.3173 | 13.8279 |
| suspended (addon inert) | 62.029 | 4499 | 72.5306 | 13.7873 |
| **delta** | +5.16 | +360 | −0.2133 | **+0.0407** |

The report's rounded `13.83` / `13.79` / `+0.04` in [`report.md`](report.md) reconcile with the
four-decimal figures above.

**Validated (`PERF_ANALYSIS.md` Step 2):** dump `addon` is `KickCD`, matching this repo; `version`
`1.2.1` matches `## Version: 1.2.1` in `KickCD.toc:5`; `schema` `2` matches `lib.SCHEMA = 2` in
`libs/LibKa0s/Perf.lua:42`; both arms have `frames > 0` (4859 active, 4499 suspended); and every
rounded figure in [`report.md`](report.md) reconciles with the four-decimal ones in
[`dump.json`](dump.json). No mismatch to report.

**The delta is unresolved, and that is not the same fact as zero.** The store's field note in
[`../README.md`](../README.md) puts the instrument's floor at roughly ±0.3 ms/frame on a 60–80 s A/B,
with anything under about 0.5 ms/frame to be read as unresolved. +0.0407 ms/frame is about a
seventh of the floor. It is *consistent* with the buckets — 3.67 ms/s ÷ 72.32 frames/s =
0.051 ms/frame — but consistency is not confirmation: an addon costing ten times this much would
have produced a delta the instrument still could not have separated from noise. At a seventh of the
floor the **sign carries no information either way**; only a backwards sign would have been a usable
tell, as the previous capture's −0.17 ms/frame was.

Both arms were combat-gated (`Experiment A RECORDING — combat started`, likewise B) and arm B ran
after an explicit `addon SUSPENDED — inert`, with no `/reload` between them — the three conditions
`performance-§7` puts on a comparable pair, all visible in the run log in [`report.md`](report.md).

## The buckets — what the addon actually cost

Every figure from [`dump.json`](dump.json)'s `buckets`; `ms/s` is `totalMs` over the **active** arm's
67.19 seconds, as [`report.md`](report.md) computes it. Buckets nest — **do not sum the column**.

| Bucket | Calls | Total ms | ms/s | Max ms | Parent |
|---|---|---|---|---|---|
| `spellPoll` | 810 | 210.5512 | 3.134 | 9.6400 | top level |
| `pollSpell` | 2450 | 99.4554 | 1.480 | 0.2961 | declares `spellPoll` — **not observed** |
| `spellState` | 1590 | 80.8323 | 1.203 | 0.2135 | declares `spellPoll` — **not observed** |
| `iconApply` | 3228 | 73.4586 | 1.093 | 0.1948 | declares `spellState` — **not observed** |
| `cdText` | 573 | 25.2480 | 0.376 | 0.1455 | top level |
| `castTick` | 778 | 9.1848 | 0.137 | 0.1345 | top level |
| `visibility` | 45 | 1.1934 | 0.018 | 0.1826 | top level |
| `castEvent` | 13 | 0.6886 | 0.010 | 0.0773 | top level |

The `ms/s` column matches the rounded one in [`report.md`](report.md) to three decimals for all
eight rows.

**Accounted cost: 3.674 ms/s** — the five top-level buckets, `spellPoll`, `cdText`, `castTick`,
`visibility` and `castEvent`. `pollSpell`, `spellState` and `iconApply` all sit inside `spellPoll`'s
subtree if the declared tree is real, and **nothing in this record verifies it**; the column is not
summed past the top level, because the report's own footer and `PERF_ANALYSIS.md` Step 4 both
forbid it.
The unverified containment is a reason to read the three nested totals as unattributed, not a reason
to add them on top.

**Declared nesting is not observed nesting.** Every one of KickCD's eight brackets calls
`Perf.Note(key, ms)` with two arguments and no `parentKey`, so `observedWithin` is never populated
and the report prints "— not observed" for all three nested rows. The tree in
`core/PerfSetup.lua:103-112` is a *reasoned* claim — `NS:SendMessage` dispatches inline through
CallbackHandler, so `IconGrid:OnSpellState` (`modules/IconGrid.lua:796`) really does execute inside
`Cooldowns:Refresh`'s bracket (`modules/Cooldowns.lua:400`) — but reasoning is not observation, and
nothing here subtracts a declared child from its declared parent.

**Every declared bucket fired.** All eight keys in the descriptor's `buckets` list
(`core/PerfSetup.lua:103-112`) appear in the table: `spellPoll`, `pollSpell`, `spellState`,
`iconApply`, `cdText`, `castEvent`, `visibility`, `castTick`. There are **no silent buckets** in this
run — the fight exercised the whole instrumented surface, including the cast bar. The one bracket the
descriptor names but never declares, `glowGate` (`IconGrid:RefreshAllGlows`), is still undeclared and
so is still invisible; `IconGrid:OnUnitCastEvent` calls it on every cast event
(`modules/IconGrid.lua:945`) and its cost is currently attributed to `castEvent`.

### Where the time goes, in the source

**`spellPoll` — 3.134 ms/s, 12.06 passes/s, 0.260 ms per pass.** This is `Cooldowns:Refresh`
(`modules/Cooldowns.lua:400`), a full re-poll of the watched-spell table. It is not driven by frame
rate: `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_USABLE` and `SPELL_UPDATE_CHARGES`
(`modules/Cooldowns.lua:529-531`) all route through `OnCooldownEvent`, which forwards into a
zero-delay coalescer built in `OnEnable` (`modules/Cooldowns.lua:553`) so a same-frame burst becomes
one pass on the next frame. 12.06 passes/s means the client fired those events in about twelve
distinct frames per second of this fight. The pass is proportional to the **watched-spell count**,
and 2450 `pollSpell` calls over 810 passes puts that at **3.02 spells** — a Protection Paladin's
three tracked interrupt/CC entries, against four for the previous capture's Warlock. A class or spec
with a longer list scales this bucket linearly.

**`pollSpell` — 1.480 ms/s, 0.0406 ms per call.** `Cooldowns:PollSpell`
(`modules/Cooldowns.lua:186`), bracketed above its guards on purpose so both exits are counted
(`:201`, `:209`). Per call it is five C API round-trips inside `buildSpellState` —
`GetSpellCooldown` (`modules/Cooldowns.lua:149`), `IsSpellUsable`, `GetSpellCharges`,
`GetSpellCooldownDuration` and the `rechargeHandle` lookup
(`modules/Cooldowns.lua:145-177`) — plus the `isPollable` gate. 0.04 ms for that is API cost, not
Lua cost, and there is no obvious slack in it.

**`spellState` → `iconApply` — 1.203 and 1.093 ms/s.** `IconGrid:OnSpellState`
(`modules/IconGrid.lua:796`) fans one payload out across `NS.Units.LIST`, touching only icons in each
instance's active pool. The **iconApply-per-spellState ratio is 2.03** (3228 / 1590), which reads
directly as *two units enabled* — target and focus — each holding an icon for the changed spell. This
ratio is the figure that survives a change of fight length and class, and it is the one to watch: a
user enabling a third unit moves it to ~3.0 and moves `iconApply`'s ms/s with it. Note also that
`spellState` fires **1.96 times per poll pass** (1590 / 810) even though only ~3 spells are watched:
`StateChanged` compares unequal for any spell parked on a cooldown, because
`C_Spell.GetSpellCooldownDuration` mints a fresh handle per call — the constraint `core/PerfSetup.lua`
documents at its head. Roughly two of the three watched spells were on cooldown at any moment, and
each re-emitted every pass.

**`cdText` — 0.376 ms/s, 8.53 ticks/s, 0.0441 ms per tick.** The shared 0.1 s ticker
`_tickAllTextIcons` (`modules/IconGrid_Render.lua:923`). 8.53/s against a nominal 10/s is the ticker
correctly pausing itself when the registered set empties (`:928-939`) — the burst-teardown exit that
bracket was widened to catch. Per tick it walks `_textIcons` and calls `_RenderCooldownText` on each;
cost is proportional to *visible cooldowns*, not to spell count.

**`castTick` — 0.137 ms/s, 11.58 calls/s.** `onUpdate` in `modules/Castbar.lua:706`, the addon's only
true per-frame handler, and it runs **only while a cast is up**. 11.58 calls/s against a 72.3 fps
client means a hostile cast was visible for roughly 16 % of this fight. Per-frame cost is 0.0118 ms —
two `SetValue` calls and a conditional `SetFormattedText`, exactly the shape the comment block at
`modules/Castbar.lua:687-705` describes.

**`visibility` and `castEvent` — 0.018 and 0.010 ms/s, together under 2 ms across the whole arm.**
Not worth optimising. Worth noting, though, that `visibility` fired **45 times against `castEvent`'s
13**: `IconGrid:RefreshVisibility` (`modules/IconGrid.lua:917`) has seven call sites and cast events
are only one of them, which is precisely why `core/PerfSetup.lua` stopped declaring `visibility`
within `castEvent`. This record supports that decision.

**The 9.64 ms `spellPoll` outlier.** One pass cost 37× the 0.260 ms mean and 70 % of a 13.83 ms
frame. The previous capture's worst pass was 1.7497 ms ([`../20260807-131311/dump.json`](../20260807-131311/dump.json)),
so this is 5.5× worse. No child bucket shows a matching spike — `pollSpell` maxed at 0.2961 ms,
`spellState` at 0.2135, `iconApply` at 0.1948 — so whatever cost the 9.64 ms happened **inside
`Cooldowns:Refresh` but outside every child bracket**, or inside a call the children make that is
itself unbracketed. The likeliest candidates are a first-poll `PollSpell` returning `nil` and driving
the vanished-spell branch (`modules/Cooldowns.lua:428-439`), or a glow start reached through
`Icon:Apply` — `LibCustomGlow`'s `*_Start` paths are not instrumented at all. A single 9.6 ms frame
is a visible hitch and this record cannot say what caused it, which is itself the finding.

## What the capture did not hold constant

Plenty, and the run log in [`report.md`](report.md) is the evidence.

- **The arms are not the same fight.** Arm A ran 67.19 s, arm B 62.03 s — a 5.16 s (8 %) difference.
  More importantly they are separated by **95 seconds** (`Experiment A ENDED` 01:37:44,
  `experiment B armed` 01:39:19), and nothing records what happened in between.
- **Group of five, in a party.** `context.group` reads `party (5) / party`. Four other players'
  addons, pets, spell effects and positions moved freely between the arms. The previous capture was
  solo, so nothing about environmental noise transfers between the two bundles.
- **A world zone with no subZone.** `context.zone` is `Nexus-Point Xenas`, `subZone` empty — not a
  training dummy on a fixed rotation, which is what the store's "How a capture is taken" section asks
  for. Passers-by are uncontrolled.
- **An earlier run was canceled.** `01:15:33 | [Perf] run CANCELED` in a different zone (Silvermoon
  City — The Bazaar) and a different group state (solo). Nothing from it is in this record, but it
  means the session had already been armed once.
- **The debug console was off for this run, and was on for the previous one.** This paste carries no
  `[Cooldowns]`, `[IconGrid]` or `[Cast]` lines at all, where
  [`../20260807-131311/report.md`](../20260807-131311/report.md) is dense with them after an explicit
  `[Debug] logging enabled`. `Cooldowns:Refresh` branches on `NS.State.debug` in at least four places
  inside its bracket — three table allocations and the GCD-probe `GetSpellCooldown` call
  (`modules/Cooldowns.lua:405-423`), per-spell id accumulation (`:435`, `:481-482`) and the summary
  print (`:494-515`) — so the two captures measure
  **different code paths through the same function**. Any `spellPoll` comparison between them is
  confounded by that, and the section below says so rather than quietly attributing the drop to the
  addon.
- **The client build moved.** `interface: 120100` here against `120007` in the previous record, and
  against the addon's own `## Interface: 120007` in `KickCD.toc`. This is the *client's* build TOC,
  not the addon's, so it is not a defect — but it is a second variable between the two captures, and
  the TOC line is now one build behind the client it was measured on.
- **Frame limiter unknown.** Both arms sit at 72.3 / 72.5 fps, close but not identical and not a
  round cap like 8.33 ms — so probably not pinned, but the record cannot say.

## What moved

Against [`../20260807-131311/`](../20260807-131311/), comparing `ms/s` and per-call figures only —
never raw `totalMs`, since the arms were 25.65 s and 67.19 s.

| Bucket | ms/s then → now | ms per call then → now | Calls/s then → now |
|---|---|---|---|
| `spellPoll` | 5.273 → 3.134 | 0.3390 → 0.2599 | 15.55 → 12.06 |
| `pollSpell` | 2.617 → 1.480 | 0.0421 → 0.0406 | 62.22 → 36.46 |
| `spellState` | 2.120 → 1.203 | 0.0465 → 0.0508 | 45.65 → 23.66 |
| `iconApply` | 1.950 → 1.093 | 0.0214 → 0.0228 | 91.30 → 48.04 |
| `cdText` | 0.447 → 0.376 | 0.0510 → 0.0441 | 8.77 → 8.53 |
| `castTick` | 0.453 → 0.137 | 0.0092 → 0.0118 | 49.20 → 11.58 |
| `visibility` | 0.064 → 0.018 | 0.0786 → 0.0265 | 0.82 → 0.67 |
| `castEvent` | 0.064 → 0.010 | 0.1487 → 0.0530 | 0.43 → 0.19 |

Call-ratio figures, which are the ones that survive a change of duration:

| Ratio | Then | Now | Reads as |
|---|---|---|---|
| `pollSpell` / `spellPoll` | 4.000 | 3.025 | watched-spell count: 4 → 3 |
| `spellState` / `spellPoll` | 2.935 | 1.963 | spells re-emitting per pass: ~3 → ~2 |
| `iconApply` / `spellState` | 2.000 | 2.030 | **units enabled: 2 → 2, unchanged** |

Accounted cost — top-level buckets only, on both sides — fell from **6.301 ms/s** to
**3.674 ms/s**, a 42 % drop. **Almost none of that is an addon improvement**, and the version is
identical (1.2.1 in both records). Three environmental causes account for it:

1. **One fewer watched spell.** A Protection Paladin's 3 against a Destruction Warlock's 4, straight
   off the `pollSpell` ratio. `spellPoll` is linear in that count, so ~25 % of the drop is the class.
2. **A bit over a fifth fewer poll passes per second** (22 %), 15.55 → 12.06, because the game
   fired fewer `SPELL_UPDATE_*` bursts in this fight.
3. **The debug console was off.** The per-call cost of `spellPoll` fell 23 % (0.3390 → 0.2599 ms)
   while its own children's per-call costs went the *other* way — `spellState` +9 %, `iconApply` +7 %,
   `pollSpell` −3 %. A parent getting cheaper per call while its children get dearer is the signature
   of work leaving the parent's own body, and the debug branches are exactly that work. This is the
   confound named in the section above; it is not evidence of an optimisation.

`castTick` collapsing from 49.20 to 11.58 calls/s is purely how much hostile casting happened, not a
code change. Its per-call cost rose 28 % (0.0092 → 0.0118 ms), which on 778 samples against 1262 is
within the noise of a shorter, sparser sample of the same handler.

Two things genuinely got better and are not explained by environment: `castEvent` per call fell 64 %
(0.1487 → 0.0530 ms) and `visibility` per call fell 66 % (0.0786 → 0.0265 ms). Both are tiny samples
(13 and 45 calls), and the earlier capture's cast-event work included the first-time `Show()` of two
grids, so the fair reading is "the previous numbers were first-call inflated", not "these paths were
optimised".

One thing got worse: `spellPoll` `maxMs` 1.7497 → 9.6400.

## Actions

1. **Instrument the 9.64 ms outlier before doing anything else.** The record cannot attribute it. Add
   a bracket around `LibCustomGlow`'s start/stop calls — the `glowGate` key `core/PerfSetup.lua`
   already anticipates but does not declare — covering `IconGrid:RefreshAllGlows` and the
   `Icon:StartGlow` / `Icon:StopGlow` pair at `modules/IconGrid_Render.lua:460-490`. Saves nothing by
   itself; it is what makes the next capture able to say whether a 9.6 ms frame is a glow start, and
   the risk is one more bracket's overhead on a path that fires a few times a fight.
   *New here — no issue, deviation ID or review finding owns this; checked against the addon's open
   issue store (#1–#5, #7–#10, #15).*
2. **Thread `parentKey` through the three nested call sites** so the declared tree becomes an
   observed one — `Perf.Note("pollSpell", ms, "spellPoll")` at `modules/Cooldowns.lua:201` and `:209`,
   `Perf.Note("spellState", ms, "spellPoll")` at `modules/IconGrid.lua:814`, and
   `Perf.Note("iconApply", ms, "spellState")` at `modules/IconGrid_Render.lua:790`. This is what
   turns the declared tree into a verified one, so a future bundle can say the containment was
   observed rather than merely reasoned. Risk, stated against what the library actually does: nothing
   is refused. `P.Note` (`libs/LibKa0s/Perf.lua:402`) counts `calls`, `totalMs` and `maxMs`
   unconditionally at `:415-417` **before** it looks at `parentKey`; `:418-427` then records the
   first `parentKey` into `observedWithin` and, on a later contradicting one, merely sets
   `observedMixed`. Both fields travel into the record beside the declared `within` (`:695-710`) with
   no comparison between them. So a wrong `parentKey` yields a **flagged-mixed bucket** — surfaced in
   the report's nesting sentence (`libs/LibKa0s/Perf.lua:252-273`) — while the measurement is still
   counted, not a rejected note.
   *New here — no issue, deviation ID or review finding owns this.*
3. **Take the next capture on a training dummy, solo, with the console in a known state.** Every
   comparison in "What moved" above is weakened by the group, the zone and the debug flag moving at
   once. Two captures now exist and neither is controlled; a third that is would make the ratio table
   mean something.
   *New here — no issue, deviation ID or review finding owns this.*
4. **Consider bumping `## Interface` in `KickCD.toc`** from `120007` to the `120100` this client is
   running. Not a perf action, and out of scope for this command, but the divergence is visible in
   this record. *New here — no issue, deviation ID or review finding owns this.*

No code was changed by this command.
