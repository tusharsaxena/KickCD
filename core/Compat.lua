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

--- Cooldown info for a spell.
-- @param spellID number
-- @return startTime, duration, isEnabled, modRate
--   On error / no cooldown: 0, 0, false, 1
function Compat.GetSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime or 0,
                   info.duration or 0,
                   info.isEnabled ~= false,
                   info.modRate or 1
        end
        return 0, 0, false, 1
    end
    -- Pre-10.2.5 fallback (unlikely on Midnight, but cheap insurance)
    if _G.GetSpellCooldown then
        local s, d, e, m = _G.GetSpellCooldown(spellID)
        return s or 0, d or 0, e ~= false, m or 1
    end
    return 0, 0, false, 1
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
-- Settings.RegisterAddOnSetting shim
-- ---------------------------------------------------------------------------
--
-- The signature of Settings.RegisterAddOnSetting has shifted across
-- 10.0 → 10.2 → 11.0 → 12.0. Blizzard's modern (12.0+) form is:
--
--   (category, variable, variableKey, variableTbl, variableType, defaultValue)
--
-- where variableTbl must be a real table that Blizzard reads/writes via
-- variableTbl[variableKey]. KickCD's authoritative store is db.profile,
-- so we hand the API a per-call scratch table seeded with the current
-- value; SetValueChangedCallback (Panel.lua) mirrors live edits back into
-- db.profile.
--
-- Older shapes still attempted as fallbacks:
--
--   (variable, name, table, type, defaultValue)                      -- 10.0
--   (category, variable, variableKey, table, type, name, default)    -- 10.2
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
    --    (category, variable, variableKey, variableTbl, variableType, defaultValue)
    local ok, setting = pcall(Settings.RegisterAddOnSetting,
        category, variable, variable, scratch, varType, defaultValue)
    if ok and setting then return setting end

    -- 2) 11.0 signature:
    --    (category, name, variable, variableTbl, variableType, defaultValue)
    ok, setting = pcall(Settings.RegisterAddOnSetting,
        category, name, variable, scratch, varType, defaultValue)
    if ok and setting then return setting end

    -- 3) 10.2 signature:
    --    (category, variable, variableKey, variableTbl, varType, name, default)
    ok, setting = pcall(Settings.RegisterAddOnSetting,
        category, variable, variable, scratch, varType, name, defaultValue)
    if ok and setting then return setting end

    -- 4) 10.0 signature:
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
