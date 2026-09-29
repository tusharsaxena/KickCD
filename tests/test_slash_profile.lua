-- tests/test_slash_profile.lua
-- `/kcd profile [name]`: the host's COMMANDS row, routed to LibKa0s-Slash-1.0's
-- CliProfile (minor 17). What the verb does (quote stripping, the sorted list,
-- the did-you-mean, the combat refusal) is the library's and is pinned in its own
-- suite; what is pinned here is the WIRING: the row, its place in the table, the
-- `profiles` descriptor field reaching NS.db, the live-while-disabled judgment,
-- the host's profile handler running on a switch, and the degraded stub.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

--- A fresh instance whose account holds three stored profiles, Default active.
local function loadProfiles(opts)
    return T.load(true, true, function(m)
        m.KickCDDB = { global = { schemaVersion = 5 },
            profiles = { Default = {}, Alt = {}, ["My Raid"] = {} } }
    end, opts)
end

--- Everything NS.Util.print emits while `fn` runs, on `inst`.
local function say(inst, fn)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

local function run(inst, input)
    return say(inst, function() inst.NS:OnSlashCommand(input) end)
end

local function joined(lines) return table.concat(lines, "\n") end

--- The stored profile names, sorted, as one string.
local function stored(inst)
    local names = inst.NS.db:GetProfiles({})
    table.sort(names)
    return table.concat(names, ",")
end

--- Strip WoW color escapes so a line reads as the player sees it.
local function plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ── the row ─────────────────────────────────────────────────────────────────

