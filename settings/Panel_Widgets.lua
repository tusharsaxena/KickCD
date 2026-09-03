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
-- WHAT STAYS, and why it could not generalize:
--
--   * SessionToggle — a checkbox over caller-supplied get/set rather than a
--     settings path, for a runtime-only flag that must never persist. The
--     library has this as SessionCheckbox, but with the argument order
--     (ctx, parent, relWidth, spec) rather than this addon's
--     (ctx, spec, parent, relativeWidth). Kept as a thin adapter rather than
--     re-ordering the call sites, and it forwards to the library so there is
--     still only ONE implementation.

local addonName, NS = ...
local Helpers = NS.Settings.Helpers

--- A checkbox wired to caller-supplied get/set instead of a settings path, for
--- runtime-only toggles that must NOT become saved settings.
---
--- A pure argument-order adapter over the library's SessionCheckbox. This
--- addon's call sites pass (ctx, spec, parent, relativeWidth); the library takes
--- (ctx, parent, relWidth, spec). Adapting here keeps one implementation of the
--- widget instead of forking it to match a signature.
---
--- `parent` given (an InlinePair row) renders inline in that row; otherwise the
--- library renders into the page's scroll.
function Helpers.SessionToggle(ctx, spec, parent, relativeWidth)
    return Helpers.SessionCheckbox(ctx, parent, relativeWidth or 0.5, spec)
end

--- Blizzard's link blue, the colour a player already reads as "this goes
--- somewhere". Not the collection's gold, which every heading and every label on
--- these pages is already wearing -- a link that shares its colour with the
--- static text around it is not a link, it is a sentence.
local LINK_COLOR = "|cff71d5ff"

--- Wrap `text` so it reads as a hyperlink.
function Helpers.LinkText(text)
    return LINK_COLOR .. (text or "") .. "|r"
end

--- A full-width line of text that navigates somewhere when clicked.
---
--- An AceGUI InteractiveLabel: the whole line takes the click, because AceGUI has
--- no widget that mixes clickable and static runs inside one string. The caller
--- therefore colours the ACTIONABLE PHRASE with Helpers.LinkText and leaves the
--- rest plain, which is what tells the reader where the sentence leads even
--- though the hit area is the whole of it.
---
--- Returns the widget, or nil having drawn nothing when there is no AceGUI or no
--- scroll -- the same contract every maker on these pages has.
function Helpers.LinkRow(ctx, text, onClick, tooltip)
    -- The INSTANCE's handle, not NS.AceGUI (library-stack-§4): the library
    -- re-resolves AceGUI at CreateOptionsPanel and hands the host a copy through
    -- onAceGUI, so the two agree in a live client -- but only the instance's is
    -- set when a page is rendered directly, which is how every suite drives one.
    local AceGUI = Helpers.AceGUI or NS.AceGUI
    local scroll = Helpers.EnsureScroll and Helpers.EnsureScroll(ctx)
    if not (AceGUI and scroll) then return nil end

    local w = AceGUI:Create("InteractiveLabel")
    w:SetFullWidth(true)
    w:SetText(text or "")
    -- NO SetHighlight, deliberately. AceGUI's InteractiveLabel forwards it to
    -- Texture:SetTexture, and the four-number form is the deprecated colour API:
    -- the client answered `(1, 1, 1, 0.12)` with a solid BRIGHT GREEN block over
    -- the whole line on mouseover. The colour on the link phrase is what marks the
    -- line as clickable; a hover highlight is not needed to say so, and there is
    -- no correct number to pass here -- a texture path would be, and this line
    -- wants no plate behind it either.
    w:SetCallback("OnClick", function()
        if not onClick then return end
        -- pcall'd for the reason every host callback on these pages is: this body
        -- reaches into live addon state and Blizzard's category switch, and a
        -- raise inside AceGUI's dispatch takes the click handling of every widget
        -- on the frame with it.
        local ok, err = pcall(onClick)
        if not ok and NS.Util then
            NS.Util.print("link failed: " .. tostring(err))
        end
    end)
    if tooltip then Helpers.AttachTooltip(w, nil, tooltip) end
    scroll:AddChild(w)
    return w
end

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
--- Refuse and say so, or answer false. Its own function because each guard in
--- the ladder counts as a decision and the two halves together measured past the
--- release gate's complexity cap (performance-§10).
---
--- The wording is this addon's localized line rather than the library's shared
--- English one, matching `/kcd config`'s refusal -- one act, one sentence,
--- whichever door it came through.
local function refusedInCombat()
    if not (InCombatLockdown and InCombatLockdown()) then return false end
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
