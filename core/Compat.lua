-- core/Compat.lua
-- See docs/compat-layer.md and docs/midnight-quirks.md.
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
local addonName, NS = ...

local Compat = {}
NS.Compat = Compat

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Return only the FIRST return of `fn(...)` (or `nil` if `fn` is missing).
---
--- Used to collapse the multi-return of WoW APIs like `UnitCastingInfo` /
--- `UnitChannelInfo` to just their `name` slot for a truthy check. The
--- previous idiom was `(_G.UnitCastingInfo(unit))` — the extra parens
--- collapse the multi-return to a single value, but read as defensive
--- boilerplate that begs explanation. `Compat._firstReturn(fn, ...)`
--- makes the intent explicit at the call site.
---
--- Truthiness on the resulting value is always safe — `if x then` doesn't
--- perform arithmetic, so a secret-tainted name passes through unchanged.
--- Callers that want the actual value should still go through the full
--- API (this helper only exposes position 1).
---
--- @param fn function|nil  the API to call (may be nil on older clients)
--- @return any  fn's first return value, or nil when fn is missing
function Compat._firstReturn(fn, ...)
    if not fn then return nil end
    return (fn(...))
end

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
    if _G.C_Spell and _G.C_Spell.GetSpellCooldown then
        local info = _G.C_Spell.GetSpellCooldown(spellID)
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
        if d and not (_G.issecretvalue and _G.issecretvalue(d)) then
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
--   Returns nil only when the API is missing (pre-12.0 client).
--
--   It does NOT return nil for a spell that is off cooldown — measured on
--   12.0.7, an idle spell yields a live but ZEROED object (GetTotalDuration
--   0, IsActive false, HasExpired true). So a non-nil handle is not a
--   "this spell is on cooldown" signal. Gate on the plain `isActive` from
--   Compat.GetSpellCooldown instead (what Cooldowns:PollSpell does, which is
--   why it only fetches the handle once isActive is already true).
--
--   Every getter on the returned object EXCEPT HasSecretValues() is
--   secret-tainted in combat — including the booleans, which therefore
--   cannot be branched on. See docs/midnight-quirks.md for the measured
--   table.
--
-- This is the API to reach for whenever you need timing info for a watched
-- spell — it works for both interrupt-style protected spells (whose raw
-- start/duration come back as 12.0 "secret values" that error on any
-- arithmetic / comparison) and ordinary spells alike.
function Compat.GetSpellCooldownDuration(spellID)
    if _G.C_Spell and _G.C_Spell.GetSpellCooldownDuration then
        return _G.C_Spell.GetSpellCooldownDuration(spellID)
    end
    return nil
end

--- File ID of the spell's icon texture.
-- @param spellID number
-- @return number|nil  fileID suitable for Texture:SetTexture()
function Compat.GetSpellTexture(spellID)
    if _G.C_Spell and _G.C_Spell.GetSpellTexture then
        return _G.C_Spell.GetSpellTexture(spellID)
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
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local i = _G.C_Spell.GetSpellInfo(spellID)
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
    if _G.C_Spell and _G.C_Spell.GetSpellCharges then
        local c = _G.C_Spell.GetSpellCharges(spellID)
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

--- Whether the spell is actually accessible to the player right now.
-- Distinguishes "known to the spell DB" (which `GetSpellInfo` answers) from
-- "the player can currently cast this" (which is what we want for the icon
-- grid — choice-node siblings like Gorefiend's Grasp / Abomination Limb
-- must NOT both render when only one is picked).
--
-- IsPlayerSpell covers the vast majority of cases including talent choice
-- nodes (only the chosen branch returns true). IsSpellKnown(id) is checked
-- as a fallback for spells that show up in the player's spellbook but not
-- via IsPlayerSpell (some racials, profession spells). IsSpellKnown(id, true)
-- catches pet spells used as default cast-stoppers — Counter Shot (147362),
-- Spell Lock (19647), Optical Blast (119910) — which only appear when the
-- right pet is summoned. That last branch correctly hides pet spells while
-- the relevant pet isn't out, which matches "show only what's available
-- right now."
-- @param spellID number
-- @return bool
function Compat.IsSpellAvailable(spellID)
    if type(spellID) ~= "number" then return false end
    if _G.IsPlayerSpell and _G.IsPlayerSpell(spellID) then return true end
    if _G.IsSpellKnown then
        if _G.IsSpellKnown(spellID) then return true end
        if _G.IsSpellKnown(spellID, true) then return true end
    end
    return false
end

--- Whether the spell is currently usable (resources / range / silence).
-- @param spellID number
-- @return usable (bool), noMana (bool)
function Compat.IsSpellUsable(spellID)
    if _G.C_Spell and _G.C_Spell.IsSpellUsable then
        local r1, r2 = _G.C_Spell.IsSpellUsable(spellID)
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
-- Specialization APIs
-- ---------------------------------------------------------------------------
--
-- 12.0 (Midnight) moved the specialization query behind the C_SpecializationInfo
-- namespace; the bare globals GetSpecialization / GetSpecializationInfo are the
-- deprecated pre-11.x seam. Route every caller through Compat so feature modules
-- never touch the deprecated globals directly (§11). Signatures are preserved:
-- GetSpecialization returns the active spec INDEX; GetSpecializationInfo(index)
-- returns (id, localisedName, description, iconID, role, ...).

