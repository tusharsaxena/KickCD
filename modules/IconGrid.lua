-- modules/IconGrid.lua
--
-- Per-unit instance manager. Owns one parent frame + N pooled child icon
-- widgets PER TRACKED UNIT (target / focus). Each unit's instance carries its
-- own frame, icon pool, ordered list, private cast-filter frame, and
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
--   Ka0s_KickCD_SpellState       -> route to the matching active icon's :Apply
--   Ka0s_KickCD_ConfigChanged    -> "icons" relayouts (zoom/border/font/grid);
--                                "spells" rebuilds;
--                                "general" re-applies lock, scale, alpha,
--                                  master-enable visibility, anchor.
--   Ka0s_KickCD_ProfileChanged   -> rebuild + re-anchor + reapply general
--   Ka0s_KickCD_CombatState      -> RefreshVisibility (drives "in_combat" mode)
--   PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD -> rebuild
--
-- Emits:
--   Ka0s_KickCD_GridLayout       -> fired at the end of every IconGrid:Layout()
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

local _, NS = ...
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
-- list, private cast-filter frame, and cached config. Formerly these
-- were file-local singletons (`pool`, `ordered`, `grid`); the instance model
-- lets a second unit coexist without any shared mutable state.
--
--   inst.pool.active   — keyed by spellID so Ka0s_KickCD_SpellState can look
--                        up its icon in O(1).
--   inst.pool.free     — a stack of released widgets ready to re-acquire.
--   inst.ordered       — ordered list of laid-out icons (primary at [1]).
--   inst.castFilter    — the ONE private UNIT_SPELLCAST_* filter frame
--                        (Util.NewUnitCastFilter), built on first enable and
--                        armed / disarmed thereafter, never rebuilt.
--   inst.cfg           — resolved icons appearance (NS.Units.Icons(unit)),
--                        refreshed at the top of Layout / config handlers.
--   inst.isCasting     — per-instance resolver published to the render file's
--                        glow trigger (replaces the module-level hook).
local instances = {}   -- [unit] = instance

