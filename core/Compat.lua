-- core/Compat.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.3
--
-- Thin compatibility shims for spell + settings APIs whose signatures
-- have churned across recent expansions. The runtime layer always goes
-- through KickCD.Compat.* so individual modules don't have to do their
-- own version-detection.
--
-- Every public function in this file is documented at the call site;
-- shapes match the table the caller expects from a "modern" Midnight
-- 12.0.5 client. When the underlying API isn't available we degrade
-- gracefully to safe defaults rather than throwing.

-- Establish the global addon namespace as early as possible. core/Compat.lua
-- is the first core file in the TOC load order, so anything that comes
-- after it can rely on _G.KickCD existing as a plain table to hang
-- helpers on (the AceAddon object replaces it later in core/KickCD.lua,
-- but the merge there preserves these fields).
KickCD = KickCD or {}

local Compat = {}
KickCD.Compat = Compat

-- ---------------------------------------------------------------------------
-- Spell APIs
-- ---------------------------------------------------------------------------

-- 12.0 secret-value protection: certain spells (notably interrupts) return
-- "secret" timing values from C_Spell.GetSpellCooldown. Comparing or doing
-- arithmetic on a secret value from tainted (addon) execution errors out,
-- and there is NO addon-side strip: securecallfunction does not clear our
-- own taint, tonumber/tostring propagate the flag, and `+0` arithmetic is
-- itself the operation that errors. The supported pattern (per Cell et al.
-- in 12.0) is to detect via `issecretvalue()` and degrade gracefully —
-- pass timing through opaquely (Blizzard C methods like Cooldown:SetCooldown
-- handle secret values fine) and use the plain boolean `info.isActive` for
-- "is on cooldown" decisions.

--- Cooldown info for a spell.
-- @param spellID number
-- @return startTime, duration, isEnabled, modRate, isActive
--   On error / no cooldown: 0, 0, false, 1, false
--   startTime/duration/modRate may be "secret" — never compare or do
--   arithmetic on them in tainted scope; pass them straight to C-side APIs
--   (Cooldown:SetCooldown) or gate with issecretvalue() first.
function Compat.GetSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if not info then return 0, 0, false, 1, false end
        return info.startTime or 0,
               info.duration  or 0,
               info.isEnabled ~= false,
               info.modRate   or 1,
               info.isActive  == true
    end
    -- Pre-12.0 fallback: no secret values, no isActive field — derive it
    -- from duration after confirming the value is plain.
    if _G.GetSpellCooldown then
        local s, d, e, m = _G.GetSpellCooldown(spellID)
        local active = false
        if d and not (issecretvalue and issecretvalue(d)) then
            active = d > 0
        end
        return s or 0, d or 0, e ~= false, m or 1, active
    end
    return 0, 0, false, 1, false
end

--- Secret-safe cooldown handle for a spell.
-- @param spellID number
-- @return CooldownDuration|nil  An opaque duration object as returned by
--   C_Spell.GetSpellCooldownDuration. Useful methods:
--     :GetRemainingDuration()           — returns the seconds remaining.
--                                         **Plain number out of combat,
--                                         secret-tainted in combat.** Only
--                                         pass directly into a Blizzard C
--                                         method (FontString:SetFormattedText,
--                                         Cooldown:SetCooldownFromDurationObject
--                                         et al.) — never bind it to a Lua
--                                         local for compare / format /
--                                         tostring, or you'll get
--                                         "attempt to compare local
--                                         '...' (a secret number value)".
--     :EvaluateRemainingDuration(curve) — pass remaining through a numeric
--                                         or color curve; same caveat
--                                         applies to the result.
--     The object itself can be handed straight to
--     Cooldown:SetCooldownFromDurationObject for the radial swipe — that C
--     method handles the secret value internally.
--   Returns nil when the spell has no active cooldown (or the API is missing
--   on a pre-12.0 client).
--
-- This is the API to reach for whenever you need timing info for a watched
-- spell — it works for both interrupt-style protected spells (whose raw
-- start/duration come back as 12.0 "secret values" that error on any
-- arithmetic / comparison) and ordinary spells alike. See
-- FloatingInterruptHighlight's Core.lua for the canonical usage pattern.
function Compat.GetSpellCooldownDuration(spellID)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        return C_Spell.GetSpellCooldownDuration(spellID)
    end
    return nil
