-- modules/DebugLog.lua — on-screen debug console (§12)
--
-- Debug output routes to THIS window, styled like the addon's own frames,
-- NOT the default chat frame. A DIALOG-strata BackdropTemplate window with a
-- ScrollingMessageFrame log, a header state-toggle, and Copy/Clear buttons.
--
-- The enabled-state is session-only (KickCD.State.debug, never in SV — §12.5);
-- DebugLog:SetEnabled is the single write seam. Capture is independent of the
-- window's visibility: logging runs even when the console is closed, so a bug
-- can be reproduced first and the log opened after.
--
-- Everything that touches a frame is built lazily in EnsureWindow(), so this
-- file is inert at load (safe under the headless test harness) — only the pure
-- formatters and the LSM font registration run at file scope.

local addonName, NS = ...
NS.DebugLog = NS.DebugLog or {}
local DebugLog = NS.DebugLog

local FONT      = NS.Const and NS.Const.FONT_MONO
local FONT_SIZE = 10
local MAX_LINES = 500

-- Ship the monospace font to LibSharedMedia at load (§12.2). Registration is a
-- no-op if LSM is missing; the console falls back to FONT directly either way.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.Register and FONT then
        LSM:Register("font", "JetBrains Mono", FONT)
    end
end

-- ---------------------------------------------------------------------------
-- Pure formatters (§12.3) — frame-free and unit-tested so the coloured
-- console string can never drift from the plain Copy-buffer string.
-- ---------------------------------------------------------------------------

