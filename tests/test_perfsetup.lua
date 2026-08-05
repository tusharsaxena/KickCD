-- tests/test_perfsetup.lua
-- LibKa0s-Perf-1.0 wiring.
--
-- testing-§8 names four things an addon MUST pin per adopted module, and this
-- suite is those four: the descriptor is well-formed, EVERY declared bucket is
-- reached by a real bracket, suspend genuinely makes THIS addon inert, and the
-- degraded path answers rather than erroring.
--
-- The bucket case is the one that cannot be replaced by reading the source: a
-- declared bucket no bracket reaches is a lie in every report, and nothing else
-- in the repo would catch it.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

--- Poke a real entry point when the module and the method both exist, swallowing
--- a throw: several of these legitimately raise headlessly. The call must stay a
--- REAL entry point — swapping one for a direct Perf.Note would prove only that
--- Note appends, which is the failure mode the bucket case exists to catch.
local function tryCall(obj, method, ...)
    if obj and obj[method] then return pcall(obj[method], obj, ...) end
end

--- Any one watched spellID, or nil. `watched` is a set, so there is no first.
local function firstWatchedSpell(Cooldowns)
    for id in pairs(Cooldowns and Cooldowns.watched or {}) do return id end
end

--- Every named bucket must have been reached by a real bracket.
local function assertBucketsReached(buckets, keys)
    for _, key in ipairs(keys) do
        assertTrue(buckets[key] ~= nil and (buckets[key].calls or 0) > 0,
            "bucket '" .. key .. "' was declared but no bracket reached it")
    end
end

-- ── the descriptor ──────────────────────────────────────────────────────────

test("NS.Perf is the library instance, with the hot-path gate as a plain field", function()
    -- performance-§2: the gate MUST be a plain boolean field and the sink a
    -- plain dot-callable function. A colon method or an accessor on the hot path
    -- defeats the point of the bracket.
    local inst = T.load(true, true)
    local P = inst.NS.Perf
    assertTrue(P ~= nil, "NS.Perf must exist")
    assertEqual(type(P.on), "boolean", "the gate must be a plain boolean field")
    assertEqual(type(P.suspended), "boolean")
    assertEqual(type(P.Note), "function")
    assertEqual(type(P.OnCommand), "function")
end)

test("the capture ring is declared in the TOC as a second SavedVariables global", function()
    -- performance-§5: it MUST live outside the AceDB tree, or "copy profile"
    -- clones it and "reset profile" wipes it — neither of which is wanted from a
    -- diagnostics store.
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local toc = fh:read("*a")
    fh:close()
    assertTrue(toc:find("KickCDPerfDB", 1, true) ~= nil,
        "KickCDPerfDB must be declared in ## SavedVariables")
    assertTrue(toc:find("core\\PerfSetup.lua", 1, true) ~= nil,
        "core/PerfSetup.lua must be in the TOC")
end)

test("every bracket call site reads the gate through a load-time upvalue", function()
    -- anti-patterns #43: reaching the probe through an NS lookup on a per-frame
    -- path is the ungated-instrumentation smell. Each instrumented module must
    -- hold `local Perf = NS.Perf` at file scope.
    for _, rel in ipairs({
        "modules/Cooldowns.lua", "modules/IconGrid.lua",
        "modules/IconGrid_Render.lua", "modules/Castbar.lua",
    }) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local src = fh:read("*a")
        fh:close()
        assertTrue(src:find("local Perf = NS.Perf", 1, true) ~= nil,
            rel .. " must take the probe as a file-scope upvalue")
        assertNil(src:match("NS%.Perf%.on and debugprofilestop"),
            rel .. " reaches the gate through NS on a bracket path")
    end
end)

-- ── every declared bucket is really reached ─────────────────────────────────

