-- core/State.lua
--
-- Tiny shared "live state" namespace. Owns process-global flags that
-- multiple modules need to read identically (today: combat state).
-- This file's bootstrap listener owns the PLAYER_REGEN_* registration
-- and the flag write, then fans out Ka0s_KickCD_CombatState so subscribers
-- (IconGrid, Castbar) see an explicit ordered transition signal. They
-- NEVER mutate the flag — this is the only writer.
--
-- Why a separate file (not a slot in core/Util.lua):
--   * Util.lua is a pile of dependency-free helpers; State.lua owns
--     the addon's combat listener (an AceEvent target armed from
--     NS:OnInitialize). Keeping it isolated makes that side effect
--     reviewable in one place.
--   * Future shared state (e.g. an addon-wide "hostile target casting"
--     flag, or per-spec resolved class/spec keys) lives here too.
--
-- Loaded in the TOC right after core/Constants.lua and before
-- core/Util.lua so any helper / module that loads later can read
-- KickCD.State.* without an existence check.

local _, NS = ...

-- `debug` is the session-only debug-logging flag (debug-logging-§5). It defaults OFF,
-- is NEVER persisted to SavedVariables, and resets to off on every /reload
-- and fresh login (a fresh addon load re-runs this file, re-seeding false).
-- The ONLY write path is KickCD.DebugLog:SetEnabled — modules read
-- KickCD.State.debug (via the KickCD.Debug sink) but never mutate it.
-- `viewedUnit` is which unit the three per-unit settings pages (Icons, Cast bar,
-- Text label) are currently editing. ONE value across all three, so flipping the
-- picker on Icons and walking to Cast bar arrives on the same unit rather than
-- back on Target -- the pages edit one addon and the picker names which half of
-- it, which is not a fact each page should hold separately.
--
-- SESSION-ONLY, deliberately, and NOT a SavedVariable: it is where the reader
-- happens to be looking, not something they configured. Persisting it would mean
-- a fresh login opening on whichever unit was selected weeks ago, with nothing on
-- screen explaining why. Re-seeded to "target" by this file on every load.
--
-- `rejectedEvents` is every event name this client refused to register this
-- session (events-frames-taint-§1), in the order first refused, each once. It is
-- the caller-owned list core/CoreSetup.lua's NS.RegisterEventList hands to
-- LibKa0s-Core's SafeRegisterEvent. SESSION-ONLY for the same reason as `debug`:
-- a refusal is a fact about this client build, so a fresh load asks again.
-- Read by `/kcd debug events` and counted in the [Init] summary.
local State = { inCombat = false, debug = false, viewedUnit = "target", rejectedEvents = {} }
NS.State = State

--- Set the live combat flag. Called only from the bootstrap event
--- listener below; modules read State.inCombat but never mutate it.
function State.SetInCombat(v)
    State.inCombat = v and true or false
end

-- ---------------------------------------------------------------------------
-- Visibility helpers (hostile-cast gate + interruptibility alpha mask)
-- ---------------------------------------------------------------------------
--
-- These two helpers used to live in core/Compat.lua, but their job isn't
-- API normalization — it's the addon's shared "is this unit's cast one
-- the player can interrupt" feature decision, used identically by the
-- icon grid (visibility + glow gating) and the cast bar (visibility +
-- alpha mask). Compat keeps the raw GetCastingInfo / GetChannelInfo
-- shims; State owns the feature decision.
--
-- The 12.0 secret-value strategy is identical in both helpers:
--   * Truthiness checks on the API's `name` return are safe (Lua's
--     `if x then` does not perform arithmetic, so a secret-tainted
--     name passes through unchanged).
--   * `notInterruptible` (positions 8 / 7 of UnitCastingInfo /
--     UnitChannelInfo) is secret-tainted in combat for protected casts;
--     it MUST go straight into Frame:SetAlphaFromBoolean — the one
--     C-side method that accepts the secret form without erroring.
-- See docs/midnight-quirks.md "Cast interruptibility" for the
-- full background.

