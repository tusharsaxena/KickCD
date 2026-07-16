# Unit Text Label + "Text Label" Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two per-unit identity labels with a single, fully-configurable text label per unit — attachable to the cast bar or icon grid — surfaced on a new "Text Label" settings sub-page, and harden the schema renderer so one bad saved value can't blank a panel.

**Architecture:** A new `modules/UnitLabel.lua` per-unit instance manager owns one `FontString` per unit (a holder frame parented to `UIParent` for independent show/alpha, `SetPoint`-anchored to the chosen attach frame so it tracks that frame live). Label appearance lives under `db.profile.units.<unit>.label.style` (link-resolved for Focus via `NS.Units.LabelStyle`), while `show`/`text` stay per-unit. A new `settings/Label.lua` panel reuses the shared unit-selector header; `Helpers.RenderUnitPanel` gains an `alwaysPerUnit` row class so `show`/`text` stay editable even when Focus is linked. IconGrid and Castbar shed their label code.

**Tech Stack:** Lua 5.1 (WoW client 12.0.7 Midnight), Ace3 (AceAddon/AceEvent/AceDB/AceGUI), LibSharedMedia. Headless harness: `lua tests/run.lua`. Lint: `luacheck .`.

## Global Constraints

Every task's requirements implicitly include these (verbatim from CLAUDE.md / spec):

- **Never auto-stage/commit/push.** The "Commit" steps mean *the user commits*; the worker stages nothing. Leave edits in the working tree.
- **Never bump the version** (`KickCD.toc` `## Version`, `NS.VERSION`, README badge/history).
- **12.0 secret values:** never compare/format/`tostring`/arithmetic on `C_Spell.GetSpellCooldown` timings or `UnitCastingInfo`/`UnitChannelInfo` `name`/`texture`/`notInterruptible`/`spellID`. Label text is a plain addon string (`NS.Units.Label(unit).text`) — never a secret — so it is safe to `SetText`/format. Do not add new Lua-side inspection of secret values.
- **Closed message bus:** the five `Ka0s_KickCD_*` messages are the only inter-module channel. This feature adds NO new message; `UnitLabel` only *subscribes* to existing ones.
- **`NS.Settings.Schema` is the single source of truth** for options. New option = schema row(s), never a parallel mutator.
- **Frame mixin, not `setmetatable`,** on Blizzard widgets.
- **CRLF line endings** on every file (`.gitattributes` enforces `* text=auto eol=crlf`). New files must be CRLF.
- **Keep static README badges in lockstep:** `[Tests]` ↔ regenerated `docs/test-cases.md` (regenerate via `lua tests/run.lua --list`, update the count in the SAME change).
- **Run `lua tests/run.lua` (exit 0) and `luacheck .` (0 errors) before every commit.**
- **Flag standard deviations** (new module + frame names, `label.style` DB sub-shape + migration, `alwaysPerUnit` flag, new `label` panel) for the user to record.

## Design invariants introduced by this feature

- **`units.<unit>.label = { show, text, style = {...} }`.** `show`/`text` are ALWAYS per-unit; `style` is link-resolved for a linked Focus. `label.style` ships **identical** across Target and Focus (single-sourced `copy(LABELSTYLE_DEFAULT)`); only `text` differs.
- **`NS.Units` is the ONLY resolver.** `NS.Units.Label(unit)` → own `{show,text}`; `NS.Units.LabelStyle(unit)` → link-resolved `style`. `UnitLabel` reads only through these.
- **One label per unit.** IconGrid/Castbar no longer create or apply any label.

---

## File Structure

- Modify `core/Database.lua` — `LABELSTYLE_DEFAULT`, `label.style` in defaults, `Database:BackfillLabelStyle`.
- Modify `core/Units.lua` — `Units.LabelStyle`, `CopyStyling` copies `label.style`.
- Modify `settings/Panel.lua` — extract `Helpers.RenderRows` + pcall hardening; `Helpers.PartitionUnitRows`; `alwaysPerUnit` in `RenderUnitPanel`; `_validPanels.label`; `order` gains `label`.
- Create `modules/UnitLabel.lua` — the single-label render module.
- Modify `modules/IconGrid.lua` / `modules/Castbar.lua` — remove label code; Castbar adds `GetCastbarFrame`.
- Create `settings/Label.lua` — the "Text Label" panel.
- Modify `settings/General.lua` — remove the label show/text rows (keep enable rows).
- Modify `KickCD.toc` — add `modules\UnitLabel.lua` and `settings\Label.lua`.
- Modify `locales/enUS.lua` — new strings.
- Modify tests: `test_database.lua`, `test_units.lua`, `test_schema.lua`; add `test_unitlabel` seam test.
- Modify docs: `saved-variables.md`, `module-map.md`, `conventions.md`, `smoke-tests.md`, `ARCHITECTURE.md`; regenerate `test-cases.md` + README badge.

---

# Task 1: DB — `label.style` default (single-sourced) + `BackfillLabelStyle` migration

