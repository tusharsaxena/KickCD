-- modules/Castbar.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.7, REQUIREMENTS.md FR-3, FR-8
--
-- Single StatusBar showing the target's current cast: spell icon + name +
-- time-remaining + spark + optional border. The frame is built once on
-- enable and styled live from db.profile.castbar via Restyle(). Visibility
-- and progress are driven entirely by the three TARGET_CAST_* messages from
-- Tracker; this module never reads UnitCastingInfo directly.
--
-- Channels render right-to-left per FR-3.4, so we invert the fraction we
-- write into the StatusBar (SetMinMaxValues is fixed to 0..1 once at
-- construction so OnUpdate just writes a fraction).
--
-- The OnUpdate script is set on cast start and cleared on cast end so we
-- never burn cycles while the bar is hidden (NFR-1, §7.2).

local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Castbar = KickCD:NewModule("Castbar", "AceEvent-3.0")

local LSM_DEFAULT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local LSM_DEFAULT_FONT    = "Fonts\\FRIZQT__.TTF"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function GetLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

local function FetchTexture(key)
    local lsm = GetLSM()
    if lsm and key then
        local t = lsm:Fetch("statusbar", key, true)
        if t then return t end
    end
    return LSM_DEFAULT_TEXTURE
end

local function FetchFont(key)
    local lsm = GetLSM()
    if lsm and key then
        local f = lsm:Fetch("font", key, true)
        if f then return f end
    end
    return LSM_DEFAULT_FONT
end

local function FetchBorder(key)
    if not key or key == "None" or key == "" then return nil end
    local lsm = GetLSM()
    if lsm then
        return lsm:Fetch("border", key, true)
    end
    return nil
end

local function GetProfile()
    return KickCD.db and KickCD.db.profile or nil
end

-- ---------------------------------------------------------------------------
-- OnUpdate
-- ---------------------------------------------------------------------------
--
-- Bound up-front (no anonymous closure inside the hot path per §7.5).
-- Frame fields the script reads: _startSec, _endSec, _isChannel, bar, spark,
-- timeText. Spark x is recomputed every tick so it tracks fractional fill
-- precisely; we floor+0.5 to snap to a pixel.

local function OnUpdate(self)
    local startSec = self._startSec
    local endSec   = self._endSec
    if not (startSec and endSec) then return end

    local now    = GetTime()
    local total  = endSec - startSec
    local elapsed = now - startSec
    if elapsed < 0 then elapsed = 0 end
    if total > 0 and elapsed > total then elapsed = total end

    local frac = (total > 0) and (elapsed / total) or 0
    if self._isChannel then frac = 1 - frac end

    self.bar:SetValue(frac)

    if self.spark and self.spark:IsShown() then
        local w = self.bar:GetWidth() or 0
        local x = math.floor(frac * w + 0.5)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", x, 0)
    end

    local left = endSec - now
    if left < 0 then left = 0 end
    if self.timeText then
        self.timeText:SetText(string.format("%.1f", left))
    end
end

-- ---------------------------------------------------------------------------
-- Drag handlers
-- ---------------------------------------------------------------------------

local function OnDragStart(frame)
    local profile = GetProfile()
    if not profile or profile.locked then return end
    frame:StartMoving()
end

local function OnDragStop(frame)
    frame:StopMovingOrSizing()
    local profile = GetProfile()
    if not profile then return end
    profile.anchors = profile.anchors or {}
    profile.anchors.castbar = KickCD.Util.SaveAnchor(frame)
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

function Castbar:BuildFrame()
    if self.frame then return self.frame end

    -- Outer frame: holds the StatusBar plus overlays + border. We anchor
    -- the outer frame to UIParent and size it to match the bar so dragging
    -- moves a single object (the user grabs anywhere on the bar).
    local frame = CreateFrame("Frame", "KickCDCastbar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(240, 22)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop",  OnDragStop)
    frame:Hide()

    -- StatusBar — fills the parent. Min/Max set once so OnUpdate writes
    -- raw fractions in [0,1].
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetAllPoints(frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(LSM_DEFAULT_TEXTURE)
    frame.bar = bar

    -- Background behind the fill so an empty bar shows a frame, not a void.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.5)
    frame.bg = bg

    -- Spark — narrow vertical line riding the right edge of the fill.
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(16, 32)
    spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
    frame.spark = spark

    -- Icon — left edge inside bar, square sized to the bar's height.
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop default border
    frame.icon = icon

    -- Name — centered. timeText — right edge. Both inset slightly.
    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(LSM_DEFAULT_FONT, 12, "OUTLINE")
    name:SetPoint("LEFT", bar, "LEFT", 28, 0)
    name:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    name:SetJustifyH("CENTER")
    name:SetWordWrap(false)
    frame.name = name

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(LSM_DEFAULT_FONT, 12, "OUTLINE")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    frame.timeText = timeText

    self.frame = frame
    return frame
