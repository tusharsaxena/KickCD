# Target + Focus Dual Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give KickCD a second watched enemy unit — **focus** — with its own icon grid + cast bar alongside the existing target ones, sharing the player's cooldowns and spell list, independently enable-able, distinguished by on-widget labels.

**Architecture:** Convert the `IconGrid` and `Castbar` modules from frame-singletons into per-unit **instance managers** (instances keyed by `"target"`/`"focus"`). A new `core/Units.lua` (`NS.Units`) is the single source of unit identity + config resolution (including the Focus "link to Target styling" behavior). Config moves under `db.profile.units.<unit>.*` via an idempotent, shape-driven migration. Cooldowns and the spell list are untouched (already player-centric). Focus event registration is enable-gated per instance.

**Tech Stack:** Lua 5.1 (WoW client 12.0.7 Midnight), Ace3 (AceAddon/AceEvent/AceDB/AceConfig/AceGUI), LibSharedMedia, LibCustomGlow. Headless test harness: `lua tests/run.lua`. Lint: `luacheck .`.

## Global Constraints

Every task's requirements implicitly include these. Copied verbatim from the spec + CLAUDE.md hard rules:

- **Never auto-stage/commit/push.** Leave edits in the working tree; the user runs `git add`/`commit`/`push`. The "Commit" steps below mean *the user commits* — the worker stages nothing on its own. (Ask the user to run each commit, or leave it to the end.)
- **Never bump the version** (`KickCD.toc` `## Version`, `NS.VERSION`, README badge/history) as part of this work.
- **12.0 secret values:** never compare/format/`tostring`/do arithmetic on `C_Spell.GetSpellCooldown` timings or `UnitCastingInfo`/`UnitChannelInfo` `name`/`texture`/`notInterruptible`/`spellID`. Pass straight into Blizzard C methods. This feature threads `unit` through the existing secret-safe seams (`NS.State.IsHostileUnitCasting(unit)`, `NS.State.ApplyInterruptibleAlpha(frame, unit, 1)`, `NS.Compat.GetCastingInfo(unit)`); do not add new Lua-side inspection of secret values.
- **Closed message bus.** The five `Ka0s_KickCD_*` messages are the only inter-module channel. This feature adds NO new message — it only adds a `unit` field to the existing `Ka0s_KickCD_GRID_LAYOUT` payload. Update every emitter, every consumer, and `docs/message-bus.md` together.
- **`NS.Settings.Schema` is the single source of truth** for options. Adding an option = schema rows, never a parallel mutator.
- **Frame mixin, not `setmetatable`**, on Blizzard widgets.
- **CRLF line endings** on every file (`.gitattributes` enforces `* text=auto eol=crlf`). New files must be CRLF.
- **Keep static README badges in lockstep** with sources: `[Tests]` ↔ regenerated `docs/test-cases.md` (regenerate via `lua tests/run.lua --list` and update the count in the SAME change).
- **Run `lua tests/run.lua` (exit 0) and `luacheck .` (0 errors) before every commit.**
- **Flag standard deviations** (frame names, message payload, module structure, DB shape) for the user to record — see spec §10.

## Design invariants introduced by this feature

- **`db.profile.units.<unit>`** (`unit ∈ {"target","focus"}`) holds per-unit `{ enabled, link, label, anchors={icons,castbar}, icons={…}, castbar={…} }`. Top-level `db.profile.icons`/`castbar`/`anchors` are REMOVED from defaults and folded into `units.target` by migration.
- **`db.profile.{enabled,locked,scale,alpha,visibility,spells}`** stay addon-wide (shared). `enabled` is the master; `units.<unit>.enabled` is per-unit.
- **The "link" is total** for appearance: when `units.focus.link == true`, Focus renders using Target's `icons`/`castbar` tables. Only `enabled`, `anchors` (position — physics), and `label.text` (semantics) are always per-unit. `target.link` is always `false`.
- **`NS.Units` is the ONLY place** that resolves link/enabled/config-root. No module reaches `db.profile.units` directly for appearance; they call `NS.Units.Icons(unit)` / `.Castbar(unit)` / `.Anchor(unit, which)`.

---

# PHASE 0 — Foundations (fully headless-testable)

## Task 1: DB restructure + idempotent units migration

**Files:**
- Modify: `core/Database.lua` (`DEFAULT_PROFILE` L28-234; `CURRENT_DB_VERSION` L26; `migrations` L453-457; add `Database:FoldLegacyUnits`; call it from `Database:Init` L560-565 and `Database:OnProfileChanged` L523-524)
- Test: `tests/test_database.lua` (extend)

**Interfaces:**
- Produces: `NS.DEFAULT_PROFILE.units.target.icons`, `…target.castbar`, `…target.anchors`, `…focus.*` (same shape, `focus.enabled=false`, `focus.link=true`). `NS.DEFAULT_PROFILE` no longer has top-level `icons`/`castbar`/`anchors`.
- Produces: `NS.Database:FoldLegacyUnits(db)` — idempotent; if `db.profile.icons`/`castbar`/`anchors` exist top-level, moves them under `db.profile.units.target` and nils the originals. No-op otherwise.

- [ ] **Step 1: Write failing tests** — append to `tests/test_database.lua`:

```lua
test("DEFAULT_PROFILE nests appearance under units.target / units.focus", function()
    local d = NS.DEFAULT_PROFILE
    assertEqual(d.icons, nil, "top-level icons must be removed from defaults")
    assertEqual(d.castbar, nil, "top-level castbar must be removed from defaults")
    assertEqual(d.anchors, nil, "top-level anchors must be removed from defaults")
    assertTrue(type(d.units) == "table", "units sub-table must exist")
    assertTrue(type(d.units.target.icons) == "table", "units.target.icons must exist")
    assertEqual(d.units.target.icons.primarySize, 64)
    assertEqual(d.units.target.enabled, true)
    assertEqual(d.units.focus.enabled, false, "focus defaults off")
    assertEqual(d.units.focus.link, true, "focus defaults linked to target")
    assertTrue(type(d.units.target.anchors.icons) == "table")
end)

test("FoldLegacyUnits moves a legacy top-level config under units.target", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    -- Simulate a legacy v1 profile: customized top-level icons/castbar/anchors.
    p.icons   = { primarySize = 48, borderColor = { 1, 0, 0, 1 } }
    p.castbar = { width = 300 }
    p.anchors = { icons = { point = "TOP", relativePoint = "TOP", x = 5, y = -5 },
                  castbar = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 10 } }
    ns.db.profile.units = nil
    ns.Database:FoldLegacyUnits(ns.db)
    assertEqual(p.icons, nil, "top-level icons cleared after fold")
    assertEqual(p.castbar, nil, "top-level castbar cleared after fold")
    assertEqual(p.anchors, nil, "top-level anchors cleared after fold")
    assertEqual(p.units.target.icons.primarySize, 48, "user icons preserved under units.target")
    assertEqual(p.units.target.castbar.width, 300, "user castbar preserved")
    assertEqual(p.units.target.anchors.icons.x, 5, "user grid anchor preserved")
    assertEqual(p.units.target.anchors.castbar.y, 10, "user castbar anchor preserved")
end)

test("FoldLegacyUnits is idempotent and leaves a fresh v2 profile untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    local sizeBefore = p.units.target.icons.primarySize
    ns.Database:FoldLegacyUnits(ns.db)   -- no top-level keys → no-op
    ns.Database:FoldLegacyUnits(ns.db)   -- run twice
    assertEqual(p.icons, nil)
    assertEqual(p.units.target.icons.primarySize, sizeBefore, "fresh profile unchanged")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — the new assertions fail (defaults still top-level; `FoldLegacyUnits` undefined).

- [ ] **Step 3: Restructure `DEFAULT_PROFILE`**

In `core/Database.lua`, wrap the existing `icons = {…}` and `castbar = {…}` blocks and the `anchors = {…}` block into a new `units` table. Keep the existing leaf contents verbatim; only change nesting. Target keeps all current defaults; Focus is a structural copy with `enabled=false`, `link=true`, and offset anchors. Replace the top-level `icons`/`castbar`/`anchors` keys with:

```lua
    -- Per-unit widgets. Appearance (icons/castbar) is duplicated per unit;
    -- Focus defaults to link=true so it mirrors Target's appearance live
    -- (NS.Units resolves the link). enabled/anchors/label.text stay per-unit
    -- even while linked. See docs/saved-variables.md.
    units = {
        target = {
            enabled = true,
            link    = false,             -- target is never linked
            label   = { show = false, text = "Target" },
            anchors = {
                icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 },
                castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 },
            },
            icons   = <MOVE the existing icons = {…} table here verbatim>,
            castbar = <MOVE the existing castbar = {…} table here verbatim>,
        },
        focus = {
            enabled = false,
            link    = true,              -- mirror target appearance by default
            label   = { show = false, text = "Focus" },
            anchors = {
                -- offset from target so the two grids don't overlap on first enable
                icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
                castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
            },
            icons   = <DEEP-COPY of the icons defaults (same leaves as target)>,
            castbar = <DEEP-COPY of the castbar defaults>,
        },
    },
