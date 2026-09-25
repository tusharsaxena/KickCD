local _, NS = ...

-- settings/OptionsSetup.lua — wires the addon into LibKa0s-Options-1.0.
--
-- The settings-canvas shell, the header and breadcrumb, the lazy Defaults
-- button, the five widget makers, the two-column flow engine and the
-- always-shown scrollbar patch live in
-- libs/LibKa0s/{Options,OptionsWidgets,OptionsScroll}.lua. This file is only the
-- part that is ours: where a value lives, which rows belong to which page, and
-- what "reset everything" has to clear that no schema row owns.
--
-- NS.Settings.Helpers IS the library instance, decorated in place by
-- settings/Panel.lua, Panel_Widgets.lua and Panel_Render.lua with the pieces
-- that did not generalize (options-ui-§1). Never a fresh table that copies
-- members across: a host page helper added later has to be able to call
-- Helpers.RenderRows like any other page does, and a suite that swaps a member
-- out to spy on it must be swapping the one the library's own callers see.
--
-- TOC POSITION: BEFORE settings/Panel.lua (which decorates this instance) and
-- therefore before every settings/<page>.lua, because those page files call
-- Helpers.AnchorValues and Helpers.AnchorOrder AT FILE LOAD, into the locals
-- their schema-row literals read. See the stub below for what that costs.

-- ---------------------------------------------------------------------
-- The one rule about what a global reset must not touch
-- ---------------------------------------------------------------------
--
-- Profiles rows are AceDBOptions-supplied and resetting them deletes user data,
-- which is not what "restore defaults" means to anyone (options-ui-§3). Named
-- once because it is enforced twice — by the library through
-- descriptor.skipRestoreAll, and by the degradation stub's own reset loop, which
-- has to keep working with no library at all.
--
-- EVERY PROFILE-BACKED ROW IS VETOED TOO (options-ui-§12). The global reset IS a
-- profile reset now — see resetProfile — so writing each row's default into
-- the profile first would refresh the panel once per row for values about to be
-- discarded whole. What the walk keeps is what a profile reset cannot reach: the
-- sessionOnly rows, whose storage is their own `set()` rather than the db.
local function vetoedFromResetAll(row)
    if row.panel == "profiles" then return true end
    return not row.sessionOnly
end

-- ---------------------------------------------------------------------
-- The one row NO reset may touch
-- ---------------------------------------------------------------------
--
-- launcher-§3 (standard v2.54.0) states this as a PROPERTY of the setting rather
-- than deriving it from where the setting is stored: whether the minimap button
-- is shown is a PER-INSTALLATION DISPLAY PREFERENCE, in the same class as the
-- POSITION the player dragged it to, which LibDBIcon keeps in the very same
-- table and which no reset in this collection touches. So it survives BOTH
-- options-ui-§12's `Reset all settings` AND a page-scoped `Defaults` button,
-- and neither may un-hide a hidden button or re-hide a shown one.
--
-- `Reset all settings` never reaches it: O.RestoreAllDefaults narrows its walk
-- to the `sessionOnly` rows when `resetProfile` is supplied, `vetoedFromResetAll`
-- above answers true for it anyway, and the reset itself empties db.PROFILE while
-- this row's table is `db.global.minimap`. The General page's `Defaults` DID
-- reach it once -- O.RestoreDefaults walks `rowsForPage("general")`, where the
-- composed Minimap button row lives, and consults no veto.
--
-- THE VETO IS THE SCHEMA SEAM'S `resetExempt` NOW (settings/SchemaSetup.lua).
-- Both of the library's resets write through `applyDefault` INSIDE the bulk
-- bracket this descriptor hands them, and Store.ApplyDefault refuses an exempt
-- row only while a bracket is open. So the row is exempt from both sweeps from
-- one place, while `/kcd reset global.minimap.shown` -- a single row the player
-- named out loud, outside any bracket -- still resets it, which is the CLI route
-- to a setting the schema CLI is supposed to reach.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)

local function helpers() return NS.Settings and NS.Settings.Helpers end

