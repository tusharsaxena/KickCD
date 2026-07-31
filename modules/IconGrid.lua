-- modules/IconGrid.lua
--
-- Per-unit instance manager. Owns one parent frame + N pooled child icon
-- widgets PER TRACKED UNIT (target / focus). Each unit's instance carries its
-- own frame, icon pool, ordered list, private cast-event dispatch frames, and
-- cached appearance config. In Phase 1 only the target unit enables (Focus
-- defaults disabled), so behavior is identical to the former singleton.
--
-- Visibility is gated on db.profile.enabled (master enable) AND
-- db.profile.visibility, the addon-wide "General visibility" setting also
-- honored by the cast bar so both panels show / hide together:
--   * "always"          — show whenever master enable is on (default)
--   * "in_combat"       — show only while in combat (event-driven flag,
--                          NOT InCombatLockdown() — that lags by a frame)
--   * "target_casting"  — show only while UnitCastingInfo / UnitChannelInfo
--                          on the instance's unit returns a non-nil name
--   * "target_casting_interruptible"
--                       — like target_casting but additionally requires
--                          the cast to be interruptible. notInterruptible
--                          is secret-tainted in 12.0 and cannot be
--                          compared in Lua, so this mode is implemented
--                          as a two-step gate: shouldBeVisible() returns
--                          true whenever the unit is a hostile unit
--                          casting (State.IsHostileUnitCasting), and
--                          ApplyInterruptibilityMask() then drives the
--                          grid frame's alpha through SetAlphaFromBoolean
--                          (C-side, secret-safe) so uninterruptible casts
--                          read as alpha=0. Friendly / self casts are
--                          excluded by the IsHostileUnitCasting gate.
-- While unlocked, the visibility mode is bypassed so the user can drag
-- the grid into position. Combat / target / cast events drive
-- RefreshVisibility. Listens to:
--
--   Ka0s_KickCD_SPELL_STATE       -> route to the matching active icon's :Apply
--   Ka0s_KickCD_CONFIG_CHANGED    -> "icons" relayouts (zoom/border/font/grid);
--                                "spells" rebuilds;
--                                "general" re-applies lock, scale, alpha,
--                                  master-enable visibility, anchor.
--   Ka0s_KickCD_PROFILE_CHANGED   -> rebuild + re-anchor + reapply general
--   Ka0s_KickCD_COMBAT_STATE      -> RefreshVisibility (drives "in_combat" mode)
--   PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD -> rebuild
--
-- Emits:
--   Ka0s_KickCD_GRID_LAYOUT       -> fired at the end of every IconGrid:Layout()
--                               so dependent modules (notably modules/Castbar.lua,
--                               which can anchor relative to the primary icon
--                               and/or auto-size to the grid) can sync after
--                               the grid frame's size and the primary icon
--                               button reference settle. Payload is
--                               { unit, gridFrame, primaryIcon, width, height };
--                               primaryIcon is nil when the active list is
--                               empty. Public accessors GetGridFrame /
--                               GetPrimaryIcon remain for callers that
--                               haven't yet adopted the payload form.

local addonName, NS = ...
local IconGrid = NS:NewModule("IconGrid", "AceEvent-3.0")
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf

-- ---------------------------------------------------------------------------
-- Per-unit instances
-- ---------------------------------------------------------------------------
--
-- Each tracked unit (target/focus) owns its own frame, icon pool, ordered
-- list, private cast-event dispatch frames, and cached config. Formerly these
-- were file-local singletons (`pool`, `ordered`, `grid`); the instance model
-- lets a second unit coexist without any shared mutable state.
--
--   inst.pool.active   — keyed by spellID so Ka0s_KickCD_SPELL_STATE can look
--                        up its icon in O(1).
--   inst.pool.free     — a stack of released widgets ready to re-acquire.
--   inst.ordered       — ordered list of laid-out icons (primary at [1]).
--   inst.eventFrames   — private UNIT_SPELLCAST_* dispatch frames (teardown).
--   inst.cfg           — resolved icons appearance (NS.Units.Icons(unit)),
--                        refreshed at the top of Layout / config handlers.
--   inst.isCasting     — per-instance resolver published to the render file's
--                        glow trigger (replaces the module-level hook).
local instances = {}   -- [unit] = instance

local function newInstance(unit)
    return {
        unit        = unit,
        grid        = nil,
        pool        = { active = {}, free = {} },
        ordered     = {},
        eventFrames = {},
        cfg         = nil,
        enabled     = false,
        -- migrated from the former self._* module fields:
        truncationWarnedFor = nil,
        lastVisible   = nil,
        lastGlowGate  = nil,
        lastCastLabel = nil,
    }
end

function IconGrid:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = newInstance(unit); instances[unit] = inst end
    return inst
end

