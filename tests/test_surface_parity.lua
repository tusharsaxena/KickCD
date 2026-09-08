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
-- produced the stub. Kit.assertSurfaceParity reads the LIVE surface and reports every divergence
-- in one message, so the question becomes "what does the library actually export today?" rather
-- than "what did somebody remember to list?".
--
-- BOTH ARMS COME FROM A REAL LOAD. The degraded arm is produced by feeding the loader an empty
-- library file list — `T.load(true, false, nil, { libFiles = {} })` — never by hand-stubbing the
-- member under test, which would only assert the test's own typing.
--
-- THE THREE LIBRARY-BACKED SEAMS CALL THE KIT'S BY-NAME FORM — assertSurfaceParity(stub, major,
-- ignore) — which arrived with kit 15 and was vendored by M4-01. Two things change.
--
--   * WHICH KEYS ARE WALKED. The by-name form compares Kit.publicMembers rather than every key of
--     the live table: LibStub's own MAJOR / MINOR / MODULES go, and so does every `__`-prefixed
--     key. Those are the library talking to itself across its own file boundary — __bannerBand,
--     __tabPlacement, __print — and the rule that a stub does not mirror them is the kit's now
--     instead of this file's typing. libs/LibKa0s/Options.lua's own comment at O.__print states
--     it and cites this filter by name. The exemptions that used to say so here are gone, and the
--     next internal a re-vendor publishes needs no edit in this file or in the stub.
--   * WHERE THE LIVE HALF COMES FROM. tests/run.lua registers it with Kit.setSurfaceSource, and it
--     has to: all three of these stubs mirror an INSTANCE — what `lib:New(descriptor)` returned —
--     not the library table LibStub answers for the same major. Left to Kit.expose's auto-wiring,
--     which reaches for the mock's LibStub, "LibKa0s-Options-1.0" would resolve a table of four
--     members and this case would go red for reasons that have nothing to do with the stub.
--
-- THE COST OF THE SECOND, STATED PLAINLY: the live half is now the runner's SHARED instance, which
-- earlier suites have already driven, rather than this file's pristine `live`. Two DebugLog test
-- seams are exempted below for exactly that reason. It is the same construction either way
-- (`loadInstance(true)`), and a divergence a preceding suite introduces is a real one.
--
-- CORE STAYS ON THE FOUR-ARGUMENT FORM, and the reason is worth having written down: it is not a
-- major's surface at all. `NS` and `NS.Util` are this addon's own namespace, half-published by
-- core/CoreSetup.lua's live arm and half by its stub. There is no name to look up, and comparing
-- two namespaces the host built itself is precisely what the four-argument form is for.
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
-- The live half is the LibKa0s-DebugLog-1.0 instance core/DebugLogSetup.lua:129 builds, which
-- tests/run.lua registers under that name. Read off the built instance rather than the file, which
-- is the same list as
--   grep -nE "^\s+function D[:.]|^\s+D\.[A-Za-z_]+\s*=" libs/LibKa0s/DebugLog.lua
-- without a parser.

test("the DebugLog stub carries the whole live surface", function()
    -- red under: deleting `ConsoleCheckbox` from core/DebugLogSetup.lua's stub table
    assertSurfaceParity(degraded.NS.DebugLog, "LibKa0s-DebugLog-1.0", {
        -- The library's own string resolver and the copy-window's text builder. Neither is
        -- reachable on the degraded path: `ShowCopy` is stubbed to the say-once notice, so nothing
        -- asks for the buffer as text, and every string the stub emits is either the host's own or
        -- NS.LIBKA0S_MISSING. Stubbing `Text` would mean shipping a second answer for the
        -- library's strings, which debug-logging-§7 is specifically about not doing.
        "Text", "CopyText",
        -- Test seams the library stamps ON THE INSTANCE when it BUILDS the console window
        -- (libs/LibKa0s/DebugLog.lua:477, :482). They are on the live half by the time this case
        -- runs only because tests/test_debuglogsetup.lua:70 showed the window on the shared
        -- instance; a library-less build has no window to build, so their absence from the stub is
        -- the condition under test rather than a gap in it. SINGLE underscore, so Kit.publicMembers
        -- does not filter them for us — its exclusion is the `__` prefix.
        "_frameForTest", "_toggleClickForTest",
    })
end)

