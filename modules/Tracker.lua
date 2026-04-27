-- modules/Tracker.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.4
--
-- Target + cast state machine. Sole authority on whether the icon grid /
-- castbar should be visible. Communicates outwards exclusively via the
-- closed message set in TECHNICAL_DESIGN §1:
--
--   KickCD_TARGET_CAST_START  { spellID, name, texture, startMS, endMS, isChannel, notInterruptible }
--   KickCD_TARGET_CAST_UPDATE { startMS, endMS, notInterruptible }
--   KickCD_TARGET_CAST_END    { reason }
--
-- States:
--   Hidden    — no UI shown
--   Showing   — a fresh interruptible cast is in progress
--
-- The "Evaluating" state in the design diagram is transient; we collapse it
-- into the Evaluate() call that decides Show vs Hide on every relevant
-- event.

local KickCD  = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Tracker = KickCD:NewModule("Tracker", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Every UNIT_SPELLCAST_* flavor we care about. Registered with
-- RegisterUnitEvent on a dedicated raw frame so the client only delivers
-- events for the player's current target — see RESEARCH §2.2 and §7.1.
local UNIT_CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

-- ---------------------------------------------------------------------------
-- Cast info helper (RESEARCH §2.1 idiom)
-- ---------------------------------------------------------------------------

--- Pull cast info for a unit, falling back from regular cast to channel.
-- @param unit string ("target")
-- @return table|nil  { spellID, name, texture, startMS, endMS, notInterruptible, isChannel }
local function GetCast(unit)
    local name, _, texture, startMS, endMS, _, _, notInterruptible, spellID =
        UnitCastingInfo(unit)
    if name then
        return {
            spellID          = spellID,
            name             = name,
            texture          = texture,
            startMS          = startMS,
            endMS            = endMS,
            notInterruptible = notInterruptible == true,
            isChannel        = false,
        }
    end
    -- UnitChannelInfo's tuple has notInterruptible at position 7 (no castID).
    name, _, texture, startMS, endMS, _, notInterruptible, spellID =
        UnitChannelInfo(unit)
    if name then
        return {
            spellID          = spellID,
            name             = name,
            texture          = texture,
            startMS          = startMS,
            endMS            = endMS,
            notInterruptible = notInterruptible == true,
            isChannel        = true,
        }
    end
    return nil
end

Tracker.GetCast = GetCast  -- exposed for tests / DebugDump

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Tracker:OnEnable()
    -- Internal state: are we currently showing a cast?
    self.shown        = false
    self.currentCast  = nil
    self.testMode     = false

    -- Dedicated raw frame for unit-filtered cast events. AceEvent's
    -- RegisterEvent is broadcast-only, but we want the client to deliver
    -- UNIT_SPELLCAST_* only when the unit happens to be "target". This
    -- frame outlives target switches because RegisterUnitEvent watches the
    -- token (see RESEARCH §2.2 — no need to re-register on
    -- PLAYER_TARGET_CHANGED).
    local f = CreateFrame("Frame", "KickCDTrackerCastFrame")
    self.castFrame = f
    for _, ev in ipairs(UNIT_CAST_EVENTS) do
        f:RegisterUnitEvent(ev, "target")
    end
    f:SetScript("OnEvent", function(_, event, unit, ...)
        self:OnCastEvent(event, unit, ...)
    end)

    -- Frame events that aren't unit-scoped — cheap on AceEvent.
    self:RegisterEvent("PLAYER_TARGET_CHANGED",  "OnTargetChanged")
    self:RegisterEvent("UNIT_FACTION",           "OnUnitFaction")

    -- Internal messages (closed list).
    self:RegisterMessage("KickCD_TEST_MODE",       "OnTestMode")
    self:RegisterMessage("KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("KickCD_CONFIG_CHANGED",  "OnConfigChanged")
end

function Tracker:OnDisable()
    if self.castFrame then
        self.castFrame:SetScript("OnEvent", nil)
        self.castFrame:UnregisterAllEvents()
    end
    if self.shown then
        self:Hide("stopped")
    end
end

-- ---------------------------------------------------------------------------
-- Event routing
-- ---------------------------------------------------------------------------

-- Events that, while we're already Showing, should only push an UPDATE
-- (delayed pushback, channel haste retick, shielded-state flip) — not a
-- full re-evaluate. A full re-evaluate would tear down + rebuild the UI
-- mid-cast which we explicitly want to avoid (TECHNICAL_DESIGN §3.4
-- "Throttling").
local UPDATE_ONLY_EVENTS = {
    UNIT_SPELLCAST_DELAYED            = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE     = true,
    UNIT_SPELLCAST_INTERRUPTIBLE      = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE  = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE     = true,
}

-- Events that unambiguously END a cast, regardless of evaluation result.
-- We map them to the appropriate hide reason without re-querying the API.
local END_EVENTS = {
    UNIT_SPELLCAST_STOP             = "stopped",
    UNIT_SPELLCAST_SUCCEEDED        = "completed",
    UNIT_SPELLCAST_INTERRUPTED      = "interrupted",
    UNIT_SPELLCAST_FAILED           = "stopped",
    UNIT_SPELLCAST_CHANNEL_STOP     = "completed",
    UNIT_SPELLCAST_EMPOWER_STOP     = "completed",
}

function Tracker:OnCastEvent(event, unit)
    if self.testMode then return end
    if unit ~= "target" then return end  -- defensive; RegisterUnitEvent already filters

    -- Definite end-of-cast events: short-circuit, no re-query.
    local endReason = END_EVENTS[event]
    if endReason then
        if self.shown then
            self:Hide(endReason)
        end
        return
    end

    -- Update-only events: only meaningful while we're already showing.
    if UPDATE_ONLY_EVENTS[event] and self.shown then
        local cast = GetCast("target")
        if cast then
            self:Update(cast)
        end
        return
    end

    -- Anything else (START / CHANNEL_START / EMPOWER_START): full evaluate.
    self:Evaluate()
end

function Tracker:OnTargetChanged()
    if self.testMode then return end
    -- Cancel any in-flight cast UI for the previous target before evaluating
    -- the new one — otherwise a fast switch can leave the old cast lingering
    -- visually until the new target's next event.
    if self.shown then
        self:Hide("no-target")
    end
    self:Evaluate()
end

function Tracker:OnUnitFaction(unit)
    if self.testMode then return end
    if unit ~= "target" then return end
    self:Evaluate()
end

function Tracker:OnTestMode(_, payload)
    -- TestMode toggles ownership of the START/END/UPDATE message stream.
    -- When testMode is true we suppress real-target work; TestMode itself
    -- fires the messages directly to drive the UI.
    self.testMode = (payload and payload.enabled) == true
    if self.testMode and self.shown then
        self:Hide("stopped")
    elseif not self.testMode then
        -- Coming out of test mode: re-sync against whatever the live target
        -- happens to be doing right now.
        self:Evaluate()
    end
end

function Tracker:OnProfileChanged()
    -- Profile swap can change nothing for Tracker proper, but the safest
    -- response is to drop any showing cast and re-evaluate so downstream
    -- UI reattaches to current state with the new profile's settings.
    if self.shown then self:Hide("stopped") end
    if not self.testMode then self:Evaluate() end
end

function Tracker:OnConfigChanged()
    -- Tracker has no styling; ignore. Hook is here so the closed message
    -- list is fully observed and future config changes can re-evaluate
    -- without breaking the contract.
end

-- ---------------------------------------------------------------------------
-- Core state machine
-- ---------------------------------------------------------------------------

--- Decide whether the UI should be shown, given the live target+cast state.
-- @return nothing; side-effects via Show/Update/Hide.
function Tracker:Evaluate()
    if self.testMode then return end

    if not UnitExists("target") then
        return self:Hide("no-target")
    end
    if UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return self:Hide("not-hostile")
    end

    local cast = GetCast("target")
    if not cast then
        return self:Hide("stopped")
    end
    if cast.notInterruptible then
        -- Per FR-1.5 the UI only shows for interruptible casts in v0.1.
        return self:Hide("stopped")
    end

    if self.shown then
        -- Already showing — push an UPDATE rather than a fresh START so the
        -- castbar interpolation stays continuous.
        self:Update(cast)
    else
        self:Show(cast)
    end
end

function Tracker:Show(cast)
    self.shown       = true
    self.currentCast = cast
    KickCD:SendMessage("KickCD_TARGET_CAST_START", {
        spellID          = cast.spellID,
        name             = cast.name,
        texture          = cast.texture,
        startMS          = cast.startMS,
        endMS            = cast.endMS,
        isChannel        = cast.isChannel,
        notInterruptible = cast.notInterruptible,
    })
end

function Tracker:Update(cast)
    if not self.shown then return end
    self.currentCast = cast
    KickCD:SendMessage("KickCD_TARGET_CAST_UPDATE", {
        startMS          = cast.startMS,
        endMS            = cast.endMS,
        notInterruptible = cast.notInterruptible,
    })
end

function Tracker:Hide(reason)
    if not self.shown then return end
    self.shown       = false
    self.currentCast = nil
    KickCD:SendMessage("KickCD_TARGET_CAST_END", { reason = reason or "stopped" })
end

-- ---------------------------------------------------------------------------
-- Debug
-- ---------------------------------------------------------------------------

--- /kickcd debug target — print current Tracker view to chat.
function Tracker:DebugDump()
    local p = KickCD.Util and KickCD.Util.print or print
    p("Tracker state:")
    p("  testMode = " .. tostring(self.testMode))
    p("  shown    = " .. tostring(self.shown))
    if UnitExists("target") then
        local name = UnitName("target") or "?"
        p(("  target   = %s (dead=%s, canAttack=%s)"):format(
            name,
            tostring(UnitIsDead("target")),
            tostring(UnitCanAttack("player", "target"))))
        local cast = GetCast("target")
        if cast then
            p(("  cast     = %s (id=%s) channel=%s notInt=%s start=%.0f end=%.0f"):format(
                tostring(cast.name),
                tostring(cast.spellID),
                tostring(cast.isChannel),
                tostring(cast.notInterruptible),
                cast.startMS or 0,
                cast.endMS or 0))
        else
            p("  cast     = (none)")
        end
    else
        p("  target   = (none)")
    end
    if self.currentCast then
        p(("  current  = %s (id=%s)"):format(
            tostring(self.currentCast.name),
            tostring(self.currentCast.spellID)))
    end
end
