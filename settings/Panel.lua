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

-- Session-only schema rows store OUTSIDE the profile. options-ui-§15 puts the
-- Debug console in the Master controls tab as a session-only row, and the
-- composer emits its path VERBATIM (`state.debugConsole`) because session state
-- is not under any block's prefix -- so Resolve finds nothing there and a write
-- would silently no-op. One table, keyed by that path, is the whole seam, and it
-- sits INSIDE Get/Set so the panel checkbox, `/kcd set` and the reset sweep all
-- take the addon's one write path (options-ui-§1).
local SESSION_PATHS = {
    -- The console WINDOW, never the debug CAPTURE flag (debug-logging-§5) --
    -- that stays on the in-window "Debug: ON/OFF" button and `/kcd debug on|off`.
    ["state.debugConsole"] = {
        get = function() return NS.DebugLog ~= nil and NS.DebugLog:IsShown() end,
        set = function(on)
            if not NS.DebugLog then return end
            if on then NS.DebugLog:Show() else NS.DebugLog:Hide() end
        end,
    },
}

function Helpers.Get(path)
    local session = SESSION_PATHS[path]
    if session then return session.get() end
    local parent, key = Resolve(path)
    if not parent then return nil end
    return parent[key]
end

-- While Helpers.Coalesced runs, announcements are held here and sent once per
-- section when it returns. nil outside a batch.
local pending

-- A nil section is still an announcement: unbatched, it goes out as
-- { section = nil }. A batch holds it under this sentinel, because a bare nil
-- cannot sit in the order list (`order[#order + 1] = nil` appends nothing, which
-- used to drop it silently), and sends it as nil again when it flushes. So
-- batching moves the timing of a nil announcement and nothing else.
local NIL_SECTION = {}

function Helpers.FireConfigChanged(section)
    if pending then
        local key = section == nil and NIL_SECTION or section
        if not pending.seen[key] then
            pending.seen[key] = true
            pending.order[#pending.order + 1] = key
        end
        return
    end
    if NS and NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = section })
    end
end

--- Run `fn` with CONFIG_CHANGED coalesced: every section it announces is sent
--- ONCE, in first-announced order, after `fn` returns (or raises -- the held
--- sections still go out, then the error is re-raised). Still this function's
--- one SendMessage site (architecture-§4); only the timing moves. A nested call
--- joins the outer batch. Helpers.SetRows is the caller.
function Helpers.Coalesced(fn)
    if pending then return fn() end
    pending = { seen = {}, order = {} }
    local ok, err = pcall(fn)
    local order = pending.order
    pending = nil
    for _, key in ipairs(order) do
        if key == NIL_SECTION then
            Helpers.FireConfigChanged(nil)
        else
            Helpers.FireConfigChanged(key)
        end
    end
    if not ok then error(err, 0) end
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
-- pendingSet[path] = { value, seq }: the value the timer will log, and when it
-- was written, so a flush can put several pending lines back in write order.
local pendingSet, setGen, setSeq = {}, {}, 0

