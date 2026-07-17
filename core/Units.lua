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

function Units.CopyStyling(fromUnit, toUnit)
    local src = Units.Config(fromUnit)
    local dst = Units.Config(toUnit)
    if not (src and dst) then return end
    dst.icons   = NS.Util.DeepCopy(src.icons)
    dst.castbar = NS.Util.DeepCopy(src.castbar)
    dst.label = dst.label or {}
    dst.label.style = NS.Util.DeepCopy(src.label and src.label.style)
    -- show follows the link (spec 2b), so a one-shot snapshot must capture it
    -- too — otherwise unlinking would revive focus's stale independent show.
    -- Text stays per-unit (spec 2a) and is deliberately NOT copied.
    dst.label.show  = (src.label and src.label.show) and true or false
    dst.link    = false
end
