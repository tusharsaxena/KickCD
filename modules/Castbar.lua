-- modules/Castbar.lua
--
-- NOTE (KCD-19, layout-§1): this file sits in the 1000–1500 LOC "on notice" band.
-- Two peels have kept it under the 1500 hard cap: debug diagnostics
-- (Castbar:DebugDump) to modules/Castbar_Debug.lua, and the config-driven
-- re-skin (Castbar:Reskin — sizing, orientation, insets, spark, fonts, text
-- anchors, per-state textures/colors/borders) to modules/Castbar_Skin.lua.
-- What remains is the instance model, the frame build (EnsureFrame), the
-- per-cast paint (RenderCast), the OnUpdate loop, the lifecycle, and the
-- event/message handlers. The next seam, if it grows back, is the
-- event/message handler block at the bottom.
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
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf
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

--- Read-only accessor for a unit's cast bar frame (or nil if that unit has
--- no live instance). Unlike GetInstance it never creates one — UnitLabel
--- anchors to whatever exists and hides otherwise.
function Castbar:GetCastbarFrame(unit)
    local inst = instances[unit or "target"]
    return inst and inst.frame
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
    -- Step 0: a suspended addon shows nothing. At the SOURCE rather than by
    -- hiding frames from Perf's suspend, because a hidden frame comes back on
    -- the next combat transition or target swap and the suspended arm then
    -- measures the addon still working (performance-§6).
    if NS.Perf and NS.Perf.suspended then return false end
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

-- Auto-size math: convert the icon grid's on-screen long-axis extent into
-- the cast bar's OWN coordinate space. The grid frame carries the master
-- scale (IconGrid:ApplyGeneral SetScale); the cast bar frame does not, so a
-- raw GetWidth()/GetHeight() copy (frame-local, scale-independent) overshoots
-- at any master scale != 1 — that's why "Auto-size to icon grid" only matched
-- the grid width at scale 1. Multiplying by the effective-scale ratio makes
-- the bar's on-screen extent equal the grid's at every scale. Pure/exposed
-- (Castbar.AutoSizeLong) for unit testing; the mock's frames are no-ops.
local function autoSizeLong(gridLong, gridEffScale, barEffScale, fallback)
    if not (gridLong and gridLong > 0) then return fallback end
    local gs = (gridEffScale and gridEffScale > 0) and gridEffScale or 1
    local bs = (barEffScale  and barEffScale  > 0) and barEffScale  or 1
    return math.floor(gridLong * gs / bs)
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
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("castbar") end
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
-- Per-state config resolution
-- ---------------------------------------------------------------------------
--
-- Shared by ApplyState here and by the whole re-skin in
-- modules/Castbar_Skin.lua, which reads them off the module table
-- (Castbar.StateConfig / .INT_FALLBACK / .UNINT_FALLBACK). They stay in this
-- file because ApplyState — the hot per-cast path — is the more frequent
-- caller and this file loads first.

-- Default sub-config used when a profile is missing the per-state nested
-- block (safety net against malformed saved-vars). Mirrors the Database
-- defaults.
local function stateConfig(c, key, fallback)
    local sc = c[key]
    if type(sc) == "table" then return sc end
    return fallback
end

local INT_FALLBACK = {
    statusBarTexture = "Blizzard Raid Bar",
    barColor         = { 1,    0.85, 0.05, 1   },
    bgColor          = { 0,    0,    0,    0.5 },
    nameTextColor    = { 1,    1,    1,    1   },
    borderShow       = false,
    borderTexture    = "Blizzard Tooltip",
    borderColor      = { 0,    0,    0,    1   },
    borderSize       = 1,
}
local UNINT_FALLBACK = {
    statusBarTexture = "Blizzard Raid Bar",
    barColor         = { 0.85, 0.10, 0.10, 1   },
    bgColor          = { 0,    0,    0,    0.5 },
    nameTextColor    = { 1,    1,    1,    1   },
    borderShow       = true,
    borderTexture    = "Blizzard Tooltip",
    borderColor      = { 1,    0.20, 0.20, 1   },
    borderSize       = 2,
}


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
    local __t0 = Perf.on and debugprofilestop()
    local frame   = inst.frame
    local current = inst.current
    local d = current and current.duration
    if not d then
        frame:SetScript("OnUpdate", nil)
        -- Close the bracket on THIS exit too. This is the frame that tears the
        -- OnUpdate handler down at the end of every cast, so it is taken once
        -- per cast — leaving it unclosed under-counts `castTick.calls` by one
        -- per cast and hides the cost of the teardown frame itself.
        if __t0 then Perf.Note("castTick", debugprofilestop() - __t0) end
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
    if __t0 then Perf.Note("castTick", debugprofilestop() - __t0) end
end

--- Four channels out of a color table, defaulted to opaque white.
--- Delegates to Util.Unpack: colors are STORED KEYED (core/Database.lua's
--- `nameTextColor = { r =, g =, b =, a = }`), so the positional read this
--- replaced saw nil on every channel and painted the spell name white no
--- matter what the user picked. Util.Unpack reads either shape, allocates
--- nothing and returns values, so the hot path is unchanged.
local function rgba(c)
    return NS.Util.Unpack(c)
end