-- The per-icon widget system — the Icon prototype, its factory, cooldown /
-- glow rendering, the step-shaped alpha/tint curves, and the shared cooldown-
-- text ticker — lives in modules/IconGrid_Render.lua (peeled out for the
-- 1500-LOC cap). The grid geometry (anchor/grow parsing + block placement)
-- lives in modules/IconGrid_Layout.lua. This file owns the pool, layout
-- orchestration, visibility, and message handlers.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local floor = math.floor

-- Iterate every currently-enabled instance in LIST order. Handlers that fan
-- out to "all live grids" (config / profile / combat / spec changes) route
-- through here so the enable-gating lives in one place.
local function forEachEnabled(fn)
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled then fn(inst) end
    end
end

-- True when the master enable flag is set. Defaults to true on a fresh
-- profile, so a missing field reads as enabled.
local function isEnabled()
    local profile = NS.db and NS.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

-- True if `inst`'s unit is currently casting or channeling. Reads
-- UnitCastingInfo / UnitChannelInfo via Compat._firstReturn — the helper
-- collapses the API's multi-return to position 1 (name) only, so the
-- truthy check below is on a single value. The name itself may be secret
-- in combat for protected casts but a nil-vs-non-nil truthy check does
-- not error (Lua's `not` is safe on secrets; same guarantee
-- `current.name and ...` relies on in modules/Castbar.lua).
local function instanceCasting(inst)
    local unit = inst.unit
    if not (_G.UnitExists and _G.UnitExists(unit)) then return false end
    if NS.Compat._firstReturn(_G.UnitCastingInfo, unit) then return true end
    if NS.Compat._firstReturn(_G.UnitChannelInfo, unit) then return true end
    return false
end

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
-- Ka0s_KickCD_COMBAT_STATE message that this module subscribes to. We
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
    -- Step 0, above everything: a suspended addon shows nothing.
    --
    -- Enforced HERE rather than by having Perf's suspend reach in and hide the
    -- grids, because imperative hiding is a snapshot — the next combat
    -- transition, target swap or settings change re-shows the grid behind
    -- suspend's back, and the suspended arm then measures the addon still
    -- working (performance-§6). A check at the source holds for the whole
    -- suspended window.
    if NS.Perf and NS.Perf.suspended then return false end
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


-- Resolve the active spec key the same way Database/Cooldowns do: the
-- locale-independent class file token from UnitClass(), plus the NUMERIC
-- specID. Never the localised spec name — see issue #8.
local function getActiveSpecKey()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end
    classFile = NS.Util.NormalizeClassToken(classFile)
    return classFile, NS.Util.PlayerSpecID()
end


-- ---------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------

function IconGrid:AcquireIcon(inst, spellID)
    local btn = table.remove(inst.pool.free)
    if not btn then
        btn = IconGrid.CreateIconWidget(inst.grid)
    end
    btn.spellID    = spellID
    btn.cfg        = inst.cfg
    btn.unit       = inst.unit
    btn.instance   = inst
    btn._lastState = nil
    btn._cdObject  = nil
    btn:ClearAllPoints()
    btn:Show()
    inst.pool.active[spellID] = btn
    return btn
end

function IconGrid:ReleaseAll(inst)
    local pool = inst.pool
    for spellID, btn in pairs(pool.active) do
        btn:Hide()
        btn:ClearAllPoints()
        btn.spellID    = nil
        btn._lastState = nil
        btn._cdObject  = nil
        btn._isPrimary = nil
        -- Pull the icon out of the shared cooldown-text ticker before
        -- recycling it; the next acquire will re-register if needed.
        self:_UnregisterTextIcon(btn)
        -- Reset cooldown so a stale swipe doesn't reappear on re-acquire.
        if btn.cooldown then btn.cooldown:Clear() end
        if btn.chargesText then btn.chargesText:Hide() end
        if btn.cooldownText then btn.cooldownText:Hide() end
        if btn.StopGlow then btn:StopGlow() end
        table.insert(pool.free, btn)
        pool.active[spellID] = nil
    end
    -- Clear the ordered list — next BuildActiveList rebuilds it.
    local ordered = inst.ordered
    for i = #ordered, 1, -1 do ordered[i] = nil end
end