local function fmtSetValue(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Log every debounced [Set] line still waiting, now, in the order they were
--- written, and retire their timers. A bulk act calls this as it opens: its own
--- line is synchronous, so a line left pending from a write just before it would
--- otherwise print AFTER the act, carrying a value the act has since replaced.
--- Each path's generation is bumped rather than cleared, so the retired timer
--- cannot match a later write that starts counting again.
local function flushPendingSets()
    if next(pendingSet) == nil then return end
    local order = {}
    for path, p in pairs(pendingSet) do order[#order + 1] = { path = path, value = p[1], seq = p[2] } end
    table.sort(order, function(a, b) return a.seq < b.seq end)
    for _, e in ipairs(order) do
        pendingSet[e.path] = nil
        setGen[e.path] = (setGen[e.path] or 0) + 1
        if NS.State and NS.State.debug and NS.Debug then
            NS.Debug("Set", "%s = %s", tostring(e.path), fmtSetValue(e.value))
        end
    end
end

-- A bulk copy or reset logs ONE `[Set] <act> <scope>: N rows` line instead of
-- one per row (debug-logging-§10). While one is open, logSet stays quiet and
-- Helpers.Set records each row's value from before the act's first write to it.
-- N is the rows whose value differs from that record at the end, so a row
-- already at its default is not counted, and a row an onChange rewrites mid-act
-- counts once. Only the log is muted: every row still writes, validates and
-- runs its onChange.
--
-- Acts nest (a host act around a library reset, a reset inside a reset). The
-- depth counter keeps ONE record across the levels, and only the outermost
-- level logs, once, with every level's rows. A level that reset the whole
-- profile silences the act, because Database:OnProfileChanged logs that. A
-- level that ended with an error marks the act's line (see logAct).
local bulkDepth, bulkProfileReset, bulkFailed, bulkBefore = 0, false, false, nil

-- Appended to an act's one line when the act ended with an error: the line
-- still goes out, once, and counts what was written before the raise.
local STOPPED = " (stopped by an error)"

local function sameValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not sameValue(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function bulkEnter()
    if bulkDepth == 0 then
        bulkBefore, bulkProfileReset, bulkFailed = {}, false, false
        flushPendingSets()
    end
    bulkDepth = bulkDepth + 1
end

--- Close one level. Returns the rows the whole act changed, and whether any
--- level ended with an error, when this closed the outermost level and no level
--- reset the profile; nil otherwise.
local function bulkLeave(profileReset, failed)
    if bulkDepth == 0 then return nil end   -- an end with no begin
    if profileReset then bulkProfileReset = true end
    if failed then bulkFailed = true end
    bulkDepth = bulkDepth - 1
    if bulkDepth > 0 then return nil end
    local before = bulkBefore
    bulkBefore = nil
    if bulkProfileReset then return nil end
    local n = 0
    for path, box in pairs(before) do
        if not sameValue(box[1], Helpers.Get(path)) then n = n + 1 end
    end
    return n, bulkFailed
end

--- The act's one line: `[Set] <act> <scope>: N rows`, or `[Set] <label>: N rows`
--- when there is no scope, marked when the act stopped on an error. Nothing
--- when bulkLeave returned nil (nested, or the profile handler logs).
local function logAct(n, failed, act, scope)
    if not (n and NS.State and NS.State.debug and NS.Debug) then return end
    local label = scope ~= nil and (tostring(act) .. " " .. tostring(scope)) or tostring(act)
    NS.Debug("Set", "%s: %d rows%s", label, n, failed and STOPPED or "")
end

--- Run `fn` as one bulk act named `label`, with the per-row [Set] line muted,
--- and close it even if `fn` raised: the act's one line still goes out, marked,
--- and then the error is re-raised unchanged. Returns the rows it changed when
--- it was the outermost act, and nil when it was nested (the outer act logs).
--- Helpers.SetRows is the caller, when it is handed a summary.
function Helpers.MuteSetLog(fn, label)
    bulkEnter()
    local ok, err = pcall(fn)
    local n, failed = bulkLeave(false, not ok)
    logAct(n, failed, label)
    if not ok then error(err, 0) end
    return n
end

--- LibKa0s' bulk bracket (Options minor 16, Slash minor 8), on the same record.
--- The library calls BulkBegin before a reset walk writes its first row and
--- BulkEnd once after it, always, even when a row raised (the raised value is
--- the fourth argument), so the mute cannot stick. The library's own `count`
--- (the third argument) is every row applyDefault returned, rows already at
--- their default included, so it is not the §10 N and is not what the line
--- carries. The degraded Reset all in settings/OptionsSetup.lua drives the same
--- pair by hand.
function Helpers.BulkBegin()
    bulkEnter()
end

function Helpers.BulkEnd(act, scope, _, err, info)
    local n, failed = bulkLeave(info and info.profileReset, err ~= nil)
    logAct(n, failed, act, scope)
end

-- ---------------------------------------------------------------------
-- The profile reset's count
-- ---------------------------------------------------------------------
--
-- A profile reset is logged ONCE, by Database:OnProfileChanged, as
-- `[Set] reset profile '<name>' to defaults (N rows)` (debug-logging-§10). N is
-- the rows the reset actually changes, and only a caller that runs BEFORE the
-- reset can count them: the profile rows (not sessionOnly, not the AceDBOptions
-- page) whose stored value differs from the row's default. Both Reset all paths
-- in settings/OptionsSetup.lua reset through ResetProfileCounted, which stashes
-- the count for the handler to take once. A reset driven straight at the db
-- (AceDBOptions' Reset Profile, a `/run`) stashes nothing, and the handler logs
-- the line with no count rather than a wrong one.
local pendingResetCount

--- The handler's count, taken once. nil when the reset did not come through
--- ResetProfileCounted.
function NS.Settings.ConsumeResetCount()
    local n = pendingResetCount
    pendingResetCount = nil
    return n
end

local function countChangedProfileRows()
    local n = 0
    for _, def in ipairs(NS.Settings.Schema) do
        if def.path and not def.sessionOnly and def.panel ~= "profiles"
            and not sameValue(Helpers.Get(def.path), def.default) then
            n = n + 1
        end
    end
    return n
end

--- Reset `db`'s active profile, with the count of rows it changes stashed for
--- the profile handler. The stash is cleared when the reset returns or raises,
--- so a count the handler never took cannot be claimed by a later reset.
function Helpers.ResetProfileCounted(db)
    pendingResetCount = countChangedProfileRows()
    local ok, err = pcall(db.ResetProfile, db)
    pendingResetCount = nil
    if not ok then error(err, 0) end
end

local function logSet(path, value)
    if not (NS.State and NS.State.debug) then return end   -- gate first
    if bulkBefore then return end   -- a bulk act logs its own one line
    setSeq = setSeq + 1
    pendingSet[path] = { value, setSeq }
    local gen = (setGen[path] or 0) + 1
    setGen[path] = gen
    _G.C_Timer.After(SET_LOG_DEBOUNCE, function()
        if setGen[path] ~= gen then return end   -- superseded by a later write
        local p = pendingSet[path]
        pendingSet[path] = nil
        setGen[path] = nil
        if p and NS.State and NS.State.debug then
            NS.Debug("Set", "%s = %s", tostring(path), fmtSetValue(p[1]))
        end
    end)
end

function Helpers.Set(path, section, value)
    local session = SESSION_PATHS[path]
    if session then
        -- No FireConfigChanged: nothing on the bus renders session state, and a
        -- CONFIG_CHANGED here would fan a full re-apply out over a window that
        -- opened.
        if bulkBefore and bulkBefore[path] == nil then bulkBefore[path] = { session.get() } end
        session.set(value)
        logSet(path, value)
        return
    end
    local parent, key = Resolve(path)
    if not parent then return end
    if bulkBefore and bulkBefore[path] == nil then bulkBefore[path] = { parent[key] } end
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

--- Stamp a composed block with this addon's own row fields and append it.
---
--- The composers (libs/LibKa0s/OptionsCompose.lua) return ORDINARY schema rows
--- carrying `page`, `group`, `subgroup` and `order`. This addon keys its rows
--- `panel` + `section` -- and, on the three per-unit pages, `unit` -- so one
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
        NS.Settings.Schema[#NS.Settings.Schema + 1] = row
    end
    return rows or {}
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