end

-- ---------------------------------------------------------------------------
-- Restyle
-- ---------------------------------------------------------------------------
--
-- Pull every visual property from db.profile.castbar (and anchor from
-- db.profile.anchors.castbar). Safe to call repeatedly — never recreates
-- widgets, only re-applies state.

function Castbar:Restyle()
    local frame = self.frame
    if not frame then return end

    local profile = GetProfile()
    if not profile then return end

    local cb = profile.castbar or {}
    local anchors = profile.anchors or {}

    -- Anchor
    if anchors.castbar then
        KickCD.Util.ApplyAnchor(frame, anchors.castbar)
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end

    -- Size
    local w = cb.width  or 240
    local h = cb.height or 22
    frame:SetSize(w, h)

    -- Scale + alpha (global, from §4)
    frame:SetScale(profile.scale or 1.0)
    frame:SetAlpha(profile.alpha or 1.0)

    -- Texture
    frame.bar:SetStatusBarTexture(FetchTexture(cb.texture))

    -- Color — v0.1 only shows interruptible casts (Tracker filters out shielded
    -- casts per FR-3.2/FR-1.5), so interruptibleColor is the only state we
    -- ever paint. notInterruptibleColor is read on-demand by OnStart if the
    -- payload ever surfaces a non-interruptible cast.
    frame.bar:SetStatusBarColor(KickCD.Util.Unpack(cb.interruptibleColor or { 1.0, 0.82, 0, 1 }))

    -- Font
    local fontFile = FetchFont(cb.font)
    local fontSize = cb.fontSize or 12
    if frame.name then
        frame.name:SetFont(fontFile, fontSize, "OUTLINE")
    end
    if frame.timeText then
        frame.timeText:SetFont(fontFile, fontSize, "OUTLINE")
    end

    -- Spark visibility
    if frame.spark then
        frame.spark:SetShown(cb.showSpark ~= false)
    end

    -- Icon visibility + sizing — square, height of the bar, anchored inside
    -- the left edge. Adjust the name's left inset so it doesn't overlap.
    if frame.icon then
        if cb.showIcon ~= false then
            local iconSize = h
            frame.icon:SetSize(iconSize, iconSize)
            frame.icon:ClearAllPoints()
            frame.icon:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
            frame.icon:Show()
            if frame.name then
                frame.name:ClearAllPoints()
                frame.name:SetPoint("LEFT",  frame.bar, "LEFT",  iconSize + 4, 0)
                frame.name:SetPoint("RIGHT", frame.bar, "RIGHT", -40, 0)
            end
        else
            frame.icon:Hide()
            if frame.name then
                frame.name:ClearAllPoints()
                frame.name:SetPoint("LEFT",  frame.bar, "LEFT",  4, 0)
                frame.name:SetPoint("RIGHT", frame.bar, "RIGHT", -40, 0)
            end
        end
    end

    -- Border via BackdropTemplate
    if frame.SetBackdrop then
        local borderFile = FetchBorder(cb.border)
        if borderFile then
            frame:SetBackdrop({
                edgeFile = borderFile,
                edgeSize = 12,
                insets   = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            frame:SetBackdropBorderColor(1, 1, 1, 1)
        else
            frame:SetBackdrop(nil)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Cast lifecycle
-- ---------------------------------------------------------------------------
--
-- All three handlers receive the message name as the first arg (Ace3
-- AceEvent-3.0 convention) and the payload table as the second. Tracker
-- emits MS-since-boot timestamps (RESEARCH §2.1) — we divide by 1000 to
-- get GetTime()-style seconds.

function Castbar:OnCastStart(_, payload)
    local frame = self.frame
    if not frame or type(payload) ~= "table" then return end

    frame._startSec   = (payload.startMS or 0) / 1000
    frame._endSec     = (payload.endMS   or 0) / 1000
    frame._isChannel  = payload.isChannel and true or false

    if frame.name then
        frame.name:SetText(payload.name or "")
    end
    if frame.icon then
        if payload.texture then
            frame.icon:SetTexture(payload.texture)
        else
            frame.icon:SetTexture(nil)
        end
    end

    -- Repaint color in case interruptibility flipped between OnEnable and now.
    local profile = GetProfile()
    local cb = profile and profile.castbar or {}
    if payload.notInterruptible then
        frame.bar:SetStatusBarColor(KickCD.Util.Unpack(cb.notInterruptibleColor or { 0.5, 0.5, 0.5, 1 }))
    else
        frame.bar:SetStatusBarColor(KickCD.Util.Unpack(cb.interruptibleColor or { 1.0, 0.82, 0, 1 }))
    end

    -- Prime the bar so the first frame after Show() isn't a flash of empty.
    OnUpdate(frame)

    frame:Show()
    frame:SetScript("OnUpdate", OnUpdate)
end

function Castbar:OnCastUpdate(_, payload)
    local frame = self.frame
    if not (frame and frame:IsShown()) or type(payload) ~= "table" then return end

    -- Tracker re-pulls UnitCastingInfo on _DELAYED / _CHANNEL_UPDATE and
    -- forwards the new times. Channel ticks may shift _startSec earlier OR
    -- later depending on haste changes, so accept whatever payload provides.
    if payload.startMS then frame._startSec = payload.startMS / 1000 end
    if payload.endMS   then frame._endSec   = payload.endMS   / 1000 end

    -- Per FR-3.2, v0.1 should not be displaying a non-interruptible cast at
    -- all (Tracker filters those out and would have fired _END), but if we
    -- ever do receive a flip mid-cast, recolor accordingly.
    if payload.notInterruptible ~= nil then
        local profile = GetProfile()
        local cb = profile and profile.castbar or {}
        if payload.notInterruptible then
            frame.bar:SetStatusBarColor(KickCD.Util.Unpack(cb.notInterruptibleColor or { 0.5, 0.5, 0.5, 1 }))
        else
            frame.bar:SetStatusBarColor(KickCD.Util.Unpack(cb.interruptibleColor or { 1.0, 0.82, 0, 1 }))
        end
    end
end

function Castbar:OnCastEnd(_, _payload)
    local frame = self.frame
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame._startSec  = nil
    frame._endSec    = nil
    frame._isChannel = nil
    frame:Hide()
end

-- ---------------------------------------------------------------------------
-- Config / profile change
-- ---------------------------------------------------------------------------

function Castbar:OnConfigChanged(_, payload)
    -- Restyle on "castbar", "general" (scale/alpha/locked), or whole-profile
    -- updates. "icons" / "spells" are no-ops for us.
    if type(payload) == "table" and payload.section then
        local s = payload.section
        if s ~= "castbar" and s ~= "general" then return end
    end
    self:Restyle()
end

function Castbar:OnProfileChanged()
    -- A profile swap can change every visual property and the anchor.
    -- Restyle handles everything; if a cast was in flight on the old profile
    -- we leave it visible — Tracker re-evaluates against the new state and
    -- will fire _END if the new profile disables tracking.
    self:Restyle()
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

function Castbar:OnEnable()
    self:BuildFrame()
    self:Restyle()

    self:RegisterMessage("KickCD_TARGET_CAST_START",  "OnCastStart")
    self:RegisterMessage("KickCD_TARGET_CAST_UPDATE", "OnCastUpdate")
    self:RegisterMessage("KickCD_TARGET_CAST_END",    "OnCastEnd")
    self:RegisterMessage("KickCD_CONFIG_CHANGED",     "OnConfigChanged")
    self:RegisterMessage("KickCD_PROFILE_CHANGED",    "OnProfileChanged")
end

function Castbar:OnDisable()
    self:UnregisterAllMessages()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
end
