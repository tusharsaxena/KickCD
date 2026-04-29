-- modules/IconGrid.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.6, REQUIREMENTS.md FR-2 / FR-8
--
-- Owns one parent frame (KickCDIconGrid) and N child icon widgets, each
-- pooled and reused on rebuild so we never churn frames. The grid is
-- always visible (no enemy-cast-driven show/hide); listens to:
--
--   KickCD_SPELL_STATE       -> route to the matching active icon's :Apply
--   KickCD_CONFIG_CHANGED    -> "icons" relayouts; "spells" rebuilds; "general" re-applies lock
--   KickCD_PROFILE_CHANGED   -> rebuild + re-anchor
--   PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD -> rebuild for the new spec
--
-- This file fires no messages. The grid is the consumer end of the pipeline.

local KickCD   = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local IconGrid = KickCD:NewModule("IconGrid", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Module-local state
-- ---------------------------------------------------------------------------

-- Pool of icon widgets. `active` is keyed by spellID so KickCD_SPELL_STATE
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

-- Standard "crop the WoW icon border" coords. The 0.08 inset removes the
-- ugly built-in 4-px frame on every Blizzard spell icon.
local ICON_TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local floor = math.floor

local function safeUnpackColor(c, fr, fg, fb, fa)
    -- Util.Unpack handles nil with sane defaults but we want module-specific
    -- fallbacks for the cooldown tint, so wrap it.
    if not c then return fr or 1, fg or 1, fb or 1, fa or 1 end
    return KickCD.Util.Unpack(c)
end

-- Resolve the active spec key the same way Database/Cooldowns do:
-- classFile is uppercase ("MAGE"); specName uppercased to match the keys
-- A3 used in defaults/Spells.lua ("ARCANE", "FROST"...).
local function getActiveSpecKey()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return classFile, nil end
    local _, specName = GetSpecializationInfo(specIdx)
    if not specName then return classFile, nil end
    return classFile, string.upper(specName)
end

-- ---------------------------------------------------------------------------
-- Per-icon widget construction
-- ---------------------------------------------------------------------------

-- Methods copied onto each button via Mixin() in CreateIconWidget. We can't
-- setmetatable() a Frame widget — that would clobber the C-side metatable
-- where ClearAllPoints/Show/SetAlpha/etc. live, and they'd become nil calls.
local Icon = {}

local function CreateIconWidget(parent)
    -- A Button (not a Frame) so a future click-to-cast hook is one
    -- :SetAttribute() away. SecureActionButton is intentionally avoided per
    -- TECHNICAL_DESIGN §7.4 (no taint).
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(48, 48)
    btn:EnableMouse(false) -- the grid as a whole handles drag, not individual icons

    -- Spell icon texture. Crop the Blizzard border with TexCoord so square
    -- icons look clean at any size. Using SetAllPoints(btn) lets the texture
    -- track the button's size when we resize it during layout.
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    tex:SetTexCoord(unpack(ICON_TEXCOORDS))
    btn.icon = tex

    -- Cooldown swipe. CooldownFrameTemplate gives us the radial sweep + the
    -- built-in OmniCC integration "for free" — any OmniCC-like addon will
    -- attach its own text overlay to this frame.
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    -- Hide the built-in CooldownFrameTemplate text so it doesn't fight with
    -- our optional cooldown FontString. Users running OmniCC will have the
    -- module re-show this if needed in a future release.
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end
    btn.cooldown = cd

    -- Optional cooldown text overlay (FR-2.6). Created up-front so we can
    -- show/hide it cheaply on config-change without recreating the FontString.
    -- Anchored CENTER for the typical "big number in the middle" look.
    local cdText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    cdText:Hide()
    btn.cooldownText = cdText

    -- Charges badge (FR-2.7) — top-right corner, à la action-bar charges.
    local charges = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    charges:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    charges:Hide()
    btn.chargesText = charges

    -- Ready-pulse highlight stub (deferred per design — created so a future
    -- patch can animate it without touching this file's layout code).
    local hl = btn:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints(btn)
    hl:SetBlendMode("ADD")
    hl:SetColorTexture(1, 1, 1, 0)
    hl:Hide()
    btn.highlight = hl

    -- Per-instance state: cfg points at db.profile.icons during Apply so we
    -- can re-color/re-alpha without re-reading the global db every time.
    -- spellID is set when the icon is acquired and used for fast lookup.
    btn.spellID = nil
    btn.cfg     = nil

    -- Mix in the Icon methods. The button itself is the public widget.
    return Mixin(btn, Icon)
end

-- Apply a KickCD_SPELL_STATE payload to this icon. Code shape mirrors
-- TECHNICAL_DESIGN §3.6 — identical branching and field names so any future
-- merge of additional state (usability, OOR) drops in cleanly.
function Icon:Apply(state)
    local cfg = self.cfg or KickCD.db.profile.icons
    if state and state.ready then
        self.icon:SetVertexColor(1, 1, 1)
        self:SetAlpha(cfg.readyAlpha or 1.0)
        self.cooldown:Hide()
        self.cooldown:SetCooldown(0, 0)
    else
        local r, g, b = safeUnpackColor(cfg.cooldownTint, 1, 0.4, 0.4)
        self.icon:SetVertexColor(r, g, b)
        self:SetAlpha(cfg.cooldownAlpha or 0.4)
        -- 12.0 secret-value safety: gate the swipe on `isActive` (plain bool
        -- from C_Spell.GetSpellCooldown) AND on start/duration being plain.
        -- Cooldown:SetCooldown rejects secret values from tainted execution
        -- ("Secret values are only allowed during untainted execution"), so
        -- when timing is protected we leave the icon desaturated/dimmed
        -- (already done above) without the radial sweep.
        local s, d = state and state.start, state and state.duration
        local sSecret = s ~= nil and issecretvalue and issecretvalue(s)
        local dSecret = d ~= nil and issecretvalue and issecretvalue(d)
        if state and state.isActive and s and d and not (sSecret or dSecret) then
            self.cooldown:SetCooldown(s, d)
            self.cooldown:Show()
        else
            self.cooldown:Hide()
        end
    end

    -- Charges badge (FR-2.7). Hidden unless there's an actual charge count
    -- to show; SetText only when visible to avoid layout thrash. Charges
    -- may be "secret" on guarded spells; skip the badge in that case rather
    -- than erroring on the > 0 comparison.
    local c = state and state.charges
    local cSecret = c ~= nil and issecretvalue and issecretvalue(c)
    if cfg.showCharges and c and not cSecret and c > 0 then
        self.chargesText:SetText(c)
        self.chargesText:Show()
    else
        self.chargesText:Hide()
    end
end

-- Wire the cooldown text on/off for this icon in response to a config
-- change. Kept separate from Apply because the cooldown text follows the
-- swipe driver itself, not the per-state payload.
function Icon:ApplyTextConfig(cfg)
    cfg = cfg or KickCD.db.profile.icons
    if cfg.showCooldownText then
        local mediaFont = nil
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            mediaFont = LSM:Fetch("font", cfg.cooldownTextFont or "")
        end
        local fontPath = mediaFont
        if not fontPath then
            -- Fallback to whatever NumberFontNormal already provides.
            local f = self.cooldownText:GetFont()
            fontPath = f
        end
        if fontPath then
            self.cooldownText:SetFont(fontPath, cfg.cooldownTextSize or 14, "OUTLINE")
        end
        -- Make the swipe drive the text via OmniCC-style handoff: when there's
        -- no third-party display, we let the CooldownFrameTemplate count down
        -- itself by un-hiding its built-in numbers. We do NOT set a per-frame
        -- OnUpdate here — that would burn CPU on every visible icon.
        if self.cooldown.SetHideCountdownNumbers then
            self.cooldown:SetHideCountdownNumbers(false)
        end
    else
        if self.cooldown.SetHideCountdownNumbers then
            self.cooldown:SetHideCountdownNumbers(true)
        end
        self.cooldownText:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------

function IconGrid:AcquireIcon(spellID)
    local btn = table.remove(pool.free)
    if not btn then
        btn = CreateIconWidget(grid)
    end
    btn.spellID = spellID
    btn.cfg     = KickCD.db.profile.icons
    btn:ClearAllPoints()
    btn:Show()
    pool.active[spellID] = btn
    return btn
end

function IconGrid:ReleaseAll()
    for spellID, btn in pairs(pool.active) do
        btn:Hide()
        btn:ClearAllPoints()
        btn.spellID = nil
        -- Reset cooldown so a stale swipe doesn't reappear on re-acquire.
        if btn.cooldown then btn.cooldown:Clear() end
        if btn.chargesText then btn.chargesText:Hide() end
        if btn.cooldownText then btn.cooldownText:Hide() end
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
--     spells are hidden — FR-2.8)
-- First survivor → primary; rest → secondaries.

function IconGrid:BuildActiveList()
    self:ReleaseAll()

    if not (KickCD.db and KickCD.db.profile) then return end

    local classFile, specName = getActiveSpecKey()
    if not (classFile and specName) then return end

    local profileSpells = KickCD.db.profile.spells
    local list = profileSpells
        and profileSpells[classFile]
        and profileSpells[classFile][specName]
    if type(list) ~= "table" then return end

    for _, entry in ipairs(list) do
        if entry and entry.enabled ~= false and entry.spellID then
            -- FR-2.8: hide entries the player can't see in their own spellbook.
            -- Compat.GetSpellInfo returns nil for unknown IDs.
            local name = KickCD.Compat.GetSpellInfo(entry.spellID)
            if name then
                local btn = self:AcquireIcon(entry.spellID)
                local tex = KickCD.Compat.GetSpellTexture(entry.spellID)
                -- Texture may be a 12.0 "secret value" on guarded spells
                -- (Mind Freeze etc.); SetTexture rejects them from tainted
                -- execution, so skip the call and leave the icon blank
                -- rather than erroring out of BuildActiveList partway.
                local texSecret = tex ~= nil and issecretvalue and issecretvalue(tex)
                if tex and not texSecret then btn.icon:SetTexture(tex) end
                btn:ApplyTextConfig(KickCD.db.profile.icons)
                -- Initial state: assume ready until Cooldowns sends a real
                -- KickCD_SPELL_STATE. Apply{} (no payload) treats the icon
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
-- Primary at index 1 sits at the grid's anchor origin and is sized to
-- icons.primarySize. Secondaries are sized to primarySize * secondarySize
-- and tiled in the configured direction. primaryAnchor names where the
-- primary lives relative to its secondaries:
--
--   "left"   primary on the left  → secondaries extend rightward
--   "right"  primary on the right → secondaries extend leftward
--   "top"    primary on top       → secondaries extend downward
--   "bottom" primary on bottom    → secondaries extend upward
--
-- Pixel-floor every offset so we don't end up with sub-pixel positions
-- on fractional UIScale values (which causes a one-pixel blur on icons).

local function layoutHorizontal(primary, secondaries, primarySize, secondarySize, gap, primaryAnchor)
    primary:ClearAllPoints()
    primary:SetSize(primarySize, primarySize)

    -- Secondaries are vertically centered relative to the primary so two
    -- different icon sizes don't look stacked top-edge-aligned.
    local secYOffset = floor((primarySize - secondarySize) / 2)

    if primaryAnchor == "right" then
        primary:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, 0)
        local x = -(primarySize + gap)
        for _, btn in ipairs(secondaries) do
            btn:SetSize(secondarySize, secondarySize)
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", grid, "TOPRIGHT", floor(x), -secYOffset)
            x = x - (secondarySize + gap)
        end
    else
        -- Default ("left"): primary at TOPLEFT, secondaries flow right.
        primary:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
        local x = primarySize + gap
        for _, btn in ipairs(secondaries) do
            btn:SetSize(secondarySize, secondarySize)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT", floor(x), -secYOffset)
            x = x + secondarySize + gap
        end
    end

    -- Bounding box: primary height (always tallest) + total secondary span.
    local secCount = #secondaries
    local secSpan  = secCount > 0 and (secCount * secondarySize + secCount * gap) or 0
    local width    = primarySize + secSpan
    -- Empty-list edge case: still set a non-zero size so the frame can be
    -- dragged in unlock mode and the user can spot where it lives.
    if width <= 0 then width = primarySize end
    return floor(width), primarySize
