-- modules/Castbar.lua
--
-- NOTE (KCD-19, §1.2): this file is in the 1000–1500 LOC "on notice" band.
-- It is under the 1500 hard cap; a future peel would split the config-driven
-- build (Reskin / sizing / anchors) from the per-cast update path (RenderCast).
--
-- Per-unit instance manager. Owns one cast-bar frame PER TRACKED UNIT
-- (target / focus); each instance mirrors ITS unit's cast / channel. Target's
-- frame keeps the exact legacy global name KickCDCastbar; Focus is
-- KickCDCastbarFocus. In Phase 2 only the target unit enables (Focus defaults
-- disabled), so behavior is identical to the former singleton. Each bar is a
-- custom-drawn StatusBar with icon, spell name, and remaining-time text.
-- Independently movable from the icon grid; visibility is gated on the unit's
-- resolved castbar.enabled (sub-module enable) AND NS.Units.IsEnabled(unit)
-- (master enable + the unit's own enable) AND db.profile.visibility (the
-- addon-wide "General visibility" mode also honored by IconGrid; in
-- "in_combat" mode the bar additionally requires KickCD.State.inCombat = true).
-- Drag-lock follows db.profile.locked, the same global lock the icon
-- grid honors.
--
-- Listens to the UNIT_SPELLCAST_* family per-instance via
-- Util.RegisterUnitCastEvent (dispatch frame fires only for the instance's
-- unit; the handler resolves instances[unit]): START/CHANNEL_START begin a
-- cast/channel, STOP/FAILED/INTERRUPTED/CHANNEL_STOP hide, DELAYED/CHANNEL_UPDATE
-- re-evaluate, INTERRUPTIBLE/_NOT_INTERRUPTIBLE re-apply per-state visuals.
-- The global unit-change events register at module level (plain RegisterEvent),
-- each refreshing only its own unit's instance if live:
--   PLAYER_TARGET_CHANGED        -> re-evaluate the target bar
--   PLAYER_FOCUS_CHANGED         -> re-evaluate the focus bar
--
--   Ka0s_KickCD_CONFIG_CHANGED  -> "castbar" reskins/relays the bar; "general"
--                             re-applies lock + anchor; other sections ignored.
--   Ka0s_KickCD_PROFILE_CHANGED -> re-anchor + reskin + re-evaluate.
--   Ka0s_KickCD_GRID_LAYOUT     -> re-anchor (in PRIMARY anchor mode the primary
--                             icon button reference may have changed) and
--                             re-apply auto-size (the grid frame may have
--                             resized).
--   Ka0s_KickCD_COMBAT_STATE    -> re-evaluate / Stop (drives "in_combat" mode).
--
-- This file fires no messages. The bar is a strict subscriber.
--
-- 12.0 secret-value strategy:
--   The previous Castbar implementation (removed at commit 59fb5c0) read
--   raw startTimeMS / endTimeMS out of UnitCastingInfo and did `now -
--   start` / `(end - start)` arithmetic in OnUpdate. Those positions are
--   "secret values" in tainted (addon) scope in combat for protected
--   interrupts; arithmetic / compare / format / tostring on a secret
--   number errors out (see core/Compat.lua line 28).
--
--   This rewrite never reads the secret timestamps. KickCD.Compat
--   exposes the cast's CastingDuration object via UnitCastingDuration /
--   UnitChannelDuration; the object's :GetTotalDuration /
--   :GetElapsedDuration / :GetRemainingDuration methods all return
--   PLAIN numbers in combat. The OnUpdate loop drives the bar entirely
--   off those numbers — no secret arithmetic anywhere in the module.
--   The spell `name` / `texture` may themselves be secret in combat,
--   but FontString:SetText / Texture:SetTexture accept secret args
--   without erroring (Blizzard's protection is on arithmetic, not on
--   UI render calls).

local addonName, NS = ...
local Castbar = NS:NewModule("Castbar", "AceEvent-3.0")
local L       = NS.L

-- ---------------------------------------------------------------------------
-- Per-unit instances
-- ---------------------------------------------------------------------------
--
-- Each tracked unit (target/focus) owns its own instance. Formerly these were
-- file-local singletons (`frame`, `current`, `lastGridLayout`); the instance
-- model lets a second unit coexist without any shared mutable state. Fields:
--   inst.frame          — the cast-bar Frame; created lazily in EnsureFrame.
--   inst.current        — active cast record (nil when idle). Built from
--                         Compat.GetCastingInfo / GetChannelInfo at cast start;
--                         OnInterruptibilityChanged MUTATES
--                         inst.current.notInterruptible in place to a plain Lua
--                         bool when *_INTERRUPTIBLE / *_NOT_INTERRUPTIBLE fires
--                         (the field may be secret-tainted in 12.0). See the
--                         "plain-after-flip invariant" comment near
--                         OnInterruptibilityChanged and docs/midnight-quirks.md.
--   inst.lastGridLayout — cached Ka0s_KickCD_GRID_LAYOUT refs for THIS unit's
--                         grid (gridFrame/primaryIcon); ApplyAnchor / Reskin
--                         prefer these over the public accessors. Fallback to
--                         IconGrid:GetGridFrame(unit) / :GetPrimaryIcon(unit)
--                         covers the first tick after enable / empty payloads.
--   inst.eventFrames    — private UNIT_SPELLCAST_* dispatch frames (teardown).
local instances = {}   -- [unit] = instance

local function newInstance(unit)
    return {
        unit           = unit,
        frame          = nil,
        current        = nil,
        lastGridLayout = { gridFrame = nil, primaryIcon = nil },
        eventFrames    = {},
        enabled        = false,
    }
end

function Castbar:GetInstance(unit)
    unit = unit or "target"
    local inst = instances[unit]
    if not inst then inst = newInstance(unit); instances[unit] = inst end
    return inst
end

-- Combat state lives in KickCD.State.inCombat (core/State.lua) — a shared,
-- single-owner flag driven off PLAYER_REGEN_* in one place, fanned out via the
-- Ka0s_KickCD_COMBAT_STATE message this module subscribes to. (InCombatLockdown()
-- lags the regen events by a frame, so the event-driven flag is the source of
-- truth.) This module just reads the shared one.

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function cfg(inst)
    return NS.Units.Castbar(inst.unit)
end

-- Iterate every currently-enabled instance in LIST order. Handlers that fan out
-- to "all live bars" (config / profile / combat / world changes) route through
-- here so the enable-gating lives in one place. Mirrors IconGrid's forEachEnabled.
local function forEachEnabled(fn)
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled then fn(inst) end
    end
end

-- Resolve `inst`'s icon-grid parent grid frame. Prefers the ref cached from
-- this unit's most recent Ka0s_KickCD_GRID_LAYOUT (CR-29); falls back to
-- IconGrid:GetGridFrame(inst.unit) for the first tick after enable / empty
-- payloads. Passing inst.unit means a focus bar resolves the focus grid.
-- GetModule(name, true) is the AceAddon optional-accessor idiom — silent on
-- missing, so a disabled IconGrid yields nil.
local function resolveGridFrame(inst)
    if inst.lastGridLayout.gridFrame then return inst.lastGridLayout.gridFrame end
    local m = NS:GetModule("IconGrid", true)
    if m and m.GetGridFrame then return m:GetGridFrame(inst.unit) end
    return nil
