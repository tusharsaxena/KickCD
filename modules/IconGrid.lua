-- modules/IconGrid.lua — KickCD v0.1
--
-- Owns one parent frame (KickCDIconGrid) and N child icon widgets, each
-- pooled and reused on rebuild so we never churn frames. Visibility is
-- gated on db.profile.enabled (master enable); when enabled, the grid
-- is persistently visible (no enemy-cast-driven show/hide). Listens to:
--
--   KickCD_SPELL_STATE       -> route to the matching active icon's :Apply
--   KickCD_CONFIG_CHANGED    -> "icons" relayouts (zoom/border/font/grid);
--                                "spells" rebuilds;
--                                "general" re-applies lock, scale, alpha,
--                                  master-enable visibility, anchor.
--   KickCD_PROFILE_CHANGED   -> rebuild + re-anchor + reapply general
--   PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD -> rebuild
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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local floor = math.floor

-- True when the master enable flag is set. Defaults to true on a fresh
-- profile, so a missing field reads as enabled.
local function isEnabled()
    local profile = KickCD.db and KickCD.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

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

    -- Spell icon texture. The TexCoord crop is applied by ApplyAppearance
    -- from cfg.zoom; we leave it untouched here so the user-configurable
    -- value is the single source of truth.
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    btn.icon = tex

    -- Per-icon border. Four edge textures on a high OVERLAY sublayer so
    -- they paint over the icon texture; the cooldown swipe lives on a
    -- separate child frame and so isn't affected by this draw layer.
    -- Using textures rather than a BackdropTemplate avoids cross-version
    -- backdrop quirks.
    local function makeEdge()
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        t:Hide()
        return t
    end
    btn.borderTop    = makeEdge()
    btn.borderBottom = makeEdge()
    btn.borderLeft   = makeEdge()
    btn.borderRight  = makeEdge()

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

-- Apply zoom (icon TexCoord crop) and border (visibility / color /
-- thickness). Called from Layout() so any /kcd set or panel change
-- takes effect on the next layout pass without a full rebuild.
function Icon:ApplyAppearance(cfg)
    cfg = cfg or KickCD.db.profile.icons
    local z = cfg.zoom or 0.08
    self.icon:SetTexCoord(z, 1 - z, z, 1 - z)

    local show = cfg.borderShow and true or false
    if show then
        local size = cfg.borderSize or 1
        if size < 1 then size = 1 end
        local r, g, b, a = safeUnpackColor(cfg.borderColor, 0, 0, 0, 1)

        for _, t in ipairs({
            self.borderTop, self.borderBottom,
            self.borderLeft, self.borderRight,
        }) do
            t:SetColorTexture(r, g, b, a)
            t:ClearAllPoints()
            t:Show()
        end

        -- Top / bottom span the full width; left / right inset between them
        -- so the corners overlap correctly and we don't double-paint pixels.
        self.borderTop:SetPoint("TOPLEFT",  self, "TOPLEFT",  0, 0)
        self.borderTop:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        self.borderTop:SetHeight(size)

        self.borderBottom:SetPoint("BOTTOMLEFT",  self, "BOTTOMLEFT",  0, 0)
        self.borderBottom:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        self.borderBottom:SetHeight(size)

        self.borderLeft:SetPoint("TOPLEFT",    self, "TOPLEFT",    0, -size)
        self.borderLeft:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0,  size)
        self.borderLeft:SetWidth(size)

        self.borderRight:SetPoint("TOPRIGHT",    self, "TOPRIGHT",    0, -size)
        self.borderRight:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0,  size)
        self.borderRight:SetWidth(size)
    else
        self.borderTop:Hide()
        self.borderBottom:Hide()
        self.borderLeft:Hide()
        self.borderRight:Hide()
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
            local flags = cfg.cooldownTextFlags or "OUTLINE"
            -- SetFont expects an empty string (not "NONE") to mean "no flags".
            if flags == "NONE" then flags = "" end
            self.cooldownText:SetFont(fontPath, cfg.cooldownTextSize or 14, flags)
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

-- Anchor-point parser. Returns (side, align) where side ∈ {TOP,BOTTOM,LEFT,RIGHT}
-- and align is the second word (CENTER, LEFT, RIGHT, TOP, BOTTOM as applicable).
local function parseAnchor(value)
    local side, align = (value or ""):match("^(%a+)_(%a+)$")
    if side == "TOP" or side == "BOTTOM" then
        if align == "CENTER" or align == "LEFT" or align == "RIGHT" then
            return side, align
        end
    elseif side == "LEFT" or side == "RIGHT" then
        if align == "CENTER" or align == "TOP" or align == "BOTTOM" then
            return side, align
        end
    end
    return "RIGHT", "CENTER"
