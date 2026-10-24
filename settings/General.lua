-- settings/General.lua
--
-- General canvas panel. ONE tab, Master controls (options-ui-§13: a one-tab strip).
-- The per-unit rows filed under the `Units` group below are skipRender and drawn
-- by the Units page's band instead (KIC-L01/L02, item 020), so that group is no
-- tab here (RenderTabbedSchema's untabbedSkipRender).
--
-- The first tab is the collection's canonical Master controls block
-- (options-ui-§15) and it is COMPOSED, not written out: H.MasterControls emits
-- SEVEN canonical rows from one declaration, and the afterGroup it returns draws
-- the closing Reset position / Reset all settings button pair.
--
-- SEVEN, not nine. options-ui-§15's canonical table's last line IS the button pair, so
-- counting "the canonical rows, plus the button-pair hook" counts those two
-- twice. What the composer emits is `enabled`, `visibility`, `scale`, `alpha`,
-- `locked`, `state.debugConsole` and -- since compose minor 7 -- the minimap
-- button's `global.minimap.shown`. The two resets are actions rather than
-- settings -- an anchor is not a key=value the schema covers -- which is why
-- they are a button pair and not rows.
--
-- NO TEST MODE ROW, by the standard's own exemption (options-ui-§15, v2.49.0):
-- unlocking already shows the grids and the cast bar's placeholder, so Lock
-- frame is the switch, and a Test mode checkbox would be a second switch for
-- the same state. Hence no `testModePath` here and no `/kcd test` verb -- which
-- is also why the Minimap button row sits alone on its line rather than paired
-- with one: the composer drops its `startsLine` only when a test mode is there
-- to pair with.
--
-- WHY ONE TAB. "Appearance" used to be a section of its own, holding master
-- scale and master alpha. Two rows whose LABELS both say Master is not a second
-- subject, it is the same subject broken over a click: enable, visibility, lock,
-- scale and alpha are all the addon-as-a-whole, and options-ui-§15 puts all five
-- under one tab anyway. The Units tab that followed it -- the per-unit enables
-- and the Focus link -- moved to the Units page's band in item 020 (KIC-L01/L02):
-- everything about one unit now sits on the page that picks the unit.
--
-- Every schema entry here is automatically wired into /kcd get|set,
-- so adding a new General option = one row in this file.

local _, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Store  = NS.Settings.Store

-- Through the seam's registry (settings/SchemaSetup.lua), so Store.FindRow
-- indexes the row the moment it lands.
local function add(t) Store.AddRows({ t }) end

-- Master controls — the canonical tab (options-ui-§15), COMPOSED rather than
-- typed out (options-ui-§16). H.MasterControls emits the canonical set in the
-- one order nine addons share:
--     [Enable KickCD]   | [General visibility]
--     [Master scale]    | [Master alpha]
--     [Lock frame]      | [Debug console]
--     [Minimap button]
-- and hands back the afterGroup that closes the tab with its button pair:
--     [Reset position]  | [Reset all settings]
--
-- The Debug console is the composer's SESSION-ONLY row now, not the bespoke
-- SessionToggle this page used to draw beside Lock frame. It still shows/hides
-- the console WINDOW and still never persists — the get/set pair wired onto
-- the row below is where its value lives — but it is a schema row, so
-- `/kcd get|set|list state.debugConsole` reaches it like anything else.
--
-- The group's rows MUST stay contiguous: RenderTabbedSchema partitions by
-- `group` in declaration order, and a row filed under a group the array has
-- already left prints that tab a second time.
local masterRows, masterTail = H.MasterControls{
    prefix           = "",
    page             = "general",
    addonName        = "KickCD",
    debugConsolePath = "state.debugConsole",
    -- The minimap button's visibility (launcher-§3), composed since compose
    -- minor 7. VERBATIM and unprefixed like the console path, and for the same
    -- reason in a different store: LibDBIcon's table lives in db.GLOBAL, outside
    -- this block's profile prefix. STORED, not session -- a button the player
    -- hid stays hidden across a reload. The row's boolean says SHOWN while
    -- LibDBIcon's key says hidden, so the inversion is ours and lives on the
    -- row's own get/set (wired below), never in the composer.
    -- The path reads in the row's sense (launcher-§3, v2.65.0) while the store
    -- stays LibDBIcon's `hide`: no `shown` key is ever written.
    minimapPath      = "global.minimap.shown",
    -- The two stored values this addon does not share with the canonical block.
    -- PASSED, never edited into the composer: the composer must not change what
    -- is stored, and `visibility` has shipped as
    -- "target_casting_interruptible" since the addon's first release.
    defaults         = {
        visibility   = "target_casting_interruptible",
        debugConsole = false,
    },
    -- Unlocking IS this addon's test mode (no Test mode row, above), so Lock
    -- frame takes the library's one tooltip for that shape (KIC-L-new4, XC-05).
    -- No host text and no `notes.locked`: the combat clause the library leaves
    -- to the host is added only once KickCD's lock behavior in combat has been
    -- verified in game.
    lockIsPreview    = true,
    onResetPosition  = function() H.ResetIconPosition() end,
    onResetAll       = function() StaticPopup_Show("KICKCD_RESET_ALL") end,
}
H.AddComposed(masterRows, { panel = "general", section = "general" })

-- THE ONE OVERRIDE, and it is a ratified deviation from options-ui-§15's value
-- list — see docs/ARCHITECTURE.md's `## Documented deviations`. KickCD's
-- visibility is CAST-state driven: "when the target is casting an interruptible
-- spell" is the mode the whole addon exists for, and the canonical Always /
-- Only in combat / Only out of combat / Never cannot express it. The stored
-- KEYS are untouched, so nothing migrates; only the option list and the prose
-- describing it differ. The row's position, label and pairing stay the
-- composer's.
local visibilityRow = Store.FindRow("visibility")
if visibilityRow then
    visibilityRow.values  = {
        ["always"] = L["Always"],
        ["in_combat"] = L["In combat"],
        ["target_casting"] = L["When the tracked unit is casting"],
        ["target_casting_interruptible"] = L["When the tracked unit is casting an interruptible spell"],
    }
    visibilityRow.sorting = {
        "always", "in_combat", "target_casting", "target_casting_interruptible",
    }
    visibilityRow.tooltip = L["When KickCD's displays (icon grids, cast bars and labels) are shown. Enable KickCD still wins: off hides everything."]
end

-- ── The three composed rows that carry this addon's own behavior ──────────
--
-- Wired here, beside the override above, because the composer declares the
-- rows and only the host knows what they do. On a library-less load the
-- composer is hollow, none of the three exists, and nothing is wired; the
-- host verbs that write `enabled` and `locked` then land through the seam's
-- writeThrough list (settings/SchemaSetup.lua).

-- THE MASTER SWITCH, TAKEN IN THE SAME TURN AS THE WRITE (slash-commands-§7).
-- The row's onChange, because every surface that can flip it -- the checkbox,
-- `/kcd set enabled`, the `enable` / `disable` verbs and a Defaults that happens
-- to clear it -- lands on the one write seam, and the seam runs onChange BEFORE
-- it announces: a module that re-rendered first and stood down second would draw
-- one frame of an addon that is already off.
local enabledRow = Store.FindRow("enabled")
if enabledRow then
    enabledRow.onChange = function() NS.RefreshEnabledHold() end
end

-- The Debug console is SESSION state: the console WINDOW, never the debug
-- CAPTURE flag (debug-logging-§5), which stays on the in-window "Debug: ON/OFF"
-- button and `/kcd debug on|off`. The composer emits its path verbatim
-- (`state.debugConsole`) and marks it sessionOnly; this pair is where its value
-- lives, so the panel checkbox, `/kcd set` and the reset sweep all take the
-- addon's one write path (options-ui-§1) and nothing reaches the profile.
local consoleRow = Store.FindRow("state.debugConsole")
if consoleRow then
    consoleRow.get = function() return NS.DebugLog ~= nil and NS.DebugLog:IsShown() end
    consoleRow.set = function(on)
        if not NS.DebugLog then return end
        if on then NS.DebugLog:Show() else NS.DebugLog:Hide() end
    end
end

-- The GLOBAL store's one schema row, and the inversion is OURS rather than the
-- library's (launcher-§3):
--
--   * SCOPE. Every other stored row lives in db.PROFILE. LibDBIcon's table is
--     `db.global.minimap` and the standard fixes it there: a profile switch must
--     not move a player's buttons, and options-ui-§12's `Reset all settings`, a
--     profile reset by definition, must not un-hide a button the player
--     deliberately hid.
--   * SENSE. The row's label says SHOWN and LibDBIcon's key says HIDDEN. There
--     is ONE boolean -- the library writes it too, from its own right-click menu
--     -- so a second stored `minimap.shown` beside it would be a copy free to
--     disagree the first time either surface was used (anti-pattern #81). The
--     PATH is the row's CLI name, and launcher-§3 (v2.65.0) spells it in the
--     row's own sense: `global.minimap.shown` answers true while the button
--     shows. No `shown` key is ever written, which is why it can only be a
--     get/set pair on the row.
--
-- STORED, not session: settings/OptionsSetup.lua's `vetoedFromResetAll` keeps
-- it out of `Reset all settings` because it is not sessionOnly, and the seam's
-- `resetExempt` keeps it out of the General page's Defaults. The set calls
-- NS.Launcher:SetShown so the button follows the checkbox immediately; SetShown
-- writes `hide` again with the same value, which is harmless.
local minimapRow = Store.FindRow("global.minimap.shown")
if minimapRow then
    minimapRow.get = function()
        local t = NS.db and NS.db.global and NS.db.global.minimap
        return not (t and t.hide)
    end
    minimapRow.set = function(shown)
        local t = NS.db and NS.db.global and NS.db.global.minimap
        if t then t.hide = not shown end
        if NS.Launcher then NS.Launcher:SetShown(shown) end
    end
end

-- Per-unit ENABLE toggles (§Task 6). One row per NS.Units.LIST entry, driving
-- `/kcd set units.<unit>.enabled` and (via the seam's announce firing
-- Ka0s_KickCD_ConfigChanged{section="units"}) IconGrid/Castbar's
-- ReconcileUnits.
--
-- DRAWN BY THE UNITS PAGE'S BAND, beside the Unit picker (KIC-L01, item 020):
-- `skipRender` here, and Helpers.RenderUnitPanel (settings/Panel_Render.lua)
-- draws the selected unit's row through the library's own RenderField. The
-- STAMP STAYS `panel = "general"`, `section = "units"`, on purpose: the
-- General page's Defaults, Reset all and `/kcd list` (grouped by panel) behave
-- exactly as before, and both pages' Defaults tooltips say so (the WS-33
-- disclosure: settings/General.lua's Build below, settings/Grid.lua's).
--
-- ONE label for both units, "Enable this unit" (XC-16): it reads with the
-- band's Unit picker, whose noun it borrows. The switch gates the unit's icon
-- grid, cast bar (modules/Castbar.lua) and label (modules/UnitLabel.lua), so
-- the tooltip names all three.
for _, u in ipairs(NS.Units.LIST) do
    add{
        panel   = "general", section = "units", group = L["Units"],
        path    = "units." .. u .. ".enabled", unit = u, type = "bool",
        label   = L["Enable this unit"],
        desc    = L["Track this unit: its icon grid, cast bar and label. Off hides all three."],
        default = true,
        skipRender = true,
    }
end

-- The Focus styling link. A real row, so `/kcd get|set|list|reset` reach it and
-- the General page's Defaults restores it (architecture-§5: a toggle the player
-- sets is a setting, and a setting with no row is a missing row). Only Focus has
-- one; Target is never linked.
--
-- `skipRender`: the row stays in the schema but the library does not draw it in
-- the flow. The Units page's band draws it beside the picker while Focus is the
-- unit in the band, paired with the Copy from Target button, through the
-- library's RenderField -- so the tick writes through the seam like any row.
--
-- The onChange is STRUCTURAL, which no other row's is. Flipping the link changes
-- what the Units page's Icons, Cast bar and Text label entries DRAW (a linked
-- Focus entry is just the note, plus its alwaysPerUnit rows), so every page that
-- declared a renderer re-renders and the hidden ones repaint on their next show.
-- The CONFIG_CHANGED `units` that IconGrid / Castbar reconcile on comes from the
-- seam's announce, through the row's section.
--
-- ONLY WHEN THE LINK MOVED. A write that leaves it where it was (a Defaults on
-- an already-linked Focus, a repeated `/kcd set`) changes nothing any page
-- draws, so it skips the rebuild of every rendered page. Copy from Target relies
-- on this row for its refresh, and repaints by itself when the link does not
-- move (core/Units.lua).
--
-- The seam hands onChange the new value and nothing else, so the row stores
-- through its own `set`, which notes whether the stored link moved before it
-- writes, and onChange reads that note. Store.Get still reads the row straight
-- out of the profile: it has no `get` of its own.
local linkMoved = false
add{
    panel   = "general", section = "units", group = L["Units"],
    path    = "units.focus.link", type = "bool",
    label   = L["Link to Target"],
    desc    = L["Focus mirrors Target's icon grid, cast bar and label appearance. Untick to give Focus its own."],
    default = NS.DEFAULT_PROFILE.units.focus.link,
    skipRender = true,
    set = function(value)
        local focus = NS.Units.Config("focus")
        linkMoved = focus ~= nil and focus.link ~= value
        if focus then focus.link = value end
    end,
    onChange = function()
        if linkMoved then H.RefreshAllPanels() end
    end,
}