end

-- Resolve `inst`'s icon-grid primary (first-laid-out) icon button. Same
-- payload-preferred / accessor-fallback policy as resolveGridFrame.
local function resolvePrimaryIcon(inst)
    if inst.lastGridLayout.primaryIcon then return inst.lastGridLayout.primaryIcon end
    local m = NS:GetModule("IconGrid", true)
    if m and m.GetPrimaryIcon then return m:GetPrimaryIcon(inst.unit) end
    return nil
end

-- Honors the addon-wide visibility mode (db.profile.visibility) for inst.unit:
--   * "always"      — usual behavior (bar shows during the unit's casts).
--   * "in_combat"   — additionally requires KickCD.State.inCombat = true (a cast
--                     that starts while out of combat is suppressed).
--   * "target_casting" — equivalent to "always" here (the bar already only shows
--                     during the unit's casts), so it adds no extra restriction.
--   * "target_casting_interruptible" — show during ANY hostile cast on the unit;
--                     an alpha mask (ApplyVisibilityMask, via SetAlphaFromBoolean)
--                     then hides the bar for uninterruptible casts. The two-step
--                     gate is required because 12.0 secret-taints notInterruptible
--                     — Lua can't make the boolean call but the C-side
--                     SetAlphaFromBoolean accepts the secret directly. Friendly /
--                     self casts are excluded by IsHostileUnitCasting.
-- While unlocked the visibility mode is ignored — the user is moving the bar.
local function isVisible(inst)
    local profile = NS.db and NS.db.profile
    if not (NS.Units.IsEnabled(inst.unit) and cfg(inst).enabled ~= false) then return false end
    if profile and profile.locked == false then return true end
    local mode = (profile and profile.visibility) or "always"
    if mode == "in_combat" then
        return NS.State.inCombat
    elseif mode == "target_casting_interruptible" then
        return NS.State.IsHostileUnitCasting
           and NS.State.IsHostileUnitCasting(inst.unit)
           or false
    end
    return true
end

--- Apply the per-cast interruptibility alpha mask to the bar frame.
--- For "target_casting_interruptible" mode + active hostile cast, the
--- frame's alpha is driven by SetAlphaFromBoolean(notInterruptible, 0, 1)
--- — a C-side method that accepts the 12.0-secret notInterruptible flag
--- without needing Lua-side comparison. Other modes / no-cast / unlocked
--- (so the user can drag the bar regardless of cast state) → alpha 1.
--- Called whenever the bar shows OR the interruptibility flag flips.
local function ApplyVisibilityMask(barFrame, unit)
    if not barFrame then return end
    local profile = NS.db and NS.db.profile
    local unlocked = profile and profile.locked == false
    local mode = (profile and profile.visibility) or "always"
    if not unlocked
       and mode == "target_casting_interruptible"
       and NS.State.ApplyInterruptibleAlpha
       and NS.State.ApplyInterruptibleAlpha(barFrame, unit, 1) then
        return
    end
    barFrame:SetAlpha(1)
end

local function unpackColor(c, fr, fg, fb, fa)
    if not c then return fr or 1, fg or 1, fb or 1, fa or 1 end
    return NS.Util.Unpack(c)
end

local function fetchStatusBarTexture(name)
    if LSM and LSM.Fetch then
        local t = LSM:Fetch("statusbar", name or "Blizzard", true)
        if t then return t end
    end
    -- Default Blizzard status-bar texture path that ships with the client.
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

local function fetchBorderTexture(name)
    if LSM and LSM.Fetch then
        local t = LSM:Fetch("border", name or "Blizzard Tooltip", true)
        if t then return t end
    end
    -- Fallback: a Blizzard-shipped tooltip-style border texture.
    return "Interface\\Tooltips\\UI-Tooltip-Border"
end

-- Apply the user's spell-name truncate cap, returning a string fit
-- to hand to FontString:SetText. `0` (or nil) means "no truncation".
--
-- Secret-value handling: `rec.name` from Compat.GetCastingInfo can
-- be secret-tainted in combat for protected casts (per the module
-- header). `string.sub` / `#` on a secret may error in tainted
-- scope, so we short-circuit with `issecretvalue` and pass the raw
-- secret straight through to SetText (which accepts secret args
-- via its C-side argument path) — losing the truncation for that
-- one frame is preferable to throwing a Lua error.
--
-- Length is byte-counted; multi-byte UTF-8 names may truncate mid-
-- character at the edge, but won't error. Most spell names are
-- short enough that the cap rarely fires anyway.
local function truncateName(name, maxChars)
    if not name then return "" end
    if not maxChars or maxChars <= 0 then return name end
    if _G.issecretvalue and _G.issecretvalue(name) then return name end
    if #name <= maxChars then return name end
    return string.sub(name, 1, maxChars) .. "…"
end

local function fetchFont(name)
    if LSM and LSM.Fetch then
        local f = LSM:Fetch("font", name or "Friz Quadrata TT", true)
        if f then return f end
    end
    -- Fall back to whatever GameFontNormal points at — guaranteed to exist.
    local fobj = _G.GameFontNormal
    if fobj and fobj.GetFont then
        local path = fobj:GetFont()
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- ---------------------------------------------------------------------------
-- Lock / drag persistence + anchoring
-- ---------------------------------------------------------------------------
--
-- Two anchor modes:
--   * FREE    — the bar floats free of the icon grid. The user drags it to
--               position; OnDragStop persists the anchor to anchors.castbar.
--   * PRIMARY — the bar is SetPoint'd to the icon grid's primary icon
--               button (or grid frame fallback when no spell is being
--               watched). Dragging is disabled in this mode because the bar
--               position is determined by the icon position and the user-
--               configured (anchorPoint, castbarPoint, offset) tuple.

local function onDragStart(_inst, self)
    if NS.db and NS.db.profile and NS.db.profile.locked then return end
    self:StartMoving()
end

local function onDragStop(inst, self)
    self:StopMovingOrSizing()
    if NS.db and NS.db.profile then
        NS.Units.SetAnchor(inst.unit, "castbar", NS.Util.SaveAnchor(self))
    end
    -- CR-34: complete the bus contract by announcing the anchor write.
    -- No subscriber listens for "castbar" anchor changes today (the bar
    -- has already moved itself), but firing it makes the bus self-
    -- consistent and defends against a future "anchor-aware" listener.
    -- Castbar's own OnConfigChanged handles { section = "castbar" }
    -- idempotently (Reskin + ApplyLock are no-ops for an already-correct
    -- frame), so the dispatch is safe to re-enter.
    if NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "castbar" })
    end
end

