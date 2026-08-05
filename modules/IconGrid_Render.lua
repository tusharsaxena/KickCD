-- modules/IconGrid_Render.lua — per-icon widget rendering (peeled from IconGrid.lua, KCD-05)
--
-- The icon-widget prototype (Icon), its factory (CreateIconWidget), the cooldown-
-- swipe / countdown-text / ready-glow rendering, the step-shaped per-unit
-- alpha/tint curves,
-- and the shared cooldown-text ticker — everything that draws a single icon. Core
-- (IconGrid.lua) owns the per-unit instances, pool, layout orchestration,
-- visibility, and message handlers; it calls IconGrid.CreateIconWidget /
-- IconGrid.BuildCurves (exposed at the bottom). The one reverse dependency
-- (the glow trigger needs "is this unit casting") goes through the instance
-- stamped on each icon (btn.instance / btn.unit) — inst.isCasting() is the
-- per-instance resolver published by core.

local addonName, NS = ...
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf
local IconGrid = NS:GetModule("IconGrid")

local GCD_UPPER = NS.Const.GCD_UPPER

-- Step-shaped curves (assigned by BuildCurves) read by Icon:Apply /
-- applyGcdSuppressionAlpha. Render-local state, formerly file-locals in IconGrid.lua.
--
-- The alpha and tint curves are PER UNIT (`_curves[unit] = {alpha, tint, sig}`):
-- their control-point values come from that unit's resolved appearance, so an
-- unlinked focus with its own readyAlpha / cooldownAlpha / cooldownTint renders
-- with those values instead of silently inheriting target's. A linked focus
-- resolves to target's table via NS.Units.Icons and simply builds an identical
-- pair — link-awareness lives in NS.Units, not here.
--
-- gcdSuppressCurve stays module-level and is built once: its control points are
-- the fixed flags 0 and 1 stepping at GCD_UPPER, with nothing config-derived to
-- vary per unit.
local _curves = {}
local gcdSuppressCurve

-- Returned by curvesFor when a unit has no curves yet, so every caller can
-- read `.alpha` / `.tint` unguarded. Shared and never written to.
local EMPTY_CURVES = {}

-- Cooldown-text ticker: the set of icons needing a per-tick FontString refresh and
-- the single shared C_Timer.NewTicker handle.
local _textIcons  = {}
local _textTicker

local function safeUnpackColor(c, fr, fg, fb, fa)
    -- Util.Unpack handles nil with sane defaults but we want module-specific
    -- fallbacks for the cooldown tint, so wrap it.
    if not c then return fr or 1, fg or 1, fb or 1, fa or 1 end
    return NS.Util.Unpack(c)
end

