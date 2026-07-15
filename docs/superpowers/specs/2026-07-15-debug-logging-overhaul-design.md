# Design — Informative, standard-compliant debug logging

**Date:** 2026-07-15
**Status:** Approved design → implementation plan
**Standard:** Ka0s WoW Addon Standard — `standards/debug-logging.md` §3 (format), §4 (sink), §8 (coverage), §9 (coalescing), §10 (settings). Reference implementation: LootHistory `modules/DebugLog.lua` + `NS.Debug("Set", …)` / `NS.Debug("Init", …)` call sites. Coalescing reference: ConsumableMaster `eab4d50` (per-item spam → one summary line per pass, list-building behind the gate).

## Problem

KickCD's debug console already meets the standard's **format** (§3): `DebugLog.FormatPlain` / `FormatColored` produce `<HH:MM:SS> | [<Tag>] <content>` verbatim. But the *content* falls short of §8/§9/§10:

- **Spam on hot paths (violates §9).** `Cooldowns` logs `poll [id] …` for every watched spell on every `Refresh`, plus `emit [id] …` per change; `IconGrid_Render` logs `apply [id] …` per icon per state application. In combat this is dozens of lines/sec (see the user's repro: `poll`/`apply`/`emit` repeating every tick).
- **Missing coverage (violates §8).** No boot/lifecycle summary, no profile-switch trace, no combat-state trace, no rebuild summary, no cast-gate trace, no view-open trace.
- **Settings changes not logged at all (violates §10).** Nothing logs at the schema write seam.
- **Sink not secret-safe (violates §4).** `NS.Debug` calls `string.format` on raw `...`; a secret-tainted arg (e.g. `charges` in combat) would raise inside the sink and freeze whatever ticker logged it until `/reload`.

## Goal

Rework debug **content** so a log read back after a repro tells the story of what the addon did (§8), with no per-item/per-tick spam (§9), every settings change captured once (§10), and a sink that can never error in combat (§4). Format (§3) is unchanged.

## Non-goals

- No change to `FormatPlain` / `FormatColored`, the console window, Copy/Clear, the session-only flag, or `SetEnabled` (§1–3, §5–7 already compliant).
- No message-bus, `Settings.Schema`, or render-behavior changes.
- No new persisted state (debug stays session-only).

## Standardized tag vocabulary

Short, semantic, one word each (§3 — open set): `Init`, `Migrate`, `Profile`, `Combat`, `Cooldowns`, `IconGrid`, `Cast`, `Set`, `Spells`, `Open`, plus the existing `Debug` bracket line. Every new/kept call site uses one of these.

## A. Secret-safe sink (§4) — `modules/DebugLog.lua`

Route every `...` arg through a secret-safe stringifier before `string.format`, keeping the zero-alloc gate first:

```lua
local function secretSafe(v)
    if _G.issecretvalue and _G.issecretvalue(v) then return "secret" end
    return v
end

function NS.Debug(tag, fmt, ...)
    if not (NS.State and NS.State.debug) then return end   -- gate first (zero-alloc when off)
    local n = select("#", ...)
    local msg
    if n > 0 then
        local args = { ... }
        for i = 1, n do args[i] = secretSafe(args[i]) end
        msg = string.format(fmt, unpack(args, 1, n))
    else
        msg = fmt
    end
    if NS.DebugLog and NS.DebugLog.Add then NS.DebugLog:Add(tag, msg) end
end
```

- Substituting `"secret"` for a guarded value means the *number* is not shown, but the line still lands — better than an error that freezes the feature.
- `Cooldowns:DebugDump`'s manual `safeStr` can stay (it also handles `nil`), but no call site is *required* to pre-sanitize anymore.
- Pure and headless-testable: `secretSafe` is exposed (e.g. `DebugLog.secretSafe`) for a unit test; under the harness `issecretvalue` is absent so it's an identity pass-through.

## B. Settings capture (§10) — `settings/Panel.lua`

Every settings mutation funnels through `Helpers.Set(path, section, value)` (Panel.lua:70 — widgets at :643/:679/:734/:797, slash + lock via `SetAndRefresh` → `Helpers.Set` at :1061). Log there, once, as `[Set] <path> = <value>`.

**Coalesce drags.** Color/slider commits call `Helpers.Set` on every throttled drag tick (~20/sec, Panel.lua:797). A raw log would spam. Use a per-path trailing debounce so a drag logs one settled value:

```lua
local SET_LOG_DEBOUNCE = 0.3
local pendingSet, setArmed = {}, {}

-- Compact value formatter: scalars direct; RGBA/array tables as {a,b,c,d}.
local function fmtSetValue(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function logSet(path, value)
    if not (NS.State and NS.State.debug) then return end   -- zero-alloc gate
    pendingSet[path] = value
    if setArmed[path] then return end
    setArmed[path] = true
    C_Timer.After(SET_LOG_DEBOUNCE, function()
        setArmed[path] = nil
        local v = pendingSet[path]; pendingSet[path] = nil
        if NS.State and NS.State.debug then
            NS.Debug("Set", "%s = %s", tostring(path), fmtSetValue(v))
        end
    end)
end
```

Call `logSet(path, value)` from inside `Helpers.Set` (before/after the `parent[key] = value` write). Discrete writes (checkbox, dropdown, `/kcd set`) log promptly (one write → one line ~0.3s later); a drag collapses to one line with the final value.

**No downstream re-echo (§10).** Config reactors (`Cooldowns:OnConfigChanged`, IconGrid/Castbar config handlers) must not restate the value. They already don't. A `Rebuild` triggered by a spells-config change logs a `[Cooldowns] rebuild …` *material-effect* line (permitted), not a value restatement.

## C. Key functional-flow traces (§8) — one gated line each

| Tag | File / seam | Line content |
|---|---|---|
| `Init` | `core/KickCD.lua` `NS:OnEnable` | `KickCD v<VERSION>, schema v<db.global.schemaVersion>, profile '<current key>'` |
| `Migrate` | `core/Database.lua` migrate loop | `v%d -> v%d (%s)` — **only when a step actually runs** (none at `CURRENT_DB_VERSION = 1`; this is the seam for future migrations) |
| `Profile` | `core/Database.lua` `OnProfileChanged` | `switched to '<key>'` |
| `Combat` | `core/State.lua` combat handler | `entered` / `left` (one per transition, where `COMBAT_STATE` is sent) |
| `IconGrid` | `modules/IconGrid.lua` visibility gate | `visibility <mode>: shown` / `hidden` — **only on transition** (track last-shown bool; no line when unchanged) |
| `Cast` | `modules/IconGrid.lua` `RefreshAllGlows` | `target cast gate: interruptible on` / `off` — **only on transition** (the function already short-circuits when the gate hasn't moved). **No secret fields** (no spellID/name/notInterruptible value). |
| `Spells` | `settings/Spells.lua` mutation points | `enable <id>` / `disable <id>` / `add <id>` / `remove <id>` (one per edit, at the db.profile.spells mutation before the `CONFIG_CHANGED{spells}` send at :268) |
| `Open` | `core/KickCD.lua` `OpenSettings` | `settings panel` |

`Init`'s watched-spell count is intentionally NOT in the boot line — the first `[Cooldowns] rebuild …` line (§D) carries it, keeping the boot line to load-time facts (§8 "one-line boot summary").

## D. Consolidation (§9) — `modules/Cooldowns.lua`, `modules/IconGrid_Render.lua`

- **`Cooldowns:Refresh`** — delete the per-spell `poll` / `emit` / `drop` dprints. Accumulate changed ids into lists (built **only when debug-on**), and after the pass emit **one** line *only when ≥1 spell changed state*:
  `[Cooldowns] k/N changed: ready=[<ids>] active=[<ids>] drop=[<ids>]`
  (omit an empty bucket; a no-change pass logs nothing). `k` = changed count, `N` = watched count.
- **`Cooldowns:Rebuild`** — replace the per-spell `skipping` dprint with one summary: `[Cooldowns] rebuild <class>/<spec>: N watched (M skipped)`.
- **`IconGrid_Render`** — delete the per-icon `apply active/charging/ready` lines (:534/:549/:559). The `[Cooldowns] … changed` summary already tells the state story. Keep the rare `duplicate spellID` warning in `IconGrid.lua:272`.

All list/`table.concat` building stays behind the `NS.State.debug` gate (§4 zero-alloc), mirroring `eab4d50`.

## E. Testing — `tests/`

Extend the headless harness (new `tests/test_debuglog.lua` cases or a `tests/test_cooldowns.lua` addition; both suites already load these modules):

1. **Secret-safe sink** — `NS.Debug("T", "%s", <mock secret>)` (stub `issecretvalue` to true for a sentinel) produces a line containing `secret` and does not error; with `issecretvalue` absent/false, the value passes through. `FormatPlain` output unchanged.
2. **Cooldowns coalescing** — drive `Refresh` with a stubbed watched set where 2 of N change: exactly one `[Cooldowns]` line, containing the changed ids; a pass with no changes yields zero new lines. (Spy via `DebugLog:BufferSize()` / `LastLine()`.)
3. **Settings capture** — `Helpers.Set` on a scalar path yields, after `__flushTimers()`, exactly one `[Set] <path> = <value>` line; two rapid writes to the same path within the window collapse to one line with the final value; an RGBA table formats as `{r,g,b,a}`.

`lua tests/run.lua` exits 0; `luacheck .` introduces no new warnings.

## Standard compliance

- **Fixes** the §4 deviation (unguarded sink → secret-safe).
- Satisfies §8 (coverage), §9 (coalescing), §10 (settings-at-seam, no re-echo).
- §1–3, §5–7 already compliant and untouched.
- No other deviation introduced; closed message bus, Schema, and secret-value handling on the functional paths are unchanged.

## Files touched

- `modules/DebugLog.lua` — secret-safe sink (A).
- `settings/Panel.lua` — `[Set]` capture with per-path debounce (B).
- `core/KickCD.lua` — `Init`, `Open` (C).
- `core/State.lua` — `Combat` (C).
- `core/Database.lua` — `Profile`, `Migrate` seam (C).
- `modules/IconGrid.lua` — `IconGrid` visibility + `Cast` gate transitions (C).
- `modules/Cooldowns.lua` — `Rebuild` summary + `Refresh` change-summary; delete per-spell dprints (C, D).
- `modules/IconGrid_Render.lua` — delete per-icon `apply` lines (D).
- `settings/Spells.lua` — `Spells` mutation lines (C).
- `tests/` — new coverage (E).
