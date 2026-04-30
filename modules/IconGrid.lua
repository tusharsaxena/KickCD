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
--                          the cast to be interruptible (friendly /
--                          self / flagged-uninterruptible suppress).
--                          Compat.IsCastingInterruptible handles the
--                          secret-value taint on notInterruptible.
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
--                               button reference settle. Payload is {}.

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

-- Upper bound on the global cooldown duration. WoW's GCD is haste-modified
-- (typically 1.0–1.5s); 1.6s comfortably covers the unhasted case plus a
-- small fp epsilon. The alpha/tint curves treat any remaining ≤ this value
-- as "GCD only — show as ready" and remaining > this value as "real CD —
-- apply visual states." Sub-second precision isn't critical because the
-- transition is a step, not a gradient.
local GCD_UPPER = 1.6

-- Step-shaped curves used to derive per-icon alpha and tint without ever
-- comparing the spell's secret-tainted remaining time in Lua scope. Built
-- from cfg.readyAlpha / cfg.cooldownAlpha / cfg.cooldownTint by
-- BuildCurves(); rebuilt whenever those settings change.
--
-- Why curves: cdObject:EvaluateRemainingDuration(curve) runs C-side, takes
-- the (possibly secret) remaining time, and returns a value the Cooldown
-- frame / Frame:SetAlphaFromBoolean / Texture:SetVertexColor accept as
-- arguments without taint errors. This is FIH's cdReadyCurve pattern,
-- generalized to KickCD's per-state visuals.
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
-- "always" so an unmigrated profile keeps the v0.1 behavior. Both this
-- module and modules/Castbar.lua read the same value so they show /
-- hide together — see Castbar:isVisible for the cast bar's read.
local function visibilityMode()
    local profile = KickCD.db and KickCD.db.profile
    return (profile and profile.visibility) or "always"
end

-- Combat state tracked via PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.
-- We deliberately do NOT consult InCombatLockdown() inside shouldBeVisible
-- — that function reports protected-frame lockdown state, which can lag
-- the PLAYER_REGEN_DISABLED event by a frame. Reading it on the event
-- itself returns false if combat just started, leaving the grid hidden
-- in "in_combat" mode until the next config change. The event-driven
-- flag is the source of truth.
local _inCombat = false

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
        return _inCombat
    elseif mode == "target_casting" then
        return isTargetCasting()
    elseif mode == "target_casting_interruptible" then
        return KickCD.Compat.IsCastingInterruptible("target")
    end
    return true  -- "always"
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
    -- between adjacent points is FIH's trick for a sharp transition under
    -- linear interpolation (LuaCurveType.Linear is the default).
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
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Mix in the Icon methods. The button itself is the public widget.
    return Mixin(btn, Icon)
end

-- Drive the cooldownText FontString from a CooldownDuration object.
--
-- 12.0 secret-value protection means we cannot read :GetRemainingDuration()
-- into a Lua local in combat (the value is itself secret-tainted, and
-- tostring / string.format / `<` / `-` all error). The trick FIH uses is to
-- pass the secret directly into a Blizzard C method as a function argument
-- — argument passing crosses into C without ever holding the value in a
-- tainted Lua local. FontString:SetFormattedText(fmt, arg) does the
-- formatting C-side, so this works:
--
--     fontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())
--
-- We can't conditionally choose the format (no comparison on remaining is
-- legal), so we live with a single fixed format. "%.1f" is the same shape
-- FIH uses for its timer.
--
-- The OnUpdate calls SetFormattedText every ~0.1s. For full spell-level
-- cooldowns we additionally re-poll the plain `isActive` bool from
-- Compat.GetSpellCooldown — SPELL_UPDATE_COOLDOWN can lag the actual
-- cooldown end by a few hundred ms, leaving the text stuck at "0.0"
-- until Cooldowns:Refresh re-emits SPELL_STATE. Because isActive is
-- plain (taint-safe), reading it here is free; on the flip we kill the
-- text + clear the swipe locally and let Cooldowns catch up via its
-- own event handler shortly after.
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
    self._cdAcc          = 0
    self._isFullCooldown = isFullCooldown and true or false
    -- Initial paint. SetFormattedText handles the secret value via its
    -- C-side argument path; the same pattern works inside OnUpdate.
    self.cooldownText:SetFormattedText("%.1f", cdObject:GetRemainingDuration())
    self.cooldownText:Show()
    self:SetScript("OnUpdate", function(s, elapsed)
        s._cdAcc = (s._cdAcc or 0) + elapsed
        if s._cdAcc < 0.1 then return end
        s._cdAcc = 0
        local obj = s._cdObject
        if not obj then
            s:StopCooldownText()
            return
        end
        if s._isFullCooldown then
            local _, _, _, _, isActive = KickCD.Compat.GetSpellCooldown(s.spellID)
            if not isActive then
                s:StopCooldownText()
                if s.cooldown then
                    s.cooldown:Hide()
                    s.cooldown:Clear()
                end
                return
            end
        end
        s.cooldownText:SetFormattedText("%.1f", obj:GetRemainingDuration())
    end)