end

-- Grow-direction parser. Returns (primaryAxis, secondaryAxis) where
-- primary is the in-line fill direction and secondary is the wrap.
local function parseGrow(value)
    local primary, secondary = (value or ""):match("^(%a+)_(%a+)$")
    local horiz = { right = true, left = true }
    local vert  = { down  = true, up   = true }
    if not ((horiz[primary] and vert[secondary]) or
            (vert[primary]  and horiz[secondary])) then
        primary, secondary = "right", "down"
    end
    return primary, secondary
end

-- Compute the secondaries block's TOPLEFT relative to the grid frame's
-- TOPLEFT, plus the primary's TOPLEFT and the grid frame's full
-- bounding-box size — all in screen-pixel space (y grows downward; the
-- caller flips the sign when handing the value to SetPoint).
local function placeBlock(side, align, primarySize, blockW, blockH, gap)
    local gridW, gridH, primaryX, primaryY, blockX, blockY

    if side == "TOP" then
        gridW = math.max(primarySize, blockW)
        gridH = blockH + gap + primarySize
        blockY    = 0
        primaryY  = blockH + gap
        if align == "CENTER" then
            primaryX = floor((gridW - primarySize) / 2)
            blockX   = floor((gridW - blockW) / 2)
        elseif align == "LEFT" then
            primaryX, blockX = 0, 0
        else  -- RIGHT
            primaryX = gridW - primarySize
            blockX   = gridW - blockW
        end
    elseif side == "BOTTOM" then
        gridW = math.max(primarySize, blockW)
        gridH = primarySize + gap + blockH
        primaryY = 0
        blockY   = primarySize + gap
        if align == "CENTER" then
            primaryX = floor((gridW - primarySize) / 2)
            blockX   = floor((gridW - blockW) / 2)
        elseif align == "LEFT" then
            primaryX, blockX = 0, 0
        else  -- RIGHT
            primaryX = gridW - primarySize
            blockX   = gridW - blockW
        end
    elseif side == "LEFT" then
        gridW = blockW + gap + primarySize
        gridH = math.max(primarySize, blockH)
        blockX    = 0
        primaryX  = blockW + gap
        if align == "CENTER" then
            primaryY = floor((gridH - primarySize) / 2)
            blockY   = floor((gridH - blockH) / 2)
        elseif align == "TOP" then
            primaryY, blockY = 0, 0
        else  -- BOTTOM
            primaryY = gridH - primarySize
            blockY   = gridH - blockH
        end
    else  -- RIGHT
        gridW = primarySize + gap + blockW
        gridH = math.max(primarySize, blockH)
        primaryX = 0
        blockX   = primarySize + gap
        if align == "CENTER" then
            primaryY = floor((gridH - primarySize) / 2)
            blockY   = floor((gridH - blockH) / 2)
        elseif align == "TOP" then
            primaryY, blockY = 0, 0
        else  -- BOTTOM
            primaryY = gridH - primarySize
            blockY   = gridH - blockH
        end
    end

    return gridW, gridH, primaryX, primaryY, blockX, blockY
end

local function layoutBlock(primary, secondaries, primarySize, secondarySize, gap,
                           anchor, grow, rows, cols, offX, offY)
    primary:ClearAllPoints()
    primary:SetSize(primarySize, primarySize)

    local side, align         = parseAnchor(anchor)
    local primaryAxis, secAxis = parseGrow(grow)

    local step = secondarySize + gap
    -- Block bounding box is the icons' rectangular extent — not cols*step,
    -- since the trailing gap doesn't belong to the block. (cols-1)*step
    -- gives the offset of the last icon's left edge; + secondarySize
    -- closes the right edge.
    local blockW = (cols - 1) * step + secondarySize
    local blockH = (rows - 1) * step + secondarySize

    local gridW, gridH, primaryX, primaryY, blockX, blockY =
        placeBlock(side, align, primarySize, blockW, blockH, gap)

    primary:SetPoint("TOPLEFT", grid, "TOPLEFT", floor(primaryX), floor(-primaryY))

    -- Fill order: row-major if grow's primary axis is horizontal,
    -- column-major if vertical.
    local rowMajor = (primaryAxis == "right" or primaryAxis == "left")
    -- `c=0` lives at the right edge if either axis is "left"; `r=0` at
    -- the bottom edge if either axis is "up".
    local invertX = (primaryAxis == "left") or (secAxis == "left")
    local invertY = (primaryAxis == "up")   or (secAxis == "up")

    local cap = rows * cols
    for i = 1, math.min(#secondaries, cap) do
        local r, c
        if rowMajor then
            r = floor((i - 1) / cols)
            c = (i - 1) - r * cols
        else
            c = floor((i - 1) / rows)
            r = (i - 1) - c * rows
        end
        local cVis = invertX and (cols - 1 - c) or c
        local rVis = invertY and (rows - 1 - r) or r

        local btn = secondaries[i]
        btn:SetSize(secondarySize, secondarySize)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
            floor(blockX + cVis * step + offX),
            floor(-(blockY + rVis * step + offY)))
    end

    -- Hide overflow secondaries — pool keeps them around for next rebuild.
    for i = cap + 1, #secondaries do
        secondaries[i]:Hide()
    end

    -- Add abs(offset) to the grid bounding box so dragging stays sane
    -- when the user has shifted the block off the primary's footprint.
    local width  = gridW + math.abs(offX)
    local height = gridH + math.abs(offY)
    if width  <= 0 then width  = primarySize end
    if height <= 0 then height = primarySize end
    return floor(width), floor(height)
