-- settings/Panel.lua
--
-- Settings UI framework — the canvas/layout core. The widget-maker
-- primitives and the schema render/reset layer were peeled into siblings
-- (KCD-24, §1.2): settings/Panel_Widgets.lua (the makers) and
-- settings/Panel_Render.lua (RenderRows / RenderSchema / Restore* / Reset*).
-- All three publish onto the one NS.Settings.Helpers table, so call order
-- across the trio is irrelevant; the siblings load right after this file.
--
-- Settings UI framework. Every tab — General, Icons, Spells, Profiles —
-- is registered as a canvas-layout subcategory and shares one header
-- design: title (left) + Defaults button (right) + divider. The title and
-- divider are stamped on by Helpers.CreatePanel; the Defaults button is
-- created lazily on the panel's first OnShow by
-- Helpers.EnsureDefaultsButton (skinning load-order race — see there).
-- Below the header each tab lays out its own body.
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
NS.Settings.order     = { "general", "icons", "castbar", "label", "spells", "profiles" }
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

-- Settings-change logging (standard §10): one [Set] line per settled change,
-- at the single write seam. Color/slider commits call Helpers.Set on every
-- throttled drag tick (~20/sec), so a per-path TRAILING debounce collapses a
-- whole drag/gesture to a single line carrying the final value, emitted
-- SET_LOG_DEBOUNCE after the last write. Each write bumps a per-path
-- generation token and schedules a fresh timer; only the timer whose token is
-- still current fires, so earlier writes in the gesture are superseded rather
-- than each producing their own line. String-building stays behind the debug
-- gate (§4 zero-alloc); the extra per-tick timers only exist while debug is on.
local SET_LOG_DEBOUNCE = 0.3
local pendingSet, setGen = {}, {}

