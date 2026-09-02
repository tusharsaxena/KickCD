-- settings/General.lua
--
-- General canvas panel. Two tabs, Master controls and Units, partitioned from
-- the `group` field in declaration order (options-ui-§13).
--
-- The first tab is the collection's canonical Master controls block
-- (options-ui-§15) and it is COMPOSED, not written out: H.MasterControls emits
-- SIX canonical rows from one declaration, and the afterGroup it returns draws
-- the closing Reset position / Reset all settings button pair.
--
-- SIX, not eight. §15's canonical table has EIGHT cells and its last line IS the
-- button pair, so "the eight canonical rows, plus the button-pair hook" counts
-- those two twice. What the composer emits is `enabled`, `visibility`, `scale`,
-- `alpha`, `locked` and `state.debugConsole`
-- (libs/LibKa0s/OptionsCompose.lua:350-380). The two resets are actions rather
-- than settings -- an anchor is not a key=value the schema covers -- which is
-- why they are a button pair and not rows.
--
-- WHY TWO TABS AND NOT THREE. "Appearance" used to be a section of its own,
-- holding master scale and master alpha. Two rows whose LABELS both say Master
-- is not a second subject, it is the same subject broken over a click: enable,
-- visibility, lock, scale and alpha are all the addon-as-a-whole, and §15 puts
-- all five under one tab anyway. Units is the one genuinely different question
-- on this page -- which grids exist, and whether Focus is its own thing -- and
-- it is what a player sets once, so it sits last.
--
-- Every schema entry here is automatically wired into /kcd get|set,
-- so adding a new General option = one row in this file.

local addonName, NS = ...
local L      = NS.L
local H      = NS.Settings.Helpers
local Schema = NS.Settings.Schema

local function add(t) Schema[#Schema + 1] = t end

-- Master controls — the canonical tab (options-ui-§15), COMPOSED rather than
-- typed out (options-ui-§16). H.MasterControls emits the canonical set in the
-- one order nine addons share:
--     [Enable KickCD]   | [General visibility]
--     [Master scale]    | [Master alpha]
--     [Lock frame]      | [Debug console]
-- and hands back the afterGroup that closes the tab with its button pair:
--     [Reset position]  | [Reset all settings]
--
-- The Debug console is the composer's SESSION-ONLY row now, not the bespoke
-- SessionToggle this page used to draw beside Lock frame. It still shows/hides
-- the console WINDOW and still never persists — settings/Panel.lua's
-- SESSION_PATHS is where its path resolves — but it is a schema row, so
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
    -- The two stored values this addon does not share with the canonical block.
    -- PASSED, never edited into the composer: the composer must not change what
    -- is stored, and `visibility` has shipped as
    -- "target_casting_interruptible" since the addon's first release.
    defaults         = {
        visibility   = "target_casting_interruptible",
        debugConsole = false,
    },
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
local visibilityRow = H.FindSchema("visibility")
if visibilityRow then
    visibilityRow.values  = {
        ["always"] = L["Always"],
        ["in_combat"] = L["In combat"],
        ["target_casting"] = L["When target is casting"],
        ["target_casting_interruptible"] = L["When target is casting an interruptible spell"],
    }
    visibilityRow.sorting = {
        "always", "in_combat", "target_casting", "target_casting_interruptible",
    }
    visibilityRow.tooltip = L["When the addon (icon grid + cast bar) should be visible. Master enable still wins — disabled hides everything."]
end

-- Per-unit ENABLE toggles (§Task 6). One row per NS.Units.LIST entry, driving
-- `/kcd set units.<unit>.enabled` and (via Helpers.Set firing
-- Ka0s_KickCD_CONFIG_CHANGED{section="units"}) IconGrid/Castbar's
-- ReconcileUnits. The label/selector/link/copy UI (Task 8) lives in its own
-- panel; this is deliberately just the enable bool so both rows render
-- under SchemaForPanel("general") regardless of which unit is "selected".
for _, u in ipairs(NS.Units.LIST) do
    add{
        panel   = "general", section = "units", group = L["Units"],
        path    = "units." .. u .. ".enabled", unit = u, type = "bool",
        label   = (u == "target" and L["Enable Target grid"] or L["Enable Focus grid"]),
        desc    = (u == "target"
                   and L["Track cooldowns for your current target."]
                   or L["Track cooldowns for your current focus."]),
        default = true,
    }
end

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
        pageKey        = "general",
        defaultsButton = true,
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
        H.RenderTabbedSchema(c, "general", {
            [H.MASTER_GROUP] = masterTail,
            -- The Focus styling link. It used to be drawn three times over, once
            -- in each unit page's hand-built header, and there is exactly one of
            -- it: whether Focus keeps its own appearance or mirrors Target's.
            -- Neither control is a schema row — `link` is a plain profile field
            -- with no path in the schema, and the copy is an action — so both
            -- hang off the Units group rather than becoming rows.
            --
            -- The write is STRUCTURAL, and that is the whole reason it can live
            -- on another page at all: H.RefreshAllPanels re-renders every page
            -- that declared a renderer, and marks the hidden ones dirty so they
            -- repaint on their next OnShow. Ticking this here really does change
            -- what Icons / Cast bar / Text Label draw.
            [L["Units"]] = function(ctxRef)
                H.SessionToggle(ctxRef, {
                    label = L["Use same styling as Target"],
                    tooltip = L["Focus mirrors Target's icon grid, cast bar and label appearance. Untick to give Focus its own."],
                    get   = function()
                        local cfg = NS.Units.Config("focus")
                        return cfg ~= nil and cfg.link == true
                    end,
                    set   = function(on)
                        local cfg = NS.Units.Config("focus")
                        if cfg then cfg.link = on and true or false end
                        H.FireConfigChanged("units")
                        H.RefreshAllPanels()
                    end,
                }, nil, 0.5)
                H.InlineButtonPair(ctxRef,
                    {
                        text    = L["Copy styling from Target"],
                        tooltip = L["Copy Target's current appearance onto Focus once, and unlink so the two can drift apart from here."],
                        onClick = function()
                            NS.Units.CopyStyling("target", "focus")
                            H.FireConfigChanged("units")
                            H.RefreshAllPanels()
                        end,
                    })
            end,
        })
    end)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["General"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("general", L["General"], Build)
end
