-- modules/DebugLog.lua — on-screen debug console (§12)
--
-- Debug output routes to THIS window, styled like the addon's own frames,
-- NOT the default chat frame. A DIALOG-strata BackdropTemplate window with a
-- ScrollingMessageFrame log, a title-bar state-toggle, and Copy/Clear buttons.
-- The look & feel is the Ka0s house style shared with the sibling addons: a
-- flat dark panel with a thin tooltip border, a dedicated title bar as the
-- sole drag handle, and flat text buttons.
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

-- ACCEPTED DEVIATION (standard "Blizzard-default media" SHOULD rule): the
-- console body/copy boxes use a bundled non-Blizzard monospace font
-- (JetBrainsMono-Regular.ttf) rather than a Blizzard-shipped face. This is an
-- intentional design choice — the debug console is a session-only developer
-- tool (never in SavedVariables, not a user-facing styled surface), and a
-- fixed-width font is required so the aligned log/copy columns don't drift.
-- It is deliberately NOT wired to a user LSM setting. Every user-facing font/
-- texture/border in the addon does default to Blizzard media and is LSM-backed.
--
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
-- Flat dark panel with a thin tooltip border (the Ka0s house style, shared
-- with the sibling addons) so the console reads like the addon's own frames.
-- ---------------------------------------------------------------------------
local SKIN = {
    backdrop = {
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    divider   = { 0, 0, 0, 1 },
    title     = { 0.9, 0.9, 0.9 },
    onColor   = { 0.30, 0.85, 0.30 },
    offColor  = { 0.90, 0.30, 0.30 },
}

local function ApplySkin(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(SKIN.backdrop)
        frame:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end
end
DebugLog.SKIN = SKIN
DebugLog.ApplySkin = ApplySkin

-- ---------------------------------------------------------------------------
-- State + buffers
-- ---------------------------------------------------------------------------
local window            -- lazily-built console frame (nil until EnsureWindow)
local copyWindow        -- lazily-built Copy window (nil until ShowCopy)
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
-- Small styled controls — no shipped art.
-- ---------------------------------------------------------------------------

-- Flat text button for the title bar (Copy / Clear): steel resting, gold hover.
local function makeTextButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 60, 18)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    fs:SetTextColor(0.7, 0.7, 0.72)
    b.text = fs
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(0.7, 0.7, 0.72) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Thin close glyph (× ) for the title bar: steel resting, red hover.
local function makeCloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER")
    fs:SetText("\195\151")  -- multiplication sign ×
    fs:SetTextColor(0.7, 0.7, 0.72)
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.3, 0.3) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(0.7, 0.7, 0.72) end)
    b:SetScript("OnClick", onClick)
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
-- Console window (lazy)
-- ---------------------------------------------------------------------------
local function buildWindow()
    local f = CreateFrame("Frame", "KickCDDebugWindow", UIParent, "BackdropTemplate")
    f:SetSize(700, 344)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    ApplySkin(f)

    -- Title bar = the sole drag handle.
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER")
    title:SetText("Ka0s KickCD \226\128\148 Debug")
    title:SetTextColor(SKIN.title[1], SKIN.title[2], SKIN.title[3])

    -- 1px divider under the title bar.
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(SKIN.divider[1], SKIN.divider[2], SKIN.divider[3], SKIN.divider[4])

    -- Close glyph (right), Clear + Copy text buttons (left of it).
    local close = makeCloseButton(titleBar, function() DebugLog:Hide() end)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    local clear = makeTextButton(titleBar, "Clear", 42, function() DebugLog:Clear() end)
    clear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    local copy = makeTextButton(titleBar, "Copy", 40, function() DebugLog:ShowCopy() end)
    copy:SetPoint("RIGHT", clear, "LEFT", -6, 0)

    -- Left-aligned state toggle: resting colour reflects state (green ON / red
    -- OFF), gold on hover; clicking flips the flag through the shared seam.
    local toggle = CreateFrame("Button", nil, titleBar)
    toggle:SetSize(80, 18)
    toggle:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    local toggleFS = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggleFS:SetPoint("LEFT")
    toggle.text = toggleFS
    toggle:SetScript("OnEnter", function() toggleFS:SetTextColor(1, 0.82, 0) end)
    toggle:SetScript("OnLeave", function() refreshHeader() end)
    toggle:SetScript("OnClick", function() DebugLog:SetEnabled(not isEnabled()) end)
    f.toggle = toggle

    -- Log surface.
    local log = CreateFrame("ScrollingMessageFrame", nil, f)
    log:SetPoint("TOPLEFT", 8, -(26 + 6))
    log:SetPoint("BOTTOMRIGHT", -8, 14)
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

    f:HookScript("OnShow", function() refreshHeader() end)
    f:Hide()
    tinsert(UISpecialFrames, "KickCDDebugWindow")
    return f
end

