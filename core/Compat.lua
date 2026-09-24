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
local _, NS = ...

local Compat = {}
NS.Compat = Compat

-- LibKa0s-Compat-1.0 carries the readers two or more Ka0s addons wrote the same way, and the
-- secret-value seam. The members it owns are ROUTED through it below; everything else in this
-- file is KickCD's own and stays hand-written. Call sites keep calling NS.Compat.X either way, so
-- a test that swaps a member on NS.Compat still reaches every caller.
--
-- Library absent (a partial copy; the whole-payload case is announced by core/CoreSetup.lua):
--   * a READER answers the major's documented absent value -- nil, or 0, 0, false, 1, false --
--     and calls no client API (LibKa0s docs/api/Compat/version-1-docs.md, "Degradation");
--   * the GUARD re-implements its one-rung body, because "the library is absent" is not "the
--     client has no secrets system": answering "not secret" on a 12.x client would send a secret
--     into a comparison on exactly the degraded path.
local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)

-- ---------------------------------------------------------------------------
-- The secret-value seam
-- ---------------------------------------------------------------------------

--- Whether `v` is a 12.0 secret value: a strict boolean, false on a client that
--- has no secrets system. The ONE place this addon asks the question -- feature
--- modules call NS.Compat.IsSecret rather than reading `issecretvalue` themselves.
-- Guard stub: deliberate, documented duplication of the library's one-rung body.
-- See LibKa0s docs/api/Compat/version-1-docs.md, "Degradation".
Compat.IsSecret = CompatLib and CompatLib.IsSecret or function(v)
    local fn = _G.issecretvalue
    if not fn then return false end
    return fn(v) and true or false
end

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

--- Cooldown info for a spell. LibKa0s-Compat-1.0's member: C_Spell.GetSpellCooldown,
--- authoritative where it exists, then the pre-12.0 global with isActive derived from
--- a plain duration (and a legacy isEnabled of 0 read as disabled).
-- @param spellID number
-- @return startTime, duration, isEnabled, modRate, isActive -- always five values
--   On error / no cooldown: 0, 0, false, 1, false
--   startTime/duration/modRate may be "secret" — never compare or do
--   arithmetic on them in tainted scope; pass them straight to C-side APIs
--   (Cooldown:SetCooldown) or gate with Compat.IsSecret first.
Compat.GetSpellCooldown = CompatLib and CompatLib.GetSpellCooldown
    or function() return 0, 0, false, 1, false end

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
--     :EvaluateTotalDuration(curve)     — same, but against the cooldown's
--                                         TOTAL length. This is the one that
--                                         separates a GCD lockout from a real
--                                         cooldown, since the two are
--                                         indistinguishable by remaining time
--                                         once the real one nears its end.
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

