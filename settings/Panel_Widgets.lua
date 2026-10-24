-- settings/Panel_Widgets.lua
--
-- What is left of this file after LibKa0s-Options-1.0 took the widget layer.
--
-- GONE, because libs/LibKa0s/OptionsWidgets.lua provides them: the five widget
-- makers (checkbox, slider, dropdown, edit box, color picker), RenderField's
-- type dispatch, the tooltip attacher, the spacer, the section heading and
-- InlineButtonPair. They were ~300 lines and one of several near-identical
-- copies across the collection — the drift anti-patterns #47 describes.
--
-- ALSO GONE: InlinePair, two half-width widgets in one Flow row where each half
-- came from a caller-supplied render function. It existed for exactly one line
-- -- General's "Lock frame" checkbox beside the bespoke session-only "Debug
-- console" toggle -- and that line is H.MasterControls' now (options-ui-§15),
-- where both halves are ordinary schema rows the flow engine pairs by itself.
-- With its one caller gone it was a host widget maker with no consumer, which is
-- precisely what options-ui-§1 says must not sit here.
--
-- ALSO GONE, with item 020 (KIC-L01/L04): SessionToggle, an argument-order
-- adapter over the library's SessionCheckbox, and LinkText / LinkRow, a
-- clickable full-width line. Their last caller was the General page's Units tab
-- -- the Focus link tick and the linked-Focus note's link to it -- and the tick
-- is the schema row itself, drawn by the Units page's band through RenderField,
-- while the note is plain text now. A host widget maker with no consumer is the
-- thing options-ui-§1 says must not sit here.
--
-- WHAT STAYS: OpenPageTab, the one seam that opens one of this addon's pages on
-- a named tab (and a Units entry key on that entry). It is navigation, not a
-- widget maker.

local _, NS = ...
local Helpers = NS.Settings.Helpers

--- Open one of this addon's own settings pages, on a named tab.
---
--- REFUSES UNDER COMBAT, and does not defer-and-replay. Blizzard's category
--- switch is protected, so calling it under lockdown taints the panel for the
--- rest of the session (options-ui-§2) -- the same rule, and the same refusal,
--- that `/kcd config` obeys. Replaying on regen is the other wrong answer: a
--- panel that opens itself the instant combat drops steals focus during recovery.
---
--- The tab is set on the page's ctx BEFORE the switch, so the page draws the
--- named tab on the render the switch triggers rather than opening on whatever it
--- was last left on and jumping a frame later.
---
--- An entry key of the Grid page (`icons`, `castbar`, `label`) opens Grid on that entry and tab.
--- Refuse and say so, or answer false. Its own function because each guard in
--- the ladder counts as a decision and the two halves together measured past the
--- release gate's complexity cap (performance-§10).
---
--- The wording is this addon's localized line rather than the library's shared
--- English one, matching `/kcd config`'s refusal -- one act, one sentence,
--- whichever door it came through.
local function refusedInCombat()
    if not (_G.InCombatLockdown and _G.InCombatLockdown()) then return false end
    local msg = (NS.L and NS.L["Cannot open settings during combat."])
        or "cannot open settings during combat"
    if NS.Util then NS.Util.print((NS.GRAY or "") .. msg .. "|r") end
    return true
end

--- The Blizzard category id for one of this addon's pages, or nil.
local function categoryID(pageKey)
    local registry = NS.Settings and NS.Settings.categoryFor
    local category = registry and registry[pageKey]
    return category and category.GetID and category:GetID()
end

function Helpers.OpenPageTab(pageKey, tabKey)
    if refusedInCombat() then return false end

    -- A former page key is an entry of the Grid page now (KickCD#33): select the
    -- entry and its tab there, then open Grid. SelectSection marks a hidden page owed
    -- a render, so the entry is what the switch below draws.
    if Helpers.GridSection and Helpers.GridSection(pageKey) then
        if not Helpers.SelectSection(pageKey, tabKey) then return false end
        pageKey, tabKey = "grid", nil
    end

    local ctx = Helpers.__panelFor and Helpers.__panelFor(pageKey)
    if ctx and tabKey then ctx.activeTab = tabKey end

    local id = categoryID(pageKey)
    if not (id and Settings and Settings.OpenToCategory) then return false end

    Settings.OpenToCategory(id)
    -- The destination page may already have been rendered, on another tab. This
    -- is structural -- a different tab is different rows -- so it is the full
    -- sweep rather than a scalar refresh.
    Helpers.RefreshAllPanels()
    return true
end
