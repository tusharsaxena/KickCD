-- modules/IconGrid.lua
--
-- Owns one parent frame (KickCDIconGrid) and N child icon widgets, each
-- pooled and reused on rebuild so we never churn frames. Visibility is
-- gated on db.profile.enabled (master enable) AND db.profile.visibility,
-- the addon-wide "General visibility" setting also honored by the cast
-- bar so both panels show / hide together:
--   * "always"          — show whenever master enable is on (default)
--   * "in_combat"       — show only while in combat (event-driven flag,
--                          NOT InCombatLockdown() — that lags by a frame)
--   * "target_casting"  — show only while UnitCastingInfo / UnitChannelInfo
--                          on "target" returns a non-nil name
--   * "target_casting_interruptible"
--                       — like target_casting but additionally requires
--                          the cast to be interruptible. notInterruptible
--                          is secret-tainted in 12.0 and cannot be
--                          compared in Lua, so this mode is implemented
--                          as a two-step gate: shouldBeVisible() returns
--                          true whenever the target is a hostile unit
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
--                               { gridFrame, primaryIcon, width, height };
--                               primaryIcon is nil when the active list is
--                               empty. Public accessors GetGridFrame /
--                               GetPrimaryIcon remain for callers that
--                               haven't yet adopted the payload form.

local addonName, NS = ...
local IconGrid = NS:NewModule("IconGrid", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Module-local state
-- ---------------------------------------------------------------------------

-- Pool of icon widgets. `active` is keyed by spellID so Ka0s_KickCD_SPELL_STATE
-- can look up its icon in O(1); `free` is a stack of released widgets ready
-- to be re-acquired on the next rebuild.
local pool = { active = {}, free = {} }

-- Ordered list of currently-laid-out icons (primary at [1], secondaries at
-- [2..N]). We keep a separate ordered list so the layout pass doesn't have
-- to walk pool.active in an unspecified hash order.
local ordered = {}

-- The parent frame. Created lazily in IconGrid:EnsureGrid() so the module's
-- OnEnable can run before UIParent is fully available in some edge cases
-- (e.g., test rigs that load us early).
local grid

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

-- True when the master enable flag is set. Defaults to true on a fresh
-- profile, so a missing field reads as enabled.
local function isEnabled()
    local profile = NS.db and NS.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

-- True if the player's target is currently casting or channeling. Reads
-- UnitCastingInfo / UnitChannelInfo via Compat._firstReturn — the helper
-- collapses the API's multi-return to position 1 (name) only, so the
-- truthy check below is on a single value. The name itself may be secret
-- in combat for protected casts but a nil-vs-non-nil truthy check does
-- not error (Lua's `not` is safe on secrets; same guarantee
-- `current.name and ...` relies on in modules/Castbar.lua).
local function isTargetCasting()
    if not (_G.UnitExists and _G.UnitExists("target")) then return false end
    if NS.Compat._firstReturn(_G.UnitCastingInfo, "target") then return true end
    if NS.Compat._firstReturn(_G.UnitChannelInfo, "target") then return true end
    return false
end
-- Published for modules/IconGrid_Render.lua's glow trigger (the one reverse
-- dependency from the peeled render file back into core visibility logic).
IconGrid._isTargetCasting = isTargetCasting

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

-- Decide whether the grid should be visible right now. Master enable is
-- the gate; visibility mode then narrows that to a subset of states.
-- While unlocked the user is repositioning, so we ignore the visibility
-- mode and always show — otherwise the grid would be invisible exactly
-- when they need to drag it.
local function shouldBeVisible()
    if not isEnabled() then return false end
    local profile = NS.db and NS.db.profile
    if profile and profile.locked == false then return true end
    local mode = visibilityMode()
    if mode == "in_combat" then
        return NS.State.inCombat
    elseif mode == "target_casting" then
        return isTargetCasting()
    elseif mode == "target_casting_interruptible" then
        -- Show whenever a hostile target is casting; the actual
        -- interruptibility filter is applied as an alpha mask in
        -- ApplyInterruptibilityMask (called from RefreshVisibility).
        return NS.State.IsHostileUnitCasting("target")
    end
    return true  -- "always"