test("every declared bucket is reached by a real bracket", function()
    -- THE case performance-§3 requires. A bucket that no bracket ever reaches
    -- reads 0.000 in every report, forever, and looks like a measurement.
    -- red under: deleting any one `Perf.Note(...)` line from modules/
    --
    -- Driven through each bucket's genuine entry point rather than by calling
    -- Note directly — calling Note would prove only that Note appends.
    local inst = T.load(true, true)
    local NS2, P = inst.NS, inst.NS.Perf
    P.on = true

    local IconGrid = NS2:GetModule("IconGrid", true)
    local Castbar  = NS2:GetModule("Castbar", true)
    local Cooldowns = NS2:GetModule("Cooldowns", true)

    -- spellPoll: the coalesced poll over the watched table.
    if Cooldowns and Cooldowns.Refresh then Cooldowns:Refresh() end
    -- spellState: Refresh only emits when a spell's state actually CHANGED, and
    -- a freshly-built instance has nothing to report. Driven through the real
    -- entry point — the message — rather than by calling Note, which would prove
    -- only that Note appends.
    local firstSpell = firstWatchedSpell(Cooldowns)
    if firstSpell then
        NS2:SendMessage("Ka0s_KickCD_SPELL_STATE",
            { spellID = firstSpell, ready = true, isActive = false })
    end
    -- castEvent -> visibility.
    tryCall(IconGrid, "OnUnitCastEvent", "UNIT_SPELLCAST_START", "target")
    for _, u in ipairs(NS2.Units.LIST) do tryCall(IconGrid, "RefreshVisibility", u) end
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end

    local buckets = P.__buckets and P.__buckets() or {}
    P.on = false

    -- Not every bucket is reachable headlessly (castTick needs a live cast,
    -- cdText needs the ticker), so assert on the ones this harness can drive and
    -- name the rest rather than pretending.
    assertBucketsReached(buckets, { "spellPoll", "spellState", "castEvent", "visibility" })
end)

test("the declared bucket list and the bracketed call sites agree exactly", function()
    -- The other half: a bracket whose key is NOT declared records but never
    -- appears in a report, and a declared key with no bracket is the lie above.
    -- Cross-checked against the source so the buckets this harness cannot drive
    -- (castTick, cdText) are still covered.
    local fh = assert(io.open(T.root .. "/core/PerfSetup.lua", "r"))
    local setup = fh:read("*a")
    fh:close()

    local declared = {}
    for key in setup:gmatch('{ key = "([%w_]+)"') do declared[key] = true end

    local bracketed = {}
    for _, rel in ipairs({
        "modules/Cooldowns.lua", "modules/IconGrid.lua",
        "modules/IconGrid_Render.lua", "modules/Castbar.lua",
    }) do
        local h = assert(io.open(T.root .. "/" .. rel, "r"))
        local src = h:read("*a")
        h:close()
        for key in src:gmatch('Perf%.Note%("([%w_]+)"') do bracketed[key] = true end
    end

    for key in pairs(declared) do
        assertTrue(bracketed[key], "declared bucket '" .. key .. "' has no Perf.Note bracket")
    end
    for key in pairs(bracketed) do
        assertTrue(declared[key], "bracket '" .. key .. "' records into an undeclared bucket")
    end
end)

test("nesting is declared for every bucket that runs inside another", function()
    -- performance-§3: nesting is DECLARED rather than left as prose, because a
    -- reader comparing two captures cannot know which totals overlap — and a
    -- parent must never be summed with its children.
    local inst = T.load(true, false)
    local fh = assert(io.open(T.root .. "/core/PerfSetup.lua", "r"))
    local setup = fh:read("*a")
    fh:close()
    -- `visibility` is deliberately NOT here. It reads as a child of castEvent
    -- from the in-combat call path, but the first live capture recorded six
    -- visibility calls against ZERO castEvent calls — they all came from its
    -- other call sites. Declaring the nesting made the report indent it under a
    -- parent that never ran, which tells the reader the opposite of the truth.
    for _, pair in ipairs({
        { "spellState", "spellPoll" },
        { "pollSpell",  "spellPoll" },
        { "iconApply",  "spellState" },
    }) do
        local pat = '{ key = "' .. pair[1] .. '",%s*within = "' .. pair[2] .. '"'
        assertTrue(setup:find(pat) ~= nil,
            pair[1] .. " must declare `within = \"" .. pair[2] .. "\"`")
    end
    assertTrue(inst.NS.Perf ~= nil)
end)

