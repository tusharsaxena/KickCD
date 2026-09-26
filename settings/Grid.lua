-- settings/Grid.lua
--
-- The Grid page (KickCD#33): Icons, Cast bar and Text Label as one page. The
-- Unit picker is the band across the top, the nav rail on the left chooses the
-- entry, and each entry keeps the tab strip its own page had. An entry IS the
-- old page key, so every row, `/kcd` path, default and profile is unchanged.
-- The registry, the renderer and the rail are settings/Panel_Render.lua's
-- (Helpers.RegisterGridSection, Helpers.RenderGridPage); the rows are declared
-- where they always were, in settings/Icons.lua, Castbar.lua and Label.lua.
--
-- The library owns WHEN this draws (H.SetRenderer): first show, and again when a
-- refresh marked it dirty while it was hidden -- which is what makes the Unit
-- band, the General page's Focus link and a deep link reach this page at all.

local _, NS = ...
local L = NS.L
local H = NS.Settings.Helpers

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx = H.CreatePanel("KickCDGridPanel", L["Grid"], {
        pageKey        = "grid",
        defaultsButton = true,
    })
    -- Parked, not wired: the button is built at the panel's first OnShow and
    -- captures this handler then, so it reads the entry at CLICK time rather than
    -- fixing the one on screen when the page was built.
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults(ctx.activeSection, ctx)
    end

    H.__bindGridPage(ctx)
    H.SetRenderer(ctx, H.RenderGridPage)

    return Settings.RegisterCanvasLayoutSubcategory(
        mainCategory, ctx.panel, L["Grid"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("grid", L["Grid"], Build)
end