```

To avoid hand-duplicating the two large appearance tables, define them as locals above `DEFAULT_PROFILE` and reference `ICONS_DEFAULT` / `CASTBAR_DEFAULT` for `target`, and `NS`-independent deep copies for `focus` (use a file-local `deepcopy` or inline a second literal). Simplest: define `local ICONS_DEFAULT = {…}` and `local CASTBAR_DEFAULT = {…}` once, then build both units. A file-local copy helper (do NOT depend on `NS.Util` — Database loads before Util may be safe, but keep it self-contained):

```lua
local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}; for k, x in pairs(v) do o[k] = copy(x) end; return o
end
```
Then `icons = copy(ICONS_DEFAULT)` for each unit (target and focus each get their own copy so profiles never alias).

- [ ] **Step 4: Bump schema version + register the migration + add `FoldLegacyUnits`**

Change `local CURRENT_DB_VERSION = 1` → `= 2`.

Add the method (place near `MigrateProfile`):

```lua
--- Fold a legacy pre-units profile (top-level icons/castbar/anchors) into
--- units.target. Idempotent and SHAPE-DRIVEN, not version-gated: a v1 account
--- that stored schemaVersion as the default never persists it, so AceDB's
--- defaults merge backfills it to the new CURRENT value and masks the account
--- as already-current (the same KCD-20 backfill trap documented in
--- MigrateProfile). Keying on the presence of the old top-level tables detects
--- exactly the accounts that carry customized legacy data; a fresh v2 install
--- has no top-level icons/castbar/anchors and is a no-op.
function Database:FoldLegacyUnits(db)
    db = db or self.db
    if not (db and db.profile) then return end
    local p = db.profile
    if p.icons == nil and p.castbar == nil and p.anchors == nil then return end
    p.units = p.units or {}
    p.units.target = p.units.target or {}
    local t = p.units.target
    if p.icons   ~= nil then t.icons   = p.icons;   p.icons   = nil end
    if p.castbar ~= nil then t.castbar = p.castbar; p.castbar = nil end
    if p.anchors ~= nil then
        t.anchors = t.anchors or {}
        if p.anchors.icons   ~= nil then t.anchors.icons   = p.anchors.icons   end
        if p.anchors.castbar ~= nil then t.anchors.castbar = p.anchors.castbar end
        p.anchors = nil
    end
    if t.enabled == nil then t.enabled = true end
end
```

Register the version-based migrator too (for accounts that DID persist `schemaVersion = 1`):

```lua
local migrations = {
    [1] = function(db) NS.Database:FoldLegacyUnits(db); db.global.schemaVersion = 2 end,
}
```

Call `FoldLegacyUnits` unconditionally in `Init` (after `AceDB:New`, before `BuildSpells`) and in `OnProfileChanged` (before `BuildSpells`):

```lua
    self:FoldLegacyUnits(db)   -- in Init, right after self.db = db / NS.db = db
```
```lua
    self:FoldLegacyUnits(self.db)   -- in OnProfileChanged, before self:BuildSpells()
```

- [ ] **Step 5: Run tests to verify pass**

Run: `lua tests/run.lua`
Expected: PASS (all, incl. the pre-existing `test_database.lua` cases — note the existing `test("OnInitialize built a live db…")` asserts `NS.db.profile.icons.primarySize` at L20 and `test("DEFAULT_PROFILE carries the expected top-level shape")` asserts `d.icons`/`d.anchors` at L13-14; **update those two existing assertions** to the new paths `NS.db.profile.units.target.icons.primarySize` and `d.units.target.icons` / `d.units.target.anchors`).

- [ ] **Step 6: Lint**

Run: `luacheck .`
Expected: 0 errors.

- [ ] **Step 7: Commit** (user runs): `Feat: nest per-unit config under db.profile.units + shape-driven migration`

---

## Task 2: `core/Units.lua` — unit identity + link-resolving config

**Files:**
- Create: `core/Units.lua`
- Modify: `KickCD.toc` (add `core/Units.lua` after `core/Util.lua`)
- Test: `tests/test_units.lua` (create); register it in `tests/run.lua` if the runner lists tests explicitly (check how `run.lua` discovers test files — if it globs, no edit needed; if it has an explicit list, append `"test_units"`).

**Interfaces:**
- Produces `NS.Units` with:
  - `NS.Units.LIST` → `{ "target", "focus" }` (iteration order; target first)
  - `NS.Units.Config(unit)` → `db.profile.units[unit]` or `nil`
  - `NS.Units.IsLinked(unit)` → `false` for `"target"`; else `Config(unit).link == true`
  - `NS.Units.IsEnabled(unit)` → `db.profile.enabled` (master) AND `Config(unit).enabled ~= false`
  - `NS.Units.Icons(unit)` → link-resolved icons table (`Config("target").icons` when linked, else own)
  - `NS.Units.Castbar(unit)` → link-resolved castbar table
  - `NS.Units.Anchor(unit, which)` → `Config(unit).anchors[which]` (`which ∈ {"icons","castbar"}`)
  - `NS.Units.Label(unit)` → `Config(unit).label` (never link-resolved for `.text`)
  - `NS.Units.CopyStyling(fromUnit, toUnit)` → deep-copies `icons`+`castbar` from→to and sets `Config(toUnit).link = false`

- [ ] **Step 1: Write failing tests** — create `tests/test_units.lua`:

```lua
-- tests/test_units.lua — NS.Units link/enable/config resolution (core/Units.lua)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Units.LIST is target then focus", function()
    assertEqual(NS.Units.LIST[1], "target")
    assertEqual(NS.Units.LIST[2], "focus")
