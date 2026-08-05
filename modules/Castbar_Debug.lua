-- modules/Castbar_Debug.lua
--
-- Debug diagnostics peeled out of modules/Castbar.lua to keep that file under
-- the layout-§1 1500-line hard cap (recorded intentional split, KCD-19). This file
-- adds the Castbar:DebugDump method to the already-registered Castbar module;
-- it is loaded AFTER modules/Castbar.lua (see the TOC). /kcd debug castbar
-- routes here via NS:GetModule("Castbar"):DebugDump() (core/KickCD.lua).

local addonName, NS = ...
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
    boolean = function(print, v)
        -- Plain boolean — safe to tostring.
        print("    plain value = " .. tostring(v))
    end,
    ["nil"] = function(print)
        print("    plain nil (treated as interruptible)")
    end,
}

local function reportSecretNint(print)
    -- Likely secret. Use the curve evaluator to surface a safe int.
    if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then
        -- Pass to FontString:SetText via a hidden frame to render and
        -- read back. Cleanest: just say "secret" and trust the curve.
        print("    secret-tainted; visual state determined via "
            .. "C_CurveUtil.EvaluateColorValueFromBoolean")
    end
end

--- Who the unit is and whether we can attack it.
--- @return boolean true when the unit exists and the dump should continue
local function dumpUnitHeader(print, inst)
    if not UnitExists(inst.unit) then
        print("  no " .. inst.unit)
        return false
    end
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", inst.unit)
    print("  " .. inst.unit .. " = " .. (UnitName(inst.unit) or "?")
        .. ", isUnit="    .. (UnitIsUnit(inst.unit, "player") and "self" or "other")
        .. ", canAttack=" .. tostring(canAttack and true or false))
    return true
end

--- The no-tracked-cast arm. Probing Compat here is the whole diagnostic value
--- of the branch: `current` nil while the API still reports a cast means an
--- event was dropped somewhere.
local function dumpNoCastHint(print, inst)
    print("  no active cast tracked (current = nil)")
    local rec = NS.Compat.GetCastingInfo(inst.unit)
    if rec then
        print("  but Compat.GetCastingInfo returned a record — debug a missed event?")
    end
end

--- The tracked cast record. Don't tostring/format secret values: use type()
--- and a boolean branch to safely report the state without arithmetic on a
--- secret.
local function dumpCastRecord(print, inst)
    local current = inst.current
    print("  current.isChannel = " .. tostring(current.isChannel))

    local nintType = type(current.notInterruptible)
    print("  current.notInterruptible: type=" .. nintType
        .. ", isSecret=" .. tostring(_G.issecretvalue and _G.issecretvalue(current.notInterruptible) or false))
    local report = NINT_REPORT[nintType] or reportSecretNint
    report(print, current.notInterruptible)

    print("  duration: " .. (current.duration and "present" or "nil"))
    print("  texture:  type=" .. type(current.texture))
    print("  spellID:  type=" .. type(current.spellID))
    print("  name:     type=" .. type(current.name))
end

--- The per-state colors the profile currently holds for this unit.
local function dumpConfiguredColors(print, inst)
    local castCfg = NS.Units.Castbar(inst.unit)
    local intCfg = castCfg.interruptible   or {}
    local nintCfg = castCfg.uninterruptible or {}
    print("  configured colors")
    print("    interruptible   bar="    .. fmtColor(intCfg.barColor)
        .. " border=" .. fmtColor(intCfg.borderColor)
        .. " bg="     .. fmtColor(intCfg.bgColor))
    print("    uninterruptible bar="    .. fmtColor(nintCfg.barColor)
        .. " border=" .. fmtColor(nintCfg.borderColor)
        .. " bg="     .. fmtColor(nintCfg.bgColor))
end

--- And the colors actually live on the StatusBar widgets right now.
local function dumpLiveBarColors(print, inst)
    print("  live SetStatusBarColor values")
    local f = inst.frame
    print("    interruptible   = " .. fmtStatusColor(f and f.bar and f.bar.interruptible))
    print("    uninterruptible = " .. fmtStatusColor(f and f.bar and f.bar.uninterruptible))
end

--- Print diagnostic info about `unit`'s cast (default "target") and what the
--- bar's logic decided about interruptibility. Wired to /kcd debug castbar.
--- Does NOT call tostring or format on notInterruptible / spellID / name --
--- those may be secret in combat. Uses tostring(type(...)) / boolean
--- branching with `not not` to avoid arithmetic on secrets.
function Castbar:DebugDump(unit)
    local inst = self:GetInstance(unit or "target")
    local print = NS.Util and NS.Util.print or _G.print
    print("castbar state (" .. inst.unit .. ")")

    if not dumpUnitHeader(print, inst) then return end
    if not inst.current then dumpNoCastHint(print, inst); return end

    dumpCastRecord(print, inst)
    dumpConfiguredColors(print, inst)
    dumpLiveBarColors(print, inst)
end
