-- modules/Castbar.lua — KickCD v0.2
--
-- Owns the KickCDCastbar frame: a custom-drawn StatusBar with icon, spell
-- name, and remaining-time text that mirrors the player's current target
-- cast / channel. Independently movable from the icon grid; visibility is
-- gated on db.profile.castbar.enabled (sub-module enable) AND
-- db.profile.enabled (master enable) AND db.profile.visibility (the
-- addon-wide "General visibility" mode also honored by IconGrid; in
-- "in_combat" mode the bar additionally requires KickCD.State.inCombat = true).
-- Drag-lock follows db.profile.locked, the same global lock the icon
-- grid honors.
--
-- Listens to:
--   PLAYER_TARGET_CHANGED        -> re-evaluate; show or hide
--   UNIT_SPELLCAST_START         -> on unit=="target", begin cast
--   UNIT_SPELLCAST_STOP          -> on unit=="target", hide
--   UNIT_SPELLCAST_FAILED        -> on unit=="target", hide
--   UNIT_SPELLCAST_INTERRUPTED   -> on unit=="target", hide
--   UNIT_SPELLCAST_DELAYED       -> on unit=="target", re-evaluate
--   UNIT_SPELLCAST_CHANNEL_START -> on unit=="target", begin channel
--   UNIT_SPELLCAST_CHANNEL_STOP  -> on unit=="target", hide
--   UNIT_SPELLCAST_CHANNEL_UPDATE-> on unit=="target", re-evaluate
--
--   KickCD_CONFIG_CHANGED  -> "castbar" reskins/relays the bar; "general"
--                             re-applies lock + anchor; other sections ignored.
--   KickCD_PROFILE_CHANGED -> re-anchor + reskin + re-evaluate.
--   KickCD_GRID_LAYOUT     -> re-anchor (in PRIMARY anchor mode the primary
--                             icon button reference may have changed) and
--                             re-apply auto-size (the grid frame may have
--                             resized).
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

local KickCD  = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Castbar = KickCD:NewModule("Castbar", "AceEvent-3.0")
local L       = KickCD.L

-- ---------------------------------------------------------------------------
-- Module-local state
-- ---------------------------------------------------------------------------

local frame   -- the cast-bar Frame; created lazily in EnsureFrame()
local current -- active cast record (nil when nothing is being cast)

-- Combat state lives in KickCD.State.inCombat (core/State.lua) — a
-- shared, single-owner flag driven off the PLAYER_REGEN_* events in
-- one place. Reading InCombatLockdown() inside the regen-disabled
-- handler is unreliable (the lockdown state lags the event by a
-- frame), so we maintain the flag via the events themselves; this
-- module just reads the shared one.

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function cfg()
    return (KickCD.db and KickCD.db.profile and KickCD.db.profile.castbar) or {}
end

local function master()
    local p = KickCD.db and KickCD.db.profile
    if not p then return true end
    return p.enabled ~= false
end

-- Honors the addon-wide visibility mode (db.profile.visibility):
--   * "always"          — usual behavior (bar shows during target casts).
--   * "in_combat"       — additionally requires KickCD.State.inCombat = true.
--                         A cast that starts on a target while we're out
--                         of combat (rare but possible — friendly NPCs)
--                         is suppressed.
--   * "target_casting"  — equivalent to "always" for the cast bar; the
--                         cast bar already only shows during target
--                         casts so this mode adds no extra restriction.
--   * "target_casting_interruptible"
--                       — Show during ANY hostile target cast; an alpha
--                         mask (ApplyVisibilityMask, fed via SetAlphaFromBoolean)
--                         then hides the bar when the cast is uninterruptible.
--                         The two-step gate is required because 12.0
--                         secret-taints notInterruptible — Lua can't make
--                         the boolean decision but the C-side
--                         SetAlphaFromBoolean accepts the secret directly.
--                         Friendly / self casts are excluded by IsHostileUnitCasting.
-- While unlocked the visibility mode is ignored — the user is moving
-- the bar and needs to see it regardless.
local function isVisible()
    local profile = KickCD.db and KickCD.db.profile
    if not (master() and cfg().enabled ~= false) then return false end
    if profile and profile.locked == false then return true end
    local mode = (profile and profile.visibility) or "always"
    if mode == "in_combat" then
        return KickCD.State.inCombat
    elseif mode == "target_casting_interruptible" then
        return KickCD.State.IsHostileUnitCasting
           and KickCD.State.IsHostileUnitCasting("target")
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
local function ApplyVisibilityMask(barFrame)
    if not barFrame then return end
    local profile = KickCD.db and KickCD.db.profile
    local unlocked = profile and profile.locked == false
    local mode = (profile and profile.visibility) or "always"
    if not unlocked
       and mode == "target_casting_interruptible"
       and KickCD.State.ApplyInterruptibleAlpha
       and KickCD.State.ApplyInterruptibleAlpha(barFrame, "target", 1) then
        return
    end
    barFrame:SetAlpha(1)