--- Whether `unit` is currently casting (or channeling) AND is a unit
--- the player can attack. Used as the visibility GATE for the
--- "target_casting_interruptible" mode — actual interruptibility is
--- filtered separately via State.ApplyInterruptibleAlpha because
--- notInterruptible is secret-tainted in 12.0 and cannot be compared
--- in Lua. (Friendly / self casts are excluded here because you can't
--- interrupt those regardless of the API flag.)
---
--- Truthiness checks on the API's `name` return are safe even when the
--- value is secret-tainted in combat — `if x then` does not perform
--- arithmetic. Compat._firstReturn collapses the multi-return to
--- position 1 so the truthy check is on a single value.
function State.IsHostileUnitCasting(unit)
    if not (unit and _G.UnitExists and _G.UnitExists(unit)) then return false end
    if _G.UnitCanAttack and not _G.UnitCanAttack("player", unit) then return false end
    local Compat = NS.Compat
    if Compat and Compat._firstReturn(_G.UnitCastingInfo, unit) then return true end
    if Compat and Compat._firstReturn(_G.UnitChannelInfo, unit) then return true end
    return false
end

--- Drive `frame`'s alpha from the unit's cast `notInterruptible` flag.
--- When the cast is interruptible (notInterruptible falsy) → frame
--- shows at `alpha`. When uninterruptible (notInterruptible truthy)
--- → frame hides (alpha 0). When the unit has no cast or is friendly
--- the function returns false WITHOUT touching the frame so the caller
--- can fall back to its own alpha policy.
---
--- The flag is fed straight into Frame:SetAlphaFromBoolean — a C-side
--- method that accepts the 12.0 "secret value" form of notInterruptible
--- without erroring. THIS IS THE ONLY 12.0-correct way to gate
--- visibility on interruptibility from an addon: any Lua-side compare
--- (`not nint`, `nint == true`, `if nint`) errors when the value is
--- secret-tainted.
---
--- @param frame Frame  must support :SetAlphaFromBoolean
--- @param unit  string ("target", ...)
--- @param alpha number alpha to use when interruptible (default 1)
--- @return bool whether the mask was applied
function State.ApplyInterruptibleAlpha(frame, unit, alpha)
    if not (frame and frame.SetAlphaFromBoolean) then return false end
    if not (unit and _G.UnitExists and _G.UnitExists(unit)) then return false end
    if _G.UnitCanAttack and not _G.UnitCanAttack("player", unit) then return false end

    local notInterruptible, hasCast
    if _G.UnitCastingInfo then
        local castName, _, _, _, _, _, _, n = _G.UnitCastingInfo(unit)
        if castName then notInterruptible, hasCast = n, true end
    end
    if not hasCast and _G.UnitChannelInfo then
        local chName, _, _, _, _, _, n = _G.UnitChannelInfo(unit)
        if chName then notInterruptible, hasCast = n, true end
    end
    if not hasCast then return false end

    -- C-side: accepts secret notInterruptible without arithmetic in Lua.
    frame:SetAlphaFromBoolean(notInterruptible, 0, alpha or 1)
    return true
end

-- ---------------------------------------------------------------------------
-- Bootstrap event listener
-- ---------------------------------------------------------------------------
--
-- One AceEvent target owns the canonical PLAYER_REGEN_* subscription.
-- We seed from InCombatLockdown() on PLAYER_LOGIN — at that moment
-- the lockdown state is reliable (the regen events haven't begun
-- racing yet). After login the flag is driven exclusively by the
-- regen events, NOT by InCombatLockdown(): reading InCombatLockdown()
-- inside the PLAYER_REGEN_DISABLED handler can return false (the
-- lockdown state lags the event by a frame) and would silently
-- corrupt the flag. The events are the source of truth.
--
-- AN ACEEVENT TARGET, NOT A FRAME (events-frames-taint-§1: no private frame
-- for ordinary event traffic). AceEvent is embedded directly rather than
-- through NS.NewBusTarget because that helper is defined in core/KickCD.lua,
-- which loads after this file. AceEvent-3.0 loads in the TOC's libs block
-- before core/ and is not part of LibKa0s, so it is present on a degraded load.
--
-- REGISTERED IN State.Arm, NOT AT FILE LOAD, because the registration goes
-- through NS.RegisterEventList (core/CoreSetup.lua, which also loads after this
-- file). NS:OnInitialize calls Arm; ADDON_LOADED always precedes PLAYER_LOGIN,
-- so the login seed is never missed.