-- Translate a 13-point anchor token (the new `<SIDE>_<ALIGN>` /
-- `CENTER` set shared with the Icons grid dropdown) into a name
-- SetPoint accepts (TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT,
-- BOTTOMLEFT, BOTTOM, BOTTOMRIGHT). For 2D-point anchors `TOP_LEFT`
-- and `LEFT_TOP` collapse to the same corner — they're distinct
-- options in the dropdown for UI consistency with the Icons panel
-- (where the alignment axis is meaningful) but produce identical
-- visuals here.
--
-- Unrecognized values pass through unchanged so legacy 9-point
-- tokens saved by older profiles (`TOP`, `BOTTOMLEFT`, …) keep
-- working without an explicit migration. Falls back to `CENTER`
-- when nil.
local SETPOINT_MAP = {
    TOP_LEFT      = "TOPLEFT",
    TOP_MIDDLE    = "TOP",
    TOP_RIGHT     = "TOPRIGHT",
    BOTTOM_LEFT   = "BOTTOMLEFT",
    BOTTOM_MIDDLE = "BOTTOM",
    BOTTOM_RIGHT  = "BOTTOMRIGHT",
    LEFT_TOP      = "TOPLEFT",
    LEFT_MIDDLE   = "LEFT",
    LEFT_BOTTOM   = "BOTTOMLEFT",
    RIGHT_TOP     = "TOPRIGHT",
    RIGHT_MIDDLE  = "RIGHT",
    RIGHT_BOTTOM  = "BOTTOMRIGHT",
    CENTER        = "CENTER",
}

local function toSetPoint(value)
    if not value then return "CENTER" end
    return SETPOINT_MAP[value] or value
end

--- (Re)anchor the cast-bar frame based on the active anchor mode.
--- FREE   -> apply the saved anchor against UIParent.
--- PRIMARY -> SetPoint(castbarPoint, primaryIcon, anchorPoint, offX, offY).
---           Falls back to the grid frame, then to the saved free anchor.
function Castbar:ApplyAnchor(inst)
    local frame = inst.frame
    if not frame then return end
    local c = cfg(inst)
    local mode = c.anchorMode or "FREE"

    if mode == "PRIMARY" then
        -- Prefer the payload-cached references over the public accessors.
        -- Falls back to the grid frame when no spells are watched (no
        -- primary icon yet).
        local target = resolvePrimaryIcon(inst) or resolveGridFrame(inst)
        if target then
            frame:ClearAllPoints()
            frame:SetPoint(
                toSetPoint(c.castbarPoint  or "BOTTOM_MIDDLE"),
                target,
                toSetPoint(c.anchorPoint   or "TOP_MIDDLE"),
                c.anchorOffsetX or 0,
                c.anchorOffsetY or 0)
            return
        end
        -- Target not yet built — fall through to the saved free anchor so
        -- the bar at least has a position to render at while we wait.
    end

    local saved = NS.Units.Anchor(inst.unit, "castbar")
    NS.Util.ApplyAnchor(frame, saved or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 })
end

function Castbar:ApplyLock(inst)
    local frame = inst.frame
    if not frame then return end
    local c              = cfg(inst)
    local primaryAnchor  = (c.anchorMode == "PRIMARY")
    local profileLocked  = NS.db and NS.db.profile and NS.db.profile.locked
    -- PRIMARY anchor mode forces drag-disabled — the bar's position is
    -- determined by the icon-grid anchor + offsets, not by dragging.
    local dragAllowed    = (not profileLocked) and (not primaryAnchor)

    if dragAllowed then
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if frame.dragHint then frame.dragHint:Show() end
    else
        frame:EnableMouse(false)
        frame:RegisterForDrag()
        if frame.dragHint then frame.dragHint:Hide() end
    end

    -- Visibility for the empty (no-cast) state:
    --   * UI unlocked + sub-module visible → show preview (so the user can
    --     see where the bar will appear, even in PRIMARY anchor mode).
    --   * UI locked → hide the empty bar; only show during real casts.
    if not inst.current then
        if (not profileLocked) and isVisible(inst) then
            self:ShowPreview(inst)
        else
            frame:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

function Castbar:EnsureFrame(inst)
    if inst.frame then return inst.frame end

    -- Target keeps the exact legacy global name KickCDCastbar (macros / other
    -- addons may reference it); Focus is KickCDCastbarFocus.
    local frame = CreateFrame("Frame",
        inst.unit == "target" and "KickCDCastbar" or "KickCDCastbarFocus", UIParent)
    inst.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Initial anchor — ApplyAnchor() handles both FREE and PRIMARY modes.
    -- Called again at OnEnable / OnConfigChanged / OnGridLayout time.
    self:ApplyAnchor(inst)

    frame:SetScript("OnDragStart", function(f) onDragStart(inst, f) end)
    frame:SetScript("OnDragStop",  function(f) onDragStop(inst, f) end)

    -- ----------------------------------------------------------------
    -- Two backgrounds (interruptible / uninterruptible), stacked. Each
    -- has its own color; alphas are curve-switched against the cast's
    -- secret notInterruptible bool in ApplyState() so only one shows.
    -- ----------------------------------------------------------------
    frame.bgInterruptible   = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgUninterruptible = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgInterruptible:SetAllPoints(frame)
    frame.bgUninterruptible:SetAllPoints(frame)

    -- ----------------------------------------------------------------
    -- Bar area is a non-StatusBar Frame container; the two state bars
    -- live inside it side-by-side (same anchors, alpha-switched).
    -- ----------------------------------------------------------------
    frame.bar = CreateFrame("Frame", nil, frame)

    frame.bar.interruptible   = CreateFrame("StatusBar", nil, frame.bar)
    frame.bar.uninterruptible = CreateFrame("StatusBar", nil, frame.bar)
    for _, sb in ipairs({ frame.bar.interruptible, frame.bar.uninterruptible }) do
        sb:SetAllPoints(frame.bar)
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0)
    end

    -- Overlay frame above the bars. Spark and the name/time text live
    -- here so they draw on TOP of the bar's filled status texture —
    -- otherwise the StatusBar children of frame.bar would render on top
    -- of any FontString/Texture parented to frame.bar at OVERLAY layer
    -- (child frames always draw above their parent's draw layers,
    -- regardless of layer name). frame.overlay sits at a higher
    -- FrameLevel than the bars, so its OVERLAY-layer children win.
    frame.overlay = CreateFrame("Frame", nil, frame.bar)
    frame.overlay:SetAllPoints(frame.bar)
    frame.overlay:SetFrameLevel(frame.bar.interruptible:GetFrameLevel() + 1)

    -- Spark texture (overlay at the right edge of the inner status texture).
    -- We anchor it to the interruptible bar's status texture: both bars
    -- share the same SetMinMaxValues / SetValue calls each frame, so their
    -- inner textures are the same width — anchoring to either is fine.
    frame.spark = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetSize(20, 30)

    -- Icon texture (square; height matches the bar).
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop the Blizzard border

    -- Spell name + remaining time on the overlay frame (above the bars).
    -- Color is per-state and curve-evaluated on a single FontString —
    -- no need to stack two FontStrings.
    frame.nameText = frame.overlay:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetWordWrap(false)

    frame.timeText = frame.overlay:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetJustifyH("RIGHT")

    -- ----------------------------------------------------------------
    -- Two LSM-textured border frames (BackdropTemplate). Each owns its
    -- own edgeFile / edgeSize / color via SetBackdrop+SetBackdropBorderColor;
    -- alphas are curve-switched in ApplyState. Border show toggles fold
    -- into the curve directly so disabled-side stays alpha=0.
    --
    -- Frame level must be HIGHER than the stacked StatusBars; otherwise
    -- the bar's filled status texture (which sits at level +2 because
    -- it's a grandchild of frame) renders ON TOP of the border's edge
    -- and makes the border look like it's tinted by the bar color.
    -- Bumping borders to bar level + 2 puts them above both the bars
    -- (level +2) and the overlay text/spark layer (level +3).
    -- ----------------------------------------------------------------
    frame.borderInterruptible   = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.borderUninterruptible = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.borderInterruptible:SetAllPoints(frame)
    frame.borderUninterruptible:SetAllPoints(frame)
    local barLevel = frame.bar.interruptible:GetFrameLevel()
    frame.borderInterruptible:SetFrameLevel(barLevel + 2)
    frame.borderUninterruptible:SetFrameLevel(barLevel + 2)

    -- Subtle "drag me" hint, shown only while unlocked.
    frame.dragHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.dragHint:SetText(L["KickCD castbar — drag to move"])
    frame.dragHint:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    frame.dragHint:Hide()

    frame:Hide()
    return frame
