# 02 — Proposed changes (KickCD, 2026-10-07)

This document is the HLD and LLD for the findings in `01_FINDINGS.md`. Each change ID (`C-0n`) maps to
one finding (`F-00n`). Standard resolved: **Ka0s WoW Addon Standard v2.76.1 (2026-10-07)**. See
`01_FINDINGS.md` for how each section file was obtained.

Every change below lands in KickCD's own files. **None targets `libs/` or `tests/_kit/`.**

## HLD — themes

### T1: A cache must not outlive the thing it caches (C-01)

`Castbar`'s `lastGridLayout` cache exists so the cast bar can re-anchor without asking IconGrid. The
payload contract (`docs/message-bus.md`, `{ unit, gridFrame, primaryIcon|nil, width, height }`) says
`primaryIcon` may be nil. The consumer reads nil as "missing field" when it really means "no primary
icon".

- **Chosen:** always copy `primaryIcon` from the payload, nil included. Keep the `gridFrame` guard,
  because IconGrid always sends a grid frame and that guard costs nothing.
- **Rejected:** having IconGrid send a sentinel such as `false` for "empty". That would widen the closed
  message contract (`architecture-§4`) to fix a consumer bug, and every other consumer would have to
  learn the sentinel.
- **Rejected:** dropping the cache and always calling `IconGrid:GetPrimaryIcon`. That works, but it
  turns a message-driven read into a cross-module call on every re-anchor, which is the coupling the
  bus exists to avoid.

### T2: Character-safe truncation (C-02)