local function fmtSetValue(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function logSet(path, value)
    if not (NS.State and NS.State.debug) then return end   -- gate first
    pendingSet[path] = value
    local gen = (setGen[path] or 0) + 1
    setGen[path] = gen
    C_Timer.After(SET_LOG_DEBOUNCE, function()
        if setGen[path] ~= gen then return end   -- superseded by a later write
        local v = pendingSet[path]
        pendingSet[path] = nil
        setGen[path] = nil
        if NS.State and NS.State.debug then
            NS.Debug("Set", "%s = %s", tostring(path), fmtSetValue(v))
        end
    end)
end

function Helpers.Set(path, section, value)
    local parent, key = Resolve(path)
    if not parent then return end
    parent[key] = value
    logSet(path, value)
    Helpers.FireConfigChanged(section)
end

-- ---------------------------------------------------------------------
-- Schema query helpers
-- ---------------------------------------------------------------------

-- `unit` (optional) filters to rows for that unit plus unit-agnostic
-- rows (e.g. General, which has no `unit` field and always matches).
-- Omitting `unit` returns every row for the panel across all units —
-- used by RestoreDefaults/RestoreAllDefaults, which reset every unit's
-- values together.
function Helpers.SchemaForPanel(panelKey, unit)
    local out = {}
    for _, def in ipairs(NS.Settings.Schema) do
        if def.panel == panelKey and (unit == nil or not def.unit or def.unit == unit) then
            out[#out + 1] = def
        end
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
    general = true, icons = true, castbar = true, label = true,
    spells  = true, profiles = true,
}
local _validSections = {
    general = true, icons = true, castbar = true, label = true,
    spells  = true, debug = true, units = true,
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
-- Published for settings/Panel_Render.lua (RenderRows), which reports a
-- per-row render failure through the same schema-error channel.
Helpers.PrintSchemaError = _printSchemaError

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
                    .. " (expected one of: general, icons, castbar, label, spells, profiles)")
                errors = errors + 1
            end
            if not _validSections[def.section] then
                _printSchemaError(where, "invalid `section` = " .. tostring(def.section)
                    .. " (expected one of: general, icons, castbar, label, spells, debug, units)")
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

    -- Record the INTENT only; the widget itself is built on first OnShow
    -- by Helpers.EnsureDefaultsButton (see the note on that function for
    -- why it can't be created here).
    panel.wantsDefaultsButton = opts.defaultsButton and true or false
    panel.defaultsTooltip     = opts.defaultsTooltip

    return titleFS, divider
end

-- Build the header's Defaults button once, on the panel's FIRST OnShow.
--
-- It stays an AceGUI Button (options-ui-§5), but *when* it's created
-- matters as much as *what* creates it. AceGUI is a shared library:
-- UI-skinning addons restyle its widgets by hooking `RegisterAsWidget`,
-- so any widget created BEFORE that hook is installed keeps Blizzard's
-- stock `UI-Panel-Button-Up` art — the red stone button — for the rest
-- of the session, while everything created after it comes out skinned.
--
-- Settings-category registration runs during load (ADDON_LOADED /
-- PLAYER_LOGIN), so building the button there is a race against every
-- other addon's load order: this addon wins it only while it happens to
-- load after the skinner. Rename the folder, or add a skin, and the same
-- code renders red. Deferring to first OnShow removes the race outright —
-- by then every addon has loaded. Do NOT "simplify" this back into
-- buildHeader / CreatePanel.
--
-- Idempotent: safe to call as the first statement of every OnShow.
function Helpers.EnsureDefaultsButton(panel)
    if not panel or panel.defaultsBtn or not panel.wantsDefaultsButton then
        return
    end
    if not AceGUI then return end

    local btn = AceGUI:Create("Button")
    if not (btn and btn.frame) then return end
    btn:SetText(L["Defaults"])
    btn:SetWidth(DEFAULTS_W)
    btn.frame:SetParent(panel)
    btn.frame:ClearAllPoints()
    btn.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                       -PADDING_X, -HEADER_TOP)
    btn.frame:Show()
    attachTooltip(btn, L["Defaults"], panel.defaultsTooltip)
    panel.defaultsBtn = btn

    -- The click handler is registered at Build() time, before the button
    -- exists, so it's parked on the panel and wired here.
    if panel.defaultsOnClick then
        btn:SetCallback("OnClick", panel.defaultsOnClick)
    end
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

    local titleFS, divider = buildHeader(panel, title, opts)
    panel.title   = titleFS
    panel.divider = divider

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
        -- Selected unit for per-unit schema panels (Icons / Castbar). Left
        -- nil here on purpose: panels without a unit selector (General,
        -- Spells, Profiles) must render rows for every unit, and
        -- RenderSchema passes ctx.unit straight into SchemaForPanel, where
        -- unit == nil is what makes that "all units" match happen. Only
        -- Helpers.RenderUnitPanel (Icons / Castbar) defaults ctx.unit to
        -- "target", right before it draws the selector.
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

-- Exposed so per-unit panel builders (Icons / Castbar) can add a
-- persistent header (unit selector, focus link/copy row) directly to the
-- panel's AceGUI scroll container ahead of the schema-driven body — see
-- Helpers.ClearScroll / Helpers.RerenderUnitPanel below.
Helpers.EnsureScroll = ensureScroll

local function fireOnChange(def, value)
    if def.onChange then
        local ok, err = pcall(def.onChange, value)
        if not ok and NS.Util then
            NS.Util.print("onChange for " .. tostring(def.path) .. " failed: " .. tostring(err))
        end
    end
end
-- Published for settings/Panel_Widgets.lua (the widget makers) and
-- settings/Panel_Render.lua (RestoreDefaults / SetAndRefresh), which all
-- run a row's onChange after committing its value.
Helpers.FireOnChange = fireOnChange

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
-- Pixel gap inserted between each two-column row of schema widgets so adjacent
-- rows have visual breathing room. AceGUI's "List" layout packs children flush
-- by default; this spacer is what gives the rendered panel its airy look.
local ROW_VSPACER = 8
local SECTION_HEADING_H     = 26
-- Published so settings/Panel_Widgets.lua (InlinePair) and
-- settings/Panel_Render.lua (RenderRows / RenderUnitPanel) insert the
-- same inter-row gap as the in-file renderers.
Helpers.ROW_VSPACER = ROW_VSPACER

local function addSpacer(scroll, height)
    local sp = AceGUI:Create("SimpleGroup")
    sp:SetLayout(nil)
    sp:SetFullWidth(true)
    sp:SetHeight(height)
    scroll:AddChild(sp)
end

-- Exposed alongside Helpers.EnsureScroll for the same reason — per-unit
-- panel headers (unit selector, focus link/copy row) want the same
-- breathing-room spacer the schema renderer uses between rows.
Helpers.AddSpacer = addSpacer

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