-- ── Slash ───────────────────────────────────────────────────────────────────
--
-- Members from: grep -n "^  function Sl[:.]" libs/LibKa0s/Slash.lua
--
-- NS.Slash is the host's own table and is identical on both paths, so it keeps the four-argument
-- form for the reason Core does. The SEAM is NS.Slash.cli, which is `SlashLib:New(...)` live and
-- settings/Slash.lua:223's local stub degraded; tests/run.lua registers the live one under the
-- major's name.

test("the Slash stub carries the whole live surface", function()
    -- red under: deleting `CliList` from settings/Slash.lua's stub `New`
    assertSurfaceParity(live.NS.Slash, degraded.NS.Slash, "NS.Slash")
    assertSurfaceParity(degraded.NS.Slash.cli, "LibKa0s-Slash-1.0", {
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
-- The live half is the LibKa0s-Options-1.0 instance the live arm of settings/OptionsSetup.lua
-- assigns to NS.Settings.Helpers, decorated in place by settings/Panel.lua, Panel_Widgets.lua and
-- Panel_Render.lua, and registered under that name by tests/run.lua. Read off the built instance
-- rather than the file, which is the same list as
--   grep -n "^  function O\." libs/LibKa0s/Options.lua
-- plus the host's own decorations, without a parser.
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
    --
    -- ONE `__` MEMBER IS PINNED BY HAND, below the parity call, and it is the one thing the kit's
    -- filter cannot decide for this repo: settings/Panel_Widgets.lua:138 CALLS Helpers.__panelFor.
    -- The kit drops the prefix because a `__` member is normally the library talking to itself and
    -- no host reaches it; here one does, and this file's own rule is that a member the host calls
    -- is a member the stub owes. Without the pin the stub could lose it in silence.
    assertSurfaceParity(degraded.NS.Settings.Helpers, "LibKa0s-Options-1.0", {
        -- The registry and the panel lifecycle. The host does not call these on Helpers at all —
        -- it calls NS.RegisterOptionsPage / NS.CreateOptionsPanel / NS.OpenOptionsPanel, which the
        -- stub DOES define (settings/OptionsSetup.lua), so the degraded path is covered on the
        -- surface the host actually uses.
        "RegisterOptionsPage", "CreateOptionsPanel", "OpenOptionsPanel",
        -- The widget makers, the flow engine and the landing-page renderer. options-ui-§1 forbids
        -- a host copy outright; a page that cannot be built has nothing to render into.
        --
        -- SetRenderer LEFT this list (CX03). It sat here under that same sentence, but it is not a
        -- widget maker or a layout constant -- it is the lifecycle registrar every page hands its
        -- renderer to, and it is where the Blizzard-sidebar combat refusal lives. The exemption is
        -- how AbsorbTracker's stub could omit the member entirely with its own parity case green,
        -- so the collection stopped granting it. It is stubbed in settings/OptionsSetup.lua now,
        -- like CreatePanel, which is exempt from nothing and is unreachable on the degraded path
        -- for exactly the same reason.
        "RenderGrid", "TextRow", "BuildLandingPage",
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
        -- WHAT IS NO LONGER ON THIS LIST, and why it got shorter rather than laxer. `__pages` and
        -- `__print` were exempted here one at a time, the second added three days ago by
        -- v1.27.0's Options minor 8 with the library's own comment at O.__print saying a stub does
        -- not mirror it and citing Kit.publicMembers by name. That filter is what this case runs
        -- through now, so the whole prefix is the kit's business and the next internal a re-vendor
        -- publishes needs no entry here. The ten no-op `__` mirrors the STUB carried for the same
        -- vanished reason went with them, in this commit — settings/OptionsSetup.lua says which
        -- one stayed and why.
    })
    -- The exception the filter cannot make for us. settings/Panel_Widgets.lua:138's OpenPageTab
    -- reads `Helpers.__panelFor and Helpers.__panelFor(pageKey)` to pre-select the destination
    -- page's tab, so the degraded path reaches this member — guarded, so losing it costs a tab
    -- selection rather than a raise, which is exactly the kind of quiet degradation nothing else
    -- would report. Kit.publicMembers dropped it with the rest of the prefix; this line puts it
    -- back for this repo alone.
    -- red under: deleting `Helpers.__panelFor` from settings/OptionsSetup.lua's stub
    assertTrue(type(degraded.NS.Settings.Helpers.__panelFor) == "function",
        "the stub owes __panelFor: settings/Panel_Widgets.lua:138 calls it")
end)