-- ---------------------------------------------------------------------
-- The panel's schema reader, PUBLISHED because nothing else can see it
-- ---------------------------------------------------------------------
--
-- This is the descriptor's `get`, lifted out of the table and given a name so a
-- test can call it. That is unusual here and the reason is specific: the ONE
-- defect this reader has ever had is invisible to every caller the library has.
--
-- Both host descriptors used to read a value as `H and H.Get and H.Get (path) or
-- nil`, which folds a stored FALSE to nil. In settings/Slash.lua that was loud --
-- the library prints nil as the literal "nil", so `/kcd get locked` reported a
-- value the addon does not hold. Here it was SILENT, and still would be: every
-- consumer of `d.get` in libs/LibKa0s/OptionsWidgets.lua folds the answer to a
-- boolean before anything can see it (`read(row) and true or false` for a
-- checkbox, a truthiness test for `disabledIf`), so false and nil draw the same
-- tick. No input a case can pass through the panel distinguishes them.
--
-- So the fix in this file had nothing pinning it while the one in settings/Slash.lua
-- did, which is the asymmetry that let one spelling of the reader live in two
-- files in the first place. Naming it makes the behavior reachable, and
-- tests/test_options_panel.lua calls it with a stored false. The descriptor below
-- takes this FUNCTION VALUE rather than wrapping it, so there is one reader and
-- the case cannot be pinning a parallel copy.
--
-- It IS the schema seam's reader now (settings/SchemaSetup.lua), bound by value:
-- Store.Get answers a stored false as false, and a row with its own storage (the
-- Debug console, the minimap button) through that row's own `get`.
NS.Settings = NS.Settings or {}
local Store = NS.Settings.Store

--- Read a schema path for the options surface: LibKa0s-Schema-1.0's Get.
NS.Settings.ReadForPanel = Store.Get

--- Backs the color picker's and the slider's 50 ms drag throttle: the
--- descriptor's `scheduleTimer`. A descriptor field rather than an AceTimer
--- embed, because embedding would be the library's second dependency-budget
--- breach.
---
--- Since LibKa0s v1.56.0 (OptionsWidgets minor 31) the library keeps its own
--- armed flag and ignores the return value. The handle is returned anyway, so a
--- payload older than that still throttles: C_Timer.After would hand back nil,
--- which such a payload read as "not armed" on every drag tick (KICKCD-R-04).
--- Named, like ReadForPanel above, so tests/test_options_panel.lua can call the
--- one function the descriptor passes by reference.
function NS.Settings.ScheduleTimer(fn, delay)
    return _G.C_Timer.NewTimer(delay, fn)
end

-- Both Reset all paths reset the profile through here. Store.ResetCounted
-- counts the rows the reset changes before it runs -- the profile rows, never the
-- AceDBOptions page's -- for the one line Database:OnProfileChanged logs
-- (debug-logging-§10), and clears the count on both exits.
local function notProfilesPage(row) return row.panel ~= "profiles" end

local function resetProfileCounted(db)
    Store.ResetCounted(function() db:ResetProfile() end, notProfilesPage)
end

--- Write a row's default through the seam, then repaint any open panel. The
--- library's own funnel for both resets: Store.ApplyDefault copies a table
--- default in, refuses the launcher-§3 row inside a sweep, and answers false
--- for a row with no default. Its answers pass through.
local function applyDefault(row)
    local ok, err, why = Store.ApplyDefault(row)
    local H = helpers()
    if ok and H and H.RefreshScalars then H.RefreshScalars() end
    return ok, err, why
end

-- ---------------------------------------------------------------------
-- The descriptor
-- ---------------------------------------------------------------------
--
-- Every callback reaches through `helpers()` at CALL time rather than capturing
-- a member: settings/Panel.lua decorates this instance AFTER this file has run,
-- so a captured reference would be nil forever.