end

-- ---------------------------------------------------------------------------
-- Configuration application (size / colors / fonts / anchors of children)
-- ---------------------------------------------------------------------------

-- Default sub-config used when a profile is missing the per-state nested
-- block (safety net against malformed saved-vars). Mirrors the Database
-- defaults.
local function stateConfig(c, key, fallback)
    local sc = c[key]
    if type(sc) == "table" then return sc end
    return fallback
end

local INT_FALLBACK = {
    statusBarTexture = "Blizzard",
    barColor         = { 1,    0.85, 0.05, 1   },
    bgColor          = { 0,    0,    0,    0.5 },
    nameTextColor    = { 1,    1,    1,    1   },
    borderShow       = false,
    borderTexture    = "Blizzard Tooltip",
    borderColor      = { 0,    0,    0,    1   },
    borderSize       = 1,
}
local UNINT_FALLBACK = {
    statusBarTexture = "Blizzard",
    barColor         = { 0.85, 0.10, 0.10, 1   },
    bgColor          = { 0,    0,    0,    0.5 },
    nameTextColor    = { 1,    1,    1,    1   },
    borderShow       = true,
    borderTexture    = "Blizzard Tooltip",
    borderColor      = { 1,    0.20, 0.20, 1   },
    borderSize       = 2,
}

-- A 4px inset on the inside positions keeps text from touching the bar
-- border. The user's offsetX is added on top so they can pull the text
-- further out or push it back in. Sourced from KickCD.Const so the
-- value lives in exactly one place across the addon.
local INSIDE_INSET  = NS.Const.CASTBAR_INSIDE_INSET
local OUTSIDE_INSET = NS.Const.CASTBAR_OUTSIDE_INSET