end

local function layoutVertical(primary, secondaries, primarySize, secondarySize, gap, primaryAnchor)
    primary:ClearAllPoints()
    primary:SetSize(primarySize, primarySize)

    local secXOffset = floor((primarySize - secondarySize) / 2)

    if primaryAnchor == "bottom" then
        primary:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, 0)
        local y = primarySize + gap
        for _, btn in ipairs(secondaries) do
            btn:SetSize(secondarySize, secondarySize)
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", secXOffset, floor(y))
            y = y + secondarySize + gap
        end
    else
        -- Default ("top"): primary at TOPLEFT, secondaries flow downward.
        primary:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
        local y = -(primarySize + gap)
        for _, btn in ipairs(secondaries) do
            btn:SetSize(secondarySize, secondarySize)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT", secXOffset, floor(y))
            y = y - (secondarySize + gap)
        end
    end

    local secCount = #secondaries
    local secSpan  = secCount > 0 and (secCount * secondarySize + secCount * gap) or 0
    local height   = primarySize + secSpan
    if height <= 0 then height = primarySize end
    return primarySize, floor(height)
end

function IconGrid:Layout()
    if not grid then return end
    local cfg = KickCD.db.profile.icons or {}

    local primarySize   = cfg.primarySize or 48
    local secondarySize = floor(primarySize * (cfg.secondarySize or 0.7))
    local gap           = cfg.gap or 4
    local layout        = cfg.layout or "horizontal"
    local primaryAnchor = cfg.primaryAnchor or "left"

    -- Re-bind cfg + text config on every layout pass so changes to color/
    -- alpha/font apply without a full rebuild (FR-6.4: live updates).
    for _, btn in ipairs(ordered) do
        btn.cfg = cfg
        btn:ApplyTextConfig(cfg)
    end

    -- Empty-list decision: keep the frame visible at primary-icon size so
    -- the user can still drag it to reposition. The frame has no fill so
    -- "empty" reads as a small invisible square at its anchor; that's a
    -- minor cosmetic issue compared to losing the drag handle entirely.
    if #ordered == 0 then
        grid:SetSize(primarySize, primarySize)
        return
    end

    local primary = ordered[1]
    local secondaries = {}
    for i = 2, #ordered do secondaries[i - 1] = ordered[i] end

    local w, h
    if layout == "vertical" then
        w, h = layoutVertical(primary, secondaries, primarySize, secondarySize, gap, primaryAnchor)
    else
        w, h = layoutHorizontal(primary, secondaries, primarySize, secondarySize, gap, primaryAnchor)
    end
    grid:SetSize(w, h)
