-- modules/Castbar_Debug.lua
--
-- Debug diagnostics peeled out of modules/Castbar.lua to keep that file under
-- the §1.2 1500-line hard cap (recorded intentional split, KCD-19). This file
-- adds the Castbar:DebugDump method to the already-registered Castbar module;
-- it is loaded AFTER modules/Castbar.lua (see the TOC). /kcd debug castbar
-- routes here via NS:GetModule("Castbar"):DebugDump() (core/KickCD.lua).

local addonName, NS = ...
local Castbar = NS:GetModule("Castbar")   -- registered by modules/Castbar.lua, which loads first

--- Print diagnostic info about `unit`'s cast (default "target") and what the
--- bar's logic decided about interruptibility. Wired to /kcd debug castbar.
--- Does NOT call tostring or format on notInterruptible / spellID / name --
--- those may be secret in combat. Uses tostring(type(...)) / boolean
--- branching with `not not` to avoid arithmetic on secrets.
function Castbar:DebugDump(unit)
    local inst = self:GetInstance(unit or "target")
    local print = NS.Util and NS.Util.print or _G.print
    print("castbar state (" .. inst.unit .. ")")

    if not UnitExists(inst.unit) then
        print("  no " .. inst.unit)
        return
    end
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", inst.unit)
    print("  " .. inst.unit .. " = " .. (UnitName(inst.unit) or "?")
        .. ", isUnit="    .. (UnitIsUnit(inst.unit, "player") and "self" or "other")
        .. ", canAttack=" .. tostring(canAttack and true or false))

    if not inst.current then
        print("  no active cast tracked (current = nil)")
        local rec = NS.Compat.GetCastingInfo(inst.unit)
        if rec then
            print("  but Compat.GetCastingInfo returned a record — debug a missed event?")
        end
        return
    end

    print("  current.isChannel = " .. tostring(inst.current.isChannel))
    -- Don't tostring/format secret values. Use type() and a curve eval to
    -- safely report the boolean state without arithmetic on a secret.
    local nintType = type(inst.current.notInterruptible)
    print("  current.notInterruptible: type=" .. nintType
        .. ", isSecret=" .. tostring(_G.issecretvalue and _G.issecretvalue(inst.current.notInterruptible) or false))
    if nintType == "boolean" then
        -- Plain boolean — safe to tostring.
        print("    plain value = " .. tostring(inst.current.notInterruptible))
    elseif nintType == "nil" then
        print("    plain nil (treated as interruptible)")
    else
        -- Likely secret. Use the curve evaluator to surface a safe int.
        if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then
            -- Pass to FontString:SetText via a hidden frame to render and
            -- read back. Cleanest: just say "secret" and trust the curve.
            print("    secret-tainted; visual state determined via "
                .. "C_CurveUtil.EvaluateColorValueFromBoolean")
        end
    end
    print("  duration: " .. (inst.current.duration and "present" or "nil"))
    print("  texture:  type=" .. type(inst.current.texture))
    print("  spellID:  type=" .. type(inst.current.spellID))
    print("  name:     type=" .. type(inst.current.name))

    -- Configured per-state colors as actually read from the live profile
    -- (link-resolved via NS.Units.Castbar). Useful for verifying that
    -- color-picker writes are persisting and that Reskin sees the updates.
    -- Renders through Util.Unpack so the dump reports what the addon actually
    -- reads, in the keyed storage shape, rather than four zeroes.
    local function fmtColor(c)
        if type(c) ~= "table" then return "(missing)" end
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(NS.Util.Unpack(c))
    end
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

    -- And the colors actually live on the StatusBar widgets right now.
    local function fmtStatusColor(sb)
        if not sb or not sb.GetStatusBarColor then return "(no widget)" end
        local r, g, b, a = sb:GetStatusBarColor()
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(r or 0, g or 0, b or 0, a or 1)
    end
    print("  live SetStatusBarColor values")
    local f = inst.frame
    print("    interruptible   = " .. fmtStatusColor(f and f.bar and f.bar.interruptible))
    print("    uninterruptible = " .. fmtStatusColor(f and f.bar and f.bar.uninterruptible))
end