end

-- For the "target_casting_interruptible" mode, drive the grid frame's
-- alpha through SetAlphaFromBoolean(notInterruptible, 0, 1) so that an
-- in-progress cast on the target only shows the icons when the cast is
-- interruptible. The flag is the 12.0 secret-tainted notInterruptible,
-- handed verbatim to a C-side method that accepts secrets — never read
-- in Lua. For all other modes (and while unlocked, where the user is
-- repositioning and needs to see the grid regardless) the grid runs at
-- alpha=1 (children carry their own alphas).
local function ApplyInterruptibilityMask()
    if not grid then return end
    local profile = NS.db and NS.db.profile
    local unlocked = profile and profile.locked == false
    local mode = visibilityMode()
    if not unlocked
       and mode == "target_casting_interruptible"
       and NS.State.ApplyInterruptibleAlpha
       and NS.State.ApplyInterruptibleAlpha(grid, "target", 1) then
        return
    end
    grid:SetAlpha(1)
end


-- Resolve the active spec key the same way Database/Cooldowns do.
-- classFile is the locale-independent token from UnitClass(); specName
-- is the localised display name from GetSpecializationInfo, normalised
-- through Util.NormalizeSpecToken so multi-word names (English "Beast
-- Mastery" and several non-English specs) collapse to the keys built
-- in defaults/Spells.lua.
local function getActiveSpecKey()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end
    classFile = NS.Util.NormalizeClassToken(classFile)
    local Compat = NS.Compat
    local specIdx = Compat and Compat.GetSpecialization()
    if not specIdx then return classFile, nil end
    local _, specName = Compat.GetSpecializationInfo(specIdx)
    if not specName then return classFile, nil end
    return classFile, NS.Util.NormalizeSpecToken(specName)
end


-- ---------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------

function IconGrid:AcquireIcon(spellID)
    local btn = table.remove(pool.free)
    if not btn then
        btn = IconGrid.CreateIconWidget(grid)
    end
    btn.spellID    = spellID
    btn.cfg        = NS.db.profile.icons
    btn._lastState = nil
    btn._cdObject  = nil
    btn:ClearAllPoints()
    btn:Show()
    pool.active[spellID] = btn
    return btn
end

function IconGrid:ReleaseAll()
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

function IconGrid:BuildActiveList()
    self:ReleaseAll()

    if not (NS.db and NS.db.profile) then return end

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
                local btn = self:AcquireIcon(entry.spellID)
                local tex = NS.Compat.GetSpellTexture(entry.spellID)
                -- Texture may be a 12.0 "secret value" on guarded spells
                -- (Mind Freeze etc.); SetTexture rejects them from tainted
                -- execution, so skip the call and leave the icon blank
                -- rather than erroring out of BuildActiveList partway.
                local texSecret = tex ~= nil and _G.issecretvalue and _G.issecretvalue(tex)
                if tex and not texSecret then btn.icon:SetTexture(tex) end
                btn:ApplyTextConfig(NS.db.profile.icons)
                -- Initial state: assume ready until Cooldowns sends a real
                -- Ka0s_KickCD_SPELL_STATE. Apply{} (no payload) treats the icon
                -- as "not ready" because state.ready is nil-falsy, so pass
                -- a synthetic ready frame to render correctly until the
                -- first real state arrives.
                btn:Apply({ ready = true, start = 0, duration = 0 })
                table.insert(ordered, btn)
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

function IconGrid:Layout()
    if not grid then return end
    local cfg = NS.db.profile.icons or {}

    local primarySize   = cfg.primarySize or 48
    local secondarySize = floor(primarySize * (cfg.secondarySize or 0.7))
    local gap           = cfg.gap or 4
    local anchor        = cfg.anchor or "RIGHT_MIDDLE"
    local grow          = cfg.secondaryGrow or "right_down"
    local rows          = cfg.secondaryRows or 1
    local cols          = cfg.secondaryCols or 6
    local offX          = cfg.secondaryOffsetX or 0
    local offY          = cfg.secondaryOffsetY or 0

    -- Re-bind cfg + text/appearance config on every layout pass so changes
    -- to color/alpha/font/zoom/border apply without a full rebuild. Stamp
    -- _isPrimary BEFORE ApplyTextConfig because that re-runs Apply which
    -- in turn calls UpdateGlow — and the glow path reads the slot flag.
    for i, btn in ipairs(ordered) do
        btn.cfg        = cfg
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
        if self._truncationWarnedFor ~= key then
            self._truncationWarnedFor = key
            if NS.Util and NS.Util.print then
                NS.Util.print(("dropped %d icon(s) past the %d-slot grid for %s — bump rows*cols or remove spells")
                    :format(truncated, cap, clsKey))
            end
        end
    elseif self._truncationWarnedFor and (truncated == 0 or not truncated) then
        -- No truncation this pass (user fixed it or the spell list shrank).
        -- Clear the dedup key so a future overflow re-warns.
        self._truncationWarnedFor = nil
    end

    -- Notify dependent modules (Castbar) that grid geometry / primary icon
    -- reference may have changed. Payload carries the gridFrame +
    -- primaryIcon references and the post-layout bounding box so the
    -- subscriber doesn't need to reach back through the public accessors.
    -- The accessors (GetGridFrame / GetPrimaryIcon) remain for callers
    -- that haven't yet adopted the payload form.
    if NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_GRID_LAYOUT", {
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
function IconGrid:ApplyGeneral()
    if not grid then return end
    local profile = NS.db and NS.db.profile
    if not profile then return end
    grid:SetScale(profile.scale or 1.0)
    grid:SetAlpha(profile.alpha or 1.0)
end

-- ---------------------------------------------------------------------------
-- Lock / unlock + drag persistence
-- ---------------------------------------------------------------------------

local function onDragStart(self)
    if NS.db and NS.db.profile and NS.db.profile.locked then return end
    self:StartMoving()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    if NS.db and NS.db.profile then
        NS.db.profile.anchors = NS.db.profile.anchors or {}
        NS.db.profile.anchors.icons = NS.Util.SaveAnchor(self)
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

function IconGrid:ApplyLock()
    if not grid then return end
    local profile  = NS.db and NS.db.profile
    local locked   = profile and profile.locked
    local showTip  = profile and profile.icons and profile.icons.showTooltip
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
    for _, btn in ipairs(ordered) do
        btn:EnableMouse(enableIconMouse)
    end
end

-- ---------------------------------------------------------------------------
-- Frame setup
-- ---------------------------------------------------------------------------

function IconGrid:EnsureGrid()
    if grid then return grid end

    grid = CreateFrame("Frame", "KickCDIconGrid", UIParent)
    grid:SetSize(48, 48)
    grid:SetFrameStrata("MEDIUM")
    grid:SetClampedToScreen(true)
    grid:SetMovable(true)

    -- Anchor from the saved profile. Util.ApplyAnchor unconditionally
    -- targets UIParent so we don't have to serialize a relativeTo.
    local anchor = NS.db and NS.db.profile
        and NS.db.profile.anchors and NS.db.profile.anchors.icons
    NS.Util.ApplyAnchor(grid, anchor or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })

    grid:SetScript("OnDragStart", onDragStart)
    grid:SetScript("OnDragStop",  onDragStop)

    -- Apply the current locked state. ApplyLock toggles EnableMouse +
    -- RegisterForDrag, which is the only correct way to "release" the mouse
    -- without permanently breaking drag — calling SetMovable(false) on a
    -- locked frame would prevent unlock without a reload.
    self:ApplyLock()
    self:ApplyGeneral()

    return grid
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

