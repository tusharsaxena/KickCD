-- modules/IconGrid.lua — KickCD v0.1
--
-- Owns one parent frame (KickCDIconGrid) and N child icon widgets, each
-- pooled and reused on rebuild so we never churn frames. Visibility is
-- gated on db.profile.enabled (master enable) AND db.profile.visibility,
-- the addon-wide "General visibility" setting also honored by the cast
-- bar so both panels show / hide together:
--   * "always"          — show whenever master enable is on (v0.1 default)
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
--                          casting (Compat.IsHostileUnitCasting), and
--                          ApplyInterruptibilityMask() then drives the
--                          grid frame's alpha through SetAlphaFromBoolean
--                          (C-side, secret-safe) so uninterruptible casts
--                          read as alpha=0. Friendly / self casts are
--                          excluded by the IsHostileUnitCasting gate.
-- While unlocked, the visibility mode is bypassed so the user can drag
-- the grid into position. Combat / target / cast events drive
-- RefreshVisibility. Listens to:
--
--   KickCD_SPELL_STATE       -> route to the matching active icon's :Apply
--   KickCD_CONFIG_CHANGED    -> "icons" relayouts (zoom/border/font/grid);
--                                "spells" rebuilds;
--                                "general" re-applies lock, scale, alpha,
--                                  master-enable visibility, anchor.
--   KickCD_PROFILE_CHANGED   -> rebuild + re-anchor + reapply general
--   PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD -> rebuild
--
-- Emits:
--   KickCD_GRID_LAYOUT       -> fired at the end of every IconGrid:Layout()
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

-- Set of icons whose cooldownText FontString needs per-tick refresh.
-- Keyed by widget reference (the Icon button itself); the shared
-- ticker iterates pairs(_textIcons) and calls _RenderCooldownText on
-- each. Prior implementation drove the same per-icon work via N
-- per-frame OnUpdate scripts; collapsing to a single ticker cuts the
-- fixed cost to one timer callback regardless of how many cooldowns
-- are visible. _textTicker is the single C_Timer.NewTicker handle —
-- nil while the set is empty (the ticker auto-pauses) and live while
-- at least one icon is registered.
local _textIcons  = {}
local _textTicker

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local floor = math.floor

-- Upper bound on the global cooldown duration. WoW's GCD is haste-modified
-- (typically 1.0–1.5s); 1.6s comfortably covers the unhasted case plus a
-- small fp epsilon. The alpha/tint curves treat any remaining ≤ this value
-- as "GCD only — show as ready" and remaining > this value as "real CD —
-- apply visual states." Sub-second precision isn't critical because the
-- transition is a step, not a gradient. Sourced from KickCD.Const so the
-- value lives in exactly one place across the addon.
local GCD_UPPER = KickCD.Const.GCD_UPPER

-- Step-shaped curves used to derive per-icon alpha and tint without ever
-- comparing the spell's secret-tainted remaining time in Lua scope. Built
-- from cfg.readyAlpha / cfg.cooldownAlpha / cfg.cooldownTint by
-- BuildCurves(); rebuilt whenever those settings change.
--
-- Why curves: cdObject:EvaluateRemainingDuration(curve) runs C-side, takes
-- the (possibly secret) remaining time, and returns a value the Cooldown
-- frame / Frame:SetAlphaFromBoolean / Texture:SetVertexColor accept as
-- arguments without taint errors.
--
-- gcdSuppressCurve drives the cooldown swipe + countdown text alpha when
-- cfg.suppressGCDSwipe is true: 0 below GCD_UPPER (hide), 1 above (show).
-- Applied via SetAlphaFromBoolean(true, curveValue, 0) so the (possibly
-- secret) numeric result rides through Blizzard's C method without
-- needing to be read in Lua.
local alphaCurve, tintCurve, gcdSuppressCurve

-- True when the master enable flag is set. Defaults to true on a fresh
-- profile, so a missing field reads as enabled.
local function isEnabled()
    local profile = KickCD.db and KickCD.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

-- True if the player's target is currently casting or channeling. Reads
-- UnitCastingInfo / UnitChannelInfo and only inspects whether the FIRST
-- return (name) is non-nil — the value itself may be secret in combat for
-- protected casts but a nil-vs-non-nil truthy check does not error
-- (Lua's `not` is safe on secrets; same guarantee `current.name and ...`
-- relies on in modules/Castbar.lua).
local function isTargetCasting()
    if not (UnitExists and UnitExists("target")) then return false end
    local castName    = _G.UnitCastingInfo and _G.UnitCastingInfo("target")
    if castName then return true end
    local channelName = _G.UnitChannelInfo and _G.UnitChannelInfo("target")
    if channelName then return true end
    return false
end

-- Resolve the addon-wide "General visibility" setting. Defaults to
-- "always" if the field is missing. Both this module and
-- modules/Castbar.lua read the same value so they show / hide together
-- — see Castbar:isVisible for the cast bar's read.
local function visibilityMode()
    local profile = KickCD.db and KickCD.db.profile
    return (profile and profile.visibility) or "always"
end

-- Combat state lives in KickCD.State.inCombat (core/State.lua) — a
-- shared, single-owner flag driven off PLAYER_REGEN_DISABLED /
-- PLAYER_REGEN_ENABLED in one place. We deliberately do NOT consult
-- InCombatLockdown() inside shouldBeVisible — that function reports
-- protected-frame lockdown state, which can lag the regen events by
-- a frame. The event-driven flag is the source of truth.

