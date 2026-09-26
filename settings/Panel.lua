-- settings/Panel.lua
--
-- Settings UI framework — the canvas/layout core. The widget-maker
-- primitives and the schema render/reset layer were peeled into siblings
-- (KCD-24, layout-§1): settings/Panel_Widgets.lua (the makers) and
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

local _, NS = ...
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
-- The write seam is settings/SchemaSetup.lua's now
-- ---------------------------------------------------------------------
--
-- Resolve, the SESSION_PATHS / GLOBAL_PATHS tables, Helpers.Get / Set, the
-- coalesced bus, the bulk bracket, the debounced [Set] line and the profile
-- reset's count all lived here. They are LibKa0s-Schema-1.0's now, as
-- NS.Settings.Store (settings/SchemaSetup.lua): Store.Get / Store.Set /
-- Store.SetMany, the bracket pair, ResetCounted / ConsumeResetCount and
-- Validate. The two rows stored outside the profile (the Debug console and the
-- minimap button) carry their own get/set on the row (settings/General.lua),
-- the master switch is the `enabled` row's onChange, and a batch's
-- announcements are the descriptor's announceBatch. What stays here is the
-- one message the write seam's announce sends.

--- The one CONFIG_CHANGED send site for a settings write (architecture-§4).
--- settings/SchemaSetup.lua's announce and announceBatch call it with the row's
--- `section`; Helpers.ResetIconPosition calls it for the anchor it writes.
function Helpers.FireConfigChanged(section)
    if NS and NS.SendMessage then
        NS:SendMessage(NS.MSG.CONFIG_CHANGED, { section = section })
    end
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

--- Stamp a composed block with this addon's own row fields and append it.
---
--- The composers (libs/LibKa0s/OptionsCompose.lua) return ORDINARY schema rows
--- carrying `page`, `group`, `subgroup` and `order`. This addon keys its rows
--- `panel` + `section` -- and, on the Grid page's three per-unit entries, `unit` -- so one
--- pass stamps those on and appends in declaration order. Nothing else about a
--- composed row is touched: what comes back is indistinguishable from a
--- hand-written row, which is the whole point of the composers being pure.
---
--- @param rows  table|nil  what a composer returned (nil on the degraded path)
--- @param stamp table      the host fields every row in the block carries
--- @return table rows
function Helpers.AddComposed(rows, stamp)
    for _, row in ipairs(rows or {}) do
        for field, value in pairs(stamp) do row[field] = value end
    end
    -- Through the seam's registry rather than onto the array by hand, so
    -- Store.FindRow indexes the block the moment it lands.
    NS.Settings.Store.AddRows(rows or {})
    return rows or {}
end

-- (The host's linear row lookup is gone: Store.FindRow is the path index. So
-- is the host's own shape check with its panel / section / type enums: the Options
-- descriptor's `validate` runs Store.Validate, which checks path, type, group,
-- duplicates and resolution against NS.DEFAULT_PROFILE, and the panel and
-- section enums are a test now -- tests/test_schema.lua's "every row's panel
-- and section are known".)


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

--- A DEFERRED reader for a LibSharedMedia media type: returns a FUNCTION which,
--- called, answers the keyed { key = key } hash. No `sorting` sibling: a media
--- list has no meaningful declared order and the widget makers alphabetize when
--- none is given, which is what a font or texture picker wants.
---
--- WHY A CLOSURE AND NOT THE HASH ITSELF. This member SHADOWS the library's
--- published `O.LSMValues` (docs/ARCHITECTURE.md's deviation register says so and
--- says why), and from LibKa0s-OptionsCompose minor 3 the shadow has a contract to
--- keep: `lib.__AttachCompose` reads this member ONCE, at row-declaration time, and
--- assigns what comes back straight into a row's `values`. Handing back the hash
--- there froze every composed media row at whatever LibSharedMedia happened to hold
--- while `settings/Icons.lua` was being read -- before any media addon has run.
--- Silently: no error, no empty dropdown, just a list that never grows. Until that
--- minor the composer wrapped this call in its own closure, which deferred the read
--- and hid the shape difference; minor 3 dropped that wrapper, because for a host
--- that does NOT shadow the member the double wrap was the collection's one Critical
--- -- `enumList` unwraps a row's `values` exactly once, so a closure round a closure
--- reached it as a function and came back empty.
---
--- The return shape is therefore the library's now: a reader, never a reading.
function Helpers.LSMValues(mediaType)
    return function()
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
end

-- ---------------------------------------------------------------------
-- Layout constants — there are none left, and that is the point
-- ---------------------------------------------------------------------
--
-- options-ui-§8: a host MUST NOT keep its own copies of the library's layout
-- constants. A host copy is the copy that goes stale, and the whole reason the
-- panel chrome was extracted is that the panels cannot then drift apart. This
-- file used to state the rule here and break it twenty lines later.
--
-- Everything is read off the instance now — Helpers.PADDING_X,
-- Helpers.ROW_VSPACER, Helpers.SECTION_HEADING_H, Helpers.BUTTON_PAIR_REL —
-- and `NS.Const.PANEL_PADDING_X` is deleted outright: its only reader was this
-- file's own EnsureScroll copy, and LibKa0s-Options-1.0's EnsureScroll applies
-- the identical inset from `lib.LAYOUT.PADDING_X` (both 16).


-- ---------------------------------------------------------------------
-- Header (title + Defaults button + divider)
-- ---------------------------------------------------------------------



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

-- The inter-row pixel gap and the invisible full-width spacer that applies it
-- both come off the instance now (Helpers.ROW_VSPACER, Helpers.AddSpacer).
-- This file used to declare `local ROW_VSPACER = 8` here and then assign it
-- over the library's published `O.ROW_VSPACER` — same number today, and a
-- silent divergence the first time the library retunes it.

-- ---------------------------------------------------------------------
-- Main (parent-category) page content
-- ---------------------------------------------------------------------
--
-- The parent canvas page carries the standard header (title + divider)
-- plus a static splash: logo, the addon's one-liner, and the slash-
-- command list. Rendered through Helpers.EnsureScroll(ctx) so the page picks
-- up the same always-visible vertical scrollbar as every other tab,
-- and so AceGUI's "List" layout left-aligns every child for free.

local MAIN_LOGO_SIZE      = 300    -- exact native size of media/logos/kickcd.logo.tga
local MAIN_GAP_AFTER_LOGO = 8
local MAIN_GAP_AFTER_DESC = 12
local MAIN_GAP_BELOW_HEAD = 6

function Helpers.BuildMainContent(ctx)
    local scroll = Helpers.EnsureScroll(ctx)

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

    Helpers.AddSpacer(scroll, MAIN_GAP_AFTER_LOGO)

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

    Helpers.AddSpacer(scroll, MAIN_GAP_AFTER_DESC)

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

    Helpers.AddSpacer(scroll, MAIN_GAP_BELOW_HEAD)

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
--     point at Helpers.BuildMainContent and the schema seam's Store.Validate.
--
-- Page ORDER is the TOC's settings/ block order, which is the order the four
-- builders (General, Grid, Spells, Profiles) register in and the order the library drains the queue in. It used
-- to be spelled a second time in NS.Settings.order, immediately below the TOC
-- that already fixed it.


-- (CreatePanel, EnsureDefaultsButton, PatchAlwaysShowScrollbar and Section are
-- LibKa0s-Options-1.0's now — the canvas shell, the header and breadcrumb, the
-- lazily-created Defaults button and the always-shown scrollbar patch. They
-- were ~230 lines here and identical in intent across the collection.)