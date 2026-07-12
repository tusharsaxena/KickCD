-- settings/Panel.lua
--
-- NOTE (KCD-19, §1.2): this file is in the 1000–1500 LOC "on notice" band.
-- It is under the 1500 hard cap; a future peel would split the canvas/layout
-- framework from the widget-primitive helpers (RenderSchema and friends).
--
-- Settings UI framework. Every tab — General, Icons, Spells, Profiles —
-- is registered as a canvas-layout subcategory and shares one header
-- design: title (left) + Defaults button (right) + divider, all built
-- by Helpers.CreatePanel. Below the header each tab lays out its own
-- body.
--
-- General and Icons are driven entirely from a declarative schema
-- (KickCD.Settings.Schema). Schema rows render as AceGUI widgets
-- (CheckBox / Slider / Dropdown / ColorPicker / Heading) inside an
-- AceGUI ScrollFrame parented to ctx.body, so the visual style matches
-- the AceGUI-driven Spells / Profiles tabs and other AceGUI-using
-- addons (e.g. Consumable Master).
--
-- The same schema feeds /kcd list|get|set (see core/KickCD.lua), so
-- adding a new option = one row that auto-wires UI and CLI.

local addonName, NS = ...
local L      = NS.L
local AceGUI = LibStub("AceGUI-3.0")

NS.Settings = NS.Settings or {}
NS.Settings.main      = nil
NS.Settings.sub       = {}
NS.Settings.builders  = {}
NS.Settings.order     = { "general", "icons", "castbar", "spells", "profiles" }
NS.Settings.Schema    = NS.Settings.Schema or {}
NS.Settings._panels   = NS.Settings._panels or {}

local Helpers = {}
NS.Settings.Helpers = Helpers

-- ---------------------------------------------------------------------
-- db.profile path helpers
-- ---------------------------------------------------------------------

local function Resolve(path)
    if not (NS.db and NS.db.profile) then return nil, nil end
    local segments = {}
    for part in string.gmatch(path, "[^.]+") do
        segments[#segments + 1] = part
    end
    if #segments == 0 then return nil, nil end
    local parent = NS.db.profile
    for i = 1, #segments - 1 do
        parent = parent[segments[i]]
        if type(parent) ~= "table" then return nil, nil end
    end
    return parent, segments[#segments]
end
Helpers.Resolve = Resolve

function Helpers.Get(path)
    local parent, key = Resolve(path)
    if not parent then return nil end
    return parent[key]
end

function Helpers.FireConfigChanged(section)
    if NS and NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = section })
    end
end

function Helpers.Set(path, section, value)
    local parent, key = Resolve(path)
    if not parent then return end
    parent[key] = value
    Helpers.FireConfigChanged(section)
end

-- ---------------------------------------------------------------------
-- Schema query helpers
-- ---------------------------------------------------------------------