-- Decide whether the grid should be visible right now. Master enable is
-- the gate; visibility mode then narrows that to a subset of states.
-- While unlocked the user is repositioning, so we ignore the visibility
-- mode and always show — otherwise the grid would be invisible exactly
-- when they need to drag it.
local function shouldBeVisible()
    if not isEnabled() then return false end
    local profile = KickCD.db and KickCD.db.profile
    if profile and profile.locked == false then return true end
    local mode = visibilityMode()
    if mode == "in_combat" then
        return KickCD.State.inCombat
    elseif mode == "target_casting" then
        return isTargetCasting()
    elseif mode == "target_casting_interruptible" then
        -- Show whenever a hostile target is casting; the actual
        -- interruptibility filter is applied as an alpha mask in
        -- ApplyInterruptibilityMask (called from RefreshVisibility).
        return KickCD.Compat.IsHostileUnitCasting("target")
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
    local profile = KickCD.db and KickCD.db.profile
    local unlocked = profile and profile.locked == false
    local mode = visibilityMode()
    if not unlocked
       and mode == "target_casting_interruptible"
       and KickCD.Compat.ApplyInterruptibleAlpha
       and KickCD.Compat.ApplyInterruptibleAlpha(grid, "target", 1) then
        return
    end
    grid:SetAlpha(1)
end

local function safeUnpackColor(c, fr, fg, fb, fa)
    -- Util.Unpack handles nil with sane defaults but we want module-specific
    -- fallbacks for the cooldown tint, so wrap it.
    if not c then return fr or 1, fg or 1, fb or 1, fa or 1 end
    return KickCD.Util.Unpack(c)
end

--- (Re)build the alpha/tint curves from db.profile.icons. Called once on
--- enable and again on any "icons" config change. Cheap — these are tiny
--- 4-point curves, recreating them per change is fine.
local function BuildCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return end

    local cfg = (KickCD.db and KickCD.db.profile and KickCD.db.profile.icons) or {}
    local readyAlpha    = cfg.readyAlpha    or 1.0
    local cooldownAlpha = cfg.cooldownAlpha or 0.4
    local r, g, b = safeUnpackColor(cfg.cooldownTint, 1, 0.4, 0.4)

    -- Step from readyAlpha to cooldownAlpha at GCD_UPPER. The 0.001s gap
    -- between adjacent points yields a sharp transition under linear
    -- interpolation (LuaCurveType.Linear is the default).
    alphaCurve = C_CurveUtil.CreateCurve()
    if alphaCurve.SetType and Enum and Enum.LuaCurveType then
        alphaCurve:SetType(Enum.LuaCurveType.Linear)
    end
    alphaCurve:AddPoint(0,             readyAlpha)
    alphaCurve:AddPoint(GCD_UPPER,     readyAlpha)
    alphaCurve:AddPoint(GCD_UPPER + 0.001, cooldownAlpha)
    alphaCurve:AddPoint(3600,          cooldownAlpha)

    -- Step from 0 (hide swipe + text) to 1 (show) at GCD_UPPER. Same
    -- shape as alphaCurve but the values are visibility flags rather
    -- than alphas. The output rides through SetAlphaFromBoolean(true,
    -- value, 0) when cfg.suppressGCDSwipe is on.
    gcdSuppressCurve = C_CurveUtil.CreateCurve()
    if gcdSuppressCurve.SetType and Enum and Enum.LuaCurveType then
        gcdSuppressCurve:SetType(Enum.LuaCurveType.Linear)
    end
    gcdSuppressCurve:AddPoint(0,                 0)
    gcdSuppressCurve:AddPoint(GCD_UPPER,         0)
    gcdSuppressCurve:AddPoint(GCD_UPPER + 0.001, 1)
    gcdSuppressCurve:AddPoint(3600,              1)

    if C_CurveUtil.CreateColorCurve and CreateColor then
        tintCurve = C_CurveUtil.CreateColorCurve()
        if tintCurve.SetType and Enum and Enum.LuaCurveType then
            tintCurve:SetType(Enum.LuaCurveType.Linear)
        end
        tintCurve:AddPoint(0,             CreateColor(1, 1, 1, 1))
        tintCurve:AddPoint(GCD_UPPER,     CreateColor(1, 1, 1, 1))
        tintCurve:AddPoint(GCD_UPPER + 0.001, CreateColor(r, g, b, 1))
        tintCurve:AddPoint(3600,          CreateColor(r, g, b, 1))
    else
        tintCurve = nil
    end
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
    classFile = KickCD.Util.NormalizeClassToken(classFile)
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return classFile, nil end
    local _, specName = GetSpecializationInfo(specIdx)
    if not specName then return classFile, nil end
    return classFile, KickCD.Util.NormalizeSpecToken(specName)
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

    -- Cooldown text overlay (FR-2.6). We drive this FontString ourselves
    -- (via an OnUpdate started from Apply) instead of relying on
    -- CooldownFrameTemplate's built-in countdown numbers — those only
    -- render while the swipe is animating, which means they never appear
    -- for secret-protected interrupts where SetCooldown is skipped.
    -- Owning the text also lets us honor cooldownTextFont/Size/Flags and
    -- inherit the parent button's alpha (so the text dims with cooldownAlpha).
    local cdText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    cdText:Hide()
    btn.cooldownText = cdText

    -- Charges badge (FR-2.7) — top-right corner, à la action-bar charges.
    local charges = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    charges:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    charges:Hide()
    btn.chargesText = charges

    -- Ready glow. A plain child Frame sized to the icon; LibCustomGlow
    -- attaches its own animated children (textures + AnimationGroups)
    -- when StartGlow runs. Frame level is bumped above the cooldown
    -- swipe and the per-icon border textures so the glow always renders
    -- on top.
    local glow = CreateFrame("Frame", nil, btn)
    glow:SetAllPoints(btn)
    glow:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn.glow = glow

    -- Per-instance state: cfg points at db.profile.icons during Apply so we
    -- can re-color/re-alpha without re-reading the global db every time.
    -- spellID is set when the icon is acquired and used for fast lookup.
    btn.spellID = nil
    btn.cfg     = nil

    -- Hover tooltip. Only fires when EnableMouse(true) on the icon, which
    -- IconGrid:ApplyLock toggles based on (locked AND icons.showTooltip).
    -- While unlocked, EnableMouse(false) so the grid frame retains the
    -- mouse for dragging.
    btn:SetScript("OnEnter", function(self)
        local profile = KickCD.db and KickCD.db.profile
        local cfg = profile and profile.icons
        if not (cfg and cfg.showTooltip and self.spellID) then return end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        -- Only dismiss the tooltip if it's the one WE set. If the user
        -- moved the mouse from this icon onto another addon's frame
        -- that owns the tooltip, indiscriminately calling :Hide()
        -- would dismiss someone else's hover.
        if GameTooltip and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    -- Mix in the Icon methods. The button itself is the public widget.
    return Mixin(btn, Icon)
end

-- Drive the cooldownText FontString from a CooldownDuration object.
--
-- 12.0 secret-value protection means we cannot read :GetRemainingDuration()
-- into a Lua local in combat (the value is itself secret-tainted, and
-- tostring / string.format / `<` / `-` all error). The trick is to pass
-- the secret directly into a Blizzard C method as a function argument —
-- argument passing crosses into C without ever holding the value in a
-- tainted Lua local. FontString:SetFormattedText(fmt, arg) does the
-- formatting C-side, so this works:
--
--     fontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())
--
-- We can't conditionally choose the format (no comparison on remaining is
-- legal), so we live with a single fixed format ("%.1f").
--
-- A single module-level C_Timer.NewTicker (see _textTicker below) iterates
-- the registered icons every 0.1s and calls _RenderCooldownText on each.
-- Per-icon OnUpdate scripts were the previous implementation but ran a
-- separate frame-driver per visible cooldown — N icons meant N OnUpdate
-- callbacks per tick. The shared ticker collapses the fixed cost to one.
-- For full spell-level cooldowns we additionally re-poll the plain
-- `isActive` bool from Compat.GetSpellCooldown — SPELL_UPDATE_COOLDOWN
-- can lag the actual cooldown end by a few hundred ms, leaving the text
-- stuck at "0.0" until Cooldowns:Refresh re-emits SPELL_STATE. Because
-- isActive is plain (taint-safe), reading it here is free; on the flip
-- we kill the text + clear the swipe locally and let Cooldowns catch up
-- via its own event handler shortly after.
--
-- For the charge-recharge path (cdObject = state.chargeCdObject,
-- isFullCooldown=false), the spell-level isActive stays false the
-- whole time so we skip that early-exit branch — SPELL_UPDATE_CHARGES
-- handles the recharge-end transition with adequate latency.
function Icon:StartCooldownText(cdObject, isFullCooldown)
    local cfg = self.cfg or KickCD.db.profile.icons
    if not cfg.showCooldownText or not cdObject then
        self:StopCooldownText()
        return
    end
    self._cdObject       = cdObject
    self._isFullCooldown = isFullCooldown and true or false
    -- Initial paint. SetFormattedText handles the secret value via its
    -- C-side argument path; the same pattern is used by the shared
    -- ticker driver.
    self.cooldownText:SetFormattedText("%.1f", cdObject:GetRemainingDuration())
    self.cooldownText:Show()
    -- Register with the module-level ticker (see IconGrid:_TextTickerStart).
    -- Idempotent — re-registering a widget already in the set is a no-op.
    IconGrid:_RegisterTextIcon(self)
