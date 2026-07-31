-- settings/Panel_Widgets.lua
--
-- What is left of this file after LibKa0s-Options-1.0 took the widget layer.
--
-- GONE, because libs/LibKa0s/OptionsWidgets.lua provides them: the five widget
-- makers (checkbox, slider, dropdown, edit box, colour picker), RenderField's
-- type dispatch, the tooltip attacher, the spacer, the section heading and
-- InlineButtonPair. They were ~300 lines and one of several near-identical
-- copies across the collection — the drift anti-patterns #47 describes.
--
-- WHAT STAYS, and why each could not generalise:
--
--   * InlinePair — two half-width widgets in one Flow row where each half is
--     supplied by a caller-provided render function. The library's flow engine
--     pairs SCHEMA rows automatically and offers `pairWith` for attaching one
--     bespoke widget to a named path's row, but neither shape covers "two
--     arbitrary renderers, one row" — which is what the General page's
--     Lock-frame / Debug-console line is.
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
local AceGUI  = LibStub("AceGUI-3.0")

--- Two half-width widgets side by side in one Flow row. Each render fn receives
--- (ctx, row) and must add exactly one 0.5-width widget to `row`.
---
--- Generalises the schema's auto-pairing for rows where one half is a bespoke
--- (non-schema) widget — the General page's "Lock frame" (a schema bool) beside
--- the session-only "Debug console" toggle.
function Helpers.InlinePair(ctx, leftRender, rightRender)
    local scroll = Helpers.EnsureScroll(ctx)
    if not scroll then return end
    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    if leftRender  then leftRender(ctx, row)  end
    if rightRender then rightRender(ctx, row) end
    scroll:AddChild(row)
    -- ROW_VSPACER read off the instance rather than restated: a host copy of a
    -- library layout constant is the copy that goes stale (options-ui-§8).
    Helpers.AddSpacer(scroll, Helpers.ROW_VSPACER)
    return row
end

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