local descriptor = {
    parentTitle   = "Ka0s KickCD",
    mainPanelName = "KickCDMainPanel",

    print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
    debug = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,

    -- The schema seams. Store.Set through SetAndRefresh, because it is the
    -- addon's SINGLE write seam: it refuses an unknown path, runs the row's
    -- onChange, fires CONFIG_CHANGED with the row's section and repaints any
    -- open panel. A panel checkbox then takes exactly the path `/kcd set` takes,
    -- which is the whole point of the rule (options-ui-§1).
    -- The reader above, BY REFERENCE. Not a wrapper: a wrapper would be a second
    -- place the `or nil` fold could come back, and the case that pins the named
    -- one would go on passing. See its header for why it is named at all.
    get = NS.Settings.ReadForPanel,
    set = function(path, value)
        local H = helpers()
        if H and H.SetAndRefresh then return H.SetAndRefresh(path, value) end
        return Store.Set(path, value)
    end,
    -- The launcher-§3 carve-out is the seam's `resetExempt`, honored because
    -- both resets run inside the bracket below (see the block above).
    applyDefault = applyDefault,

    -- `filter` is ctx.unit, passed through by the library without interpreting
    -- it. That is what makes a per-unit page render only the selected unit's
    -- rows while a page with ctx.unit nil gets every unit's.
    rowsForPage = function(pageKey, filter)
        local H = helpers()
        return H and H.SchemaForPanel and H.SchemaForPanel(pageKey, filter) or {}
    end,
    allRows = function() return NS.Settings and NS.Settings.Schema or {} end,

    skipRestoreAll = vetoedFromResetAll,

    -- Anchors and the spell lists are NOT schema rows, so applyDefault never
    -- reaches them — and neither needs a hook of its own any more, because RESET
    -- ALL IS A PROFILE RESET (options-ui-§12) and both live IN the profile. (The
    -- Focus `link` flag is a row now, and lives in the profile too.) The library
    -- calls `resetProfile` below.
    --
    -- One call, and the same act as the Profiles page's Reset Profile. AceDB
    -- empties the ACTIVE profile — only that one; the profile LIST is untouched,
    -- which is the line the veto above exists for — `aceDBDefaults()` merges
    -- NS.DEFAULT_PROFILE back over it (anchors and every unit's `link` flag with
    -- it), and OnProfileReset reaches Database:OnProfileChanged, which already
    -- folds legacy units, migrates spec keys, RE-SEEDS THE SPELL LISTS and
    -- refreshes — exactly what it does for a profile switch.
    --
    -- ResetAllPositions and RestoreUnitLinks, which used to sit beside this
    -- call, are both gone; the spell wipe left Helpers.ResetAll for the same
    -- reason.
    -- It runs BEFORE the refresh, which is load-bearing: a refresh first would
    -- paint the pre-hook values.
    -- `resetProfile` rather than a hand-written afterRestoreAll: LibKa0s-Options-1.0
    -- minor 9 made this a descriptor field precisely so eight sibling addons stop
    -- writing the same two lines. With it supplied the library narrows its own row
    -- walk to the sessionOnly rows before calling this, so the veto above is belt to
    -- that braces on the live path and the whole policy on the degraded one.
    resetProfile = function()
        local db = NS.db
        if db and db.ResetProfile then resetProfileCounted(db) end
    end,

    -- This addon ships the AceDBOptions Profiles page (settings/Profiles.lua),
    -- so the General page's Reset all settings tooltip names the equivalence
    -- options-ui-§12 asks for: "the same thing Profiles → Reset Profile does".
    -- The library cannot see which pages a host registers, so the host says so
    -- (LibKa0s-Options-1.0 minor 18). It changes that tooltip and nothing else.
    profilesPage = true,

    -- The bulk bracket (LibKa0s-Options-1.0 minor 16) around RestoreDefaults and
    -- RestoreAllDefaults: the schema seam's own pair. A page's Defaults logs ONE
    -- `[Set] reset <page>: N rows` line rather than one per row, and Reset all
    -- logs only the profile handler's line, because the library reports that the
    -- act reset the profile (debug-logging-§10). A debounced `[Set]` line still
    -- pending from a write just before the act is logged first, with its own
    -- value, so the log never reads the act and then a value it replaced.
    bulkBegin = function(act, scope)
        NS.Settings.FlushPendingSets()
        Store.BulkBegin(act, scope)
    end,
    bulkEnd = Store.BulkEnd,

    -- The drag throttle's timer, BY REFERENCE (see NS.Settings.ScheduleTimer).
    scheduleTimer = NS.Settings.ScheduleTimer,

    getLSM   = function() return LibStub and LibStub("LibSharedMedia-3.0", true) end,
    -- The schema's shape check: path, type, group and duplicates on every row,
    -- and every stored path resolving against NS.DEFAULT_PROFILE. A row with its
    -- own `get` stores somewhere else (session state, db.global) and is in no
    -- defaults tree, so it is answered nil and skipped rather than reported.
    -- The panel and section enums are tests/test_schema.lua's.
    validate = function()
        Store.Validate({
            defaultsRoot = function(_, row)
                if type(row.get) == "function" then return nil end
                return NS.DEFAULT_PROFILE, 1
            end,
        })
    end,

    -- Ka0s standard, library-stack-§4: resolve AceGUI once and read the upvalue. The page
    -- builders read NS.AceGUI, so the library hands it over rather than keeping
    -- it private.
    onAceGUI = function(AceGUI) NS.AceGUI = AceGUI end,

    -- The landing page's body — the logo, the tagline and the slash-command
    -- rows — is genuinely per-addon, so it stays ours and fires on the main
    -- panel's first OnShow.
    buildMain = function(ctx)
        local H = helpers()
        if H and H.BuildMainContent then H.BuildMainContent(ctx) end
    end,

    -- Colors are stored as the keyed { r =, g =, b =, a = } table, which IS the
    -- library's default shape — core/Database.lua's v3 -> v4 migration moved
    -- them there rather than translating at every seam. Written out anyway
    -- rather than omitted, because the stored shape is a real contract with the
    -- rest of the addon (NS.Util.Unpack, every module's color read) and a
    -- silent default is a poor place for it to live.
    colorDecode = function(c)
        if type(c) ~= "table" then c = {} end
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end,
    colorEncode = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end,
}

-- ---------------------------------------------------------------------
-- The degradation stub — LOAD-COMPLETING, not member-answering
-- ---------------------------------------------------------------------
--
-- Every other setup file in this addon degrades to a table whose members each
-- print an honest "not installed" line. This one MUST NOT, and the reason is not
-- importance but WHEN the missing code is reached (options-ui-§1).
--
-- settings/Icons.lua and settings/Castbar.lua evaluate `H.AnchorValues()` and
-- `H.AnchorOrder()` at FILE LOAD, into the file-scope locals their schema-row
-- literals read. With those members nil the page file raises, so its rows never
-- register, so a large part of NS.Settings.Schema is missing — and `/kcd list`,
-- `/kcd get`, `/kcd set`, `/kcd reset` and the profile defaults all break with
-- it, silently. The addon would not degrade; it would half-load and say nothing.
--
-- MEASURED, not assumed (options-ui-§1 requires exactly that): this stub needs
-- ZERO load-time members, and that is a real difference from the reference
-- consumer. AbsorbTracker takes LSMValues from the LIBRARY, so its stub must
-- publish one or its page files raise. KickCD's load-time callers are
-- AnchorValues and AnchorOrder, both of them its OWN code in settings/Panel.lua
-- (host code that is present whether or not LibKa0s is), and Panel.lua loads
-- before every page file. So the load-time hole AbsorbTracker's stub exists to
-- plug does not exist here. LSMValues is host code here too, but nothing
-- evaluates it at load any more.
--
-- The measurement is the gate, not this comment:
-- tests/test_options_panel.lua loads the addon with the library ABSENT and pins
-- #NS.Settings.Schema against the fully-loaded environment. If a future change
-- moves either generator onto the library instance, that case goes red and this
-- stub grows the member back.
--
-- Note what is NOT here: no widget maker, no flow engine, no header, and none of
-- the library's layout constants. A host copy of a library constant is the copy
-- that goes stale, and hand-copying the code whose drift the extraction exists
-- to end is the one duplicate testing-§8 most specifically forbids.
if not lib then
    -- The cause half is core/CoreSetup.lua's shared clause (NS.LIBKA0S_MISSING);
    -- only the consequence is this seam's. Nothing about the STUB converges — it
    -- stays load-completing for the reasons measured above — just the sentence.
    local MISSING = NS.LIBKA0S_MISSING .. ", so the settings panel is unavailable."

    local Helpers = {}
    NS.Settings = NS.Settings or {}
    NS.Settings.Helpers = Helpers

    -- Reached at load, so it has to be real enough for the page files to finish.
    -- AnchorValues/AnchorOrder are the host's own and are republished by
    -- settings/Panel.lua, which loads after this — but a page file evaluates
    -- them at load, so the stub answers until then.

    -- Kept real even though it is call-time: the user whose panel will not open
    -- is exactly the user who needs "reset everything", and the schema loaded
    -- fine, so the reset still works with no panel at all.
    -- The sessionOnly rows -- they are the ONLY ones the veto lets through, and
    -- the only ones a profile reset cannot reach, because their storage is their
    -- own set() rather than the db (options-ui-§12).
    local function restoreSessionRows()
        for _, row in ipairs(Store.AllRows()) do
            if not vetoedFromResetAll(row) then applyDefault(row) end
        end
    end

    Helpers.RestoreAllDefaults = function()
        -- The library's bracket, driven by hand, as the live path runs under it:
        -- the sessionOnly rows written first add no [Set] line of their own, and a
        -- profile reset is logged ONCE, by Database:OnProfileChanged
        -- (debug-logging-§10). The pair is the schema seam's, whichever it is:
        -- a library-less load has the log-silent stub, whose bracket is a depth.
        --
        -- `reset` is set only once the reset RETURNS, as the library does: with no
        -- db, or a reset that raised, the handler may never have run, and then the
        -- bracket's own `[Set] reset all: N rows` line is the only record.
        Store.BulkBegin("reset", "all")
        local reset = false
        local ok, err = pcall(function()
            restoreSessionRows()
            -- Then the profile itself, which is the reset. The same one call the
            -- live descriptor's resetProfile makes -- this stub exists because the
            -- LIBRARY is missing, not the db, and the user whose panel will not
            -- open is exactly the user who needs "reset everything".
            local db = NS.db
            if db and db.ResetProfile then
                resetProfileCounted(db)
                reset = true
            end
        end)
        Store.BulkEnd("reset", "all", nil, err, { profileReset = reset })
        if not ok then error(err, 0) end
    end

    -- Reached only from a builder or a user action, so a no-op is honest.
    --
    -- The tabbed-page members (options-ui-§13) and the page banner (options-ui-§14) joined the list when
    -- the pages adopted them: TabStrip and PageBanner draw the chrome band, SetChromeHeight moves
    -- the scroll's top edge under it, and RenderTabbedSchema is what settings/Panel_Render.lua and
    -- settings/General.lua now call in RenderSchema's place. RefreshScalars joined for a different
    -- reason and it is NOT cosmetic: Helpers.SetAndRefresh calls it on every write now, so on the
    -- degraded path a missing member is a raise inside `/kcd set`, which still works with no panel.
    --
    -- SetRenderer joined the list with CX03. It had been EXEMPTED in
    -- tests/test_surface_parity.lua on the argument that a page which cannot be built has nothing
    -- to render into -- true, and equally true of CreatePanel and EnsureScroll beside it, which are
    -- stubbed anyway. That exemption is how AbsorbTracker's stub came to omit the member outright
    -- with every suite green, and it is now called by all six of this addon's pages rather than
    -- four. A member the host calls is a member the stub owes.
    --
    -- The last five arrived with LibKa0s v1.35.0 (OptionsWidgets 16): the ChoiceGrid radio grid,
    -- the IdInput / IdList spell-item-currency id editor, and the ResolveId / UnnamedCandidates
    -- lookups behind it. This addon adopts none of them yet, and every one is render-time -- a
    -- renderer or a user action reaches it, never a file load -- so the same inert no-op answers.
    -- ResolveId and UnnamedCandidates answer nil, which is what an unresolved id answers live.
    for _, name in ipairs({
        "CreatePanel", "SetRenderer",
        "EnsureDefaultsButton", "EnsureScroll", "ClearScroll", "Section",
        "AddSpacer", "AttachTooltip", "InlineButtonPair", "RenderField", "RenderRows",
        "RenderSchema", "RenderGrid", "SessionCheckbox", "RefreshAllPanels", "RefreshPanel",
        "RefreshScalars",
        "RestoreDefaults",
        "PatchAlwaysShowScrollbar",
        "SetChromeHeight", "TabStrip", "PageBanner", "PageHeader", "SubTabStrip",
        "RenderTabbedSchema",
        "ChoiceGrid", "IdInput", "IdList", "ResolveId", "UnnamedCandidates",
        -- SelectTab, new at LibKa0s v1.36.0: reached only from a tab click on an already-rendered
        -- page. This addon does not adopt tab-scoped refresh, so the same inert no-op applies.
        "SelectTab",
    }) do
        Helpers[name] = function() end
    end
    -- The id editor's per-kind name hints. EMPTY, not a copy: the live table is built from the
    -- library's own kind text (libs/LibKa0s/OptionsWidgets.lua), and options-ui-§1 forbids a
    -- host copy of library content exactly as it forbids a copy of a layout constant. A reader
    -- indexing it on the degraded path gets nil, as it would for a kind the library lacks.
    Helpers.ID_NAME_HINT = {}

    -- The SCHEMA COMPOSERS (libs/LibKa0s/OptionsCompose.lua), and the one place
    -- in this stub that is load-completing for a NEW reason. Every page file
    -- calls them inside its schema declaration at FILE LOAD, so nil members
    -- would raise and take that page's whole row set with them -- the failure
    -- this stub exists to prevent.
    --
    -- HOLLOW, deliberately, AND NOW THE COMPLIANT ANSWER RATHER THAN A ROW.
    -- This was docs/ARCHITECTURE.md's one PROVISIONAL register row until
    -- options-ui-§1 ruled on it: when the missing content is COMPOSED the
    -- no-copy MUST wins, a stub's composer members answer an empty row list,
    -- and the rows already written for the shape retire. The canonical
    -- font / border / bar /
    -- color-pair / master-controls blocks live in the library, and a host copy of
    -- them is exactly the drift the composers were extracted to end
    -- (options-ui-§16, anti-pattern #73) -- the same argument options-ui-§1 makes
    -- against copying a widget maker or a layout constant here. So the degraded
    -- load registers 112 of the addon's 228 rows.
    --
    -- WHAT THAT COSTS, MEASURED. options-ui-§1's stated harm is `list`, `get`, `set`,
    -- `reset` and the profile defaults breaking silently, and neither half is
    -- reachable here:
    --   * LibKa0s-Slash-1.0 is in this same libs/LibKa0s/ folder, which options-ui-§1
    --     requires be vendored WHOLE (anti-pattern #48), so the load that loses
    --     the composers loses the schema CLI in the same breath.
    --     settings/Slash.lua's stub answers set/get/list/reset with one "is
    --     unavailable" line each -- for a HOST-DECLARED row exactly as for a
    --     composed one. A composed path is never addressable-but-missing.
    --   * The profile defaults are defaults/Profile.lua's, merged by AceDB in
    --     core/Database.lua's aceDBDefaults, and are never read off the schema.
    -- The three readers of NS.Settings.Schema are the CLI, the panel and
    -- RestoreAllDefaults' sessionOnly walk -- absent, absent, and looking for
    -- state.debugConsole, whose console window is unavailable on this path too.
    --
    -- Both halves are pinned rather than argued: tests/test_options_panel.lua's
    -- "with LibKa0s absent the schema loads complete BAR the composed blocks"
    -- fingerprints the delta, and "the hollow composers cost the degraded path no
    -- CLI reach it otherwise has" pins the blast radius.
    for _, name in ipairs({ "ColorPair", "FontGroup", "BorderGroup", "BarGroup" }) do
        Helpers[name] = function() return {} end
    end
    -- Two returns, because the live one has two: the rows, and the afterGroup
    -- that draws the tab's closing button pair. settings/General.lua keys its
    -- afterGroup table with the second, inside a renderer that never runs here.
    Helpers.MasterControls = function() return {}, function() end end
    -- ONE of the library's `__` internals, and the list used to be eleven.
    --
    -- The ten that left -- __panels, __bannerBand, __layoutTabs, __releaseChrome, __scrollTopInset,
    -- __tabBand, __tabPlacement, __releaseSubTabs, __tabArtHeight, __resetTabArtHeight -- were
    -- mirrored for ONE reason, and it was stated here: the parity gate read the WHOLE live surface,
    -- so a member that existed live and not here was reported as a hole. M4-09 moved
    -- tests/test_surface_parity.lua onto Kit.assertSurfaceParity's by-name form, which compares
    -- Kit.publicMembers and drops the whole `__` prefix, so that reason is gone and what was left
    -- was ten no-op members with no caller anywhere in this addon -- copies waiting to go stale on
    -- the next re-vendor that renames one. libs/LibKa0s/Options.lua's comment at O.__print states
    -- the rule the kit now enforces: a `__` member is the library talking to itself across its own
    -- file boundary, and a degradation stub does not mirror it.
    --
    -- __panelFor STAYS, because this addon is the exception to that rule and the kit cannot know
    -- it: settings/Panel_Widgets.lua:138's OpenPageTab reads
    -- `Helpers.__panelFor and Helpers.__panelFor(pageKey)` to pre-select the destination page's
    -- tab. A member the host calls is a member the stub owes -- the same sentence SetRenderer
    -- joined the no-op list under. The guard means losing it costs a tab selection rather than a
    -- raise, which is why tests/test_surface_parity.lua pins it BY HAND beside the parity call
    -- rather than trusting the filter.
    --
    -- The three layout CONSTANTS that arrived with the departed ten -- BANNER_H, CHROME_GAP, TAB_H
    -- -- never appeared here and still must not: options-ui-§8 forbids a host copy of a library
    -- constant, the copy is the one that goes stale, and tests/test_options_panel.lua scans this
    -- file for exactly that.
    Helpers.__panelFor = function() return nil end

    NS.RegisterOptionsPage = function() end
    NS.RefreshOptionsPanel = function() end
    NS.CreateOptionsPanel  = function()
        if NS.Util and NS.Util.print then NS.Util.print(MISSING) end
    end
    NS.OpenOptionsPanel = NS.CreateOptionsPanel
    return
end

-- ---------------------------------------------------------------------
-- The live wiring
-- ---------------------------------------------------------------------

-- The LSM30_Border fixup, and why it is a call rather than a file.
--
-- A LIBRARY ACT, NOT AN ADDON ONE. AceGUI's WidgetRegistry is process-global:
-- one slot named "LSM30_Border" that every addon in the client shares, Ka0s or
-- not. This addon carried the fixup privately in core/LSMPatch.lua, and so did
-- AbsorbTracker, ConsumableMaster, MultiMeters and PanelMaster -- five copies,
-- five distinct md5s, each registering its wrapper at whatever version it found
-- plus one. Load all five in one session and the wrapper a Border dropdown
-- actually gets belongs to whichever addon the loader reached last. Nothing in
-- any of the five repos could see it: each suite loads one copy, registers once
-- and passes.
--
-- lib.__PatchLSM30Border (LibKa0s-Options-1.0 minor 15) is the same wrapper
-- published once, guarded by lib.__lsmBorderPatched. Five vendored copies of
-- the library are still ONE instance to LibStub, so five callers produce one
-- registration and the return value says which call made it. Calling it is
-- unconditional and needs no agreement with any sibling addon.
--
-- HERE, AT FILE LOAD, is early enough. KickCD.toc pulls
-- libs\AceGUI-3.0-SharedMediaWidgets\widget.xml in with the other libraries
-- (:28), well before settings\OptionsSetup.lua (:72), so the slot already holds
-- AGSMW's own constructor when this line runs. AceGUI refuses a registration
-- whose version is not strictly higher than the one it already holds, so
-- another addon's later copy of AGSMW cannot take the slot back at its own
-- fixed version. (Written without naming the AceGUI entry point, so that
-- C02's acceptance grep for it over core/, modules/ and settings/ keeps
-- returning nothing rather than one comment an auditor has to re-read.)
-- It sits in this file because this is where the addon's options
-- surface is wired, which is where the library's own note on the member says to
-- call it from.
--
-- core/LSMPatch.lua IS GONE, deleted in the same commit that added this line.
-- Keeping it would have been a second registration of a wrapper the library has
-- already installed -- harmless in effect, since both hide the same tile and
-- re-anchor the same two regions, but it is the exact shape the promotion
-- exists to remove.
lib.__PatchLSM30Border()

NS.Settings = NS.Settings or {}
NS.Settings.Helpers = lib:New(descriptor)

local Helpers = NS.Settings.Helpers

-- Every page's Blizzard subcategory, by page key. The library's registry drops
-- the builder's return value -- it has no use for it -- so the one thing a host
-- needs to send a reader to ANOTHER page is otherwise unrecoverable: Blizzard's
-- Settings.OpenToCategory takes a category id, and the object that carries it
-- exists for exactly one statement inside each builder.
--
-- Captured HERE rather than in the builders, so a page added later gets it for
-- free instead of remembering to file itself.
NS.Settings.categoryFor = NS.Settings.categoryFor or {}

NS.RegisterOptionsPage = function(key, name, builder)
    Helpers.RegisterOptionsPage(key, name, function(mainCategory)
        local category = builder(mainCategory)
        NS.Settings.categoryFor[key] = category
        return category
    end)
end
NS.CreateOptionsPanel  = function() Helpers.CreateOptionsPanel() end
NS.OpenOptionsPanel    = function() Helpers.OpenOptionsPanel() end

-- AceDB profile changes call this so any open page re-reads its values, and so
-- do `/kcd set`, `/kcd reset` and `/kcd resetall` through SetAndRefresh.
NS.RefreshOptionsPanel = function() Helpers.RefreshAllPanels() end
