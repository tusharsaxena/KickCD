-- settings/Grid.lua
--
-- The Units page (KickCD#33; labeled "Grid" until item 020's KIC-L06): Icons,
-- Cast bar and Text label as one page. The page KEY is still `grid` -- the panel
-- stamps and Helpers.__panelFor("grid") are unchanged; only the
-- label moved, because the page edits one unit's grid, cast bar and label. The
-- Unit picker and the unit's own acts (Enable this unit, and for Focus Link to
-- Target and Copy from Target) are the band across the top, the nav rail on the
-- left chooses the entry, and each entry keeps the tab strip its own page had.
-- An entry IS the old page key, so every row, `/kcd` path, default and profile
-- is unchanged.
-- The registry, the renderer and the rail are settings/Panel_Render.lua's
-- (Helpers.RegisterGridSection, Helpers.RenderGridPage); the rows are declared
-- where they always were, in settings/Icons.lua, Castbar.lua and Label.lua.
--
-- The library owns WHEN this draws (H.SetRenderer): first show, and again when a
-- refresh marked it dirty while it was hidden -- which is what makes the Unit
-- band and the General page's Focus link reach this page at all.

local _, NS = ...
local L = NS.L
local H = NS.Settings.Helpers

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx = H.CreatePanel("KickCDGridPanel", L["Units"], {
        pageKey         = "grid",
        defaultsButton  = true,
        -- The blast radius is the whole rail ENTRY, not the tab on screen
        -- (options-ui-§13; the ratified deviation in docs/ARCHITECTURE.md). The
        -- last sentence is this page's half of the WS-33 disclosure: the band's
        -- rows keep their General stamp (settings/General.lua), so this button
        -- does not reset them and the General page's does.
        defaultsTooltip = L["Restore every tab of the entry selected on the left, for the unit in the band, to its defaults. The other unit keeps its own. The band's Enable this unit and Link to Target are reset by the General page's Defaults."],
    })
    -- Parked, not wired: the button is built at the panel's first OnShow and
    -- captures this handler then, so it reads the entry at CLICK time. It restores
    -- the entry's rows for the unit in the band only (Helpers.RestoreGridSection).
    ctx.panel.defaultsOnClick = function()
        H.RestoreGridSection(ctx)
    end

    H.__bindGridPage(ctx)
    H.SetRenderer(ctx, H.RenderGridPage)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Units"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("grid", L["Units"], Build)
end