end

--- File ID of the spell's icon texture.
-- @param spellID number
-- @return number|nil  fileID suitable for Texture:SetTexture()
function Compat.GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    if _G.GetSpellTexture then
        return _G.GetSpellTexture(spellID)
    end
    return nil
end

--- Basic spell info.
-- @param spellID number
-- @return name, iconID, castTime, minRange, maxRange, spellID
function Compat.GetSpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(spellID)
        if i then
            return i.name, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID
        end
        return nil
    end
    if _G.GetSpellInfo then
        return _G.GetSpellInfo(spellID)
    end
    return nil
end

--- Charge info for a spell that has charges (Mind Freeze talents etc.).
-- @param spellID number
-- @return currentCharges, maxCharges, cooldownStartTime, cooldownDuration
--   Returns nil for spells without charges.
function Compat.GetSpellCharges(spellID)
    if C_Spell and C_Spell.GetSpellCharges then
        local c = C_Spell.GetSpellCharges(spellID)
        if c then
            return c.currentCharges, c.maxCharges,
                   c.cooldownStartTime, c.cooldownDuration
        end
        return nil
    end
    if _G.GetSpellCharges then
        return _G.GetSpellCharges(spellID)
    end
    return nil
end

--- Whether the spell is currently usable (resources / range / silence).
-- @param spellID number
-- @return usable (bool), noMana (bool)
function Compat.IsSpellUsable(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local r1, r2 = C_Spell.IsSpellUsable(spellID)
        -- Some Midnight builds return a SpellUsabilityInfo table,
        -- others return two booleans directly. Cover both.
        if type(r1) == "table" then
            return r1.usable == true, r1.noMana == true
        end
        return r1 == true, r2 == true
    end
    if _G.IsUsableSpell then
        local u, n = _G.IsUsableSpell(spellID)
        return u == true or u == 1, n == true or n == 1
    end
    return true, false
end

-- ---------------------------------------------------------------------------
-- Cast / channel info (target cast bar)
-- ---------------------------------------------------------------------------
--
-- 12.0 secret-value protection: UnitCastingInfo / UnitChannelInfo positions
-- 4-5 (startTimeMS / endTimeMS) come back tainted in combat for spells the
-- player can interrupt with a protected interrupt. C_Spell.GetSpellInfo's
-- ENTIRE return table is also secret-tainted in that scenario (every
-- field — castTime, iconID, ...). Doing arithmetic / comparison / format
-- on a secret raises a Lua error in tainted (addon) scope, and the usual
-- "detox" workarounds (tonumber, +0, securecallfunction) don't help.
--
-- Solution: never read the secret timestamps. Blizzard ships
-- UnitCastingDuration(unit) / UnitChannelDuration(unit) which return a
-- CastingDuration object whose :GetTotalDuration / :GetElapsedDuration /
-- :GetRemainingDuration / :GetStartTime / :GetEndTime methods all return
-- PLAIN numbers — safe to compare, format, and feed straight into
-- StatusBar:SetValue. This is the same trick UltimateCastbars uses and is
-- conceptually identical to the CooldownDuration object KickCD already
-- consumes in modules/Cooldowns.lua, EXCEPT the cast variant's
-- :GetRemainingDuration stays plain in combat (cooldown's goes secret —
-- they are different objects despite the similar shape).
--
-- We pull `name` / `texture` / `notInterruptible` / `spellID` straight
-- out of UnitCastingInfo without inspection. They may be secret-tainted
-- in combat, but the consumers we feed them to (Texture:SetTexture,
-- FontString:SetText, C_CurveUtil.EvaluateColorValueFromBoolean) accept
-- secret values without erroring — Blizzard's protection is on
-- arithmetic, not on UI rendering. Storing them as Lua locals is fine
-- as long as we never compare or format them ourselves.
--
-- Record shape:
--   { name, texture, spellID, notInterruptible, isChannel,
--     duration }                         -- CastingDuration object

local function buildCastRecord(name, texture, notInterruptible, spellID,
                               isChannel, duration)
    return {
        name             = name,
        texture          = texture,
        spellID          = spellID,
        notInterruptible = notInterruptible,  -- may be secret; only feed to
                                              -- C_CurveUtil, never compare
        isChannel        = isChannel and true or false,
        duration         = duration,          -- CastingDuration; methods
                                              -- return plain numbers
    }
end

-- The raw UnitCastingInfo.notInterruptible field reports whether the
-- spell is FLAGGED uninterruptible — i.e. whether spell-interrupt
-- mechanics work on it AT ALL (Counterspell, Mind Freeze, Polymorph
-- in PvP, ...). It does NOT consider the per-player practical
-- interruptibility: you can't interrupt a friendly cast, you can't
-- interrupt your own self-cast, regardless of the API flag.
--
-- For the cast bar's color logic, "I can interrupt this" is the
-- useful question, so we override notInterruptible to true (force
-- "uninterruptible" visuals) when the player can't attack the unit.
-- This catches mount casts on yourself, friendly NPC casts, etc.
-- For hostile units the raw API flag is returned unchanged.
local function effectiveNotInterruptible(unit, raw)
    if _G.UnitCanAttack and unit and not _G.UnitCanAttack("player", unit) then
        return true
    end
    return raw
end

--- Casting info for a unit, secret-value safe.
-- @param unit string ("target", "focus", ...)
-- @return record (table)|nil   nil when the unit isn't casting AND isn't channeling.
function Compat.GetCastingInfo(unit)
    if _G.UnitCastingInfo then
        local name, _, texture, _, _, _, _, notInterruptible, spellID =
            _G.UnitCastingInfo(unit)
        if name then
            local duration = _G.UnitCastingDuration and _G.UnitCastingDuration(unit) or nil
            return buildCastRecord(
                name, texture, effectiveNotInterruptible(unit, notInterruptible),
                spellID, false, duration)
        end
    end
    return Compat.GetChannelInfo(unit)
end

--- Whether the named unit is currently casting (or channeling) a spell
--- the player can practically interrupt. Used by the addon-wide
--- visibility mode "target_casting_interruptible" — see modules/IconGrid
--- and modules/Castbar — to gate the UI on actually-interruptible casts.
---
--- Secret-value handling: notInterruptible may be secret-tainted in
--- combat for casts that the player has a protected interrupt against
--- (Mind Freeze / Pummel / Kick / ...). Per the 12.0 protection rules
--- this taint only happens for casts the protected interrupt CAN target,
--- which means the cast IS interruptible from the user's perspective.
--- So when the value is secret we conservatively return true rather
--- than risking a Lua compare on a secret. issecretvalue() itself is
--- a safe query (does not error on secrets).
---
--- Friendly targets always return false (you can't interrupt a friendly
--- cast or a self-cast, regardless of the API flag).
function Compat.IsCastingInterruptible(unit)
    if not (unit and _G.UnitExists and _G.UnitExists(unit)) then return false end
    if _G.UnitCanAttack and not _G.UnitCanAttack("player", unit) then return false end

    local nint, hasCast
    if _G.UnitCastingInfo then
        local castName, _, _, _, _, _, _, n = _G.UnitCastingInfo(unit)
        if castName then hasCast, nint = true, n end
    end
    if not hasCast and _G.UnitChannelInfo then
        local chName, _, _, _, _, _, n = _G.UnitChannelInfo(unit)
        if chName then hasCast, nint = true, n end
    end
    if not hasCast then return false end

    if issecretvalue and issecretvalue(nint) then return true end
    return not nint
end

--- Channel info for a unit, secret-value safe. Same record shape as the
--- cast variant. Channels run total → 0 (full to empty); the consumer
--- chooses elapsed-vs-remaining for the bar value.
function Compat.GetChannelInfo(unit)
    if not _G.UnitChannelInfo then return nil end
    -- UnitChannelInfo's signature is one position shorter than
    -- UnitCastingInfo: there's no isTradeSkill at position 6, so
    -- notInterruptible lands at 7 (not 8) and spellID at 8 (not 9).
    local name, _, texture, _, _, _, notInterruptible, spellID =
        _G.UnitChannelInfo(unit)
    if not name then return nil end
    local duration = _G.UnitChannelDuration and _G.UnitChannelDuration(unit) or nil
    return buildCastRecord(
        name, texture, effectiveNotInterruptible(unit, notInterruptible),
        spellID, true, duration)
end

-- ---------------------------------------------------------------------------
-- Settings.RegisterAddOnSetting shim
-- ---------------------------------------------------------------------------
--
-- The signature of Settings.RegisterAddOnSetting has shifted across
-- 10.0 → 10.2 → 11.0 → 12.0. Blizzard's modern (12.0+) form is:
--
--   (category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--
-- where variableTbl must be a real table that Blizzard reads/writes via
-- variableTbl[variableKey], and `name` is the display label shown in the
-- panel. KickCD's authoritative store is db.profile, so we hand the API
-- a per-call scratch table seeded with the current value;
-- SetValueChangedCallback (Panel.lua) mirrors live edits back into db.profile.
--
-- Older shapes attempted as fallbacks:
--
--   (variable, name, table, type, defaultValue)                      -- 10.0
--   (category, name, variable, table, type, defaultValue)            -- 11.0
--
-- The shim tries the newest form first and falls back on pcall failure.

--- Register an addon setting in the Blizzard Settings panel.
-- @param category    Settings category object (from Settings.RegisterVerticalLayoutCategory)
-- @param variable    Unique string identifier ("KickCD_iconSize" etc.)
-- @param name        Display name (localized)
-- @param defaultValue Default value (boolean / number / string)
-- @param varType     Settings.VarType.* constant
-- @return Setting object (or nil on hard failure)
function Compat.RegisterAddOnSetting(category, variable, name, defaultValue, varType)
    if not (Settings and Settings.RegisterAddOnSetting) then
        return nil
    end

    -- Per-call scratch table. Blizzard writes to scratch[variable] when the
    -- user changes the setting; SetValueChangedCallback in Panel.lua mirrors
    -- those writes into db.profile. Pre-seeded with the current value so
    -- the panel reflects state correctly on open.
    local scratch = { [variable] = defaultValue }

    -- 1) Modern 12.0+ signature:
    --    (category, variable, variableKey, variableTbl, variableType, name, defaultValue)
    local ok, setting = pcall(Settings.RegisterAddOnSetting,
        category, variable, variable, scratch, varType, name, defaultValue)
    if ok and setting then return setting end

    -- 2) 11.0 signature:
    --    (category, name, variable, variableTbl, variableType, defaultValue)
    ok, setting = pcall(Settings.RegisterAddOnSetting,
        category, name, variable, scratch, varType, defaultValue)
    if ok and setting then return setting end

    -- 3) 10.0 signature:
    --    (variable, name, variableTbl, varType, defaultValue)
    ok, setting = pcall(Settings.RegisterAddOnSetting,
        variable, name, scratch, varType, defaultValue)
    if ok and setting then return setting end

    -- All forms exhausted; surface a one-time warning so the user can
    -- report it but don't crash the addon.
    if not Compat._registerWarned then
        Compat._registerWarned = true
        local err = tostring(setting)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ff00KickCD|r: Settings.RegisterAddOnSetting failed for '"
                .. tostring(variable) .. "' — " .. err)
        end
    end
    return nil
end