function IconGrid:OnEnable()
    -- Combat flag is owned by core/State.lua's bootstrap listener, so
    -- this module no longer seeds it on enable.
    self:EnsureGrid()
    IconGrid.BuildCurves()
    self:BuildActiveList()
    self:Layout()
    self:RefreshVisibility()

    -- Internal-message subscriptions. The grid never sends; Ka0s_KickCD_GRID_LAYOUT
    -- is fired from IconGrid:Layout itself, not via a SendMessage in OnEnable.
    self:RegisterMessage("Ka0s_KickCD_SPELL_STATE",     "OnSpellState")
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    -- Combat-state fan-out from core/State.lua. We no longer hook
    -- PLAYER_REGEN_* directly — State owns the only registration so the
    -- flag write and the visibility refresh stay ordered by construction.
    self:RegisterMessage("Ka0s_KickCD_COMBAT_STATE",    "OnCombatStateChanged")

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

    -- Events that drive the "General visibility" mode. We listen
    -- unconditionally so toggling the mode at runtime via /kcd set or the
    -- panel just works without re-registering. RefreshVisibility short-
    -- circuits to "always show" in "always" mode, so the only cost when
    -- the user hasn't opted into a gated mode is a few cheap callbacks.
    -- Combat transitions arrive via the Ka0s_KickCD_COMBAT_STATE message
    -- subscription above, not raw PLAYER_REGEN_* events.
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")

    -- UNIT_SPELLCAST_* registrations go through Util.RegisterTargetEvent
    -- so the dispatch frame fires only when the unit IS "target". With
    -- vanilla RegisterEvent the handler runs for every party / raid /
    -- nameplate cast and early-returns inside; in a 25-player raid that's
    -- thousands of no-op dispatches per minute. Interruptibility flips
    -- mid-cast (boss casts that toggle immunity via an aura, etc.) also
    -- come through this path so the "target_casting_interruptible" mode
    -- re-evaluates. The returned frames are stashed on the module so
    -- OnDisable can release them — AceEvent's UnregisterAllEvents only
    -- knows about its own table, not these private frames.
    self._targetEventFrames = self._targetEventFrames or {}
    local Util = NS.Util
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
        self._targetEventFrames[#self._targetEventFrames + 1] =
            Util.RegisterTargetEvent(self, ev, "OnTargetCastEvent")
    end
end

function IconGrid:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    if self._targetEventFrames then
        for _, f in ipairs(self._targetEventFrames) do
            f:UnregisterAllEvents()
        end
        self._targetEventFrames = {}
    end
    if grid then grid:Hide() end
end

-- ---------------------------------------------------------------------------
-- Message / event handlers
-- ---------------------------------------------------------------------------

function IconGrid:OnSpellState(_evt, payload)
    -- Payload contract per CLAUDE.md:
    --   { spellID, ready, isActive, cdObject, charges }
    -- We only update icons currently in the active pool — Cooldowns may
    -- watch a slightly larger or stale set during config transitions.
    if not (payload and payload.spellID) then return end
    local btn = pool.active[payload.spellID]
    if btn then btn:Apply(payload) end
end

function IconGrid:OnConfigChanged(_evt, payload)
    local section = payload and payload.section
    if section == "icons" then
        -- Re-layout only — widgets and their textures don't need to change
        -- when only sizing/colors/alphas changed. Layout() also calls
        -- ApplyAppearance/ApplyTextConfig per-icon so zoom/border/font
        -- changes flow through the same path.
        IconGrid.BuildCurves()  -- readyAlpha/cooldownAlpha/cooldownTint may have moved
        self:Layout()
        self:ApplyLock()
    elseif section == "spells" then
        -- Spell list changed under us — rebuild from the profile and stay
        -- visible. Lock state is unaffected.
        self:BuildActiveList()
        self:Layout()
    elseif section == "general" then
        -- General-tab edits include the master enable, the lock toggle,
        -- master scale / alpha, the visibility mode, and the Reset
        -- position button. Apply scale/alpha unconditionally; visibility
        -- decision rolls master enable + the mode together.
        if grid then
            local anchor = NS.db and NS.db.profile
                and NS.db.profile.anchors and NS.db.profile.anchors.icons
            if anchor then NS.Util.ApplyAnchor(grid, anchor) end
            self:ApplyGeneral()
        end
        self:RefreshVisibility()
        self:ApplyLock()
    end
end

function IconGrid:OnProfileChanged(_evt, payload)
    -- Full reset: re-anchor, rebuild the active list against the new
    -- profile's spell defaults, and re-apply the lock + general state.
    if grid then
        local anchor = NS.db and NS.db.profile
            and NS.db.profile.anchors and NS.db.profile.anchors.icons
        NS.Util.ApplyAnchor(grid, anchor or
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })
    end
    IconGrid.BuildCurves()
    self:BuildActiveList()
    self:Layout()
    self:ApplyLock()
    self:ApplyGeneral()
    self:RefreshVisibility()
