-- modules/IconGrid_Visibility.lua — the grid's visibility gate and glow gate (peeled from IconGrid.lua, #25)
--
-- The visibility decision (visibilityMode / shouldBeVisible), the
-- "target_casting_interruptible" alpha mask (ApplyInterruptibilityMask),
-- IconGrid:RefreshVisibility, the UNIT_SPELLCAST_* / PLAYER_TARGET_CHANGED /
-- PLAYER_FOCUS_CHANGED handlers, and the glow gate (resolveInterruptible,
-- gateMoved, logGateChange, IconGrid:RefreshAllGlows). A pure move: IconGrid.lua
-- went past 1400 lines against layout-§1's 1500 cap, and this is the seam #25
-- named. IconGrid.lua keeps the instances, the lifecycle (EnableUnit still calls
-- RefreshVisibility / RefreshAllGlows as methods, resolved at call time) and
-- ICON_CAST_ROUTES, because EnableUnit owns the cast filter that routes here.
--
-- What it reads from IconGrid.lua comes off the module table at file load:
-- `IconGrid._instances` (the per-unit instance table itself, not a copy),
-- `IconGrid.InstanceCasting` and `IconGrid.MasterEnabled`. IconGrid.lua loads
-- first (KickCD.toc's LOAD-BEARING note), so all three exist by now.

local _, NS = ...
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf
local IconGrid = NS:GetModule("IconGrid")

local instances       = IconGrid._instances
local instanceCasting = IconGrid.InstanceCasting
local isEnabled       = IconGrid.MasterEnabled

-- Resolve the addon-wide "General visibility" setting. Defaults to
-- "always" if the field is missing. Both this module and
-- modules/Castbar.lua read the same value so they show / hide together
-- — see Castbar:isVisible for the cast bar's read.
local function visibilityMode()
    local profile = NS.db and NS.db.profile
    return (profile and profile.visibility) or "always"
end

-- Combat state lives in KickCD.State.inCombat (core/State.lua) — a
-- shared, single-owner flag driven off PLAYER_REGEN_DISABLED /
-- PLAYER_REGEN_ENABLED in one place, fanned out via the
-- Ka0s_KickCD_CombatState message that this module subscribes to. We
-- deliberately do NOT consult InCombatLockdown() inside shouldBeVisible
-- — that function reports protected-frame lockdown state, which can lag
-- the regen events by a frame. The event-driven flag is the source of
-- truth.

-- Decide whether `inst`'s grid should be visible right now. Master enable is
-- the gate; visibility mode then narrows that to a subset of states.
-- While unlocked the user is repositioning, so we ignore the visibility
-- mode and always show — otherwise the grid would be invisible exactly
-- when they need to drag it.
local function shouldBeVisible(inst)
    -- Step 0, above everything: a STOOD-DOWN addon shows nothing, for either
    -- reason it can be down — the player disabled it, or the perf harness
    -- suspended it. One question, asked of the latch (core/LifecycleSetup.lua),
    -- rather than two flags that can disagree.
    --
    -- Enforced HERE rather than by having the stand-down reach in and hide the
    -- grids, because imperative hiding is a snapshot — the next combat
    -- transition, target swap or settings change re-shows the grid behind the
    -- latch's back, and the addon is then visibly running while it claims to be
    -- off (slash-commands-§7, performance-§6). A check at the source holds for
    -- the whole window.
    if NS.IsDown and NS.IsDown() then return false end
    if not isEnabled() then return false end
    local profile = NS.db and NS.db.profile
    if profile and profile.locked == false then return true end
    local mode = visibilityMode()
    if mode == "in_combat" then
        return NS.State.inCombat
    elseif mode == "target_casting" then
        return instanceCasting(inst)
    elseif mode == "target_casting_interruptible" then
        -- Show whenever a hostile unit is casting; the actual
        -- interruptibility filter is applied as an alpha mask in
        -- ApplyInterruptibilityMask (called from RefreshVisibility).
        return NS.State.IsHostileUnitCasting(inst.unit)
    end
    return true  -- "always"
end

-- For the "target_casting_interruptible" mode, drive the grid frame's
-- alpha through SetAlphaFromBoolean(notInterruptible, 0, 1) so that an
-- in-progress cast on the unit only shows the icons when the cast is
-- interruptible. The flag is the 12.0 secret-tainted notInterruptible,
-- handed verbatim to a C-side method that accepts secrets — never read
-- in Lua. For all other modes (and while unlocked, where the user is
-- repositioning and needs to see the grid regardless) the grid runs at
-- alpha=1 (children carry their own alphas).
local function ApplyInterruptibilityMask(inst)
    local grid = inst.grid
    if not grid then return end
    local profile = NS.db and NS.db.profile
    local unlocked = profile and profile.locked == false
    local mode = visibilityMode()
    if not unlocked
       and mode == "target_casting_interruptible"
       and NS.State.ApplyInterruptibleAlpha
       and NS.State.ApplyInterruptibleAlpha(grid, inst.unit, 1) then
        return
    end
    grid:SetAlpha(1)
end

--- Apply the visibility decision (shouldBeVisible) to the grid frame.
--- Called from EnableUnit, every config change that touches general/master,
--- combat transitions, unit changes, and cast start/stop events.
---
--- For the "target_casting_interruptible" mode the Show gate fires for
--- ANY hostile cast — the per-cast interruptible filter rides on top of
--- it via SetAlphaFromBoolean (see ApplyInterruptibilityMask). Calling
--- it on every refresh is cheap and keeps the alpha in sync as
--- UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE events flip the
--- secret-value flag mid-cast.
function IconGrid:RefreshVisibility(inst)
    local grid = inst.grid
    if not grid then return end
    local __t0 = Perf.on and debugprofilestop()
    local show = shouldBeVisible(inst)
    if NS.State and NS.State.debug and show ~= inst.lastVisible then
        NS.Debug("IconGrid", "[%s] visibility %s: %s", inst.unit,
            tostring(visibilityMode()), show and "shown" or "hidden")
    end
    inst.lastVisible = show
    if show then
        grid:Show()
        ApplyInterruptibilityMask(inst)
    else
        grid:Hide()
    end
    if __t0 then Perf.Note("visibility", debugprofilestop() - __t0) end
end

--- UNIT_SPELLCAST_* events, EMPOWER_* included. The filter frame
--- (Util.NewUnitCastFilter in EnableUnit) already filters to this instance's unit, so `unit` names
--- the instance to refresh. Both the "*_casting" visibility modes and the
--- same-named glow triggers key off the unit's cast state.
function IconGrid:OnUnitCastEvent(_event, unit)
    local __t0 = Perf.on and debugprofilestop()
    local inst = instances[unit]
    if inst and inst.enabled then
        self:RefreshVisibility(inst)
        self:RefreshAllGlows(inst)
    end
    if __t0 then Perf.Note("castEvent", debugprofilestop() - __t0) end
end

--- PLAYER_TARGET_CHANGED handler. Both the "target_casting" /
--- "target_casting_interruptible" visibility modes AND the same-named
--- glow triggers depend on the target's cast state, so a target swap
--- requires re-evaluating both. A disabled target is a cheap no-op.
function IconGrid:OnTargetChanged()
    local inst = instances["target"]
    if inst and inst.enabled then
        self:RefreshVisibility(inst)
        self:RefreshAllGlows(inst)
    end
end

--- PLAYER_FOCUS_CHANGED handler — the focus-unit equivalent of
--- OnTargetChanged. Focus defaults disabled, so this is a no-op until the
--- focus instance is enabled (Phase 3).
function IconGrid:OnFocusChanged()
    local inst = instances["focus"]
    if inst and inst.enabled then
        self:RefreshVisibility(inst)
        self:RefreshAllGlows(inst)
    end
end

-- The gate's fourth state: interruptibility is secret-tainted and therefore
-- uncomparable. Named rather than written inline so it can never be mistaken
-- for the library's rendered <secret> sentinel (see core/Compat).
local SECRET_GATE = "secret"

-- The printed name of each resolved gate state. Cannot carry a nil key, so
-- "no hostile cast" is the caller's `or` fallback.
local GATE_LABEL = {
    [true]        = "on",
    [false]       = "off",
    [SECRET_GATE] = "secret (combat-tainted)",
}

--- Resolve the cast's interruptibility into the tri-state the gate compares:
---   * true     — hostile cast in progress and it IS interruptible
---   * false    — hostile cast in progress and it is NOT interruptible
---   * "secret" — the flag is secret-tainted and cannot be compared
---   * nil      — no hostile cast in progress
---
--- notInterruptible may be secret-tainted; comparing it directly
--- in Lua would error in tainted scope. We only need to detect
--- "did the truthy/falsy state change?" — convert through a C-side
--- coercion via `not not` IF the value is plain. When it's a secret
--- we leave it as-is and skip the equality compare in the gate
--- (treat any secret reading as "moved" and re-run iteration —
--- correctness over efficiency for the rare interruptibility flip).
local function resolveInterruptible(unit, hostileCasting)
    if not (hostileCasting and _G.UnitCastingInfo) then return nil end
    local _, _, _, _, _, _, _, notInterruptible = _G.UnitCastingInfo(unit)
    if notInterruptible == nil and _G.UnitChannelInfo then
        local _, _, _, _, _, _, ni = _G.UnitChannelInfo(unit)
        notInterruptible = ni
    end
    if NS.Compat.IsSecret(notInterruptible) then
        return SECRET_GATE
    end
    return not notInterruptible
end

--- Has the gate moved since the last call on this instance? A "secret"
--- reading always counts as moved — the flip behind it is uncomparable, so
--- iteration re-runs rather than risk stranding a stale glow decision.
--- The very first call also counts: hostileCasting is always a real boolean,
--- so it can never equal the nil the instance starts with.
local function gateMoved(inst, hostileCasting, interruptible)
    return inst.lastGateCasting ~= hostileCasting
        or inst.lastGateInterruptible ~= interruptible
        or interruptible == SECRET_GATE
end

--- Log the gate transition, once per distinct label.
--- Dedup: while interruptibility is secret-tainted the gate short-circuit
--- is deliberately bypassed, so every cast event reaches here — a boss
--- firing many casts would log an identical line each time. Emit only when
--- the printed label actually changes (debug-logging-§9). Label each state precisely
--- rather than collapsing "secret"/nil into a misleading "on".
local function logGateChange(unit, interruptible)
    if not (NS.State and NS.State.debug) then return end
    local gate = GATE_LABEL[interruptible] or "none (no hostile cast)"
    NS.DebugLog.DebugChanged("Cast." .. unit, "Cast", "[%s] cast gate: interruptible %s", unit, gate)
end

--- Re-run UpdateGlow for every active icon against its last-known state.
--- Called when the trigger condition could have changed (unit swap,
--- unit cast start/stop, interruptibility flip) — the icons' Cooldowns
--- state hasn't moved but the glow gate has, so we need to push the new
--- decision through.
---
--- Short-circuit on a (hostileCasting, interruptible) gate that hasn't
--- moved since the previous call. Boss casts that fire many short
--- abilities used to retrigger N icon evaluations per cast event even
--- when the gate decision was identical to last time; this caches the
--- two booleans the trigger predicates branch on and skips the per-icon
--- iteration when neither moved. Cache is per-instance so target and
--- focus don't share (or clobber) each other's gate.
function IconGrid:RefreshAllGlows(inst)
    -- Bracketed as `glowGate`, opening ABOVE the gate check for the same reason
    -- Cooldowns:PollSpell opens above its guards: resolveInterruptible and
    -- IsHostileUnitCasting are themselves API calls, and a bracket that covered
    -- only the fall-through would measure the cache's misses and call the hits
    -- free. Both exits close it. No parentKey: four of the five call sites run
    -- under no bracket at all (core/PerfSetup.lua).
    local __t0 = Perf.on and debugprofilestop()
    local unit = inst.unit
    -- Compute the gate booleans once. `interruptible` is a tri-state:
    --   * true  — unit is hostile-casting AND the cast is interruptible
    --   * false — unit is hostile-casting AND the cast is NOT interruptible
    --   * nil   — no hostile cast in progress (both true/false reads as
    --             irrelevant to the trigger decision)
    -- KickCD.State.IsHostileUnitCasting handles existence/can-attack gates
    -- and existing-channel checks; we only need to layer interruptibility
    -- on top.
    local hostileCasting = NS.State
        and NS.State.IsHostileUnitCasting
        and NS.State.IsHostileUnitCasting(unit) or false
    local interruptible = resolveInterruptible(unit, hostileCasting)

    if not gateMoved(inst, hostileCasting, interruptible) then
        if __t0 then Perf.Note("glowGate", debugprofilestop() - __t0) end
        return
    end
    -- Two scalars rather than a record, so a boss chaining casts doesn't
    -- allocate a table per gate change.
    inst.lastGateCasting, inst.lastGateInterruptible = hostileCasting, interruptible

    logGateChange(unit, interruptible)

    for _, btn in ipairs(inst.ordered) do
        if btn.UpdateGlow then btn:UpdateGlow(btn._lastState) end
    end
    if __t0 then Perf.Note("glowGate", debugprofilestop() - __t0) end
end

-- ---------------------------------------------------------------------------
-- Exposed for unit testing (see the note at the foot of IconGrid.lua)
-- ---------------------------------------------------------------------------
IconGrid.VisibilityMode   = visibilityMode
IconGrid.ShouldBeVisible  = shouldBeVisible
