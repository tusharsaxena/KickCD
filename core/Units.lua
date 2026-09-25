-- core/Units.lua
--
-- Single source of unit identity + per-unit config resolution for the
-- target/focus dual-tracking feature. The two widget modules (IconGrid,
-- Castbar) never reach db.profile.units directly for appearance — they call
-- NS.Units.Icons(unit) / .Castbar(unit) / .Anchor(unit, which) so the
-- "link to target styling" behavior lives in exactly one place.
--
-- Link semantics (spec 2b): when units.focus.link == true, Focus renders with
-- Target's icons/castbar tables (total mirror). enabled, anchors (position),
-- and label.text stay per-unit even while linked. Target is never linked.

local _, NS = ...
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
    -- The master flag through its one reader (core/LifecycleSetup.lua), never
    -- off the profile here. A missing profile still answers false below:
    -- Units.Config has no table to return.
    if NS.MasterEnabled and not NS.MasterEnabled() then return false end
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

-- Persist a saved anchor for `unit`'s `which` frame ("icons" / "castbar").
-- Position stays per-unit even while linked (only appearance is mirrored),
-- so the write always targets the unit's own config table.
function Units.SetAnchor(unit, which, a)
    local c = Units.Config(unit)
    if c then
        c.anchors = c.anchors or {}
        c.anchors[which] = a
    end
end

--- Per-unit label table (units.<unit>.label). Read `.text` from here — the
--- label TEXT is per-unit even while linked (spec 2a: a focus label reading
--- "Target" defeats its purpose). Label VISIBILITY (`.show`) is NOT per-unit;
--- resolve it through Units.LabelShow, which follows the styling link.
function Units.Label(unit)
    local c = Units.Config(unit)
    return (c and c.label) or { show = false, text = unit }
end

--- Link-resolved label VISIBILITY (units.<unit>.label.show). Per spec 2b,
--- label.show follows the Focus link exactly like Icons/Castbar/label.style —
--- a linked focus mirrors target's show, so turning the target label off also
--- hides a linked focus. Only label.text stays per-unit (see Units.Label).
function Units.LabelShow(unit)
    local c = Units.Config(sourceUnit(unit))
    return c ~= nil and c.label ~= nil and c.label.show == true
end

--- Link-resolved label APPEARANCE (units.<unit>.label.style). Follows the
--- Focus link exactly like Icons/Castbar: a linked focus reads target's
--- style. label.text is NOT resolved here — it stays per-unit (see
--- Units.Label); label.show follows the link via Units.LabelShow.
function Units.LabelStyle(unit)
    local c = Units.Config(sourceUnit(unit))
    return (c and c.label and c.label.style) or {}
end

-- What a copy carries, relative to `units.<unit>.`: every row under these.
-- Every leaf under the three subtrees IS a schema row (tests/test_units.lua's
-- characterization walks them), so a walk of rows is the whole copy. label.show
-- is in because it follows the link (spec 2b): a one-shot snapshot must capture
-- it, or unlinking would revive focus's stale independent show. label.text is
-- deliberately OUT: the text stays per-unit (spec 2a).
local COPIED = { "icons.", "castbar.", "label.style.", "label.show" }

local function copied(rel)
    for _, prefix in ipairs(COPIED) do
        if rel:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Copy `fromUnit`'s appearance onto `toUnit` once, then unlink `toUnit`.
---
--- ONE Store.SetMany (architecture-§5: a copy-from that touches rows is a helper
--- write), so the copy is one act, ALL OR NOTHING: every row is checked before
--- any is stored, and a refusal leaves `toUnit` exactly as it was. Then every
--- row is stored, then every row's onChange runs, in schema declaration order.
--- Stores first is what a reaction reading a sibling row needs -- orientation's
--- onChange sees the copied growDirection already stored and leaves it alone
--- (settings/Castbar.lua).
---
--- ONE announcement per section, not a hundred-odd: the seam's announceBatch
--- sends each section the batch touched once, after every reaction
--- (settings/SchemaSetup.lua). The link row is written last, and when the copy
--- flips it, its own onChange is the structural refresh the Units tab used to do
--- by hand. That onChange repaints only when the link moves, so a copy onto a
--- unit that is already unlinked, or onto a unit with no link row (Target), gets
--- the same one refresh here instead.
---
--- ONE [Set] line, not one per row: `act = "copy"` makes the batch one bracket,
--- so the debug log shows `[Set] copy target→focus: N rows`, N the rows the copy
--- actually moved (debug-logging-§10).
--- @return boolean  whether the copy ran (false before the settings layer loads,
---                  or when the seam refused the batch)
function Units.CopyStyling(fromUnit, toUnit)
    local Settings = NS.Settings
    local Store = Settings and Settings.Store
    local H = Settings and Settings.Helpers
    if not (Store and H and Units.Config(fromUnit) and Units.Config(toUnit)) then
        return false
    end
    local src, dst = "units." .. fromUnit .. ".", "units." .. toUnit .. "."
    local entries = {}
    for _, def in ipairs(Store.AllRows()) do
        local path = def.path
        if type(path) == "string" and path:sub(1, #src) == src then
            local rel = path:sub(#src + 1)
            if copied(rel) then
                -- The seam copies a table value in, so a color never aliases.
                entries[#entries + 1] = { path = dst .. rel, value = Store.Get(path) }
            end
        end
    end
    local linkRow = Store.FindRow(dst .. "link")
    -- Whether the link row's onChange will repaint: only when the copy flips it.
    local linkFlips = linkRow ~= nil and Store.Get(linkRow.path) ~= false
    if linkRow then entries[#entries + 1] = { path = linkRow.path, value = false } end
    local ok = Store.SetMany(entries, { act = "copy", scope = fromUnit .. "→" .. toUnit })
    if not ok then return false end
    if not linkFlips then H.RefreshAllPanels() end
    return true
end
