-- modules/Castbar_Events.lua -- the cast bar's event and message handlers
-- (peeled from Castbar.lua, #24 / KC-ATS-01)
--
-- Everything the bar does in RESPONSE to something: the two global unit-change
-- events, the combat and world transitions, the per-instance UNIT_SPELLCAST_*
-- dispatch (OnCastStart / OnChannelStart / OnCastStop /
-- OnInterruptibilityChanged / OnCastDelayed) and the three bus messages
-- (OnConfigChanged / OnProfileChanged / OnGridLayout). Castbar.lua keeps the
-- instance model, the frame build, the per-cast paint, the OnUpdate loop and the
-- lifecycle that registers these handlers.
--
-- Peeled because Castbar.lua reached 1440 LOC, ten below the 1450 re-check line
-- the automated-tests watch list set for it, inside layout-§1's 1000-1500 band.
-- The seam is the one that file's own header and #24 nominated: the handler
-- block at its bottom, which reaches into nothing but five file-locals.
--
-- Every registration names its handler by STRING -- AceEvent's RegisterEvent /
-- RegisterMessage and Util.NewUnitCastFilter's CASTBAR_CAST_ROUTES all look the
-- method up on the module when the event fires -- so defining them here, after
-- Castbar.lua has built the route table, changes nothing about dispatch. The
-- first dispatch is OnEnable at PLAYER_LOGIN, long after every file has loaded.
--
-- The helpers come off the module table rather than being duplicated, the
-- pattern Castbar_Skin.lua and Castbar_Handle.lua follow, and are bound to
-- file-scope upvalues once at load, so a handler pays exactly the upvalue read
-- it paid before the move (anti-patterns #43).

local _, NS = ...
local Castbar = NS:GetModule("Castbar")   -- registered by modules/Castbar.lua, which loads first

local instances           = Castbar.Instances
local cfg                 = Castbar.Cfg
local forEachEnabled      = Castbar.ForEachEnabled
local isVisible           = Castbar.IsVisible
local ApplyVisibilityMask = Castbar.ApplyVisibilityMask

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

--- PLAYER_TARGET_CHANGED handler. A target swap requires re-evaluating the
--- target bar's cast state. A disabled / absent target instance is a no-op.
function Castbar:OnTargetChanged()
    local inst = instances["target"]
    if inst and inst.enabled then self:Reevaluate(inst) end
end

--- PLAYER_FOCUS_CHANGED handler — the focus-unit equivalent of
--- OnTargetChanged. Focus is enabled by default; a disabled/absent focus
--- instance is a cheap no-op here.
function Castbar:OnFocusChanged()
    local inst = instances["focus"]
    if inst and inst.enabled then self:Reevaluate(inst) end
end

-- Re-evaluate every live bar on combat-state transitions so each shows / hides
-- as the visibility mode dictates. In "in_combat" mode entering combat reveals
-- the bar (if a cast is ongoing), and leaving combat tears it down even if the
-- cast continues. The combat flag itself is owned by core/State.lua's bootstrap
-- listener; this handler runs only for its side effect (Reevaluate / Stop).
-- Payload carries `inCombat` but isVisible() reads State.inCombat directly so we
-- ignore it here.
function Castbar:OnCombatStateChanged()
    forEachEnabled(function(inst)
        if isVisible(inst) then
            self:Reevaluate(inst)
        else
            self:Stop(inst)
        end
    end)
end

function Castbar:OnPlayerEnteringWorld()
    forEachEnabled(function(inst)
        self:Reevaluate(inst)
    end)
end

-- Cast / channel / interruptibility handlers receive (self, event, unit) from
-- the per-instance cast filter (already filtered to the instance's unit).
-- Each resolves instances[unit]; a dispatch for a dead instance is a no-op.

function Castbar:OnCastStart(_event, unit)
    local inst = instances[unit]
    if inst and isVisible(inst) then
        local rec = NS.Compat.GetCastingInfo(inst.unit)
        if rec then self:Start(inst, rec) end
    end
end

function Castbar:OnChannelStart(_event, unit)
    local inst = instances[unit]
    if inst and isVisible(inst) then
        local rec = NS.Compat.GetChannelInfo(inst.unit)
        if rec then self:Start(inst, rec) end
    end
end

function Castbar:OnCastStop(_event, unit)
    local inst = instances[unit]
    if inst then self:Stop(inst) end
end

function Castbar:OnInterruptibilityChanged(evt, unit)
    local inst = instances[unit]
    if not inst then return end
    -- evt is "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" when the cast just became
    -- uninterruptible, "UNIT_SPELLCAST_INTERRUPTIBLE" when it just became
    -- interruptible. Update the record's bool and re-apply per-state visuals.
    --
    -- Plain-after-flip invariant: at cast start `current.notInterruptible`
    -- is whatever UnitCastingInfo.notInterruptible returned (plain on
    -- non-protected casts, secret-tainted in combat for casts the player
    -- has a protected interrupt against). This handler OVERWRITES that
    -- value with a plain Lua boolean derived from the event name; from
    -- this point on `current.notInterruptible` is plain. ApplyState's
    -- C_CurveUtil.EvaluateColorValueFromBoolean accepts both forms (plain
    -- and secret) so this swap is safe in either direction. See
    -- docs/castbar.md and docs/midnight-quirks.md "Plain-after-flip
    -- invariant" for the full rationale.
    if inst.current then
        inst.current.notInterruptible = (evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        self:ApplyState(inst)
    end
    -- For the "target_casting_interruptible" mode the bar STAYS shown for
    -- any hostile cast (so we can hand the secret-tainted notInterruptible
    -- flag to SetAlphaFromBoolean) — re-driving the alpha mask is the
    -- only thing that needs to happen when the flag flips. Falling back
    -- to Stop/Reevaluate here would race with the cast lifecycle and
    -- reorder the very Show that the alpha mask depends on.
    if isVisible(inst) then
        if not inst.current then
            self:Reevaluate(inst)
        else
            ApplyVisibilityMask(inst.frame, inst.unit)
        end
    else
        self:Stop(inst)
    end
end

function Castbar:OnCastDelayed(_event, unit)
    local inst = instances[unit]
    if not (inst and inst.current) then return end
    -- Re-query so the timeline reflects the pushback / haste change.
    -- notInterruptible could in principle change too (e.g. an aura that
    -- toggles interruptibility mid-cast), so re-apply the per-state
    -- visuals as well.
    local rec = NS.Compat.GetCastingInfo(inst.unit)
    if rec then
        inst.current = rec
        -- Re-cache showTime: the user may have toggled it between the
        -- cast starting and the delay event. (CR-10: onUpdate reads
        -- current.showTime, not cfg().showTime.)
        inst.current.showTime = (cfg(inst).showTime ~= false)
        -- The duration object's total duration just changed (pushback /
        -- haste / channel pulse re-time). Re-set both StatusBars' ranges
        -- here so onUpdate doesn't have to do it every frame. Pass the
        -- duration method straight to the C method — secret-safe.
        local d = rec.duration
        if d and inst.frame then
            inst.frame.bar.interruptible:SetMinMaxValues(0, d:GetTotalDuration())
            inst.frame.bar.uninterruptible:SetMinMaxValues(0, d:GetTotalDuration())
        end
        self:ApplyState(inst)
    end
end

-- ---------------------------------------------------------------------------
-- Message handlers
-- ---------------------------------------------------------------------------

function Castbar:OnConfigChanged(_evt, payload)
    local section = payload and payload.section
    if section == "castbar" or section == "units" then
        -- "units" (Task 6: per-unit enable; Task 8: link flag) can change
        -- which appearance table cfg(inst) resolves to (NS.Units.Castbar
        -- link-resolves through units.<unit>.link), so re-skin exactly like
        -- a "castbar" section edit. Reconcile enable-state first so a
        -- just-enabled unit's frame exists before Reskin/ApplyAnchor touch it.
        if section == "units" then self:ReconcileUnits() end
        forEachEnabled(function(inst)
            -- Anchor mode + offsets and orientation/grow may have changed;
            -- apply both before reskin so Reskin sees the right frame size
            -- when it computes auto-size and child anchors.
            self:ApplyAnchor(inst)
            self:Reskin(inst)
            if inst.current then
                -- Refresh the per-cast-record showTime cache so onUpdate's hot
                -- path picks up a config flip mid-cast (CR-10).
                inst.current.showTime = (cfg(inst).showTime ~= false)
                -- Re-paint the per-cast texture / name so structural changes
                -- (iconSize toggle, nameTruncate change, ...) take effect
                -- immediately without waiting for the next cast (CR-17).
                self:RenderCast(inst, inst.current)
            end
            if not isVisible(inst) then
                self:Stop(inst)
            else
                -- castbar.enabled may have just flipped from false → true; pick
                -- up an in-progress cast so the bar appears immediately.
                if not inst.current then self:Reevaluate(inst) end
                self:ApplyLock(inst)
            end
        end)
    elseif section == "general" then
        -- Master enable / lock flag may have flipped. Reconcile FIRST: this
        -- is the fix for the regression where flipping master enable back
        -- on didn't revive the bar without /reload — ReconcileUnits sees
        -- want=true again and calls EnableUnit, which snaps to any
        -- in-progress cast via Reevaluate.
        self:ReconcileUnits()
        forEachEnabled(function(inst)
            self:ApplyLock(inst)
            if not isVisible(inst) then
                self:Stop(inst)
            else
                self:Reevaluate(inst)
            end
        end)
    end
end

function Castbar:OnProfileChanged()
    -- A profile swap can carry different units.<unit>.enabled values than
    -- the outgoing profile, so reconcile live-vs-desired FIRST — mirrors
    -- IconGrid:OnProfileChanged.
    self:ReconcileUnits()
    forEachEnabled(function(inst)
        self:ApplyAnchor(inst)
        self:Reskin(inst)
        if inst.current then self:RenderCast(inst, inst.current) end
        self:ApplyLock(inst)
        if isVisible(inst) then self:Reevaluate(inst) else self:Stop(inst) end
    end)
end

--- Fired by IconGrid after every Layout()/BuildActiveList() pass. Payload shape
--- (CR-29): { unit, gridFrame, primaryIcon (Button|nil), width, height }. The
--- grid frame may have resized (auto-size tracks it) and the primary icon ref
--- may have changed (PRIMARY anchor retargets). The resolveGridFrame /
--- resolvePrimaryIcon accessor fallback covers the first tick / empty payloads.
function Castbar:OnGridLayout(_evt, payload)
    -- Filter by unit: the payload names which grid re-laid out. A focus grid's
    -- layout must NOT overwrite the target bar's cached grid refs.
    if type(payload) ~= "table" or not payload.unit then return end
    local inst = instances[payload.unit]
    if not (inst and inst.frame) then return end

    -- Cache the payload's references for ApplyAnchor / Reskin.
    -- Defensive: only cache when the field is actually populated, so an
    -- empty payload doesn't blank the cache.
    if payload.gridFrame   ~= nil then inst.lastGridLayout.gridFrame   = payload.gridFrame   end
    if payload.primaryIcon ~= nil then inst.lastGridLayout.primaryIcon = payload.primaryIcon end

    local c = cfg(inst)
    -- PRIMARY mode: re-target the primary icon button (which may have been
    -- released to pool and a new one acquired).
    if c.anchorMode == "PRIMARY" then
        self:ApplyAnchor(inst)
    end
    -- Auto-size: re-run Reskin so the bar's dimensions track the grid's
    -- current footprint. Skip the no-op Reskin when auto-size is off.
    -- If a cast is active, RenderCast picks up the new dimensions for the
    -- texture / bar values that the new structural layout exposes.
    if c.autoSize then
        self:Reskin(inst)
        if inst.current then self:RenderCast(inst, inst.current) end
    end
end