end

--- Apply the visibility decision (shouldBeVisible) to the grid frame.
--- Called from OnEnable, every config change that touches general/master,
--- combat transitions, target changes, and target cast start/stop events.
---
--- For the "target_casting_interruptible" mode the Show gate fires for
--- ANY hostile cast — the per-cast interruptible filter rides on top of
--- it via SetAlphaFromBoolean (see ApplyInterruptibilityMask). Calling
--- it on every refresh is cheap and keeps the alpha in sync as
--- UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE events flip the
--- secret-value flag mid-cast.
function IconGrid:RefreshVisibility()
    if not grid then return end
    local show = shouldBeVisible()
    if NS.State and NS.State.debug and show ~= self._lastVisible then
        NS.Debug("IconGrid", "visibility %s: %s", tostring(visibilityMode()),
            show and "shown" or "hidden")
    end
    self._lastVisible = show
    if show then
        grid:Show()
        ApplyInterruptibilityMask()
    else
        grid:Hide()
    end
end

--- UNIT_SPELLCAST_* events fire for any unit. We only care about the
--- "target" unit because that's what the "target_casting" visibility
--- mode + the glow trigger key off of. The unit filter lives in the
--- registration site (Util.RegisterTargetEvent in OnEnable), so this
--- handler trusts that `unit` is always "target".
function IconGrid:OnTargetCastEvent()
    self:RefreshVisibility()
    self:RefreshAllGlows()