end

function Icon:StopCooldownText()
    IconGrid:_UnregisterTextIcon(self)
    self._cdObject = nil
    self.cooldownText:Hide()
end

--- Per-tick render for one icon's cooldown text. Called by the module-
--- level ticker for every registered widget. Mirrors the per-frame work
--- the previous OnUpdate did (full-cooldown plain-bool early-exit +
--- secret-safe SetFormattedText), but the iteration cadence comes from
--- the shared ticker, not a per-icon script.
function Icon:_RenderCooldownText()
    local obj = self._cdObject
    if not obj then
        self:StopCooldownText()
        return
    end
    if self._isFullCooldown then
        local _, _, _, _, isActive = KickCD.Compat.GetSpellCooldown(self.spellID)
        if not isActive then
            self:StopCooldownText()
            if self.cooldown then
                self.cooldown:Hide()
                self.cooldown:Clear()
            end
            return
        end
    end
    self.cooldownText:SetFormattedText("%.1f", obj:GetRemainingDuration())
end

-- ---------------------------------------------------------------------------
-- Ready glow
-- ---------------------------------------------------------------------------
--
-- Glow rendering is delegated to LibCustomGlow-1.0 (vendored under
-- libs/LibCustomGlow-1.0). The library handles the textures, animations,
-- and frame-level management for each effect; we only own the trigger
-- decision and the per-slot config plumbing.
--
-- Trigger values (db.profile.icons.{primary,secondary}GlowTrigger):
--   * "never"                       — glow off
--   * "always"                      — glow whenever the spell is ready
--   * "target_casting"              — only while target is casting (any spell)
--   * "target_casting_interruptible" — only for interruptible target casts
--
-- Type values map 1:1 to LibCustomGlow's four glow effects:
--   * "button"   — LCG.ButtonGlow_Start   (Blizzard rotating rays + spark)
--   * "proc"     — LCG.ProcGlow_Start     (modern Blizzard proc flipbook)
--   * "pixel"    — LCG.PixelGlow_Start    (animated pixel border)
--   * "autocast" — LCG.AutoCastGlow_Start (pet auto-cast sparkles)
--
-- Primary and secondary icons read independent trigger / type / color
-- settings — Layout stamps `_isPrimary` on each icon so UpdateGlow knows
-- which slot it's in.

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
-- Per-frame key passed to LCG so addons sharing a button (e.g. Masque
-- ports) can coexist without each other's glow effects. ButtonGlow_Stop
-- doesn't take a key (only one Blizzard-style glow per frame); the
-- other three Stop fns do.
--
-- Single-key constraint: today every glow trigger / type writes to the
-- same `"KickCD"` slot, so an icon can host at most one KickCD-managed
-- glow at a time. That's the right shape for v0.1's mutually-exclusive
-- triggers (a spell is either ready-and-castable, or it isn't), but a
-- future "interruptible-target-cast PLUS spell-ready" combined glow
-- would need TWO concurrent glows on the same icon — and LCG enforces
-- that two different glow effects targeting the same key cancel each
-- other.
--
-- To extend safely:
--   1. Promote LCG_KEY to a small enum (LCG_KEY_PRIMARY / LCG_KEY_TARGET
--      or similar — pick names that describe the role, not the visual).
--   2. StartGlow / StopGlow take an explicit key argument; the per-slot
--      decision in UpdateGlow picks which key it's writing to.
--   3. ButtonGlow_Start still has no key (one Blizzard-style glow per
--      frame, period) — that constraint is on Blizzard's side, not LCG's,
--      so a combined-glow scenario will need to pick one of the three
--      keyed effects (proc / pixel / autocast) for at least one slot.
-- Until then, leave LCG_KEY single — adding a second key has API churn
-- across StartGlow / StopGlow / UpdateGlow callers, and a real
-- combined-glow scenario hasn't materialised yet.
local LCG_KEY = "KickCD"

local function unpackGlowColor(c)
    if type(c) ~= "table" then return 0.95, 0.95, 0.32, 1 end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

function Icon:StopGlow()
    local g = self.glow
    if not (g and LCG) then return end
    -- Stop every effect kind unconditionally so a stale glow from a
    -- previous type doesn't linger when the user switches types.
    LCG.ButtonGlow_Stop(g)
    LCG.PixelGlow_Stop(g, LCG_KEY)
    LCG.AutoCastGlow_Stop(g, LCG_KEY)
    LCG.ProcGlow_Stop(g, LCG_KEY)
    self._glowKind = nil
    self._glowColor = nil
end

function Icon:StartGlow(kind, color)
    local g = self.glow
    if not (g and LCG) then return end
    local r, gr, b, a = unpackGlowColor(color)
    -- Idempotency gate: UpdateGlow gets called on every SPELL_STATE re-emit
    -- (Cooldowns:Refresh fires for any non-trivially-equal poll, and charged
    -- secondaries hit this path multiple times per second because
    -- C_Spell.GetSpellCooldownDuration returns a fresh handle each call).
    -- Re-issuing Stop+Start unconditionally replays LCG's animIn — most
    -- visibly the ButtonGlow pop — so skip when nothing changed.
    local prev = self._glowColor
    if self._glowKind == kind and prev
       and prev[1] == r and prev[2] == gr and prev[3] == b and prev[4] == a
    then
        return
    end
    local c = { r, gr, b, a }
    -- Stop first so a kind change (e.g. button → pixel) doesn't stack.
    self:StopGlow()
    if kind == "button" then
        LCG.ButtonGlow_Start(g, c)
    elseif kind == "proc" then
        LCG.ProcGlow_Start(g, { color = c, key = LCG_KEY })
    elseif kind == "pixel" then
        -- (frame, color, N, frequency, length, th, xOffset, yOffset, border, key, frameLevel)
        LCG.PixelGlow_Start(g, c, nil, nil, nil, nil, nil, nil, nil, LCG_KEY)
    elseif kind == "autocast" then
        -- (frame, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
        LCG.AutoCastGlow_Start(g, c, nil, nil, nil, 0, 0, LCG_KEY)
    end
    self._glowKind = kind
    self._glowColor = c
end

-- Resolve the trigger condition for this icon's slot. Reuses the same
-- helpers the addon-wide visibility mode uses so triggers and visibility
-- stay in lockstep semantically.
--
-- The "target_casting_interruptible" branch fires for ANY hostile cast
-- — Lua can't decide notInterruptible because it's secret-tainted in
-- 12.0 — and UpdateGlow applies SetAlphaFromBoolean on the glow frame
-- to actually filter out uninterruptible casts (alpha 0). Same pattern
-- as RefreshVisibility / ApplyInterruptibilityMask above.
local function triggerSatisfied(trigger)
    if trigger == "always" then
        return true
    elseif trigger == "target_casting" then
        return isTargetCasting()
    elseif trigger == "target_casting_interruptible" then
        return KickCD.Compat
           and KickCD.Compat.IsHostileUnitCasting
           and KickCD.Compat.IsHostileUnitCasting("target")
           or false
    end
    -- "never" or unknown — glow off.
    return false
end

-- Decide glow visibility from the current state, config, and trigger
-- condition. Called from Apply (state changed), ApplyTextConfig
-- (per-slot config changed via Layout), and IconGrid:RefreshAllGlows
-- (target / cast events fire the trigger reevaluation). state.ready is
-- the canonical "spell can be cast" boolean — see modules/Cooldowns.lua.
--
-- For the "target_casting_interruptible" trigger the glow STARTS for
-- any hostile cast (the trigger satisfied branch above) and the glow
-- frame's alpha is then driven by SetAlphaFromBoolean(notInterruptible,
-- 0, 1) — the C-side path that accepts the secret-tainted flag. So
-- uninterruptible casts run the animation invisibly until the flag
-- flips back (UNIT_SPELLCAST_INTERRUPTIBLE) or the cast ends.
function Icon:UpdateGlow(state)
    local cfg = self.cfg or KickCD.db.profile.icons
    if not cfg then return self:StopGlow() end

    local trigger, kind, color
    if self._isPrimary then
        trigger, kind, color =
            cfg.primaryGlowTrigger,   cfg.primaryGlowType,   cfg.primaryGlowColor
    else
        trigger, kind, color =
            cfg.secondaryGlowTrigger, cfg.secondaryGlowType, cfg.secondaryGlowColor
    end

    local ready = state and state.ready and true or false
    if not ready or not triggerSatisfied(trigger) then
        self:StopGlow()
        return
    end
    self:StartGlow(kind, color)

    -- Per-cast interruptibility filter (alpha mask on the glow frame).
    if trigger == "target_casting_interruptible"
       and self.glow
       and KickCD.Compat.ApplyInterruptibleAlpha
       and KickCD.Compat.ApplyInterruptibleAlpha(self.glow, "target", 1) then
        return
    end
    if self.glow then self.glow:SetAlpha(1) end
end

-- Apply the configured GCD-suppression alpha mask to the cooldown
-- swipe + countdown text using a duration object. When
-- cfg.suppressGCDSwipe is on, the gcdSuppressCurve evaluates to 0 below
-- GCD_UPPER (hide) and 1 above (show). The result is fed through
-- SetAlphaFromBoolean(true, value, 0) — both args may be secret-tainted
-- in combat but the C method handles it.
local function applyGcdSuppressionAlpha(icon, cdObject)
    local cfg = icon.cfg or KickCD.db.profile.icons
    if cfg and cfg.suppressGCDSwipe and gcdSuppressCurve and cdObject
        and icon.cooldown.SetAlphaFromBoolean and icon.cooldownText.SetAlphaFromBoolean
    then
        local visAlpha = cdObject:EvaluateRemainingDuration(gcdSuppressCurve)
        icon.cooldown:SetAlphaFromBoolean(true, visAlpha, 0)
        icon.cooldownText:SetAlphaFromBoolean(true, visAlpha, 0)
    else
        icon.cooldown:SetAlpha(1)
        icon.cooldownText:SetAlpha(1)
    end
end

-- Apply a KickCD_SPELL_STATE payload to this icon. Payload shape:
--   { spellID, ready, isActive, cdObject, chargeCdObject, charges }
--
-- Three branches:
--   1. cdObject non-nil — full spell-level cooldown (real CD or
--      just-GCD). Curves drive the icon-body alpha / tint so a GCD-only
--      window still reads as "ready"; a real CD past the GCD threshold
--      dims and tints the icon. Swipe + text render unconditionally,
--      gated on cfg.suppressGCDSwipe via gcdSuppressCurve.
--   2. chargeCdObject non-nil — partial-charge recharge timer ticking
--      while at least one charge is still available. Render swipe + text
--      WITHOUT mutating alpha / tint — the spell IS castable
--      (state.ready stays true), it just has fewer charges than max.
--   3. otherwise — no cooldown at all. Plain ready
--      visuals; no swipe / text.
--
-- The GCD-vs-real-CD and ready-vs-charging distinctions all happen
-- C-side via curve evaluation; Lua never compares the spell's
-- secret-tainted remaining time directly.
function Icon:Apply(state)
    local cfg = self.cfg or KickCD.db.profile.icons
    -- Cache so ApplyTextConfig can re-render with fresh cfg when the user
    -- toggles showCooldownText (or any other visual state) mid-cooldown
    -- without waiting for the next SPELL_STATE message.
    self._lastState = state

    if state and state.cdObject and alphaCurve then
        -- Branch 1: full cooldown.
        local alpha = state.cdObject:EvaluateRemainingDuration(alphaCurve)
        -- SetAlphaFromBoolean accepts secret values for its alpha args.
        -- Passing `true` as the condition selects the second arg
        -- unconditionally.
        if self.SetAlphaFromBoolean then
            self:SetAlphaFromBoolean(true, alpha, 0)
        else
            self:SetAlpha(alpha)
        end

        if tintCurve then
            local color = state.cdObject:EvaluateRemainingDuration(tintCurve)
            if color and color.GetRGB then
                self.icon:SetVertexColor(color:GetRGB())
            end
        end

        self.cooldown:SetCooldownFromDurationObject(state.cdObject)
        self.cooldown:Show()
        self:StartCooldownText(state.cdObject, true)
        applyGcdSuppressionAlpha(self, state.cdObject)

        if KickCD._debugLog and KickCD.Util and KickCD.Util.print then
            KickCD.Util.print(("IconGrid: apply [%d] active (curve)"):format(
                state.spellID or -1))
        end
    elseif state and state.chargeCdObject then
        -- Branch 2: charge recharge ticking; spell is still castable.
        -- Show swipe + countdown text but keep the icon body at ready
        -- visuals (no alpha dim, no tint shift). state.ready stays true
        -- so the glow trigger keeps firing as configured.
        self:SetAlpha(cfg.readyAlpha or 1.0)
        self.icon:SetVertexColor(1, 1, 1)
        self.cooldown:SetCooldownFromDurationObject(state.chargeCdObject)
        self.cooldown:Show()
        self:StartCooldownText(state.chargeCdObject, false)
        applyGcdSuppressionAlpha(self, state.chargeCdObject)

        if KickCD._debugLog and KickCD.Util and KickCD.Util.print then
            KickCD.Util.print(("IconGrid: apply [%d] charging (curve)"):format(
                state.spellID or -1))
        end
    else
        -- Branch 3: no active cooldown of any kind. Plain ready visuals.
        self:SetAlpha(cfg.readyAlpha or 1.0)
        self.icon:SetVertexColor(1, 1, 1)
        self.cooldown:Hide()
        self.cooldown:Clear()
        self:StopCooldownText()
        if KickCD._debugLog and KickCD.Util and KickCD.Util.print then
            KickCD.Util.print(("IconGrid: apply [%d] ready"):format(
                state and state.spellID or -1))
        end
    end

    -- Ready glow (off when on cooldown, on when castable). Driven from
    -- state.ready so it picks up the same "is castable" decision the
    -- rest of the UI uses; primary vs secondary chooses which schema
    -- entry's type/color applies.
    self:UpdateGlow(state)

    -- Charges badge (FR-2.7). Visibility = "this spell has charges at all",
    -- not "this spell has > 0 charges". Compat.GetSpellCharges returns nil
    -- for spells that don't track charges (regular Mind Freeze etc.) and a
    -- number (0..max) for spells that do, so the truthy check on `c` is
    -- the right gate — and it works for plain numbers, secret-tainted
    -- numbers (in-combat guarded spells), and the nil/no-charges case
    -- alike. SetFormattedText is the canonical secret-safe render path
    -- (the format is interpreted C-side, accepts secret args without
    -- erroring; same pattern as the cooldown text overlay).
    local c = state and state.charges
    if cfg.showCharges and c then
        self.chargesText:SetFormattedText("%d", c)
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

-- Wire the cooldown text font / size / flags on this icon in response to a
-- config change. The built-in CooldownFrameTemplate countdown numbers are
-- always suppressed — we render our own FontString via StartCooldownText
-- so the text displays even when the swipe is hidden (interrupts) and
-- inherits parent alpha for free.
function Icon:ApplyTextConfig(cfg)
    cfg = cfg or KickCD.db.profile.icons
    if self.cooldown.SetHideCountdownNumbers then
        self.cooldown:SetHideCountdownNumbers(true)
    end

    local mediaFont = nil
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        mediaFont = LSM:Fetch("font", cfg.cooldownTextFont or "")
    end
    local fontPath = mediaFont
    if not fontPath then
        fontPath = self.cooldownText:GetFont()
    end
    if fontPath then
        local flags = cfg.cooldownTextFlags or "OUTLINE"
        if flags == "NONE" then flags = "" end
        self.cooldownText:SetFont(fontPath, cfg.cooldownTextSize or 14, flags)
    end

    -- Re-render so a showCooldownText toggle (or any other visual state
    -- change) flowing through Layout takes effect immediately on a
    -- currently-active cooldown, without waiting for the next SPELL_STATE.
    if self._lastState then
        self:Apply(self._lastState)
    else
        self.cooldownText:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Shared cooldown-text ticker
-- ---------------------------------------------------------------------------
--
-- One C_Timer.NewTicker(0.1) drives every visible cooldown's countdown
-- text. Icons register on StartCooldownText and deregister on
-- StopCooldownText (or ReleaseAll); the ticker pauses (Cancel + nil)
-- the moment the set goes empty so the addon costs nothing while no
-- cooldowns are active. Re-arms on the next register call.

local function _tickAllTextIcons()
    -- Snapshot the count and short-circuit if empty — guards against
    -- a race where the ticker fires after the last icon deregistered
    -- but before we got around to cancelling the timer.
    if next(_textIcons) == nil then
        if _textTicker and _textTicker.Cancel then
            _textTicker:Cancel()
        end
        _textTicker = nil
        return
    end
    for icon in pairs(_textIcons) do
        if icon and icon._RenderCooldownText then
            icon:_RenderCooldownText()
        end
    end
end

function IconGrid:_RegisterTextIcon(icon)
    if not icon then return end
    -- Idempotent — re-registering an already-active icon is a no-op.
    if _textIcons[icon] then return end
    _textIcons[icon] = true
    -- Lazy-start the ticker on the first registered icon.
    if not _textTicker and C_Timer and C_Timer.NewTicker then
        _textTicker = C_Timer.NewTicker(0.1, _tickAllTextIcons)
    end
end

function IconGrid:_UnregisterTextIcon(icon)
    if not icon then return end
    if not _textIcons[icon] then return end
    _textIcons[icon] = nil
    -- The ticker itself notices the empty set on its next fire and
    -- self-cancels — see _tickAllTextIcons above. We could cancel
    -- eagerly here too, but lazy cancel keeps the deregister path
    -- O(1) and avoids double-free races if Cancel is non-idempotent
    -- on a given Blizzard build.
end

-- ---------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------

function IconGrid:AcquireIcon(spellID)
    local btn = table.remove(pool.free)
    if not btn then
        btn = CreateIconWidget(grid)
    end
    btn.spellID    = spellID
    btn.cfg        = KickCD.db.profile.icons
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
--     spells are hidden — FR-2.8)
-- First survivor → primary; rest → secondaries.