end

local function unpackColor(c, fr, fg, fb, fa)
    if not c then return fr or 1, fg or 1, fb or 1, fa or 1 end
    return KickCD.Util.Unpack(c)
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
    if issecretvalue and issecretvalue(name) then return name end
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

local function onDragStart(self)
    if KickCD.db and KickCD.db.profile and KickCD.db.profile.locked then return end
    self:StartMoving()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    if KickCD.db and KickCD.db.profile then
        KickCD.db.profile.anchors = KickCD.db.profile.anchors or {}
        KickCD.db.profile.anchors.castbar = KickCD.Util.SaveAnchor(self)
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
function Castbar:ApplyAnchor()
    if not frame then return end
    local c = cfg()
    local mode = c.anchorMode or "FREE"

    if mode == "PRIMARY" then
        local target
        if KickCD.IconGrid and KickCD.IconGrid.GetPrimaryIcon then
            target = KickCD.IconGrid:GetPrimaryIcon()
        end
        if not target and KickCD.IconGrid and KickCD.IconGrid.GetGridFrame then
            target = KickCD.IconGrid:GetGridFrame()
        end
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

    local saved = KickCD.db and KickCD.db.profile
        and KickCD.db.profile.anchors and KickCD.db.profile.anchors.castbar
    KickCD.Util.ApplyAnchor(frame, saved or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 })
end

function Castbar:ApplyLock()
    if not frame then return end
    local c              = cfg()
    local primaryAnchor  = (c.anchorMode == "PRIMARY")
    local profileLocked  = KickCD.db and KickCD.db.profile and KickCD.db.profile.locked
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
    if not current then
        if (not profileLocked) and isVisible() then
            self:ShowPreview()
        else
            frame:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

function Castbar:EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "KickCDCastbar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Initial anchor — ApplyAnchor() handles both FREE and PRIMARY modes.
    -- Called again at OnEnable / OnConfigChanged / OnGridLayout time.
    self:ApplyAnchor()

    frame:SetScript("OnDragStart", onDragStart)
    frame:SetScript("OnDragStop",  onDragStop)

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
local INSIDE_INSET  = KickCD.Const.CASTBAR_INSIDE_INSET
local OUTSIDE_INSET = KickCD.Const.CASTBAR_OUTSIDE_INSET

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

function Castbar:ApplyConfig()
    if not frame then return end
    local c = cfg()

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
    -- user-configured. Re-runs on every KickCD_GRID_LAYOUT so the
    -- bar tracks the grid as icons are added / removed / resized.
    if c.autoSize and KickCD.IconGrid and KickCD.IconGrid.GetGridFrame then
        local gridFrame = KickCD.IconGrid:GetGridFrame()
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
    self:ApplyState()

    -- Re-paint the icon if a cast is in progress (texture coords were already
    -- set in EnsureFrame; only the texture file itself depends on cast state).
    if current and current.texture and showIcon then
        frame.icon:SetTexture(current.texture)
    end

    -- Re-paint the spell name when a cast is active so a config
    -- change to nameTruncate / showName takes effect immediately
    -- without waiting for the next cast. Truncate cap is read live
    -- from cfg() and the secret-value short-circuit in
    -- truncateName keeps protected-cast names safe.
    if current and c.showName ~= false then
        frame.nameText:SetText(truncateName(current.name, c.nameTruncate))
    elseif c.showName == false then
        frame.nameText:SetText("")
    end
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