end

function IconGrid:Layout()
    if not grid then return end
    local cfg = KickCD.db.profile.icons or {}

    local primarySize   = cfg.primarySize or 48
    local secondarySize = floor(primarySize * (cfg.secondarySize or 0.7))
    local gap           = cfg.gap or 4
    local anchor        = cfg.anchor or "RIGHT_CENTER"
    local grow          = cfg.secondaryGrow or "right_down"
    local rows          = cfg.secondaryRows or 1
    local cols          = cfg.secondaryCols or 6
    local offX          = cfg.secondaryOffsetX or 0
    local offY          = cfg.secondaryOffsetY or 0

    -- Re-bind cfg + text/appearance config on every layout pass so changes
    -- to color/alpha/font/zoom/border apply without a full rebuild.
    for _, btn in ipairs(ordered) do
        btn.cfg = cfg
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
        return
    end

    local primary = ordered[1]
    local secondaries = {}
    for i = 2, #ordered do secondaries[i - 1] = ordered[i] end

    local w, h = layoutBlock(primary, secondaries, primarySize, secondarySize, gap,
                             anchor, grow, rows, cols, offX, offY)
    grid:SetSize(w, h)
end

-- Apply general-tab visual settings (scale, alpha) to the parent frame.
-- Per-icon alpha continues to be set by Icon:Apply (cfg.readyAlpha /
-- cfg.cooldownAlpha) and multiplies naturally with the parent's alpha.
function IconGrid:ApplyGeneral()
    if not grid then return end
    local profile = KickCD.db and KickCD.db.profile
    if not profile then return end
    grid:SetScale(profile.scale or 1.0)
    grid:SetAlpha(profile.alpha or 1.0)
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
    self:ApplyGeneral()

    return grid
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

function IconGrid:OnEnable()
    self:EnsureGrid()
    self:BuildActiveList()
    self:Layout()
    if grid then
        if isEnabled() then grid:Show() else grid:Hide() end
    end

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
        -- when only sizing/colors/alphas changed. Layout() also calls
        -- ApplyAppearance/ApplyTextConfig per-icon so zoom/border/font
        -- changes flow through the same path.
        self:Layout()
        self:ApplyLock()
    elseif section == "spells" then
        -- Spell list changed under us — rebuild from the profile and stay
        -- visible. Lock state is unaffected.
        self:BuildActiveList()
        self:Layout()
    elseif section == "general" then
        -- General-tab edits include the master enable, the lock toggle,
        -- master scale / alpha, and the Reset position button. Apply
        -- scale/alpha unconditionally; toggle visibility on the master
        -- enable.
        if grid then
            local anchor = KickCD.db and KickCD.db.profile
                and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
            if anchor then KickCD.Util.ApplyAnchor(grid, anchor) end
            self:ApplyGeneral()
            if isEnabled() then grid:Show() else grid:Hide() end
        end
        self:ApplyLock()
    end
end

function IconGrid:OnProfileChanged(_evt, payload)
    -- Full reset: re-anchor, rebuild the active list against the new
    -- profile's spell defaults, and re-apply the lock + general state.
    if grid then
        local anchor = KickCD.db and KickCD.db.profile
            and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
        KickCD.Util.ApplyAnchor(grid, anchor or
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })
    end
    self:BuildActiveList()
    self:Layout()
    self:ApplyLock()
    self:ApplyGeneral()
    if grid then
        if isEnabled() then grid:Show() else grid:Hide() end
    end
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