local function anchorTextElement(fs, bar, position, ox, oy)
    fs:ClearAllPoints()
    if position == "INSIDE_RIGHT" then
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", bar, "RIGHT", -INSIDE_INSET + ox, oy)
    elseif position == "CENTER" then
        fs:SetJustifyH("CENTER")
        fs:SetPoint("CENTER", bar, "CENTER", ox, oy)
    elseif position == "OUTSIDE_LEFT" then
        -- Text floats just to the left of the bar (right-justified so the
        -- text grows outward from the bar's left edge).
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", bar, "LEFT", -OUTSIDE_INSET + ox, oy)
    elseif position == "OUTSIDE_RIGHT" then
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", bar, "RIGHT", OUTSIDE_INSET + ox, oy)
    else
        -- INSIDE_LEFT (default).
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", bar, "LEFT", INSIDE_INSET + ox, oy)
    end
end

local function applyBorder(borderFrame, sc)
    -- BackdropTemplate's SetBackdrop wants the table verbatim each call.
    -- edgeFile is an LSM border texture; edgeSize is the thickness of that
    -- texture's edge slices. Color tints the texture via SetBackdropBorderColor.
    borderFrame:SetBackdrop({
        edgeFile = fetchBorderTexture(sc.borderTexture),
        edgeSize = math.max(1, sc.borderSize or 1),
    })
    borderFrame:SetBackdropBorderColor(unpackColor(sc.borderColor, 0, 0, 0, 1))
end

--- Config-driven re-skin of the cast bar widgets. Recomputes orientation,
--- size, child anchors, fonts, backdrops, status-bar textures + colors,
--- spark rotation, and per-state border backdrops. Does NOT touch the
--- per-cast texture, spell name, or bar fill values — those are
--- Castbar:RenderCast's job.
---
--- Called from:
---   * OnConfigChanged (section == "castbar") — config flip
---   * OnGridLayout — auto-size needs to re-track the grid frame
---   * OnProfileChanged — profile swap
---   * ShowPreview — the placeholder bar still depends on config
---
--- This used to be Castbar:ApplyConfig and was called on every cast
--- start, recomputing ~40 widget calls per cast. CR-17 split it: cast
--- start now goes through Castbar:RenderCast (~6 widget calls) and
--- only re-skins on actual config changes.
-- TODO(perf): split into "color-only" vs "structural" so the 50 ms-throttled
-- color-picker drag doesn't re-run all ~40 widget calls per tick (F-015).
function Castbar:Reskin(inst)
    local frame = inst.frame
    if not frame then return end
    local c = cfg(inst)

    local intCfg   = stateConfig(c, "interruptible",   INT_FALLBACK)
    local unintCfg = stateConfig(c, "uninterruptible", UNINT_FALLBACK)

    local isVertical = (c.orientation == "VERTICAL")
    -- For HORIZONTAL: grow="LEFT" reverses fill (right-anchored texture grows
    -- right→left). For VERTICAL: grow="DOWN" reverses fill (top-anchored
    -- texture grows top→bottom). The default non-reverse case is
    -- HORIZONTAL/RIGHT (left→right) and VERTICAL/UP (bottom→top), which is
    -- what most cast bars use.
    local reverseFill
    if isVertical then
        reverseFill = (c.growDirection == "DOWN")
    else
        reverseFill = (c.growDirection == "LEFT")
    end

    -- "Cast bar width" / "Cast bar height" in the settings UI are
    -- semantic, NOT physical: width = the bar's long axis (the
    -- direction that fills during a cast), height = its thickness
    -- perpendicular to fill. WoW Frames have no native rotation, so
    -- we fake the user's "rotate 90° in vertical mode" mental model
    -- by swapping which physical axis each maps to. With defaults
    -- (width=250, height=24):
    --   * Horizontal → frame is 250×24 (wide, short).
    --   * Vertical   → frame is 24×250 (narrow, tall).
    -- Everything downstream — bar sub-frame insets, spark rotation,
    -- the iconPos LEFT→TOP / RIGHT→BOTTOM remap below — already works
    -- once the physical dimensions reflect the rotated geometry; the
    -- previous implementation left the frame wide-and-short even in
    -- vertical mode, which is why the bar visibly only filled across
    -- 24 px of vertical space.
    local barLong  = math.max(40, c.width  or 250)
    local barThick = math.max(8,  c.height or 24)

    -- Auto-size override: match the bar's long axis to the icon
    -- grid's corresponding screen-axis extent. Thickness stays
    -- user-configured. Re-runs on every Ka0s_KickCD_GRID_LAYOUT so the
    -- bar tracks the grid as icons are added / removed / resized.
    if c.autoSize then
        local gridFrame = resolveGridFrame(inst)
        if gridFrame then
            if isVertical then
                local h = gridFrame:GetHeight()
                if h and h > 0 then barLong = math.floor(h) end
            else
                local w = gridFrame:GetWidth()
                if w and w > 0 then barLong = math.floor(w) end
            end
        end
    end

    if isVertical then
        frame:SetSize(barThick, barLong)
    else
        frame:SetSize(barLong, barThick)
    end

    -- Per-state backgrounds (alpha-switched in ApplyState).
    frame.bgInterruptible:SetColorTexture(unpackColor(intCfg.bgColor, 0, 0, 0, 0.5))
    frame.bgUninterruptible:SetColorTexture(unpackColor(unintCfg.bgColor, 0, 0, 0, 0.5))

    -- Per-state bar textures + colors. Both bars share size/anchors so
    -- the spark anchor (to the interruptible inner status texture) is
    -- always at the correct fill edge regardless of which one is visible.
    frame.bar.interruptible:SetStatusBarTexture(fetchStatusBarTexture(intCfg.statusBarTexture))
    frame.bar.interruptible:SetStatusBarColor(unpackColor(intCfg.barColor, 1, 0.85, 0.05, 1))
    frame.bar.uninterruptible:SetStatusBarTexture(fetchStatusBarTexture(unintCfg.statusBarTexture))
    frame.bar.uninterruptible:SetStatusBarColor(unpackColor(unintCfg.barColor, 0.85, 0.1, 0.1, 1))

    -- Apply orientation + reverse-fill on both stacked StatusBars. Blizzard
    -- handles all the C-side texture growth math, so we never have to do
    -- per-frame arithmetic ourselves (which would error on secret
    -- CastingDuration values in combat).
    local barOrient = isVertical and "VERTICAL" or "HORIZONTAL"
    frame.bar.interruptible:SetOrientation(barOrient)
    frame.bar.uninterruptible:SetOrientation(barOrient)
    frame.bar.interruptible:SetReverseFill(reverseFill)
    frame.bar.uninterruptible:SetReverseFill(reverseFill)

    -- Icon position decides bar inset. "OFF" hides the icon entirely and
    -- gives the bar the full frame; "LEFT" / "RIGHT" inset the bar on the
    -- corresponding side. In VERTICAL orientation, LEFT is remapped to TOP
    -- and RIGHT to BOTTOM since literal left/right doesn't make sense for
    -- a tall bar.
    local iconPos  = c.iconPosition or "LEFT"
    local iconSize = math.max(0, c.iconSize or barThick)
    -- Cap iconSize at the bar's thickness (the perpendicular-to-fill
    -- dimension) so the icon never overflows the bar's short axis.
    if iconSize > barThick then iconSize = barThick end
    local showIcon = (iconPos ~= "OFF") and (iconSize > 0)

    frame.icon:ClearAllPoints()
    frame.bar:ClearAllPoints()
    if showIcon then
        frame.icon:Show()
        frame.icon:SetSize(iconSize, iconSize)
        if isVertical then
            if iconPos == "RIGHT" then
                -- BOTTOM in vertical mode.
                frame.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, iconSize)
            else
                -- TOP in vertical mode (default).
                frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, -iconSize)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, 0)
            end
        else
            if iconPos == "RIGHT" then
                frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -iconSize, 0)
            else
                frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      iconSize, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, 0)
            end
        end
    else
        frame.icon:Hide()
        frame.bar:SetAllPoints(frame)
    end

    -- Spark — anchor to the fill edge of the interruptible bar's inner
    -- status texture. Both stacked bars receive identical
    -- SetMinMaxValues / SetValue calls every frame, so their textures are
    -- the same size; anchoring to either gives the same fill-edge position.
    -- The fill edge depends on orientation + reverseFill:
    --   * HORIZONTAL non-reverse  → texture grows L→R, fill edge = RIGHT
    --   * HORIZONTAL reverse      → texture grows R→L, fill edge = LEFT
    --   * VERTICAL   non-reverse  → texture grows B→T, fill edge = TOP
    --   * VERTICAL   reverse      → texture grows T→B, fill edge = BOTTOM
    -- The natural Blizzard spark is a tall vertical line; for VERTICAL
    -- orientation we rotate it 90° so it reads as a horizontal slash
    -- across the bar's fill edge.
    if c.showSpark ~= false then
        frame.spark:Show()
        frame.spark:ClearAllPoints()
        if isVertical then
            -- Spark sized to span the bar's thickness (now the
            -- horizontal axis); 90° rotation turns the texture's
            -- tall line into a horizontal slash across the fill edge.
            frame.spark:SetSize(barThick + 6, 20)
            if frame.spark.SetRotation then frame.spark:SetRotation(math.pi / 2) end
        else
            frame.spark:SetSize(20, barThick + 6)
            if frame.spark.SetRotation then frame.spark:SetRotation(0) end
        end
        local fill = frame.bar.interruptible:GetStatusBarTexture()
        if fill then
            local sparkAnchor
            if isVertical then
                sparkAnchor = reverseFill and "BOTTOM" or "TOP"
            else
                sparkAnchor = reverseFill and "LEFT"   or "RIGHT"
            end
            frame.spark:SetPoint("CENTER", fill, sparkAnchor, 0, 0)
        end
    else
        frame.spark:Hide()
    end

    -- Font for both labels (shared across states).
    local fontPath = fetchFont(c.font)
    local fontSize = c.fontSize or 12
    local fontFlags = c.fontFlags
    if fontFlags == "NONE" or fontFlags == nil then fontFlags = "" end

    frame.nameText:SetFont(fontPath, fontSize, fontFlags)
    frame.timeText:SetFont(fontPath, fontSize, fontFlags)
    -- timeText color stays shared (white). nameText color is per-state and
    -- applied in ApplyState via curve-evaluated channels.
    frame.timeText:SetTextColor(1, 1, 1, 1)

    -- Position labels per their independent anchor settings. INSIDE_*
    -- variants pin the text to a bar edge (with a 4px breathing-room
    -- inset that the user's offsetX adds to). OUTSIDE_* variants float
    -- the text just past the bar edge so multi-line layouts can put
    -- name above and time below the bar by combining OUTSIDE positions
    -- with appropriate Y offsets. CENTER pins to bar center.
    anchorTextElement(frame.nameText, frame.bar,
        c.namePosition or "INSIDE_LEFT",  c.nameOffsetX or 0, c.nameOffsetY or 0)
    anchorTextElement(frame.timeText, frame.bar,
        c.timePosition or "INSIDE_RIGHT", c.timeOffsetX or 0, c.timeOffsetY or 0)

    if c.showName == false then frame.nameText:Hide() else frame.nameText:Show() end
    if c.showTime == false then frame.timeText:Hide() else frame.timeText:Show() end

    -- Per-state borders via BackdropTemplate. Visibility is folded into
    -- alpha switching in ApplyState; here we just configure the backdrop
    -- and color on each frame so they're ready when the curve unhides them.
    applyBorder(frame.borderInterruptible,   intCfg)
    applyBorder(frame.borderUninterruptible, unintCfg)

    -- Apply the secret-bool-driven alpha + name color now so a config
    -- change that arrives mid-cast picks up the new per-state values.
    self:ApplyState(inst)

    -- Per-cast texture / name re-paint is the responsibility of
    -- Castbar:RenderCast. OnConfigChanged calls RenderCast(current)
    -- after Reskin when a cast is active so the texture / name pick
    -- up any structural change (iconSize toggling on / off,
    -- nameTruncate change, ...). See CR-17 for the split.
end

--- Per-cast paint of the bar widgets. Sets the spell icon texture, the
--- truncated spell name, seeds both stacked StatusBars' ranges + values
--- from the cast's CastingDuration object, and re-applies per-state
--- visuals via ApplyState.
---
--- This is the cast-record-driven half of the CR-17 split: Reskin owns
--- the structural / config-driven work and runs on every config flip;
--- RenderCast owns the per-cast work and runs on Castbar:Start (and on
--- OnConfigChanged when a cast is active so the new structural layout
--- shows the right texture / name for the current cast).
---
--- @param rec table  cast record (current); must carry texture, name,
---                   isChannel, duration. Methods on duration may return
---                   secret-tainted numbers in combat — pass them
---                   directly as args to Blizzard C methods, never bind
---                   to Lua locals.
function Castbar:RenderCast(inst, rec)
    local frame = inst.frame
    if not (frame and rec) then return end
    local c = cfg(inst)

    -- name / texture may themselves be secret in combat for protected
    -- casts, but Texture:SetTexture / FontString:SetText accept secret
    -- args without erroring. Pass them through.
    if c.iconSize and c.iconSize > 0 and rec.texture then
        frame.icon:SetTexture(rec.texture)
    end
    if c.showName ~= false then
        frame.nameText:SetText(truncateName(rec.name, c.nameTruncate))
    else
        frame.nameText:SetText("")
    end

    -- Seed both bars from the duration object so we don't flash a 0% bar
    -- before the first OnUpdate tick. SetMinMaxValues runs here once per
    -- cast (and again from OnCastDelayed if the duration changes mid-cast)
    -- — onUpdate's hot path no longer touches the range. Pass duration
    -- methods directly to the StatusBar C methods; never bind to locals.
    local d = rec.duration
    if d then
        frame.bar.interruptible:SetMinMaxValues(0, d:GetTotalDuration())
        frame.bar.uninterruptible:SetMinMaxValues(0, d:GetTotalDuration())
        if rec.isChannel then
            frame.bar.interruptible:SetValue(d:GetRemainingDuration())
            frame.bar.uninterruptible:SetValue(d:GetRemainingDuration())
        else
            frame.bar.interruptible:SetValue(d:GetElapsedDuration())
            frame.bar.uninterruptible:SetValue(d:GetElapsedDuration())
        end
    end

    -- Per-state alpha + name color from the (possibly secret) notInterruptible.
    self:ApplyState(inst)
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------
--
-- Animation strategy:
--   * `current` is the record returned by Compat.GetCastingInfo / GetChannelInfo.
--     The record carries the cast's CastingDuration object (`current.duration`)
--     whose :GetTotalDuration / :GetElapsedDuration / :GetRemainingDuration
--     methods return secret-tainted numbers in combat for protected casts —
--     same protection rule as CooldownDuration. We NEVER bind those return
--     values to a Lua local; we pass them DIRECTLY as arguments to Blizzard
--     C methods (StatusBar:SetMinMaxValues / SetValue, FontString:
--     SetFormattedText) which accept secret args without erroring. This is
--     the one and only safe pattern — see CLAUDE.md "Cast bar module".
--
--   * Bar fills 0 → total for casts, drains total → 0 for channels. We feed
--     d:GetElapsedDuration() vs d:GetRemainingDuration() to SetValue based
--     on `current.isChannel` (a plain boolean).
--
--   * The spark sits at the right edge of the bar's status texture. Blizzard
--     resizes the inner status texture C-side as the bar value changes, and
--     the spark is anchored to that texture's RIGHT — so it follows the
--     fill edge automatically without any per-frame Lua arithmetic.
--
--   * Stop on UNIT_SPELLCAST_STOP / FAILED / INTERRUPTED / CHANNEL_STOP.
--     We can't detect cast end from OnUpdate (would need `if remaining <= 0`,
--     which is a secret comparison), so the events are the sole source of
--     truth for "cast finished".