function IconGrid:BuildActiveList()
    self:ReleaseAll()

    if not (KickCD.db and KickCD.db.profile) then return end

    local classFile, specName = getActiveSpecKey()
    if not (classFile and specName) then return end

    -- Read-only lookup via Database:GetSpellList — never lazy-creates
    -- a per-spec table, so a class+spec the user has never customised
    -- doesn't pollute the saved-vars with an empty entry.
    local list = KickCD.Database and KickCD.Database:GetSpellList(classFile, specName)
    if not list then return end

    -- Dedupe by spellID so pool.active stays strictly 1:1 with id.
    -- A duplicate id (hand-edited saved-vars, profile copy gone wrong,
    -- or a future bug at the mutation layer) would otherwise have
    -- AcquireIcon overwrite pool.active[id] with the second widget,
    -- orphaning the first — which then never receives SPELL_STATE
    -- updates while still being visible. Skip the duplicate; surface
    -- it in the debug log when the user has _debugLog on.
    local _seen = {}
    for _, entry in ipairs(list) do
        if entry and entry.enabled ~= false and entry.spellID and _seen[entry.spellID] then
            if KickCD._debugLog and KickCD.Util and KickCD.Util.print then
                KickCD.Util.print(("IconGrid: duplicate spellID %d in %s/%s — skipping"):format(
                    entry.spellID, classFile, specName))
            end
        elseif entry and entry.enabled ~= false and entry.spellID then
            _seen[entry.spellID] = true
            -- FR-2.8: hide entries the player can't see in their own spellbook.
            -- GetSpellInfo only proves the ID exists in the DB; IsSpellAvailable
            -- additionally requires the spell to be actually accessible right now,
            -- so an unpicked talent choice-node sibling (e.g. Blood DK's
            -- Gorefiend's Grasp ↔ Abomination Limb — both default-listed because
            -- either could be picked, but only one is castable) doesn't render.
            -- Pet spells (Counter Shot, Spell Lock) are likewise hidden until
            -- their pet is summoned.
            local name      = KickCD.Compat.GetSpellInfo(entry.spellID)
            local available = KickCD.Compat.IsSpellAvailable(entry.spellID)
            if name and available then
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