test("instrumentation is inert when capture is off", function()
    -- The zero-cost claim, exercised rather than asserted in a comment: with the
    -- gate off, driving a bracketed path must record nothing at all.
    local inst = T.load(true, true)
    local P = inst.NS.Perf
    P.on = false
    local Cooldowns = inst.NS:GetModule("Cooldowns", true)
    if Cooldowns and Cooldowns.Refresh then pcall(Cooldowns.Refresh, Cooldowns) end
    local buckets = P.__buckets and P.__buckets() or {}
    local total = 0
    for _, b in pairs(buckets) do total = total + (b.calls or 0) end
    assertEqual(total, 0, "a bracket must record nothing while the gate is off")
end)

-- ── suspend / resume ────────────────────────────────────────────────────────

test("the show decisions consult Perf.suspended as step 0, at the source", function()
    -- performance-§6: visibility MUST be enforced by the addon's own
    -- show-decision, never by suspend reaching in and hiding frames. A hidden
    -- frame comes back on the next combat transition or target swap, and the
    -- suspended arm then measures the addon still working.
    -- red under: deleting either guard
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local IconGrid = NS2:GetModule("IconGrid", true)
    assertTrue(IconGrid ~= nil)
    assertTrue(IconGrid.ShouldBeVisible ~= nil, "IconGrid.ShouldBeVisible must be published")

    local fakeInst = { unit = "target" }
    NS2.Perf.suspended = false
    local beforeCall = IconGrid.ShouldBeVisible(fakeInst)
    NS2.Perf.suspended = true
    local whileSuspended = IconGrid.ShouldBeVisible(fakeInst)
    NS2.Perf.suspended = false

    assertEqual(whileSuspended, false, "the grid must refuse to show while suspended")
    assertTrue(beforeCall ~= nil, "sanity: the ladder answered before suspending")
end)

test("suspend releases the per-unit dispatch frames AceEvent cannot reach", function()
    -- The 8-per-unit (IconGrid) and 10-per-unit (Castbar) UNIT_SPELLCAST_*
    -- frames are created by Util.RegisterUnitCastEvent and stashed on the
    -- instance; AceEvent's UnregisterAllEvents only knows its own table.
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local IconGrid = NS2:GetModule("IconGrid", true)

    NS2.Perf.Suspend()
    assertEqual(NS2.Perf.suspended, true, "Suspend must set the flag the ladders read")

    -- Counted, not inferred from visibility: asserting ShouldBeVisible here
    -- would pass on the show-decision guard alone and stay green with the
    -- ReconcileUnits guard deleted — an unfalsifiable assertion, caught by
    -- mutating exactly that.
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "suspend must release every UNIT_SPELLCAST_START dispatch frame")

    assertEqual(IconGrid.ShouldBeVisible({ unit = "target" }), false,
        "and the grid must refuse to show")
    NS2.Perf.Resume()
end)

test("enabling a unit while suspended does not re-register its frames mid-capture", function()
    -- THE scenario the ReconcileUnits guard exists for, and the one a naive test
    -- misses: Suspend leaves `inst.enabled` alone, so a plain CONFIG_CHANGED
    -- finds every instance already reconciled and does nothing either way. The
    -- guard only earns its keep when the DESIRED state changes while suspended —
    -- a unit toggled ON — because ReconcileUnits would then call EnableUnit and
    -- rebuild all 8 dispatch frames per unit in the middle of a capture.
    --
    -- red under: deleting `if NS.Perf and NS.Perf.suspended then return end`
    -- from IconGrid:ReconcileUnits
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local H = NS2.Settings.Helpers

    -- Start from focus OFF so enabling it is a real state change.
    H.SetAndRefresh("units.focus.enabled", false)
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end

    NS2.Perf.Suspend()
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "suspend must leave no dispatch frame registered")

    -- Toggle focus ON while suspended. Without the guard this reaches EnableUnit.
    H.SetAndRefresh("units.focus.enabled", true)
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end
    assertEqual(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START"), 0,
        "a unit enabled while suspended must not register frames until Resume")

    -- Resume then honors the CURRENT desired state, focus included.
    NS2.Perf.Resume()
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end
    assertTrue(inst.mocks.__countFramesFor("UNIT_SPELLCAST_START") > 0,
        "Resume must rebuild the dispatch frames from current state")

    NS2.Perf.Resume()
    assertEqual(NS2.Perf.suspended, false, "Resume must clear the flag")