-- Hot path. Runs every frame while a cast is active. Constraints:
--   * No table lookups for config — `current.showTime` is cached on cast
--     start (see Castbar:Start) and re-cached on Ka0s_KickCD_CONFIG_CHANGED.
--   * No SetMinMaxValues — the duration object's total only changes at
--     cast start / on UNIT_SPELLCAST_DELAYED / UNIT_SPELLCAST_CHANNEL_UPDATE.
--     Both transitions go through Castbar:Start (initial) or
--     Castbar:OnCastDelayed (mid-cast). Setting the same range every frame
--     is pure waste.
--   * d:Get*Duration() returns may be secret in combat for protected
--     casts; pass them DIRECTLY as arguments to Blizzard C methods
--     (SetValue / SetFormattedText) and never bind to a Lua local.
-- Per-frame work shrinks from ~6 method calls (2 SetMinMaxValues + 2
-- SetValue + 1 SetFormattedText + 1 cfg() table lookup) to 2-3
-- (SetValue × 2 + (conditional) SetFormattedText × 1).
local function onUpdate(inst)
    local frame   = inst.frame
    local current = inst.current
    local d = current and current.duration
    if not d then
        frame:SetScript("OnUpdate", nil)
        return
    end

    -- Both stacked StatusBars get the same value every frame so their
    -- inner textures stay in sync — only one of them is alpha-visible
    -- at a time (curve-switched in ApplyState off current.notInterruptible).
    if current.isChannel then
        frame.bar.interruptible:SetValue(d:GetRemainingDuration())
        frame.bar.uninterruptible:SetValue(d:GetRemainingDuration())
    else
        frame.bar.interruptible:SetValue(d:GetElapsedDuration())
        frame.bar.uninterruptible:SetValue(d:GetElapsedDuration())
    end

    if current.showTime then
        frame.timeText:SetFormattedText(
            "%.1f / %.1f", d:GetRemainingDuration(), d:GetTotalDuration())
    end
    -- The spark's position is driven by Blizzard reanchoring the
    -- interruptible bar's inner status texture; nothing to do here.
end