--- Active specialization index (or nil if unavailable).
-- @return number|nil
function Compat.GetSpecialization()
    if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecialization then
        return _G.C_SpecializationInfo.GetSpecialization()
    end
    return _G.GetSpecialization and _G.GetSpecialization()
end

--- Specialization info for a spec index. Multi-return passthrough of the
--- underlying API (id, localisedName, description, iconID, role, ...).
-- @param index number
function Compat.GetSpecializationInfo(index)
    if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecializationInfo then
        return _G.C_SpecializationInfo.GetSpecializationInfo(index)
    end
    if _G.GetSpecializationInfo then return _G.GetSpecializationInfo(index) end
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
-- StatusBar:SetValue. Conceptually identical to the CooldownDuration
-- object KickCD already consumes in modules/Cooldowns.lua, EXCEPT the
-- cast variant's
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

-- The "is this unit's cast one I should react to" feature decision used
-- to live here as Compat.IsHostileUnitCasting / Compat.ApplyInterruptibleAlpha.
-- Both are NOT API-shape normalisation — they encode the addon's shared
-- visibility / glow gating policy and are now owned by core/State.lua
-- (KickCD.State.IsHostileUnitCasting / KickCD.State.ApplyInterruptibleAlpha).
-- Compat keeps the raw GetCastingInfo / GetChannelInfo shims above; reach
-- for State.* when you need the feature decision.

--- Print a verbose diagnostic dump of the unit's cast state. Wired to
--- `/kcd debug interrupt` — used to verify whether `notInterruptible`
--- is in fact coming back secret-tainted in the user's 12.0 client
--- (the root cause of the "uninterruptible cast still shows" bug
--- before the alpha-mask refactor).
---
--- Every value pulled from a `Unit*` API is funnelled through
--- `safeRender` first because in combat *any* string field
--- (name, displayName, texture, even UnitName) can come back
--- secret-tainted. tostring/format on a secret propagate the taint
--- and table.concat on the resulting string then errors out — that's
--- why a naive "tostring(name)" inside :format() blew up combat.
function Compat.DebugInterrupt(unit)
    local out = (NS.Util and NS.Util.print) or _G.print
    unit = unit or "target"

    -- Stringify a value safely in tainted scope: secret → "<secret>",
    -- otherwise the usual tostring (or "%q" for strings to quote them).
    local function safeRender(value)
        if _G.issecretvalue and _G.issecretvalue(value) then
            return "<secret>"
        end
        local t = type(value)
        if t == "string"  then return ("%q"):format(value) end
        if t == "number"  then return tostring(value) end
        if t == "boolean" then return tostring(value) end
        if t == "nil"     then return "nil" end
        return "<" .. t .. ">"
    end

    if not (_G.UnitExists and _G.UnitExists(unit)) then
        out("DebugInterrupt: unit '" .. unit .. "' does not exist")
        return
    end

    local rawName  = _G.UnitName and _G.UnitName(unit)
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", unit) or false
    out(("DebugInterrupt: unit=%s name=%s canAttack=%s"):format(
        unit, safeRender(rawName), tostring(canAttack)))

    local function describe(label, value)
        local t = type(value)
        local secret = _G.issecretvalue and _G.issecretvalue(value) or false
        out(("  %-20s type=%-8s isSecret=%-5s value=%s"):format(
            label, t, tostring(secret), safeRender(value)))
    end

    if _G.UnitCastingInfo then
        local castName, displayName, texture, startMS, endMS, isTradeSkill,
              castID, notInterruptible, spellID = _G.UnitCastingInfo(unit)
        if castName then
            out("UnitCastingInfo positions")
            describe("1 name",             castName)
            describe("2 displayName",      displayName)
            describe("3 texture",          texture)
            describe("4 startTimeMS",      startMS)
            describe("5 endTimeMS",        endMS)
            describe("6 isTradeSkill",     isTradeSkill)
            describe("7 castID",           castID)
            describe("8 notInterruptible", notInterruptible)
            describe("9 spellID",          spellID)
        else
            out("UnitCastingInfo: not casting")
        end
    end

    if _G.UnitChannelInfo then
        local chName, displayName, texture, startMS, endMS, isTradeSkill,
              notInterruptible, spellID = _G.UnitChannelInfo(unit)
        if chName then
            out("UnitChannelInfo positions")
            describe("1 name",             chName)
            describe("2 displayName",      displayName)
            describe("3 texture",          texture)
            describe("4 startTimeMS",      startMS)
            describe("5 endTimeMS",        endMS)
            describe("6 isTradeSkill",     isTradeSkill)
            describe("7 notInterruptible", notInterruptible)
            describe("8 spellID",          spellID)
        else
            out("UnitChannelInfo: not channeling")
        end
    end

    out(("State.IsHostileUnitCasting(%s) = %s"):format(
        unit, tostring(NS.State.IsHostileUnitCasting(unit))))

    -- Report what the addon-wide visibility / glow logic decided. The
    -- visibility mode is the addon-wide setting; per-icon glow triggers
    -- live in units.<unit>.icons.{primary,secondary}GlowTrigger.
    local profile = NS.db and NS.db.profile
    local mode = (profile and profile.visibility) or "always"
    out(("addon visibility mode = %s"):format(tostring(mode)))
    local icons = (NS.Units and NS.Units.Icons and NS.Units.Icons(unit)) or {}
    out(("primary glow trigger   = %s"):format(tostring(icons.primaryGlowTrigger)))
    out(("secondary glow trigger = %s"):format(tostring(icons.secondaryGlowTrigger)))
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
