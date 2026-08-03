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
-- Helpers.LSMValues and Helpers.AnchorValues inside schema-row literals AT FILE
-- LOAD. See the stub below for what that costs.

-- ---------------------------------------------------------------------
-- The one rule about what a global reset must not touch
-- ---------------------------------------------------------------------
--
-- Profiles rows are AceDBOptions-supplied and resetting them deletes user data,
-- which is not what "restore defaults" means to anyone (options-ui-§3). Named
-- once because it is enforced twice — by the library through
-- descriptor.skipRestoreAll, and by the degradation stub's own reset loop, which
-- has to keep working with no library at all.
local function vetoedFromResetAll(row) return row.panel == "profiles" end

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
    -- so applyDefault never reaches them. `/kcd resetall` and the General page's
    -- popup both funnel through Helpers.ResetAll, which clears all three — this
    -- hook is how the library's own RestoreAllDefaults gets there too. It runs
    -- BEFORE the refresh, which is load-bearing: a refresh first would paint the
    -- pre-hook values.
    afterRestoreAll = function()
        local H = helpers()
        if H and H.ResetAllPositions then H.ResetAllPositions() end
        if H and H.RestoreUnitLinks then H.RestoreUnitLinks() end
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

    -- Ka0s standard §3.4: resolve AceGUI once and read the upvalue. The page
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
-- settings/Icons.lua and settings/Castbar.lua evaluate `H.LSMValues("border")`
-- and `H.AnchorValues()` inside schema-row literals, at FILE LOAD. With those
-- members nil the page file raises, so its rows never register, so a large part
-- of NS.Settings.Schema is missing — and `/kcd list`, `/kcd get`, `/kcd set`,
-- `/kcd reset` and the profile defaults all break with it, silently. The addon
-- would not degrade; it would half-load and say nothing.
--
-- MEASURED, not assumed (options-ui-§1 requires exactly that): this stub needs
-- ZERO load-time members, and that is a real difference from the reference
-- consumer. AbsorbTracker takes LSMValues from the LIBRARY, so its stub must
-- publish one or its page files raise. KickCD keeps LSMValues, AnchorValues and
-- AnchorOrder as its OWN code in settings/Panel.lua — host code that is present
-- whether or not LibKa0s is — and Panel.lua loads before every page file. So the
-- load-time hole AbsorbTracker's stub exists to plug does not exist here.
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
        for _, row in ipairs(NS.Settings.Schema or {}) do
            if not vetoedFromResetAll(row) and Helpers.SetAndRefresh then
                local d = row.default
                Helpers.SetAndRefresh(row.path, type(d) == "table" and NS.Util.DeepCopy(d) or d)
            end
        end
        if Helpers.ResetAllPositions then Helpers.ResetAllPositions() end
        if Helpers.RestoreUnitLinks then Helpers.RestoreUnitLinks() end
    end

    -- Reached only from a builder or a user action, so a no-op is honest.
    for _, name in ipairs({
        "CreatePanel", "EnsureDefaultsButton", "EnsureScroll", "ClearScroll", "Section",
        "AddSpacer", "AttachTooltip", "InlineButtonPair", "RenderField", "RenderRows",
        "RenderSchema", "SessionCheckbox", "RefreshAllPanels", "RestoreDefaults",
        "PatchAlwaysShowScrollbar",
    }) do
        Helpers[name] = function() end
    end
    Helpers.__panels   = function() return {} end
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

NS.Settings = NS.Settings or {}
NS.Settings.Helpers = lib:New(descriptor)

local Helpers = NS.Settings.Helpers

NS.RegisterOptionsPage = function(key, name, builder) Helpers.RegisterOptionsPage(key, name, builder) end
NS.CreateOptionsPanel  = function() Helpers.CreateOptionsPanel() end
NS.OpenOptionsPanel    = function() Helpers.OpenOptionsPanel() end

-- AceDB profile changes call this so any open page re-reads its values, and so
-- do `/kcd set`, `/kcd reset` and `/kcd resetall` through SetAndRefresh.
NS.RefreshOptionsPanel = function() Helpers.RefreshAllPanels() end
