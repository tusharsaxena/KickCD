-- core/State.lua — KickCD v0.1
--
-- Tiny shared "live state" namespace. Owns process-global flags that
-- multiple modules need to read identically (today: combat state).
-- Modules subscribe to PLAYER_REGEN_* themselves for SIDE EFFECTS
-- (e.g. IconGrid:RefreshVisibility, Castbar:Reevaluate / :Stop), but
-- they NEVER mutate the flag — this file's bootstrap listener owns
-- that, so the flag stays in lockstep across modules by construction.
--
-- Why a separate file (not a slot in core/Util.lua):
--   * Util.lua is a pile of dependency-free helpers; State.lua owns
--     the only side-effect frame at module load (the bootstrap
--     CreateFrame). Keeping it isolated makes the side effect
--     reviewable in one place.
--   * Future shared state (e.g. an addon-wide "hostile target casting"
--     flag, or per-spec resolved class/spec keys) lives here too.
--
-- Loaded in the TOC right after core/Constants.lua and before
-- core/Util.lua so any helper / module that loads later can read
-- KickCD.State.* without an existence check.

KickCD = KickCD or {}

local State = { inCombat = false }
KickCD.State = State

--- Set the live combat flag. Called only from the bootstrap event
--- listener below; modules read State.inCombat but never mutate it.
function State.SetInCombat(v)
    State.inCombat = v and true or false
end

-- ---------------------------------------------------------------------------
-- Bootstrap event listener
-- ---------------------------------------------------------------------------
--
-- One unnamed frame owns the canonical PLAYER_REGEN_* subscription.
-- We seed from InCombatLockdown() on PLAYER_LOGIN — at that moment
-- the lockdown state is reliable (the regen events haven't begun
-- racing yet). After login the flag is driven exclusively by the
-- regen events, NOT by InCombatLockdown(): reading InCombatLockdown()
-- inside the PLAYER_REGEN_DISABLED handler can return false (the
-- lockdown state lags the event by a frame) and would silently
-- corrupt the flag. The events are the source of truth.

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_DISABLED")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        State.SetInCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        State.SetInCombat(false)
    elseif event == "PLAYER_LOGIN" then
        State.SetInCombat(InCombatLockdown and InCombatLockdown() or false)
    end
end)
