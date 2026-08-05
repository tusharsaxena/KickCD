local addonName, NS = ...

-- core/DebugLogSetup.lua — wires the addon into LibKa0s-DebugLog-1.0.
--
-- The console window, the copy window, the two formatters, the 500-line buffer,
-- the scrollbar sync, the line counter and the enable seam live in
-- libs/LibKa0s/DebugLog.lua and are shared across every Ka0s addon. This file
-- supplies only the part that is ours: the frame-name prefix, the title, the
-- monospace font, where the debug flag actually lives, and what the [Init]
-- session summary says.
--
-- It replaces modules/DebugLog.lua (518 lines), which is deleted. That file was
-- the cleanest win in the repo: BOTH its formatters were already byte-identical
-- to the library's, down to the muted timestamp color, the tan tag and the
-- escaped `||` separator, and its window was the same 700x344 DIALOG-strata
-- frame. Seven such consoles existed across the collection; the color codes
-- agreed and the scrollbar behavior did not.
--
-- (The hex codes themselves are deliberately not quoted anywhere in this file —
-- tests/test_debuglogsetup.lua greps for them to prove the degradation stub
-- carries no copy of the format, and a comment would satisfy that grep.)
--
-- TOC POSITION. It sits in core/ rather than modules/ and after
-- core/CoreSetup.lua, which pins three things:
--   * core/Constants.lua has run, so NS.Const.FONT_MONO resolves;
--   * core/State.lua has run, so NS.State.debug — the flag — exists;
--   * core/CoreSetup.lua has run, so NS.Util.print and NS.SafeToString exist.
-- Everything that calls NS.Debug loads after it. Moving the console out of
-- modules/ costs nothing here because nothing in modules/ was borrowing its
-- skin or its close button — the sibling addons where that inversion bites do
-- not apply.

-- The monospace font ships to LibSharedMedia at load (debug-logging-§2), and it
-- does so ABOVE the library guard: the registration exposes the face to other
-- addons and is not the console's to skip just because the console is missing.
-- A no-op when LSM is absent; the console takes the path directly either way.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local FONT = NS.Const and NS.Const.FONT_MONO
    if LSM and LSM.Register and FONT then
        LSM:Register("font", "JetBrains Mono", FONT)
    end
end

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)

if not lib then
    -- A missing vendored lib must degrade, not error at load. The stub covers
    -- EVERY member the addon calls — core/KickCD.lua's `/kcd debug` verbs,
    -- settings/General.lua's console checkbox, and the buffer introspection the
    -- suites drive — because a stub that omits one is not a fallback, it is a
    -- crash moved to a rarer code path.
    --
    -- The flag itself still works: NS.State.debug is ours, and a user who types
    -- `/kcd debug on` must not be told nothing happened. What is lost is the
    -- WINDOW, and the stub says so once, honestly.
    --
    -- WHAT IS NOT HERE, AND WHY. debug-logging-§3 forbids reproducing the line
    -- format OR its color codes in a fallback, and the format is the half that
    -- matters: a log pasted from any Ka0s addon parses the same way by eye
    -- BECAUSE one library renders it. A stub that re-spells the library's
    -- timestamp / separator / bracketed-tag line has forked that guarantee
    -- whether or not it also copied the hexes — and this file used to do
    -- exactly that while its own comment claimed the opposite, arguing only
    -- about color. The shape is deliberately not quoted here either: a grep for
    -- a hand-copied format must not find one in the very file that swore off it.
    --
    -- So the stub renders NO line. It has no console to render one into, and
    -- inventing a shape here would be a second format to keep in step with the
    -- library's. FormatPlain / FormatColored answer the member (surface parity
    -- is what debug-logging-§7 asks for) and hand back the message unchanged.
    -- The state words in the ack below are likewise uncolored: the ON/OFF hexes
    -- are the library's string, not this file's to copy.
    -- The cause half is core/CoreSetup.lua's shared clause (NS.LIBKA0S_MISSING);
    -- only the consequence is this seam's. Do not re-spell the cause here.
    local missing = NS.LIBKA0S_MISSING .. ", so the debug console window is unavailable."
    local announced = false
    local function sayOnce()
        if announced then return end
        announced = true
        if NS.Util and NS.Util.print then NS.Util.print(missing) end
    end

    local D
    D = {
        buffer = {},
        Add             = function() end,
        Debug           = function() end,
        Clear           = function() end,
        Show            = function() sayOnce() end,
        Hide            = function() end,
        Toggle          = function() sayOnce() end,
        IsShown         = function() return false end,
        IsEnabled       = function() return NS.State and NS.State.debug or false end,
        RefreshHeader   = function() end,
        ShowCopy        = function() sayOnce() end,
        UpdateScrollBar = function() end,
        UpdateStatus    = function() end,
        BufferSize      = function() return 0 end,
        LastLine        = function() return nil end,
        FindLine        = function() return nil end,
        MakeCloseButton = function() return nil end,
        -- The message, verbatim. NOT the library's line — see the note above.
        -- Nothing in this addon calls these; they exist so the stub's surface
        -- matches the live instance's, which is what the parity case asserts.
        FormatPlain     = function(_ts, _tag, msg) return tostring(msg) end,
        SetEnabled      = function(_, on)
            on = not not on
            if NS.State then NS.State.debug = on end
            if NS.Util and NS.Util.print then
                -- Uncolored on purpose: the green/red state hexes are the
                -- library's, and copying them is the same defect as copying
                -- the line format. The ACK itself is required (debug-logging-§7).
                NS.Util.print("debug logging " .. (on and "ON" or "OFF"))
            end
            if on then sayOnce() end
        end,
        ConsoleCheckbox = function()
            return {
                label   = "Debug console",
                tooltip = missing,
                get     = function() return false end,
                set     = function() sayOnce() end,
            }
        end,
    }
    D.FormatColored = D.FormatPlain
    NS.DebugLog = D
    NS.Debug = D.Debug
    return
