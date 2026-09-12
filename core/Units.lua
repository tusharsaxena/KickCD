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
--- Row by row through the settings helper (architecture-§5: a copy-from that
--- touches rows is a helper write), via H.SetRows, so every row's write is
--- Helpers.Set's and its onChange runs. The walk is in schema declaration order,
--- and that is load-bearing for the cast bar: orientation's onChange resets
--- growDirection to that axis's default, and growDirection is declared after it,
--- so the copied value lands last and wins.
---
--- ONE structural refresh, not dozens of reactors. H.SetRows coalesces the bus,
--- so each section is announced once, after the last row. The link row is
--- written last, and when the copy flips it, its own onChange is the structural
--- refresh the Units tab used to do by hand. That onChange repaints only when the
--- link moves, so a copy onto a unit that is already unlinked, or onto a unit
--- with no link row (Target), gets the same one refresh here instead.
---
--- ONE [Set] line, not one per row. The copy is a single act, so it hands
--- SetRows a summary: the per-row lines are muted and the debug log shows
--- `[Set] copy target→focus: N rows`. Validation and onChange stay per row.
--- @return boolean  whether the copy ran (false before the settings layer loads)
function Units.CopyStyling(fromUnit, toUnit)
    local H = NS.Settings and NS.Settings.Helpers
    if not (H and H.SetRows and Units.Config(fromUnit) and Units.Config(toUnit)) then
        return false
    end
    local src, dst = "units." .. fromUnit .. ".", "units." .. toUnit .. "."
    local writes = {}
    for _, def in ipairs(NS.Settings.Schema) do
        local path = def.path
        if type(path) == "string" and path:sub(1, #src) == src then
            local rel = path:sub(#src + 1)
            if copied(rel) then
                local v = H.Get(path)
                -- A color is a table; the copy must own its own.
                writes[#writes + 1] = { dst .. rel, type(v) == "table" and NS.Util.DeepCopy(v) or v }
            end
        end
    end
    local linkRow = H.FindSchema(dst .. "link")
    -- Whether the link row's onChange will repaint: only when the copy flips it.
    local linkFlips = linkRow ~= nil and H.Get(linkRow.path) ~= false
    if linkRow then writes[#writes + 1] = { linkRow.path, false } end
    H.SetRows(writes, "copy " .. fromUnit .. "→" .. toUnit)
    if not linkFlips then H.RefreshAllPanels() end
    return true
end