-- ---------------------------------------------------------------------------
-- Copy window (lazy, separate) — a read-through multiline EditBox pre-filled
-- with the plain buffer and auto-highlighted for Ctrl+C (WoW exposes no
-- clipboard API — the user's Ctrl+C inside an EditBox is the only copy path —
-- §12.6). A standalone window on FULLSCREEN strata so it floats above the
-- console it was launched from.
-- ---------------------------------------------------------------------------
local function buildCopyWindow()
    local f = CreateFrame("Frame", "KickCDDebugCopyWindow", UIParent, "BackdropTemplate")
    f:SetSize(560, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    ApplySkin(f)

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER")
    title:SetText("Copy log \226\128\148 Ctrl+C, then Esc")
    title:SetTextColor(SKIN.title[1], SKIN.title[2], SKIN.title[3])

    local close = makeCloseButton(titleBar, function() f:Hide() end)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)

    local scroll = CreateFrame("ScrollFrame", "KickCDDebugCopyScroll", f,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -30)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    if FONT then edit:SetFont(FONT, FONT_SIZE, "") end
    edit:SetAutoFocus(false)
    edit:SetWidth(510)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    scroll:SetScrollChild(edit)
    f.scroll = scroll
    f.edit = edit

    f:Hide()
    tinsert(UISpecialFrames, "KickCDDebugCopyWindow")
    return f
end

local function ensureCopyWindow()
    if not copyWindow then copyWindow = buildCopyWindow() end
    return copyWindow
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
    refreshHeader()
end

function DebugLog:Hide()
    if window then window:Hide() end
end

function DebugLog:Toggle()
    if window and window:IsShown() then self:Hide() else self:Show() end
end

--- Is the console WINDOW currently on screen? Distinct from IsEnabled (the
--- capture flag): the window can be shown while capture is off, and vice
--- versa. Backs the General panel's "Debug console" checkbox.
function DebugLog:IsShown()
    return window ~= nil and window:IsShown() and true or false
end

--- Append a line. The RAW append seam — NOT gated on the debug flag, so
--- SetEnabled can bracket a disabled session (the gate lives in NS.Debug, the
--- sink, which is the only other caller and is already flag-checked).
function DebugLog:Add(tag, msg)
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
    if copyWindow and copyWindow.edit then copyWindow.edit:SetText("") end
end

function DebugLog:ShowCopy()
    local f = ensureCopyWindow()
    f.edit:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 510)
    f.edit:SetText(table.concat(plainLines, "\n"))
    f.edit:SetCursorPosition(0)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

function DebugLog:HideCopy()
    if copyWindow then copyWindow:Hide() end
end

--- The single write seam for the session-only debug flag (§12.5): set flag →
--- refresh header → print a NS.PREFIX-tagged chat ack → bracket the session
--- with a console line at both transitions. Never persisted.
function DebugLog:SetEnabled(on)
    on = on and true or false
    if NS.State then NS.State.debug = on end
    refreshHeader()
    if NS.Util and NS.Util.print then
        NS.Util.print("debug logging " .. (on and "|cff40ff40ON|r" or "|cffff4040OFF|r"))
    end
    -- Bracket every session at both ends. Written through the raw Add (not the
    -- flag-gated NS.Debug sink) so the "logging disabled" line still lands after
    -- NS.State.debug has flipped off (§12.5).
    DebugLog:Add("Debug", on and "logging enabled" or "logging disabled")
    -- On enable, snapshot the session's load-time facts (standard §8 boot
    -- summary) so a log captured mid-session still records what it's running
    -- against. Emitted through the raw Add (state just flipped on; NS.Debug
    -- would also work, but Add keeps this ordered right after the bracket).
    if on and NS.db then
        local ver     = NS.VERSION or "?"
        local schema  = NS.db.global and NS.db.global.schemaVersion or "?"
        local profile = NS.db.GetCurrentProfile and NS.db:GetCurrentProfile() or "?"
        DebugLog:Add("Init", ("KickCD v%s, schema v%s, profile '%s'")
            :format(tostring(ver), tostring(schema), tostring(profile)))
    end
end

function DebugLog:IsEnabled()
    return isEnabled()
end

-- Buffer introspection (headless-testable; also handy for a future dump verb).
function DebugLog:BufferSize() return #plainLines end
function DebugLog:LastLine() return plainLines[#plainLines] end

--- True if any buffered line contains `substr` (plain find, no patterns).
--- Buffer introspection for tests (and a future dump verb) — needed because a
--- session-start line is no longer guaranteed to be LastLine now that enable
--- appends both the bracket and the [Init] snapshot.
function DebugLog:FindLine(substr)
    for i = 1, #plainLines do
        if plainLines[i]:find(substr, 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The sink (§12.4) — the addon-wide debug entry point.
-- ---------------------------------------------------------------------------

--- Substitute a placeholder for a combat-protected "secret" value so the sink
--- (§4) can never raise inside string.format when a call site passes one (e.g.
--- charges in combat). Identity pass-through when issecretvalue is unavailable
--- (headless harness) or the value is plain.
local function secretSafe(v)
    if _G.issecretvalue and _G.issecretvalue(v) then return "secret" end
    return v
end
DebugLog.secretSafe = secretSafe

--- NS.Debug(tag, fmt, ...) — zero-allocation when off (the gate is the first
--- line; no format/concat/table build before it). Each ... arg is routed
--- through secretSafe so a secret value renders as "secret" rather than
--- erroring the console. Routes to the console, not chat.
function NS.Debug(tag, fmt, ...)
    if not (NS.State and NS.State.debug) then return end
    local n = select("#", ...)
    local msg
    if n > 0 then
        local args = { ... }
        for i = 1, n do args[i] = secretSafe(args[i]) end
        msg = string.format(fmt, unpack(args, 1, n))
    else
        msg = fmt
    end
    if NS.DebugLog and NS.DebugLog.Add then
        NS.DebugLog:Add(tag, msg)
    end
end