end)

test("target is never linked; focus honors its link flag", function()
    assertEqual(NS.Units.IsLinked("target"), false)
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.IsLinked("focus"), true)
    NS.db.profile.units.focus.link = false
    assertEqual(NS.Units.IsLinked("focus"), false)
end)

test("Icons(focus) resolves to target's icons when linked", function()
    NS.db.profile.units.target.icons.primarySize = 70
    NS.db.profile.units.focus.icons.primarySize  = 30
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.Icons("focus").primarySize, 70, "linked focus reads target icons")
    NS.db.profile.units.focus.link = false
    assertEqual(NS.Units.Icons("focus").primarySize, 30, "unlinked focus reads its own icons")
end)

test("IsEnabled combines master and per-unit enable", function()
    NS.db.profile.enabled = true
    NS.db.profile.units.target.enabled = true
    NS.db.profile.units.focus.enabled  = false
    assertEqual(NS.Units.IsEnabled("target"), true)
    assertEqual(NS.Units.IsEnabled("focus"), false)
    NS.db.profile.enabled = false
    assertEqual(NS.Units.IsEnabled("target"), false, "master off disables all units")
    NS.db.profile.enabled = true
end)

test("CopyStyling snapshots target appearance into focus and unlinks", function()
    NS.db.profile.units.target.icons.primarySize = 55
    NS.db.profile.units.focus.link = true
    NS.Units.CopyStyling("target", "focus")
    assertEqual(NS.db.profile.units.focus.link, false, "copy unlinks")
    assertEqual(NS.db.profile.units.focus.icons.primarySize, 55, "focus gets a copy of target size")
    -- mutating the copy must not affect the source (deep copy, not alias)
    NS.db.profile.units.focus.icons.primarySize = 999
    assertEqual(NS.db.profile.units.target.icons.primarySize, 55, "copy is deep, not aliased")
end)

test("Label.text is per-unit and not link-resolved", function()
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.Label("focus").text, "Focus")
    assertEqual(NS.Units.Label("target").text, "Target")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — `NS.Units` is nil.

- [ ] **Step 3: Implement `core/Units.lua`**

```lua
-- core/Units.lua
--
-- Single source of unit identity + per-unit config resolution for the
-- target/focus dual-tracking feature. The two widget modules (IconGrid,
-- Castbar) never reach db.profile.units directly for appearance — they call
-- NS.Units.Icons(unit) / .Castbar(unit) / .Anchor(unit, which) so the
-- "link to target styling" behavior lives in exactly one place.
--
-- Link semantics (spec §2b): when units.focus.link == true, Focus renders with
-- Target's icons/castbar tables (total mirror). enabled, anchors (position),
-- and label.text stay per-unit even while linked. Target is never linked.

local addonName, NS = ...
local Units = {}
NS.Units = Units

Units.LIST = { "target", "focus" }

local function profile() return NS.db and NS.db.profile end

function Units.Config(unit)
    local p = profile()
    if not (p and p.units) then return nil end
    return p.units[unit]
end

function Units.IsLinked(unit)
    if unit == "target" then return false end
    local c = Units.Config(unit)
    return c ~= nil and c.link == true
end

function Units.IsEnabled(unit)
    local p = profile()
    if not p or p.enabled == false then return false end
    local c = Units.Config(unit)
    return c ~= nil and c.enabled ~= false
end

-- Resolve the appearance source unit (target when this unit is linked).
local function sourceUnit(unit)
    return Units.IsLinked(unit) and "target" or unit
end

function Units.Icons(unit)
    local c = Units.Config(sourceUnit(unit))
    return (c and c.icons) or {}
end

function Units.Castbar(unit)
    local c = Units.Config(sourceUnit(unit))
    return (c and c.castbar) or {}
end

function Units.Anchor(unit, which)
    local c = Units.Config(unit)
    return c and c.anchors and c.anchors[which]
end

function Units.Label(unit)
    local c = Units.Config(unit)
    return (c and c.label) or { show = false, text = unit }
end

function Units.CopyStyling(fromUnit, toUnit)
    local src = Units.Config(fromUnit)
    local dst = Units.Config(toUnit)
    if not (src and dst) then return end
    dst.icons   = NS.Util.DeepCopy(src.icons)
    dst.castbar = NS.Util.DeepCopy(src.castbar)
    dst.link    = false
end
```

- [ ] **Step 4: Add to TOC**

In `KickCD.toc`, add `core/Units.lua` immediately after `core/Util.lua` (Units depends on `NS.Util.DeepCopy` at call time; Util loads at step 6 in the ordered load, Units after it).

- [ ] **Step 5: Run tests to verify pass**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 6: Lint + commit** (user): `luacheck .` (0 errors); commit `Feat: add NS.Units — per-unit config + link resolution`.

---

## Task 3: Generalize the unit-event dispatch helper

**Files:**
- Modify: `core/Util.lua` (`Util.RegisterTargetEvent` L197-205)
- Test: `tests/test_util.lua` (extend)