end

NS.DebugLog = lib:New({
    -- Seeds KickCDDebugWindow / KickCDDebugCopyWindow / KickCDDebugCopyScroll —
    -- the three globals modules/DebugLog.lua spelled out by hand, reproduced
    -- exactly, so a saved frame position and ESC-to-close behave as before.
    name  = addonName,
    -- The library appends its own " — Debug", giving "Ka0s KickCD — Debug",
    -- which is byte for byte what the old title bar read.
    title = "Ka0s KickCD",
    font  = NS.Const and NS.Const.FONT_MONO,
    slash = "/kcd",
    -- fontSize omitted: 10 is the library's default and was this addon's value.

    -- The flag stays ours. NS.State.debug is session-only (never in
    -- SavedVariables) and is read by the settings panel and by `/kcd debug`, so
    -- a second copy inside the library would be a second truth.
    isEnabled  = function() return NS.State and NS.State.debug or false end,
    setEnabled = function(on) if NS.State then NS.State.debug = on end end,

    -- Both resolved at CALL time rather than captured. core/CoreSetup.lua has
    -- already run, so a captured reference would in fact be correct here — but
    -- the forwarder costs nothing and is what keeps this file's correctness from
    -- depending on a TOC line staying where it is (anti-patterns #36).
    print        = function(line) NS.Util.print(line) end,
    safeToString = function(v) return NS.SafeToString(v) end,

    -- The [Init] line the console brackets a session with. The library owns WHEN
    -- it is emitted — on enable, because the flag is off at login and a
    -- load-time summary would always be gated off — and only we can know what it
    -- says. Byte-identical to what modules/DebugLog.lua composed.
    initSummary = function()
        local ver     = NS.VERSION or "?"
        local schema  = NS.db and NS.db.global and NS.db.global.schemaVersion or "?"
        local profile = NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile() or "?"
        return ("KickCD v%s, schema v%s, profile '%s'"):format(
            NS.SafeToString(ver), NS.SafeToString(schema), NS.SafeToString(profile))
    end,

    -- The General page's "Debug console" checkbox mirrors the window's
    -- visibility, so a console closed with ESC or opened from `/kcd debug` has
    -- to move the checkbox on a settings panel that is already open.
    onVisibilityChanged = function()
        local H = NS.Settings and NS.Settings.Helpers
        if H and H.RefreshAllPanels then H.RefreshAllPanels() end
    end,
})

-- The addon-wide gated sink (debug-logging-§4), published under the name every
-- existing call site already uses. Bound BARE rather than wrapped: it is a plain
-- function precisely so `NS.Debug("Cast", "unit=%s", unit)` keeps working with
-- no self and no allocation when the flag is off.
NS.Debug = NS.DebugLog.Debug