-- ---------------------------------------------------------------------------
-- Active spell list
-- ---------------------------------------------------------------------------
--
-- Filter the profile spell list down to entries:
--   * with enabled ~= false
--   * whose spellID resolves via Compat.GetSpellInfo (so spec-locked
--     spells the player can't see in their own spellbook are hidden)
-- First survivor → primary; rest → secondaries.

function IconGrid:BuildActiveList(inst)
    self:ReleaseAll(inst)

    if not (NS.db and NS.db.profile) then return end

    inst.cfg = NS.Units.Icons(inst.unit)

    local classFile, specName = getActiveSpecKey()
    if not (classFile and specName) then return end

    -- Read-only lookup via Database:GetSpellList — never lazy-creates
    -- a per-spec table, so a class+spec the user has never customised
    -- doesn't pollute the saved-vars with an empty entry.
    local list = NS.Database and NS.Database:GetSpellList(classFile, specName)
    if not list then return end

    -- Dedupe by spellID so pool.active stays strictly 1:1 with id.
    -- A duplicate id (hand-edited saved-vars, profile copy gone wrong,
    -- or a future bug at the mutation layer) would otherwise have
    -- AcquireIcon overwrite pool.active[id] with the second widget,
    -- orphaning the first — which then never receives SPELL_STATE
    -- updates while still being visible. Skip the duplicate; surface
    -- it in the debug console when debug logging is on (KickCD.State.debug).
    local _seen = {}
    for _, entry in ipairs(list) do
        if entry and entry.enabled ~= false and entry.spellID and _seen[entry.spellID] then
            if NS.State and NS.State.debug then
                NS.Debug("IconGrid", ("duplicate spellID %d in %s/%s — skipping"):format(
                    entry.spellID, classFile, specName))
            end
        elseif entry and entry.enabled ~= false and entry.spellID then
            _seen[entry.spellID] = true
            -- Hide entries the player can't see in their own spellbook.
            -- GetSpellInfo only proves the ID exists in the DB; IsSpellAvailable
            -- additionally requires the spell to be actually accessible right now,
            -- so an unpicked talent choice-node sibling (e.g. Blood DK's
            -- Gorefiend's Grasp ↔ Abomination Limb — both default-listed because
            -- either could be picked, but only one is castable) doesn't render.
            -- Pet spells (Counter Shot, Spell Lock) are likewise hidden until
            -- their pet is summoned.
            local name      = NS.Compat.GetSpellInfo(entry.spellID)
            local available = NS.Compat.IsSpellAvailable(entry.spellID)
            if name and available then
                local btn = self:AcquireIcon(inst, entry.spellID)
                local tex = NS.Compat.GetSpellTexture(entry.spellID)
                -- Texture may be a 12.0 "secret value" on guarded spells
                -- (Mind Freeze etc.); SetTexture rejects them from tainted
                -- execution, so skip the call and leave the icon blank
                -- rather than erroring out of BuildActiveList partway.
                local texSecret = tex ~= nil and _G.issecretvalue and _G.issecretvalue(tex)
                if tex and not texSecret then btn.icon:SetTexture(tex) end
                btn:ApplyTextConfig(inst.cfg)
                -- Initial state: assume ready until Cooldowns sends a real
                -- Ka0s_KickCD_SPELL_STATE. Apply{} (no payload) treats the icon
                -- as "not ready" because state.ready is nil-falsy, so pass
                -- a synthetic ready frame to render correctly until the
                -- first real state arrives.
                -- force=true: a rebuilt list may hand a pooled button whose
                -- _lastState still matches, and this pass has to repaint it.
                btn:Apply({ ready = true, start = 0, duration = 0 }, true)
                table.insert(inst.ordered, btn)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
--
-- The primary sits at one corner/edge of the grid frame; the `rows × cols`
-- secondary block attaches to one of 12 anchor points on the primary.
-- Layout is computed in three independent steps:
--
--   1. ANCHOR — picks where the block sits relative to the primary. The
--      first word (TOP/BOTTOM/LEFT/RIGHT) is the side; the second
--      (CENTER plus the alignment along the perpendicular axis: LEFT/RIGHT
--      for TOP/BOTTOM sides, TOP/BOTTOM for LEFT/RIGHT sides) picks where
--      on that side. 12 valid combinations.
--   2. GROW — fill order inside the block as a compound "<primary>_<secondary>"
--      direction (8 combinations of right/left/down/up). The primary axis
--      decides whether fill is row-major (right/left) or column-major
--      (down/up); the secondary axis decides which way the next row/column
--      goes after the first wraps. Anchor and grow are orthogonal: any
--      anchor works with any grow direction.
--   3. ROWS × COLS — block dimensions. `rows` is the vertical extent
--      (icons stacked up/down), `cols` the horizontal extent (icons
--      arranged left/right). Always geometric — never axis-relative.
--
-- secondaryOffsetX / secondaryOffsetY shift the entire block in screen-pixel
-- space (positive X = right, positive Y = down) without moving the primary.
--
-- Pixel-floor every offset so we don't end up with sub-pixel positions
-- on fractional UIScale values (which would blur icons by one pixel).

function IconGrid:Layout(inst)
    local grid = inst.grid
    if not grid then return end
    inst.cfg = NS.Units.Icons(inst.unit)
    local cfg = inst.cfg or {}

    local primarySize   = cfg.primarySize or 48
    local secondarySize = floor(primarySize * (cfg.secondarySize or 0.7))
    local gap           = cfg.gap or 4
    local anchor        = cfg.anchor or "RIGHT_MIDDLE"
    local grow          = cfg.secondaryGrow or "right_down"
    local rows          = cfg.secondaryRows or 1
    local cols          = cfg.secondaryCols or 6
    local offX          = cfg.secondaryOffsetX or 0
    local offY          = cfg.secondaryOffsetY or 0

    local ordered = inst.ordered

    -- Re-bind cfg + text/appearance config on every layout pass so changes
    -- to color/alpha/font/zoom/border apply without a full rebuild. Stamp
    -- _isPrimary BEFORE ApplyTextConfig because that re-runs Apply which
    -- in turn calls UpdateGlow — and the glow path reads the slot flag.
    for i, btn in ipairs(ordered) do
        btn.cfg        = cfg
        btn.unit       = inst.unit
        btn.instance   = inst
        btn._isPrimary = (i == 1)
        btn:Show()
        btn:ApplyAppearance(cfg)
        btn:ApplyTextConfig(cfg)
    end

    -- Empty-list decision: keep the frame visible at primary-icon size so
    -- the user can still drag it to reposition. The frame has no fill so
    -- "empty" reads as a small invisible square at its anchor; that's a
    -- minor cosmetic issue compared to losing the drag handle entirely.
    if #ordered == 0 then
        grid:SetSize(primarySize, primarySize)
        if NS.SendMessage then
            -- primaryIcon is nil here (no spells in the active list) —
            -- subscribers fall back to the public accessor or just skip.
            NS:SendMessage("Ka0s_KickCD_GRID_LAYOUT", {
                unit        = inst.unit,
                gridFrame   = grid,
                primaryIcon = nil,
                width       = primarySize,
                height      = primarySize,
            })
        end
        return
    end

    local primary = ordered[1]
    local secondaries = {}
    for i = 2, #ordered do secondaries[i - 1] = ordered[i] end

    local w, h, truncated = IconGrid.LayoutMath.layoutBlock(grid, primary, secondaries, primarySize, secondarySize, gap,
                                        anchor, grow, rows, cols, offX, offY)
    grid:SetSize(w, h)

    -- Warn once per (class/spec/cap) tuple when the configured grid
    -- size dropped icons. Without this the user sees a smaller grid
    -- than they configured with no indication that some spells are
    -- silently invisible. The dedup key includes cap so changing
    -- secondaryRows / secondaryCols re-arms the warning.
    if truncated and truncated > 0 then
        local cap     = (rows or 0) * (cols or 0)
        local clsKey  = "?/?"
        local cls, spc = getActiveSpecKey()
        if cls and spc then clsKey = cls .. "/" .. spc end
        local key = clsKey .. "/" .. tostring(cap)
        if inst.truncationWarnedFor ~= key then
            inst.truncationWarnedFor = key
            if NS.Util and NS.Util.print then
                NS.Util.print(("dropped %d icon(s) past the %d-slot grid for %s — bump rows*cols or remove spells")
                    :format(truncated, cap, clsKey))
            end
        end
    elseif inst.truncationWarnedFor and (truncated == 0 or not truncated) then
        -- No truncation this pass (user fixed it or the spell list shrank).
        -- Clear the dedup key so a future overflow re-warns.
        inst.truncationWarnedFor = nil
    end

    -- Notify dependent modules (Castbar) that grid geometry / primary icon
    -- reference may have changed. Payload carries the unit + gridFrame +
    -- primaryIcon references and the post-layout bounding box so the
    -- subscriber doesn't need to reach back through the public accessors.
    -- The accessors (GetGridFrame / GetPrimaryIcon) remain for callers
    -- that haven't yet adopted the payload form.
    if NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_GRID_LAYOUT", {
            unit        = inst.unit,
            gridFrame   = grid,
            primaryIcon = primary,
            width       = w,
            height      = h,
        })
    end