end

-- ---------------------------------------------------------------------------
-- Lock / unlock + drag persistence (FR-8.2, FR-8.4)
-- ---------------------------------------------------------------------------

local function onDragStart(self)
    if KickCD.db and KickCD.db.profile and KickCD.db.profile.locked then return end
    self:StartMoving()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    if KickCD.db and KickCD.db.profile then
        KickCD.db.profile.anchors = KickCD.db.profile.anchors or {}
        KickCD.db.profile.anchors.icons = KickCD.Util.SaveAnchor(self)
    end
end

function IconGrid:ApplyLock()
    if not grid then return end
    local locked = KickCD.db and KickCD.db.profile and KickCD.db.profile.locked
    if locked then
        grid:RegisterForDrag()        -- clear all drag buttons
        grid:EnableMouse(false)
    else
        grid:EnableMouse(true)
        grid:RegisterForDrag("LeftButton")
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
    local anchor = KickCD.db and KickCD.db.profile
        and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
    KickCD.Util.ApplyAnchor(grid, anchor or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })

    grid:SetScript("OnDragStart", onDragStart)
    grid:SetScript("OnDragStop",  onDragStop)

    -- Apply the current locked state. ApplyLock toggles EnableMouse +
    -- RegisterForDrag, which is the only correct way to "release" the mouse
    -- without permanently breaking drag — calling SetMovable(false) on a
    -- locked frame would prevent unlock without a reload.
    self:ApplyLock()

    return grid
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

