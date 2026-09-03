local addonName, NS = ...

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

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)

local function helpers() return NS.Settings and NS.Settings.Helpers end

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

    -- The schema seams. SetAndRefresh rather than the 3-arg Helpers.Set, because
    -- it is the addon's SINGLE write seam: it fires CONFIG_CHANGED with the
    -- row's section, runs the row's onChange and refreshes any open panel. A
    -- panel checkbox then takes exactly the path `/kcd set` takes, which is the
    -- whole point of the rule (options-ui-§1).
    get = function(path)
        local H = helpers()
        return H and H.Get and H.Get(path) or nil
    end,
    set = function(path, value)
        local H = helpers()
        if H and H.SetAndRefresh then H.SetAndRefresh(path, value) end
    end,
    applyDefault = function(row)
        local H = helpers()
        if not (H and H.SetAndRefresh) then return end
        -- DeepCopy, because a default that is a table (an RGBA color) would
        -- otherwise be shared by every profile that reset to it.
        local d = row.default
        H.SetAndRefresh(row.path, type(d) == "table" and NS.Util.DeepCopy(d) or d)
    end,

    -- `filter` is ctx.unit, passed through by the library without interpreting
    -- it. That is what makes a per-unit page render only the selected unit's
    -- rows while a page with ctx.unit nil gets every unit's.
    rowsForPage = function(pageKey, filter)
        local H = helpers()
        return H and H.SchemaForPanel and H.SchemaForPanel(pageKey, filter) or {}
    end,
    allRows = function() return NS.Settings and NS.Settings.Schema or {} end,

    skipRestoreAll = vetoedFromResetAll,

    -- Anchors, the per-unit `link` flag and the spell lists are NOT schema rows,
    -- so applyDefault never reaches them — and none of them needs a hook of its
    -- own any more, because RESET ALL IS A PROFILE RESET (options-ui-§12) and all
    -- three live IN the profile. The library calls `resetProfile` below.
    --
    -- One call, and the same act as the Profiles page's Reset Profile. AceDB
    -- empties the ACTIVE profile — only that one; the profile LIST is untouched,
    -- which is the line the veto above exists for — `aceDBDefaults()` merges
    -- NS.DEFAULT_PROFILE back over it (anchors and every unit's `link` flag with
    -- it), and OnProfileReset reaches Database:OnProfileChanged, which already
    -- folds legacy units, migrates spec keys, RE-SEEDS THE SPELL LISTS and
    -- refreshes — exactly what it does for a profile switch.
    --
    -- ResetAllPositions and RestoreUnitLinks leave this path and keep their other
    -- callers; the spell wipe leaves Helpers.ResetAll for the same reason.
    -- It runs BEFORE the refresh, which is load-bearing: a refresh first would
    -- paint the pre-hook values.
    -- `resetProfile` rather than a hand-written afterRestoreAll: LibKa0s-Options-1.0
    -- minor 9 made this a descriptor field precisely so eight sibling addons stop
    -- writing the same two lines. With it supplied the library narrows its own row
    -- walk to the sessionOnly rows before calling this, so the veto above is belt to
    -- that braces on the live path and the whole policy on the degraded one.
    resetProfile = function()
        local db = NS.db
        if db and db.ResetProfile then db:ResetProfile() end
    end,

    -- Backs the color picker's 50 ms drag throttle. A descriptor field rather
    -- than an AceTimer embed, because embedding would be the library's second
    -- dependency-budget breach.
    scheduleTimer = function(fn, delay) return C_Timer.After(delay, fn) end,

    getLSM   = function() return LibStub and LibStub("LibSharedMedia-3.0", true) end,
    validate = function()
        local H = helpers()
        if H and H.ValidateSchema then H.ValidateSchema() end
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
    Helpers.RestoreAllDefaults = function()
        -- The sessionOnly rows first -- they are the ONLY ones the veto lets
        -- through, and the only ones a profile reset cannot reach, because their
        -- storage is their own set() rather than the db (options-ui-§12).
        for _, row in ipairs(NS.Settings.Schema or {}) do
            if not vetoedFromResetAll(row) and Helpers.SetAndRefresh then
                local d = row.default
                Helpers.SetAndRefresh(row.path, type(d) == "table" and NS.Util.DeepCopy(d) or d)
            end
        end
        -- Then the profile itself, which is the reset. The same one call the live
        -- descriptor's resetProfile makes -- this stub exists because the
        -- LIBRARY is missing, not the db, and the user whose panel will not open
        -- is exactly the user who needs "reset everything".
        local db = NS.db
        if db and db.ResetProfile then db:ResetProfile() end
    end

    -- Reached only from a builder or a user action, so a no-op is honest.
    --
    -- The tabbed-page members (options-ui-§13) and the page banner (§14) joined the list when
    -- the pages adopted them: TabStrip and PageBanner draw the chrome band, SetChromeHeight moves
    -- the scroll's top edge under it, and RenderTabbedSchema is what settings/Panel_Render.lua and
    -- settings/General.lua now call in RenderSchema's place. RefreshScalars joined for a different
    -- reason and it is NOT cosmetic: Helpers.SetAndRefresh calls it on every write now, so on the
    -- degraded path a missing member is a raise inside `/kcd set`, which still works with no panel.
    for _, name in ipairs({
        "CreatePanel", "EnsureDefaultsButton", "EnsureScroll", "ClearScroll", "Section",
        "AddSpacer", "AttachTooltip", "InlineButtonPair", "RenderField", "RenderRows",
        "RenderSchema", "RenderGrid", "SessionCheckbox", "RefreshAllPanels", "RefreshPanel",
        "RefreshScalars",
        "RestoreDefaults",
        "PatchAlwaysShowScrollbar",
        "SetChromeHeight", "TabStrip", "PageBanner", "PageHeader", "SubTabStrip",
        "RenderTabbedSchema",
    }) do
        Helpers[name] = function() end
    end

    -- The SCHEMA COMPOSERS (libs/LibKa0s/OptionsCompose.lua), and the one place
    -- in this stub that is load-completing for a NEW reason. Every page file
    -- calls them inside its schema declaration at FILE LOAD, so nil members
    -- would raise and take that page's whole row set with them -- the failure
    -- this stub exists to prevent.
    --
    -- HOLLOW, deliberately, AND THE DEVIATION THIS PASS MOST WANTS REVIEWED --
    -- docs/ARCHITECTURE.md's `## Documented deviations` carries it as the one
    -- PROVISIONAL row in the table. The canonical font / border / bar /
    -- color-pair / master-controls blocks live in the library, and a host copy of
    -- them is exactly the drift the composers were extracted to end
    -- (options-ui-§16, anti-pattern #73) -- the same argument options-ui-§1 makes
    -- against copying a widget maker or a layout constant here. So the degraded
    -- load registers 112 of the addon's 228 rows.
    --
    -- WHAT THAT COSTS, MEASURED. §1's stated harm is `list`, `get`, `set`,
    -- `reset` and the profile defaults breaking silently, and neither half is
    -- reachable here:
    --   * LibKa0s-Slash-1.0 is in this same libs/LibKa0s/ folder, which §1
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
    -- The library's own internals, mirrored for the same reason __panels and __panelFor already
    -- were: the parity gate reads the WHOLE live surface, and a member that exists live and not
    -- here is a hole whether or not today's host code happens to reach it. The three layout
    -- CONSTANTS that arrived with them -- BANNER_H, CHROME_GAP, TAB_H -- deliberately do NOT
    -- appear: options-ui-§8 forbids a host copy of a library constant, the copy is the one that
    -- goes stale, and tests/test_options_panel.lua scans this file for exactly that.
    Helpers.__panels        = function() return {} end
    Helpers.__panelFor      = function() return nil end
    Helpers.__bannerBand    = function() end
    Helpers.__layoutTabs    = function() end
    Helpers.__releaseChrome = function() end
    Helpers.__scrollTopInset = function() end
    Helpers.__tabBand       = function() end
    Helpers.__tabPlacement  = function() end
    Helpers.__releaseSubTabs   = function() end
    Helpers.__tabArtHeight     = function() end
    Helpers.__resetTabArtHeight = function() end

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