end

-- Apply general-tab visual settings (scale, alpha) to the parent frame.
-- Per-icon alpha continues to be set by Icon:Apply (cfg.readyAlpha /
-- cfg.cooldownAlpha) and multiplies naturally with the parent's alpha.
function IconGrid:ApplyGeneral(inst)
    local grid = inst.grid
    if not grid then return end
    local profile = NS.db and NS.db.profile
    if not profile then return end
    grid:SetScale(profile.scale or 1.0)
    grid:SetAlpha(profile.alpha or 1.0)
end

-- ---------------------------------------------------------------------------
-- Lock / unlock + drag persistence
-- ---------------------------------------------------------------------------

local function onDragStart(_inst, frame)
    if NS.db and NS.db.profile and NS.db.profile.locked then return end
    frame:StartMoving()
end

local function onDragStop(inst, frame)
    frame:StopMovingOrSizing()
    if NS.db and NS.db.profile then
        NS.Units.SetAnchor(inst.unit, "icons", NS.Util.SaveAnchor(frame))
    end
    -- Fire the closed bus message so any future "anchor-aware"
    -- subscriber (e.g. a hypothetical Castbar mode that follows the
    -- grid's free-floating position) gets notified. IconGrid's own
    -- OnConfigChanged handler is idempotent on `general` — re-anchoring
    -- to the just-saved value is a no-op — so this doesn't double-work.
    if NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })
    end
end

