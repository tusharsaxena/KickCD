-- tests/test_settings_log.lua — settings-change capture at Helpers.Set (§10)
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Helpers.Set logs one debounced [Set] line with the settled value", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()

    -- Two rapid writes to the same path within the debounce window. NOTE:
    -- with the full lifecycle enabled (T.load(true, true)), a "general"
    -- CONFIG_CHANGED also triggers Cooldowns:Rebuild(), which logs its own
    -- synchronous "[Cooldowns] rebuild ..." line on every Set call — that's
    -- pre-existing, unrelated module behavior, not the debounced [Set] line
    -- under test here. Assertions below key off the "[Set]"-tagged line
    -- specifically (via FindLine) rather than raw BufferSize()/LastLine(),
    -- so this suite stays robust to that orthogonal noise.
    Helpers.Set("locked", "general", false)
    Helpers.Set("locked", "general", true)
    assertTrue(not NS.DebugLog:FindLine("[Set]"), "nothing [Set]-tagged logs before the debounce fires")

    inst.mocks.__flushTimers()
    assertTrue(NS.DebugLog:FindLine("[Set] locked = true"), "settled value is logged after the debounce fires")
    assertTrue(not NS.DebugLog:FindLine("[Set] locked = false"),
        "burst collapses to one [Set] line; the earlier value must not appear")
end)

test("Helpers.Set formats an RGBA table compactly", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Helpers.Set("units.target.castbar.interruptible.barColor", "castbar", { 1, 0.5, 0, 1 })
    inst.mocks.__flushTimers()
    assertTrue(NS.DebugLog:FindLine("{1,0.5,0,1}"), "RGBA renders as {r,g,b,a}")
end)

test("ResetIconPosition restores units.target.anchors.icons to the default (Task 8 fix)", function()
    local inst = T.load(true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers

    -- Simulate the user having dragged the target grid away from default.
    NS.db.profile.units.target.anchors.icons = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 400, y = -300 }

    Helpers.ResetIconPosition()

    local d = NS.DEFAULT_PROFILE.units.target.anchors.icons
    local a = NS.db.profile.units.target.anchors.icons
    assertEqual(a.point, d.point, "point restored to default")
    assertEqual(a.relativePoint, d.relativePoint, "relativePoint restored to default")
    assertEqual(a.x, d.x, "x restored to default")
    assertEqual(a.y, d.y, "y restored to default")
end)

test("ResetIconPosition writes nothing when the defaults tree is absent (M4-18 / KICKCD-R-08)", function()
    -- RED before M4-18. Helpers.ResetIconPosition's header promises the default
    -- coordinate lives in exactly one place, DEFAULT_PROFILE.units.target.anchors
    -- .icons, "so we don't duplicate magic numbers across UI / CLI / Database
    -- layers" — and then the line under it duplicated the number anyway, and got
    -- it wrong: the fallback wrote y = -180 where defaults/Profile.lua ships
    -- y = +120. 300 px apart and opposite in sign, so a fallback that fired would
    -- have parked the grid below screen center instead of above it.
    --
    -- The branch cannot be reached in a shipping install — defaults/Profile.lua is
    -- a TOC-loaded file, so NS.DEFAULT_PROFILE is always there — which is exactly
    -- why nothing caught the wrong number for as long as it sat there. Taking the
    -- table away by hand is the only way to pin the contract. The right answer for
    -- a reset with no defaults to reset TO is to do nothing at all: leave the
    -- stored anchor where the user dragged it and publish nothing.
    local inst = T.load(true)
    local NS = inst.NS
    local Helpers = NS.Settings.Helpers

    NS.db.profile.units.target.anchors.icons =
        { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 400, y = -300 }
    NS.DEFAULT_PROFILE = nil

    local fired = false
    local busTarget = NS.NewBusTarget()
    busTarget:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED", function() fired = true end)
    Helpers.ResetIconPosition()
    busTarget:UnregisterMessage("Ka0s_KickCD_CONFIG_CHANGED")

    local a = NS.db.profile.units.target.anchors.icons
    assertEqual(a.point, "TOPLEFT", "no defaults tree, no write: the dragged point survives")
    assertEqual(a.x, 400, "no defaults tree, no write: the dragged x survives")
    assertEqual(a.y, -300, "no defaults tree, no write: the dragged y survives, and is not -180")
    assertTrue(not fired, "and nothing is published, because nothing changed")
end)

