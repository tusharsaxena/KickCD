-- modules/Castbar_Debug.lua
--
-- Debug diagnostics peeled out of modules/Castbar.lua to keep that file under
-- the layout-§1 1500-line hard cap (recorded intentional split, KCD-19). This file
-- adds the Castbar:DebugDump method to the already-registered Castbar module;
-- it is loaded AFTER modules/Castbar.lua (see the TOC). /kcd debug castbar
-- routes here via NS:GetModule("Castbar"):DebugDump() (core/KickCD.lua).

local _, NS = ...
local Castbar = NS:GetModule("Castbar")   -- registered by modules/Castbar.lua, which loads first

-- Configured per-state colors as actually read from the live profile
-- (link-resolved via NS.Units.Castbar). Useful for verifying that
-- color-picker writes are persisting and that Reskin sees the updates.
-- Renders through Util.Unpack so the dump reports what the addon actually
-- reads, in the keyed storage shape, rather than four zeroes.
local function fmtColor(c)
    if type(c) ~= "table" then return "(missing)" end
    return ("{%.2f, %.2f, %.2f, %.2f}"):format(NS.Util.Unpack(c))
end

--- The color actually live on a StatusBar widget right now.
local function fmtStatusColor(sb)
    if not sb or not sb.GetStatusBarColor then return "(no widget)" end
    local r, g, b, a = sb:GetStatusBarColor()
    return ("{%.2f, %.2f, %.2f, %.2f}"):format(r or 0, g or 0, b or 0, a or 1)
end

--- Report the notInterruptible flag's plain value, keyed on its TYPE. A
--- boolean or a nil is safe to render; anything else is presumed secret and
--- only ever described, never tostring'd. The default arm is the secret one.
local NINT_REPORT = {
    boolean = function(emit, v)
        -- Plain boolean — safe to tostring.
        emit("    plain value = " .. tostring(v))
    end,
    ["nil"] = function(emit)
        emit("    plain nil (treated as interruptible)")
    end,
}

--- The DEFAULT arm of NINT_REPORT: anything that is neither a boolean nor a
--- nil lands here, which on a 12.0 client is the interesting case.
---
--- The line goes out UNCONDITIONALLY. Whether C_CurveUtil is there decides how
--- the visual state is being determined, and that is a clause of the sentence;
--- it is not permission to say anything at all. Printing only when the
--- evaluator exists is what this used to do, and it left a client without one
--- reporting the field as secret and then falling silent about it -- which,
--- to somebody pasting the dump into a bug report, reads exactly like a dump
--- that had nothing to say rather than one that could not render it.
---
--- The value itself is still never tostring'd or formatted: it is described.
local function reportSecretNint(emit)
    local via = (_G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean)
        and "visual state determined via C_CurveUtil.EvaluateColorValueFromBoolean"
        or  "C_CurveUtil.EvaluateColorValueFromBoolean unavailable"
    emit("    secret-tainted; " .. via)
end

--- Who the unit is and whether we can attack it.
--- @return boolean true when the unit exists and the dump should continue
local function dumpUnitHeader(emit, inst)
    if not _G.UnitExists(inst.unit) then
        emit("  no " .. inst.unit)
        return false
    end
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", inst.unit)
    emit("  " .. inst.unit .. " = " .. (_G.UnitName(inst.unit) or "?")
        .. ", isUnit="    .. (UnitIsUnit(inst.unit, "player") and "self" or "other")
        .. ", canAttack=" .. tostring(canAttack and true or false))
    return true
end

--- The no-tracked-cast arm. Probing Compat here is the whole diagnostic value
--- of the branch: `current` nil while the API still reports a cast means an
--- event was dropped somewhere.
local function dumpNoCastHint(emit, inst)
    emit("  no active cast tracked (current = nil)")
    local rec = NS.Compat.GetCastingInfo(inst.unit)
    if rec then
        emit("  but Compat.GetCastingInfo returned a record — debug a missed event?")
    end
end

--- The tracked cast record. Don't tostring/format secret values: use type()
--- and a boolean branch to safely report the state without arithmetic on a
--- secret.
local function dumpCastRecord(emit, inst)
    local current = inst.current
    emit("  current.isChannel = " .. tostring(current.isChannel))

    local nintType = type(current.notInterruptible)
    emit("  current.notInterruptible: type=" .. nintType
        .. ", isSecret=" .. tostring(_G.issecretvalue and _G.issecretvalue(current.notInterruptible) or false))
    local report = NINT_REPORT[nintType] or reportSecretNint
    report(emit, current.notInterruptible)

    emit("  duration: " .. (current.duration and "present" or "nil"))
    emit("  texture:  type=" .. type(current.texture))
    emit("  spellID:  type=" .. type(current.spellID))
    emit("  name:     type=" .. type(current.name))
end

--- The per-state colors the profile currently holds for this unit.
local function dumpConfiguredColors(emit, inst)
    local castCfg = NS.Units.Castbar(inst.unit)
    local intCfg = castCfg.interruptible   or {}
    local nintCfg = castCfg.uninterruptible or {}
    emit("  configured colors")
    emit("    interruptible   bar="    .. fmtColor(intCfg.barColor)
        .. " border=" .. fmtColor(intCfg.borderColor)
        .. " bg="     .. fmtColor(intCfg.bgColor))
    emit("    uninterruptible bar="    .. fmtColor(nintCfg.barColor)
        .. " border=" .. fmtColor(nintCfg.borderColor)
        .. " bg="     .. fmtColor(nintCfg.bgColor))
end

--- And the colors actually live on the StatusBar widgets right now.
local function dumpLiveBarColors(emit, inst)
    emit("  live SetStatusBarColor values")
    local f = inst.frame
    emit("    interruptible   = " .. fmtStatusColor(f and f.bar and f.bar.interruptible))
    emit("    uninterruptible = " .. fmtStatusColor(f and f.bar and f.bar.uninterruptible))
end

--- Print diagnostic info about `unit`'s cast (default "target") and what the
--- bar's logic decided about interruptibility. Wired to /kcd debug castbar.
--- Does NOT call tostring or format on notInterruptible / spellID / name --
--- those may be secret in combat. Uses tostring(type(...)) / boolean
--- branching with `not not` to avoid arithmetic on secrets.
function Castbar:DebugDump(unit)
    local inst = self:GetInstance(unit or "target")
    local emit = NS.Util.print
    emit("castbar state (" .. inst.unit .. ")")

    if not dumpUnitHeader(emit, inst) then return end
    if not inst.current then dumpNoCastHint(emit, inst); return end

    dumpCastRecord(emit, inst)
    dumpConfiguredColors(emit, inst)
    dumpLiveBarColors(emit, inst)
end