function IconGrid:ApplyLock(inst)
    local grid = inst.grid
    if not grid then return end
    local profile  = NS.db and NS.db.profile
    local locked   = profile and profile.locked
    inst.cfg = NS.Units.Icons(inst.unit)
    local showTip  = inst.cfg and inst.cfg.showTooltip
    if locked then
        grid:RegisterForDrag()        -- clear all drag buttons
        grid:EnableMouse(false)
    else
        grid:EnableMouse(true)
        grid:RegisterForDrag("LeftButton")
    end
    -- Per-icon mouse follows (locked AND showTooltip): when locked the
    -- grid frame doesn't capture mouse, so individual icons can claim
    -- it for hover tooltips. When unlocked, the grid wants mouse for
    -- drag and icons must pass through.
    local enableIconMouse = (locked and showTip) and true or false
    for _, btn in ipairs(inst.ordered) do
        btn:EnableMouse(enableIconMouse)
    end
end

-- ---------------------------------------------------------------------------
-- Frame setup
-- ---------------------------------------------------------------------------

function IconGrid:EnsureGrid(inst)
    if inst.grid then return inst.grid end

    -- Target keeps the exact legacy global name KickCDIconGrid (macros /
    -- other addons may reference it); Focus is KickCDIconGridFocus.
    local frameName = "KickCDIconGrid" .. (inst.unit == "target" and "" or "Focus")
    local grid = CreateFrame("Frame", frameName, UIParent)
    inst.grid = grid
    grid:SetSize(48, 48)
    grid:SetFrameStrata("MEDIUM")
    grid:SetClampedToScreen(true)
    grid:SetMovable(true)

    -- Anchor from the saved profile. Util.ApplyAnchor unconditionally
    -- targets UIParent so we don't have to serialize a relativeTo.
    local anchor = NS.Units.Anchor(inst.unit, "icons")
    NS.Util.ApplyAnchor(grid, anchor or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })

    grid:SetScript("OnDragStart", function(f) onDragStart(inst, f) end)
    grid:SetScript("OnDragStop",  function(f) onDragStop(inst, f) end)

    -- Apply the current locked state. ApplyLock toggles EnableMouse +
    -- RegisterForDrag, which is the only correct way to "release" the mouse
    -- without permanently breaking drag — calling SetMovable(false) on a
    -- locked frame would prevent unlock without a reload.
    self:ApplyLock(inst)
    self:ApplyGeneral(inst)

    return grid
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