local function onUpdate(self)
    local d = current and current.duration
    if not d then
        self:SetScript("OnUpdate", nil)
        return
    end

    -- Both stacked StatusBars get the same range and value every frame so
    -- their inner textures stay in sync — only one of them is alpha-visible
    -- at a time (curve-switched in ApplyState off current.notInterruptible).
    -- Duration-method returns may be secret in combat for protected casts;
    -- pass them DIRECTLY as arguments to Blizzard C methods (SetMinMaxValues
    -- / SetValue / SetFormattedText) and never bind to a Lua local.
    frame.bar.interruptible:SetMinMaxValues(0, d:GetTotalDuration())
    frame.bar.uninterruptible:SetMinMaxValues(0, d:GetTotalDuration())
    if current.isChannel then
        frame.bar.interruptible:SetValue(d:GetRemainingDuration())
        frame.bar.uninterruptible:SetValue(d:GetRemainingDuration())
    else
        frame.bar.interruptible:SetValue(d:GetElapsedDuration())
        frame.bar.uninterruptible:SetValue(d:GetElapsedDuration())
    end

    if cfg().showTime ~= false then
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
function Castbar:ApplyState()
    if not frame then return end
    local c        = cfg()
    local intCfg   = stateConfig(c, "interruptible",   INT_FALLBACK)
    local unintCfg = stateConfig(c, "uninterruptible", UNINT_FALLBACK)

    local intBorderShow  = intCfg.borderShow   and 1 or 0
    local unintBorderShow = unintCfg.borderShow and 1 or 0

    if not current then
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
    local nint = current.notInterruptible
    local intName  = intCfg.nameTextColor   or { 1, 1, 1, 1 }
    local unintName = unintCfg.nameTextColor or { 1, 1, 1, 1 }

    frame.bgInterruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, 1))
    frame.bgUninterruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, 1, 0))

    frame.bar.interruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, 1))
    frame.bar.uninterruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, 1, 0))

    -- Border show toggles fold INTO the curve params, not as a separate
    -- multiplication afterwards (multiplying a secret curve result would
    -- error). 0 in the relevant slot disables that side regardless.
    frame.borderInterruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, 0, intBorderShow))
    frame.borderUninterruptible:SetAlpha(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintBorderShow, 0))

    frame.nameText:SetTextColor(
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[1] or 1, intName[1] or 1),
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[2] or 1, intName[2] or 1),
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[3] or 1, intName[3] or 1),
        C_CurveUtil.EvaluateColorValueFromBoolean(nint, unintName[4] or 1, intName[4] or 1))
end

function Castbar:Start(rec)
    if not rec then return self:Stop() end
    if not rec.duration then
        -- No CastingDuration object available — pre-12.0 client, or the API
        -- failed for some reason. We don't try to fake it; just skip.
        return self:Stop()
    end
    self:EnsureFrame()
    current = rec
    self:ApplyConfig()    -- runs ApplyState too, picking up notInterruptible

    -- name / texture may themselves be secret in combat for protected
    -- casts, but Texture:SetTexture / FontString:SetText accept secret
    -- args without erroring (the protection is on arithmetic). Pass them
    -- through; the bar renders the spell's real icon and name.
    if cfg().iconSize and cfg().iconSize > 0 and rec.texture then
        frame.icon:SetTexture(rec.texture)
    end
    if cfg().showName ~= false then
        frame.nameText:SetText(truncateName(rec.name, cfg().nameTruncate))
    else
        frame.nameText:SetText("")
    end

    -- Seed both bars from the duration object so we don't flash a 0% bar
    -- before the first OnUpdate tick. Pass duration methods directly to
    -- the StatusBar C methods; never bind to locals.
    local d = rec.duration
    frame.bar.interruptible:SetMinMaxValues(0, d:GetTotalDuration())
    frame.bar.uninterruptible:SetMinMaxValues(0, d:GetTotalDuration())
    if rec.isChannel then
        frame.bar.interruptible:SetValue(d:GetRemainingDuration())
        frame.bar.uninterruptible:SetValue(d:GetRemainingDuration())
    else
        frame.bar.interruptible:SetValue(d:GetElapsedDuration())
        frame.bar.uninterruptible:SetValue(d:GetElapsedDuration())
    end

    if isVisible() then
        frame:Show()
        ApplyVisibilityMask(frame)
        frame:SetScript("OnUpdate", onUpdate)
    end
end

function Castbar:Stop()
    current = nil
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame.bar.interruptible:SetValue(0)
    frame.bar.uninterruptible:SetValue(0)

    -- Keep the preview visible while unlocked so the user can still drag
    -- the empty bar around. Otherwise hide it.
    local locked = KickCD.db and KickCD.db.profile and KickCD.db.profile.locked
    if (not locked) and isVisible() then
        self:ShowPreview()
    else
        frame:Hide()
    end
end

--- Show a placeholder bar so the user has something to grab while
--- repositioning. Used while the cast bar is unlocked and no target is
--- currently casting.
function Castbar:ShowPreview()
    if not frame then return end
    self:ApplyConfig()    -- runs ApplyState (no-cast branch → interruptible visuals)
    if cfg().iconSize and cfg().iconSize > 0 then
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if cfg().showName ~= false then
        frame.nameText:SetText(truncateName(L["KickCD castbar"], cfg().nameTruncate))
    else
        frame.nameText:SetText("")
    end
    if cfg().showTime ~= false then
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