-- Anchor-point parser. Returns (side, align) where side ∈
-- {TOP,BOTTOM,LEFT,RIGHT,CENTER} and align is the perpendicular-axis
-- position on that side (CENTER/LEFT/RIGHT for TOP/BOTTOM,
-- CENTER/TOP/BOTTOM for LEFT/RIGHT, or CENTER/CENTER for the whole-
-- frame CENTER anchor).
--
-- Token compatibility:
--   * Plain "CENTER" → ("CENTER", "CENTER"). The 13th anchor option
--     stacks the secondary block on top of the primary, both centered
--     on the grid frame.
--   * "<SIDE>_MIDDLE" (modern naming used by the dropdowns) is
--     normalized to ("<SIDE>", "CENTER") — the layout math below was
--     written against the legacy "CENTER" alignment token, and
--     normalizing here keeps placeBlock's switch unchanged.
--   * "<SIDE>_CENTER" (legacy saved profiles) is accepted unchanged.
local function parseAnchor(value)
    if value == "CENTER" then return "CENTER", "CENTER" end

    local side, align = (value or ""):match("^(%a+)_(%a+)$")
    if align == "MIDDLE" then align = "CENTER" end

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

    if side == "CENTER" then
        -- Degenerate "stack on top of the primary" anchor: grid
        -- bounding box is whichever of the two is bigger on each axis,
        -- and both primary and the secondary block sit centered in
        -- it. The block visually overlaps the primary — niche, but
        -- it's the natural read of a 13th "CENTER" anchor option in a
        -- dropdown otherwise built around side+alignment edges.
        gridW    = math.max(primarySize, blockW)
        gridH    = math.max(primarySize, blockH)
        primaryX = floor((gridW - primarySize) / 2)
        primaryY = floor((gridH - primarySize) / 2)
        blockX   = floor((gridW - blockW) / 2)
        blockY   = floor((gridH - blockH) / 2)
    elseif side == "TOP" then
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

    -- Visible-count short-circuit: a primary-only grid has no
    -- secondary block, so collapse to a primarySize × primarySize
    -- frame (no gap, no empty block padding). Without this, the
    -- placeBlock math below would add `gap + 0` to each side
    -- creating a phantom strip the user can drag but can't see.
    local visibleCount = #secondaries
    if visibleCount == 0 then
        primary:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
        return primarySize, primarySize
    end

    local side, align         = parseAnchor(anchor)
    local primaryAxis, secAxis = parseGrow(grow)

    -- Fill order: row-major if grow's primary axis is horizontal,
    -- column-major if vertical.
    local rowMajor = (primaryAxis == "right" or primaryAxis == "left")
    -- `c=0` lives at the right edge if either axis is "left"; `r=0` at
    -- the bottom edge if either axis is "up".
    local invertX = (primaryAxis == "left") or (secAxis == "left")
    local invertY = (primaryAxis == "up")   or (secAxis == "up")

    -- "Used" extent — the actual rectangular area the visible icons
    -- occupy, regardless of how much capacity (rows * cols) was
    -- configured. Lets the grid frame's bounding box hug the live
    -- icons so:
    --   * The cast bar's "Auto-size to icon grid" tracks the visible
    --     extent, not the configured capacity.
    --   * The drag handle doesn't include phantom empty slots beyond
    --     the rendered icons.
    -- Wrap math in the per-icon loop below still uses the configured
    -- `cols` / `rows` so multi-row layouts wrap at the user's chosen
    -- column count; only the bounding box and the inverted-axis
    -- mirror collapse onto `usedCols` / `usedRows`.
    local usedCols, usedRows
    if rowMajor then
        usedCols = math.min(visibleCount, cols)
        usedRows = math.ceil(visibleCount / cols)
    else
        usedRows = math.min(visibleCount, rows)
        usedCols = math.ceil(visibleCount / rows)
    end

    local step = secondarySize + gap
    -- Block bounding box is the icons' rectangular extent — not cols*step,
    -- since the trailing gap doesn't belong to the block. (usedCols-1)*step
    -- gives the offset of the last icon's left edge; + secondarySize
    -- closes the right edge.
    local blockW = (usedCols - 1) * step + secondarySize
    local blockH = (usedRows - 1) * step + secondarySize

    local gridW, gridH, primaryX, primaryY, blockX, blockY =
        placeBlock(side, align, primarySize, blockW, blockH, gap)

    primary:SetPoint("TOPLEFT", grid, "TOPLEFT", floor(primaryX), floor(-primaryY))

    local cap = rows * cols
    for i = 1, math.min(visibleCount, cap) do
        local r, c
        if rowMajor then
            r = floor((i - 1) / cols)
            c = (i - 1) - r * cols
        else
            c = floor((i - 1) / rows)
            r = (i - 1) - c * rows
        end
        -- Visual position uses usedCols / usedRows for inverted axes
        -- so the mirror lands inside the shrunk block (icons cluster
        -- against the primary instead of against a phantom far edge).
        -- Non-inverted axes don't need to mirror — `c` and `r` are
        -- already 0-based indices that fit naturally.
        local cVis = invertX and (usedCols - 1 - c) or c
        local rVis = invertY and (usedRows - 1 - r) or r

        local btn = secondaries[i]
        btn:SetSize(secondarySize, secondarySize)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
            floor(blockX + cVis * step + offX),
            floor(-(blockY + rVis * step + offY)))
    end

    -- Hide overflow secondaries — pool keeps them around for next rebuild.
    -- Track the truncation count so the caller can warn the user once
    -- per (class/spec/cap) tuple — silently dropping icons past the
    -- configured grid size used to be an invisible failure mode.
    local truncated = 0
    for i = cap + 1, #secondaries do
        secondaries[i]:Hide()
        truncated = truncated + 1
    end

    -- Add abs(offset) to the grid bounding box so dragging stays sane
    -- when the user has shifted the block off the primary's footprint.
    local width  = gridW + math.abs(offX)
    local height = gridH + math.abs(offY)
    if width  <= 0 then width  = primarySize end
    if height <= 0 then height = primarySize end
    return floor(width), floor(height), truncated