-- Resolve an LSM border-texture key to a file path, falling back to a
-- Blizzard-shipped tooltip border when the lib isn't loaded or the key
-- isn't registered. Mirrors fetchBorderTexture in modules/Castbar.lua so
-- the two pieces of UI share one fallback rule.
local function fetchBorderTexture(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.Fetch then
        local t = LSM:Fetch("border", name or "Blizzard Tooltip", true)
        if t then return t end
    end
    return "Interface\\Tooltips\\UI-Tooltip-Border"
end

--- The three inputs an alpha/tint curve pair is built from, flattened into a
--- comparison key. Only these five numbers change a curve's shape; every other
--- field in the "icons" config (border, font, layout, glow, zoom, tooltip)
--- leaves it identical.
---
--- Plain numbers throughout — nothing here is ever secret. These come from the
--- SavedVariables config, not from a cooldown API.
local function curveSignature(cfg)
    local r, g, b = safeUnpackColor(cfg.cooldownTint, 1, 0.4, 0.4)
    return table.concat({
        cfg.readyAlpha    or 1.0,
        cfg.cooldownAlpha or 0.4,
        r, g, b,
    }, ":")
end

--- Build the shared 0/1 GCD-suppression curve. Config-independent, so it is
--- built once and never rebuilt.
---
--- Steps from 0 (hide swipe + text) to 1 (show) at GCD_UPPER. Same shape as a
--- unit's alphaCurve but the values are visibility flags rather than alphas.
--- The output rides through SetAlphaFromBoolean(true, value, 0) when
--- cfg.suppressGCDSwipe is on.
local function buildGcdSuppressCurve()
    if gcdSuppressCurve then return end

    gcdSuppressCurve = _G.C_CurveUtil.CreateCurve()
    if gcdSuppressCurve.SetType and Enum and Enum.LuaCurveType then
        gcdSuppressCurve:SetType(Enum.LuaCurveType.Linear)
    end
    gcdSuppressCurve:AddPoint(0,                 0)
    gcdSuppressCurve:AddPoint(GCD_UPPER,         0)
    gcdSuppressCurve:AddPoint(GCD_UPPER + 0.001, 1)
    gcdSuppressCurve:AddPoint(3600,              1)
end

--- (Re)build one unit's alpha/tint curves from its resolved icons config
--- (NS.Units.Icons — link-aware, so a linked focus resolves target's table).
---
--- Skips the rebuild when the three curve-shaping values are unchanged
--- (F-016): every "icons" Ka0s_KickCD_CONFIG_CHANGED used to land here, so a
--- border, font, layout or glow edit recreated all three curves for nothing.
--- Cheap either way — these are tiny 4-point curves — but the signature check
--- is cheaper still, and it makes "what actually shapes a curve" explicit.
local function buildUnitCurves(unit)
    local cfg = NS.Units.Icons(unit)
    if not cfg then return end

    local sig = curveSignature(cfg)
    local set = _curves[unit]
    if set and set.sig == sig then return end

    local readyAlpha    = cfg.readyAlpha    or 1.0
    local cooldownAlpha = cfg.cooldownAlpha or 0.4
    local r, g, b = safeUnpackColor(cfg.cooldownTint, 1, 0.4, 0.4)

    set = { sig = sig }

    -- Step from readyAlpha to cooldownAlpha at GCD_UPPER. The 0.001s gap
    -- between adjacent points yields a sharp transition under linear
    -- interpolation (LuaCurveType.Linear is the default).
    set.alpha = _G.C_CurveUtil.CreateCurve()
    if set.alpha.SetType and Enum and Enum.LuaCurveType then
        set.alpha:SetType(Enum.LuaCurveType.Linear)
    end
    set.alpha:AddPoint(0,                 readyAlpha)
    set.alpha:AddPoint(GCD_UPPER,         readyAlpha)
    set.alpha:AddPoint(GCD_UPPER + 0.001, cooldownAlpha)
    set.alpha:AddPoint(3600,              cooldownAlpha)

    if _G.C_CurveUtil.CreateColorCurve and CreateColor then
        set.tint = _G.C_CurveUtil.CreateColorCurve()
        if set.tint.SetType and Enum and Enum.LuaCurveType then
            set.tint:SetType(Enum.LuaCurveType.Linear)
        end
        set.tint:AddPoint(0,                 CreateColor(1, 1, 1, 1))
        set.tint:AddPoint(GCD_UPPER,         CreateColor(1, 1, 1, 1))
        set.tint:AddPoint(GCD_UPPER + 0.001, CreateColor(r, g, b, 1))
        set.tint:AddPoint(3600,              CreateColor(r, g, b, 1))
    end

    _curves[unit] = set
end

--- (Re)build the alpha/tint curves. Called once on enable and again on any
--- "icons" config change or profile swap.
---
--- @param unit string|nil  rebuild just this unit, or every unit when omitted.
--- Callers pass nothing: an "icons" edit on a linked pair moves both units'
--- resolved config, and the per-unit signature check makes the unaffected
--- unit's pass a no-op anyway.
local function BuildCurves(unit)
    if not (_G.C_CurveUtil and _G.C_CurveUtil.CreateCurve) then return end

    buildGcdSuppressCurve()

    if unit then
        buildUnitCurves(unit)
        return
    end
    for _, u in ipairs(NS.Units.LIST) do
        buildUnitCurves(u)
    end
end

--- The curve pair for a unit, or an empty table when curves were never built
--- (no C_CurveUtil — Icon:Apply then falls through to its non-curve path).
--- Never returns nil, so callers read `.alpha` / `.tint` without a guard.
---
--- Deliberately does NOT fall back to target's pair: inheriting another unit's
--- alpha/tint is the exact bug this per-unit split exists to fix, so an
--- unbuilt unit renders without curves rather than with the wrong ones.
local function curvesFor(unit)
    return _curves[unit or "target"] or EMPTY_CURVES
end
-- ---------------------------------------------------------------------------
-- Per-icon widget construction
-- ---------------------------------------------------------------------------

-- Methods copied onto each button via Mixin() in CreateIconWidget. We can't
-- setmetatable() a Frame widget — that would clobber the C-side metatable
-- where ClearAllPoints/Show/SetAlpha/etc. live, and they'd become nil calls.
local Icon = {}

-- Published so the headless suites can mix these methods onto a stand-in
-- frame and drive Icon:Apply directly. Not part of the inter-module
-- contract — nothing in the addon reads it; icons get the methods via
-- Mixin() in CreateIconWidget below.
IconGrid.Icon = Icon

local function CreateIconWidget(parent)
    -- A Button (not a Frame) so a future click-to-cast hook is one
    -- :SetAttribute() away. SecureActionButton is intentionally avoided
    -- to keep the icon grid free of protected-frame taint.
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(48, 48)
    btn:EnableMouse(false) -- the grid as a whole handles drag, not individual icons

    -- Spell icon texture. The TexCoord crop is applied by ApplyAppearance
    -- from cfg.zoom; we leave it untouched here so the user-configurable
    -- value is the single source of truth.
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    btn.icon = tex

    -- Per-icon border. A BackdropTemplate child sized over the button so
    -- the edgeFile slices render on top of the icon texture; the cooldown
    -- swipe lives on a separate child frame and so isn't affected. Same
    -- approach used by modules/Castbar.lua so the two pieces of UI share
    -- one LSM "border" texture surface.
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints(btn)
    border:SetFrameLevel(btn:GetFrameLevel() + 1)
    border:Hide()
    btn.border = border

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

    -- Cooldown text overlay. We drive this FontString ourselves
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

    -- Charges badge — top-right corner, à la action-bar charges.
    local charges = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    charges:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    charges:Hide()
    btn.chargesText = charges

    -- Ready glow. A plain child Frame sized to the icon; LibCustomGlow
    -- attaches its own animated children (textures + AnimationGroups)
    -- when StartGlow runs. Frame level is bumped above the cooldown
    -- swipe and the per-icon border frame so the glow always renders
    -- on top.
    local glow = CreateFrame("Frame", nil, btn)
    glow:SetAllPoints(btn)
    glow:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn.glow = glow

    -- Per-widget state: cfg points at the owning unit's resolved appearance
    -- (NS.Units.Icons) during Apply so we can re-color/re-alpha without
    -- re-reading the db every time. spellID is set when the icon is acquired
    -- and used for fast lookup. unit / instance are stamped in AcquireIcon so
    -- a de-pooled icon still resolves the right unit's config + cast state.
    btn.spellID   = nil
    btn.cfg       = nil
    btn.unit      = nil
    btn.instance  = nil

    -- Hover tooltip. Only fires when EnableMouse(true) on the icon, which
    -- IconGrid:ApplyLock toggles based on (locked AND icons.showTooltip).
    -- While unlocked, EnableMouse(false) so the grid frame retains the
    -- mouse for dragging.
    btn:SetScript("OnEnter", function(self)
        local cfg = NS.Units.Icons(self.unit or "target")
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
    local cfg = self.cfg or NS.Units.Icons(self.unit or "target")
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
        local _, _, _, _, isActive = NS.Compat.GetSpellCooldown(self.spellID)
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
-- Trigger values (units.<unit>.icons.{primary,secondary}GlowTrigger):
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
-- glow at a time. That's the right shape for the current mutually-exclusive
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
-- combined-glow scenario hasn't materialized yet.
local LCG_KEY = "KickCD"

-- The out-of-table fallback stays local (the glow's default is not white), but
-- the unpack itself goes through Util.Unpack: colors are stored keyed, and an
-- index read would have made every glow render the same yellow.
local function unpackGlowColor(c)
    if type(c) ~= "table" then return 0.95, 0.95, 0.32, 1 end
    return NS.Util.Unpack(c)
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
local function triggerSatisfied(trigger, inst)
    if trigger == "always" then
        return true
    elseif trigger == "target_casting" then
        return inst and inst.isCasting and inst.isCasting() or false
    elseif trigger == "target_casting_interruptible" then
        local unit = (inst and inst.unit) or "target"
        return NS.State
           and NS.State.IsHostileUnitCasting
           and NS.State.IsHostileUnitCasting(unit)
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
--- The glow trigger, type and color for this slot — the primary and the
--- secondaries carry separate schema entries.
local function glowConfig(cfg, isPrimary)
    if isPrimary then
        return cfg.primaryGlowTrigger,   cfg.primaryGlowType,   cfg.primaryGlowColor
    end
    return cfg.secondaryGlowTrigger, cfg.secondaryGlowType, cfg.secondaryGlowColor
end

--- Per-cast interruptibility filter (alpha mask on the glow frame). Truthy
--- when the mask took over the glow's alpha, so the caller leaves it alone.
--- Only the target_casting_interruptible trigger masks.
local function applyInterruptibleMask(icon, trigger)
    return trigger == "target_casting_interruptible"
       and icon.glow
       and NS.State.ApplyInterruptibleAlpha
       and NS.State.ApplyInterruptibleAlpha(icon.glow, icon.unit or "target", 1)
end

function Icon:UpdateGlow(state)
    local cfg = self.cfg or NS.Units.Icons(self.unit or "target")
    if not cfg then return self:StopGlow() end

    local trigger, kind, color = glowConfig(cfg, self._isPrimary)

    local ready = state and state.ready and true or false
    if not ready or not triggerSatisfied(trigger, self.instance) then
        self:StopGlow()
        return
    end
    self:StartGlow(kind, color)

    if applyInterruptibleMask(self, trigger) then return end
    if self.glow then self.glow:SetAlpha(1) end
end

-- Apply the configured GCD-suppression alpha mask to the cooldown
-- swipe + countdown text using a duration object. When
-- cfg.suppressGCDSwipe is on, the gcdSuppressCurve evaluates to 0 below
-- GCD_UPPER (hide) and 1 above (show). The result is fed through
-- SetAlphaFromBoolean(true, value, 0) — both args may be secret-tainted
-- in combat but the C method handles it.
local function applyGcdSuppressionAlpha(icon, cdObject)
    local cfg = icon.cfg or NS.Units.Icons(icon.unit or "target")
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

-- Apply a Ka0s_KickCD_SPELL_STATE payload to this icon. Payload shape:
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
--- Did any PLAIN state field move between two payloads?
---
--- Splits Icon:Apply's work in two. The alpha/tint/GCD curves, the swipe
--- handle and the countdown text are TIME-varying and must be re-applied on
--- every payload. Glow, the charges badge and the Show/Hide calls depend only
--- on the fields below — so when none of them moved, redoing that half is
--- pure waste, repeated ~10x/sec for the whole of every cooldown (the emit
--- rate is forced: see docs/midnight-quirks.md, nothing on the duration
--- object is comparable from Lua in combat).
---
--- Charges are deliberately NOT part of this gate. They can be secret, and a
--- secret cannot be compared — while the badge renders one fine via
--- SetFormattedText's C-side path. Gating on an uncomparable value would
--- strand a stale count on screen for a whole fight, so the badge is simply
--- always refreshed; it is two calls.
local function plainStateMoved(prev, next_)
    if not prev then return true end
    if prev.ready    ~= next_.ready    then return true end
    if prev.isActive ~= next_.isActive then return true end
    -- Handle PRESENCE picks the render branch (full cooldown / charge
    -- recharge / idle); handle IDENTITY changes constantly and means nothing.
    if (prev.cdObject       == nil) ~= (next_.cdObject       == nil) then return true end
    if (prev.chargeCdObject == nil) ~= (next_.chargeCdObject == nil) then return true end
    return false
end

--- Branch 1: full spell-level cooldown (real CD or just-GCD). The curves drive
--- the icon-body alpha / tint so a GCD-only window still reads as "ready";
--- a real CD past the GCD threshold dims and tints the icon.
local function renderFullCooldown(icon, state, curves, stateWork)
    local alpha = state.cdObject:EvaluateRemainingDuration(curves.alpha)
    -- SetAlphaFromBoolean accepts secret values for its alpha args.
    -- Passing `true` as the condition selects the second arg
    -- unconditionally.
    if icon.SetAlphaFromBoolean then
        icon:SetAlphaFromBoolean(true, alpha, 0)
    else
        icon:SetAlpha(alpha)
    end

    if curves.tint then
        local color = state.cdObject:EvaluateRemainingDuration(curves.tint)
        if color and color.GetRGB then
            icon.icon:SetVertexColor(color:GetRGB())
        end
    end

    icon.cooldown:SetCooldownFromDurationObject(state.cdObject)
    if stateWork then icon.cooldown:Show() end
    icon:StartCooldownText(state.cdObject, true)
    applyGcdSuppressionAlpha(icon, state.cdObject)
end

--- Branch 2: charge recharge ticking; spell is still castable.
--- Show swipe + countdown text but keep the icon body at ready
--- visuals (no alpha dim, no tint shift). state.ready stays true
--- so the glow trigger keeps firing as configured.
local function renderChargeRecharge(icon, state, cfg, stateWork)
    if stateWork then
        icon:SetAlpha(cfg.readyAlpha or 1.0)
        icon.icon:SetVertexColor(1, 1, 1)
    end
    icon.cooldown:SetCooldownFromDurationObject(state.chargeCdObject)
    if stateWork then icon.cooldown:Show() end
    icon:StartCooldownText(state.chargeCdObject, false)
    applyGcdSuppressionAlpha(icon, state.chargeCdObject)
end

--- Branch 3: no active cooldown of any kind. Plain ready visuals.
local function renderIdle(icon, cfg, stateWork)
    if stateWork then
        icon:SetAlpha(cfg.readyAlpha or 1.0)
        icon.icon:SetVertexColor(1, 1, 1)
        icon.cooldown:Hide()
        icon.cooldown:Clear()
        icon:StopCooldownText()
    end
end

--- Charges badge. Visibility = "this spell has charges at all",
--- not "this spell has > 0 charges". Compat.GetSpellCharges returns nil
--- for spells that don't track charges (regular Mind Freeze etc.) and a
--- number (0..max) for spells that do, so the truthy check on `c` is
--- the right gate — and it works for plain numbers, secret-tainted
--- numbers (in-combat guarded spells), and the nil/no-charges case
--- alike. SetFormattedText is the canonical secret-safe render path
--- (the format is interpreted C-side, accepts secret args without
--- erroring; same pattern as the cooldown text overlay).
local function renderChargesBadge(icon, cfg, state)
    local c = state and state.charges
    if cfg.showCharges and c then
        icon.chargesText:SetFormattedText("%d", c)
        icon.chargesText:Show()
    else
        icon.chargesText:Hide()
    end
end

--- Apply a Ka0s_KickCD_SPELL_STATE payload.
-- @param state table   the payload (see the block comment above)
-- @param force boolean pass true when re-applying after a CONFIG change
--        rather than a fresh poll. Config re-applies hand back the SAME
--        state table, so the gate would correctly conclude "nothing moved"
--        and skip the very work the config change was meant to refresh.
function Icon:Apply(state, force)
    local __t0 = Perf.on and debugprofilestop()
    local cfg = self.cfg or NS.Units.Icons(self.unit or "target")
    local stateWork = force or plainStateMoved(self._lastState, state)
    -- Cache so ApplyTextConfig can re-render with fresh cfg when the user
    -- toggles showCooldownText (or any other visual state) mid-cooldown
    -- without waiting for the next SPELL_STATE message.
    self._lastState = state

    -- Resolve THIS icon's unit curves, not a module-level pair — an unlinked
    -- focus has its own readyAlpha / cooldownAlpha / cooldownTint.
    local curves = curvesFor(self.unit)

    -- The branch predicate is "which duration handle is non-nil", which an
    -- if/elseif states far more clearly than a dispatch table would.
    if state and state.cdObject and curves.alpha then
        renderFullCooldown(self, state, curves, stateWork)
    elseif state and state.chargeCdObject then
        renderChargeRecharge(self, state, cfg, stateWork)
    else
        renderIdle(self, cfg, stateWork)
    end

    -- Ready glow (off when on cooldown, on when castable). Driven from
    -- state.ready so it picks up the same "is castable" decision the
    -- rest of the UI uses; primary vs secondary chooses which schema
    -- entry's type/color applies.
    -- Gated: this costs four LibCustomGlow stop calls per apply while the
    -- spell is on cooldown. The trigger also depends on the UNIT's cast
    -- state, which changes independently of the spell — but
    -- IconGrid:OnUnitCastEvent already re-runs UpdateGlow across every icon
    -- on each UNIT_SPELLCAST_* transition, so that path stays covered.
    if stateWork then self:UpdateGlow(state) end

    renderChargesBadge(self, cfg, state)
    if __t0 then Perf.Note("iconApply", debugprofilestop() - __t0) end
end

-- Apply zoom (icon TexCoord crop) and border (visibility / color /
-- thickness). Called from Layout() so any /kcd set or panel change
-- takes effect on the next layout pass without a full rebuild.
function Icon:ApplyAppearance(cfg)
    cfg = cfg or NS.Units.Icons(self.unit or "target")
    local z = cfg.zoom or 0.08
    self.icon:SetTexCoord(z, 1 - z, z, 1 - z)

    local show = cfg.borderShow and true or false
    if show then
        local size = cfg.borderSize or 1
        if size < 1 then size = 1 end
        -- BackdropTemplate's SetBackdrop wants the table verbatim each call.
        -- edgeFile is an LSM border texture; edgeSize is the thickness of
        -- that texture's edge slices. Color tints the texture via
        -- SetBackdropBorderColor.
        self.border:SetBackdrop({
            edgeFile = fetchBorderTexture(cfg.borderTexture),
            edgeSize = size,
        })
        self.border:SetBackdropBorderColor(
            safeUnpackColor(cfg.borderColor, 0, 0, 0, 1))
        self.border:Show()
    else
        self.border:Hide()
    end
end

-- Wire the cooldown text font / size / flags on this icon in response to a
-- config change. The built-in CooldownFrameTemplate countdown numbers are
-- always suppressed — we render our own FontString via StartCooldownText
-- so the text displays even when the swipe is hidden (interrupts) and
-- inherits parent alpha for free.
function Icon:ApplyTextConfig(cfg)
    cfg = cfg or NS.Units.Icons(self.unit or "target")
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
        -- force=true: this hands back the SAME table, so the plain-state gate
        -- would see "nothing moved" and skip exactly the work this config
        -- change needs redone.
        self:Apply(self._lastState, true)
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
    local __t0 = Perf.on and debugprofilestop()
    -- Snapshot the count and short-circuit if empty — guards against
    -- a race where the ticker fires after the last icon deregistered
    -- but before we got around to canceling the timer.
    if next(_textIcons) == nil then
        if _textTicker and _textTicker.Cancel then
            _textTicker:Cancel()
        end
        _textTicker = nil
        -- Close the bracket on THIS exit too. The tick that finds the set
        -- empty still paid for the ticker callback and the `next` probe, and
        -- it is the exit taken on the very last tick of every cooldown burst
        -- — so leaving it unclosed under-counts `cdText.calls` by exactly the
        -- number of bursts and drops their teardown cost on the floor.
        if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
        return
    end
    for icon in pairs(_textIcons) do
        if icon and icon._RenderCooldownText then
            icon:_RenderCooldownText()
        end
    end
    if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
end

function IconGrid:_RegisterTextIcon(icon)
    if not icon then return end
    -- Idempotent — re-registering an already-active icon is a no-op.
    if _textIcons[icon] then return end
    _textIcons[icon] = true
    -- Lazy-start the ticker on the first registered icon.
    if not _textTicker and _G.C_Timer and _G.C_Timer.NewTicker then
        _textTicker = _G.C_Timer.NewTicker(0.1, _tickAllTextIcons)
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
-- Exposed to core/IconGrid.lua
-- ---------------------------------------------------------------------------
IconGrid.CreateIconWidget = CreateIconWidget
IconGrid.BuildCurves      = BuildCurves
-- Published so the headless suites can assert that each unit got its OWN curve
-- pair and that an unchanged config reuses the same objects. Nothing in the
-- addon reads it — Icon:Apply calls the file-local directly.
IconGrid.CurvesFor        = curvesFor
IconGrid.CurveSignature   = curveSignature

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- Pure file-locals with no frame dependency, published so the headless
-- harness can reach them (same idiom as Castbar.AutoSizeLong). The addon
-- itself keeps calling the locals directly.
IconGrid.SafeUnpackColor = safeUnpackColor
IconGrid.UnpackGlowColor = unpackGlowColor
IconGrid.TriggerSatisfied = triggerSatisfied
IconGrid.PlainStateMoved  = plainStateMoved
IconGrid.FetchBorderTexture = fetchBorderTexture