function Castbar:Reevaluate()
    if not UnitExists("target") then return self:Stop() end
    if UnitIsDead and UnitIsDead("target") then return self:Stop() end
    local rec = KickCD.Compat.GetCastingInfo("target")
    if rec then
        self:Start(rec)
    else
        self:Stop()
    end
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

function Castbar:OnEnable()
    -- Combat flag is owned by core/State.lua's bootstrap listener, so
    -- this module no longer seeds it on enable.
    self:EnsureFrame()
    self:ApplyConfig()
    self:ApplyLock()

    self:RegisterEvent("PLAYER_REGEN_DISABLED",         "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",          "OnRegenEnabled")
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START",          "OnCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP",           "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED",         "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",    "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_DELAYED",        "OnCastDelayed")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START",  "OnChannelStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnCastDelayed")
    -- Catch dynamic interruptibility transitions mid-cast (e.g. boss casts
    -- that toggle interrupt-immunity via an aura). The events fire on the
    -- transition, not at cast start, so the initial value still comes from
    -- UnitCastingInfo.notInterruptible captured in Compat.GetCastingInfo.
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE",     "OnInterruptibilityChanged")
    self:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "OnInterruptibilityChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")

    self:RegisterMessage("KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("KickCD_GRID_LAYOUT",     "OnGridLayout")

    -- Snap to the current target's state on enable in case we logged in
    -- staring at a casting mob.
    self:Reevaluate()
end

function Castbar:OnDisable()
    self:UnregisterAllEvents()
    self:UnregisterAllMessages()
    self:Stop()
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

function Castbar:OnTargetChanged()
    self:Reevaluate()
end

-- Re-evaluate the bar on combat-state transitions so it shows / hides
-- as the visibility mode dictates. In "in_combat" mode entering combat
-- reveals the bar (if a target cast is ongoing), and leaving combat
-- tears it down even if the cast continues. The combat flag itself is
-- owned by core/State.lua's bootstrap listener; these handlers run
-- only for their side effect (Reevaluate / Stop).
function Castbar:OnRegenDisabled()
    if isVisible() then
        self:Reevaluate()
    else
        self:Stop()
    end
end

function Castbar:OnRegenEnabled()
    if isVisible() then
        self:Reevaluate()
    else
        self:Stop()
    end
end

function Castbar:OnPlayerEnteringWorld()
    self:Reevaluate()
end

function Castbar:OnCastStart(_evt, unit)
    if unit ~= "target" then return end
    if not isVisible() then return end
    local rec = KickCD.Compat.GetCastingInfo("target")
    if rec then self:Start(rec) end
end

function Castbar:OnChannelStart(_evt, unit)
    if unit ~= "target" then return end
    if not isVisible() then return end
    local rec = KickCD.Compat.GetChannelInfo("target")
    if rec then self:Start(rec) end
end

function Castbar:OnCastStop(_evt, unit)
    if unit ~= "target" then return end
    self:Stop()
end

function Castbar:OnInterruptibilityChanged(evt, unit)
    if unit ~= "target" then return end
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
    -- docs/CLAUDE_CASTBAR.md "Plain-after-flip" and
    -- docs/CLAUDE_SECRET_VALUES.md for the full rationale.
    if current then
        current.notInterruptible = (evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        self:ApplyState()
    end
    -- For the "target_casting_interruptible" mode the bar STAYS shown for
    -- any hostile cast (so we can hand the secret-tainted notInterruptible
    -- flag to SetAlphaFromBoolean) — re-driving the alpha mask is the
    -- only thing that needs to happen when the flag flips. Falling back
    -- to Stop/Reevaluate here would race with the cast lifecycle and
    -- reorder the very Show that the alpha mask depends on.
    if isVisible() then
        if not current then
            self:Reevaluate()
        else
            ApplyVisibilityMask(frame)
        end
    else
        self:Stop()
    end
end

function Castbar:OnCastDelayed(_evt, unit)
    if unit ~= "target" then return end
    if not current then return end
    -- Re-query so the timeline reflects the pushback / haste change.
    -- notInterruptible could in principle change too (e.g. an aura that
    -- toggles interruptibility mid-cast), so re-apply the per-state
    -- visuals as well.
    local rec = KickCD.Compat.GetCastingInfo("target")
    if rec then
        current = rec
        self:ApplyState()
    end
end

-- ---------------------------------------------------------------------------
-- Message handlers
-- ---------------------------------------------------------------------------

function Castbar:OnConfigChanged(_evt, payload)
    local section = payload and payload.section
    if section == "castbar" then
        -- Anchor mode + offsets and orientation/grow may have changed; apply
        -- both before reskin so ApplyConfig sees the right frame size when
        -- it computes auto-size and child anchors.
        self:ApplyAnchor()
        self:ApplyConfig()
        if not isVisible() then
            self:Stop()
        else
            -- castbar.enabled may have just flipped from false → true; pick
            -- up an in-progress cast so the bar appears immediately.
            if not current then self:Reevaluate() end
            self:ApplyLock()
        end
    elseif section == "general" then
        -- Master enable / lock flag may have flipped.
        self:ApplyLock()
        if not isVisible() then
            self:Stop()
        else
            self:Reevaluate()
        end
    end
end

function Castbar:OnProfileChanged()
    self:ApplyAnchor()
    self:ApplyConfig()
    self:ApplyLock()
    if isVisible() then self:Reevaluate() else self:Stop() end
end

--- Fired by IconGrid after every Layout()/BuildActiveList() pass. The grid
--- frame may have resized (auto-size needs to track) and the primary icon
--- button reference may have changed (PRIMARY anchor mode needs to retarget).
function Castbar:OnGridLayout()
    if not frame then return end
    local c = cfg()
    -- PRIMARY mode: re-target the primary icon button (which may have been
    -- released to pool and a new one acquired).
    if c.anchorMode == "PRIMARY" then
        self:ApplyAnchor()
    end
    -- Auto-size: re-run ApplyConfig so the bar's dimensions track the grid's
    -- current footprint. Skip the no-op ApplyConfig when neither is active.
    if c.autoSize then
        self:ApplyConfig()
    end
end

--- Print diagnostic info about the current target's cast and what the
--- bar's logic decided about interruptibility. Wired to /kcd debug castbar.
--- Does NOT call tostring or format on notInterruptible / spellID / name —
--- those may be secret in combat. Uses tostring(type(...)) / boolean
--- branching with `not not` to avoid arithmetic on secrets.
function Castbar:DebugDump()
    local print = KickCD.Util and KickCD.Util.print or _G.print
    print("|cff00ff00KickCD|r castbar state:")

    if not UnitExists("target") then
        print("  no target")
        return
    end
    local canAttack = _G.UnitCanAttack and _G.UnitCanAttack("player", "target")
    print("  target = " .. (UnitName("target") or "?")
        .. ", isUnit="    .. (UnitIsUnit("target", "player") and "self" or "other")
        .. ", canAttack=" .. tostring(canAttack and true or false))

    if not current then
        print("  no active cast tracked (current = nil)")
        local rec = KickCD.Compat.GetCastingInfo("target")
        if rec then
            print("  but Compat.GetCastingInfo returned a record — debug a missed event?")
        end
        return
    end

    print("  current.isChannel = " .. tostring(current.isChannel))
    -- Don't tostring/format secret values. Use type() and a curve eval to
    -- safely report the boolean state without arithmetic on a secret.
    local nintType = type(current.notInterruptible)
    print("  current.notInterruptible: type=" .. nintType
        .. ", isSecret=" .. tostring(_G.issecretvalue and _G.issecretvalue(current.notInterruptible) or false))
    if nintType == "boolean" then
        -- Plain boolean — safe to tostring.
        print("    plain value = " .. tostring(current.notInterruptible))
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
    print("  duration: " .. (current.duration and "present" or "nil"))
    print("  texture:  type=" .. type(current.texture))
    print("  spellID:  type=" .. type(current.spellID))
    print("  name:     type=" .. type(current.name))

    -- Configured per-state colors as actually read from the live db.profile.
    -- Useful for verifying that color-picker writes are persisting and that
    -- ApplyConfig sees the updated values.
    local function fmtColor(c)
        if type(c) ~= "table" then return "(missing)" end
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(
            c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
    end
    local cfg = KickCD.db and KickCD.db.profile and KickCD.db.profile.castbar or {}
    local intCfg = cfg.interruptible   or {}
    local nintCfg = cfg.uninterruptible or {}
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
    print("    interruptible   = " .. fmtStatusColor(frame and frame.bar and frame.bar.interruptible))
    print("    uninterruptible = " .. fmtStatusColor(frame and frame.bar and frame.bar.uninterruptible))
end

-- Expose for /kcd debug + future tooling.
KickCD.Castbar = Castbar