end

function IconGrid:Layout()
    if not grid then return end
    local cfg = KickCD.db.profile.icons or {}

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
        if KickCD.SendMessage then
            -- primaryIcon is nil here (no spells in the active list) —
            -- subscribers fall back to the public accessor or just skip.
            KickCD:SendMessage("KickCD_GRID_LAYOUT", {
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

    local w, h, truncated = layoutBlock(primary, secondaries, primarySize, secondarySize, gap,
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
            if KickCD.Util and KickCD.Util.print then
                KickCD.Util.print(("dropped %d icon(s) past the %d-slot grid for %s — bump rows*cols or remove spells")
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
    if KickCD.SendMessage then
        KickCD:SendMessage("KickCD_GRID_LAYOUT", {
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
    -- Fire the closed bus message so any future "anchor-aware"
    -- subscriber (e.g. a hypothetical Castbar mode that follows the
    -- grid's free-floating position) gets notified. IconGrid's own
    -- OnConfigChanged handler is idempotent on `general` — re-anchoring
    -- to the just-saved value is a no-op — so this doesn't double-work.
    if KickCD.SendMessage then
        KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = "general" })
    end
end

function IconGrid:ApplyLock()
    if not grid then return end
    local profile  = KickCD.db and KickCD.db.profile
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
    -- Combat flag is owned by core/State.lua's bootstrap listener, so
    -- this module no longer seeds it on enable.
    self:EnsureGrid()
    BuildCurves()
    self:BuildActiveList()
    self:Layout()
    self:RefreshVisibility()

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
    self:RegisterEvent("PLAYER_REGEN_DISABLED",         "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",          "OnRegenEnabled")
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START",          "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_STOP",           "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED",         "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",    "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START",  "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "OnTargetCastEvent")
    -- Interruptibility flips mid-cast (boss casts that toggle immunity
    -- via an aura, etc.) need to retrigger the visibility check for
    -- the "target_casting_interruptible" mode.
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE",      "OnTargetCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE",  "OnTargetCastEvent")
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
        BuildCurves()  -- readyAlpha/cooldownAlpha/cooldownTint may have moved
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
            local anchor = KickCD.db and KickCD.db.profile
                and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
            if anchor then KickCD.Util.ApplyAnchor(grid, anchor) end
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
        local anchor = KickCD.db and KickCD.db.profile
            and KickCD.db.profile.anchors and KickCD.db.profile.anchors.icons
        KickCD.Util.ApplyAnchor(grid, anchor or
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 })
    end
    BuildCurves()
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
    if shouldBeVisible() then
        grid:Show()
        ApplyInterruptibilityMask()
    else
        grid:Hide()
    end
end

--- UNIT_SPELLCAST_* events fire for any unit. We only care about the
--- "target" unit because that's what the "target_casting" visibility
--- mode + the glow trigger key off of. Filter here so RefreshVisibility
--- and RefreshAllGlows don't re-run on every player / nameplate cast.
function IconGrid:OnTargetCastEvent(_evt, unit)
    if unit ~= "target" then return end
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
    -- Compat.IsHostileUnitCasting handles existence/can-attack gates
    -- and existing-channel checks; we only need to layer interruptibility
    -- on top.
    local hostileCasting = KickCD.Compat
        and KickCD.Compat.IsHostileUnitCasting
        and KickCD.Compat.IsHostileUnitCasting("target") or false
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
        if issecretvalue and issecretvalue(notInterruptible) then
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

    for _, btn in ipairs(ordered) do
        if btn.UpdateGlow then btn:UpdateGlow(btn._lastState) end
    end
end

--- Re-evaluate visibility on combat-state transitions. The flag itself
--- is owned by core/State.lua's bootstrap listener; this handler runs
--- only for its side effect (the visibility refresh).
function IconGrid:OnRegenDisabled()
    self:RefreshVisibility()
end

function IconGrid:OnRegenEnabled()
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

-- Expose the module so the orchestrator's debug slash commands can poke at it.
KickCD.IconGrid = IconGrid