--- Apply the secret-bool-driven visuals: alpha-switch the dual bg / bar /
--- border widgets and update the spell-name color, all driven off
--- `current.notInterruptible` via C_CurveUtil.EvaluateColorValueFromBoolean.
--- The curve evaluator accepts a (possibly secret) boolean as its first
--- arg and returns the second or third value accordingly. The result may
--- itself be tainted; we pass it directly to a Blizzard C method
--- (SetAlpha / SetTextColor) without binding to a local.
function Castbar:ApplyState(inst)
    local frame = inst.frame
    if not frame then return end
    local c        = cfg(inst)
    local intCfg   = stateConfig(c, "interruptible",   INT_FALLBACK)
    local unintCfg = stateConfig(c, "uninterruptible", UNINT_FALLBACK)

    local intBorderShow  = intCfg.borderShow   and 1 or 0
    local unintBorderShow = unintCfg.borderShow and 1 or 0

    if not inst.current then
        -- Preview / no-cast: show interruptible visuals; uninterruptible
        -- side is fully alpha=0.
        frame.bgInterruptible:SetAlpha(1)
        frame.bgUninterruptible:SetAlpha(0)
        frame.bar.interruptible:SetAlpha(1)
        frame.bar.uninterruptible:SetAlpha(0)
        frame.borderInterruptible:SetAlpha(intBorderShow)
        frame.borderUninterruptible:SetAlpha(0)
        local n = intCfg.nameTextColor or { 1, 1, 1, 1 }
        frame.nameText:SetTextColor(n[1] or 1, n[2] or 1, n[3] or 1, n[4] or 1)
        return
    end

    -- Active cast. current.notInterruptible may be plain or secret. Pass
    -- it (and the per-channel color values) to C_CurveUtil; pipe each
    -- result straight into a Blizzard C method without binding.
    local nint = inst.current.notInterruptible
    local intName  = intCfg.nameTextColor   or { 1, 1, 1, 1 }
    local unintName = unintCfg.nameTextColor or { 1, 1, 1, 1 }

    frame.bgInterruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, 1))
    frame.bgUninterruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, 1, 0))

    frame.bar.interruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, 1))
    frame.bar.uninterruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, 1, 0))

    -- Border show toggles fold INTO the curve params, not as a separate
    -- multiplication afterwards (multiplying a secret curve result would
    -- error). 0 in the relevant slot disables that side regardless.
    frame.borderInterruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, intBorderShow))
    frame.borderUninterruptible:SetAlpha(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintBorderShow, 0))

    frame.nameText:SetTextColor(
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[1] or 1, intName[1] or 1),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[2] or 1, intName[2] or 1),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[3] or 1, intName[3] or 1),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[4] or 1, intName[4] or 1))
end

function Castbar:Start(inst, rec)
    if not rec then return self:Stop(inst) end
    if not rec.duration then
        -- No CastingDuration object available — pre-12.0 client, or the API
        -- failed for some reason. We don't try to fake it; just skip.
        return self:Stop(inst)
    end
    self:EnsureFrame(inst)
    inst.current = rec
    -- Cache showTime on the cast record so onUpdate doesn't have to hit
    -- the cfg() table every frame. Refreshed on Ka0s_KickCD_CONFIG_CHANGED via
    -- OnConfigChanged when the section is "castbar".
    inst.current.showTime = (cfg(inst).showTime ~= false)

    -- CR-17: cast start no longer re-skins the bar. Reskin runs only on
    -- config flips / grid layout / profile change — the structural setup
    -- doesn't depend on the cast record. RenderCast does the cast-specific
    -- work (texture, name, seed bar values, ApplyState).
    self:RenderCast(inst, rec)

    if isVisible(inst) then
        inst.frame:Show()
        ApplyVisibilityMask(inst.frame, inst.unit)
        inst.frame:SetScript("OnUpdate", function() onUpdate(inst) end)
    end
end

function Castbar:Stop(inst)
    inst.current = nil
    local frame = inst.frame
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame.bar.interruptible:SetValue(0)
    frame.bar.uninterruptible:SetValue(0)

    -- Keep the preview visible while unlocked so the user can still drag
    -- the empty bar around. Otherwise hide it.
    local locked = NS.db and NS.db.profile and NS.db.profile.locked
    if (not locked) and isVisible(inst) then
        self:ShowPreview(inst)
    else
        frame:Hide()
    end
end

