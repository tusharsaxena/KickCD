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
