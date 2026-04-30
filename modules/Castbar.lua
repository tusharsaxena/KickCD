-- modules/Castbar.lua — KickCD v0.2
--
-- Owns the KickCDCastbar frame: a custom-drawn StatusBar with icon, spell
-- name, and remaining-time text that mirrors the player's current target
-- cast / channel. Independently movable from the icon grid; visibility is
-- gated on db.profile.castbar.enabled (sub-module enable) AND
-- db.profile.enabled (master enable). Drag-lock follows db.profile.locked,
-- the same global lock the icon grid honors.
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
--   This is the same technique UltimateCastbars uses for the
--   target/focus cast bar. The spell `name` / `texture` may themselves
--   be secret in combat, but FontString:SetText / Texture:SetTexture
--   accept secret args without erroring (Blizzard's protection is on
--   arithmetic, not on UI render calls).

local KickCD  = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Castbar = KickCD:NewModule("Castbar", "AceEvent-3.0")
local L       = KickCD.L

-- ---------------------------------------------------------------------------
-- Module-local state
-- ---------------------------------------------------------------------------

local frame   -- the cast-bar Frame; created lazily in EnsureFrame()
local current -- active cast record (nil when nothing is being cast)

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

local function isVisible()
    return master() and cfg().enabled ~= false
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
-- Lock / drag persistence
-- ---------------------------------------------------------------------------

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

function Castbar:ApplyLock()
    if not frame then return end
    local locked = KickCD.db and KickCD.db.profile and KickCD.db.profile.locked
    if locked then
        frame:RegisterForDrag()
        frame:EnableMouse(false)
        if frame.dragHint then frame.dragHint:Hide() end
        -- When locked, the bar is only visible during a real cast — hide
        -- if nothing is being cast right now.
        if not current then frame:Hide() end
    else
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if frame.dragHint then frame.dragHint:Show() end
        -- When unlocked, force-show a preview state so the user has a
        -- frame to grab even when no target is casting. ShowPreview is a
        -- no-op while a real cast is animating.
        if not current and isVisible() then
            self:ShowPreview()
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

    local anchor = KickCD.db and KickCD.db.profile
        and KickCD.db.profile.anchors and KickCD.db.profile.anchors.castbar
    KickCD.Util.ApplyAnchor(frame, anchor or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 })

    frame:SetScript("OnDragStart", onDragStart)
    frame:SetScript("OnDragStop",  onDragStop)

    -- Background texture (drawn behind the bar).
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetColorTexture(0, 0, 0, 0.5)

    -- The actual cast bar — a StatusBar; we drive its value through
    -- :SetValue(0..1) from OnUpdate using only plain (non-secret) numbers.
    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0)

    -- Spark texture (overlay marking the leading edge of the bar fill).
    frame.spark = frame.bar:CreateTexture(nil, "OVERLAY")
    frame.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetSize(20, 30)

    -- Icon texture (square; height matches the bar).
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop the Blizzard border

    -- Spell name (anchored relative to bar in ApplyConfig).
    frame.nameText = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetWordWrap(false)

    -- Remaining time (anchored to the right edge of the bar in ApplyConfig).
    frame.timeText = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetJustifyH("RIGHT")

    -- Four 1-pixel-thin edge textures form the border (same pattern the
    -- icon grid uses, no BackdropTemplate).
    frame.borders = {
        top    = frame:CreateTexture(nil, "BORDER"),
        bottom = frame:CreateTexture(nil, "BORDER"),
        left   = frame:CreateTexture(nil, "BORDER"),
        right  = frame:CreateTexture(nil, "BORDER"),
    }

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

