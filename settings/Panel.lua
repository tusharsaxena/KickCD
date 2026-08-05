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
NS.Settings.Schema    = NS.Settings.Schema or {}
NS.Settings._panels   = NS.Settings._panels or {}

-- (`main`, `sub`, `builders` and `order` were this file's private page registry.
-- They went with RegisterTab / RegisterPanel — see the note at the foot of this
-- file. Page order is the TOC's now, which is where it was already duplicated.)

-- NS.Settings.Helpers IS the LibKa0s-Options-1.0 instance, built in
-- settings/OptionsSetup.lua which loads immediately before this file. This file
-- DECORATES it in place with the pieces that did not generalize, rather than
-- creating a fresh table (options-ui-§1): a host page helper added later has to
-- be able to call Helpers.RenderRows like any other page does, and a suite that
-- swaps a member out to spy on it must be swapping the one the library's own
-- callers see.
local Helpers = NS.Settings.Helpers

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
-- broken row is an addon-author bug; the right user-visible behavior
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
--- The 13 frame-anchor options, as the keyed { key = label } hash the widget
--- makers and the value parser both read.
---
--- Keyed rather than an ordered array of records: that is LibKa0s-Options-1.0's
--- and LibKa0s-Slash-1.0's vocabulary, and an array is silently invisible to
--- both — the parser would offer "1, 2, 3 ..." as the allowed values and the
--- dropdown would list indices instead of anchors.
function Helpers.AnchorValues()
    return {
        ["TOP_LEFT"]      = L["Top left"],
        ["TOP_MIDDLE"]    = L["Top middle"],
        ["TOP_RIGHT"]     = L["Top right"],
        ["BOTTOM_LEFT"]   = L["Bottom left"],
        ["BOTTOM_MIDDLE"] = L["Bottom middle"],
        ["BOTTOM_RIGHT"]  = L["Bottom right"],
        ["LEFT_TOP"]      = L["Left top"],
        ["LEFT_MIDDLE"]   = L["Left middle"],
        ["LEFT_BOTTOM"]   = L["Left bottom"],
        ["RIGHT_TOP"]     = L["Right top"],
        ["RIGHT_MIDDLE"]  = L["Right middle"],
        ["RIGHT_BOTTOM"]  = L["Right bottom"],
        ["CENTER"]        = L["Center"],
    }
end

--- The declared render order for AnchorValues, handed to a row as `sorting`.
--- A SIBLING because a hash has none: without it the dropdown alphabetizes,
--- scrambling a list whose reading order (top row, bottom row, the two sides,
--- then center) is the whole point.
function Helpers.AnchorOrder()
    return {
        "TOP_LEFT", "TOP_MIDDLE", "TOP_RIGHT",
        "BOTTOM_LEFT", "BOTTOM_MIDDLE", "BOTTOM_RIGHT",
        "LEFT_TOP", "LEFT_MIDDLE", "LEFT_BOTTOM",
        "RIGHT_TOP", "RIGHT_MIDDLE", "RIGHT_BOTTOM",
        "CENTER",
    }
end

--- Build the option list for a LibSharedMedia media type.
--- The option list for a LibSharedMedia media type, as a keyed { key = key }
--- hash. No `sorting` sibling: a media list has no meaningful declared order and
--- the widget makers alphabetize when none is given, which is what a font or
--- texture picker wants.
function Helpers.LSMValues(mediaType)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM and LSM.List then
        for _, key in ipairs(LSM:List(mediaType) or {}) do out[key] = key end
    end
    -- Never empty: a dropdown with no options renders as a dead control, and an
    -- absent optional media library should cost the swatch, not the setting.
    if next(out) == nil then out["Default"] = "Default" end
    return out
end

-- ---------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------
--
-- Sourced from KickCD.Const so the values live in exactly one place
-- across the addon — see core/Constants.lua for the rationale on each.

-- Only PADDING_X survives, and only because this addon's own landing-page body
-- still uses it. HEADER_TOP and HEADER_HEIGHT went with the header: those are
-- LibKa0s-Options-1.0's LAYOUT table now, and options-ui-§8 is explicit that a
-- host MUST NOT keep its own copies — a host copy is the copy that goes stale,
-- and the whole point is that the panels cannot drift apart. Where host code
-- needs one, it reads it off the instance (Helpers.ROW_VSPACER,
-- Helpers.SECTION_HEADING_H, Helpers.BUTTON_PAIR_REL) rather than restating it.
local PADDING_X = NS.Const.PANEL_PADDING_X

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

-- Pixel gap inserted between each two-column row of schema widgets so adjacent
-- rows have visual breathing room. AceGUI's "List" layout packs children flush
-- by default; this spacer is what gives the rendered panel its airy look.
local ROW_VSPACER = 8
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

    -- 4) Slash-command rows, rendered by the SAME formatter `/kcd help` prints
    -- through (NS.Slash:LandingRows -> LibKa0s-Slash-1.0's one row formatter),
    -- minus the chat indent — each row here is its own label, where a leading
    -- indent reads as a mistake.
    --
    -- This file used to carry its own format string for the same NS.COMMANDS
    -- data: two spaces either side of the dash, the dash itself wrapped in the
    -- white color run, and the description left uncolored. So the panel and
    -- the help block rendered one table two ways, and every command added drifted
    -- them further. That is the divergence the convergence exists to end, and the
    -- visible cost is this page's spacing halving and its descriptions turning
    -- white. Adding a command in core/KickCD.lua still surfaces here
    -- automatically.
    for _, text in ipairs(NS.Slash and NS.Slash:LandingRows() or {}) do
        local row = AceGUI:Create("Label")
        row:SetFullWidth(true)
        row:SetText(text)
        if row.label and row.label.SetJustifyH then
            row.label:SetJustifyH("LEFT")
        end
        scroll:AddChild(row)
    end
end

-- ---------------------------------------------------------------------
-- Tab + main-category registration — GONE, and where it went
-- ---------------------------------------------------------------------
--
-- This file used to carry a SECOND page registry alongside the library's:
-- NS.Settings.RegisterTab queued builders into NS.Settings.builders, a private
-- RegisterPanel registered the parent canvas category and drained the queue in
-- NS.Settings.order, and a private bootstrap frame fired it on PLAYER_LOGIN /
-- ADDON_LOADED. The library's own registry — O.RegisterOptionsPage, the
-- pendingPages queue and O.CreateOptionsPanel — was wired up at
-- settings/OptionsSetup.lua and had no callers at all (KCD-R-03, KCD-A-09).
--
-- Two registries for one options tree is not a redundancy, it is a coin toss:
-- whichever one ran registered the pages, and the other's guarantees (the
-- per-page pcall that names the failing page, the queue drain that cannot run
-- twice, the idempotent CreateOptionsPanel that refuses to register a second
-- Blizzard category) applied to nothing. options-ui-§5 says registration goes
-- through the library's registry and that the library's CreateOptionsPanel runs
-- at PLAYER_LOGIN; that is now the only path.
--
--   * each page file tail calls NS.RegisterOptionsPage(key, name, Build)
--     (settings/OptionsSetup.lua:RegisterOptionsPage -> O.RegisterOptionsPage);
--   * core/KickCD.lua's OnEnable calls NS.CreateOptionsPanel() once;
--   * the main canvas, its lazy first-OnShow body render and the schema
--     validation are the descriptor's `buildMain` and `validate` hooks, which
--     already pointed at Helpers.BuildMainContent and Helpers.ValidateSchema.
--
-- Page ORDER is the TOC's settings/ block order, which is the order the six
-- builders register in and the order the library drains the queue in. It used
-- to be spelled a second time in NS.Settings.order, immediately below the TOC
-- that already fixed it.


-- (CreatePanel, EnsureDefaultsButton, PatchAlwaysShowScrollbar and Section are
-- LibKa0s-Options-1.0's now — the canvas shell, the header and breadcrumb, the
-- lazily-created Defaults button and the always-shown scrollbar patch. They
-- were ~230 lines here and identical in intent across the collection.)