-- ---------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------

-- StaticPopup for "Reset all settings" — irreversible, so confirm
-- before wiping. The OnAccept body lives in Helpers.ResetAll so the
-- popup, the General > "Reset all settings" button, and the
-- `/kcd resetall` slash command all share a single implementation —
-- no chance of the popup and the slash diverging.
StaticPopupDialogs["KICKCD_RESET_ALL"] = {
    -- THE COLLECTION'S ONE WORDING (options-ui-§12), verbatim. Addon-agnostic on
    -- purpose: no addon enumerates its own nouns, and eight phrasings of one act
    -- is how a collection reads as eight addons.
    text         = L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded \226\128\148 your other profiles are not affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function() H.ResetAll() end,
}

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx
    -- `pageKey`, not `panelKey`: the library's CreatePanel reads opts.pageKey and
    -- drops anything else, so every page in this addon had been handing it a key
    -- it ignored -- leaving ctx.pageKey nil, O.__panelFor unable to find any
    -- page, and the library's render-failure line naming "?" instead of the page
    -- that raised. Inert until something asked, which is exactly why it survived.
    ctx = H.CreatePanel("KickCDGeneralPanel", L["General"], {
        pageKey         = "general",
        defaultsButton  = true,
        -- A PAGE reset, not the global one (that is Reset all settings), so not
        -- H.ResetAllTooltip. Its last sentence is this page's half of the WS-33
        -- disclosure: the three rows the Units page's band draws keep their
        -- `panel = "general"` stamp, so this button resets them (settings/Grid.lua
        -- carries the other half).
        defaultsTooltip = L["Restore the Master controls tab to its defaults. It also resets both units' Enable this unit and Focus's Link to Target, which sit in the Units page's band."],
    })
    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("general", ctx)
    end

    -- The library owns WHEN this draws (H.SetRenderer): first show, and again
    -- when a refresh marked it dirty while it was hidden. Building at
    -- registration time would lay the widgets out against a zero-width body,
    -- because registration happens at PLAYER_LOGIN.
    H.SetRenderer(ctx, function(c)
        H.ClearScroll(c)
        -- untabbedSkipRender: the `Units` group's rows are all skipRender (the
        -- Units page's band draws them), so the group must not become an empty
        -- tab here (LibKa0s OptionsTabs minor 8).
        H.RenderTabbedSchema(c, "general", {
            [H.MASTER_GROUP] = masterTail,
        }, nil, { untabbedSkipRender = true })
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["General"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("general", L["General"], Build)
end