end

--- PLAYER_TARGET_CHANGED handler. Both the "target_casting" /
--- "target_casting_interruptible" visibility modes AND the same-named
--- glow triggers depend on the target's cast state, so a target swap
--- requires re-evaluating both.
function IconGrid:OnTargetChanged()
    self:RefreshVisibility()
    self:RefreshAllGlows()
end

--- Re-run UpdateGlow for every active icon against its last-known state.
--- Called when the trigger condition could have changed (target swap,
--- target cast start/stop, interruptibility flip) — the icons' Cooldowns
--- state hasn't moved but the glow gate has, so we need to push the new
--- decision through.
---
--- Short-circuit on a (hostileCasting, interruptible) gate that hasn't
--- moved since the previous call. Boss casts that fire many short
--- abilities used to retrigger N icon evaluations per cast event even
--- when the gate decision was identical to last time; this caches the
--- two booleans the trigger predicates branch on and skips the per-icon
--- iteration when neither moved. Cache is recomputed on every event the
--- function is called from (see OnTargetCastEvent / OnTargetChanged /
--- the per-icon Apply / ApplyTextConfig fall-throughs).
function IconGrid:RefreshAllGlows()
    -- Compute the gate booleans once. `interruptible` is a tri-state:
    --   * true  — target is hostile-casting AND the cast is interruptible
    --   * false — target is hostile-casting AND the cast is NOT interruptible
    --   * nil   — no hostile cast in progress (both true/false reads as
    --             irrelevant to the trigger decision)
    -- KickCD.State.IsHostileUnitCasting handles existence/can-attack gates
    -- and existing-channel checks; we only need to layer interruptibility
    -- on top.
    local hostileCasting = NS.State
        and NS.State.IsHostileUnitCasting
        and NS.State.IsHostileUnitCasting("target") or false
    local interruptible
    if hostileCasting and _G.UnitCastingInfo then
        local _, _, _, _, _, _, _, notInterruptible = _G.UnitCastingInfo("target")
        if notInterruptible == nil and _G.UnitChannelInfo then
            local _, _, _, _, _, _, ni = _G.UnitChannelInfo("target")
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

    local prev = self._lastGlowGate
    if prev
       and prev.hostileCasting == hostileCasting
       and prev.interruptible  == interruptible
       and interruptible ~= "secret"
    then
        return
    end
    self._lastGlowGate = { hostileCasting = hostileCasting, interruptible = interruptible }

    if NS.State and NS.State.debug then
        -- interruptible is a resolved tri-state (true/false/nil/"secret"), never
        -- a raw secret here — so these == compares are plain. Label each state
        -- precisely rather than collapsing "secret"/nil into a misleading "on".
        local gate = interruptible == true and "on"
            or interruptible == false and "off"
            or interruptible == "secret" and "secret (combat-tainted)"
            or "none (no hostile cast)"
        -- Dedup: while interruptibility is secret-tainted the gate short-circuit
        -- above is deliberately bypassed, so every target-cast event reaches
        -- here — a boss firing many casts would log an identical line each time.
        -- Emit only when the printed label actually changes (§9).
        if gate ~= self._lastCastLabel then
            self._lastCastLabel = gate
            NS.Debug("Cast", "target cast gate: interruptible %s", gate)
        end
    end

    for _, btn in ipairs(ordered) do
        if btn.UpdateGlow then btn:UpdateGlow(btn._lastState) end
    end