--- File ID of the spell's icon texture. LibKa0s-Compat-1.0's member: exactly one
--- value (the client's second return, the original icon, is dropped).
-- @param spellID number|string
-- @return number|nil  fileID suitable for Texture:SetTexture()
Compat.GetSpellTexture = CompatLib and CompatLib.GetSpellTexture
    or function() return nil end

--- Basic spell info. LibKa0s-Compat-1.0's member: C_Spell.GetSpellInfo flattened and
--- authoritative, else the legacy global remapped from its real shape (rank dropped).
--- A typed NAME resolves too -- settings/Spells.lua and core/KickCD.lua read the
--- spellID off position 6.
-- @param spellID number|string
-- @return name, iconID, castTime, minRange, maxRange, spellID -- or a single nil
Compat.GetSpellInfo = CompatLib and CompatLib.GetSpellInfo
    or function() return nil end

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
-- never touch the deprecated globals directly (§11). Both members are
-- LibKa0s-Compat-1.0's: GetSpecialization returns the active spec INDEX;
-- GetSpecializationInfo(index) returns (id, localizedName, description, iconID,
-- role, ...), and answers nil for a nil index without calling the client.

--- Active specialization index (or nil if unavailable). Exactly one value.
-- @return number|nil
Compat.GetSpecialization = CompatLib and CompatLib.GetSpecialization
    or function() return nil end

--- Specialization info for a spec index. Multi-return passthrough of the
--- underlying API (id, localizedName, description, iconID, role, ...).
-- @param index number
Compat.GetSpecializationInfo = CompatLib and CompatLib.GetSpecializationInfo
    or function() return nil end

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
-- Both are NOT API-shape normalization — they encode the addon's shared
-- visibility / glow gating policy and are now owned by core/State.lua
-- (KickCD.State.IsHostileUnitCasting / KickCD.State.ApplyInterruptibleAlpha).
-- Compat keeps the raw GetCastingInfo / GetChannelInfo shims above; reach
-- for State.* when you need the feature decision.

-- ── /kcd debug interrupt ────────────────────────────────────────────────────

-- Renderers by Lua type, so safeRender below is one lookup instead of a
-- ladder. Every entry is total: none of them can raise on the value it is
-- reached for.
local RENDER_BY_TYPE = {
    string  = function(v) return ("%q"):format(v) end,
    number  = tostring,
    boolean = tostring,
    ["nil"] = function() return "nil" end,
}

-- Stringify a value safely in tainted scope: secret → "<secret>",
-- otherwise the usual tostring (or "%q" for strings to quote them).
local function safeRender(value)
    if Compat.IsSecret(value) then
        return "<secret>"
    end
    local t = type(value)
    local render = RENDER_BY_TYPE[t]
    if render then return render(value) end
    return "<" .. t .. ">"
end

-- One annotated line per reported value. The column widths are what make a
-- pasted dump line up and diff cleanly against another user's — leave them be.
local function describe(out, label, value)
    local t = type(value)
    local secret = Compat.IsSecret(value)
    out(("  %-20s type=%-8s isSecret=%-5s value=%s"):format(
        label, t, tostring(secret), safeRender(value)))
end

-- Position labels for the two cast APIs — the only difference between the two
-- dumps. UnitChannelInfo's signature is one position shorter than
-- UnitCastingInfo's: there is no isTradeSkill at 6, so notInterruptible lands
-- at 7 (not 8) and spellID at 8 (not 9). The numbering is spelled out rather
-- than derived because it is exactly what the reader diffs against.
local CASTING_FIELDS = {
    "1 name", "2 displayName", "3 texture", "4 startTimeMS", "5 endTimeMS",
    "6 isTradeSkill", "7 castID", "8 notInterruptible", "9 spellID",
}
local CHANNEL_FIELDS = {
    "1 name", "2 displayName", "3 texture", "4 startTimeMS", "5 endTimeMS",
    "6 isTradeSkill", "7 notInterruptible", "8 spellID",
}

-- Dump one API's return positions, or the idle line when nothing is in
-- progress. The varargs are the API's RAW returns: they are never concatenated
-- or formatted here, only handed one at a time to describe/safeRender.
local function dumpPositions(out, title, idle, fields, ...)
    local first = select(1, ...)
    if not first then
        out(title .. ": " .. idle)
        return
    end
    out(title .. " positions")
    for i = 1, #fields do
        describe(out, fields[i], (select(i, ...)))
    end
end

-- Report what the addon-wide visibility / glow logic decided. The visibility
-- mode is the addon-wide setting; per-icon glow triggers live in
-- units.<unit>.icons.{primary,secondary}GlowTrigger.
local function dumpVisibilityGate(out, unit)
    local profile = NS.db and NS.db.profile
    local mode = (profile and profile.visibility) or "always"
    out(("addon visibility mode = %s"):format(tostring(mode)))
    local icons = (NS.Units and NS.Units.Icons and NS.Units.Icons(unit)) or {}
    out(("primary glow trigger   = %s"):format(tostring(icons.primaryGlowTrigger)))
    out(("secondary glow trigger = %s"):format(tostring(icons.secondaryGlowTrigger)))
end

--- Print a verbose diagnostic dump of the unit's cast state. Wired to
--- `/kcd debug interrupt` — used to verify whether `notInterruptible`
--- is in fact coming back secret-tainted in the user's 12.0 client
--- (the root cause of the "uninterruptible cast still shows" bug
--- before the alpha-mask refactor).
---
--- Every value pulled from a `Unit*` API is funneled through
--- `safeRender` first because in combat *any* string field
--- (name, displayName, texture, even UnitName) can come back
--- secret-tainted. tostring/format on a secret propagate the taint
--- and table.concat on the resulting string then errors out — that's
--- why a naive "tostring(name)" inside :format() blew up combat.
function Compat.DebugInterrupt(unit)
    local out = NS.Util.print
    unit = unit or "target"

    if not (_G.UnitExists and _G.UnitExists(unit)) then
        out("DebugInterrupt: unit '" .. unit .. "' does not exist")
        return
    end

    local rawName  = _G.UnitName and _G.UnitName(unit)
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", unit) or false
    out(("DebugInterrupt: unit=%s name=%s canAttack=%s"):format(
        unit, safeRender(rawName), tostring(canAttack)))

    if _G.UnitCastingInfo then
        dumpPositions(out, "UnitCastingInfo", "not casting", CASTING_FIELDS,
            _G.UnitCastingInfo(unit))
    end

    if _G.UnitChannelInfo then
        dumpPositions(out, "UnitChannelInfo", "not channeling", CHANNEL_FIELDS,
            _G.UnitChannelInfo(unit))
    end

    out(("State.IsHostileUnitCasting(%s) = %s"):format(
        unit, tostring(NS.State.IsHostileUnitCasting(unit))))

    dumpVisibilityGate(out, unit)
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