-- The cast filter's FIXED event set, every one refreshing the unit's
-- "*_casting" visibility and glow. FILE SCOPE so an enable allocates nothing
-- (anti-patterns #43). EMPOWER_* is an Evoker's empowered cast, which reads as a
-- channel but fires its own start/update/stop instead of CHANNEL_*.
local ICON_CAST_ROUTES = {
    UNIT_SPELLCAST_START             = "OnUnitCastEvent",
    UNIT_SPELLCAST_STOP              = "OnUnitCastEvent",
    UNIT_SPELLCAST_FAILED            = "OnUnitCastEvent",
    UNIT_SPELLCAST_INTERRUPTED       = "OnUnitCastEvent",
    UNIT_SPELLCAST_CHANNEL_START     = "OnUnitCastEvent",
    UNIT_SPELLCAST_CHANNEL_STOP      = "OnUnitCastEvent",
    UNIT_SPELLCAST_INTERRUPTIBLE     = "OnUnitCastEvent",
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "OnUnitCastEvent",
    UNIT_SPELLCAST_EMPOWER_START     = "OnUnitCastEvent",
    UNIT_SPELLCAST_EMPOWER_UPDATE    = "OnUnitCastEvent",
    UNIT_SPELLCAST_EMPOWER_STOP      = "OnUnitCastEvent",
}

local function newInstance(unit)
    return {
        unit        = unit,
        grid        = nil,
        pool        = NS.Pool.NewKeyed(),
        ordered     = {},
        castFilter  = nil,
        cfg         = nil,
        enabled     = false,
        -- migrated from the former self._* module fields:
        truncationWarnedFor = nil,
        lastVisible   = nil,
        lastGateCasting      = nil,
        lastGateInterruptible = nil,
        lastGateAnyCasting    = nil,
        -- The `[Cast]` gate line and the `[IconGrid] [unit] list ...` summary
        -- are change-gated on the console (D.DebugChanged, keyed per unit),
        -- not on fields here: a Clear or a fresh enable re-arms them.
    }
end

function IconGrid:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = newInstance(unit); instances[unit] = inst end
    return inst
end

--- The unit's instance if one exists, or nil. Unlike GetInstance it never
--- creates one: `/kcd diagnostics` reads through it and must build nothing.
function IconGrid:PeekInstance(unit)
    return instances[unit or "target"]
end

-- The per-icon widget system — the Icon prototype, its factory, cooldown /
-- glow rendering and the step-shaped alpha/tint curves — lives in
-- modules/IconGrid_Render.lua, the shared cooldown ticker in IconGrid_Ticker.lua (peeled out for the
-- 1500-LOC cap). The grid geometry (anchor/grow parsing + block placement)
-- lives in modules/IconGrid_Layout.lua; visibility and the glow gate in
-- IconGrid_Visibility.lua; the drag strip in IconGrid_Handle.lua. This file owns
-- the instances, the pool, layout orchestration, lifecycle and message handlers.

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

-- True when the master enable flag is set. Asks NS.MasterEnabled
-- (core/LifecycleSetup.lua, THE one reader of the stored flag), resolved at
-- call time; a load without it reads as enabled, the reader's own default.
local function isEnabled()
    return NS.MasterEnabled == nil or NS.MasterEnabled()
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

-- visibilityMode, shouldBeVisible and ApplyInterruptibilityMask -- the visibility
-- decision and the interruptible mask -- live in modules/IconGrid_Visibility.lua (#25).


-- Resolve the active spec key the same way Database/Cooldowns do: the
-- locale-independent class file token from UnitClass(), plus the NUMERIC
-- specID. Never the localized spec name — see issue #8.
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
    -- The pool half is LibKa0s-Pool-1.0's, keyed by spellID (core/PoolSetup.lua says why the
    -- keying is load-bearing). The library shows what it hands back, so the anchors are cleared
    -- immediately after — the caller anchors it before anything can be drawn.
    local btn = NS.Pool.AcquireKeyed(inst.pool, spellID, function()
        return IconGrid.CreateIconWidget(inst.grid)
    end)
    btn.spellID    = spellID
    btn.cfg        = inst.cfg
    btn.unit       = inst.unit
    btn.instance   = inst
    btn._lastState = nil
    btn._cdObject  = nil
    btn:ClearAllPoints()
    return btn
end

function IconGrid:ReleaseAll(inst)
    -- Hiding and returning every button to the free list is the library's; what runs in the hook
    -- is the part that is about an ICON rather than about a pool. The hook fires while the button
    -- is still shown and the library hides it immediately after, in the same call.
    NS.Pool.ReleaseAllKeyed(inst.pool, function(btn)
        btn:ClearAllPoints()
        btn.spellID    = nil
        btn._lastState = nil
        btn._swipeDone = nil
        btn._cdEnded   = nil
        btn._isPrimary = nil
        -- Pull the icon out of the shared cooldown ticker before
        -- recycling it; the next acquire will re-register if needed.
        self:_UnregisterCdIcon(btn)
        -- Reset cooldown so a stale swipe doesn't reappear on re-acquire.
        if btn.cooldown then btn.cooldown:Clear() end
        if btn.chargesText then btn.chargesText:Hide() end
        if btn.cooldownText then btn.cooldownText:Hide() end
        if btn.StopGlow then btn:StopGlow() end
    end)
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

--- The spellID this list entry contributes, or nil when the entry is missing,
--- disabled, or carries no ID. One statement of the eligibility rule, read
--- once per entry — it used to be written out twice, once in the
--- duplicate-detection arm and once in its else.
local function eligibleSpellID(entry)
    if entry and entry.enabled ~= false and entry.spellID then return entry.spellID end
    return nil
end

--- Can the player actually see this spell in their own spellbook?
--- GetSpellInfo only proves the ID exists in the DB; IsSpellAvailable
--- additionally requires the spell to be actually accessible right now,
--- so an unpicked talent choice-node sibling (e.g. Blood DK's
--- Gorefiend's Grasp ↔ Abomination Limb — both default-listed because
--- either could be picked, but only one is castable) doesn't render.
--- Pet spells (Counter Shot, Spell Lock) are likewise hidden until
--- their pet is summoned.
local function isRenderable(spellID)
    local name      = NS.Compat.GetSpellInfo(spellID)
    local available = NS.Compat.IsSpellAvailable(spellID)
    return name and available
end

--- The one `[IconGrid] [unit] list ...` line a rebuild writes, and only when it
--- differs from the last one this instance wrote (debug-logging-§9, quiet steady
--- state). SPELLS_CHANGED fires several times at login and every `spells`
--- section write rebuilds, so an unchanged list is the common case and says
--- nothing new. `trace` is nil with the flag off: nothing here is built then.
---
--- The line is the missing-icon answer (debug-logging-§8): which spells the
--- grid drew, which the list holds that the player cannot cast right now (an
--- unpicked choice node, a pet spell with no pet), and which duplicate IDs it
--- skipped. `head` names the spec the list was read for, or why none was.
local function logActiveList(inst, head, trace)
    if not trace then return end
    local shown = {}
    for i, btn in ipairs(inst.ordered) do shown[i] = tostring(btn.spellID) end
    local shownList   = table.concat(shown, ",")
    local unknownList = table.concat(trace.unknown, ",")
    local dupList     = table.concat(trace.dup, ",")
    NS.DebugLog.DebugChanged("IconGrid.list." .. inst.unit, "IconGrid", "[%s] list %s: %d icon(s) (%s); %d not castable (%s); %d duplicate spellID(s) skipped (%s)",
        inst.unit, head, #shown, shownList, #trace.unknown, unknownList, #trace.dup, dupList)
end

--- Paint the spell's icon texture, unless it is a 12.0 "secret value".
--- Guarded spells (Mind Freeze etc.) hand back one, and SetTexture rejects
--- them from tainted execution — so skip the call and leave the icon blank
--- rather than erroring out of BuildActiveList partway.
local function applySpellTexture(btn, spellID)
    local tex = NS.Compat.GetSpellTexture(spellID)
    local texSecret = tex ~= nil and NS.Compat.IsSecret(tex)
    if tex and not texSecret then btn.icon:SetTexture(tex) end
end

--- The seed for an icon Cooldowns holds no state for. One shared, never-
--- mutated table: Icon:Apply only reads its state and keeps it as
--- _lastState, so a rebuild allocates no per-icon seed.
local READY_SEED = { ready = true, start = 0, duration = 0 }

--- Acquire, dress and seed one button for `spellID`, appending it to the
--- instance's ordered list.
local function seedIcon(grid, inst, spellID)
    local btn = grid:AcquireIcon(inst, spellID)
    applySpellTexture(btn, spellID)
    btn:ApplyTextConfig(inst.cfg)
    -- Seed from what Cooldowns ALREADY knows. Both modules rebuild on PEW,
    -- SPELLS_CHANGED, TRAIT_CONFIG_UPDATED and a profile change, and
    -- CallbackHandler runs the two handlers in pairs order: when Cooldowns
    -- goes first, its SPELL_STATE lands on the pool this rebuild just
    -- released, and it will not emit again until the spell's state changes.
    -- So pull its current state (read-only, Cooldowns:StateFor) instead of
    -- painting ready. READY_SEED covers the spell Cooldowns does not watch
    -- (yet); Apply{} would read nil-falsy `ready` as "not ready".
    -- force=true: a rebuilt list may hand a pooled button whose
    -- _lastState still matches, and this pass has to repaint it.
    local cd = NS:GetModule("Cooldowns", true)
    btn:Apply((cd and cd:StateFor(spellID)) or READY_SEED, true)
    table.insert(inst.ordered, btn)
end

--- Walk the list into the pool, deduped by spellID. With `trace` (debug on)
--- the skipped IDs are collected for logActiveList's one summary line, in
--- place of the per-duplicate line this used to write (debug-logging-§9).
local function seedList(grid, inst, list, trace)
    local seen = {}
    for _, entry in ipairs(list) do
        local spellID = eligibleSpellID(entry)
        if spellID and seen[spellID] then
            if trace then trace.dup[#trace.dup + 1] = spellID end
        elseif spellID then
            seen[spellID] = true
            -- Hide entries the player can't see in their own spellbook.
            if isRenderable(spellID) then
                seedIcon(grid, inst, spellID)
            elseif trace then
                trace.unknown[#trace.unknown + 1] = spellID
            end
        end
    end
end

function IconGrid:BuildActiveList(inst)
    self:ReleaseAll(inst)

    if not (NS.db and NS.db.profile) then return end

    inst.cfg = NS.Units.Icons(inst.unit)
    -- Built only while the console is listening (debug-logging-§4 zero-alloc).
    local trace = NS.State and NS.State.debug and { unknown = {}, dup = {} } or nil

    local classFile, specName = getActiveSpecKey()
    if not (classFile and specName) then
        return logActiveList(inst, "skipped: class/spec not resolved", trace)
    end
    local head = tostring(classFile) .. "/" .. tostring(specName)

    -- Read-only lookup via Database:GetSpellList — never lazy-creates
    -- a per-spec table, so a class+spec the user has never customized
    -- doesn't pollute the saved-vars with an empty entry.
    local list = NS.Database and NS.Database:GetSpellList(classFile, specName)
    if not list then
        return logActiveList(inst, head .. " (no stored list)", trace)
    end

    -- Dedupe by spellID so pool.active stays strictly 1:1 with id.
    -- A duplicate id (hand-edited saved-vars, profile copy gone wrong,
    -- or a future bug at the mutation layer) would otherwise have
    -- AcquireIcon overwrite pool.active[id] with the second widget,
    -- orphaning the first — which then never receives SPELL_STATE
    -- updates while still being visible. Skip the duplicate; the summary
    -- line names it when debug logging is on (KickCD.State.debug).
    seedList(self, inst, list, trace)
    logActiveList(inst, head, trace)
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

-- ── Layout's pieces (split from one CCN-29 method, GI-KC-12) ────────────────

--- Every layout input, resolved against its default. One table per pass, as the cfg read is.
local function layoutSettings(cfg)
    local primarySize = cfg.primarySize or 48
    return {
        primarySize   = primarySize,
        secondarySize = floor(primarySize * (cfg.secondarySize or 0.7)),
        gap           = cfg.gap or 4,
        anchor        = cfg.anchor or "RIGHT_MIDDLE",
        grow          = cfg.secondaryGrow or "right_down",
        rows          = cfg.secondaryRows or 1,
        cols          = cfg.secondaryCols or 6,
        offX          = cfg.secondaryOffsetX or 0,
        offY          = cfg.secondaryOffsetY or 0,
    }
end

--- Re-bind cfg + appearance/text config every pass, so a style change applies without a rebuild.
--- _isPrimary is stamped BEFORE ApplyTextConfig: that re-runs Apply -> UpdateGlow, which reads it.
local function bindIcons(inst, cfg)
    for i, btn in ipairs(inst.ordered) do
        btn.cfg        = cfg
        btn.unit       = inst.unit
        btn.instance   = inst
        btn._isPrimary = (i == 1)
        btn:Show()
        btn:ApplyAppearance(cfg)
        btn:ApplyTextConfig(cfg)
    end
end

--- Tell dependents (Castbar) the geometry / primary icon may have moved, with the bounding box,
--- so they need not reach back through GetGridFrame / GetPrimaryIcon. primaryIcon is nil for an
--- empty list; subscribers fall back to the public accessor or skip.
local function announceLayout(inst, primary, w, h)
    if not NS.SendMessage then return end
    NS:SendMessage(NS.MSG.GRID_LAYOUT, {
        unit        = inst.unit,
        gridFrame   = inst.grid,
        primaryIcon = primary,
        width       = w,
        height      = h,
    })
end

--- Warn once per (class/spec/cap) tuple when the grid dropped icons, or the user sees a smaller
--- grid than configured with no hint that spells are invisible. The cap in the key re-arms it.
local function warnTruncation(inst, truncated, rows, cols)
    local cap     = (rows or 0) * (cols or 0)
    local clsKey  = "?/?"
    local cls, spc = getActiveSpecKey()
    if cls and spc then clsKey = cls .. "/" .. spc end
    local key = clsKey .. "/" .. tostring(cap)
    if inst.truncationWarnedFor == key then return end
    inst.truncationWarnedFor = key
    if NS.Util and NS.Util.print then
        NS.Util.print(("dropped %d icon(s) past the %d-slot grid for %s — bump rows*cols or remove spells")
            :format(truncated, cap, clsKey))
    end
end

function IconGrid:Layout(inst)
    local grid = inst.grid
    if not grid then return end
    inst.cfg = NS.Units.Icons(inst.unit)
    local cfg = inst.cfg or {}
    local geo = layoutSettings(cfg)
    local ordered = inst.ordered

    bindIcons(inst, cfg)

    -- Empty-list decision: keep the frame visible at primary-icon size so
    -- the user can still drag it to reposition. The frame has no fill so
    -- "empty" reads as a small invisible square at its anchor; that's a
    -- minor cosmetic issue compared to losing the drag handle entirely.
    if #ordered == 0 then
        grid:SetSize(geo.primarySize, geo.primarySize)
        announceLayout(inst, nil, geo.primarySize, geo.primarySize)
        return
    end

    local primary = ordered[1]
    local secondaries = {}
    for i = 2, #ordered do secondaries[i - 1] = ordered[i] end

    local w, h, truncated = IconGrid.LayoutMath.layoutBlock(grid, primary, secondaries,
        geo.primarySize, geo.secondarySize, geo.gap, geo.anchor, geo.grow, geo.rows, geo.cols, geo.offX, geo.offY)
    grid:SetSize(w, h)

    if truncated and truncated > 0 then
        warnTruncation(inst, truncated, geo.rows, geo.cols)
    elseif truncated == 0 or not truncated then
        -- No truncation this pass: clear the dedup key so a future overflow re-warns.
        inst.truncationWarnedFor = nil
    end

    announceLayout(inst, primary, w, h)
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
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("general") end
end

-- The drag strip and IconGrid:ApplyLock live in modules/IconGrid_Handle.lua (#25),
-- which saves through onDragStop above (published as IconGrid._OnDragStop).

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

    -- The strip the player actually grabs, built HERE because it is parented to the grid and there
    -- is nothing to parent it to any earlier. Once per instance: this function returns at its first
    -- line when inst.grid is already set, and DisableUnit hides the grid rather than dropping it,
    -- which hides the strip with it. nil without LibKa0s-Widgets-1.0, which every use guards for.
    inst.handle = IconGrid._BuildHandle(inst, grid)

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
-- visibility, and arm the per-instance UNIT_SPELLCAST_* filter frame.
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

    -- UNIT_SPELLCAST_* registrations ride ONE filter frame per unit
    -- (Util.NewUnitCastFilter) that fires only when the unit IS this
    -- instance's unit. With vanilla RegisterEvent the handler runs for every
    -- party / raid / nameplate cast and early-returns inside; in a 25-player
    -- raid that's thousands of no-op dispatches per minute. Interruptibility
    -- flips mid-cast also come through this path so the
    -- "target_casting_interruptible" mode re-evaluates. The filter is built
    -- once and re-armed on every later enable (events-frames-taint-§1);
    -- DisableUnit / Suspend disarm it, since AceEvent's UnregisterAllEvents
    -- only knows about its own table.
    inst.castFilter = inst.castFilter
        or NS.Util.NewUnitCastFilter(self, unit, ICON_CAST_ROUTES)
    inst.castFilter.Arm()
    inst.enabled = true
    -- The per-unit enable edge (debug-logging-§8, diagnosis). ReconcileUnits
    -- calls this only on a want-vs-live mismatch, so it is one line per edge.
    if NS.State and NS.State.debug then NS.Debug("IconGrid", "[%s] unit enabled", unit) end
end

-- Tear a unit's instance down: disarm its private cast-filter frame and hide
-- its grid. Used by OnDisable and (Phase 3) runtime enable-gating.
function IconGrid:DisableUnit(unit)
    local inst = instances[unit]
    if not inst then return end
    if inst.castFilter then inst.castFilter.Disarm() end
    if inst.grid then inst.grid:Hide() end
    -- Only a live instance going down is an edge; OnDisable walks every unit.
    if inst.enabled and NS.State and NS.State.debug then
        NS.Debug("IconGrid", "[%s] unit disabled", unit)
    end
    inst.enabled = false
    -- The next enable starts a fresh story: its list line prints even when
    -- the list is the one that was showing before.
    if NS.State and NS.State.debug then NS.DebugLog.DebugForget("IconGrid.list." .. unit) end
end

--- Make this module INERT -- for either reason the latch can be down: a perf
--- capture's second arm, or a player who switched the addon off
--- (slash-commands-§7). One teardown, because two would drift.
---
--- The enabled flag is deliberately left alone: it is the user's setting, and
--- Resume rebuilds from the CURRENT enabled set so a unit toggled while the
--- addon was down comes back correctly (performance-§6). What goes away is
--- everything that costs anything — the module's own game events, its bus
--- subscriptions, the private per-unit cast filters (which AceEvent's
--- UnregisterAllEvents cannot reach because it only knows its own table), and
--- the shared cooldown ticker.
---
--- MESSAGES GO TOO, which they did not while this was a perf-only suspend. A
--- subscription is a registration and slash-commands-§7 carves nothing out for the addon's own
--- bus; Resume is called directly by the latch now, so nothing depends on this
--- module hearing a republish it was never going to hear anyway.
function IconGrid:Suspend()
    self:UnregisterAllEvents()
    self:UnregisterAllMessages()
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.castFilter then inst.castFilter.Disarm() end
        if inst and inst.grid then inst.grid:Hide() end
    end
    -- The 0.1s cooldown ticker is module-level and outlives any single
    -- icon, so nothing in the loop above reaches it. Left armed it would wake up
    -- ten times a second on a stood-down addon, which is the survivor slash-commands-§7 calls
    -- the most expensive of the lot.
    self:_StopCdTicker()
end

--- ONE WAY UP, and OnEnable is not it -- this is (slash-commands-§7). The
--- module's whole start-up lives here so the login path and the stand-up path
--- cannot drift, and everything it reads it reads FROM CURRENT STATE rather than
--- from a snapshot taken on the way down (performance-§6).
function IconGrid:Resume()
    IconGrid.BuildCurves()

    -- Internal-message subscriptions. The grid never sends; Ka0s_KickCD_GridLayout
    -- is fired from IconGrid:Layout itself, not via a SendMessage here.
    self:RegisterMessage(NS.MSG.SPELL_STATE,     "OnSpellState")
    self:RegisterMessage(NS.MSG.CONFIG_CHANGED,  "OnConfigChanged")
    self:RegisterMessage(NS.MSG.PROFILE_CHANGED, "OnProfileChanged")
    -- Combat-state fan-out from core/State.lua. We no longer hook
    -- PLAYER_REGEN_* directly -- State owns the only registration so the
    -- flag write and the visibility refresh stay ordered by construction.
    self:RegisterMessage(NS.MSG.COMBAT_STATE,    "OnCombatStateChanged")

    self:RegisterLifecycleEvents()
    -- Every instance was left flagged enabled, so ReconcileUnits would consider
    -- them already reconciled and never re-arm the filters Suspend disarmed.
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled and not (inst.castFilter and inst.castFilter.armed) then
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
    -- While the latch is down the desired state is "nothing runs". Without this
    -- the next `general`/`units` CONFIG_CHANGED would call EnableUnit and
    -- re-arm every unit's cast filter on an addon the player switched
    -- off -- and a settings change is exactly what a player does while it is off.
    if NS.IsDown and NS.IsDown() then return end
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

-- The module's GAME events, as `{ event, method }` rows for NS.RegisterEventList.
-- FILE SCOPE so a stand-up allocates nothing (anti-patterns #43), and one name a
-- future client retires costs only its own row (events-frames-taint-§1).
local LIFECYCLE_EVENTS = {
    -- Spec / login events: rebuild against the new spec's spell list. The
    -- Cooldowns module hooks the same events to refresh its watched set, so
    -- both sides stay in sync.
    { "PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged" },
    { "PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld" },
    -- Talent / spellbook changes within the active spec also flip the
    -- "available" set used by BuildActiveList (choice-node swap, pet
    -- summon/dismiss for pet spells). Rebuild + relayout so the grid
    -- always shows only the spells the player can currently cast.
    { "SPELLS_CHANGED",                "OnSpellsChanged" },
    { "TRAIT_CONFIG_UPDATED",          "OnSpellsChanged" },
    -- The two global unit-change events. These are GLOBAL (no unit filter),
    -- so they register at MODULE level via plain RegisterEvent — NOT through
    -- NewUnitCastFilter (which is for the UNIT_SPELLCAST_* family). Each
    -- handler refreshes only its own unit's instance if that instance is live.
    { "PLAYER_TARGET_CHANGED",         "OnTargetChanged" },
    { "PLAYER_FOCUS_CHANGED",          "OnFocusChanged" },
}

--- The module's GAME-event registrations, split out of OnEnable so a perf
--- Resume can re-arm exactly the same set without re-running the rest of the
--- enable path (rebuilding curves, re-subscribing to messages it never dropped).
--- Registration is idempotent — AceEvent keys on (event, target) — so calling
--- this twice is harmless.
function IconGrid:RegisterLifecycleEvents()
    NS.RegisterEventList(self, LIFECYCLE_EVENTS)
end

function IconGrid:OnEnable()
    -- Combat flag is owned by core/State.lua's bootstrap listener, so
    -- this module no longer seeds it on enable.
    --
    -- The latch may ALREADY be down when AceAddon gets here: NS:OnEnable takes
    -- the stored `disabled` hold, and AceAddon enables the addon before its
    -- modules. Registering here and being torn down a moment later would be a
    -- brief, invisible window in which a disabled addon watched the client.
    if NS.IsDown and NS.IsDown() then return end
    self:Resume()
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
    --   { spellID, ready, isActive, cdObject, chargeCdObject, charges, rebuild }
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
            if btn then btn:Apply(payload, nil, "spellState") end
        end
    end
    -- The parent is the publish this ran inside: Rebuild's (`rebuildEmit`)
    -- or the poll's (`stateEmit`), so a capture reports the mix honestly.
    if __t0 then
        Perf.Note("spellState", debugprofilestop() - __t0,
            payload.rebuild and "rebuildEmit" or "stateEmit")
    end
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
    elseif section == "label" then
        -- The unit label can be turned on or off, moved between the grid and the cast bar, or
        -- re-anchored, and the drag strip hangs above it when it sits on the grid. ApplyLock is
        -- where the strip is re-anchored, so a label edit has to reach it; without this branch
        -- the strip kept the label's previous answer until the next lock toggle (owner, in the
        -- client, 2026-09-26). Every enabled unit, because a linked Focus reads Target's label.
        forEachEnabled(function(inst) self:ApplyLock(inst) end)
    end
end

function IconGrid:OnProfileChanged(_evt, _payload)
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

-- RefreshVisibility, the cast / target / focus handlers and the glow gate
-- (RefreshAllGlows) live in modules/IconGrid_Visibility.lua (#25).

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
IconGrid.InstanceCasting  = instanceCasting
IconGrid.MasterEnabled    = isEnabled
-- VisibilityMode / ShouldBeVisible: modules/IconGrid_Visibility.lua. The siblings'
-- seams (#25): the instance table itself, and the one drag-stop save path.
IconGrid._instances       = instances
IconGrid._OnDragStop      = onDragStop