--- Clean text for the Copy buffer: `<ts> | [<tag>] <msg>`.
function DebugLog.FormatPlain(ts, tag, msg)
    return ("%s | [%s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
end

--- Coloured console line: muted steel-blue timestamp, muted tan [tag], white
--- separator + content. `||` renders one literal pipe inside a colour string.
function DebugLog.FormatColored(ts, tag, msg)
    return ("|cff6f8faf%s|r || |cffc9a66b[%s]|r %s"):format(
        tostring(ts), tostring(tag or ""), tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Skin seam (§6A) — stock Blizzard textures only, one re-skin touch point.
-- ---------------------------------------------------------------------------
local SKIN = {
    backdrop = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    divider   = { 0.4, 0.4, 0.4, 0.8 },
    title     = { 0.9, 0.9, 0.9 },
    onColor   = { 0.25, 1.0, 0.25 },
    offColor  = { 1.0, 0.3, 0.3 },
}

local function ApplySkin(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(SKIN.backdrop)
        frame:SetBackdropColor(0, 0, 0, 0.9)
    end
end
DebugLog.SKIN = SKIN
DebugLog.ApplySkin = ApplySkin

-- ---------------------------------------------------------------------------
-- State + buffers
-- ---------------------------------------------------------------------------
local window            -- lazily-built frame (nil until EnsureWindow)
local plainLines = {}   -- plain-text ring buffer for the Copy view (≤ MAX_LINES)

local function nowStamp()
    -- WoW exposes a global `date`; fall back to os.date under the harness.
    local d = _G.date or (os and os.date)
    return d and d("%H:%M:%S") or "--:--:--"
end

local function isEnabled()
    return NS.State and NS.State.debug and true or false
end

-- ---------------------------------------------------------------------------
-- Small styled text button (Copy / Clear / state toggle) — no shipped art.
-- ---------------------------------------------------------------------------
local function makeTextButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(60, 18)
    local fs = b:CreateFontString(nil, "OVERLAY")
    if FONT then fs:SetFont(FONT, FONT_SIZE, "") end
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b.text = fs
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function() fs:SetAlpha(0.7) end)
    b:SetScript("OnLeave", function() fs:SetAlpha(1.0) end)
    return b
end

local function refreshHeader()
    if not (window and window.toggle) then return end
    local on = isEnabled()
    local c = on and SKIN.onColor or SKIN.offColor
    window.toggle.text:SetText(on and "Debug: ON" or "Debug: OFF")
    window.toggle.text:SetTextColor(c[1], c[2], c[3])
end
DebugLog.refreshHeader = refreshHeader

-- ---------------------------------------------------------------------------
-- Window construction (lazy)
-- ---------------------------------------------------------------------------
local function buildWindow()
    local f = CreateFrame("Frame", "KickCDDebugWindow", UIParent, "BackdropTemplate")
    f:SetSize(700, 344)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ApplySkin(f)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("KickCD — Debug")
    title:SetTextColor(SKIN.title[1], SKIN.title[2], SKIN.title[3])

    -- Header state-toggle (left)
    local toggle = makeTextButton(f, "Debug: OFF", function()
        DebugLog:SetEnabled(not isEnabled())
    end)
    toggle:SetSize(80, 18)
    toggle:SetPoint("TOPLEFT", 12, -9)
    f.toggle = toggle

    -- Close glyph (thin, top-right)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Copy / Clear text buttons (top-right, left of the close glyph)
    local clear = makeTextButton(f, "Clear", function() DebugLog:Clear() end)
    clear:SetPoint("TOPRIGHT", -30, -9)
    local copy = makeTextButton(f, "Copy", function() DebugLog:ShowCopy() end)
    copy:SetPoint("TOPRIGHT", -92, -9)

    -- 1px divider under the header
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(SKIN.divider[1], SKIN.divider[2], SKIN.divider[3], SKIN.divider[4])
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 10, -30)
    divider:SetPoint("TOPRIGHT", -10, -30)

    -- Log surface
    local log = CreateFrame("ScrollingMessageFrame", nil, f)
    log:SetPoint("TOPLEFT", 12, -38)
    log:SetPoint("BOTTOMRIGHT", -12, 12)
    if FONT then log:SetFont(FONT, FONT_SIZE, "") end
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(MAX_LINES)
    log:SetHyperlinksEnabled(false)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    f.log = log

    -- Copy overlay: a read-through multiline EditBox pre-filled with the plain
    -- buffer, auto-highlighted for Ctrl+C (WoW exposes no clipboard API — the
    -- user's Ctrl+C inside an EditBox is the only copy path — §12.6).
    local copyScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", 12, -38)
    copyScroll:SetPoint("BOTTOMRIGHT", -30, 12)
    copyScroll:Hide()
    local edit = CreateFrame("EditBox", nil, copyScroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    if FONT then edit:SetFont(FONT, FONT_SIZE, "") end
    edit:SetWidth(640)
    edit:SetScript("OnEscapePressed", function() DebugLog:HideCopy() end)
    copyScroll:SetScrollChild(edit)
    f.copyScroll = copyScroll
    f.copyBox = edit

    tinsert(UISpecialFrames, "KickCDDebugWindow")
    return f
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function DebugLog:EnsureWindow()
    if not window then
        window = buildWindow()
        refreshHeader()
    end
    return window
end

function DebugLog:Show()
    self:EnsureWindow():Show()
    self:HideCopy()
    refreshHeader()
end

function DebugLog:Hide()
    if window then window:Hide() end
end

function DebugLog:Toggle()
    if window and window:IsShown() then self:Hide() else self:Show() end
end

--- Append a line. Called only through the KickCD.Debug sink (already gated),
--- but re-checks so a direct call can't leak when disabled.
function DebugLog:Add(tag, msg)
    if not isEnabled() then return end
    local ts = nowStamp()
    plainLines[#plainLines + 1] = DebugLog.FormatPlain(ts, tag, msg)
    if #plainLines > MAX_LINES then table.remove(plainLines, 1) end
    if window and window.log then
        window.log:AddMessage(DebugLog.FormatColored(ts, tag, msg))
    end
end

--- Clear wipes both the visible log AND the Copy buffer (§12.6).
function DebugLog:Clear()
    for i = #plainLines, 1, -1 do plainLines[i] = nil end
    if window and window.log then window.log:Clear() end
    if window and window.copyBox then window.copyBox:SetText("") end
end

function DebugLog:ShowCopy()
    self:EnsureWindow()
    if not (window and window.copyBox) then return end
    window.log:Hide()
    window.copyScroll:Show()
    window.copyBox:SetText(table.concat(plainLines, "\n"))
    window.copyBox:HighlightText()
    window.copyBox:SetFocus()
end

function DebugLog:HideCopy()
    if window and window.copyScroll then
        window.copyScroll:Hide()
        window.copyBox:ClearFocus()
        window.log:Show()
    end
end

--- The single write seam for the session-only debug flag (§12.5): set flag →
--- refresh header → print a NS.PREFIX-tagged chat ack. Never persisted.
function DebugLog:SetEnabled(on)
    on = on and true or false
    if NS.State then NS.State.debug = on end
    refreshHeader()
    if NS.Util and NS.Util.print then
        NS.Util.print("debug logging " .. (on and "|cff40ff40ON|r" or "|cffff4040OFF|r"))
    end
end

function DebugLog:IsEnabled()
    return isEnabled()
end

-- Buffer introspection (headless-testable; also handy for a future dump verb).
function DebugLog:BufferSize() return #plainLines end
function DebugLog:LastLine() return plainLines[#plainLines] end

-- ---------------------------------------------------------------------------
-- The sink (§12.4) — the addon-wide debug entry point.
-- ---------------------------------------------------------------------------

--- NS.Debug(tag, fmt, ...) — zero-allocation when off (the gate is the first
--- line; no string.format or concat runs before it). The tag is the first arg
--- so every call site self-documents its category. Routes to the console, not
--- chat.
function NS.Debug(tag, fmt, ...)
    if not (NS.State and NS.State.debug) then return end
    local msg = (select("#", ...) > 0) and string.format(fmt, ...) or fmt
    if NS.DebugLog and NS.DebugLog.Add then
        NS.DebugLog:Add(tag, msg)
    end
end