test("COMMANDS carries `profile` beside the settings verbs, in a pinned order", function()
    -- red under: the row missing, moved, or a verb added without this list moving with it
    local order = {}
    for _, e in ipairs(T.NS.COMMANDS) do order[#order + 1] = e[1] end
    assertEqual(table.concat(order, " "),
        "help version config enable disable lock unlock toggle list get set reset resetall "
        .. "profile resetposition spells debug diagnostics perf")
    assertEqual(#T.NS.COMMANDS, 19, "nineteen verbs")
end)

test("the `profile` description is the locale's, and names the <name> form", function()
    -- red under: an English literal in COMMANDS instead of NS.L
    local key = "List profiles, or switch to one: profile <name>"
    assertEqual(rawget(T.NS.L, key), key, "locales/enUS.lua must define the key")
    for _, e in ipairs(T.NS.COMMANDS) do
        if e[1] == "profile" then assertEqual(e[2], T.NS.L[key]) end
    end
end)

test("`/kcd help` lists `profile` once, one row per COMMANDS entry", function()
    -- red under: a help renderer or COMMANDS row that drops or doubles the verb
    local inst = loadProfiles()
    local rows = inst.NS.Slash.cli:HelpRows()
    assertEqual(#rows, #inst.NS.COMMANDS, "one help row per verb")
    local hits = 0
    for _, line in ipairs(run(inst, "help")) do
        if plain(line):find("/kcd profile", 1, true) then hits = hits + 1 end
    end
    assertEqual(hits, 1, "`/kcd help` must list `/kcd profile` exactly once")
end)

-- ── the verb ────────────────────────────────────────────────────────────────

test("bare `/kcd profile` lists the stored profiles, the current one marked", function()
    -- red under: a `profiles` descriptor field missing (the library prints
    -- "Profiles are not available.") or answering something other than NS.db
    local inst = loadProfiles()
    local lines = run(inst, "profile")
    local text = plain(joined(lines))
    assertNil(text:find("not available", 1, true), "the store must reach the library: " .. text)
    assertEqual(plain(lines[1]), "Profiles")
    assertEqual(plain(lines[2]), "  Alt")
    assertEqual(plain(lines[3]), "  Default (current)")
    assertEqual(plain(lines[4]), "  My Raid")
    assertTrue(plain(lines[5]):find("/kcd profile <name>", 1, true) ~= nil, "the hint names /kcd")
    for _, line in ipairs(lines) do
        assertTrue(plain(line):sub(-1) ~= ":", "no trailing colon: " .. line)
    end
end)

test("`/kcd profile Alt` switches, and the host's profile handler runs", function()
    -- red under: the row calling SetProfile on something other than NS.db, or
    -- Database:OnProfileChanged not reached (no [Profile] trace, no bus message)
    local inst = loadProfiles()
    local NS = inst.NS
    NS.State.debug = true
    NS.DebugLog:Clear()
    local fired, realSend = 0, NS.SendMessage
    NS.SendMessage = function(self, msg, ...)
        if msg == NS.MSG.PROFILE_CHANGED then fired = fired + 1 end
        return realSend(self, msg, ...)
    end
    local lines = run(inst, "profile Alt")
    NS.SendMessage = realSend
    NS.State.debug = false
    assertEqual(NS.db:GetCurrentProfile(), "Alt", "the switch landed")
    assertEqual(plain(joined(lines)), "Switched to profile 'Alt'.")
    assertTrue(NS.DebugLog:FindLine("[Profile] switched to 'Alt'"),
        "the host's handler logs the one switch line")
    assertEqual(fired, 1, "the handler published the profile-changed message once")
end)

test("a quoted name with spaces switches, case kept", function()
    -- red under: a host that splits or lowercases `rest` before the library sees it
    local inst = loadProfiles()
    local lines = run(inst, '  profile "My Raid"  ')
    assertEqual(inst.NS.db:GetCurrentProfile(), "My Raid")
    assertEqual(plain(joined(lines)), "Switched to profile 'My Raid'.")
end)

test("an unknown name is refused, lists the profiles, and creates nothing", function()
    -- red under: calling SetProfile without the existence check (AceDB creates
    -- a missing profile, which is how a typo becomes a stray one)
    local inst = loadProfiles()
    local before = stored(inst)
    local lines = run(inst, "profile Nope")
    assertEqual(plain(lines[1]), "No profile named 'Nope'.")
    assertEqual(plain(lines[2]), "Profiles", "the list follows the refusal")
    assertEqual(inst.NS.db:GetCurrentProfile(), "Default", "nothing switched")
    assertEqual(stored(inst), before, "nothing was created")
end)

test("a name that differs only in case is refused with a did-you-mean", function()
    local inst = loadProfiles()
    local lines = run(inst, "profile alt")
    assertEqual(plain(lines[1]), "No profile named 'alt'.")
    assertEqual(plain(lines[2]), "Did you mean 'Alt'?")
    assertEqual(inst.NS.db:GetCurrentProfile(), "Default")
end)

test("the current profile answers `Already on`, and switches nothing", function()
    local inst = loadProfiles()
    local fired, realSend = 0, inst.NS.SendMessage
    inst.NS.SendMessage = function(self, msg, ...)
        if msg == inst.NS.MSG.PROFILE_CHANGED then fired = fired + 1 end
        return realSend(self, msg, ...)
    end
    local lines = run(inst, "profile Default")
    inst.NS.SendMessage = realSend
    assertEqual(plain(joined(lines)), "Already on profile 'Default'.")
    assertEqual(fired, 0, "no profile event")
end)

test("in combat the switch is refused, and the profile does not move", function()
    -- red under: a host path that calls SetProfile itself, around the library's guard
    local inst = loadProfiles()
    inst.mocks.InCombatLockdown = function() return true end
    local lines = run(inst, "profile Alt")
    inst.mocks.InCombatLockdown = function() return false end
    assertEqual(plain(joined(lines)), "Can't switch profiles in combat.")
    assertEqual(inst.NS.db:GetCurrentProfile(), "Default")
end)

-- ── while disabled ──────────────────────────────────────────────────────────

test("`profile` is on the addon's own live verbs, not the library's reserved list", function()
    -- `profile` is a host verb (slash-commands.md:7), so it is not in
    -- lib.LIVE_VERBS; the host widens its own set to keep it live.
    -- red under: `profile` missing from NS.EXTRA_LIVE_VERBS
    local live = {}
    for _, v in ipairs(T.NS.EXTRA_LIVE_VERBS) do live[v] = true end
    assertTrue(live.profile, "NS.EXTRA_LIVE_VERBS must carry `profile`")
    for _, v in ipairs(T.mocks.LibStub("LibKa0s-Slash-1.0", true).LIVE_VERBS) do
        assertTrue(v ~= "profile", "the library does not reserve `profile`")
    end
end)

test("while disabled `/kcd profile <name>` still switches, with no refusal line", function()
    -- A profile switch repairs settings, and a player with the addon off is the
    -- one most likely to need it.
    -- red under: `profile` refused by the disabled gate
    local inst = loadProfiles()
    run(inst, "disable")
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: the addon is off")
    local lines = run(inst, "profile Alt")
    for _, line in ipairs(lines) do
        assertNil(line:find("is disabled", 1, true), "refused: " .. line)
    end
    assertEqual(inst.NS.db:GetCurrentProfile(), "Alt", "the switch landed while disabled")
end)

-- ── the degraded stub ───────────────────────────────────────────────────────

test("with LibKa0s absent `/kcd profile` prints the library-absent line and switches nothing", function()
    -- red under: a stub route that switches through NS.db without the library's checks
    local inst = loadProfiles({ libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Slash-1.0", true), "sanity: no Slash major on this load")
    local lines = run(inst, "profile Alt")
    assertEqual(joined(lines),
        inst.NS.L["%s is unavailable: the LibKa0s library did not load."]:format("/kcd profile"))
    assertEqual(inst.NS.db:GetCurrentProfile(), "Default")
end)

test("with LibKa0s absent and the addon disabled, `/kcd profile` is not refused", function()
    -- The degraded gate refuses NS.FEATURE_VERBS only, and `profile` is not one.
    -- red under: `profile` added to NS.FEATURE_VERBS
    local inst = loadProfiles({ libFiles = {} })
    run(inst, "disable")
    assertEqual(inst.NS.db.profile.enabled, false, "sanity: disabled")
    local lines = run(inst, "profile")
    assertEqual(joined(lines),
        inst.NS.L["%s is unavailable: the LibKa0s library did not load."]:format("/kcd profile"))
end)