-- ---------------------------------------------------------------------------
-- Bulk resets (debug-logging-§10): ONE [Set] line per act, never one per row
-- ---------------------------------------------------------------------------

--- Every [Set]-tagged console line, read after the debounce has fired, because
--- a per-row line is a debounced one and would otherwise be missed.
local function setLines(inst)
    inst.mocks.__flushTimers()
    local out = {}
    for line in (inst.NS.DebugLog:CopyText() .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("[Set]", 1, true) then out[#out + 1] = line end
    end
    return out
end

local function debugOn(inst)
    inst.mocks.__flushTimers()
    inst.NS.State.debug = true
    inst.NS.DebugLog:Clear()
end

--- Move exactly `n` of the profile's boolean rows off their default through the
--- raw seam, before the console is watched. A profile reset's count is the rows
--- whose stored value it changes, so these are the rows it should report.
local function dirtyRows(NS, n)
    local k = 0
    for _, def in ipairs(NS.Settings.Schema) do
        if k < n and def.type == "bool" and def.path and not def.sessionOnly and def.panel ~= "profiles" then
            NS.Settings.Helpers.Set(def.path, def.section, not def.default)
            k = k + 1
        end
    end
    assertEqual(k, n, "sanity: the schema has " .. n .. " boolean profile rows to move")
end

--- Every [Set] line a degraded load logs: it has no console, so NS.Debug is
--- replaced and read directly.
local function captureSet(NS)
    local set = {}
    NS.Debug = function(tag, fmt, ...)
        if tag == "Set" then set[#set + 1] = string.format(fmt, ...) end
    end
    return set
end

--- Move up to two of `page`'s boolean rows off their default through the raw
--- seam, before the console is watched. Returns how many it moved.
local function dirty(H, page)
    local k = 0
    for _, def in ipairs(H.SchemaForPanel(page)) do
        if k < 2 and def.type == "bool" and not def.sessionOnly then
            H.Set(def.path, def.section, not def.default)
            k = k + 1
        end
    end
    return k
end

-- The four schema pages whose Defaults button is LibKa0s' RestoreDefaults, and
-- the rows each one walks.
for _, case in ipairs({ { "castbar", 110 }, { "icons", 78 }, { "label", 32 }, { "general", 9 } }) do
    local page, rows = case[1], case[2]
    test("the " .. page .. " page's Defaults logs ONE [Set] reset line counting the rows it changed",
    function()
        -- red under: a descriptor with no bulkBegin/bulkEnd, where every row the
        -- page resets logs its own [Set] <path> = <value> line; or a line that
        -- carries the library's count, every row walked (debug-logging-§10's N is
        -- the rows the act actually changed).
        local inst = T.load(true, true)
        local H = inst.NS.Settings.Helpers
        assertEqual(#H.SchemaForPanel(page), rows, "sanity: the " .. page .. " page walks " .. rows .. " rows")
        local moved = dirty(H, page)
        assertTrue(moved > 0, "sanity: the " .. page .. " page has a boolean row to move")
        debugOn(inst)
        H.RestoreDefaults(page)
        local lines = setLines(inst)
        inst.NS.State.debug = false
        assertEqual(#lines, 1, "one line for the whole page: " .. table.concat(lines, " | "))
        assertTrue(lines[1]:find("[Set] reset " .. page .. ": " .. moved .. " rows", 1, true) ~= nil,
            "it names the act, the page and the rows it changed (" .. moved .. "): " .. lines[1])
    end)
end

test("a Defaults on a page already at its defaults logs 0 rows, and no per-row line", function()
    -- The line is kept at N = 0 rather than dropped, so the press is still on
    -- the record.
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    debugOn(inst)
    H.RestoreDefaults("castbar")
    local lines = setLines(inst)
    inst.NS.State.debug = false
    assertEqual(#lines, 1, "one line for the whole page: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset castbar: 0 rows", 1, true) ~= nil,
        "110 rows walked, none changed: " .. lines[1])
end)

test("nested bulk acts log ONE line, the outermost's, with every level's rows", function()
    -- red under: each level logging as it closes, or the outer line counting
    -- only its own writes.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local moved = dirty(H, "general") + dirty(H, "label")
    debugOn(inst)
    H.BulkBegin("reset", "all")
    H.RestoreDefaults("general")
    H.RestoreDefaults("label")
    H.BulkEnd("reset", "all", 0, nil, { profileReset = false })
    local lines = setLines(inst)
    assertEqual(#lines, 1, "one line for the whole act: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset all: " .. moved .. " rows", 1, true) ~= nil,
        "the outer act's line, with both pages' rows (" .. moved .. "): " .. lines[1])

    -- A level that reset the whole profile silences the act: the profile
    -- handler's line is the only one.
    NS.DebugLog:Clear()
    H.BulkBegin("reset", "outer")
    H.ResetAll()
    H.BulkEnd("reset", "outer", 0, nil, { profileReset = false })
    lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the whole act: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset profile 'Default' to defaults", 1, true) ~= nil,
        "and it is the handler's: " .. lines[1])
end)

test("the per-row [Set] line comes back after a Defaults, even one whose row raised", function()
    -- red under: a mute that is not released at bulkEnd, or released only when
    -- the walk returns normally.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    debugOn(inst)
    H.RestoreDefaults("general")
    H.Set("locked", "general", false)
    local lines = setLines(inst)
    assertEqual(#lines, 2, "the reset's line, then the single write's: " .. table.concat(lines, " | "))
    assertTrue(lines[2]:find("[Set] locked = false", 1, true) ~= nil, "a write after the reset logs: " .. lines[2])

    NS.DebugLog:Clear()
    local real = H.SetAndRefresh
    H.SetAndRefresh = function() error("boom", 0) end
    local ok, err = pcall(H.RestoreDefaults, "general")
    H.SetAndRefresh = real
    assertTrue(not ok and err == "boom", "the row's error reaches the caller unchanged: " .. tostring(err))
    H.Set("locked", "general", true)
    lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 2, "the aborted reset's line, then the write's: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset general: 0 rows (stopped by an error)", 1, true) ~= nil,
        "the aborted reset counts only what it wrote, and says it stopped: " .. lines[1])
    assertTrue(lines[2]:find("[Set] locked = true", 1, true) ~= nil, "and the mute did not stick: " .. lines[2])
end)

test("Reset all logs ONE line in total, the profile handler's, counting the rows it changed", function()
    -- red under: OnProfileReset worded as a switch, a sessionOnly row's own
    -- [Set] line, a bulkEnd that adds "[Set] reset all: N rows" beside it, or a
    -- count that is the schema's size (every row the profile stores) rather than
    -- the rows not at their default just before the reset.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    debugOn(inst)
    H.ResetAll()
    local lines = setLines(inst)
    assertEqual(#lines, 1, "one line for the whole reset: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset profile 'Default' to defaults (0 rows)", 1, true) ~= nil,
        "a profile already at its defaults changes no row: " .. lines[1])
    assertTrue(not NS.DebugLog:FindLine("[Profile] switched"), "a reset is not reported as a switch")

    dirtyRows(NS, 3)
    debugOn(inst)
    H.ResetAll()
    lines = setLines(inst)
    assertEqual(#lines, 1, "one line for the whole reset: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset profile 'Default' to defaults (3 rows)", 1, true) ~= nil,
        "three rows off their default, three rows reset: " .. lines[1])

    H.Set("locked", "general", false)
    lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 2, "and the mute is released afterwards: " .. table.concat(lines, " | "))
end)

test("with LibKa0s absent, Reset all logs exactly one line, the profile handler's, with the rows it changed",
function()
    -- The degraded stub walks the sessionOnly rows itself and then resets the
    -- profile. red under: that walk logging its rows, the handler's line worded
    -- as a switch, or a count that is the degraded schema's size.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local NS = inst.NS
    local set = captureSet(NS)
    inst.mocks.__flushTimers()
    dirtyRows(NS, 3)
    NS.State.debug = true
    NS.Settings.Helpers.RestoreAllDefaults()
    inst.mocks.__flushTimers()
    NS.Settings.Helpers.Set("locked", "general", false)
    inst.mocks.__flushTimers()
    NS.State.debug = false
    assertEqual(#set, 2, "the handler's line, then the write after it: " .. table.concat(set, " | "))
    assertEqual(set[1], "reset profile 'Default' to defaults (3 rows)", "worded by the event, with the rows")
    assertEqual(set[2], "locked = false", "and the mute is released afterwards")
end)

test("with LibKa0s absent, a Reset all that reset no profile logs the bracket's own line", function()
    -- red under: the stub telling the bracket it reset the profile before it
    -- knew, so a missing db (or a reset that raised) left no line at all.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local set = captureSet(NS)
    inst.mocks.__flushTimers()
    NS.State.debug = true
    local real = NS.db.ResetProfile
    NS.db.ResetProfile = nil
    H.RestoreAllDefaults()
    inst.mocks.__flushTimers()
    assertEqual(#set, 1, "one line, since no handler ran: " .. table.concat(set, " | "))
    assertEqual(set[1], "reset all: 0 rows", "the act's own line")

    -- A reset that raised: the same line, marked, once; the error reaches the
    -- caller; and the mute is released.
    set[1] = nil
    NS.db.ResetProfile = function() error("boom", 0) end
    local ok, err = pcall(H.RestoreAllDefaults)
    NS.db.ResetProfile = real
    assertTrue(not ok and err == "boom", "the reset's error reaches the caller unchanged: " .. tostring(err))
    H.Set("locked", "general", false)
    inst.mocks.__flushTimers()
    NS.State.debug = false
    assertEqual(#set, 2, "the marked line, then the write after it: " .. table.concat(set, " | "))
    assertEqual(set[1], "reset all: 0 rows (stopped by an error)", "the act says it stopped")
    assertEqual(set[2], "locked = false", "and the mute is released afterwards")
end)

test("a profile reset driven straight at the db logs its one line with no count", function()
    -- AceDBOptions' Reset Profile button and a `/run` call db:ResetProfile()
    -- directly, so nothing counted the rows before the profile was replaced.
    -- red under: the handler printing the schema's size as the count.
    local inst = T.load(true, true)
    local NS = inst.NS
    dirtyRows(NS, 3)
    debugOn(inst)
    NS.db:ResetProfile()
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the reset: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset profile 'Default' to defaults", 1, true) ~= nil,
        "worded by the event: " .. lines[1])
    assertTrue(not lines[1]:find("rows", 1, true), "and no count, since none was taken: " .. lines[1])
end)

test("a count taken for a reset that raised does not leak into the next reset", function()
    -- red under: a stash cleared only by the handler, which a reset that raised
    -- before firing OnProfileReset never reached.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    dirtyRows(NS, 3)
    debugOn(inst)
    local real = NS.db.ResetProfile
    NS.db.ResetProfile = function() error("boom", 0) end
    local ok, err = pcall(H.ResetAll)
    NS.db.ResetProfile = real
    assertTrue(not ok and err == "boom", "the reset's error reaches the caller unchanged: " .. tostring(err))
    local lines = setLines(inst)
    assertEqual(#lines, 1, "the failed act logs once: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset all: 0 rows (stopped by an error)", 1, true) ~= nil,
        "no handler ran, so the bracket logs, marked: " .. lines[1])

    NS.DebugLog:Clear()
    NS.db:ResetProfile()
    lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the direct reset: " .. table.concat(lines, " | "))
    assertTrue(not lines[1]:find("rows", 1, true), "the failed reset's count is gone: " .. lines[1])
end)

test("a profile copy logs one [Set] copied line and announces the profile that is active", function()
    -- AceDB's OnProfileCopied hands the SOURCE profile as its third argument.
    -- red under: the one handler wording every event as a switch, and passing
    -- that source name on as the newly active profile's key.
    local inst = T.load(true, true)
    local NS = inst.NS
    debugOn(inst)
    local announced
    local bus = NS.NewBusTarget()
    bus:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", function(_, payload)
        announced = payload and payload.newProfileKey
    end)
    NS.Database:OnProfileChanged("OnProfileCopied", NS.db, "Main")
    bus:UnregisterMessage("Ka0s_KickCD_PROFILE_CHANGED")
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the copy: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] copied profile 'Main' \226\134\146 'Default'", 1, true) ~= nil,
        "it names both profiles: " .. lines[1])
    assertTrue(not NS.DebugLog:FindLine("[Profile] switched"), "a copy is not reported as a switch")
    assertEqual(announced, "Default", "the copy made no other profile active")
end)