**Interfaces:**
- Produces: `Util.RegisterUnitCastEvent(module, unit, eventName, handlerName)` → private dispatch `Frame` registered via `RegisterUnitEvent(eventName, unit)`, forwarding `module[handlerName](module, event, unit, ...)`. Returns the frame for caller-owned teardown.
- Keep `Util.RegisterTargetEvent(module, eventName, handlerName)` as a thin back-compat wrapper `= RegisterUnitCastEvent(module, "target", eventName, handlerName)` (avoids touching call sites that aren't yet unit-aware; the module refactors below switch to the new name directly).

- [ ] **Step 1: Write failing test** — append to `tests/test_util.lua` (mirror the harness's existing style; confirm `wow_mock.lua` provides a `CreateFrame` stub whose returned frame records `RegisterUnitEvent` calls — if not, extend the mock frame to store `frame._unitEvents[eventName] = unit`):

```lua
test("RegisterUnitCastEvent registers the dispatch frame for the named unit", function()
    local NS = T.NS
    local calls = {}
    local module = { OnX = function(self, event, unit) calls[#calls+1] = { event, unit } end }
    local f = NS.Util.RegisterUnitCastEvent(module, "focus", "UNIT_SPELLCAST_START", "OnX")
    assertTrue(f ~= nil, "returns a frame for teardown")
    assertEqual(f._unitEvents["UNIT_SPELLCAST_START"], "focus", "registered for focus, not target")
    -- simulate the event firing for focus
    f:_fire("UNIT_SPELLCAST_START", "focus")
    assertEqual(calls[1][2], "focus", "handler receives the unit")
end)
```

(If `wow_mock.lua`'s frame stub lacks `_unitEvents`/`_fire`, add them: `RegisterUnitEvent(self, ev, unit) self._unitEvents[ev] = unit end` and a test-only `_fire(self, ev, ...) if self._onevent then self._onevent(self, ev, ...) end end`, with `SetScript("OnEvent", fn)` storing `self._onevent = fn`. Keep these additions minimal and clearly test-scoped.)

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — `RegisterUnitCastEvent` undefined.

- [ ] **Step 3: Implement**

Replace `core/Util.lua` L197-205 with:

```lua
--- Create a private dispatch frame that fires `module[handlerName](module, ...)`
--- only when `eventName` fires for `unit`. Caller stashes the returned frame and
--- runs UnregisterAllEvents in OnDisable (or on per-unit enable-toggle teardown).
--- @param module table     — AceEvent module (handler methods live on it)
--- @param unit string      — "target" / "focus"
--- @param eventName string — UNIT_SPELLCAST_START / _STOP / etc.
--- @param handlerName string — method on `module` to call on dispatch
--- @return Frame
function Util.RegisterUnitCastEvent(module, unit, eventName, handlerName)
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent(eventName, unit)
    f:SetScript("OnEvent", function(_, event, evUnit, ...)
        local fn = module[handlerName]
        if fn then fn(module, event, evUnit, ...) end
    end)
    return f
end

--- Back-compat: target-only registration (unchanged call sites).
function Util.RegisterTargetEvent(module, eventName, handlerName)
    return Util.RegisterUnitCastEvent(module, "target", eventName, handlerName)
end
```

- [ ] **Step 4: Run tests + lint**

Run: `lua tests/run.lua` (PASS); `luacheck .` (0 errors).

- [ ] **Step 5: Commit** (user): `Refactor: add Util.RegisterUnitCastEvent(unit) dispatch helper`.

---

# PHASE 1 — IconGrid → instance manager (behavior-preserving, target-only)

> **Verification note:** the headless harness cannot create frames or fire real cast events, so Phase 1–3 correctness rests on (a) the existing regression suite staying green, (b) `luacheck` clean, and (c) the in-game smoke tests listed at each task's end. The pure seams (`NS.Units`, layout math) are already covered by Phase 0 + `test_icongrid_layout.lua`. Do NOT claim these tasks "work" without running the smoke test.

## Task 4: Introduce the IconGrid instance model (still one instance: target)

**Files:**
- Modify: `modules/IconGrid.lua` (singleton state L62/67/72; `EnsureGrid` L493-520; `OnEnable` L526-591; accessors L831-839; `Layout` GRID_LAYOUT emits L370-379 & L421-428; visibility `shouldBeVisible`/`isTargetCasting`/`ApplyInterruptibilityMask`/`RefreshVisibility`/`RefreshAllGlows` L102-173, L677-792; config reads L206/296/340/471; anchor reads L454-455/504-505/640-642/654-655)
- Modify: `modules/IconGrid_Render.lua` (`triggerSatisfied` L406-419; `Icon:UpdateGlow` L433-461; per-method `NS.db.profile.icons` fallbacks; the `IconGrid._isTargetCasting` hook L410)

**Interfaces:**
- Produces: `IconGrid.instances` — table keyed by unit. `IconGrid:GetInstance(unit)` returns/creates the instance `{ unit, grid, pool = {active={},free={}}, ordered = {}, eventFrames = {}, cfg, caches… }`.
- Produces: `IconGrid:GetGridFrame(unit)` and `IconGrid:GetPrimaryIcon(unit)` (unit param; defaults to `"target"` when omitted for any stale caller).
- Produces: `Ka0s_KickCD_GRID_LAYOUT` payload now carries `unit = <inst.unit>`.

- [ ] **Step 1: Add the instance factory + table.** Replace file-locals `local pool` (L62), `local ordered` (L67), `local grid` (L72) with an instances table and a factory. Each was singleton; now they live on the instance:

```lua
-- Per-unit instances (target/focus). Each owns its own frame, icon pool,
-- ordered list, private cast-event dispatch frames, and cached config.
local instances = {}   -- [unit] = instance

local function newInstance(unit)
    return {
        unit        = unit,
        grid        = nil,
        pool        = { active = {}, free = {} },
        ordered     = {},
        eventFrames = {},
        cfg         = nil,          -- resolved icons appearance (NS.Units.Icons)
        -- migrated from self._*:
        truncationWarnedFor = {},
        lastVisible   = nil,
        lastGlowGate  = nil,
        lastCastLabel = nil,
    }
end

function IconGrid:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = newInstance(unit); instances[unit] = inst end
    return inst
end
```

- [ ] **Step 2: Parameterize the frame/anchor/config functions by instance.** Convert the file-local closures (`isEnabled`, `visibilityMode`, `RefreshVisibility`, `isTargetCasting`, `ApplyInterruptibilityMask`, `shouldBeVisible`, `RefreshAllGlows`) and the methods (`EnsureGrid`, `Layout`, `ApplyLock`, `ApplyGeneral`, `BuildActiveList`, `onDragStart`/`onDragStop`) to take an `inst` (or `unit`) argument and read `inst.grid` / `inst.pool` / `inst.ordered` / `inst.cfg` instead of the former upvalues. Concretely for the recon's site list:
  - `EnsureGrid(inst)`: `inst.grid = CreateFrame("Frame", "KickCDIconGrid" .. (inst.unit == "target" and "" or "Focus"), UIParent)` — Target keeps the exact legacy name `KickCDIconGrid`; Focus is `KickCDIconGridFocus`. Anchor from `NS.Units.Anchor(inst.unit, "icons")`.
  - Config reads (L206 `btn.cfg`, L296 `ApplyTextConfig`, L340 `Layout` local `cfg`, L471 `showTooltip`): read `inst.cfg = NS.Units.Icons(inst.unit)` (refresh `inst.cfg` at the top of `Layout`/`ApplyLock`/config handlers) and pass it down; stamp `btn.cfg = inst.cfg` and `btn.unit = inst.unit` in `AcquireIcon`/the Layout per-icon loop.
  - Anchor reads (L454-455 drag save, L504-505 ensure, L640-642 & L654-655 config/profile re-anchor): read via `NS.Units.Anchor(inst.unit,"icons")` and write via a new `NS.Units.SetAnchor(inst.unit,"icons", Util.SaveAnchor(inst.grid))` (add this setter to `core/Units.lua`: `function Units.SetAnchor(unit, which, a) local c = Units.Config(unit); if c then c.anchors = c.anchors or {}; c.anchors[which] = a end end`). `onDragStop` fires `Ka0s_KickCD_CONFIG_CHANGED { section = "general" }` as today.
  - Visibility (L148, L169) and glow gate (L737/740/743): replace the `"target"` literal with `inst.unit` in `NS.State.IsHostileUnitCasting(inst.unit)`, `NS.State.ApplyInterruptibleAlpha(inst.grid, inst.unit, 1)`, and the `UnitCastingInfo(inst.unit)` / `UnitChannelInfo(inst.unit)` reads (these are secret-safe — passed straight into C, per Global Constraints).
  - `isTargetCasting()` → `instanceCasting(inst)` reading `UnitExists(inst.unit)` / `UnitCastingInfo(inst.unit)` / `UnitChannelInfo(inst.unit)`. Store the resolver per instance: `inst.isCasting = function() return instanceCasting(inst) end` (replaces the module-level `IconGrid._isTargetCasting` hook the render file calls — see Step 4).

- [ ] **Step 3: Make `OnEnable` iterate enabled units.** Replace the single-grid bootstrap + the target-event loop with a loop over `NS.Units.LIST` gated by `NS.Units.IsEnabled(unit)`. Extract the per-unit setup into `IconGrid:EnableUnit(unit)` and teardown into `IconGrid:DisableUnit(unit)` (used later by enable-gating in Phase 3).

Register once at module level (NOT per unit):
  - Messages: `SPELL_STATE`, `CONFIG_CHANGED`, `PROFILE_CHANGED`, `COMBAT_STATE`.
  - Player-scoped events: `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `TRAIT_CONFIG_UPDATED`.
  - **The two global unit-change events** `PLAYER_TARGET_CHANGED` → `OnTargetChanged` and `PLAYER_FOCUS_CHANGED` → `OnFocusChanged`. These are GLOBAL events (no unit filter — they must NOT use `RegisterUnitCastEvent`/`RegisterUnitEvent`). Each handler refreshes only its unit's instance if live: `function IconGrid:OnFocusChanged() local inst = instances["focus"]; if inst and inst.enabled then self:RefreshVisibility(inst); self:RefreshAllGlows(inst) end end` (and the target equivalent). A disabled unit's handler is a cheap no-op.

Only the high-frequency `UNIT_SPELLCAST_*` family is per-instance and enable-gated:

```lua
function IconGrid:EnableUnit(unit)
    local inst = self:GetInstance(unit)
    inst.cfg = NS.Units.Icons(unit)
    self:EnsureGrid(inst)
    self:BuildActiveList(inst)
    self:Layout(inst)
    self:RefreshVisibility(inst)
    self:RefreshAllGlows(inst)         -- reflect any in-progress cast (reevaluate-on-enable)
    for _, ev in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    }) do
        inst.eventFrames[#inst.eventFrames+1] =
            NS.Util.RegisterUnitCastEvent(self, unit, ev, "OnUnitCastEvent")
    end
    inst.enabled = true
end

function IconGrid:DisableUnit(unit)
    local inst = instances[unit]
    if not inst then return end
    for _, f in ipairs(inst.eventFrames) do f:UnregisterAllEvents() end
    inst.eventFrames = {}
    if inst.grid then inst.grid:Hide() end
    inst.enabled = false
end
```

`OnUnitCastEvent(self, event, unit)` replaces `OnTargetCastEvent`: `local inst = instances[unit]; if inst then self:RefreshVisibility(inst); self:RefreshAllGlows(inst) end`. In Phase 1, `OnEnable` loops `for _, u in ipairs(NS.Units.LIST) do if NS.Units.IsEnabled(u) then self:EnableUnit(u) end end` — with Focus defaulting disabled, only `target` enables, so behavior is unchanged.

- [ ] **Step 4: Fix the render-file reverse dependency + per-instance glow.** In `IconGrid_Render.lua`:
  - `triggerSatisfied(trigger, inst)` gains the instance; L410 `IconGrid._isTargetCasting()` → `inst.isCasting()`; L414 `IsHostileUnitCasting("target")` → `IsHostileUnitCasting(inst.unit)`. Thread `inst` from the caller (`UpdateGlow`), which reads it from the icon: stamp `btn.instance = inst` (or at least `btn.unit`) in `AcquireIcon`.
  - `Icon:UpdateGlow` L454-457: `ApplyInterruptibleAlpha(self.glow, self.unit or "target", 1)`.
  - Every `self.cfg or NS.db.profile.icons` fallback: change the fallback to `self.cfg or NS.Units.Icons(self.unit or "target")` so a de-pooled icon still resolves the right unit's config.

- [ ] **Step 5: Add the `unit` field to both GRID_LAYOUT emits.** `IconGrid.lua` L373-378 and L422-427: add `unit = inst.unit,` to each payload table (the `Layout(inst)` method now has `inst`).

- [ ] **Step 6: Update the accessors.** L831-839:

```lua
function IconGrid:GetGridFrame(unit)
    local inst = instances[unit or "target"]
    return inst and inst.grid
end
function IconGrid:GetPrimaryIcon(unit)
    local inst = instances[unit or "target"]
    return inst and inst.ordered[1]
end
```

- [ ] **Step 7: Regression + lint.**

Run: `lua tests/run.lua`
Expected: PASS — `test_icongrid_layout.lua` (layout math untouched) and all others green. If `test_flow_traces.lua` or `test_lifecycle.lua` assert on `GetGridFrame()`/`GetPrimaryIcon()` arity or on `OnTargetCastEvent`, update those call sites/expectations to the new names (`GetGridFrame("target")`, `OnUnitCastEvent`).

Run: `luacheck .`
Expected: 0 errors (watch for unused upvalue warnings from the removed `grid`/`pool`/`ordered` locals — delete them fully).

- [ ] **Step 8: SMOKE TEST (required).** In-game: `/reload`. Confirm the target icon grid renders, positions, glows, respects visibility modes, drags while unlocked, and shows cooldowns EXACTLY as before this task (behavior-preserving refactor). Follow `docs/smoke-tests.md` target-grid scenarios.

- [ ] **Step 9: Commit** (user): `Refactor: IconGrid singleton -> per-unit instance manager (target-only)`.

---

# PHASE 2 — Castbar → instance manager (behavior-preserving, target-only)

## Task 5: Introduce the Castbar instance model (still one instance: target)

**Files:**
- Modify: `modules/Castbar.lua` (singleton state L66/74/85; `cfg()` L101-103; resolvers L112-126; `isVisible`/`ApplyVisibilityMask` L154-188; `ApplyAnchor` L323-351; `EnsureFrame` L389-402; `OnEnable` L1078-1130; `Reevaluate` L1063-1072; cast handlers L1177-1187, L1229-1235, `OnInterruptibilityChanged`, `OnCastStop`; `OnGridLayout` L1315-1339; `OnDisable` L1132-1142; `DebugDump` L1350-1361)

**Interfaces:**
- Produces: `Castbar.instances` keyed by unit; `Castbar:GetInstance(unit)` → `{ unit, frame, current, lastGridLayout = {gridFrame,primaryIcon}, eventFrames = {} }`.
- Consumes: `IconGrid:GetGridFrame(unit)` / `:GetPrimaryIcon(unit)` (Task 4), `NS.Units.Castbar(unit)` / `.Anchor(unit,"castbar")` (Task 2), `NS.Util.RegisterUnitCastEvent` (Task 3).
- Consumes: `Ka0s_KickCD_GRID_LAYOUT` payload `unit` field (Task 4) — cache only when `payload.unit == inst.unit`.

- [ ] **Step 1: Instance factory.** Replace `local frame` (L66), `local current` (L74), `local lastGridLayout` (L85) with `local instances = {}` + `newInstance(unit)` + `Castbar:GetInstance(unit)`, mirroring Task 4 Step 1. `current` and `lastGridLayout` become `inst.current` / `inst.lastGridLayout`.

- [ ] **Step 2: Parameterize config + resolvers + anchoring by instance.**
  - `cfg()` → `cfg(inst)` returning `NS.Units.Castbar(inst.unit)`. Update every caller (recon lists `ApplyAnchor`, `Reskin` L588, `RenderCast` L814, `ApplyState` L928, `Start` L993, `ShowPreview` L1037-1045, `OnCastDelayed` L1241, `OnConfigChanged` L1270, `OnGridLayout` L1325) to thread `inst`.
  - `resolveGridFrame(inst)` / `resolvePrimaryIcon(inst)` (L112-126): first check `inst.lastGridLayout`, then fall back to `NS:GetModule("IconGrid", true):GetGridFrame(inst.unit)` / `:GetPrimaryIcon(inst.unit)` — passing `inst.unit` so a focus castbar finds the focus grid.
  - `ApplyAnchor(inst)` (L323-351): anchor `inst.frame`; FREE anchor from `NS.Units.Anchor(inst.unit, "castbar")`; `onDragStop` saves via `NS.Units.SetAnchor(inst.unit, "castbar", …)`.
  - `EnsureFrame(inst)` (L392): `inst.frame = CreateFrame("Frame", inst.unit == "target" and "KickCDCastbar" or "KickCDCastbarFocus", UIParent)` — Target keeps legacy `KickCDCastbar`.
  - `isVisible(inst)` L154-167 and `ApplyVisibilityMask(inst.frame, inst.unit)` L176-188: replace `master() and cfg().enabled` with `NS.Units.IsEnabled(inst.unit) and cfg(inst).enabled ~= false`; replace both `"target"` literals (L163, L184) with `inst.unit`.

- [ ] **Step 3: Parameterize cast handlers + Reevaluate by unit.** Handlers receive `(self, event, unit, …)` from the dispatch frame; resolve `local inst = instances[unit]` and use it:
  - `Reevaluate(inst)` (L1063-1072): `UnitExists(inst.unit)`, `UnitIsDead(inst.unit)`, `NS.Compat.GetCastingInfo(inst.unit)`.
  - `OnCastStart(self, event, unit)` L1177: `local inst = instances[unit]; if inst and isVisible(inst) then local rec = NS.Compat.GetCastingInfo(inst.unit); if rec then self:Start(inst, rec) end end`. Same shape for `OnChannelStart` (GetChannelInfo), `OnCastDelayed` (L1235), `OnCastStop`, `OnInterruptibilityChanged` (mutates `inst.current.notInterruptible`, calls `ApplyVisibilityMask(inst.frame, inst.unit)`).
  - `Start`/`Stop`/`RenderCast`/`ApplyState` gain `inst` as first arg and operate on `inst.frame`/`inst.current`.
  - `DebugDump` (L1350-1361): iterate instances or take a unit; read `inst.unit` for the `Unit*` diagnostics.

- [ ] **Step 4: Filter `OnGridLayout` by unit.** L1315-1339:

```lua
function Castbar:OnGridLayout(_evt, payload)
    if type(payload) ~= "table" or not payload.unit then return end
    local inst = instances[payload.unit]
    if not (inst and inst.frame) then return end
    if payload.gridFrame   ~= nil then inst.lastGridLayout.gridFrame   = payload.gridFrame   end
    if payload.primaryIcon ~= nil then inst.lastGridLayout.primaryIcon = payload.primaryIcon end
    local c = cfg(inst)
    if c.anchorMode == "PRIMARY" then self:ApplyAnchor(inst) end
    if c.autoSize then self:Reskin(inst); if inst.current then self:RenderCast(inst, inst.current) end end
end
```

- [ ] **Step 5: `OnEnable`/`EnableUnit`/`DisableUnit`.** Mirror Task 4 Step 3. Register once at module level: messages (`CONFIG_CHANGED`, `PROFILE_CHANGED`, `GRID_LAYOUT`, `COMBAT_STATE`), `PLAYER_ENTERING_WORLD`, and the two GLOBAL change events `PLAYER_TARGET_CHANGED` → `OnTargetChanged` / `PLAYER_FOCUS_CHANGED` → `OnFocusChanged` (each `Reevaluate`s only its unit's instance if live — NOT via `RegisterUnitCastEvent`). Per-unit, enable-gated: `EnsureFrame(inst)`, `Reskin(inst)`, `ApplyLock(inst)`, the `UNIT_SPELLCAST_*` family (10 events, recon L1105-1116) via `NS.Util.RegisterUnitCastEvent(self, unit, ev, handler)`, and `Reevaluate(inst)` (reevaluate-on-enable). `OnDisable`/`DisableUnit` tears down `inst.eventFrames`, hides `inst.frame`, and calls `Stop(inst)`. In Phase 2 the enable loop still only lights up `target`.

- [ ] **Step 6: Regression + lint.** `lua tests/run.lua` (PASS — update any castbar-touching flow/lifecycle test expectations for the new arity); `luacheck .` (0 errors).

- [ ] **Step 7: SMOKE TEST (required).** `/reload`; confirm the target cast bar behaves EXACTLY as before: mirrors the target's casts/channels, interruptible vs uninterruptible appearance, PRIMARY-anchor follows the grid, autoSize, FREE drag. Follow `docs/smoke-tests.md` cast-bar scenarios.

- [ ] **Step 8: Commit** (user): `Refactor: Castbar singleton -> per-unit instance manager (target-only)`.

---

# PHASE 3 — Light up Focus + enable-gated registration

## Task 6: Enable the focus instance + per-instance enable-gating

**Files:**
- Modify: `modules/IconGrid.lua` (`OnConfigChanged` L619-648 — handle a `units` section; already loops units in `OnEnable`), `modules/Castbar.lua` (`OnConfigChanged` L1270)
- Modify: `settings/Panel.lua` (`_validSections` L149-152 — add `units`) [also needed by Task 8; do it here]

**Interfaces:**
- Consumes: `NS.Units.IsEnabled(unit)`, `IconGrid:EnableUnit/DisableUnit`, `Castbar:EnableUnit/DisableUnit`.
- Behavior: toggling `db.profile.units.<unit>.enabled` (or master `enabled`) fires `Ka0s_KickCD_CONFIG_CHANGED { section = "units" }`; each module reconciles every unit: enabled-but-not-live → `EnableUnit` + reevaluate; live-but-disabled → `DisableUnit`.

- [ ] **Step 1: Add `units` to `_validSections`** in `settings/Panel.lua` L149-152 (`units = true`).

- [ ] **Step 1b: Add the per-unit ENABLE schema rows now** (they drive `ReconcileUnits` and make `/kcd set units.<unit>.enabled` work — the label rows and the selector/link/copy UI come in Task 8). In `settings/General.lua`, after the master controls:

```lua
for _, u in ipairs(NS.Units.LIST) do
    add{ panel="general", section="units", group=L["Units"],
         path="units."..u..".enabled", unit=u, type="bool",
         label=(u=="target" and L["Enable Target grid"] or L["Enable Focus grid"]),
         default=(u=="target"), }
end
```

Add `L["Units"]`, `L["Enable Target grid"]`, `L["Enable Focus grid"]` to `locales/enUS.lua`. (`SchemaForPanel("general")` is called without a unit, so both rows always render.) Because these are `section="units"` rows, `Helpers.Set` fires `Ka0s_KickCD_CONFIG_CHANGED{section="units"}` on toggle — which the next steps consume.

- [ ] **Step 2: Reconcile-on-config-changed in IconGrid.** In `OnConfigChanged`, add a branch that (for `section == "units"` or `"general"`) walks `NS.Units.LIST` and reconciles live vs desired:

```lua
function IconGrid:ReconcileUnits()
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        local want = NS.Units.IsEnabled(u)
        if want and not (inst and inst.enabled) then
            self:EnableUnit(u)
        elseif not want and inst and inst.enabled then
            self:DisableUnit(u)
        end
    end
end
```

Call `self:ReconcileUnits()` from `OnConfigChanged` for the `general`/`units` sections and from `OnEnable` (replacing the inline loop). On enable, `EnableUnit` already runs `RefreshVisibility` + a first `Layout`; add a `RefreshAllGlows(inst)` so an in-progress cast is reflected (reevaluate-on-enable, spec §3).

- [ ] **Step 3: Reconcile-on-config-changed in Castbar.** Same `Castbar:ReconcileUnits()` (Enable/DisableUnit + `Reevaluate(inst)` on enable so a mid-cast focus is caught). Call from `OnConfigChanged` (`general`/`units`) and `OnEnable`.

- [ ] **Step 4: Config/profile re-resolve for linked appearance.** When `section == "icons"`/`"castbar"`/`"units"`, refresh each live instance's resolved config and re-render: for IconGrid `inst.cfg = NS.Units.Icons(inst.unit); self:Layout(inst); self:ApplyLock(inst)`; for Castbar `self:Reskin(inst); self:ApplyAnchor(inst)`. This makes a Target appearance edit propagate to a linked Focus automatically (since `NS.Units.Icons("focus")` returns Target's table while linked). Do the same in `OnProfileChanged`.

- [ ] **Step 5: Regression + lint.** `lua tests/run.lua` (PASS); `luacheck .` (0 errors). Add a headless test to `tests/test_units.lua` asserting the reconcile *intent* is data-only where possible — e.g. `IsEnabled` transitions — the frame side stays smoke-tested.

- [ ] **Step 6: SMOKE TEST (required).**
  1. `/kcd set units.focus.enabled true` (or via panel in Task 8). A second grid appears at the focus default offset; with `link=true` it looks identical to the target grid.
  2. Set focus, target a caster and a focus caster separately; with visibility `target_casting`, confirm the **focus** grid/bar gate on the **focus's** cast and the target grid/bar on the target's — independently.
  3. Enable focus **while the focus is mid-cast** → the focus cast bar shows the in-progress cast immediately.
  4. `/kcd set units.focus.enabled false` → focus grid+bar vanish; target grid+bar unaffected; no focus event handling remains.

- [ ] **Step 7: Commit** (user): `Feat: light up the focus instance with enable-gated registration`.

---

# PHASE 4 — Settings panel

## Task 7: Per-unit schema rows (generate icons + castbar rows per unit)

**Files:**
- Modify: `settings/Icons.lua` (wrap the ~30 `add{…}` rows in a `local function addUnitRows(unit)` and call for each unit; prefix `path`)
- Modify: `settings/Castbar.lua` (same for the ~42 rows)
- Modify: `settings/Panel.lua` (`Helpers.SchemaForPanel` L117-123 — optional `unit` filter; `RenderSchema` L972-1028 — render only `ctx.unit` rows)

**Interfaces:**
- Produces: schema rows whose `path` is `units.<unit>.icons.<field>` / `units.<unit>.castbar.<field>`, each tagged `unit = "target"|"focus"` and `section = "icons"|"castbar"` (unchanged section — both instances re-read on an `icons`/`castbar` change).
- Produces: `Helpers.SchemaForPanel(panelKey, unit)` — when `unit` is given, returns only rows matching both `panel` and `unit` (rows with no `unit` field, e.g. General, always match).

- [ ] **Step 1** (headless test): append to `tests/test_schema.lua` a check that every icons/castbar row now has a `unit` field and a `units.<unit>.` path, and that `ValidateSchema()` returns 0:

```lua
test("icons/castbar schema rows are unit-scoped and valid", function()
    local NS = T.NS
    local seen = { target = false, focus = false }
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == "icons" or def.panel == "castbar" then
            assertTrue(def.unit ~= nil, "row " .. tostring(def.path) .. " must carry a unit")
            assertTrue(def.path:match("^units%." .. def.unit .. "%."), "path must be unit-scoped: " .. def.path)
            seen[def.unit] = true
        end
    end
    assertTrue(seen.target and seen.focus, "both target and focus rows must exist")
    assertEqual(NS.Settings.Helpers.ValidateSchema(), 0, "schema must be valid")
end)
```

- [ ] **Step 2: Run to verify failure.** `lua tests/run.lua` → FAIL.

- [ ] **Step 3: Refactor `settings/Icons.lua` to emit per-unit rows.** Wrap the body's `add{…}` calls in `local function addUnitRows(unit) … end` where each row is built with `path = "units."..unit..".icons."..field`, `unit = unit`, and an unchanged `default`/`type`/`label`/`group`. Then:

```lua
for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end
```

Keep `section = "icons"` on every row (both grids react to an `icons` change; the specific unit's linked/own resolution happens in `NS.Units.Icons`). The `default` values stay identical across units.

- [ ] **Step 4: Refactor `settings/Castbar.lua`** identically (`units.<unit>.castbar.<field>`, `section = "castbar"`, `unit = unit`), including the nested `castbar.interruptible.*` / `castbar.uninterruptible.*` rows → `units.<unit>.castbar.interruptible.*`.

- [ ] **Step 5: Teach `SchemaForPanel` + `RenderSchema` the unit filter.** `Helpers.SchemaForPanel(panelKey, unit)` returns rows where `def.panel == panelKey and (not def.unit or def.unit == unit)`. `RenderSchema(ctx, panelKey, afterGroup)` calls `SchemaForPanel(panelKey, ctx.unit or "target")`. (`ctx.unit` is set by Task 8's selector; defaulting to `"target"` keeps rendering correct until then.)

- [ ] **Step 6: Run tests + lint.** `lua tests/run.lua` (PASS — the `test_schema.lua` count/shape and `test_settings_log.lua` may reference old paths; update to `units.target.icons.*`). `luacheck .` (0 errors).

- [ ] **Step 7: Commit** (user): `Feat: generate per-unit icons/castbar schema rows`.

## Task 8: Unit selector + link toggle + Copy button + General per-unit controls

**Files:**
- Modify: `settings/Icons.lua` + `settings/Castbar.lua` builders (add a unit selector + focus link/copy header before `RenderSchema`)
- Modify: `settings/General.lua` (per-unit enable + label rows/controls)
- Modify: `settings/Panel.lua` (`CreatePanel`/ctx — `ctx.unit`; a re-render helper that clears the scroll and re-runs `RenderSchema` on unit switch)

**Interfaces:**
- Consumes: `Helpers.RenderSchema` unit filter (Task 7), `NS.Units.CopyStyling`, `NS.Units.LIST`.
- Produces: `ctx.unit` (default `"target"`); a dropdown `[ Target / Focus ]` at the top of Icons + Castbar panels that sets `ctx.unit`, clears `ctx.scroll` children, resets `ctx.lastGroup=nil`, and re-renders. For Focus: a "Use same styling as Target" checkbox bound to `units.focus.link` and a "Copy styling from Target" button calling `NS.Units.CopyStyling("target","focus")` then firing `CONFIG_CHANGED{section="units"}` + re-render. While `link==true`, disable the appearance widgets (gray) — simplest correct approach: when `ctx.unit=="focus"` and linked, render the selector + link/copy header but SKIP the schema-body render (show a note "Linked to Target — uncheck to customize"), so there are no editable-but-ignored widgets.

- [ ] **Step 1: `ctx.unit` + re-render helper in `Panel.lua`.** Add `ctx.unit = "target"` in `CreatePanel`. Add `Helpers.RerenderUnitPanel(ctx, panelKey, afterGroup)` that releases the current AceGUI scroll children, resets `ctx.lastGroup`, and calls `RenderSchema` again. (Follow the existing `ensureScroll`/AceGUI release pattern; AceGUI containers expose `:ReleaseChildren()`.)

- [ ] **Step 2: Unit selector header.** In the Icons and Castbar builders, before the `RenderSchema` call in the `OnShow`, render a full-width `Dropdown` (AceGUI) with `NS.Units.LIST` values (`Target`/`Focus`, localized via `L`), `SetValue(ctx.unit)`, `OnValueChanged` → set `ctx.unit`, then `Helpers.RerenderUnitPanel(...)`. Keep the selector OUTSIDE the re-rendered scroll body so it persists across switches (render it into `ctx.body` above the scroll, or re-add it first each re-render).

- [ ] **Step 3: Focus link + copy header.** When `ctx.unit == "focus"`, before the body: a `CheckBox` bound to `NS.Units.Config("focus").link` (on toggle: write link, fire `CONFIG_CHANGED{section="units"}`, `RerenderUnitPanel`), and a `Button` "Copy styling from Target" → `NS.Units.CopyStyling("target","focus")`, fire `CONFIG_CHANGED{section="units"}`, `RerenderUnitPanel`. If linked, render a short note instead of the schema body (Step from Task 8 interface).

- [ ] **Step 4: General panel per-unit LABEL controls.** (The enable rows were added in Task 6 Step 1b.) In `settings/General.lua`, add the label rows (they auto-wire to `/kcd set`):

```lua
for _, u in ipairs(NS.Units.LIST) do
  local Title = u:sub(1,1):upper() .. u:sub(2)
  add{ panel="general", section="units", group=L["Units"],
       path="units."..u..".label.show", unit=u, type="bool",
       label=L["Show "..Title.." label"], default=false, }
  add{ panel="general", section="units", group=L["Units"],
       path="units."..u..".label.text", unit=u, type="string",
       label=L[Title.." label text"], default=Title, }
end
```

(These General rows carry a `unit` field but General has no unit selector — `SchemaForPanel("general")` is called WITHOUT a unit, so the `not def.unit or …` clause includes them all. The `type="string"` free-text label needs an editbox widget: confirm `Helpers.RenderField` supports a `string` type without `values` as an EditBox; if it only supports dropdown strings, add a minimal EditBox branch.) Add the new label locale strings to `locales/enUS.lua`.

- [ ] **Step 5: Reset coverage.** `RestoreDefaults`/`RestoreAllDefaults` iterate `SchemaForPanel(panelKey)` with no unit → they already hit BOTH units' rows (both carry `default`). Verify the per-panel "Defaults" button and `/kcd resetall` reset target AND focus. `ResetIconPosition` (L1114-1129) resets `db.profile.anchors.icons` — update it to reset `units.target.anchors.icons` (and consider a focus variant or reset the currently-selected unit); simplest: reset the selected `ctx.unit`'s icon anchor, or both. Pick resetting `units.<selected>.anchors.icons`.

- [ ] **Step 6: Run tests + lint.** `lua tests/run.lua` (PASS — update `test_settings_log.lua` / `test_list_mode.lua` if they assert specific `/kcd list` paths; the CLI now exposes `units.*` paths). `luacheck .` (0 errors).

- [ ] **Step 7: SMOKE TEST (required).** Open Settings → Icons: switch the unit selector Target↔Focus; edit Focus size while unlinked and confirm only the focus grid changes; toggle "Use same styling as Target" and confirm focus snaps back to target's look; "Copy styling from Target" then edit focus independently. General tab: toggle each unit's enable + label show + edit label text. `/kcd set units.focus.icons.primarySize 40` reflects live.

- [ ] **Step 8: Commit** (user): `Feat: settings unit selector, focus link/copy, per-unit enable+label controls`.

---

# PHASE 5 — Labels, docs, badges

## Task 9: On-widget identity labels (grid + cast bar)

**Files:**
- Modify: `modules/IconGrid.lua` (create/anchor a label FontString per instance; refresh on config/profile change)
- Modify: `modules/Castbar.lua` (same on the cast bar frame)

**Interfaces:**
- Consumes: `NS.Units.Label(unit)` → `{ show, text }`. Label `show`/style follow the link only in that the label widget's font matches the resolved appearance; `text` is always `NS.Units.Label(unit).text`.

- [ ] **Step 1: IconGrid label.** In `EnsureGrid(inst)`, create `inst.label = inst.grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")` anchored above the grid (`BOTTOM` of label to `TOP` of grid). Add `IconGrid:ApplyLabel(inst)`: read `local lbl = NS.Units.Label(inst.unit)`; `inst.label:SetText(lbl.text or "")`; `inst.label:SetShown(lbl.show == true)`. Call from `Layout(inst)` and the config/profile handlers.

- [ ] **Step 2: Castbar label.** Same pattern on `inst.frame` (anchor above the bar). `Castbar:ApplyLabel(inst)` from `Reskin(inst)` / config handlers.

- [ ] **Step 3: Lint + regression.** `lua tests/run.lua` (PASS); `luacheck .` (0 errors).

- [ ] **Step 4: SMOKE TEST (required).** Enable focus; toggle each unit's label show; confirm "Target"/"Focus" render above the grid AND cast bar, editable text updates live, and hide when toggled off.

- [ ] **Step 5: Commit** (user): `Feat: on-widget Target/Focus identity labels`.

## Task 10: Docs, message-bus, saved-variables, badges

**Files:**
- Modify: `docs/message-bus.md` (GRID_LAYOUT payload gains `unit`), `docs/saved-variables.md` (`db.profile.units.*` shape + migration), `docs/module-map.md` + `docs/ARCHITECTURE.md` (instance-manager structure; new `core/Units.lua`; new frame names `KickCDIconGridFocus`/`KickCDCastbarFocus`; the `Ka0s_KickCD_CONFIG_CHANGED` `units` section), `docs/conventions.md` (frame-name extension), `docs/icon-grid.md` + `docs/castbar.md` (per-unit notes), `docs/smoke-tests.md` (new focus scenarios), `docs/scope.md` (focus now in scope)
- Modify: `docs/test-cases.md` (regenerate) + `README.md` (`[Tests]` badge count)

- [ ] **Step 1: Regenerate the test inventory + badge.**

Run: `lua tests/run.lua --list > docs/test-cases.md`
Then update the README `Tests-X/Y_passing` badge to the new counts in the SAME edit. Verify: `diff <(lua tests/run.lua --list) docs/test-cases.md` (empty).

- [ ] **Step 2: Update each doc** listed above to match the shipped behavior (payload `unit` field; `units.*` DB shape + the shape-driven migration rationale; instance-manager module structure; enable-gated registration; the two new global frame names; the `units` config section). Record the spec §10 deviations as intentional (frame names, payload change, module structure, DB restructure) with a one-line justification each.

- [ ] **Step 3: Final full verification.**

Run: `lua tests/run.lua` (exit 0) and `luacheck .` (0 errors).
Run the full `docs/smoke-tests.md` pass including every new focus scenario and a **migration smoke** (load a pre-feature `KickCDDB` with customized icons and confirm it folds into `units.target` with no visual change).

- [ ] **Step 4: Commit** (user): `Docs: de-drift for target/focus dual tracking; regenerate test inventory + badge`.

---

## Task dependency order

1 → 2 → 3 (Phase 0, foundations) → 4 (Phase 1) → 5 (Phase 2) → 6 (Phase 3) → 7 → 8 (Phase 4) → 9 → 10 (Phase 5). Phases 1 and 2 are behavior-preserving refactors that must smoke-clean on target-only before Phase 3 lights up focus.