-- Bring a unit's instance fully online: build its frame, active list, layout,
-- visibility, and register the per-instance UNIT_SPELLCAST_* dispatch frames.
function IconGrid:EnableUnit(unit)
    local inst = self:GetInstance(unit)
    inst.cfg = NS.Units.Icons(unit)
    -- Per-instance cast resolver, published to the render file's glow trigger
    -- via the icon's btn.instance (replaces the former module-level
    -- IconGrid._isTargetCasting hook). Idempotent across re-enables.
    inst.isCasting = inst.isCasting or function() return instanceCasting(inst) end
    self:EnsureGrid(inst)
    self:BuildActiveList(inst)
    self:Layout(inst)
    self:RefreshVisibility(inst)
    self:RefreshAllGlows(inst)   -- reflect any in-progress cast (reevaluate-on-enable)

    -- UNIT_SPELLCAST_* registrations go through Util.RegisterUnitCastEvent
    -- so the dispatch frame fires only when the unit IS this instance's unit.
    -- With vanilla RegisterEvent the handler runs for every party / raid /
    -- nameplate cast and early-returns inside; in a 25-player raid that's
    -- thousands of no-op dispatches per minute. Interruptibility flips
    -- mid-cast (boss casts that toggle immunity via an aura, etc.) also
    -- come through this path so the "target_casting_interruptible" mode
    -- re-evaluates. The returned frames are stashed on the instance so
    -- DisableUnit / OnDisable can release them — AceEvent's
    -- UnregisterAllEvents only knows about its own table, not these frames.
    for _, ev in ipairs({
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    }) do
        inst.eventFrames[#inst.eventFrames + 1] =
            NS.Util.RegisterUnitCastEvent(self, unit, ev, "OnUnitCastEvent")
    end
    inst.enabled = true
end

-- Tear a unit's instance down: release its private dispatch frames and hide
-- its grid. Used by OnDisable and (Phase 3) runtime enable-gating.
function IconGrid:DisableUnit(unit)
    local inst = instances[unit]
    if not inst then return end
    for _, f in ipairs(inst.eventFrames) do f:UnregisterAllEvents() end
    inst.eventFrames = {}
    if inst.grid then inst.grid:Hide() end
    inst.enabled = false
end

--- Make this module inert for a performance capture, WITHOUT a /reload and
--- without touching `inst.enabled`.
---
--- The enabled flag is deliberately left alone: it is the user's setting, and
--- Resume rebuilds from the CURRENT enabled set so a unit toggled while
--- suspended comes back correctly (performance-§6). What goes away is the work —
--- the module's own game events and the private per-unit dispatch frames, which
--- AceEvent's UnregisterAllEvents cannot reach because it only knows its own
--- table.
---
--- Messages are NOT unregistered. Resume republishes on the bus, and a module
--- that had torn down its subscriptions would never hear it.
function IconGrid:Suspend()
    self:UnregisterAllEvents()
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.eventFrames then
            for _, f in ipairs(inst.eventFrames) do f:UnregisterAllEvents() end
            inst.eventFrames = {}
        end
        if inst and inst.grid then inst.grid:Hide() end
    end
end

--- Restore everything Suspend took away, from current state rather than from a
--- snapshot: RegisterLifecycleEvents re-arms the game events and ReconcileUnits
--- re-creates the dispatch frames for whichever units are enabled NOW.
function IconGrid:Resume()
    self:RegisterLifecycleEvents()
    -- Every instance was left flagged enabled, so ReconcileUnits would consider
    -- them already reconciled and never re-create the frames Suspend released.
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled and #(inst.eventFrames or {}) == 0 then
            inst.enabled = false
        end
    end
    self:ReconcileUnits()
end

--- Reconcile every tracked unit's live enable-state against its desired
--- state (NS.Units.IsEnabled). Called from OnEnable and from
--- OnConfigChanged for the "general"/"units" sections so toggling the
--- master enable OR a per-unit enable brings the grid into the right
--- state without a /reload — including reviving a unit that was disabled
--- by master-enable being off (KCD regression: master off -> on used to
--- require /reload because OnConfigChanged "general" never re-ran the
--- enable loop). Idempotent: EnableUnit/DisableUnit are only invoked on
--- an actual want-vs-live mismatch.
function IconGrid:ReconcileUnits()
    -- While suspended, the desired state is "nothing runs". Without this the
    -- next `general`/`units` CONFIG_CHANGED would call EnableUnit and re-create
    -- all 8 dispatch frames per unit while the capture was still running.
    if NS.Perf and NS.Perf.suspended then return end
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        local want = NS.Units.IsEnabled(u)
        if want and not (inst and inst.enabled) then
            self:EnableUnit(u)
        elseif not want and inst and inst.enabled then
            self:DisableUnit(u)
        end
    end
end

--- The module's GAME-event registrations, split out of OnEnable so a perf
--- Resume can re-arm exactly the same set without re-running the rest of the
--- enable path (rebuilding curves, re-subscribing to messages it never dropped).
--- Registration is idempotent — AceEvent keys on (event, target) — so calling
--- this twice is harmless.
function IconGrid:RegisterLifecycleEvents()
    -- Spec / login events: rebuild against the new spec's spell list. The
    -- Cooldowns module hooks the same events to refresh its watched set, so
    -- both sides stay in sync.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")
    -- Talent / spellbook changes within the active spec also flip the
    -- "available" set used by BuildActiveList (choice-node swap, pet
    -- summon/dismiss for pet spells). Rebuild + relayout so the grid
    -- always shows only the spells the player can currently cast.
    self:RegisterEvent("SPELLS_CHANGED",                "OnSpellsChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED",          "OnSpellsChanged")

    -- The two global unit-change events. These are GLOBAL (no unit filter),
    -- so they register at MODULE level via plain RegisterEvent — NOT through
    -- RegisterUnitCastEvent (which is for the UNIT_SPELLCAST_* family). Each
    -- handler refreshes only its own unit's instance if that instance is live.
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED",          "OnFocusChanged")
end

function IconGrid:OnEnable()
    -- Combat flag is owned by core/State.lua's bootstrap listener, so
    -- this module no longer seeds it on enable.
    IconGrid.BuildCurves()

    -- Internal-message subscriptions. The grid never sends; Ka0s_KickCD_GRID_LAYOUT
    -- is fired from IconGrid:Layout itself, not via a SendMessage in OnEnable.
    self:RegisterMessage("Ka0s_KickCD_SPELL_STATE",     "OnSpellState")
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    -- Combat-state fan-out from core/State.lua. We no longer hook
    -- PLAYER_REGEN_* directly — State owns the only registration so the
    -- flag write and the visibility refresh stay ordered by construction.
    self:RegisterMessage("Ka0s_KickCD_COMBAT_STATE",    "OnCombatStateChanged")

    self:RegisterLifecycleEvents()

    -- Bring every enabled unit online. Focus defaults disabled, so only the
    -- target instance enables here and behavior matches the former singleton.
    self:ReconcileUnits()
end

function IconGrid:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    for _, u in ipairs(NS.Units.LIST) do
        self:DisableUnit(u)
    end
end

-- ---------------------------------------------------------------------------
-- Message / event handlers
-- ---------------------------------------------------------------------------

function IconGrid:OnSpellState(_evt, payload)
    -- Payload contract per CLAUDE.md:
    --   { spellID, ready, isActive, cdObject, charges }
    -- The player's cooldown state applies to every live unit's icon for
    -- that spell, so fan out to each enabled instance's active pool. We
    -- only update icons currently in the active pool — Cooldowns may watch
    -- a slightly larger or stale set during config transitions.
    if not (payload and payload.spellID) then return end
    local __t0 = Perf.on and debugprofilestop()
    -- Inlined (not forEachEnabled) so this hot path allocates no per-message
    -- closure. SPELL_STATE fires on every cooldown-state change.
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled then
            local btn = inst.pool.active[payload.spellID]
            if btn then btn:Apply(payload) end
        end
    end
    if __t0 then Perf.Note("spellState", debugprofilestop() - __t0) end
end

function IconGrid:OnConfigChanged(_evt, payload)
    local section = payload and payload.section
    if section == "icons" then
        -- Re-layout only — widgets and their textures don't need to change
        -- when only sizing/colors/alphas changed. Layout() also calls
        -- ApplyAppearance/ApplyTextConfig per-icon so zoom/border/font
        -- changes flow through the same path.
        IconGrid.BuildCurves()  -- readyAlpha/cooldownAlpha/cooldownTint may have moved
        forEachEnabled(function(inst)
            -- Re-resolve the link-aware appearance table first: a Target
            -- appearance edit must propagate to a linked Focus even though
            -- the edit only touched units.target.icons.
            inst.cfg = NS.Units.Icons(inst.unit)
            self:Layout(inst)
            self:ApplyLock(inst)
        end)
    elseif section == "spells" then
        -- Spell list changed under us — rebuild from the profile and stay
        -- visible. Lock state is unaffected.
        forEachEnabled(function(inst)
            self:BuildActiveList(inst)
            self:Layout(inst)
        end)
    elseif section == "general" or section == "units" then
        -- General-tab edits include the master enable, the lock toggle,
        -- master scale / alpha, the visibility mode, and the Reset
        -- position button. "units" covers the per-unit enable toggles
        -- (Task 6) and (Task 8) the link flag. Either can flip a unit's
        -- live-vs-desired enable state, so reconcile FIRST — a unit that
        -- just got enabled needs its grid built (ReconcileUnits ->
        -- EnableUnit already does that: sets inst.cfg, builds the active
        -- list, lays out, refreshes visibility/glows) before the
        -- already-live instances below are re-applied. This is also the
        -- fix for the regression where flipping master enable back on
        -- didn't revive the grid without /reload: ReconcileUnits sees
        -- want=true again and calls EnableUnit.
        self:ReconcileUnits()
        -- The curves are per unit and resolve through NS.Units.Icons, which is
        -- link-aware — so the focus LINK flag changes what a unit's curve
        -- should be built from even though no icons.* value moved. That flag
        -- lives in this section, not "icons", so a link flip has to rebuild
        -- here or an unlinked focus keeps rendering with target's readyAlpha /
        -- cooldownAlpha / cooldownTint. Per-unit enable toggles land here too,
        -- and a unit coming back online wants curves matching its current
        -- resolution. Cheap: BuildCurves skips any unit whose resolved values
        -- are unchanged.
        IconGrid.BuildCurves()
        forEachEnabled(function(inst)
            if inst.grid then
                local anchor = NS.Units.Anchor(inst.unit, "icons")
                if anchor then NS.Util.ApplyAnchor(inst.grid, anchor) end
                self:ApplyGeneral(inst)
            end
            if section == "units" then
                -- Re-resolve the link-aware appearance table: a link flag
                -- flip (Task 8) or an already-live focus's own enable
                -- toggle both need this instance's cfg/render current.
                inst.cfg = NS.Units.Icons(inst.unit)
                self:Layout(inst)
            end
            self:RefreshVisibility(inst)
            self:RefreshAllGlows(inst)
            self:ApplyLock(inst)
        end)
    end
end

function IconGrid:OnProfileChanged(_evt, payload)
    -- Full reset: re-anchor, rebuild the active list against the new
    -- profile's spell defaults, and re-apply the lock + general state.
    -- A profile swap can carry different units.<unit>.enabled values than
    -- the outgoing profile, so reconcile live-vs-desired FIRST — otherwise
    -- a focus that was live under the old profile but disabled in the new
    -- one would keep running (or vice versa) until the next config event.
    self:ReconcileUnits()
    IconGrid.BuildCurves()
    forEachEnabled(function(inst)
        if inst.grid then
            local anchor = NS.Units.Anchor(inst.unit, "icons")
            NS.Util.ApplyAnchor(inst.grid, anchor or
                { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })
        end
        self:BuildActiveList(inst)
        self:Layout(inst)
        self:ApplyLock(inst)
        self:ApplyGeneral(inst)
        self:RefreshVisibility(inst)
    end)
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

--- UNIT_SPELLCAST_* events. The dispatch frame (Util.RegisterUnitCastEvent
--- in EnableUnit) already filters to this instance's unit, so `unit` names
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
    local interruptible
    if hostileCasting and _G.UnitCastingInfo then
        local _, _, _, _, _, _, _, notInterruptible = _G.UnitCastingInfo(unit)
        if notInterruptible == nil and _G.UnitChannelInfo then
            local _, _, _, _, _, _, ni = _G.UnitChannelInfo(unit)
            notInterruptible = ni
        end
        -- notInterruptible may be secret-tainted; comparing it directly
        -- in Lua would error in tainted scope. We only need to detect
        -- "did the truthy/falsy state change?" — convert through a C-side
        -- coercion via `not not` IF the value is plain. When it's a secret
        -- we leave it as-is and skip the equality compare in the gate
        -- (treat any secret reading as "moved" and re-run iteration —
        -- correctness over efficiency for the rare interruptibility flip).
        if _G.issecretvalue and _G.issecretvalue(notInterruptible) then
            interruptible = "secret"
        else
            interruptible = not notInterruptible
        end
    else
        interruptible = nil
    end

    local prev = inst.lastGlowGate
    if prev
       and prev.hostileCasting == hostileCasting
       and prev.interruptible  == interruptible
       and interruptible ~= "secret"
    then
        return
    end
    inst.lastGlowGate = { hostileCasting = hostileCasting, interruptible = interruptible }

    if NS.State and NS.State.debug then
        -- interruptible is a resolved tri-state (true/false/nil/"secret"), never
        -- a raw secret here — so these == compares are plain. Label each state
        -- precisely rather than collapsing "secret"/nil into a misleading "on".
        local gate = interruptible == true and "on"
            or interruptible == false and "off"
            or interruptible == "secret" and "secret (combat-tainted)"
            or "none (no hostile cast)"
        -- Dedup: while interruptibility is secret-tainted the gate short-circuit
        -- above is deliberately bypassed, so every cast event reaches here — a
        -- boss firing many casts would log an identical line each time. Emit
        -- only when the printed label actually changes (§9).
        if gate ~= inst.lastCastLabel then
            inst.lastCastLabel = gate
            NS.Debug("Cast", "[%s] cast gate: interruptible %s", unit, gate)
        end
    end

    for _, btn in ipairs(inst.ordered) do
        if btn.UpdateGlow then btn:UpdateGlow(btn._lastState) end
    end
end

--- Re-evaluate visibility on combat-state transitions. The flag itself
--- is owned by core/State.lua's bootstrap listener; this handler runs
--- only for its side effect (the visibility refresh). Payload carries
--- `inCombat` but we read State.inCombat for consistency with
--- shouldBeVisible's other read sites.
function IconGrid:OnCombatStateChanged()
    forEachEnabled(function(inst)
        self:RefreshVisibility(inst)
    end)
end

function IconGrid:OnSpecChanged(_evt, unit)
    -- PLAYER_SPECIALIZATION_CHANGED fires for any unit; only react for the
    -- player.
    if unit and unit ~= "player" then return end
    forEachEnabled(function(inst)
        self:BuildActiveList(inst)
        self:Layout(inst)
    end)
end

function IconGrid:OnPlayerEnteringWorld()
    forEachEnabled(function(inst)
        self:BuildActiveList(inst)
        self:Layout(inst)
    end)
end

-- SPELLS_CHANGED / TRAIT_CONFIG_UPDATED handler. SPELLS_CHANGED in
-- particular fires several times during login, but BuildActiveList +
-- Layout are cheap (icon widgets pool, no frame churn) so a handful of
-- redundant rebuilds is fine.
function IconGrid:OnSpellsChanged()
    forEachEnabled(function(inst)
        self:BuildActiveList(inst)
        self:Layout(inst)
    end)
end

-- ---------------------------------------------------------------------------
-- Public accessors
-- ---------------------------------------------------------------------------

--- Return the parent grid frame for `unit` (default "target") or nil if not
--- yet built. Target's frame keeps the legacy global name KickCDIconGrid.
--- Used by the cast bar module so it can anchor itself relative to the grid.
function IconGrid:GetGridFrame(unit)
    local inst = instances[unit or "target"]
    return inst and inst.grid
end

--- Return the primary icon button (first laid-out icon) for `unit` (default
--- "target") or nil if no spells are currently watched. Used by the cast bar
--- module's PRIMARY anchor mode.
function IconGrid:GetPrimaryIcon(unit)
    local inst = instances[unit or "target"]
    return inst and inst.ordered[1]
end

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- The visibility decision is the single most branch-heavy piece of logic in
-- the module and is otherwise only reachable through a frame, so publish the
-- deciders (same idiom as Castbar.AutoSizeLong). Internal call sites still
-- use the locals.
-- NB: named MasterEnabled, NOT IsEnabled — AceAddon embeds its own
-- IsEnabled(self) (returns self.enabledState) directly onto every module
-- object, so publishing under that name would silently shadow the library
-- method with one that answers a different question.
IconGrid.VisibilityMode   = visibilityMode
IconGrid.ShouldBeVisible  = shouldBeVisible
IconGrid.InstanceCasting  = instanceCasting
IconGrid.MasterEnabled    = isEnabled