test("the schema CLI's resetall, handed the same bracket, logs one [Set] reset all line", function()
    -- Nothing in KickCD routes to Sl:CliResetAll (`/kcd resetall` is a host verb
    -- that reaches the Options walk), but the Slash descriptor takes the same
    -- pair, so a future route cannot bring the per-row lines back.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    H.Set("locked", "general", not H.FindSchema("locked").default)
    debugOn(inst)
    NS.Slash.cli:CliResetAll()
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 1, "one line for the whole walk: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] reset all: 1 rows", 1, true) ~= nil,
        "act, scope and the one row it changed: " .. lines[1])
end)

test("a write still pending when an act opens logs BEFORE the act's line, with its own value", function()
    -- red under: the debounced line firing after the act's synchronous one, so
    -- the log reads the act first and then a value the act already replaced.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local def = H.FindSchema("locked")
    debugOn(inst)
    H.Set("locked", "general", not def.default)
    H.RestoreDefaults("general")
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 2, "the write's line, then the act's: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] locked = " .. tostring(not def.default), 1, true) ~= nil,
        "the write comes first, with the value it wrote: " .. lines[1])
    assertTrue(lines[2]:find("[Set] reset general: 1 rows", 1, true) ~= nil,
        "then the act, which changed that row back: " .. lines[2])
end)

test("a bulk copy that raises logs its one line once, marked, releases the mute and re-raises", function()
    -- red under: SetRows logging only after MuteSetLog returned, so a raising
    -- row lost the act's line entirely.
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local def = H.FindSchema("locked")
    debugOn(inst)
    local real = H.Set
    H.Set = function(path, ...)
        if path ~= "locked" then error("boom", 0) end
        return real(path, ...)
    end
    local ok, err = pcall(H.SetRows, { { "locked", not def.default }, { "enabled", false } }, "copy test")
    H.Set = real
    assertTrue(not ok and err == "boom", "the row's error reaches the caller unchanged: " .. tostring(err))
    H.Set("locked", "general", def.default)
    local lines = setLines(inst)
    NS.State.debug = false
    assertEqual(#lines, 2, "the act's line, then the write's: " .. table.concat(lines, " | "))
    assertTrue(lines[1]:find("[Set] copy test: 1 rows (stopped by an error)", 1, true) ~= nil,
        "the one row it wrote, and that it stopped: " .. lines[1])
    assertTrue(lines[2]:find("[Set] locked = " .. tostring(def.default), 1, true) ~= nil,
        "and the mute did not stick: " .. lines[2])
end)