--- Show a placeholder bar so the user has something to grab while
--- repositioning. Used while the cast bar is unlocked and no target is
--- currently casting.
---
--- CR-17: depends on config (orientation, fonts, sizes, anchors,
--- per-state colors), so we run a full Reskin and then layer a minimal
--- preview-state branch on top — placeholder icon, label, fixed-mid-bar
--- value. RenderCast is NOT used here because there's no real cast
--- record (no duration object, no texture etc.).
function Castbar:ShowPreview(inst)
    local frame = inst.frame
    if not frame then return end
    self:Reskin(inst)    -- runs ApplyState (no-cast branch → interruptible visuals)
    local c = cfg(inst)
    if c.iconSize and c.iconSize > 0 then
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if c.showName ~= false then
        frame.nameText:SetText(truncateName(L["KickCD castbar"], c.nameTruncate))
    else
        frame.nameText:SetText("")
    end
    if c.showTime ~= false then
        frame.timeText:SetText("0.0 / 0.0")
    else
        frame.timeText:SetText("")
    end
    -- Reset both bars' ranges — a previous Start() may have left them at
    -- the last cast's totalDuration, and we want the preview to show a
    -- fixed mid-bar regardless of that.
    frame.bar.interruptible:SetMinMaxValues(0, 1)
    frame.bar.interruptible:SetValue(0.5)
    frame.bar.uninterruptible:SetMinMaxValues(0, 1)
    frame.bar.uninterruptible:SetValue(0.5)
    frame:Show()
    -- Preview is only shown while unlocked (caller's invariant), so the
    -- visibility mode is ignored — leave alpha at 1.
    frame:SetAlpha(1)
end

function Castbar:Reevaluate(inst)
    if not UnitExists(inst.unit) then return self:Stop(inst) end
    if UnitIsDead and UnitIsDead(inst.unit) then return self:Stop(inst) end
    local rec = NS.Compat.GetCastingInfo(inst.unit)
    if rec then
        self:Start(inst, rec)
    else
        self:Stop(inst)
    end
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

-- Bring a unit's instance online: build + skin its frame, apply the lock,
-- register the per-instance UNIT_SPELLCAST_* frames, and snap to any live cast.
function Castbar:EnableUnit(unit)
    local inst = self:GetInstance(unit)
    self:EnsureFrame(inst)
    self:Reskin(inst)
    self:ApplyLock(inst)

    -- UNIT_SPELLCAST_* registrations go through Util.RegisterUnitCastEvent so
    -- the dispatch frame fires only when the event unit IS this instance's unit
    -- (vanilla RegisterEvent would run the handler for every party/raid/nameplate
    -- cast and early-return — thousands of no-op dispatches per minute in a raid).
    -- INTERRUPTIBLE / NOT_INTERRUPTIBLE are dynamic mid-cast events; the initial
    -- value still comes from UnitCastingInfo.notInterruptible captured in
    -- Compat.GetCastingInfo. The returned frames are stashed on the instance so
    -- DisableUnit / OnDisable can release them — AceEvent's UnregisterAllEvents
    -- only knows about its own table, not these frames.
    local Util = NS.Util
    local castEvents = {
        { "UNIT_SPELLCAST_START",             "OnCastStart"               },
        { "UNIT_SPELLCAST_STOP",              "OnCastStop"                },
        { "UNIT_SPELLCAST_FAILED",            "OnCastStop"                },
        { "UNIT_SPELLCAST_INTERRUPTED",       "OnCastStop"                },
        { "UNIT_SPELLCAST_DELAYED",           "OnCastDelayed"             },
        { "UNIT_SPELLCAST_CHANNEL_START",     "OnChannelStart"            },
        { "UNIT_SPELLCAST_CHANNEL_STOP",      "OnCastStop"                },
        { "UNIT_SPELLCAST_CHANNEL_UPDATE",    "OnCastDelayed"             },
        { "UNIT_SPELLCAST_INTERRUPTIBLE",     "OnInterruptibilityChanged" },
        { "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "OnInterruptibilityChanged" },
    }
    for _, e in ipairs(castEvents) do
        inst.eventFrames[#inst.eventFrames + 1] =
            Util.RegisterUnitCastEvent(self, unit, e[1], e[2])
    end
    inst.enabled = true

    -- Snap to the unit's current state on enable in case we logged in staring
    -- at a casting mob.
    self:Reevaluate(inst)
end

-- Tear a unit's instance down: release its dispatch frames, stop any active
-- cast, hide its bar. Used by OnDisable and (Phase 3) runtime enable-gating.
function Castbar:DisableUnit(unit)
    local inst = instances[unit]
    if not inst then return end
    for _, f in ipairs(inst.eventFrames) do f:UnregisterAllEvents() end
    inst.eventFrames = {}
    self:Stop(inst)
    if inst.frame then inst.frame:Hide() end
    inst.enabled = false
end

--- Reconcile every tracked unit's live enable-state against its desired
--- state (NS.Units.IsEnabled). Mirrors IconGrid:ReconcileUnits. Called from
--- OnEnable and from OnConfigChanged for the "general"/"units" sections so
--- toggling the master enable OR a per-unit enable brings the bar into the
--- right state without a /reload — including reviving a unit that was
--- disabled by master-enable being off. EnableUnit already snaps to any
--- live cast via Reevaluate, so a mid-cast focus enable shows immediately.
--- Idempotent: Enable/DisableUnit only run on an actual want-vs-live
--- mismatch.
function Castbar:ReconcileUnits()
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

function Castbar:OnEnable()
    -- Combat transitions arrive via the Ka0s_KickCD_COMBAT_STATE message (State
    -- owns the only PLAYER_REGEN_* registration, so the flag write and the
    -- visibility refresh stay ordered by construction), not raw events here.
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("Ka0s_KickCD_GRID_LAYOUT",     "OnGridLayout")
    self:RegisterMessage("Ka0s_KickCD_COMBAT_STATE",    "OnCombatStateChanged")

    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")

    -- The two GLOBAL unit-change events register at MODULE level via plain
    -- RegisterEvent (NOT RegisterUnitCastEvent, which is for UNIT_SPELLCAST_*).
    -- Each handler re-evaluates only its own unit's instance if live.
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED",          "OnFocusChanged")

    -- Bring every enabled unit online. Focus defaults disabled, so only the
    -- target instance enables here and behavior matches the former singleton.
    self:ReconcileUnits()
end

function Castbar:OnDisable()
    self:UnregisterAllMessages()
    self:UnregisterAllEvents()
    for _, u in ipairs(NS.Units.LIST) do
        self:DisableUnit(u)
    end
end

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
--- OnTargetChanged. Focus defaults disabled, so this is a no-op until the
--- focus instance is enabled (Phase 3).
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
-- the per-instance dispatch frame (already filtered to the instance's unit).
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

--- Print diagnostic info about `unit`'s cast (default "target") and what the
--- bar's logic decided about interruptibility. Wired to /kcd debug castbar.
--- Does NOT call tostring or format on notInterruptible / spellID / name —
--- those may be secret in combat. Uses tostring(type(...)) / boolean
--- branching with `not not` to avoid arithmetic on secrets.
function Castbar:DebugDump(unit)
    local inst = self:GetInstance(unit or "target")
    local print = NS.Util and NS.Util.print or _G.print
    print("castbar state (" .. inst.unit .. "):")

    if not UnitExists(inst.unit) then
        print("  no " .. inst.unit)
        return
    end
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", inst.unit)
    print("  " .. inst.unit .. " = " .. (UnitName(inst.unit) or "?")
        .. ", isUnit="    .. (UnitIsUnit(inst.unit, "player") and "self" or "other")
        .. ", canAttack=" .. tostring(canAttack and true or false))

    if not inst.current then
        print("  no active cast tracked (current = nil)")
        local rec = NS.Compat.GetCastingInfo(inst.unit)
        if rec then
            print("  but Compat.GetCastingInfo returned a record — debug a missed event?")
        end
        return
    end

    print("  current.isChannel = " .. tostring(inst.current.isChannel))
    -- Don't tostring/format secret values. Use type() and a curve eval to
    -- safely report the boolean state without arithmetic on a secret.
    local nintType = type(inst.current.notInterruptible)
    print("  current.notInterruptible: type=" .. nintType
        .. ", isSecret=" .. tostring(_G.issecretvalue and _G.issecretvalue(inst.current.notInterruptible) or false))
    if nintType == "boolean" then
        -- Plain boolean — safe to tostring.
        print("    plain value = " .. tostring(inst.current.notInterruptible))
    elseif nintType == "nil" then
        print("    plain nil (treated as interruptible)")
    else
        -- Likely secret. Use the curve evaluator to surface a safe int.
        if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then
            -- Pass to FontString:SetText via a hidden frame to render and
            -- read back. Cleanest: just say "secret" and trust the curve.
            print("    secret-tainted; visual state determined via "
                .. "C_CurveUtil.EvaluateColorValueFromBoolean")
        end
    end
    print("  duration: " .. (inst.current.duration and "present" or "nil"))
    print("  texture:  type=" .. type(inst.current.texture))
    print("  spellID:  type=" .. type(inst.current.spellID))
    print("  name:     type=" .. type(inst.current.name))

    -- Configured per-state colors as actually read from the live profile
    -- (link-resolved via NS.Units.Castbar). Useful for verifying that
    -- color-picker writes are persisting and that Reskin sees the updates.
    local function fmtColor(c)
        if type(c) ~= "table" then return "(missing)" end
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(
            c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
    end
    local castCfg = cfg(inst)
    local intCfg = castCfg.interruptible   or {}
    local nintCfg = castCfg.uninterruptible or {}
    print("  configured colors:")
    print("    interruptible   bar="    .. fmtColor(intCfg.barColor)
        .. " border=" .. fmtColor(intCfg.borderColor)
        .. " bg="     .. fmtColor(intCfg.bgColor))
    print("    uninterruptible bar="    .. fmtColor(nintCfg.barColor)
        .. " border=" .. fmtColor(nintCfg.borderColor)
        .. " bg="     .. fmtColor(nintCfg.bgColor))

    -- And the colors actually live on the StatusBar widgets right now.
    local function fmtStatusColor(sb)
        if not sb or not sb.GetStatusBarColor then return "(no widget)" end
        local r, g, b, a = sb:GetStatusBarColor()
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(r or 0, g or 0, b or 0, a or 1)
    end
    print("  live SetStatusBarColor:")
    local f = inst.frame
    print("    interruptible   = " .. fmtStatusColor(f and f.bar and f.bar.interruptible))
    print("    uninterruptible = " .. fmtStatusColor(f and f.bar and f.bar.uninterruptible))
end

-- Expose for /kcd debug + future tooling.
NS.Castbar = Castbar