end)

test("resume restores from CURRENT state, not from a snapshot", function()
    -- performance-§6: a unit toggled while suspended must come back correctly,
    -- which is why Resume rebuilds through ReconcileUnits rather than replaying
    -- what was live at suspend time.
    local inst = T.load(true, true)
    local NS2 = inst.NS
    local H = NS2.Settings.Helpers

    NS2.Perf.Suspend()
    -- Toggle focus off WHILE suspended.
    local before = H.Get("units.focus.enabled")
    H.SetAndRefresh("units.focus.enabled", not before)
    NS2.Perf.Resume()
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end

    -- The addon must reflect the value as it is NOW, not as it was at suspend.
    assertEqual(H.Get("units.focus.enabled"), not before)
    H.SetAndRefresh("units.focus.enabled", before)
end)

test("the suspended flag is session-only and never persisted", function()
    -- performance-§6: a suspended addon that stayed suspended across a /reload
    -- is indistinguishable from a broken one.
    local inst = T.load(true, true)
    inst.NS.Perf.Suspend()
    local db = inst.NS.db
    assertNil(db.profile.perfSuspended, "suspend state must not reach the profile")
    assertNil(db.global and db.global.perfSuspended, "nor the global table")
    inst.NS.Perf.Resume()
end)

-- ── the slash verb ──────────────────────────────────────────────────────────

test("`perf` is a host verb in NS.COMMANDS, not registered by the library", function()
    -- performance-§4 / slash-commands-§2: `perf` is reserved across the
    -- collection and MUST dispatch through the addon's own ordered table with
    -- the mandated cyan tag. The lib returns lines; the host prints them.
    local found = false
    for _, e in ipairs(T.NS.COMMANDS) do
        if e[1] == "perf" then found = true break end
    end
    assertTrue(found, "COMMANDS must carry a `perf` verb")
end)

test("a bare /kcd perf answers through the addon's tagged printer", function()
    local lines = {}
    local frame = T.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    T.NS:OnSlashCommand("perf")
    frame.AddMessage = orig
    assertTrue(#lines > 0, "`/kcd perf` must answer")
    assertTrue(lines[1]:find(T.NS.PREFIX, 1, true) == 1,
        "every line must carry the cyan tag; got: " .. tostring(lines[1]))
end)

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the probe stub answers every member the addon calls", function()
    local inst = T.load(true, false, nil, { libFiles = {} })
    local P = inst.NS.Perf
    assertTrue(P ~= nil, "NS.Perf must exist even with no library")
    assertEqual(P.on, false, "the gate must be a real false, so brackets stay inert")
    assertEqual(P.suspended, false, "the show ladders read this unconditionally")
    assertEqual(type(P.Note), "function")
    local lines = P.OnCommand("")
    assertEqual(type(lines), "table", "OnCommand must return printable lines")
    assertTrue(#lines > 0 and lines[1]:find("LibKa0s", 1, true) ~= nil,
        "the stub must name the missing library")
end)

test("with LibKa0s absent the bracketed paths still run", function()
    -- A missing diagnostics harness must not break the addon's own function.
    local inst = T.load(true, true, nil, { libFiles = {} })
    local Cooldowns = inst.NS:GetModule("Cooldowns", true)
    local ok = pcall(function()
        if Cooldowns and Cooldowns.Refresh then Cooldowns:Refresh() end
    end)
    assertTrue(ok, "a bracketed path must not raise when the probe is a stub")
end)

-- ── the locale seam ─────────────────────────────────────────────────────────