end

function Icon:StopCooldownText()
    self:SetScript("OnUpdate", nil)
    self._cdObject = nil
    self.cooldownText:Hide()
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
end

function Icon:StartGlow(kind, color)
    local g = self.glow
    if not (g and LCG) then return end
    local r, gr, b, a = unpackGlowColor(color)
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
end

-- Resolve the trigger condition for this icon's slot. Reuses the same
-- helpers the addon-wide visibility mode uses so triggers and visibility
-- stay in lockstep semantically.
local function triggerSatisfied(trigger)
    if trigger == "always" then
        return true
    elseif trigger == "target_casting" then
        return isTargetCasting()
    elseif trigger == "target_casting_interruptible" then
        return KickCD.Compat
           and KickCD.Compat.IsCastingInterruptible
           and KickCD.Compat.IsCastingInterruptible("target")
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
        -- SetAlphaFromBoolean accepts secret values for its alpha args
        -- (FIH uses the same pattern for its cdReadyCurve). Passing `true`
        -- as the condition selects the second arg unconditionally.
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
        btn:SetScript("OnUpdate", nil)
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
            KickCD:SendMessage("KickCD_GRID_LAYOUT", {})
        end
        return
    end

    local primary = ordered[1]
    local secondaries = {}
    for i = 2, #ordered do secondaries[i - 1] = ordered[i] end

    local w, h = layoutBlock(primary, secondaries, primarySize, secondarySize, gap,
                             anchor, grow, rows, cols, offX, offY)
    grid:SetSize(w, h)

    -- Notify dependent modules (Castbar) that grid geometry / primary icon
    -- reference may have changed.
    if KickCD.SendMessage then
        KickCD:SendMessage("KickCD_GRID_LAYOUT", {})
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
    -- Seed the combat flag from InCombatLockdown — at module-enable time
    -- it's reliable (no race with PLAYER_REGEN_DISABLED). After this we
    -- only mutate it via the regen events.
    _inCombat = (InCombatLockdown and InCombatLockdown()) or false

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
function IconGrid:RefreshVisibility()
    if not grid then return end
    if shouldBeVisible() then grid:Show() else grid:Hide() end
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
function IconGrid:RefreshAllGlows()
    for _, btn in ipairs(ordered) do
        if btn.UpdateGlow then btn:UpdateGlow(btn._lastState) end
    end
end

--- Maintain the event-driven combat flag. Reading InCombatLockdown() at
--- the moment PLAYER_REGEN_DISABLED fires can return false (the lockdown
--- state lags the event by a frame), which left the grid hidden in
--- "in_combat" mode until the next config change. The flag is the
--- source of truth — flip it on the event itself.
function IconGrid:OnRegenDisabled()
    _inCombat = true
    self:RefreshVisibility()
end

function IconGrid:OnRegenEnabled()
    _inCombat = false
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