function IconGrid:OnEnable()
    self:EnsureGrid()
    self:BuildActiveList()
    self:Layout()
    if grid then grid:Show() end

    -- Internal-message subscriptions. The grid is a strict subscriber and
    -- never sends.
    self:RegisterMessage("KickCD_SPELL_STATE",     "OnSpellState")
    self:RegisterMessage("KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("KickCD_PROFILE_CHANGED", "OnProfileChanged")

    -- Spec / login events: rebuild against the new spec's spell list. The
    -- Cooldowns module hooks the same events to refresh its watched set, so
    -- both sides stay in sync.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")
end

function IconGrid:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    if grid then grid:Hide() end
end

-- ---------------------------------------------------------------------------
-- Message / event handlers
-- ---------------------------------------------------------------------------

function IconGrid:OnSpellState(_evt, payload)
    -- Payload contract per §1: { spellID, ready, isActive, start, duration, charges }.
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
        -- when only sizing/colors/alphas changed.
        self:Layout()
        self:ApplyLock()
    elseif section == "spells" then
        -- Spell list changed under us — rebuild from the profile and stay
        -- visible. Lock state is unaffected.
        self:BuildActiveList()
        self:Layout()
    elseif section == "general" then
        -- General-tab edits include the lock toggle and the Reset position
        -- button. Re-apply the anchor in case the latter was used, then
        -- refresh the lock state.
        if grid then
            local anchor = KickCD.db and KickCD.db.profile
                and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
            if anchor then KickCD.Util.ApplyAnchor(grid, anchor) end
        end
        self:ApplyLock()
    end
end

function IconGrid:OnProfileChanged(_evt, payload)
    -- Full reset: re-anchor, rebuild the active list against the new
    -- profile's spell defaults, and re-apply the lock state. Stay visible.
    if grid then
        local anchor = KickCD.db and KickCD.db.profile
            and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
        KickCD.Util.ApplyAnchor(grid, anchor or
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })
    end
    self:BuildActiveList()
    self:Layout()
    self:ApplyLock()
    if grid then grid:Show() end
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

-- Expose the module so the orchestrator's debug slash commands can poke at it.
KickCD.IconGrid = IconGrid