local boot = {}
LibStub("AceEvent-3.0"):Embed(boot)

local function onBootEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        State.SetInCombat(true)
        if State.debug and NS and NS.Debug then NS.Debug("Combat", "entered") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        State.SetInCombat(false)
        if State.debug and NS and NS.Debug then NS.Debug("Combat", "left") end
    elseif event == "PLAYER_LOGIN" then
        State.SetInCombat(_G.InCombatLockdown and _G.InCombatLockdown() or false)
        -- PLAYER_LOGIN fires once per session; release it once the flag is
        -- seeded. The only one-shot PLAYER_LOGIN listener in the addon.
        boot:UnregisterEvent("PLAYER_LOGIN")
    end
    -- Fan out the freshly-written flag so subscribers (IconGrid,
    -- Castbar) see an explicit ordered transition signal instead of
    -- relying on registration order to ensure this listener ran before
    -- any module's. Guard documents the AceAddon-mixin race
    -- (KickCD has SendMessage by PLAYER_LOGIN time, but the guard makes
    -- the dependency explicit). See docs/message-bus.md.
    if NS and NS.SendMessage then
        NS:SendMessage(NS.MSG.COMBAT_STATE, { inCombat = State.inCombat })
    end
end

-- `{ event, handler }` rows for NS.RegisterEventList. FILE SCOPE so a stand-up
-- allocates nothing (anti-patterns #43).
local ARM_EVENTS = {
    { "PLAYER_LOGIN",          onBootEvent },
    { "PLAYER_REGEN_DISABLED", onBootEvent },
    { "PLAYER_REGEN_ENABLED",  onBootEvent },
}
local REGEN_EVENTS = {
    { "PLAYER_REGEN_DISABLED", onBootEvent },
    { "PLAYER_REGEN_ENABLED",  onBootEvent },
}

--- Register the listener for the session. Called once, from NS:OnInitialize.
function State.Arm()
    NS.RegisterEventList(boot, ARM_EVENTS)
end

-- ---------------------------------------------------------------------------
-- The bootstrap listener under the stand-down latch (slash-commands-§7)
-- ---------------------------------------------------------------------------
--
-- A disabled addon whose PLAYER_REGEN_* subscription still fired would still
-- enter Lua, still publish COMBAT_STATE onto a bus nobody is listening to, and
-- -- with debug on -- still print "entered" at a player who thinks the addon is
-- off. So the stand-down releases it: gone, not gated. §7 is explicit that a
-- handler which merely early-returns has not stopped watching, it has stopped
-- reacting, and it still pays the dispatch.
--
-- NOTHING IS HELD PENDING HERE. §7 permits a disabled addon to keep exactly one
-- registration -- a secure or attribute teardown that combat lockdown refused,
-- finished on PLAYER_REGEN_ENABLED. KickCD owns no secure frame, no attribute
-- driver and no state driver, so it has nothing to hold pending and keeps
-- nothing: the disabled registration set is EMPTY, and tests/test_disabled.lua
-- asserts that by count.

--- Release the bootstrap subscription. Called by the latch's standDown.
function State.StandDown()
    boot:UnregisterAllEvents()
end

--- Re-arm the regen pair, and re-seed the combat flag FROM CURRENT STATE rather
--- than from whatever it held when the addon went down: a fight can start and
--- finish while the addon is switched off, and the events that would have
--- corrected the flag were not being watched.
---
--- PLAYER_LOGIN is never re-registered. The first hold is taken in OnEnable,
--- which AceAddon runs from its own PLAYER_LOGIN handler, so no stand-up can
--- precede login: by the time one runs, PLAYER_LOGIN has fired and will not fire
--- again. The seed below is what the login branch was for.
function State.StandUp()
    NS.RegisterEventList(boot, REGEN_EVENTS)
    State.SetInCombat(_G.InCombatLockdown and _G.InCombatLockdown() or false)
end