--- Preview / no-cast: show interruptible visuals; the uninterruptible side is
--- fully alpha=0. No curve involved — there is no flag to switch on yet.
local function applyPreviewVisuals(frame, intCfg, intBorderShow)
    frame.bgInterruptible:SetAlpha(1)
    frame.bgUninterruptible:SetAlpha(0)
    frame.bar.interruptible:SetAlpha(1)
    frame.bar.uninterruptible:SetAlpha(0)
    frame.borderInterruptible:SetAlpha(intBorderShow)
    frame.borderUninterruptible:SetAlpha(0)
    frame.nameText:SetTextColor(rgba(intCfg.nameTextColor))
end

--- Active cast. `nint` may be plain or secret. Pass it (and the per-channel
--- color values) to C_CurveUtil; pipe each result straight into a Blizzard C
--- method without binding it to a local.
local function applyLiveVisuals(frame, nint, intCfg, unintCfg, intBorderShow, unintBorderShow)
    local ur, ug, ub, ua = rgba(unintCfg.nameTextColor)
    local ir, ig, ib, ia = rgba(intCfg.nameTextColor)

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
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, ur, ir),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, ug, ig),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, ub, ib),
        _G.C_CurveUtil.EvaluateColorValueFromBoolean(nint, ua, ia))
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
        applyPreviewVisuals(frame, intCfg, intBorderShow)
        return
    end
    applyLiveVisuals(frame, inst.current.notInterruptible,
        intCfg, unintCfg, intBorderShow, unintBorderShow)
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
    -- force: EnsureFrame may have just built the widgets, which start with no
    -- geometry, while the instance can still carry a matching structure
    -- signature from before it was disabled. Once per enable, so free.
    self:Reskin(inst, true)
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
    -- While suspended the desired state is "nothing runs"; without this the next
    -- CONFIG_CHANGED would re-create all 10 dispatch frames per unit mid-capture.
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
--- Resume can re-arm the same set without re-running the rest of the enable
--- path. Idempotent: AceEvent keys on (event, target).
function Castbar:RegisterLifecycleEvents()
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")

    -- The two GLOBAL unit-change events register at MODULE level via plain
    -- RegisterEvent (NOT RegisterUnitCastEvent, which is for UNIT_SPELLCAST_*).
    -- Each handler re-evaluates only its own unit's instance if live.
    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED",          "OnFocusChanged")
end

--- Make this module inert for a performance capture, without a /reload and
--- without touching `inst.enabled` (the user's setting). Drops the module's game
--- events and the private per-unit dispatch frames, and stops any in-flight cast
--- animation — Stop() nils the per-frame OnUpdate, which is this addon's only
--- true 60 Hz handler and therefore the thing most worth silencing.
---
--- Messages stay registered: Resume republishes on the bus and a module that had
--- dropped its subscriptions would never hear it.
function Castbar:Suspend()
    self:UnregisterAllEvents()
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst then
            for _, f in ipairs(inst.eventFrames or {}) do f:UnregisterAllEvents() end
            inst.eventFrames = {}
            self:Stop(inst)
            if inst.frame then inst.frame:Hide() end
        end
    end
end

--- Restore from CURRENT state, not from a snapshot taken at suspend time, so a
--- unit toggled while suspended comes back correctly.
function Castbar:Resume()
    self:RegisterLifecycleEvents()
    -- Suspend left `enabled` true while releasing the frames, so ReconcileUnits
    -- would consider each instance already reconciled and never rebuild them.
    for _, u in ipairs(NS.Units.LIST) do
        local inst = instances[u]
        if inst and inst.enabled and #(inst.eventFrames or {}) == 0 then
            inst.enabled = false
        end
    end
    self:ReconcileUnits()
end

function Castbar:OnEnable()
    -- Combat transitions arrive via the Ka0s_KickCD_COMBAT_STATE message (State
    -- owns the only PLAYER_REGEN_* registration, so the flag write and the
    -- visibility refresh stay ordered by construction), not raw events here.
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("Ka0s_KickCD_GRID_LAYOUT",     "OnGridLayout")
    self:RegisterMessage("Ka0s_KickCD_COMBAT_STATE",    "OnCombatStateChanged")

    self:RegisterLifecycleEvents()

    -- Bring every enabled unit online. Focus is enabled by default; a disabled/absent
    -- focus instance is a cheap no-op here.
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
--- OnTargetChanged. Focus is enabled by default; a disabled/absent focus
--- instance is a cheap no-op here.
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

-- ---------------------------------------------------------------------------
-- Exposed for /kcd debug + unit testing
-- ---------------------------------------------------------------------------
--
-- These are pure file-locals with no frame dependency. Publishing them on the
-- module is the established idiom for making that logic reachable from the
-- headless harness (AutoSizeLong set the precedent); nothing inside the addon
-- calls them through these fields.
Castbar.AutoSizeLong  = autoSizeLong
Castbar.UnpackColor   = unpackColor
Castbar.TruncateName  = truncateName
Castbar.StateConfig   = stateConfig
Castbar.ToSetPoint    = toSetPoint
Castbar.FetchStatusBarTexture = fetchStatusBarTexture
Castbar.FetchBorderTexture    = fetchBorderTexture
Castbar.FetchFont     = fetchFont
Castbar.INT_FALLBACK   = INT_FALLBACK
Castbar.UNINT_FALLBACK = UNINT_FALLBACK

-- Not a test hook: modules/Castbar_Skin.lua genuinely calls this to resolve the
-- auto-size reference frame, and the payload-preferred / accessor-fallback
-- policy must stay in exactly one place.
Castbar.ResolveGridFrame = resolveGridFrame
