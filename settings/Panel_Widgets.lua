-- settings/Panel_Widgets.lua
--
-- Widget-maker primitives for the settings panel, peeled out of
-- settings/Panel.lua (KCD-24, §1.2) so each file stays under the LOC cap.
-- Each maker binds an AceGUI widget directly to db.profile via
-- Helpers.Get/Set, registers a refresher closure (so the widget re-syncs
-- after a Defaults reset or a /kcd set), and adds itself to the panel's
-- AceGUI ScrollFrame container. Loads AFTER settings/Panel.lua (which
-- publishes the shared framework helpers rebound below) and BEFORE the
-- per-tab files (General / Icons / …) that call these makers.

local addonName, NS = ...
local AceGUI  = LibStub("AceGUI-3.0")
local Helpers = NS.Settings.Helpers

-- Framework helpers published by settings/Panel.lua, rebound to
-- file-locals so the moved code below reads exactly as it did in place.
local ensureScroll  = Helpers.EnsureScroll
local addSpacer     = Helpers.AddSpacer
local attachTooltip = Helpers.AttachTooltip
local fireOnChange  = Helpers.FireOnChange
local ROW_VSPACER   = Helpers.ROW_VSPACER

-- Each button in an InlineButtonPair reserves a hair under half the row so
-- AceGUI Flow's ~2px right-cell spill can't push the right button past the
-- ScrollFrame clip rect (which would shave its right border). The dropdowns
-- above escape this naturally because their control sits inset from the
-- cell edge; a cell-filling Button does not, so we inset it here. Tuned so
-- the right button clears the clip by a few px without wasting column width.
local BUTTON_PAIR_REL = 0.492

-- ---------------------------------------------------------------------
-- Widget creators — each binds directly to db.profile via
-- Helpers.Get/Set, registers a refresher closure so the widget can
-- re-sync after a Defaults reset or a /kcd set, and adds itself to
-- the panel's AceGUI ScrollFrame container.
-- ---------------------------------------------------------------------

-- Width helper used by every maker. When relativeWidth is given (RenderSchema's
-- two-column layout passes 0.5), the widget claims half the parent's width and
-- sits next to its sibling in a Flow-laid SimpleGroup row. Otherwise it spans
-- the full parent — used by tabs that render directly to ctx.scroll.
local function applyWidth(widget, relativeWidth)
    if relativeWidth then
        widget:SetRelativeWidth(relativeWidth)
    else
        widget:SetFullWidth(true)
    end
end

local function makeCheckbox(ctx, def, parent, relativeWidth)
    parent = parent or ensureScroll(ctx)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(def.label or def.path)
    applyWidth(cb, relativeWidth)
    cb:SetValue(Helpers.Get(def.path) and true or false)

    local function refresh()
        cb:SetValue(Helpers.Get(def.path) and true or false)
    end

    cb:SetCallback("OnValueChanged", function(_, _, value)
        local v = value and true or false
        Helpers.Set(def.path, def.section, v)
        fireOnChange(def, v)
    end)

    attachTooltip(cb, def.label, def.tooltip)
    parent:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
end

-- The slider's editbox is left to AceGUI's default formatter (integer step
-- → integer text, float step → 2-decimal text). Unit hints (px, ×) belong
-- in def.label, not appended to the value. def.fmt is still consulted by
-- the /kcd get|list slash output where text-only context benefits from a
-- "48 px" / "1.50x" rendering.
local function snapToStep(value, mn, step)
    if not (step and step > 0) then return value end
    return math.floor((value - mn) / step + 0.5) * step + mn
end

local function makeSlider(ctx, def, parent, relativeWidth)
    parent = parent or ensureScroll(ctx)
    local s = AceGUI:Create("Slider")
    s:SetLabel(def.label or def.path)
    s:SetSliderValues(def.min or 0, def.max or 1, def.step or 1)
    s:SetIsPercent(false)
    applyWidth(s, relativeWidth)

    local function refresh()
        local v = Helpers.Get(def.path)
        if type(v) ~= "number" then v = def.default or def.min or 0 end
        s:SetValue(v)
    end

    s:SetCallback("OnMouseUp", function(_, _, value)
        local snapped = snapToStep(value, def.min or 0, def.step or 0)
        Helpers.Set(def.path, def.section, snapped)
        fireOnChange(def, snapped)
    end)

    attachTooltip(s, def.label, def.tooltip)
    parent:AddChild(s)
    refresh()
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return s
end

-- Map a schema row's `lsm` value (the LibSharedMedia media type) to the
-- AceGUI widget type registered by libs/AceGUI-3.0-SharedMediaWidgets.
-- nil for any row that isn't an LSM dropdown — those use the stock
-- AceGUI Dropdown widget below.
local LSM_WIDGET = {
    statusbar = "LSM30_Statusbar",
    border    = "LSM30_Border",
    font      = "LSM30_Font",
}