**Files:**
- Modify: `core/Database.lua` (add `LABELSTYLE_DEFAULT` near `ICONS_DEFAULT` L41 / `CASTBAR_DEFAULT` L122; extend both units' `label` L241 & L252; add `Database:BackfillLabelStyle` near `FoldLegacyUnits` L494; call it in `Init` after L627 `self:FoldLegacyUnits(db)` and in `OnProfileChanged` after L587)
- Test: `tests/test_database.lua` (extend)

**Interfaces:**
- Produces: `NS.DEFAULT_PROFILE.units.<unit>.label.style` (identical across units); `NS.Database:BackfillLabelStyle(db)` — idempotent, shape-driven (keyed on `label.style == nil`), preserves existing `show`/`text`.

- [ ] **Step 1: Write failing tests** — append to `tests/test_database.lua`:

```lua
test("DEFAULT_PROFILE ships an identical label.style for target and focus", function()
    local d = NS.DEFAULT_PROFILE
    assertTrue(type(d.units.target.label.style) == "table", "target label.style must exist")
    assertTrue(type(d.units.focus.label.style)  == "table", "focus label.style must exist")
    assertEqual(d.units.target.label.style.attach,   "castbar")
    assertEqual(d.units.target.label.style.relPoint, "TOP")
    -- style ships identical (only text differs)
    for k, v in pairs(d.units.target.label.style) do
        assertEqual(d.units.focus.label.style[k], v, "focus style differs at key " .. tostring(k))
    end
    assertEqual(d.units.target.label.text, "Target")
    assertEqual(d.units.focus.label.text,  "Focus")
end)

test("BackfillLabelStyle adds a missing label.style and preserves show/text", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label = { show = true, text = "TANK" }   -- legacy: no style
    p.units.focus.label  = { show = false, text = "Focus" }
    p.units.focus.label.style = nil
    ns.Database:BackfillLabelStyle(ns.db)
    assertTrue(type(p.units.target.label.style) == "table", "style backfilled")
    assertEqual(p.units.target.label.show, true,  "show preserved")
    assertEqual(p.units.target.label.text, "TANK", "text preserved")
    assertEqual(p.units.target.label.style.attach, "castbar", "style is the default")
end)

test("BackfillLabelStyle is idempotent and leaves an existing style untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label.style.size = 22   -- user customised
    ns.Database:BackfillLabelStyle(ns.db)
    ns.Database:BackfillLabelStyle(ns.db)
    assertEqual(p.units.target.label.style.size, 22, "existing style not overwritten")
end)
```

- [ ] **Step 2: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (`label.style` nil; `BackfillLabelStyle` undefined).

- [ ] **Step 3: Add `LABELSTYLE_DEFAULT`** — in `core/Database.lua`, immediately after the `CASTBAR_DEFAULT = {...}` block (ends ~L134), add:

```lua
-- Single-sourced so Target and Focus ship an IDENTICAL label appearance
-- (copy()'d into each unit below). label.show/label.text stay per-unit;
-- only `style` is duplicated + link-resolved (NS.Units.LabelStyle).
local LABELSTYLE_DEFAULT = {
        attach   = "castbar",     -- "castbar" | "icons"
        point    = "BOTTOM",      -- the label's own anchor point
        relPoint = "TOP",         -- point on the attach frame
        offsetX  = 0,
        offsetY  = 0,
        justifyH = "CENTER",      -- LEFT | CENTER | RIGHT
        justifyV = "MIDDLE",      -- TOP  | MIDDLE | BOTTOM
        rotation = 0,             -- degrees
        font     = "Friz Quadrata TT",
        size     = 14,
        flags    = "OUTLINE",     -- NONE | OUTLINE | THICKOUTLINE | MONOCHROME
}
```

- [ ] **Step 4: Give each unit a `label.style`** — change the two `label` lines:
  - L241 `label = { show = false, text = "Target" },` → `label = { show = false, text = "Target", style = copy(LABELSTYLE_DEFAULT) },`
  - L252 `label = { show = false, text = "Focus" },` → `label = { show = false, text = "Focus", style = copy(LABELSTYLE_DEFAULT) },`

- [ ] **Step 5: Add `BackfillLabelStyle`** — after `Database:FoldLegacyUnits` (ends ~L511), add:

```lua
--- Backfill units.<unit>.label.style on a profile saved before the single
--- text-label feature. Idempotent and SHAPE-DRIVEN (keyed on style == nil),
--- not version-gated — same rationale as FoldLegacyUnits (AceDB defaults
--- merge would mask the account as already-current). show/text are left
--- exactly as saved; only the missing style sub-table is filled from
--- LABELSTYLE_DEFAULT. A fresh install already has style and is a no-op.
function Database:BackfillLabelStyle(db)
    db = db or self.db
    if not (db and db.profile and db.profile.units) then return end
    for _, unit in ipairs({ "target", "focus" }) do
        local u = db.profile.units[unit]
        if u then
            u.label = u.label or {}
            if u.label.style == nil then
                u.label.style = copy(LABELSTYLE_DEFAULT)
            end
        end
    end
end
```

- [ ] **Step 6: Call it after every `FoldLegacyUnits`** — in `Database:Init`, immediately after `self:FoldLegacyUnits(db)` (L627) add `self:BackfillLabelStyle(db)`. In `Database:OnProfileChanged`, immediately after `self:FoldLegacyUnits(self.db)` (L587) add `self:BackfillLabelStyle(self.db)`.

- [ ] **Step 7: Run tests to verify pass** — Run: `lua tests/run.lua` — Expected: PASS (incl. the extended `test_database.lua`).

- [ ] **Step 8: Lint** — Run: `luacheck .` — Expected: 0 errors.

- [ ] **Step 9: Commit** (user): `Feat: single-sourced label.style default + shape-driven backfill`

---

# Task 2: `NS.Units.LabelStyle` resolver + `CopyStyling` copies `label.style`

**Files:**
- Modify: `core/Units.lua` (add `Units.LabelStyle` after `Units.Label` L71; extend `Units.CopyStyling` L76-82)
- Test: `tests/test_units.lua` (extend)

**Interfaces:**
- Consumes: `NS.Util.DeepCopy`, the file-local `sourceUnit(unit)` (L41-43).
- Produces: `NS.Units.LabelStyle(unit)` → link-resolved `label.style` table (Target's when `unit` is a linked Focus, else own); `CopyStyling(from,to)` now also deep-copies `label.style`, leaving `show`/`text` per-unit.

- [ ] **Step 1: Write failing tests** — append to `tests/test_units.lua`:

```lua
test("LabelStyle resolves to target's style when focus is linked", function()
    local NS = T.NS
    NS.db.profile.units.target.label.style.size = 20
    NS.db.profile.units.focus.label.style.size  = 8
    NS.db.profile.units.focus.link = true
    assertEqual(NS.Units.LabelStyle("focus").size, 20, "linked focus reads target style")
    NS.db.profile.units.focus.link = false
    assertEqual(NS.Units.LabelStyle("focus").size, 8, "unlinked focus reads its own style")
end)

test("CopyStyling snapshots target label.style but keeps focus text/show", function()
    local NS = T.NS
    NS.db.profile.units.target.label.style.size = 17
    NS.db.profile.units.focus.label.show = true
    NS.db.profile.units.focus.label.text = "MINE"
    NS.db.profile.units.focus.link = true
    NS.Units.CopyStyling("target", "focus")
    assertEqual(NS.db.profile.units.focus.link, false, "copy unlinks")
    assertEqual(NS.db.profile.units.focus.label.style.size, 17, "focus got a copy of target style")
    assertEqual(NS.db.profile.units.focus.label.text, "MINE", "per-unit text preserved")
    assertEqual(NS.db.profile.units.focus.label.show, true,  "per-unit show preserved")
    NS.db.profile.units.focus.label.style.size = 99
    assertEqual(NS.db.profile.units.target.label.style.size, 17, "copy is deep, not aliased")
end)
```

- [ ] **Step 2: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (`LabelStyle` nil; CopyStyling doesn't touch label).

- [ ] **Step 3: Add `Units.LabelStyle`** — in `core/Units.lua`, after `Units.Label` (L71-74), add:

```lua
--- Link-resolved label APPEARANCE (units.<unit>.label.style). Follows the
--- Focus link exactly like Icons/Castbar: a linked focus reads target's
--- style. label.show/label.text are NOT resolved here — they stay per-unit
--- (see Units.Label).
function Units.LabelStyle(unit)
    local c = Units.Config(sourceUnit(unit))
    return (c and c.label and c.label.style) or {}
end
```

- [ ] **Step 4: Extend `CopyStyling`** — in `Units.CopyStyling` (L76-82), after the `dst.castbar = NS.Util.DeepCopy(src.castbar)` line and before `dst.link = false`, add:

```lua
    dst.label = dst.label or {}
    dst.label.style = NS.Util.DeepCopy(src.label and src.label.style)
```

- [ ] **Step 5: Run tests to verify pass** — Run: `lua tests/run.lua` — Expected: PASS.

- [ ] **Step 6: Lint + commit** (user) — `luacheck .` (0 errors); commit `Feat: NS.Units.LabelStyle + CopyStyling label.style`.

---

# Task 3: Harden the schema renderer (extract `RenderRows` + pcall per row)

**Files:**
- Modify: `settings/Panel.lua` (`Helpers.RenderSchema` L1029-1085 — extract loop into `Helpers.RenderRows`; wrap `RenderField` in pcall)
- Test: `tests/test_schema.lua` (extend)

**Interfaces:**
- Produces: `Helpers.RenderRows(ctx, rows, afterGroup)` — renders an explicit row list (the old `RenderSchema` body). `Helpers.RenderSchema(ctx, panelKey, afterGroup)` now delegates to it. One row whose `RenderField` throws logs a schema error and is skipped; the rest render.

- [ ] **Step 1: Write failing test** — append to `tests/test_schema.lua`:

```lua
test("RenderRows survives a row whose render throws (no blank panel)", function()
    local NS = T.NS
    local H  = NS.Settings.Helpers
    local ctx = H.CreatePanel("KickCDHardenTest", "Harden", { panelKey = "general" })
    local good1 = { panel = "general", section = "general", path = "scale",
                    type = "number", label = "A", default = 1 }
    local boom  = { panel = "general", section = "general", path = "boom",
                    type = "string", label = "B", values = function() error("kaboom") end }
    local good2 = { panel = "general", section = "general", path = "alpha",
                    type = "number", label = "C", default = 1 }
    local ok = pcall(function() H.RenderRows(ctx, { good1, boom, good2 }, nil) end)
    assertTrue(ok, "RenderRows must not propagate a single row's render error")
end)
```

(The AceGUI mock — `tests/wow_mock.lua` L242 — returns no-op frames from `AceGUI:Create`, so `RenderRows` runs headless. A `values` function that `error()`s makes `makeDropdown` throw, exercising the pcall.)

- [ ] **Step 2: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (`RenderRows` undefined; error propagates).

- [ ] **Step 3: Extract `RenderRows` + add pcall** — replace `Helpers.RenderSchema` (L1029-1085) with:

```lua
-- Render an explicit list of schema rows into ctx's scroll. Two-column
-- Flow layout, group headings, `solo` rows, and afterGroup hooks behave
-- exactly as before — this is the former RenderSchema body, lifted so
-- RenderUnitPanel can render a filtered subset (alwaysPerUnit rows).
--
-- Each row's RenderField is wrapped in pcall: a single bad saved value
-- (bad enum, wrong-typed value) then degrades to one missing widget plus
-- a logged schema error, instead of aborting the whole panel body. This
-- is defensive coverage for legacy / hand-edited SavedVariables.
function Helpers.RenderRows(ctx, rows, afterGroup)
    local scroll = ensureScroll(ctx)
    local pendingRow, pendingCount = nil, 0

    local function flushRow()
        if pendingRow then
            scroll:AddChild(pendingRow)
            addSpacer(scroll, ROW_VSPACER)
            pendingRow, pendingCount = nil, 0
        end
    end

    local function startRow()
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        return row
    end

    for i, def in ipairs(rows) do
        if def.group and def.group ~= ctx.lastGroup then
            flushRow()
            Helpers.Section(ctx, def.group)
            ctx.lastGroup = def.group
        end

        if def.solo and pendingCount > 0 then
            flushRow()
        end

        if not pendingRow then pendingRow = startRow() end
        local ok, err = pcall(Helpers.RenderField, ctx, def, pendingRow, 0.5)
        if not ok then
            _printSchemaError("row (" .. tostring(def.path) .. ")",
                "render failed, widget skipped: " .. tostring(err))
        end
        pendingCount = pendingCount + 1
        if def.solo or pendingCount >= 2 then flushRow() end

        local nextDef = rows[i + 1]
        if afterGroup and def.group
           and (not nextDef or nextDef.group ~= def.group)
           and afterGroup[def.group] then
            flushRow()
            afterGroup[def.group](ctx)
            afterGroup[def.group] = nil
        end
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
end

function Helpers.RenderSchema(ctx, panelKey, afterGroup)
    Helpers.RenderRows(ctx, Helpers.SchemaForPanel(panelKey, ctx.unit), afterGroup)
end
```

(`_printSchemaError` is a file-local defined at L164 — `RenderRows` is below it, so it is in scope.)

- [ ] **Step 4: Run tests to verify pass** — Run: `lua tests/run.lua` — Expected: PASS.

- [ ] **Step 5: Lint + commit** (user) — `luacheck .` (0 errors); commit `Fix: schema renderer survives a bad row instead of blanking the panel`.

---

# Task 4: `alwaysPerUnit` rows survive the Focus link

**Files:**
- Modify: `settings/Panel.lua` (add `Helpers.PartitionUnitRows`; `RenderUnitPanel` linked branch L1187-1199)
- Test: `tests/test_schema.lua` (extend)

**Interfaces:**
- Produces: `Helpers.PartitionUnitRows(rows)` → `perUnit, styled` (rows split by `def.alwaysPerUnit`). `RenderUnitPanel`, when Focus is linked, renders `perUnit` rows then the "Linked to Target" note (instead of skipping the whole body).

- [ ] **Step 1: Write failing test** — append to `tests/test_schema.lua`:

```lua
test("PartitionUnitRows splits alwaysPerUnit rows from styled rows", function()
    local H = T.NS.Settings.Helpers
    local rows = {
        { path = "a", alwaysPerUnit = true },
        { path = "b" },
        { path = "c", alwaysPerUnit = true },
    }
    local perUnit, styled = H.PartitionUnitRows(rows)
    assertEqual(#perUnit, 2, "two alwaysPerUnit rows")
    assertEqual(#styled, 1, "one styled row")
    assertEqual(perUnit[1].path, "a")
    assertEqual(styled[1].path, "b")
end)
```

- [ ] **Step 2: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (`PartitionUnitRows` undefined).

- [ ] **Step 3: Add `PartitionUnitRows`** — in `settings/Panel.lua`, immediately before `Helpers.RenderUnitPanel` (L1130), add:

```lua
-- Split a unit panel's rows into those that stay editable even when Focus
-- is linked (alwaysPerUnit — e.g. label show/text, which are per-unit by
-- design) and the appearance rows the link hides. Pure; unit-tested.
function Helpers.PartitionUnitRows(rows)
    local perUnit, styled = {}, {}
    for _, def in ipairs(rows) do
        if def.alwaysPerUnit then
            perUnit[#perUnit + 1] = def
        else
            styled[#styled + 1] = def
        end
    end
    return perUnit, styled
end
```

- [ ] **Step 4: Render `perUnit` rows under a link** — in `RenderUnitPanel`, replace the `if linked then ... end` block (L1187-1199) with:

```lua
        if linked then
            -- Editable-but-ignored appearance widgets are worse than none:
            -- a linked Focus renders with Target's tables, so any styled row
            -- here would write to a table nothing reads. But alwaysPerUnit
            -- rows (label show/text) ARE per-unit even while linked, so they
            -- stay editable; only the appearance rows are replaced by a note.
            local perUnit = Helpers.PartitionUnitRows(
                Helpers.SchemaForPanel(panelKey, ctx.unit))
            Helpers.RenderRows(ctx, perUnit, afterGroup)

            local note = AceGUI:Create("Label")
            note:SetFullWidth(true)
            note:SetText(L["Linked to Target — uncheck to customize."])
            scroll:AddChild(note)
            if scroll.DoLayout then scroll:DoLayout() end
            return
        end
```

(Icons/Castbar have no `alwaysPerUnit` rows, so `perUnit` is empty and their linked behavior is unchanged: note only.)

- [ ] **Step 5: Run tests + lint** — Run: `lua tests/run.lua` (PASS); `luacheck .` (0 errors).

- [ ] **Step 6: Commit** (user): `Feat: alwaysPerUnit schema rows stay editable under a Focus link`.

---

# Task 5: `modules/UnitLabel.lua` — the single label; remove IconGrid/Castbar labels

**Files:**
- Create: `modules/UnitLabel.lua`
- Modify: `KickCD.toc` (add `modules\UnitLabel.lua` after `modules\Castbar.lua` L52)
- Modify: `modules/Castbar.lua` (add `Castbar:GetCastbarFrame(unit)`; remove label code)
- Modify: `modules/IconGrid.lua` (remove label code)
- Test: `tests/test_unitlabel.lua` (create) + register nothing (runner globs `test_*.lua`)

**Interfaces:**
- Consumes: `NS.Units.Label(unit)`, `NS.Units.LabelStyle(unit)`, `NS.Units.IsEnabled(unit)`, `IconGrid:GetGridFrame(unit)`, `Castbar:GetCastbarFrame(unit)`, existing messages `Ka0s_KickCD_CONFIG_CHANGED` / `_PROFILE_CHANGED` / `_GRID_LAYOUT`.
- Produces: module `UnitLabel` with `GetInstance(unit)`, `Apply(inst)`, `ApplyAll()`; frames `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`. `Castbar:GetCastbarFrame(unit)` → the unit's cast bar frame or nil (read-only, does NOT create an instance).

- [ ] **Step 1: Add `Castbar:GetCastbarFrame`** — in `modules/Castbar.lua`, immediately after `Castbar:GetInstance` (ends ~L110), add (mirrors `IconGrid:GetGridFrame` — a read-only accessor that does NOT create an instance):

```lua
--- Read-only accessor for a unit's cast bar frame (or nil if that unit has
--- no live instance). Unlike GetInstance it never creates one — UnitLabel
--- anchors to whatever exists and hides otherwise.
function Castbar:GetCastbarFrame(unit)
    local inst = instances[unit or "target"]
    return inst and inst.frame
end
```

- [ ] **Step 2: Write the seam test** — create `tests/test_unitlabel.lua`:

```lua
-- tests/test_unitlabel.lua — UnitLabel module load + resolver wiring.
-- The FontString rendering itself is smoke-tested in-game (the headless
-- mock's frames are no-ops); here we assert the module loaded, registered,
-- and resolves its label data through NS.Units without error.
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("UnitLabel module is registered", function()
    assertTrue(NS:GetModule("UnitLabel", true) ~= nil, "UnitLabel module must exist")
end)

test("UnitLabel.ApplyAll runs without error for both units", function()
    local m = NS:GetModule("UnitLabel", true)
    NS.db.profile.units.focus.enabled = true
    local ok, err = pcall(function() m:ApplyAll() end)
    assertTrue(ok, "ApplyAll must not error: " .. tostring(err))
    NS.db.profile.units.focus.enabled = false
end)

test("Castbar:GetCastbarFrame does not create an instance for an unknown unit", function()
    local cb = NS:GetModule("Castbar", true)
    assertEqual(cb:GetCastbarFrame("nonexistent"), nil)
end)
```

- [ ] **Step 3: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (`UnitLabel` module nil).

- [ ] **Step 4: Create `modules/UnitLabel.lua`**:

```lua
-- modules/UnitLabel.lua
--
-- One identity label per unit (target/focus). A holder frame parented to
-- UIParent (so the label's show state + alpha are INDEPENDENT of the attach
-- target's visibility) is SetPoint-anchored to the chosen attach frame —
-- the unit's cast bar or icon grid — so it tracks that frame's position
-- live with no per-frame bookkeeping. Appearance is link-resolved for a
-- linked Focus via NS.Units.LabelStyle; show/text stay per-unit via
-- NS.Units.Label. Replaces the two labels the dual-tracking work put on the
-- grid and cast bar directly.
--
-- The label text is a plain addon string (NS.Units.Label(unit).text), never
-- a 12.0 secret value, so SetText/SetFont on it are safe.

local addonName, NS = ...
local UnitLabel = NS:NewModule("UnitLabel", "AceEvent-3.0")

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- OUTLINE-family flag string fed to FontString:SetFont. "NONE" -> "".
local FLAG_MAP = {
    NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROME = "MONOCHROME",
}

local instances = {}   -- [unit] = { unit, frame, text, enabled }

local function titleCase(unit) return unit:sub(1, 1):upper() .. unit:sub(2) end

function UnitLabel:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = { unit = unit, frame = nil, text = nil, enabled = false }; instances[unit] = inst end
    return inst
end

-- The frame this unit's label anchors to, or nil if that widget isn't live.
local function attachFrame(unit, attach)
    if attach == "icons" then
        local m = NS:GetModule("IconGrid", true)
        return m and m:GetGridFrame(unit) or nil
    end
    local m = NS:GetModule("Castbar", true)
    return m and m:GetCastbarFrame(unit) or nil
end

function UnitLabel:EnsureFrame(inst)
    if inst.frame then return end
    local f = CreateFrame("Frame", "KickCDUnitLabel" .. titleCase(inst.unit), UIParent)
    f:SetSize(1, 1)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    inst.frame, inst.text = f, fs
end

--- Resolve + apply this unit's label: text (per-unit), appearance (link-
--- resolved), and position (anchored to the chosen attach frame). Shown
--- only when the unit is enabled, label.show is on, AND an attach frame
--- exists — independent of whether that frame is currently drawn.
function UnitLabel:Apply(inst)
    self:EnsureFrame(inst)
    local lbl   = NS.Units.Label(inst.unit)
    local style = NS.Units.LabelStyle(inst.unit)
    local fs, f = inst.text, inst.frame

    fs:SetText(lbl.text or "")

    local fontPath
    if LSM and LSM.Fetch then
        fontPath = LSM:Fetch("font", style.font or "Friz Quadrata TT", true)
    end
    fs:SetFont(fontPath or STANDARD_TEXT_FONT, style.size or 14, FLAG_MAP[style.flags] or "OUTLINE")
    fs:SetJustifyH(style.justifyH or "CENTER")
    fs:SetJustifyV(style.justifyV or "MIDDLE")
    if fs.SetRotation then
        fs:SetRotation(((style.rotation or 0) * math.pi) / 180)
    end

    local target = attachFrame(inst.unit, style.attach or "castbar")
    f:ClearAllPoints()
    if target then
        f:SetPoint(style.point or "BOTTOM", target, style.relPoint or "TOP",
                   style.offsetX or 0, style.offsetY or 0)
    end

    inst.enabled = NS.Units.IsEnabled(inst.unit)
    f:SetShown(inst.enabled and lbl.show == true and target ~= nil)
end

function UnitLabel:ApplyAll()
    for _, u in ipairs(NS.Units.LIST) do
        self:Apply(self:GetInstance(u))
    end
end

-- A label edit, a per-unit enable toggle, or — for a linked Focus — an
-- icons/castbar edit can all change the resolved label or its anchor, so
-- re-apply on any CONFIG_CHANGED. Cheap: two SetText/SetPoint passes.
function UnitLabel:OnConfigChanged() self:ApplyAll() end
function UnitLabel:OnProfileChanged() self:ApplyAll() end
-- A grid (re)created after we first anchored needs a fresh SetPoint target.
function UnitLabel:OnGridLayout() self:ApplyAll() end
function UnitLabel:OnPlayerEnteringWorld() self:ApplyAll() end

function UnitLabel:OnEnable()
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("Ka0s_KickCD_GRID_LAYOUT",     "OnGridLayout")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")
    self:ApplyAll()
end

function UnitLabel:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    for _, inst in pairs(instances) do
        if inst.frame then inst.frame:Hide() end
    end
end
```

- [ ] **Step 5: Register in TOC** — in `KickCD.toc`, add `modules\UnitLabel.lua` immediately after `modules\Castbar.lua` (L52). (Load order after Castbar/IconGrid; it references them via `GetModule` at apply-time, so registration order is sufficient.)

- [ ] **Step 6: Remove the IconGrid label** — in `modules/IconGrid.lua`:
  - Delete the `label = nil,` instance field (L83).
  - Delete the whole `IconGrid:ApplyLabel` method (L502-512 — the function and its doc comment L502-507).
  - Delete the label-creation block in `EnsureGrid` (L580-585: the comment + `inst.label = grid:CreateFontString(...)` + its `SetPoint`).
  - Delete the three `self:ApplyLabel(inst)` calls (L405, L809, L833) and their immediately-preceding explanatory comments where present (L401-405, L806-809).

- [ ] **Step 7: Remove the Castbar label** — in `modules/Castbar.lua`:
  - Delete the `label = nil,` instance field (L93).
  - Delete the whole `Castbar:ApplyLabel` method (L562-572 incl. its doc comment).
  - Delete the label-creation block in `EnsureFrame` (L509-515: comment + `inst.label = frame:CreateFontString(...)` + `SetPoint`).
  - Delete the identity-label re-apply in `Reskin` (L827-831: comment + `self:ApplyLabel(inst)`).
  - Delete the `self:ApplyLabel(inst)` call in the config handler (L1418) and its preceding comment (L1415-1418).

- [ ] **Step 8: Run tests + lint** — Run: `lua tests/run.lua` — Expected: PASS (incl. `test_unitlabel.lua`; existing IconGrid/Castbar tests still green — none asserted on `ApplyLabel`). Run: `luacheck .` — Expected: 0 errors (delete any now-unused label upvalues/locals fully).

- [ ] **Step 9: SMOKE TEST (required)** — `/reload`. With `units.<unit>.label.show` toggled on (via `/kcd set units.target.label.show true`), confirm exactly ONE "Target" label renders (not two), anchored above the cast bar by default, and no label appears on the icon grid. Confirm no Lua errors in BugSack.

- [ ] **Step 10: Commit** (user): `Feat: single UnitLabel module; remove grid + cast bar labels`.

---

# Task 6: "Text Label" settings page + move controls out of General

**Files:**
- Create: `settings/Label.lua`
- Modify: `settings/Panel.lua` (`_validPanels` L152-155 add `label = true`; `NS.Settings.order` L31 add `"label"` after `"castbar"`)
- Modify: `settings/General.lua` (remove the label show/text `for` loop L~; keep the enable loop)
- Modify: `KickCD.toc` (add `settings\Label.lua` after `settings\Castbar.lua` L58)
- Modify: `locales/enUS.lua` (new strings)
- Test: `tests/test_schema.lua` (update General/label expectations)

**Interfaces:**
- Consumes: `Helpers.RenderUnitPanel`, `Helpers.AnchorValues`, `Helpers.LSMValues`, `NS.Units.LIST`.
- Produces: schema rows `panel = "label"`, `section = "label"`, unit-scoped `units.<unit>.label.*`; `show`/`text` rows carry `alwaysPerUnit = true`.

- [ ] **Step 1: Write/adjust failing tests** — in `tests/test_schema.lua`:
  - Extend the unit-scope test (L37-45) so `def.panel == "label"` is included in the `if` that requires a `unit` field and a `units.<unit>.` path.
  - Replace the General focus-rows test (L68-101) assertions about `units.focus.label.show/text` being on **General** with: they now live on **label**, and General no longer carries them. Concretely:

```lua
test("label panel carries per-unit label rows; General no longer does", function()
    local NS = T.NS
    local H  = NS.Settings.Helpers
    local function hasPath(rows, path)
        for _, d in ipairs(rows) do if d.path == path then return true end end
        return false
    end
    local generalRows = H.SchemaForPanel("general", nil)
    assertTrue(not hasPath(generalRows, "units.focus.label.show"),
        "General must NOT carry label.show anymore")
    assertTrue(hasPath(generalRows, "units.focus.enabled"),
        "General still carries the per-unit enable")

    local labelFocus = H.SchemaForPanel("label", "focus")
    assertTrue(hasPath(labelFocus, "units.focus.label.show"), "label panel has focus label.show")
    assertTrue(hasPath(labelFocus, "units.focus.label.text"), "label panel has focus label.text")

    -- show/text are alwaysPerUnit so they survive a Focus link
    for _, d in ipairs(labelFocus) do
        if d.path == "units.focus.label.show" or d.path == "units.focus.label.text" then
            assertTrue(d.alwaysPerUnit == true, d.path .. " must be alwaysPerUnit")
        end
    end
    assertEqual(H.ValidateSchema(), 0, "schema still valid with the label panel")
end)
```

- [ ] **Step 2: Run to verify failure** — Run: `lua tests/run.lua` — Expected: FAIL (label panel rows absent; General still has them; `_validPanels.label` missing → ValidateSchema > 0).

- [ ] **Step 3: Allow the `label` panel + order it** — in `settings/Panel.lua`:
  - `_validPanels` (L152-155): add `label = true,`.
  - `NS.Settings.order` (L31): change to `{ "general", "icons", "castbar", "label", "spells", "profiles" }`.

  Note: `_validSections` already contains no `label` entry — add `label = true,` to `_validSections` (L156-159) as well, since the new rows use `section = "label"`.

- [ ] **Step 4: Create `settings/Label.lua`**:

```lua
-- settings/Label.lua
--
-- "Text Label" canvas panel. One identity label per unit (target/focus),
-- rendered by modules/UnitLabel.lua. Pure schema: every widget is a row in
-- KickCD.Settings.Schema, generated once per NS.Units.LIST entry with a
-- unit-scoped path (units.<unit>.label.*). show/text are alwaysPerUnit
-- (per-unit even when Focus is linked); the appearance rows follow the link.
-- Uses the shared unit-selector header via Helpers.RenderUnitPanel.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

local ANCHOR_VALUES = H.AnchorValues()

local JUSTIFY_H_VALUES = {
    { value = "LEFT",   label = L["Left"]   },
    { value = "CENTER", label = L["Center"] },
    { value = "RIGHT",  label = L["Right"]  },
}
local JUSTIFY_V_VALUES = {
    { value = "TOP",    label = L["Top"]    },
    { value = "MIDDLE", label = L["Middle"] },
    { value = "BOTTOM", label = L["Bottom"] },
}
local FLAG_VALUES = {
    { value = "NONE",         label = L["None"]          },
    { value = "OUTLINE",      label = L["Outline"]       },
    { value = "THICKOUTLINE", label = L["Thick outline"] },
    { value = "MONOCHROME",   label = L["Monochrome"]    },
}
local ATTACH_VALUES = {
    { value = "castbar", label = L["Cast bar"]  },
    { value = "icons",   label = L["Icon grid"] },
}

local function addUnitRows(unit)
    -- Identity (per-unit even when linked) --------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Label"],
         alwaysPerUnit = true,
         path = "units." .. unit .. ".label.show", type = "bool",
         label = L["Show label"],
         tooltip = L["Show this unit's identity label."],
         default = false }
    add{ panel = "label", section = "label", unit = unit, group = L["Label"],
         alwaysPerUnit = true,
         path = "units." .. unit .. ".label.text", type = "string",
         label = L["Label text"],
         tooltip = L["Text shown on this unit's label."],
         default = (unit == "target" and "Target" or "Focus") }

    -- Placement -----------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.attach", type = "string",
         label = L["Attach to"],
         tooltip = L["Which widget the label anchors to."],
         default = "castbar", values = ATTACH_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.point", type = "string",
         label = L["Label anchor point"],
         tooltip = L["Which point of the label attaches."],
         default = "BOTTOM", values = ANCHOR_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.relPoint", type = "string",
         label = L["Attach point"],
         tooltip = L["Which point of the target widget the label attaches to."],
         default = "TOP", values = ANCHOR_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetX", type = "number",
         label = L["X offset (in px)"],
         tooltip = L["Horizontal pixel shift (positive = right)."],
         default = 0, min = -200, max = 200, step = 1, fmt = "%d px" }
    add{ panel = "label", section = "label", unit = unit, group = L["Placement"],
         path = "units." .. unit .. ".label.style.offsetY", type = "number",
         label = L["Y offset (in px)"],
         tooltip = L["Vertical pixel shift (positive = up)."],
         default = 0, min = -200, max = 200, step = 1, fmt = "%d px" }

    -- Orientation ---------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.justifyH", type = "string",
         label = L["Horizontal justify"],
         tooltip = L["Horizontal text alignment."],
         default = "CENTER", values = JUSTIFY_H_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.justifyV", type = "string",
         label = L["Vertical justify"],
         tooltip = L["Vertical text alignment."],
         default = "MIDDLE", values = JUSTIFY_V_VALUES }
    add{ panel = "label", section = "label", unit = unit, group = L["Orientation"],
         path = "units." .. unit .. ".label.style.rotation", type = "number",
         label = L["Rotation (degrees)"],
         tooltip = L["Rotate the label. 0 = upright."],
         default = 0, min = -180, max = 180, step = 5, fmt = "%d°" }

    -- Font ----------------------------------------------------------------
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.font", type = "string",
         label = L["Font"],
         tooltip = L["LSM font for the label."],
         default = "Friz Quadrata TT", lsm = "font",
         values = function() return H.LSMValues("font") end }
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.size", type = "number",
         label = L["Font size"],
         tooltip = L["Label font size in pixels."],
         default = 14, min = 6, max = 48, step = 1, fmt = "%d" }
    add{ panel = "label", section = "label", unit = unit, group = L["Font"],
         path = "units." .. unit .. ".label.style.flags", type = "string",
         label = L["Font flags"],
         tooltip = L["Outline / monochrome flags."],
         default = "OUTLINE", values = FLAG_VALUES }
end

for _, u in ipairs(NS.Units.LIST) do addUnitRows(u) end

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    local ctx
    ctx = H.CreatePanel("KickCDLabelPanel", L["Text Label"], {
        panelKey       = "label",
        defaultsButton = true,
    })
    if ctx.panel.defaultsBtn then
        ctx.panel.defaultsBtn:SetCallback("OnClick", function()
            H.RestoreDefaults("label", ctx)
        end)
    end
    local rendered = false
    ctx.panel:SetScript("OnShow", function()
        if rendered then return end
        rendered = true
        H.RenderUnitPanel(ctx, "label")
    end)
    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Text Label"])
end

if NS.Settings and NS.Settings.RegisterTab then
    NS.Settings.RegisterTab("label", Build)
end
```

- [ ] **Step 5: Register in TOC** — in `KickCD.toc`, add `settings\Label.lua` immediately after `settings\Castbar.lua` (L58).

- [ ] **Step 6: Remove the label rows from General** — in `settings/General.lua`, delete the entire second per-unit `for` loop (the one adding `units.<unit>.label.show` and `units.<unit>.label.text`, ~L after the enable loop, including its explanatory comment block). Keep the FIRST loop (the per-unit `enabled` rows) intact.

- [ ] **Step 7: Add locale strings** — in `locales/enUS.lua`, add any missing keys (leave existing ones untouched):

```lua
L["Text Label"]          = "Text Label"
L["Label"]               = "Label"
L["Show label"]          = "Show label"
L["Label text"]          = "Label text"
L["Placement"]           = "Placement"
L["Attach to"]           = "Attach to"
L["Cast bar"]            = "Cast bar"
L["Icon grid"]           = "Icon grid"
L["Label anchor point"]  = "Label anchor point"
L["Attach point"]        = "Attach point"
L["Orientation"]         = "Orientation"
L["Horizontal justify"]  = "Horizontal justify"
L["Vertical justify"]    = "Vertical justify"
L["Rotation (degrees)"]  = "Rotation (degrees)"
L["Left"]                = "Left"
L["Right"]               = "Right"
L["Top"]                 = "Top"
L["Middle"]              = "Middle"
L["Bottom"]              = "Bottom"
```

(`Center`, `Font`, `Font size`, `Font flags`, `None`, `Outline`, `Thick outline`, `Monochrome`, `X offset (in px)`, `Y offset (in px)` already exist from Icons — do not re-add.)

- [ ] **Step 8: Run tests + lint** — Run: `lua tests/run.lua` — Expected: PASS (updated `test_schema.lua`). Run: `luacheck .` — Expected: 0 errors.

- [ ] **Step 9: SMOKE TEST (required)** — `/reload`. Open Settings → **Text Label**:
  1. Unit selector Target↔Focus works (like Cast bar's).
  2. Toggle Show label; edit Label text → live on the widget.
  3. Attach to: Cast bar ↔ Icon grid → label jumps between the two anchors.
  4. Anchor point / attach point / X/Y offset → label moves accordingly.
  5. Horizontal/Vertical justify + Rotation → label re-orients.
  6. Font / size / flags → label restyles.
  7. Focus **linked**: Show + Label text stay editable; the appearance rows are replaced by the "Linked to Target" note. Uncheck link → appearance rows appear.
  8. Independent visibility: with attach = cast bar and target NOT casting (cast bar hidden), the label still shows.
  9. `/kcd set units.focus.label.style.size 30` reflects live. Confirm General no longer shows label show/text rows.

- [ ] **Step 10: Commit** (user): `Feat: Text Label settings page; move label controls out of General`.

---

# Task 7: Docs, deviations, badges

**Files:**
- Modify: `docs/saved-variables.md`, `docs/module-map.md`, `docs/conventions.md`, `docs/ARCHITECTURE.md`, `docs/smoke-tests.md`
- Regenerate: `docs/test-cases.md` + README `[Tests]` badge

- [ ] **Step 1: Record the deviations** (per the existing intentional-deviation pattern):
  - `docs/conventions.md` — new frame names `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus` (extend the existing frame-name deviation note: the label frames follow the same `KickCD<Widget><UnitTitleCase>` pattern; they are parented to `UIParent`, not a widget, because the label's visibility is deliberately independent of its attach target).
  - `docs/saved-variables.md` — `units.<unit>.label.style` sub-shape + the shape-driven `BackfillLabelStyle` migration; note `show`/`text` are per-unit and `style` is link-resolved.
  - `docs/module-map.md` — new `modules/UnitLabel.lua` (per-unit single label; parented to UIParent, SetPoint-anchored to grid/cast bar); IconGrid/Castbar no longer own labels; new `alwaysPerUnit` schema flag; new `label` settings panel/section.
  - `docs/ARCHITECTURE.md` — add UnitLabel to the module map + message-subscriber list (subscribes CONFIG_CHANGED / PROFILE_CHANGED / GRID_LAYOUT).

- [ ] **Step 2: Add smoke scenarios** — in `docs/smoke-tests.md`, add the Text Label scenarios from Task 6 Step 9 and the migration smoke (load a pre-`label.style` `KickCDDB`; confirm `BackfillLabelStyle` fills it with no visual change).

- [ ] **Step 3: Regenerate the test inventory + badge** — Run: `lua tests/run.lua --list > docs/test-cases.md`. Then update the README `Tests-X/Y_passing` badge to the new counts in the SAME edit. Verify: `diff <(lua tests/run.lua --list) docs/test-cases.md` (empty).

- [ ] **Step 4: Final verification** — Run: `lua tests/run.lua` (exit 0); `luacheck .` (0 errors).

- [ ] **Step 5: Commit** (user): `Docs: single text-label feature; regenerate test inventory + badge`.

---

## Task dependency order

1 (DB defaults + migration) → 2 (NS.Units resolvers) → 3 (renderer hardening) → 4 (alwaysPerUnit) → 5 (UnitLabel module + strip old labels) → 6 (Text Label page + General cleanup) → 7 (docs/badges). Tasks 1–4 are fully headless-testable; 5–6 require the in-game smoke tests noted. Task 3 (hardening) is independent of the label work and could land first if desired.

## Open item carried from the spec

**Focus anchor offset:** `units.focus.anchors.icons/castbar` keep a small default offset from Target's (so the grids don't stack on first enable). This plan does NOT change that — it is the sole non-identical default. If the user wants the position anchors identical too, that is a one-line change to `DEFAULT_PROFILE.units.focus.anchors` in `core/Database.lua`, added as a step to Task 1.
