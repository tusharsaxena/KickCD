local _, NS = ...

-- settings/SchemaSetup.lua — wires the addon into LibKa0s-Schema-1.0.
--
-- The settings schema's RUNTIME: the path index, the single write seam
-- (architecture-§5), the bulk bracket that makes a sweep one debug line
-- (debug-logging-§10), the profile reset's changed-row count and the load-time
-- shape check. All of it is libs/LibKa0s/Schema.lua's; this file keeps only
-- what is genuinely this addon's:
--
--   * where a stored row lives (db.profile, always -- the two rows stored
--     anywhere else carry their own get/set, wired in settings/General.lua);
--   * what a write announces (CONFIG_CHANGED with the row's own `section`, once
--     per distinct section for a batch);
--   * the debounced `[Set]` line a color drag collapses into;
--   * the two paths the host's own verbs write with no row on a library-less
--     load (NS.Settings.WRITE_THROUGH);
--   * the degradation stub, below.
--
-- NS.Settings.Store IS the instance. Every member is a closure and is
-- dot-called (Store.Set(path, v)), so the Options and Slash descriptors and the
-- host's own callers take them as values.
--
-- TOC POSITION: the FIRST line of the settings block. It creates
-- NS.Settings.Schema (the rows array) and NS.Settings.Store, and the page files
-- reach Store.AddRows at file load through their own `add` and through
-- Helpers.AddComposed; settings/Slash.lua and settings/OptionsSetup.lua take
-- Store members into their descriptors at load.

NS.Settings = NS.Settings or {}
NS.Settings.Schema = NS.Settings.Schema or {}
local Schema = NS.Settings.Schema

-- ---------------------------------------------------------------------
-- The two paths the host verbs write with no row (options-ui-§1 route (a))
-- ---------------------------------------------------------------------
--
-- `enabled` and `locked` are COMPOSED rows: LibKa0s-Options-1.0's Master
-- controls block declares them, so a load where that composer is absent has no
-- row for either. The host verbs that write them -- `/kcd lock`, `unlock`,
-- `toggle` and the launcher's click, all through core/KickCD.lua's setLocked,
-- and the master switch -- still run there. The list is handed to the live
-- instance and to the stub below, one table for both, so a degraded verb lands
-- in the store instead of being refused by the seam. A listed path that HAS a
-- row takes the row, so on a full load nothing changes.
NS.Settings.WRITE_THROUGH = { "enabled", "locked" }

-- ---------------------------------------------------------------------
-- The debounced [Set] line (debug-logging-§10)
-- ---------------------------------------------------------------------
--
-- One [Set] line per settled change. Color/slider commits reach the seam on
-- every throttled drag tick (~20/sec), so a per-path TRAILING debounce
-- collapses a whole drag/gesture to a single line carrying the final value,
-- emitted SET_LOG_DEBOUNCE after the last write. Each write bumps a per-path
-- generation token and schedules a fresh timer; only the timer whose token is
-- still current fires, so earlier writes in the gesture are superseded rather
-- than each producing their own line. String-building stays behind the debug
-- gate (§4 zero-alloc): the library asks debugEnabled before it formats, and the
-- extra per-tick timers only exist while debug is on.
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

local function debugOn() return NS.State ~= nil and NS.State.debug == true end