**Option A (preferred, cross-repo):** add an additive member to `LibKa0s-Core-1.0`, for example
`lib.Utf8Prefix(s, n)`, which returns the first `n` characters plus a flag saying whether it cut. Both
current consumers then adopt it: KickCD here, and `../MultiMeters/modules/Row_NameCell.lua:280`, which
carries its own `utf8Truncate`. That makes two consumers with the same semantics and no per-consumer
flag, so the helper passes `anti-patterns` #55's sharing test. The library already holds the
character-count idiom privately (`OptionsIds.lua`'s `charCount`). LibKa0s would bump the Core minor,
cut a release, and re-vendor into every consumer as its own commit (`library-stack-§7`).

**Option B (local fallback):** a six-line file-local helper in `modules/Castbar.lua`. This is
acceptable if the consolidated plan does not want a LibKa0s release for it, but it makes the second
private copy in the collection.

**Rejected:** the client globals `strlenutf8` / `string.utf8sub`. They are not available headless, so
the change would be untestable in the gate (MultiMeters' comment gives the same reason).

**Decision for the consolidator:** A if this cycle already ships a LibKa0s release, otherwise B.

### T3: A refusal must not act (C-03, C-04)

`debug-logging-§5` says the bare `/<slash> debug` toggles the window, and that the handler falls back
to *usage* for anything else. Today the unknown-word path re-enters the bare branch, so a typo both
refuses and toggles. The fix splits "print the sub-verb list" out of the bare branch so both paths share
it and only the bare path toggles. C-04 goes in the same function: the two topic verbs read an optional
unit (`target` or `focus`, default `target`).

### T4: One trigger, one meaning (C-05)

The glow gate's cache key must cover every input the triggers read. Two options:

- **(a)** Add `inst.isCasting()` to the gate tuple, so `target_casting` refreshes on any cast.
- **(b)** Redefine the `target_casting` glow trigger as hostile-only, to match the gate.

Option (a) keeps the trigger matching the grid's own `target_casting` visibility mode, which counts any
cast (`modules/IconGrid_Visibility.lua:71-72`). **Recommend (a)**, unless the owner prefers (b).

### T5: Announce only what a listener needs (C-06)

Cooldowns has no use for `general`. The master switch already stands Cooldowns down and up through the
Lifecycle latch, and `Cooldowns:Resume` rebuilds. Narrow its `OnConfigChanged` filter to `spells`.

### T6: Deferred and hygiene (C-07, C-08, C-09)

- **C-07 (defer):** per-pair seeding in `BuildSpells`, so defaults reach `nil` pairs only. Nobody is
  affected today. Re-check trigger: the first spec added to `defaults/Spells.lua` after 1.4.0.
- **C-08:** tighten the lint whitelist.
- **C-09:** measure before changing.

## Upstream change-set

**No defects upstream.** If T2 Option A is chosen, there is one additive request:

| Repo | File | Change | Minor | Consumer re-vendor |
|---|---|---|---|---|
| `LibKa0s` | `LibKa0s/Core.lua` (`LibKa0s-Core-1.0`) | add `lib.Utf8Prefix(s, n)` → `prefix, cut`, pure Lua, nil- and secret-safe (returns `s, false` for a secret, as `truncateName` does today); unit case in the library's own suite | Core 10 → 11 | every consumer takes the release as its own commit; KickCD and MultiMeters then adopt it in a separate commit |

## LLD

### C-01 → F-001: cache `primaryIcon` verbatim

`modules/Castbar_Events.lua`, `Castbar:OnGridLayout`. Current code:

```lua
if payload.gridFrame   ~= nil then inst.lastGridLayout.gridFrame   = payload.gridFrame   end
if payload.primaryIcon ~= nil then inst.lastGridLayout.primaryIcon = payload.primaryIcon end
```

Proposed:

```lua
if payload.gridFrame ~= nil then inst.lastGridLayout.gridFrame = payload.gridFrame end
-- nil is a real state: the grid laid out with no icons. Keeping the old button
-- would anchor the bar to a pooled, point-less frame (KickCD review 2026-10-07 F-001).
inst.lastGridLayout.primaryIcon = payload.primaryIcon
```

Also correct the comment above it ("an empty payload doesn't blank the cache"), which is what the bug
encoded.

- **Risk:** low. `resolvePrimaryIcon` (`modules/Castbar.lua:219-224`) already falls back to
  `IconGrid:GetPrimaryIcon`, which also answers nil for an empty grid, and `ApplyAnchor` then takes
  `resolveGridFrame`.
- **Test:** add a case to `tests/test_castbar_frame.lua`. Enable target with a seeded list, `Layout`,
  then empty the list (`Database:SetSpellEnabled(..., false)` for every entry →
  `FireConfigChanged("spells")`). Assert the cast bar's point-1 `relativeTo` is the grid frame and not
  the released button. *Red under:* reverting the line above.
- **Test count:** +1. Regenerate `docs/test-cases.md` and the README `[tests]` badge in the same commit
  (`testing-§5`).
- **Standards:** it does not change the `GRID_LAYOUT` payload (`architecture-§4`), so it adds no
  deviation.

### C-02 → F-002: character-safe truncation

`modules/Castbar.lua`, `truncateName`. With Option A:

```lua
local Core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local function truncateName(name, maxChars)
    if not name then return "" end
    if not maxChars or maxChars <= 0 then return name end
    if NS.Compat.IsSecret(name) then return name end
    local prefix, cut = Core.Utf8Prefix(name, maxChars)
    return cut and (prefix .. "…") or name
end
```

The library-absent arm must keep a byte-safe local copy, or simply return `name` uncut. Pick one and
pin it in the degraded suite. A copy in the stub is the one sanctioned place a second implementation
may live (`events-frames-taint-§8`'s degraded-build clause applies by analogy). Option B is the same
body with a file-local `utf8Prefix` that walks bytes, counts lead bytes (`b < 0x80 or b >= 0xC0`) and
cuts before the `(n+1)`th lead byte.

- Update the stale comment at `modules/Castbar.lua:332-333`.
- **Tests:** in `tests/test_castbar_frame.lua` (or `test_castbar_helpers.lua`), assert that
  `TruncateName("Éclair de givre", 3)` returns `"Écl…"` and that the result is valid UTF-8. Add a
  4-byte-free CJK case. *Red under:* restoring `string.sub(name, 1, maxChars)`.
- **Test count:** +1 or +2. Badge and inventory move in the same commit.
- **Localization:** no new user-facing string, and the row label stays truthful (`localization-§1`).

### C-03 → F-003 and C-04 → F-004: debug verb dispatch (`core/KickCD.lua`)

```lua
local function printDebugList(self)
    p(self, "debug subcommands")
    for _, row in ipairs(NS.Slash.CommandRows("/kcd debug", DEBUG_COMMANDS, "  ")) do p(self, row) end
end

function runDebug(self, rest)
    local sub, rem = NS.Slash.SplitVerb(rest)
    if sub == "diagnostics" then return self.DebugLog:RunDiagnostics() end
    if sub == "" then
        if self.DebugLog then self.DebugLog:Toggle() end   -- bare only (debug-logging-§5)
        return printDebugList(self)
    end
    local entry = NS.Slash.FindCommand(DEBUG_COMMANDS, sub)
    if entry then return entry[3](self, rem) end
    refuse(self, "Debug", "debug", nil, "unknown subcommand", "unknown debug subcommand '" .. sub .. "'", sub)
    printDebugList(self)                                    -- usage fallback, no toggle
end
```

- **C-04:** the `castbar` and `interrupt` handlers take `(self, rest)`, resolve
  `unit = (rest or ""):lower():match("^%s*(%a+)")`, accept only `target` or `focus` (default
  `target`), and pass it to `m:DebugDump(unit)` and `NS.Compat.DebugInterrupt(unit)`. Their row
  descriptions become `… [target|focus]`.
- **`diagnostics` stays first** (`debug-logging-§14`), and no alias is added.
- **Tests (`tests/test_slash.lua`):** extend "an unknown debug word refuses, then reprints the list" so
  it asserts the console's shown state did not change, and drop the
  `runVerb("debug") -- … toggle it back` workaround line. That edit removes a workaround for the defect;
  it does not weaken the assertion. *Red under:* reverting to `runDebug(self, "")`. Add one case:
  `debug castbar focus` reaches `DebugDump` with `"focus"`. Pin it on the argument, not on the output
  (`anti-patterns` #64).
- **Test count:** +1 (the C-04 case). Inventory and badge move in the same commit.
- **Docs:** `docs/slash-dispatch.md` and `docs/ARCHITECTURE.md`'s `/kcd debug` sub-verb lines name the
  optional unit. `docs/testing.md`'s coverage matrix gains the focus row if it lists those verbs.

### C-05 → F-005: the glow gate covers what the trigger reads (`modules/IconGrid_Visibility.lua`)

```lua
local casting = inst.isCasting and inst.isCasting() or false
if not gateMoved(inst, hostileCasting, interruptible, casting) then … end
inst.lastGateCasting, inst.lastGateInterruptible, inst.lastGateAny = hostileCasting, interruptible, casting
```

`gateMoved` gains `or inst.lastGateAny ~= casting`, and `newInstance` (`modules/IconGrid.lua:103-121`)
declares `lastGateAny = nil`.

- **Perf:** one extra `UnitCastingInfo`/`UnitChannelInfo` probe per cast event when the hostile probe
  was false. Re-run `tests/perf.lua` and confirm the existing scenarios do not move. No scenario covers
  `glowGate` today, so cite none.
- **Test:** add a case to `tests/test_icongrid_glowgate.lua`: a non-attackable target starts a cast with
  the trigger at `target_casting` → `UpdateGlow` runs. *Red under:* removing `casting` from the tuple.
- **Test count:** +1.
- **Diagnostics:** `modules/Diagnostics.lua:188-189` may add `any=%s`. That is optional and adds no new
  string key.

### C-06 → F-006: Cooldowns ignores `general` (`modules/Cooldowns.lua:708`)

`if section == "spells" or section == "general" then` becomes `if section == "spells" then`.

- **Risk:** check whether the master `enabled` write ever reaches Cooldowns **only** through `general`.
  Per `core/LifecycleSetup.lua:118-146`, standDown and standUp call `Suspend`/`Resume`, and `Resume`
  rebuilds when `IsLoggedIn()` (`modules/Cooldowns.lua:655-657`). Also update the comment at
  `:709-712`, which explains why `general` was included.
- **Characterization test first** (`tests/test_cooldowns_refresh.lua`):
  - toggling `enabled` false then true leaves `watched` populated;
  - a `general` announce with `scale` changed does not call `Rebuild` (spy on it).
  - *Red under:* re-adding `general` (second case); dropping Resume's Rebuild (first case).
- **Test count:** +2.

### C-07 → F-007: deferred

No change this cycle. If it is ever done, `BuildSpells` would seed only `(class, spec)` pairs where
`GetSpellList` answers nil, add the racial on the player's class, and keep the whole-table policy
documented for non-nil lists. Record the re-check trigger in the consolidated plan's deferred list.

### C-08 → F-008: tighten `.luacheckrc`

Remove `GameFontDisable` and `UIDropDownMenu_AddButton` from `read_globals`. Move the 20 names read
only under `tests/` into a `read_globals` key on the existing `files["tests/"]` stanza. Re-run
`ka0s-bounded luacheck .` and expect 0/0. If a shipped file turns out to need one of them, keep that
name top-level.

- `tests/test_lintconfig.lua:278-307` already pins the deprecated-name half (KICKCD-R-16). Generalize
  it with one more case: every top-level `read_globals` name has at least one bare reader among the
  shipped files (`core/`, `defaults/`, `locales/`, `modules/`, `settings/`). *Red under:* re-adding
  `UIDropDownMenu_AddButton`. Test count: +1.

### C-09 → F-009: measure first

Add an `onCooldownEvent` scenario to `tests/perf.lua` that calls `Cooldowns:OnCooldownEvent()` N times
inside a throttle window and reports bytes per call. Only if the bytes are non-trivial, change
`Util.Throttle` to skip the table when `select("#", ...) == 0`. Scenarios are not test cases, so the
badge does not move (`testing-§7`).

## Expected watch-list and record movement (for the next release regeneration, not now)

- No function is near CCN 15 because of these changes. The fresh run's max CCN of 15 is pre-existing.
- `docs/automated-tests/RESULTS.md` is already stale (81 commits). The next `/dev-copilot:bump-version`
  regeneration picks up today's count plus the cases added here.

## Standards conformance

| Change | Conformance |
|---|---|
| C-01 | Closed bus unchanged (`architecture-§4`). No vendored edit (`library-stack-§5`/`§7`). |
| C-02 | Option A is an additive upstream member: the compliant direction for a shared helper (`anti-patterns` #55 test passed: two consumers, same semantics, no flags). Option B adds no standards deviation. |
| C-03/C-04 | Bare `debug` toggles and the fallback is usage (`debug-logging-§5`). `diagnostics` stays first with no alias (`debug-logging-§14`, `anti-patterns` #90). |
| C-05 | No new bucket or bracket (`performance-§2` unchanged). |
| C-06 | The stand-down latch stays the only enable path (`slash-commands-§7`). |
| C-08 | Narrows suppression and adds none (`lint`). |
| All test-adding changes | Inventory and badge move in the same change (`testing-§5`). Every new negative assertion carries a `-- red under:` note (`testing-§12`). |