end

--- Re-evaluate visibility on combat-state transitions. The flag itself
--- is owned by core/State.lua's bootstrap listener; this handler runs
--- only for its side effect (the visibility refresh). Payload carries
--- `inCombat` but we read State.inCombat for consistency with
--- shouldBeVisible's other read sites.
function IconGrid:OnCombatStateChanged()
    self:RefreshVisibility()
end

function IconGrid:OnSpecChanged(_evt, unit)
    -- PLAYER_SPECIALIZATION_CHANGED fires for any unit; only react for the
    -- player.
    if unit and unit ~= "player" then return end
    self:BuildActiveList()
    self:Layout()
end

function IconGrid:OnPlayerEnteringWorld()
    self:BuildActiveList()
    self:Layout()
end

-- SPELLS_CHANGED / TRAIT_CONFIG_UPDATED handler. SPELLS_CHANGED in
-- particular fires several times during login, but BuildActiveList +
-- Layout are cheap (icon widgets pool, no frame churn) so a handful of
-- redundant rebuilds is fine.
function IconGrid:OnSpellsChanged()
    self:BuildActiveList()
    self:Layout()
end

-- ---------------------------------------------------------------------------
-- Public accessors
-- ---------------------------------------------------------------------------

--- Return the parent grid frame (KickCDIconGrid) or nil if not yet built.
--- Used by the cast bar module so it can anchor itself relative to the grid.
function IconGrid:GetGridFrame()
    return grid
end

--- Return the primary icon button (first laid-out icon) or nil if no spells
--- are currently watched. Used by the cast bar module's PRIMARY anchor mode.
function IconGrid:GetPrimaryIcon()
    return ordered[1]
end