--- Log every debounced [Set] line still waiting, now, in the order they were
--- written, and retire their timers. A bulk act calls this as it opens, and any
--- other line calls it before it prints: an act's own line is synchronous, so a
--- line left pending from a write just before it would otherwise print AFTER the
--- act, carrying a value the act has since replaced. Each path's generation is
--- bumped rather than cleared, so the retired timer cannot match a later write
--- that starts counting again.
local function flushPendingSets()
    if next(pendingSet) == nil then return end
    local order = {}
    for path, p in pairs(pendingSet) do order[#order + 1] = { path = path, value = p[1], seq = p[2] } end
    table.sort(order, function(a, b) return a.seq < b.seq end)
    for _, e in ipairs(order) do
        pendingSet[e.path] = nil
        setGen[e.path] = (setGen[e.path] or 0) + 1
        if debugOn() and NS.Debug then
            NS.Debug("Set", "%s = %s", tostring(e.path), e.value)
        end
    end
end
NS.Settings.FlushPendingSets = flushPendingSets

--- The single-write line, debounced per path. `shown` is already formatted:
--- the library ran `format` before handing it over.
local function logSet(path, shown)
    setSeq = setSeq + 1
    pendingSet[path] = { shown, setSeq }
    local gen = (setGen[path] or 0) + 1
    setGen[path] = gen
    _G.C_Timer.After(SET_LOG_DEBOUNCE, function()
        if setGen[path] ~= gen then return end   -- superseded by a later write
        local p = pendingSet[path]
        pendingSet[path] = nil
        setGen[path] = nil
        if p and debugOn() and NS.Debug then
            NS.Debug("Set", "%s = %s", tostring(path), p[1])
        end
    end)
end

-- ---------------------------------------------------------------------
-- The announce
-- ---------------------------------------------------------------------

local function fire(section)
    local H = NS.Settings.Helpers
    if H and H.FireConfigChanged then
        H.FireConfigChanged(section)
    elseif NS.SendMessage and NS.MSG then
        NS:SendMessage(NS.MSG.CONFIG_CHANGED, { section = section })
    end
end

--- The section a write announces, or false when it announces nothing.
---
--- A session row and a row with its own storage send nothing, as they never
--- did: nothing on the bus renders the console window or the minimap button,
--- and a CONFIG_CHANGED there would fan a full re-apply out over a checkbox. A
--- written-through path has no row to carry a section, and both it can be are
--- the General page's.
local function sectionOf(row)
    if row.sessionOnly or type(row.get) == "function" then return false end
    return row.section or (row.writeThrough and "general") or nil
end

--- THE MASTER SWITCH ON A ROW-LESS LOAD. With the row present its own onChange
--- (settings/General.lua) takes the hold, before this announce runs; a
--- written-through `enabled` runs no onChange, so the reaction is dispatched
--- here instead -- still BEFORE the announcement, because a module that
--- re-rendered first and stood down second would draw one frame of an addon
--- that is already off.
local function holdFor(row, path)
    if row.writeThrough and path == "enabled" and NS.RefreshEnabledHold then
        NS.RefreshEnabledHold()
    end
end

local function announce(row, path)
    local section = sectionOf(row)
    if section == false then return end
    holdFor(row, path)
    fire(section)
end

-- A batch holds a nil section under this sentinel: a bare nil cannot sit in an
-- order list (`order[#order + 1] = nil` appends nothing), and a nil section is
-- still an announcement.
local NIL_SECTION = {}

--- A batch announces each distinct section ONCE, in first-seen order: Copy
--- styling's hundred-odd rows are one CONFIG_CHANGED per section, not one per
--- row.
local function announceBatch(writes)
    local seen, order = {}, {}
    for _, w in ipairs(writes) do
        local section = sectionOf(w.row)
        if section ~= false then
            holdFor(w.row, w.path)
            local key = section == nil and NIL_SECTION or section
            if not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _, key in ipairs(order) do
        if key == NIL_SECTION then fire(nil) else fire(key) end
    end
end

-- ---------------------------------------------------------------------
-- The degradation stub (LibKa0s docs/api/Schema/version-2-docs.md,
-- "The degradation stub")
-- ---------------------------------------------------------------------
--
-- A DELIBERATE, DOCUMENTED DUPLICATION, copied from that repo's
-- tests/test_schema.lua `referenceStub` and trimmed to what this addon calls.
-- This major is reached by host writers that never needed Options or Slash:
-- `/kcd lock`, `unlock` and `toggle`, the launcher's click and the degraded
-- Options stub's Reset all all write through NS.Settings.Store, and
-- slash-commands-§1 keeps those verbs working without the library. A stub that
-- refused `Set` would leave every one of them dead on exactly the load it
-- exists to survive (anti-pattern #56, shape 2). So it is WRITE-COMPLETING and
-- LOG-SILENT: reads, writes, the reaction, the announce and the sweep veto all
-- work; the `[Set]` line, the bracket's tally and the profile reset's count do
-- not, because the degraded DebugLog stub discards those lines anyway.
--
-- Its refusals are this addon's own words (locales/enUS.lua), never a copy of
-- the library's STRINGS. tests/test_surface_parity.lua pins its surface against
-- a live instance and its library half against the major by name.
local L = NS.L or setmetatable({}, { __index = function(_, k) return k end })

local stubLib = {}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- The primitives, lib level: a host whose own code calls them keeps one seam.
function stubLib.SplitPath(path)
    local parts = {}
    if path ~= nil then
        for seg in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = seg end
    end
    return parts
end

local function partsOf(p) return type(p) == "table" and p or stubLib.SplitPath(p) end

function stubLib.Read(root, p, first)
    local parts, node = partsOf(p), root
    first = first or 1
    if type(root) ~= "table" or #parts < first then return nil end
    for i = first, #parts do
        if type(node) ~= "table" then return nil end
        node = node[parts[i]]
    end
    return node
end

function stubLib.Write(root, p, value, first)
    local parts, node = partsOf(p), root
    first = first or 1
    if type(root) ~= "table" or #parts < first then return end
    for i = first, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
end

function stubLib.SameValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not stubLib.SameValue(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The instance's read half and its registry: rows held by reference, a linear
-- first-match FindRow, Reindex a no-op.
local function addRegistry(S, d)
    local rows = d.rows
    function S.AllRows() return rows end
    function S.FindRow(path)
        if type(path) ~= "string" then return nil end
        for _, row in ipairs(rows) do
            if type(row) == "table" and row.path == path then return row end
        end
    end
    function S.AddRows(list, at)
        if type(list) ~= "table" then return 0 end
        at = type(at) == "number" and math.floor(at) or #rows + 1
        if at > #rows + 1 then at = #rows + 1 elseif at < 1 then at = 1 end
        for i, row in ipairs(list) do table.insert(rows, at + i - 1, row) end
        return #list
    end
    function S.Reindex() end
end

local function resolver(d)
    return function(parts, id)
        if type(d.resolveRoot) ~= "function" then return nil end
        return d.resolveRoot(parts, id)
    end
end

-- The write seam's order without its log and tally: refuse (a listed
-- writeThrough path is not refused), validate, normalize, the missing root.
-- Answers a plan, or nil and the refusal; Set and SetMany share it.
local function preparer(S, resolve, through)
    local function refuse(path, why) return nil, L["Invalid value for %s"]:format(path), why end
    return function(path, value, id)
        local row = S.FindRow(path) or through[path]
        if not row then return nil, L["Setting not found: %s"]:format(tostring(path)) end
        local w = { row = row, path = path, value = value, rid = id }
        w.stored = type(row.set) ~= "function" and not row.sessionOnly
        if w.stored then
            w.parts = stubLib.SplitPath(path)
            local r, f, got = resolve(w.parts, id)
            if type(r) == "table" then w.root, w.first = r, f end
            if got ~= nil then w.rid = got end
        end
        if type(row.validate) == "function" then
            local ok, why = row.validate(value, w.rid)
            if not ok then return refuse(path, why) end
        end
        if type(row.normalize) == "function" then
            local out, why = row.normalize(value, w.rid)
            if out == nil then return refuse(path, why) end
            w.value = out
        end
        if w.stored and not w.root then
            return nil, L["Setting has nowhere to be stored yet: %s"]:format(path)
        end
        return w
    end
end

local function store(w)
    if type(w.row.set) == "function" then
        w.row.set(w.value)
    elseif w.stored then
        stubLib.Write(w.root, w.parts, copy(w.value), w.first)
    end
end

local function react(w)
    if type(w.row.onChange) == "function" then w.row.onChange(w.value, w.rid) end
end

local function addWrites(S, d, prepare)
    function S.Set(path, value, id)
        local w, err, why = prepare(path, value, id)
        if not w then return false, err, why end
        store(w)
        react(w)
        if type(d.announce) == "function" then d.announce(w.row, path, w.value, w.rid) end
        return true
    end
    -- All or nothing, as the library's: every entry prepared, then every store,
    -- every onChange, and one announceBatch (or announce per write). `act` is
    -- not read -- there is no line to make one of.
    function S.SetMany(entries, opts)
        local id = type(opts) == "table" and opts.instanceId or nil
        local ws = {}
        for i, e in ipairs(type(entries) == "table" and entries or {}) do
            if type(e) ~= "table" then e = {} end
            local w, err, why = prepare(e.path, e.value, id)
            if not w then return false, err, why, i end
            ws[i] = w
        end
        for _, w in ipairs(ws) do store(w) end
        for _, w in ipairs(ws) do react(w) end
        if #ws == 0 then return true end
        if type(d.announceBatch) == "function" then
            d.announceBatch(ws, ws[1].rid)
        elseif type(d.announce) == "function" then
            for _, w in ipairs(ws) do d.announce(w.row, w.path, w.value, w.rid) end
        end
        return true
    end
    function S.Default(path)
        local row = S.FindRow(path)
        return row and copy(row.default)
    end
end

-- The bracket keeps its depth, because ApplyDefault's sweep veto reads it; it
-- counts nothing and logs nothing.
local function addBracket(S, d)
    local depth = 0
    function S.ApplyDefault(row, id)
        if type(row) ~= "table" or type(row.path) ~= "string" or row.default == nil then return false end
        local exempt = d.resetExempt
        if depth > 0 and type(exempt) == "table" and exempt[row.path] then return false end
        return S.Set(row.path, copy(row.default), id)
    end
    function S.BulkBegin() depth = depth + 1 end
    function S.BulkEnd() if depth > 0 then depth = depth - 1 end end
    function S.BulkRun(act, scope, fn)
        S.BulkBegin(act, scope)
        local ok, err = pcall(fn, { profileReset = false })
        S.BulkEnd(act, scope)
        if not ok then error(err, 0) end
    end
    function S.BulkAdd() end
    function S.InBulk() return depth > 0 end
    function S.CountOffDefault() return 0 end
    function S.ResetCounted(fn) fn() end
    function S.ConsumeResetCount() return nil end
    function S.Validate()
        if type(d.print) == "function" then
            d.print(NS.LIBKA0S_MISSING .. ", so the settings schema was not checked.")
        end
        return 0, 0, 0
    end
end

-- Colon-called, like every major's constructor; the stub library is `self`.
function stubLib.New(_, d)
    local S = {}
    local through = {}
    for _, p in ipairs(type(d.writeThrough) == "table" and d.writeThrough or {}) do
        if type(p) == "string" and p ~= "" then through[p] = { path = p, writeThrough = true } end
    end
    local resolve = resolver(d)
    addRegistry(S, d)
    function S.Get(path, id)
        local row = S.FindRow(path)
        if row and type(row.get) == "function" then return row.get(id) end
        if type(path) ~= "string" or (row and row.sessionOnly) then return nil end
        local parts = stubLib.SplitPath(path)
        local root, first = resolve(parts, id)
        if type(root) ~= "table" then return nil end
        return stubLib.Read(root, parts, first)
    end
    addWrites(S, d, preparer(S, resolve, through))
    addBracket(S, d)
    return S
end

-- Published on both paths, so tests/test_surface_parity.lua can hold it to the
-- major by name on a load where the library is present.
NS.Settings.HostSchemaStub = stubLib

-- ---------------------------------------------------------------------
-- The instance
-- ---------------------------------------------------------------------

local SchemaLib = LibStub and LibStub("LibKa0s-Schema-1.0", true) or stubLib
NS.Settings.SchemaLib = SchemaLib

NS.Settings.Store = SchemaLib:New({
    -- The live array, never copied: the page files AddRows into it.
    rows = Schema,
    -- Every stored row lives in the active profile. `, 1` rather than a reason
    -- before the db exists: a non-table root is "nowhere, now", and the
    -- library reads only a STRING second value as the refusal's text.
    resolveRoot = function() return NS.db and NS.db.profile, 1 end,
    writeThrough = NS.Settings.WRITE_THROUGH,
    announce = announce,
    announceBatch = announceBatch,
    -- The single-write line is the debounced one; any other line (a bracket's
    -- one `[Set] <act> <scope>: N rows`) prints now, after whatever is still
    -- pending, so the log reads in the order things happened.
    debug = function(tag, fmt, ...)
        if tag == "Set" and fmt == "%s = %s" then return logSet(...) end
        flushPendingSets()
        if NS.Debug then NS.Debug(tag, fmt, ...) end
    end,
    debugEnabled = debugOn,
    format = function(_, value) return fmtSetValue(value) end,
    print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
    -- The one row no SWEEP may touch (launcher-§3): whether the minimap button
    -- shows is a per-installation display preference, like the position the
    -- player dragged it to. The library honors this only while a bracket is
    -- open, so the General page's Defaults and Reset all leave it alone while
    -- `/kcd reset global.minimap.shown`, one row named out loud, still works.
    resetExempt = { ["global.minimap.shown"] = true },
})
