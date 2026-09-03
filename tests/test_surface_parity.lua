-- tests/test_surface_parity.lua — one stub-surface parity case per adopted LibKa0s seam
-- (testing-§8, anti-pattern #56).
--
-- KickCD adopts eight LibKa0s majors; these five have a degradation stub in their setup file:
--
--   Core      core/CoreSetup.lua        NS.IsConcatSafe / NS.SafeToString / NS.Util.print
--   DebugLog  core/DebugLogSetup.lua    NS.DebugLog
--   Slash     settings/Slash.lua        NS.Slash.cli
--   Options   settings/OptionsSetup.lua NS.Settings.Helpers
--   Perf      core/PerfSetup.lua        NS.Perf
--
-- WHY THIS FILE EXISTS. Three of the collection's surviving High findings are one omitted stub
-- member: a stub returns without assigning a function the addon calls, and the command raises on
-- exactly the degraded path the stub exists to survive. A member-by-member checklist does not
-- catch it, because the checklist is written from the same stale reading of the surface that
-- produced the stub. Kit.assertSurfaceParity walks the LIVE table and reports every divergence in
-- one message, so the question becomes "what does the library actually export today?" rather than
-- "what did somebody remember to list?".
--
-- BOTH ARMS COME FROM A REAL LOAD. The degraded arm is produced by feeding the loader an empty
-- library file list — `T.load(true, false, nil, { libFiles = {} })` — never by hand-stubbing the
-- member under test, which would only assert the test's own typing.
--
-- WHAT THIS CANNOT CATCH, stated so nobody over-claims: a stub with the right member set and a
-- WRONG IMPLEMENTATION. `KCD-A-14` — the DebugLog stub hand-copying the library's line format and
-- state hexes — is a debug-logging-§7 violation and stays addon-side, in
-- tests/test_debuglogsetup.lua's source-scan cases.

local T = _G.KICKCD_TEST
local test, assertSurfaceParity, assertTrue = T.test, T.assertSurfaceParity, T.assertTrue

--- The two arms, built once. Loading eight library files plus the whole TOC twice per case is
--- several seconds across five cases, and nothing here mutates either instance.
local live     = T.load(true)
local degraded = T.load(true, false, nil, { libFiles = {} })

test("sanity: the degraded arm really has no LibKa0s", function()
    -- Without this, every case below could be comparing two live loads and passing for the most
    -- boring possible reason.
    for _, major in ipairs({ "LibKa0s-Core-1.0", "LibKa0s-DebugLog-1.0", "LibKa0s-Slash-1.0",
                             "LibKa0s-Options-1.0", "LibKa0s-Perf-1.0" }) do
        assertTrue(live.mocks.LibStub(major, true) ~= nil, major .. " must be live in the live arm")
        assertTrue(degraded.mocks.LibStub(major, true) == nil,
            major .. " is registered in the DEGRADED arm — the partial file list did not take")
    end
end)

-- ── Core ────────────────────────────────────────────────────────────────────
--
-- Core publishes onto the namespace itself (NS.IsConcatSafe, NS.SafeToString) and onto NS.Util
-- (the prefixed printer). Members from:
--   grep -n "^function lib\." libs/LibKa0s/Core.lua
--   grep -n "^NS\.\|^Util\.\|function Util\." core/CoreSetup.lua
--
-- The whole namespace is compared rather than a hand-picked three, because the hand-picked list is
-- the thing that goes stale. It is also the strongest statement available about a degraded load:
-- every symbol the addon publishes with the library present, it publishes without it.

test("the whole namespace survives a LibKa0s-less load", function()
    -- red under: deleting `function NS.SafeToString` from core/CoreSetup.lua's stub branch
    assertSurfaceParity(live.NS, degraded.NS, "NS")
end)

test("the Core printer seam degrades with its whole surface intact", function()
    -- red under: deleting `Util.print` from core/CoreSetup.lua's stub branch
    assertSurfaceParity(live.NS.Util, degraded.NS.Util, "NS.Util (Core printer seam)")
end)

-- ── DebugLog ────────────────────────────────────────────────────────────────
--
-- Members from: grep -nE "^\s+function D[:.]|^\s+D\.[A-Za-z_]+\s*=" libs/LibKa0s/DebugLog.lua

test("the DebugLog stub carries the whole live surface", function()
    -- red under: deleting `ConsoleCheckbox` from core/DebugLogSetup.lua's stub table
    assertSurfaceParity(live.NS.DebugLog, degraded.NS.DebugLog, "NS.DebugLog", {
        -- The library's own string resolver and the copy-window's text builder. Neither is
        -- reachable on the degraded path: `ShowCopy` is stubbed to the say-once notice, so nothing
        -- asks for the buffer as text, and every string the stub emits is either the host's own or
        -- NS.LIBKA0S_MISSING. Stubbing `Text` would mean shipping a second answer for the
        -- library's strings, which debug-logging-§7 is specifically about not doing.
        "Text", "CopyText",
    })
end)

-- ── Slash ───────────────────────────────────────────────────────────────────
--
-- Members from: grep -n "^  function Sl[:.]" libs/LibKa0s/Slash.lua
--
-- NS.Slash is the host's own table and is identical on both paths; the seam is NS.Slash.cli, which
-- is `SlashLib:New(...)` live and settings/Slash.lua:206's local stub degraded.

test("the Slash stub carries the whole live surface", function()
    -- red under: deleting `CliList` from settings/Slash.lua's stub `New`
    assertSurfaceParity(live.NS.Slash, degraded.NS.Slash, "NS.Slash")
    assertSurfaceParity(live.NS.Slash.cli, degraded.NS.Slash.cli, "NS.Slash.cli", {
        -- `Text` is the library's string resolver (see the DebugLog note — same reason).
        "Text",
        -- `HelpHeader` and `BuildListLines` are renderers the library calls from inside PrintHelp
        -- and CliList. The stub answers those two verbs itself with the "unavailable" line, so
        -- nothing on the degraded path reaches either. LootHistory's HelpHeader finding is the
        -- opposite case — there the HOST calls it — which is why this is data and not a comment.
        "HelpHeader", "BuildListLines",
    })
end)

-- ── Options ─────────────────────────────────────────────────────────────────
--
-- Members from: grep -n "^  function O\." libs/LibKa0s/Options.lua
--
-- This stub is LOAD-COMPLETING rather than member-answering, and that is a different contract from
-- the other three (settings/OptionsSetup.lua says so and says why). options-ui-§1 is explicit that
-- it MUST NOT carry a widget maker, the flow engine, the header, or any of the library's layout
-- constants — a host copy of a library constant is the copy that goes stale, and hand-copying the
-- code whose drift the extraction exists to end is the duplicate testing-§8 most specifically
-- forbids. So the parity statement here is "every member the HOST calls", and the exclusions are
-- carried AS DATA below, each with the reason it is not a gap.
--
-- What this still buys: a re-vendor that adds a member to the library forces a decision — stub it,
-- or record it here as deliberately live-only. Today it silently appears on one path only.

test("the Options stub carries every member the host calls", function()
    -- red under: deleting `RenderRows` from settings/OptionsSetup.lua's stub no-op list
    assertSurfaceParity(live.NS.Settings.Helpers, degraded.NS.Settings.Helpers,
        "NS.Settings.Helpers", {
        -- The registry and the panel lifecycle. The host does not call these on Helpers at all —
        -- it calls NS.RegisterOptionsPage / NS.CreateOptionsPanel / NS.OpenOptionsPanel, which the
        -- stub DOES define (settings/OptionsSetup.lua), so the degraded path is covered on the
        -- surface the host actually uses.
        "RegisterOptionsPage", "CreateOptionsPanel", "OpenOptionsPanel", "__pages",
        -- The widget makers, the flow engine and the landing-page renderer. options-ui-§1 forbids
        -- a host copy outright; a page that cannot be built has nothing to render into.
        "SetRenderer", "RenderGrid", "TextRow", "BuildLandingPage",
        -- The library's layout constants. Same rule, stated as constants:
        -- tests/test_options_panel.lua's source scan already fails if a copy of any of these
        -- appears in the host or in the stub.
        --
        -- ROW_VSPACER joined this list when the host stopped restating it. settings/Panel.lua used
        -- to declare `local ROW_VSPACER = 8` and assign it over the library's published value, so
        -- the member existed on BOTH paths and parity held for the wrong reason — the host copy was
        -- filling the degraded hole. With the copy deleted (options-ui-§8) it is live-only like its
        -- three siblings, and the stub MUST NOT grow it back: settings/Panel_Render.lua binds it at
        -- load and settings/Panel_Widgets.lua forwards it to AddSpacer, both of which are no-ops on
        -- the degraded path, so nil is inert there.
        --
        -- RefreshScalars LEFT this list when settings/Panel_Render.lua's SetAndRefresh started
        -- calling it (the write seam is a SCALAR refresh now, never a structural one -- a
        -- structural sweep rebuilds the page under the slider being dragged). A member the host
        -- calls is a member the stub owes, so it is stubbed rather than exempted.
        "PADDING_X", "ROW_VSPACER", "SECTION_HEADING_H", "BUTTON_PAIR_REL",
        -- The three that arrived with the tabbed page and the banner (options-ui-§13 / §14) are
        -- the same class and exempt for the same reason: BANNER_H is the banner's height floor,
        -- TAB_H one row of the strip, CHROME_GAP the gap under the whole band. The host reads them
        -- off the instance or not at all, and tests/test_options_panel.lua fails if a copy of any
        -- of them appears in settings/OptionsSetup.lua.
        "BANNER_H", "CHROME_GAP", "TAB_H",
        -- The composers' PUBLISHED CONSTANTS (OptionsCompose 1) are the same
        -- class of thing one layer up: FONT_FLAGS / FONT_FLAGS_SORT are the
        -- canonical font-flag value list, VISIBILITY_VALUES / VISIBILITY_SORT
        -- the canonical visibility list, MASTER_GROUP the literal that is both
        -- the tab name and the afterGroup key, CLASS_COLOR_NOTE the sentence
        -- every color swatch's tooltip ends with. Copying any of them here is
        -- the copy that goes stale, and the whole point of the composers is that
        -- nine addons cannot drift apart on exactly these values
        -- (options-ui-§15/§16/§17). The host reads them off the instance inside
        -- a renderer or not at all, and no renderer runs on the degraded path.
        "FONT_FLAGS", "FONT_FLAGS_SORT", "VISIBILITY_VALUES", "VISIBILITY_SORT",
        "MASTER_GROUP", "CLASS_COLOR_NOTE",
        -- The AceGUI handle the library resolves at CreateOptionsPanel time. With no library there
        -- is no CreateOptionsPanel, so there is nothing to resolve; the host reads NS.AceGUI.
        "AceGUI",
    })
end)