local function makeDropdown(ctx, def, parent, relativeWidth)
    parent = parent or ensureScroll(ctx)
    -- LSM dropdowns get the in-tree LSM30_* widget so each row renders
    -- with a swatch / font preview. Everything else uses the stock
    -- AceGUI Dropdown — the two share enough of an interface
    -- (SetLabel/SetList/SetValue/OnValueChanged) that the rest of this
    -- function is unchanged either way.
    local widgetType = def.lsm and LSM_WIDGET[def.lsm] or "Dropdown"
    local dd = AceGUI:Create(widgetType)
    dd:SetLabel(def.label or def.path)
    applyWidth(dd, relativeWidth)

    local function valuesList()
        if type(def.values) == "function" then return def.values() or {} end
        return def.values or {}
    end

    local function applyList()
        local items, order = {}, {}
        for i, item in ipairs(valuesList()) do
            items[item.value] = item.label or tostring(item.value)
            order[i] = item.value
        end
        dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(Helpers.Get(def.path))

    local function refresh()
        applyList()                            -- LSM lists may grow over time
        dd:SetValue(Helpers.Get(def.path))
    end

    dd:SetCallback("OnValueChanged", function(_, _, value)
        Helpers.Set(def.path, def.section, value)
        fireOnChange(def, value)
        -- Upstream AceGUI-3.0-SharedMediaWidgets fire OnValueChanged
        -- from their ContentOnClick WITHOUT first calling SetValue —
        -- they assume the caller is AceConfigDialog and that its
        -- post-set `AceConfigDialog:Open(...)` will re-render the
        -- panel with a fresh widget showing the new value. KickCD's
        -- canvas-layout panel doesn't re-render on value change, so
        -- without an explicit push the LSM widget's `self.value` and
        -- displayed text stay stale (the underlying db.profile write
        -- in Helpers.Set above DID land — only the UI looks like a
        -- no-op). Standard AceGUI Dropdown already SetValue'd in its
        -- own click handler before firing, so this assignment is
        -- idempotent for the non-LSM path.
        dd:SetValue(value)
    end)

    attachTooltip(dd, def.label, def.tooltip)
    parent:AddChild(dd)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return dd
end