test("the perf panel resolves real English, never a raw STRINGS key", function()
    -- THE bug this case exists for, and it was visible only in game.
    --
    -- NS.L carries the metatable fallback the standard MANDATES (anti-patterns
    -- #2): a miss returns the KEY, not nil. Handing that table to a LibKa0s
    -- descriptor's `L` therefore satisfies the library's "is it a string?" check
    -- for EVERY key, so its own STRINGS are never reached and the panel renders
    -- STEP_START, STEP_MEASURE_A, PANEL_TITLE_SUFFIX ... verbatim.
    --
    -- Defense in depth, and honest about which half is falsifiable:
    -- restoring `L = NS.L` no longer reddens this, because the vendored library
    -- now resolves an override with rawget (DebugLog 3 / Slash 3 / Perf 4). The
    -- guard that DOES redden on the descriptor mistake is the source check
    -- below; the guard that reddens on a LIBRARY regression is the
    -- fallback-locale case after it. This one pins the rendered result.
    local inst = T.load(true, true)
    local P = inst.NS.Perf

    for _, step in ipairs(P.STEPS or {}) do
        assertTrue(step.label ~= nil and step.label ~= "",
            "step " .. tostring(step.key) .. " has no label")
        -- A resolved label is prose. An unresolved one is the STRINGS key
        -- itself: SCREAMING_SNAKE_CASE, which no English label ever is.
        assertNil(step.label:match("^[A-Z][A-Z0-9_]+$"),
            "step '" .. tostring(step.key) .. "' rendered its raw key: " .. step.label)
        assertNil(step.label:match("^STEP_"),
            "step '" .. tostring(step.key) .. "' rendered a STEP_ key: " .. step.label)
    end
end)

test("no LibKa0s descriptor is handed the key-returning locale table", function()
    -- The general form, so the next setup file cannot reintroduce it. A locale
    -- table whose __index returns the key can never be a valid `L` override:
    -- it answers every key, so the library's own STRINGS become unreachable.
    -- Pass nothing, or pass a plain table holding only the real overrides.
    -- red under: adding `L = NS.L,` or `L = NS.L or {…},` to any setup file's descriptor
    --
    -- Matched on what the expression can EVALUATE TO, not on one spelling. This case used to
    -- anchor `L = NS.L,` to end-of-line, which mattered here more than anywhere: this addon's
    -- real descriptor at settings/Slash.lua is `L = NS.L and { ... } or nil`, so an `and` -> `or`
    -- typo yields the live trap on a line the old pattern never looked at.
    --
    --   L = NS.L                     -- the table itself                        OFFENDER
    --   L = NS.L or { ... }          -- NS.L is always truthy, so: the table    OFFENDER
    --   L = NS.L and { ... } or nil  -- evaluates to the plain table            fine
    --
    -- `and` is the one operator that can select something else; anything after `NS.L` other than
    -- `and` leaves the locale table reachable.
    local function handedTheLocaleTable(line)
        -- `L = NS.L` as a descriptor field, not `local L = NS.L`.
        local tail = line:match("^%s*L%s*=%s*NS%.L(.*)$")
                  or line:match("[{,]%s*L%s*=%s*NS%.L(.*)$")
        if not tail then return false end
        return not (tail:match("^%s*and$") or tail:match("^%s*and[^%w_]"))
    end

    -- Non-vacuity: pin the matcher against all three forms, so it cannot be narrowed back to the
    -- single anchored spelling while still reporting green.
    assertTrue(handedTheLocaleTable("    L = NS.L,"),
        "the bare form must be flagged")
    assertTrue(handedTheLocaleTable("    L = NS.L or {},"),
        "the `or` form is the same trap and must be flagged")
    assertFalse(handedTheLocaleTable("    L = NS.L and { LIST_HEADER = x } or nil,"),
        "the `and` form evaluates to the plain table and must NOT be flagged")

    local offenders = {}
    for _, rel in ipairs({
        "core/CoreSetup.lua", "core/DebugLogSetup.lua", "core/PerfSetup.lua",
        "settings/Slash.lua", "settings/OptionsSetup.lua",
    }) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local n = 0
        for line in fh:lines() do
            n = n + 1
            if handedTheLocaleTable(line) then
                offenders[#offenders + 1] = rel .. ":" .. n
            end
        end
        fh:close()
    end
    assertEqual(#offenders, 0,
        "descriptor handed the fallback locale table at: " .. table.concat(offenders, ", "))
end)

test("the panel title is the host's brand plus the library's resolved suffix", function()
    -- The title in the screenshot read "Ka0s KickCDPANEL_TITLE_SUFFIX": the brand
    -- concatenated with an UNRESOLVED key. Asserted through the panel frame the
    -- library actually builds, not through a Text() helper the instance does not
    -- expose — an earlier version of this case guarded on `if title then` and so
    -- passed vacuously, which is worse than no case at all.
    local inst = T.load(true, true)
    local P = inst.NS.Perf
    P.ShowPanel()
    local frame = P.__panel and P.__panel()
    assertTrue(frame ~= nil, "the library did not build a panel frame")

    local title = frame.__titleText or (frame.title and frame.title.__text)
    assertTrue(title ~= nil and title ~= "", "the panel has no title text")
    assertNil(title:match("PANEL_TITLE"), "the title rendered a raw key: " .. tostring(title))
    assertTrue(title:find("Ka0s KickCD", 1, true) == 1,
        "the title must lead with the host's brand; got: " .. tostring(title))
    assertTrue(title:find("Perf Run", 1, true) ~= nil,
        "and carry the library's resolved suffix; got: " .. tostring(title))
    P.HidePanel()
end)

test("the VENDORED library ignores a fallback-synthesized locale entry", function()
    -- The case that actually reddens on a library regression, and the reason it
    -- builds its own instance: KickCD passes no `L`, so nothing in the addon
    -- exercises the resolver's override path at all. Reverting the rawget in
    -- libs/LibKa0s/Perf.lua therefore changes nothing the addon can observe —
    -- which is precisely the drift a re-vendor introduces with both repos green.
    --
    -- red under: `local v = rawget(L, key)` -> `local v = L[key]` in
    -- libs/LibKa0s/Perf.lua
    local lib = T.mocks.LibStub("LibKa0s-Perf-1.0", true)
    assertTrue(lib ~= nil, "the vendored Perf major must be registered")

    local P = lib:New({
        name = "TrapProbe", sv = "TrapProbeDB",
        suspend = function() end, resume = function() end,
        -- The exact shape every Ka0s host's locale table has.
        L = setmetatable({}, { __index = function(_, k) return k end }),
    })

    for _, step in ipairs(P.STEPS or {}) do
        assertNil(step.label:match("^[A-Z][A-Z0-9_]+$"),
            "the vendored library let a synthesized key through as '" .. step.label .. "'")
        assertEqual(step.label, lib.STRINGS[step.string],
            "it must fall through to the library's own string")
    end
end)

-- ── the capture record identifies itself ────────────────────────────────────

test("the record stamps a real addon version, never \"?\"", function()
    -- The first live capture recorded `"version":"?"` and a header reading
    -- "(KickCD, schema 2, v?)". core/PerfSetup.lua passed `version = NS.VERSION`,
    -- but NS.VERSION is set in core/KickCD.lua which loads AFTER it — so the
    -- descriptor captured nil and the library defaulted.
    --
    -- The library takes `version` as a plain STRING, resolved once at :New, so a
    -- host cannot defer it with a function the way Slash's `version` allows. The
    -- value therefore has to be resolvable at this file's own load time.
    --
    -- performance-§8: a record must identify itself outside the file it came
    -- from. "v?" makes every archived capture unattributable.
    -- red under: restoring `version = NS.VERSION` to core/PerfSetup.lua
    local inst = T.load(true, true)
    local rec = inst.NS.Perf.BuildRecord and inst.NS.Perf.BuildRecord("t")
    assertTrue(rec ~= nil, "BuildRecord returned nothing")
    assertTrue(rec.version ~= nil and rec.version ~= "" and rec.version ~= "?",
        "the record must carry a real version; got: " .. tostring(rec.version))
    assertTrue(rec.version:match("^%d+%.%d+"),
        "and it must look like a version; got: " .. tostring(rec.version))
end)

test("the perf version agrees with the one /kcd version prints", function()
    -- Two readers of one fact drift. Both resolve through the TOC manifest with
    -- the in-code stamp as fallback (slash-commands-§3).
    local inst = T.load(true, true)
    local rec = inst.NS.Perf.BuildRecord("t")
    assertEqual(rec.version, inst.NS.Slash.Version(),
        "the capture record and the slash layer must report the same version")
end)

test("the version fallback is reachable, not dead", function()
    -- Belt and braces, and the belt was broken. The descriptor prefers the TOC
    -- manifest and falls back to NS.VERSION — but while core/PerfSetup.lua
    -- loaded before core/KickCD.lua that fallback was ALWAYS nil, so a client
    -- without the metadata API would still have stamped "v?". The TOC position
    -- is what makes it real.
    -- red under: moving core\PerfSetup.lua back above core\KickCD.lua
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local order, seen = {}, {}
    for line in fh:lines() do
        local f = line:match("^(core\\[%w_]+%.lua)")
        if f then order[#order + 1] = f; seen[f] = #order end
    end
    fh:close()
    assertTrue(seen["core\\KickCD.lua"] ~= nil and seen["core\\PerfSetup.lua"] ~= nil,
        "both files must be in the TOC")
    assertTrue(seen["core\\PerfSetup.lua"] > seen["core\\KickCD.lua"],
        "core/PerfSetup.lua must load AFTER core/KickCD.lua, or NS.VERSION is nil at :New")
end)

test("every PollSpell exit is measured, including the rejections", function()
    -- The objection that kept `pollSpell` undeclared in the first place: a
    -- function with four exits and a bracket on one under-counts `calls` and
    -- reports a total that quietly excludes the rejected paths. All four are
    -- instrumented now, and this is what says so — a source-level bracket count
    -- would pass just as happily with the Note attached to the wrong branch.
    --
    -- red under: removing the Perf.Note from any one of PollSpell's early returns
    local inst = T.load(true, true)
    local P = inst.NS.Perf
    local Cooldowns = inst.NS:GetModule("Cooldowns", true)
    assertTrue(Cooldowns ~= nil)

    P.Reset()
    P.on = true
    -- Exit 1: a non-numeric id, rejected before any API call.
    Cooldowns:PollSpell(nil)
    Cooldowns:PollSpell("not a number")
    -- Exit 2: a numeric id the spell DB does not know.
    Cooldowns:PollSpell(99999999)
    -- Exit 3: a REAL spell the player cannot currently cast (the unpicked branch
    -- of a talent choice node, or a pet spell with no pet out). Reached by
    -- making the availability check say no, since every watched spell is by
    -- definition available.
    local known
    for id in pairs(Cooldowns.watched or {}) do known = id break end
    assertTrue(known ~= nil, "the fixture has no watched spell to reject")
    local realAvail = inst.NS.Compat.IsSpellAvailable
    inst.NS.Compat.IsSpellAvailable = function() return false end
    Cooldowns:PollSpell(known)
    inst.NS.Compat.IsSpellAvailable = realAvail
    -- Exit 4: the success path.
    Cooldowns:PollSpell(known)
    P.on = false

    local b = (P.__buckets and P.__buckets() or {}).pollSpell
    assertTrue(b ~= nil, "no pollSpell measurement recorded at all")
    assertEqual(b.calls, 5,
        "every exit must be counted; got " .. tostring(b.calls) .. " of 5")
end)

test("no bracketed function leaks an exit — every return closes the bracket", function()
    -- The generalization of the PollSpell case above, and the reason it exists:
    -- PollSpell got its four-exit coverage by hand, and two OTHER brackets were
    -- leaking the whole time. `_tickAllTextIcons` returned unclosed on the
    -- empty-set guard (taken on the last tick of every cooldown burst) and
    -- Castbar's `onUpdate` returned unclosed on the no-duration guard (taken
    -- once per cast, on the frame that tears the handler down). Both are
    -- `Note`-shaped rather than `Open`/`Close`-shaped, so LibKa0s cannot detect
    -- them for us — there is no stack to leave unbalanced. Nothing observes the
    -- leak either: the bucket still reports, just with a `calls` count short by
    -- exactly the number of times the leaked exit was taken, which reads as a
    -- cheap path rather than as a bug.
    --
    -- Behavioral coverage is not available here. `cdText` is driven by a
    -- C_Timer ticker and `castTick` by an OnUpdate script; the harness drives
    -- neither, which is exactly why these two survived. testing-§11's
    -- source-scan shape is the fallback, and this comment is its justification.
    --
    -- red under: deleting the `Perf.Note` line from any early return in any of
    -- the four bracketed modules.
    local leaks = {}
    for _, rel in ipairs({
        "modules/Cooldowns.lua", "modules/IconGrid.lua",
        "modules/IconGrid_Render.lua", "modules/Castbar.lua",
    }) do
        local fh = assert(io.open(T.root .. "/" .. rel, "r"))
        local lines = {}
        for line in fh:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
        fh:close()

        -- Walk top-level function blocks. Every bracket site in this addon is a
        -- column-0 `local function f(` or `function M:f(` closed by a column-0
        -- `end`, so the block boundaries need no Lua parser — and a bracket that
        -- ever moves inside a nested closure trips the "no closing Note" arm
        -- below rather than being silently skipped.
        local i, n = 1, #lines
        while i <= n do
            local head = lines[i]
            if head:match("^local function [%w_]+%(") or head:match("^function [%w_.:]+%(") then
                local body, j = {}, i + 1
                while j <= n and lines[j] ~= "end" do body[#body + 1] = lines[j]; j = j + 1 end
                local bracketed = false
                for _, l in ipairs(body) do
                    if l:match("__t0%s*=%s*Perf%.on") then bracketed = true break end
                end
                if bracketed then
                    local where = rel .. ":" .. i .. " " .. head
                    local sawNote = false
                    for k, l in ipairs(body) do
                        if l:match("Perf%.Note%(") then sawNote = true end
                        if l:match("^%s*return%f[%W]") then
                            -- The Note must be on the nearest preceding line
                            -- that is neither blank nor a comment.
                            local guarded, m = false, k - 1
                            while m >= 1 do
                                local p = body[m]
                                if p:match("^%s*$") or p:match("^%s*%-%-") then
                                    m = m - 1
                                else
                                    guarded = p:match("Perf%.Note%(") ~= nil
                                    break
                                end
                            end
                            if not guarded then
                                leaks[#leaks + 1] = where .. " — unclosed `return` at body line " .. k
                            end
                        end
                    end
                    if not sawNote then
                        leaks[#leaks + 1] = where .. " — opens a bracket it never closes"
                    end
                end
                i = j + 1
            else
                i = i + 1
            end
        end
    end
    assertEqual(#leaks, 0, "bracketed exits left unclosed:\n  " .. table.concat(leaks, "\n  "))
end)

test("the record stamps a real client interface version, never 0", function()
    -- The live capture read `"interface":0`. Blizzard does not serve `Interface`
    -- through GetAddOnMetadata — confirmed in game — so the library read it from
    -- GetBuildInfo's fourth return instead (Perf minor 5).
    --
    -- Asserted HERE as well as upstream because this addon's mock had the same
    -- blind spot the library's did: a GetAddOnMetadata that answers every field
    -- makes the broken read look fine. This case fails against a vendored copy
    -- older than Perf 5.
    -- red under: reverting interfaceVersion() in libs/LibKa0s/Perf.lua
    local inst = T.load(true, true)
    local rec = inst.NS.Perf.BuildRecord("t")
    assertTrue(rec.interface and rec.interface > 0,
        "the record must identify the game build; got: " .. tostring(rec.interface))
end)