function Helpers.SchemaForPanel(panelKey)
    local out = {}
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == panelKey then out[#out + 1] = def end
    end
    return out
end

function Helpers.FindSchema(path)
    for _, def in ipairs(NS.Settings.Schema) do
        if def.path == path then return def end
    end
end

-- ---------------------------------------------------------------------
-- Schema-shape validation
-- ---------------------------------------------------------------------
--
-- Run once at panel-registration time after every settings/* file has
-- finished loading. Catches misspelled `panel` / `section` / `type`
-- enum values, missing `path`, and other schema-row typos that today
-- silently fail to render or fail to wire into the slash command.
--
-- The validator only PRINTS errors — it never refuses to load. A
-- broken row is an addon-author bug; the right user-visible behaviour
-- is "the option you wanted is missing AND a chat error tells you
-- why," not "the entire settings panel refuses to register."

local _validPanels = {
    general = true, icons = true, castbar = true,
    spells  = true, profiles = true,
}
local _validSections = {
    general = true, icons = true, castbar = true,
    spells  = true, debug = true,
}
local _validTypes = {
    bool = true, number = true, string = true, color = true,
}

local function _printSchemaError(prefix, msg)
    local out = NS.Util and NS.Util.print
    if out then
        out("|cffff0000schema error|r: " .. prefix .. ": " .. msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            (NS.PREFIX or "|cff00ffff[KCD]|r") .. " |cffff0000schema error|r: " .. prefix .. ": " .. msg)
    end
end

--- Walk the assembled schema and surface any malformed row. Called from
--- RegisterPanel after all settings/* files have loaded their rows.
--- Returns the count of errors found (always called for side effects;
--- the count is exposed for the test harness / future debug surface).
function Helpers.ValidateSchema()
    local errors = 0
    for i, def in ipairs(NS.Settings.Schema or {}) do
        local where = "row #" .. i .. " (" .. tostring(def.path or "<no path>") .. ")"
        if type(def) ~= "table" then
            _printSchemaError(where, "row is not a table")
            errors = errors + 1
        else
            if type(def.path) ~= "string" or def.path == "" then
                _printSchemaError(where, "missing or empty `path`")
                errors = errors + 1
            end
            if not _validPanels[def.panel] then
                _printSchemaError(where, "invalid `panel` = " .. tostring(def.panel)
                    .. " (expected one of: general, icons, castbar, spells, profiles)")
                errors = errors + 1
            end
            if not _validSections[def.section] then
                _printSchemaError(where, "invalid `section` = " .. tostring(def.section)
                    .. " (expected one of: general, icons, castbar, spells, debug)")
                errors = errors + 1
            end
            if not _validTypes[def.type] then
                _printSchemaError(where, "invalid `type` = " .. tostring(def.type)
                    .. " (expected one of: bool, number, string, color)")
                errors = errors + 1
            end
        end
    end
    return errors
end

--- The canonical 13-option dropdown list shared by every "frame
--- anchor" dropdown in the addon (Icons → Layout → Anchor point and
--- Cast bar → Position → Anchor on primary icon / cast bar). Returns
--- a fresh table on every call so consumers can mutate without
--- aliasing.
---
--- Value tokens follow a `<SIDE>_<ALIGN>` pattern: SIDE is the edge
--- the anchor lives on (TOP/BOTTOM/LEFT/RIGHT), ALIGN is the
--- perpendicular-axis position on that edge. The 13th option, plain
--- `CENTER`, names the whole-frame center.
---
--- Labels say "middle" rather than "center" for the perpendicular
--- alignment, matching the user's preferred naming.
function Helpers.AnchorValues()
    return {
        { value = "TOP_LEFT",      label = L["Top left"]      },
        { value = "TOP_MIDDLE",    label = L["Top middle"]    },
        { value = "TOP_RIGHT",     label = L["Top right"]     },
        { value = "BOTTOM_LEFT",   label = L["Bottom left"]   },
        { value = "BOTTOM_MIDDLE", label = L["Bottom middle"] },
        { value = "BOTTOM_RIGHT",  label = L["Bottom right"]  },
        { value = "LEFT_TOP",      label = L["Left top"]      },
        { value = "LEFT_MIDDLE",   label = L["Left middle"]   },
        { value = "LEFT_BOTTOM",   label = L["Left bottom"]   },
        { value = "RIGHT_TOP",     label = L["Right top"]     },
        { value = "RIGHT_MIDDLE",  label = L["Right middle"]  },
        { value = "RIGHT_BOTTOM",  label = L["Right bottom"]  },
        { value = "CENTER",        label = L["Center"]        },
    }
end

--- Build the option list for a LibSharedMedia media type.
function Helpers.LSMValues(mediaType)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM or not LSM.List then
        return { { value = "Default", label = "Default" } }
    end
    local list = LSM:List(mediaType) or {}
    local out = {}
    for i, key in ipairs(list) do
        out[i] = { value = key, label = key }
    end
    if #out == 0 then
        out[1] = { value = "Default", label = "Default" }
    end
    return out
end

-- ---------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------
--
-- Sourced from KickCD.Const so the values live in exactly one place
-- across the addon — see core/Constants.lua for the rationale on each.

local PADDING_X     = NS.Const.PANEL_PADDING_X
local HEADER_TOP    = NS.Const.PANEL_HEADER_TOP
local HEADER_HEIGHT = NS.Const.PANEL_HEADER_HEIGHT
local DEFAULTS_W    = NS.Const.PANEL_DEFAULTS_W

-- Each button in an InlineButtonPair reserves a hair under half the row so
-- AceGUI Flow's ~2px right-cell spill can't push the right button past the
-- ScrollFrame clip rect (which would shave its right border). The dropdowns
-- above escape this naturally because their control sits inset from the
-- cell edge; a cell-filling Button does not, so we inset it here. Tuned so
-- the right button clears the clip by a few px without wasting column width.
local BUTTON_PAIR_REL = 0.492

-- ---------------------------------------------------------------------
-- Tooltip helper — works on AceGUI widgets (via SetCallback) and plain
-- Blizzard frames (via HookScript). Anchors on widget.frame when the
-- target is an AceGUI widget.
-- ---------------------------------------------------------------------

local function attachTooltip(widget, label, tooltip)
    if not widget then return end
    local anchor = widget.frame or widget
    if not anchor then return end

    local function show()
        if not GameTooltip then return end
        GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
        if label and label ~= "" then
            GameTooltip:SetText(label, 1, 1, 1)
        end
        if tooltip and tooltip ~= "" then
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end
    local function hide() if GameTooltip then GameTooltip:Hide() end end

    if widget.SetCallback then
        widget:SetCallback("OnEnter", show)
        widget:SetCallback("OnLeave", hide)
    elseif widget.HookScript then
        widget:HookScript("OnEnter", show)
        widget:HookScript("OnLeave", hide)
    end
end
Helpers.AttachTooltip = attachTooltip

-- ---------------------------------------------------------------------
-- Header (title + Defaults button + divider)
-- ---------------------------------------------------------------------

local function buildHeader(panel, title, opts)
    -- Sub-pages render with an "Ka0s KickCD ▸ <Page>" breadcrumb. The
    -- separator is an inline texture (not a glyph) so it renders the
    -- same regardless of the active FontString font / locale fallback.
    -- The parent/main page opts in to the unprefixed form via
    -- opts.isMain (otherwise it would read "Ka0s KickCD ▸ Ka0s KickCD").
    -- The Blizzard left-tree label is driven by panel.name in
    -- CreatePanel and stays unprefixed so the tree indents under the
    -- parent without visual repetition.
    local displayTitle = title
    if not opts.isMain then
        local sep = " |A:common-icon-forwardarrow:16:16|a "
        displayTitle = L["Ka0s KickCD"] .. sep .. title
    end

    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING_X, -HEADER_TOP)
    titleFS:SetText(displayTitle)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",   PADDING_X, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING_X, -HEADER_HEIGHT)
    -- Tint to match the title's font color (Blizzard's NORMAL_FONT_COLOR
    -- yellow on GameFontNormalHuge). Reading from the title rather than
    -- hardcoding the gold tracks any future theme retune.
    divider:SetVertexColor(titleFS:GetTextColor())

    local defaultsBtn
    if opts.defaultsButton then
        defaultsBtn = AceGUI:Create("Button")
        defaultsBtn:SetText(L["Defaults"])
        defaultsBtn:SetWidth(DEFAULTS_W)
        defaultsBtn.frame:SetParent(panel)
        defaultsBtn.frame:ClearAllPoints()
        defaultsBtn.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                                   -PADDING_X, -HEADER_TOP)
        defaultsBtn.frame:Show()
        attachTooltip(defaultsBtn, L["Defaults"], opts.defaultsTooltip)
    end

    return titleFS, divider, defaultsBtn
end

-- ---------------------------------------------------------------------
-- CreatePanel — Frame compatible with RegisterCanvasLayoutSubcategory
-- with the unified header stamped on top. Returns a `ctx` table the
-- caller threads through Section / RenderField / RenderSchema /
-- Button / RestoreDefaults.
-- ---------------------------------------------------------------------

function Helpers.CreatePanel(name, title, opts)
    opts = opts or {}

    local panel = CreateFrame("Frame", name)
    panel.name = title
    panel:Hide()

    local titleFS, divider, defaultsBtn = buildHeader(panel, title, opts)
    panel.title       = titleFS
    panel.divider     = divider
    panel.defaultsBtn = defaultsBtn

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -(HEADER_HEIGHT + 8))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.body = body

    local ctx = {
        panel       = panel,
        body        = body,
        scroll      = nil,           -- lazy AceGUI ScrollFrame
        refreshers  = {},
        lastGroup   = nil,
        panelKey    = opts.panelKey,
    }
    NS.Settings._panels[#NS.Settings._panels + 1] = ctx
    return ctx
end

-- ---------------------------------------------------------------------
-- Always-visible scrollbar patch
-- ---------------------------------------------------------------------
--
-- AceGUI's stock ScrollFrame.FixScroll auto-hides the scrollbar when
-- content fits inside the viewport. Across our settings tabs that
-- means General (short) shows no scrollbar while Icons / Cast bar
-- (long) do — visually asymmetric.
--
-- This helper rebinds FixScroll on a single ScrollFrame instance to
-- always keep the scrollbar (and its 20 px right-side gutter) shown,
-- and parks the thumb at the top when there's nothing to scroll. The
-- gutter persists either way so the body content's right edge sits at
-- the same x across every panel.
--
-- We restore the stock FixScroll + OnRelease on widget release so the
-- AceGUI pool returns to a clean state — AceGUI's pool is shared
-- across addons, and we don't want our patch leaking into another
-- addon's ScrollFrame after it picks up the same recycled instance.
function Helpers.PatchAlwaysShowScrollbar(scroll)
    if not scroll or scroll._kcdAlwaysScrollbar then return end
    scroll._kcdAlwaysScrollbar = true

    local origFixScroll  = scroll.FixScroll
    local origMoveScroll = scroll.MoveScroll
    local origOnRelease  = scroll.OnRelease

    -- Look up the UIPanelScrollBarTemplate's optional up/down arrow
    -- buttons by name. Newer scrollbar variants strip these; in that
    -- case we simply skip the button-side toggle. Cached once because
    -- the names are stable for the widget's lifetime.
    local scrollbar  = scroll.scrollbar
    local thumb      = scrollbar and scrollbar.GetThumbTexture and scrollbar:GetThumbTexture() or nil
    local sbName     = scrollbar and scrollbar.GetName and scrollbar:GetName() or nil
    local upBtn      = sbName and _G[sbName .. "ScrollUpButton"]   or nil
    local downBtn    = sbName and _G[sbName .. "ScrollDownButton"] or nil

    -- Tri-state: nil = "not yet applied" (forces the first transition
    -- to actually run regardless of which way it goes). After that,
    -- `true` / `false` short-circuit redundant calls every OnUpdate
    -- tick, since FixScroll runs on every paint.
    local currentEnabled

    local function setEnabled(want)
        if currentEnabled == want then return end
        currentEnabled = want
        if not scrollbar then return end

        if want then
            if scrollbar.Enable then scrollbar:Enable() end
            if thumb and thumb.SetVertexColor then
                thumb:SetVertexColor(1, 1, 1, 1)
            end
            if upBtn   and upBtn.Enable   then upBtn:Enable()   end
            if downBtn and downBtn.Enable then downBtn:Enable() end
        else
            -- Park the value at 0 first so the thumb sits at the top
            -- before we lock interaction down. Disabling the slider
            -- first and *then* parking would skip OnValueChanged.
            scrollbar:SetValue(0)
            if scrollbar.Disable then scrollbar:Disable() end
            if thumb and thumb.SetVertexColor then
                thumb:SetVertexColor(0.5, 0.5, 0.5, 0.6)
            end
            if upBtn   and upBtn.Disable   then upBtn:Disable()   end
            if downBtn and downBtn.Disable then downBtn:Disable() end
        end
    end

    -- Initial setup: reserve the gutter and reveal the scrollbar.
    -- Mirrors the "scrollbar visible" branch of stock FixScroll so we
    -- don't have to wait for the first OnUpdate tick to take effect.
    scroll.scrollBarShown = true
    if scrollbar then scrollbar:Show() end
    if scroll.scrollframe then
        scroll.scrollframe:SetPoint("BOTTOMRIGHT", -20, 0)
    end
    if scroll.content and scroll.content.original_width then
        scroll.content.width = scroll.content.original_width - 20
    end

    -- Rebound FixScroll: the upstream "viewheight < height + 2 →
    -- hide scrollbar" branch is replaced by "park thumb at top,
    -- disable interaction, leave scrollbar visible." The overflow
    -- branch is kept verbatim so actual scrolling still works on long
    -- panels.
    scroll.FixScroll = function(self)
        if self.updateLock then return end
        self.updateLock = true

        -- Defensive re-show in case Blizzard or AceGUI layout has
        -- stomped our anchor / content width since the last tick.
        if not self.scrollBarShown then
            self.scrollBarShown = true
            self.scrollbar:Show()
            self.scrollframe:SetPoint("BOTTOMRIGHT", -20, 0)
            if self.content.original_width then
                self.content.width = self.content.original_width - 20
            end
        end

        local status = self.status or self.localstatus
        local height, viewheight =
            self.scrollframe:GetHeight(), self.content:GetHeight()
        local offset = status.offset or 0

        if viewheight < height + 2 then
            -- Content fits: park the thumb at the top and grey the
            -- scrollbar out so the user reads it as inert.
            setEnabled(false)
            self.scrollbar:SetValue(0)
            self.scrollframe:SetVerticalScroll(0)
            status.offset = 0
        else
            setEnabled(true)
            local value = (offset / (viewheight - height) * 1000)
            if value > 1000 then value = 1000 end
            self.scrollbar:SetValue(value)
            self:SetScroll(value)
            if value < 1000 then
                self.content:ClearAllPoints()
                self.content:SetPoint("TOPLEFT",  0, offset)
                self.content:SetPoint("TOPRIGHT", 0, offset)
                status.offset = offset
            end
        end

        self.updateLock = nil
    end

    -- MoveScroll is the mousewheel entrypoint. Stock implementation
    -- writes through to scrollbar:SetValue, which would shift the
    -- thumb visually even though SetScroll's offset guard keeps the
    -- content stationary. Short-circuit when disabled so a wheel
    -- input over a content-fits panel is fully inert.
    scroll.MoveScroll = function(self, value)
        if currentEnabled == false then return end
        if origMoveScroll then return origMoveScroll(self, value) end
    end

    -- Undo the patch on release so the recycled widget pool returns
    -- to stock behavior for any subsequent acquirer.
    scroll.OnRelease = function(self)
        self.FixScroll  = origFixScroll
        self.MoveScroll = origMoveScroll
        self.OnRelease  = origOnRelease
        self._kcdAlwaysScrollbar = nil
        currentEnabled  = nil
        -- Restore the thumb's normal vertex color in case OnRelease
        -- runs while we're in the disabled state — otherwise the
        -- next acquirer would inherit a greyed thumb.
        if thumb and thumb.SetVertexColor then
            thumb:SetVertexColor(1, 1, 1, 1)
        end
        if scrollbar and scrollbar.Enable then scrollbar:Enable() end
        if upBtn   and upBtn.Enable   then upBtn:Enable()   end
        if downBtn and downBtn.Enable then downBtn:Enable() end
        if origOnRelease then origOnRelease(self) end
    end
end

-- ---------------------------------------------------------------------
-- Lazy AceGUI scroll container. Tabs that drive ctx.body directly
-- (Spells, Profiles) never trigger this; they place their own AceGUI
-- containers on top of ctx.body.
-- ---------------------------------------------------------------------

local function ensureScroll(ctx)
    if ctx.scroll then return ctx.scroll end
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(ctx.body)
    scroll.frame:ClearAllPoints()
    -- Right-edge inset of PADDING_X+12 leaves room for the scrollbar
    -- (which AceGUI nudges 20px to the right of the scrollframe when
    -- visible) without it being flush against the panel border.
    scroll.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      PADDING_X - 4, -8)
    scroll.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -(PADDING_X + 12), 8)
    scroll.frame:Show()

    -- AceGUI's ScrollFrame normally has its width/height set by a parent
    -- AceGUI container during DoLayout, which fires OnWidthSet/OnHeightSet
    -- and updates content.width / the scrollbar visibility. We parent it
    -- to a Blizzard frame via anchors instead, so those callbacks never
    -- fire and `content.width` stays nil. Hook OnSizeChanged to forward
    -- the actual size into AceGUI and then re-run DoLayout + FixScroll so
    -- the scrollbar appears whenever the body resizes (panel open / show).
    scroll.frame:SetScript("OnSizeChanged", function(_, w, h)
        if scroll.OnWidthSet  then scroll:OnWidthSet(w)  end
        if scroll.OnHeightSet then scroll:OnHeightSet(h) end
        if scroll.DoLayout    then scroll:DoLayout()     end
        if scroll.FixScroll   then scroll:FixScroll()    end
    end)

    -- Always render the scrollbar, even on short panels — gives every
    -- settings tab a symmetric right-edge gutter. See
    -- Helpers.PatchAlwaysShowScrollbar.
    Helpers.PatchAlwaysShowScrollbar(scroll)

    ctx.scroll = scroll
    return scroll
end

local function fireOnChange(def, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and NS.Util then
            NS.Util.print("onChange for " .. tostring(def.path) .. " failed: " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------
-- Section header — AceGUI Heading (full-width label flanked by side
-- divider textures, matches AceConfigDialog group separators).
--
-- Visual tweaks vs raw AceGUI defaults:
--   * Larger label font (GameFontNormalLarge) so the section title
--     stands out from body widgets.
--   * Extra vertical breathing room above and below by inserting a
--     SimpleGroup spacer between consecutive sections (skipped on the
--     first section since the panel header already provides whitespace
--     above the first group), plus a trailing spacer to push the first
--     widget of the section away from the heading.
-- ---------------------------------------------------------------------

local SECTION_TOP_SPACER    = 10
local SECTION_BOTTOM_SPACER = 6
local SECTION_HEADING_H     = 26

local function addSpacer(scroll, height)
    local sp = AceGUI:Create("SimpleGroup")
    sp:SetLayout(nil)
    sp:SetFullWidth(true)
    sp:SetHeight(height)
    scroll:AddChild(sp)
end

function Helpers.Section(ctx, label)
    local scroll = ensureScroll(ctx)

    if ctx.lastGroup ~= nil then
        addSpacer(scroll, SECTION_TOP_SPACER)
    end

    local h = AceGUI:Create("Heading")
    h:SetText(label)
    h:SetFullWidth(true)
    h:SetHeight(SECTION_HEADING_H)
    if h.label and h.label.SetFontObject and _G.GameFontNormalLarge then
        h.label:SetFontObject(_G.GameFontNormalLarge)
    end
    scroll:AddChild(h)

    addSpacer(scroll, SECTION_BOTTOM_SPACER)
    return h
end

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
    if def.type == "string" then return makeDropdown(ctx, def, parent, relativeWidth)    end
    if def.type == "color"  then return makeColorPicker(ctx, def, parent, relativeWidth) end
end

-- Standalone action button (no label row). Used for actions that read
-- naturally from the button text alone, e.g. "Reset position".
function Helpers.InlineButton(ctx, buttonText, tooltip, onClick, width)
    local scroll = ensureScroll(ctx)

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local btn = AceGUI:Create("Button")
    btn:SetText(buttonText or "")
    btn:SetWidth(width or 160)
    btn:SetCallback("OnClick", function()
        if not onClick then return end
        local ok, err = pcall(onClick)
        if not ok and NS.Util then
            NS.Util.print("button onClick failed: " .. tostring(err))
        end
    end)
    row:AddChild(btn)

    attachTooltip(btn, buttonText, tooltip)
    scroll:AddChild(row)
    return btn
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

-- Inline action button (label on the left, button on the right).
-- Used for "Reset position" et al. — not a setting.
function Helpers.Button(ctx, labelText, buttonText, tooltip, onClick)
    local scroll = ensureScroll(ctx)

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local lbl = AceGUI:Create("Label")
    lbl:SetText(labelText or "")
    lbl:SetWidth(280)
    row:AddChild(lbl)

    local btn = AceGUI:Create("Button")
    btn:SetText(buttonText or "")
    btn:SetWidth(140)
    btn:SetCallback("OnClick", function()
        if not onClick then return end
        local ok, err = pcall(onClick)
        if not ok and NS.Util then
            NS.Util.print("button onClick failed: " .. tostring(err))
        end
    end)
    row:AddChild(btn)

    attachTooltip(btn, labelText, tooltip)
    scroll:AddChild(row)
    return btn
end

-- ---------------------------------------------------------------------
-- Schema-driven render
-- ---------------------------------------------------------------------

-- Pixel gap inserted between each two-column row of schema widgets so
-- adjacent rows have visual breathing room. AceGUI's "List" layout packs
-- children flush by default; this spacer is what gives the rendered
-- panel its airy look.
local ROW_VSPACER = 8

-- afterGroup is an optional { [groupName] = function(ctx) ... end } map.
-- The callback runs once, immediately after the last schema row of that
-- group is rendered (and before the next group's section header). Used
-- by the General tab to drop the "Reset position" button into the
-- "Master controls" group instead of giving it its own subsection.
--
-- Rendering layout: schema widgets are paired into 50%/50% Flow rows,
-- each row wrapped in a full-width SimpleGroup so the AceGUI layout pass
-- gives both children exactly half the panel width and breaks them onto
-- the same line. Section headings span the full width (one per row),
-- and every row is followed by a small vertical spacer for breathing
-- room. afterGroup callbacks (e.g. inline action buttons) fire after
-- the in-progress row is flushed, so they always start on a fresh line.
function Helpers.RenderSchema(ctx, panelKey, afterGroup)
    local rows = Helpers.SchemaForPanel(panelKey)
    local scroll = ensureScroll(ctx)
    local pendingRow, pendingCount = nil, 0

    local function flushRow()
        if pendingRow then
            scroll:AddChild(pendingRow)
            addSpacer(scroll, ROW_VSPACER)
            pendingRow, pendingCount = nil, 0
        end
    end

    local function startRow()
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        return row
    end

    for i, def in ipairs(rows) do
        if def.group and def.group ~= ctx.lastGroup then
            flushRow()                 -- previous group's tail row
            Helpers.Section(ctx, def.group)
            ctx.lastGroup = def.group
        end

        -- def.solo = true means "render this widget alone in the left
        -- half of its own row, leaving the right half empty." Used for
        -- visually-grouping pivots (e.g. Icons → Border's "Show border"
        -- header followed by Border thickness | Border color, or Cast
        -- bar → Position's "Anchor Mode" pivot above the two attach-
        -- point dropdowns). Implementation: flush the in-progress row
        -- first so the solo widget starts fresh, then flush again
        -- immediately after rendering so the next widget begins on a
        -- new row.
        if def.solo and pendingCount > 0 then
            flushRow()
        end

        if not pendingRow then pendingRow = startRow() end
        Helpers.RenderField(ctx, def, pendingRow, 0.5)
        pendingCount = pendingCount + 1
        if def.solo or pendingCount >= 2 then flushRow() end

        local nextDef = rows[i + 1]
        if afterGroup and def.group
           and (not nextDef or nextDef.group ~= def.group)
           and afterGroup[def.group] then
            flushRow()                 -- afterGroup buttons start fresh
            afterGroup[def.group](ctx)
            afterGroup[def.group] = nil  -- one-shot
        end
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
end

-- Refresh every widget on every panel ctx — called after a slash-cmd
-- /kcd set so an open panel reflects the new value immediately.
function Helpers.RefreshAllPanels()
    for _, ctx in ipairs(NS.Settings._panels) do
        for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    end
end

-- Reset every Schema entry for `panelKey` back to its default; fire
-- CONFIG_CHANGED for each unique section. Used by the per-panel
-- Defaults button.
function Helpers.RestoreDefaults(panelKey, ctx)
    local sections = {}
    for _, def in ipairs(Helpers.SchemaForPanel(panelKey)) do
        if def.default ~= nil then
            local parent, key = Resolve(def.path)
            if parent then
                -- DeepCopy so two profiles don't end up sharing the same
                -- nested-table default (e.g. an RGBA array — today the only
                -- tabular default — but anything nested would silently leak
                -- without a real recursive clone).
                local v = NS.Util.DeepCopy(def.default)
                parent[key] = v
                fireOnChange(def, v)
                sections[def.section or panelKey] = true
            end
        end
    end
    for s in pairs(sections) do Helpers.FireConfigChanged(s) end
    if ctx and ctx.refreshers then
        for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    end
end

-- Reset every schema-driven panel (general / icons / castbar) to its
-- per-row default. Spells and Profiles are skipped here on purpose —
-- spells have a separate Database:ResetAllSpells() (the General >
-- "Reset all settings" popup calls both); resetting profiles would
-- delete user data. After resetting, all open panels' refreshers
-- run so live widgets reflect the new state.
function Helpers.RestoreAllDefaults()
    local ctxByKey = {}
    for _, ctx in ipairs(NS.Settings._panels or {}) do
        if ctx.panelKey then ctxByKey[ctx.panelKey] = ctx end
    end
    for _, panelKey in ipairs(NS.Settings.order or {}) do
        if Helpers.SchemaForPanel(panelKey)[1] then
            Helpers.RestoreDefaults(panelKey, ctxByKey[panelKey])
        end
    end
    Helpers.RefreshAllPanels()
end

-- Look up `path` in the schema and write `value` through the same
-- path the schema widgets use: Helpers.Set (which fires CONFIG_CHANGED
-- with def.section), then def.onChange, then RefreshAllPanels so any
-- open settings tab reflects the new value. Returns true on success,
-- false if no schema row matches `path`.
--
-- Lets slash commands that mutate schema-backed fields (e.g. `/kcd
-- lock`, `/kcd debug log`) share a single write/notify/refresh code
-- path with `/kcd set <path> <value>` and the panel widgets — so a
-- future onChange added to a row doesn't silently diverge between
-- code paths.
function Helpers.SetAndRefresh(path, value)
    local def = Helpers.FindSchema(path)
    if not def then return false end
    Helpers.Set(def.path, def.section, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and NS.Util then
            NS.Util.print("onChange for " .. tostring(def.path)
                              .. " failed: " .. tostring(err))
        end
    end
    Helpers.RefreshAllPanels()
    return true
end

-- Restore the icon grid to its default screen position and notify the
-- icon module so it re-anchors immediately. Used by the General tab's
-- "Reset position" button and the `/kcd resetposition` slash command.
-- The default coords come from KickCD.DEFAULT_PROFILE.anchors.icons so
-- we don't duplicate magic numbers across UI / CLI / Database layers.
function Helpers.ResetIconPosition()
    if not (NS.db and NS.db.profile) then return end
    local d = NS.DEFAULT_PROFILE
              and NS.DEFAULT_PROFILE.anchors
              and NS.DEFAULT_PROFILE.anchors.icons
    NS.db.profile.anchors = NS.db.profile.anchors or {}
    NS.db.profile.anchors.icons = d
        and { point = d.point, relativePoint = d.relativePoint,
              x = d.x, y = d.y }
        or  { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
    -- "general" alone is sufficient: IconGrid:OnConfigChanged's general
    -- branch re-anchors the grid. The previous "icons" fire was
    -- redundant work — no row in the icons section actually changed,
    -- and the general branch already owns the re-anchor pass.
    Helpers.FireConfigChanged("general")
end

-- Reset every schema-driven panel AND every spec's spell list to addon
-- defaults. The active profile is the only one affected. Used by the
-- General tab's "Reset all settings" popup and the `/kcd resetall`
-- slash command — both go through this single helper so the two paths
-- never diverge.
function Helpers.ResetAll()
    Helpers.RestoreAllDefaults()
    if NS.Database and NS.Database.ResetAllSpells then
        NS.Database:ResetAllSpells()
    end
end

-- ---------------------------------------------------------------------
-- Main (parent-category) page content
-- ---------------------------------------------------------------------
--
-- The parent canvas page carries the standard header (title + divider)
-- plus a static splash: logo, the addon's one-liner, and the slash-
-- command list. Rendered through ensureScroll(ctx) so the page picks
-- up the same always-visible vertical scrollbar as every other tab,
-- and so AceGUI's "List" layout left-aligns every child for free.

local MAIN_LOGO_SIZE      = 300    -- exact native size of media/logos/kickcd.logo.tga
local MAIN_GAP_AFTER_LOGO = 8
local MAIN_GAP_AFTER_DESC = 12
local MAIN_GAP_BELOW_HEAD = 6

local function addBlock(scroll, height)
    local sp = AceGUI:Create("SimpleGroup")
    sp:SetLayout(nil)
    sp:SetFullWidth(true)
    sp:SetHeight(height)
    scroll:AddChild(sp)
    return sp
end

function Helpers.BuildMainContent(ctx)
    local scroll = ensureScroll(ctx)

    -- 1) Logo. SimpleGroup is a full-width child so AceGUI's List layout
    -- gives it the scroll's full width to live in; the texture inside
    -- is anchored TOPLEFT, sized to the source TGA's native dimensions
    -- (MAIN_LOGO_SIZE × MAIN_LOGO_SIZE), so it renders pixel-exact and
    -- left-aligned regardless of panel width.
    local logoGroup = AceGUI:Create("SimpleGroup")
    logoGroup:SetLayout(nil)
    logoGroup:SetFullWidth(true)
    logoGroup:SetHeight(MAIN_LOGO_SIZE)

    local logoTex = logoGroup.frame:CreateTexture(nil, "ARTWORK")
    logoTex:SetTexture("Interface\\AddOns\\KickCD\\media\\logos\\kickcd.logo.tga")
    logoTex:SetSize(MAIN_LOGO_SIZE, MAIN_LOGO_SIZE)
    logoTex:SetPoint("TOPLEFT", logoGroup.frame, "TOPLEFT", 0, 0)
    scroll:AddChild(logoGroup)

    addBlock(scroll, MAIN_GAP_AFTER_LOGO)

    -- 2) One-liner — full-width Label (left-aligned by AceGUI default).
    local desc = AceGUI:Create("Label")
    desc:SetFullWidth(true)
    desc:SetText(L["Tracks interrupt and CC cooldowns on a movable icon grid."])
    if desc.label and desc.label.SetFontObject and _G.GameFontHighlight then
        desc.label:SetFontObject(_G.GameFontHighlight)
    end
    if desc.label and desc.label.SetJustifyH then
        desc.label:SetJustifyH("LEFT")
    end
    scroll:AddChild(desc)

    addBlock(scroll, MAIN_GAP_AFTER_DESC)

    -- 3) Separator + "Slash Commands" heading: a single AceGUI Heading
    -- widget renders as a label flanked by side dividers, so this one
    -- widget delivers both the visual separator and the section title.
    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetHeight(26)
    heading:SetText(L["Slash Commands"])
    if heading.label and heading.label.SetFontObject and _G.GameFontNormalLarge then
        heading.label:SetFontObject(_G.GameFontNormalLarge)
    end
    scroll:AddChild(heading)

    addBlock(scroll, MAIN_GAP_BELOW_HEAD)

    -- 4) Slash-command rows pulled from KickCD.COMMANDS so this list
    -- stays in lockstep with /kcd help — adding a command in
    -- core/KickCD.lua surfaces here automatically.
    for _, entry in ipairs(NS.COMMANDS or {}) do
        local row = AceGUI:Create("Label")
        row:SetFullWidth(true)
        row:SetText(("|cffffff00/kcd %s|r  |cffffffff—|r  %s")
            :format(entry[1], entry[2]))
        if row.label and row.label.SetJustifyH then
            row.label:SetJustifyH("LEFT")
        end
        scroll:AddChild(row)
    end
end

-- ---------------------------------------------------------------------
-- Tab + main-category registration
-- ---------------------------------------------------------------------

function NS.Settings.RegisterTab(key, builder)
    if type(key) ~= "string" or type(builder) ~= "function" then return end
    NS.Settings.builders[key] = builder
    if NS.Settings.main and not NS.Settings.sub[key] then
        local ok, sub = pcall(builder, NS.Settings.main)
        if ok and sub then
            NS.Settings.sub[key] = sub
        end
    end
end

local function RegisterPanel()
    if NS.Settings.main then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory
            and Settings.RegisterAddOnCategory) then
        return
    end

    -- Validate the assembled schema before we hand any rows to the
    -- panel renderer / slash command. Errors are printed but
    -- non-fatal: a broken row should surface a clear chat error,
    -- not silently fail to render or block the rest of the panel
    -- from registering.
    Helpers.ValidateSchema()

    -- Register the parent as a canvas-layout category (rather than
    -- vertical-layout) so the parent page renders with the same custom
    -- header — gold title + gold divider — that every subcategory uses.
    -- Vertical-layout categories auto-render their own header, which
    -- visually clashes with our subcategory styling.
    local mainCtx = Helpers.CreatePanel("KickCDMainPanel", L["Ka0s KickCD"], { isMain = true })

    -- Defer body render until first OnShow: AceGUI's ScrollFrame lays
    -- out children against the parent's current width, which is zero at
    -- PLAYER_LOGIN, and there's no point building widgets for a panel
    -- the user may never open.
    local mainRendered = false
    mainCtx.panel:SetScript("OnShow", function()
        if mainRendered then return end
        mainRendered = true
        Helpers.BuildMainContent(mainCtx)
    end)

    local main = Settings.RegisterCanvasLayoutCategory(mainCtx.panel, L["Ka0s KickCD"])
    Settings.RegisterAddOnCategory(main)
    NS.Settings.main = main

    for _, key in ipairs(NS.Settings.order) do
        local fn = NS.Settings.builders[key]
        if type(fn) == "function" and not NS.Settings.sub[key] then
            local ok, sub = pcall(fn, main)
            if ok and sub then
                NS.Settings.sub[key] = sub
            elseif not ok and NS.Util then
                NS.Util.print("settings tab '" .. key .. "' failed: " .. tostring(sub))
            end
        end
    end
end
NS.Settings.Register = RegisterPanel

-- bootstrap: defer until Blizzard_Settings is ready
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_Settings" then return end
    RegisterPanel()
    if NS.Settings.main then
        self:UnregisterAllEvents()
    end
end)