-- Free-text string widget — used by schema rows with type="string" and no
-- `values` list (e.g. a unit's label.text). Unlike the sliders/checkboxes
-- above, which commit on every drag/click, this commits on Enter/focus-
-- loss (AceGUI EditBox's OnEnterPressed) so a half-typed label never
-- writes a partial string to db.profile.
local function makeEditBox(ctx, def, parent, relativeWidth)
    parent = parent or ensureScroll(ctx)
    local eb = AceGUI:Create("EditBox")
    eb:SetLabel(def.label or def.path)
    applyWidth(eb, relativeWidth)
    eb:SetText(Helpers.Get(def.path) or "")

    local function refresh()
        eb:SetText(Helpers.Get(def.path) or "")
    end

    eb:SetCallback("OnEnterPressed", function(_, _, text)
        Helpers.Set(def.path, def.section, text)
        fireOnChange(def, text)
    end)

    attachTooltip(eb, def.label, def.tooltip)
    parent:AddChild(eb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return eb
end

local function makeColorPicker(ctx, def, parent, relativeWidth)
    parent = parent or ensureScroll(ctx)
    local cp = AceGUI:Create("ColorPicker")
    cp:SetLabel(def.label or def.path)
    cp:SetHasAlpha(true)
    applyWidth(cp, relativeWidth)

    local function readColor()
        local c = Helpers.Get(def.path)
        if type(c) ~= "table" then c = { 1, 1, 1, 1 } end
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end

    cp:SetColor(readColor())

    local function refresh()
        cp:SetColor(readColor())
    end

    -- AceGUI's ColorPicker only fires `OnValueConfirmed` via the alpha
    -- callback path, which in modern WoW (SetupColorPickerAndShow API)
    -- means it fires on **Cancel** (where cancelFunc invokes the alpha
    -- branch with the original color) but NOT on **OK** (where the
    -- picker just hides without an extra callback). So we'd be missing
    -- every confirmed write if we listened to OnValueConfirmed alone.
    --
    -- Listen to both:
    --   * OnValueChanged fires during drag while the picker is visible.
    --     Treat it as the primary write — gives a live preview AND
    --     persists the value before the user even clicks OK. Wrapped
    --     in Util.Throttle(50ms) so a sustained drag fires
    --     Ka0s_KickCD_CONFIG_CHANGED at most ~20 times/sec (the live
    --     module re-skins on each fire; the throttle keeps the UI
    --     responsive on lower-end systems without losing the snap of
    --     a live preview).
    --   * OnValueConfirmed fires (only) when the user cancels, with
    --     the ORIGINAL color. We commit it IMMEDIATELY — the user
    --     expects the bar to snap back to the pre-drag color, not
    --     to wait out a throttle window first.
    local function commit(r, g, b, a)
        Helpers.Set(def.path, def.section, { r, g, b, a or 1 })
        fireOnChange(def, { r, g, b, a or 1 })
    end
    local throttledCommit = (NS.Util and NS.Util.Throttle)
        and NS.Util.Throttle(50, commit)
        or  commit
    cp:SetCallback("OnValueChanged",   function(_, _, r, g, b, a) throttledCommit(r, g, b, a) end)
    cp:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a) commit(r, g, b, a) end)

    attachTooltip(cp, def.label, def.tooltip)
    parent:AddChild(cp)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cp
end

-- Generic field renderer — dispatches by def.type.
function Helpers.RenderField(ctx, def, parent, relativeWidth)
    if def.type == "bool"   then return makeCheckbox(ctx, def, parent, relativeWidth)    end
    if def.type == "number" then return makeSlider(ctx, def, parent, relativeWidth)      end
    if def.type == "string" then
        -- Free-text rows (no `values` list, e.g. a unit's label.text) get
        -- an EditBox; every other string row is a fixed-choice Dropdown.
        if def.values then return makeDropdown(ctx, def, parent, relativeWidth) end
        return makeEditBox(ctx, def, parent, relativeWidth)
    end
    if def.type == "color"  then return makeColorPicker(ctx, def, parent, relativeWidth) end
end

-- Standalone SESSION-ONLY checkbox — deliberately NOT a schema row, so it
-- writes nothing to db.profile / SavedVariables. For controls that must never
-- persist across sessions, e.g. the debug console toggle (§12.5). `spec.get`
-- seeds the initial checked state; `spec.set(bool)` runs on toggle. Rendered at
-- half width so it lines up with the schema's paired bool rows above it.
function Helpers.SessionToggle(ctx, spec, parent, relativeWidth)
    -- `parent` given (e.g. an InlinePair row) → render inline in that row;
    -- otherwise render in a half-width slot of a fresh full-width row.
    local ownRow = not parent
    local target = parent
    if ownRow then
        target = AceGUI:Create("SimpleGroup")
        target:SetLayout("Flow")
        target:SetFullWidth(true)
    end

    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(spec.label or "")
    applyWidth(cb, relativeWidth or 0.5)
    local function readVal() return spec.get and spec.get() and true or false end
    cb:SetValue(readVal())
    cb:SetCallback("OnValueChanged", function(_, _, value)
        if not spec.set then return end
        local ok, err = pcall(spec.set, value and true or false)
        if not ok and NS.Util then
            NS.Util.print("session toggle '" .. tostring(spec.label) .. "' failed: " .. tostring(err))
        end
    end)
    attachTooltip(cb, spec.label, spec.tooltip)
    target:AddChild(cb)
    if ownRow then ensureScroll(ctx):AddChild(target) end
    -- Re-read on panel refresh (e.g. Defaults) so the checkbox tracks state
    -- changed via other paths (the window's own close button, `/kcd debug`).
    ctx.refreshers[#ctx.refreshers + 1] = function() cb:SetValue(readVal()) end
    return cb
end

-- Render two half-width widgets side by side in one Flow row. Each render fn
-- receives (ctx, row) and must add exactly one 0.5-width widget to `row`.
-- Generalises the schema's auto-pairing for rows where one half is a bespoke
-- (non-schema) widget — e.g. Lock frame (a schema bool) beside the
-- session-only Debug console toggle.
function Helpers.InlinePair(ctx, leftRender, rightRender)
    local scroll = ensureScroll(ctx)
    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    if leftRender  then leftRender(ctx, row)  end
    if rightRender then rightRender(ctx, row) end
    scroll:AddChild(row)
    addSpacer(scroll, ROW_VSPACER)
    return row
end

-- Two side-by-side action buttons sharing one Flow row at 50% / 50%
-- width. Each spec is { text = ..., tooltip = ..., onClick = function }.
-- Used by the General tab's afterGroup callback so "Reset position" and
-- "Reset all settings" sit on a single row aligned with the schema's
-- two-column grid above them.
function Helpers.InlineButtonPair(ctx, leftSpec, rightSpec)
    local scroll = ensureScroll(ctx)

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local function makeBtn(spec)
        if not spec then return end
        local btn = AceGUI:Create("Button")
        btn:SetText(spec.text or "")
        btn:SetRelativeWidth(BUTTON_PAIR_REL)
        btn:SetCallback("OnClick", function()
            if not spec.onClick then return end
            local ok, err = pcall(spec.onClick)
            if not ok and NS.Util then
                NS.Util.print("button onClick failed: " .. tostring(err))
            end
        end)
        attachTooltip(btn, spec.text, spec.tooltip)
        row:AddChild(btn)
    end

    makeBtn(leftSpec)
    makeBtn(rightSpec)
    scroll:AddChild(row)
end

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- Slider step snapping is pure arithmetic that decides what value the user's
-- drag actually writes to the DB, so it is worth pinning headlessly (same
-- idiom as Castbar.AutoSizeLong).
Helpers.SnapToStep = snapToStep