function Castbar:ApplyConfig()
    if not frame then return end
    local c = cfg()

    local width  = math.max(40, c.width  or 250)
    local height = math.max(8,  c.height or 24)
    frame:SetSize(width, height)

    -- Background color
    frame.bg:SetColorTexture(unpackColor(c.bgColor, 0, 0, 0, 0.5))

    -- Bar texture + color
    frame.bar:SetStatusBarTexture(fetchStatusBarTexture(c.statusBarTexture))
    frame.bar:SetStatusBarColor(unpackColor(c.barColor, 0.7, 0.2, 0.2, 1))

    -- Icon position decides bar inset.
    local iconSize = math.max(0, c.iconSize or height)
    if iconSize > height then iconSize = height end
    local showIcon = iconSize > 0
    frame.icon:ClearAllPoints()
    frame.bar:ClearAllPoints()
    if showIcon then
        frame.icon:Show()
        frame.icon:SetSize(iconSize, iconSize)
        if (c.iconPosition or "LEFT") == "RIGHT" then
            frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, 0)
            frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -iconSize, 0)
        else
            frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      iconSize, 0)
            frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
    else
        frame.icon:Hide()
        frame.bar:SetAllPoints(frame)
    end

    -- Spark — anchor to the bar's inner status texture's RIGHT edge.
    -- Blizzard resizes that texture C-side as the bar value changes, so the
    -- spark follows the fill edge automatically — for both casts (fill grows
    -- left → right) and channels (fill shrinks right → left). This sidesteps
    -- the per-frame `barWidth * (elapsed / total)` arithmetic that would
    -- error on a CastingDuration secret return.
    if c.showSpark ~= false then
        frame.spark:Show()
        frame.spark:SetHeight(height + 6)
        frame.spark:ClearAllPoints()
        local fill = frame.bar:GetStatusBarTexture()
        if fill then
            frame.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
        end
    else
        frame.spark:Hide()
    end

    -- Font for both labels.
    local fontPath = fetchFont(c.font)
    local fontSize = c.fontSize or 12
    local fontFlags = c.fontFlags
    if fontFlags == "NONE" or fontFlags == nil then fontFlags = "" end

    frame.nameText:SetFont(fontPath, fontSize, fontFlags)
    frame.timeText:SetFont(fontPath, fontSize, fontFlags)
    frame.nameText:SetTextColor(1, 1, 1, 1)
    frame.timeText:SetTextColor(1, 1, 1, 1)

    -- Re-anchor labels inside the bar.
    frame.nameText:ClearAllPoints()
    frame.timeText:ClearAllPoints()
    frame.nameText:SetPoint("LEFT",  frame.bar, "LEFT",   4, 0)
    frame.nameText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
    frame.timeText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)

    if c.showName == false then frame.nameText:Hide() else frame.nameText:Show() end
    if c.showTime == false then frame.timeText:Hide() else frame.timeText:Show() end

    -- Border (four edge lines hugging the outside of the frame).
    local borderShow = c.borderShow == true
    local borderSize = math.max(1, c.borderSize or 1)
    local br, bg, bb, ba = unpackColor(c.borderColor, 0, 0, 0, 1)
    for _, t in pairs(frame.borders) do
        t:ClearAllPoints()
        if borderShow then
            t:SetColorTexture(br, bg, bb, ba)
            t:Show()
        else
            t:Hide()
        end
    end
    if borderShow then
        frame.borders.top:SetPoint("TOPLEFT",    frame, "TOPLEFT",     -borderSize,  borderSize)
        frame.borders.top:SetPoint("TOPRIGHT",   frame, "TOPRIGHT",     borderSize,  borderSize)
        frame.borders.top:SetHeight(borderSize)

        frame.borders.bottom:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  -borderSize, -borderSize)
        frame.borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  borderSize, -borderSize)
        frame.borders.bottom:SetHeight(borderSize)

        frame.borders.left:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -borderSize,  borderSize)
        frame.borders.left:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  -borderSize, -borderSize)
        frame.borders.left:SetWidth(borderSize)

        frame.borders.right:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",     borderSize,  borderSize)
        frame.borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  borderSize, -borderSize)
        frame.borders.right:SetWidth(borderSize)
    end

    -- Re-paint the icon if a cast is in progress (texture coords were already
    -- set in EnsureFrame; only the texture file itself depends on cast state).
    if current and current.texture and showIcon then
        frame.icon:SetTexture(current.texture)
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

    -- All four return values may be secret in combat for protected casts.
    -- Hand them DIRECTLY to Blizzard C methods — never bind to a local for
    -- comparison or arithmetic. SetMinMaxValues / SetValue accept secret
    -- args without erroring; SetFormattedText handles the format C-side.
    frame.bar:SetMinMaxValues(0, d:GetTotalDuration())
    if current.isChannel then
        frame.bar:SetValue(d:GetRemainingDuration())
    else
        frame.bar:SetValue(d:GetElapsedDuration())
    end

    if cfg().showTime ~= false then
        frame.timeText:SetFormattedText(
            "%.1f / %.1f", d:GetRemainingDuration(), d:GetTotalDuration())
    end
    -- The spark's position is driven entirely by Blizzard reanchoring the
    -- bar's inner status texture; nothing to do here.
end

function Castbar:Start(rec)
    if not rec then return self:Stop() end
    if not rec.duration then
        -- No CastingDuration object available — pre-12.0 client, or the API
        -- failed for some reason. We don't try to fake it; just skip.
        return self:Stop()
    end
    self:EnsureFrame()
    self:ApplyConfig()
    current = rec

    -- name / texture may themselves be secret in combat for protected
    -- casts, but Texture:SetTexture / FontString:SetText accept secret
    -- args without erroring (the protection is on arithmetic). Pass them
    -- through; the bar renders the spell's real icon and name.
    if cfg().iconSize and cfg().iconSize > 0 and rec.texture then
        frame.icon:SetTexture(rec.texture)
    end
    if cfg().showName ~= false then
        frame.nameText:SetText(rec.name or "")
    else
        frame.nameText:SetText("")
    end

    -- Seed the bar from the duration object so we don't flash a 0% bar
    -- before the first OnUpdate tick. Same secret-safe pattern as OnUpdate
    -- — pass the method calls straight to the C side, never bind locals.
    local d = rec.duration
    frame.bar:SetMinMaxValues(0, d:GetTotalDuration())
    if rec.isChannel then
        frame.bar:SetValue(d:GetRemainingDuration())
    else
        frame.bar:SetValue(d:GetElapsedDuration())
    end

    if isVisible() then
        frame:Show()
        frame:SetScript("OnUpdate", onUpdate)
    end
end

function Castbar:Stop()
    current = nil
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame.bar:SetValue(0)

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
    self:ApplyConfig()
    if cfg().iconSize and cfg().iconSize > 0 then
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if cfg().showName ~= false then
        frame.nameText:SetText(L["KickCD castbar"])
    else
        frame.nameText:SetText("")
    end
    if cfg().showTime ~= false then
        frame.timeText:SetText("0.0 / 0.0")
    else
        frame.timeText:SetText("")
    end
    -- Reset the bar's range — a previous Start() may have left it at the
    -- last cast's totalDuration, and we want the preview to show a fixed
    -- mid-bar regardless of that.
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0.5)
    frame:Show()
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
    self:EnsureFrame()
    self:ApplyConfig()
    self:ApplyLock()

    self:RegisterEvent("PLAYER_TARGET_CHANGED",         "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START",          "OnCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP",           "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED",         "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",    "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_DELAYED",        "OnCastDelayed")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START",  "OnChannelStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnCastDelayed")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")

    self:RegisterMessage("KickCD_CONFIG_CHANGED",  "OnConfigChanged")
    self:RegisterMessage("KickCD_PROFILE_CHANGED", "OnProfileChanged")

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

function Castbar:OnCastDelayed(_evt, unit)
    if unit ~= "target" then return end
    if not current then return end
    -- Re-query so the timeline reflects the pushback / haste change. The
    -- shim re-checks issecretvalue() so we may transition between the
    -- plain and fallback paths between calls — both are safe.
    local rec = KickCD.Compat.GetCastingInfo("target")
    if rec then current = rec end
end

-- ---------------------------------------------------------------------------
-- Message handlers
-- ---------------------------------------------------------------------------

function Castbar:OnConfigChanged(_evt, payload)
    local section = payload and payload.section
    if section == "castbar" then
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
    if frame then
        local anchor = KickCD.db and KickCD.db.profile
            and KickCD.db.profile.anchors and KickCD.db.profile.anchors.castbar
        KickCD.Util.ApplyAnchor(frame, anchor or
            { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 })
    end
    self:ApplyConfig()
    self:ApplyLock()
    if isVisible() then self:Reevaluate() else self:Stop() end
end

-- Expose for /kcd debug + future tooling.
KickCD.Castbar = Castbar
