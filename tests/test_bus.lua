-- tests/test_bus.lua — message bus keyed by (message, target) (architecture-§4 / AP-33)
--
-- The whole point: two receivers of ONE message, each on its OWN target,
-- must BOTH fire. A no-op or single-slot mock would hide the last-registrant-
-- wins clobber this addon's Spells panel was vulnerable to (KCD-09).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("AceEvent mock fans one message out to two distinct targets", function()
    local inst = T.load(false)
    local AceEvent = inst.mocks.__libs["AceEvent-3.0"]

    local a, b = {}, {}
    AceEvent:Embed(a)
    AceEvent:Embed(b)

    local gotA, gotB = nil, nil
    a:RegisterMessage("Test_Msg", function(_, payload) gotA = payload end)
    b:RegisterMessage("Test_Msg", function(_, payload) gotB = payload end)

    a:SendMessage("Test_Msg", 42)
    assertEqual(gotA, 42, "receiver A must fire")
    assertEqual(gotB, 42, "receiver B (separate target) must ALSO fire")
end)

test("Two receivers on the SAME target clobber (proves keying is by target)", function()
    local inst = T.load(false)
    local AceEvent = inst.mocks.__libs["AceEvent-3.0"]
    local shared = {}
    AceEvent:Embed(shared)

    local firstFired, secondFired = false, false
    shared:RegisterMessage("Dup_Msg", function() firstFired = true end)
    shared:RegisterMessage("Dup_Msg", function() secondFired = true end)  -- overwrites
    shared:SendMessage("Dup_Msg")
    -- Only the last registrant on a single target survives — this is exactly
    -- the clobber the receiver rule forbids; asserting it locks in the mock's
    -- (message, target) semantics.
    assertFalse(firstFired, "first registrant on a shared target is clobbered")
    assertTrue(secondFired, "last registrant on a shared target must be the survivor")
end)

test("Addon SendMessage reaches a registered module target", function()
    local inst = T.load(true)
    local NS = inst.NS
    local target = assert(NS.NewBusTarget, "NS.NewBusTarget must exist (core/KickCD.lua)")()
    local got = false
    target:RegisterMessage(T.NS.MSG.CONFIG_CHANGED, function() got = true end)
    NS:SendMessage(T.NS.MSG.CONFIG_CHANGED, { section = "test" })
    assertTrue(got, "a private target must receive the addon's broadcast")
end)

test("a batch holds a nil-section announcement and sends it once, as nil", function()
    -- A batch (Store.SetMany, through settings/SchemaSetup.lua's announceBatch)
    -- announces each distinct section once, in first-seen order, and moves the
    -- TIMING of CONFIG_CHANGED and nothing else -- so it must send what an
    -- unbatched write sends. red under: a batch that marks a nil section seen and
    -- then appends nil to its order list (a no-op), dropping the announcement.
    local inst = T.load(true)
    local NS = inst.NS
    local S = NS.Settings.Store
    -- A row with no section, which no shipped row is, added for the case alone.
    S.AddRows({ { path = "zzProbe", type = "bool", group = "Probe", default = false } })
    local icons = S.FindRow("units.target.icons.primarySize")
    local sent = {}
    local realSend = NS.SendMessage
    NS.SendMessage = function(self, msg, payload)
        if msg == T.NS.MSG.CONFIG_CHANGED then
            sent[#sent + 1] = payload.section == nil and "<nil>" or payload.section
        end
        return realSend(self, msg, payload)
    end
    local ok, err = pcall(function()
        S.Set("zzProbe", true)             -- unbatched: sent as it is
        S.SetMany({
            { path = "zzProbe", value = false },
            { path = icons.path, value = icons.default },
            { path = "zzProbe", value = true },   -- a repeat, held once like any section
        })
    end)
    NS.SendMessage = realSend
    if not ok then error(err, 0) end
    assertEqual(#sent, 3, "one unbatched nil, then the batch's nil and icons: " .. table.concat(sent, ", "))
    assertEqual(sent[1], "<nil>", "the unbatched write")
    assertEqual(sent[2], "<nil>", "the batch sends its nil, in first-announced order")
    assertEqual(sent[3], "icons")
end)

test("NewBusTarget gives each receiver its own target — both fire (KCD-09)", function()
    local inst = T.load(true)
    local NS = inst.NS
    assertTrue(type(NS.NewBusTarget) == "function", "NewBusTarget factory must exist")

    -- Two independent consumers (e.g. the Spells panel + a module) each own a
    -- private target; a single broadcast must reach BOTH.
    local a = NS.NewBusTarget()
    local b = NS.NewBusTarget()
    assertTrue(a ~= b, "each NewBusTarget must be a distinct table")
    local gotA, gotB = false, false
    a:RegisterMessage(T.NS.MSG.PROFILE_CHANGED, function() gotA = true end)
    b:RegisterMessage(T.NS.MSG.PROFILE_CHANGED, function() gotB = true end)
    NS:SendMessage(T.NS.MSG.PROFILE_CHANGED, { newProfileKey = "Default" })
    assertTrue(gotA, "receiver A (private target) must fire")
    assertTrue(gotB, "receiver B (private target) must ALSO fire")
end)

-- Characterization for #21: the dispatch shapes production relies on, pinned before
-- the harness moved onto the kit's AceEvent, so the swap is proven not to change them.

test("a string method is dispatched as target:Method(message, payload)", function()
    local inst = T.load(false)
    local t = inst.mocks.LibStub("AceEvent-3.0"):Embed({})
    local got = {}
    function t:OnThing(msg, payload) got.self, got.msg, got.payload = self, msg, payload end
    t:RegisterMessage("Test_Str", "OnThing")
    t:SendMessage("Test_Str", 7)
    assertTrue(got.self == t, "the method must be called on its own target")
    assertEqual(got.msg, "Test_Str")
    assertEqual(got.payload, 7)
end)

test("a registration with no handler calls the method named after the message", function()
    local inst = T.load(false)
    local t = inst.mocks.LibStub("AceEvent-3.0"):Embed({})
    local got
    t.Test_Default = function(self, msg) got = (self == t) and msg end
    t:RegisterMessage("Test_Default")
    t:SendMessage("Test_Default")
    assertEqual(got, "Test_Default")
end)

test("UnregisterMessage stops delivery to that target and no other", function()
    local inst = T.load(false)
    local AceEvent = inst.mocks.LibStub("AceEvent-3.0")
    local a, b = AceEvent:Embed({}), AceEvent:Embed({})
    local gotA, gotB = 0, 0
    a:RegisterMessage("Test_Unreg", function() gotA = gotA + 1 end)
    b:RegisterMessage("Test_Unreg", function() gotB = gotB + 1 end)
    a:UnregisterMessage("Test_Unreg")
    b:SendMessage("Test_Unreg")
    assertEqual(gotA, 0, "the unregistered target must not hear it")
    assertEqual(gotB, 1, "the other target still does")
end)

-- ── The subscription map (characterization for the declare-once sweep) ──────
--
-- Pinned on the literal-typed tree BEFORE the call sites moved onto NS.MSG, so the sweep is
-- proven to register every receiver for exactly the wire names it registered before. The wire
-- names are spelled out here on purpose: this case is the one that says what goes over the wire.
-- They moved once, deliberately, with the PascalCase rename (naming-cheatsheet) that let the
-- table be wrapped in LibKa0s-Bus-1.0's Catalog; the receiver sets did not.

--- Sorted wire names `target` is registered for, read off the live message registry.
local function registeredFor(reg, target)
    local out = {}
    for msg, targets in pairs(reg) do
        if type(targets) == "table" and targets[target] ~= nil then out[#out + 1] = msg end
    end
    table.sort(out)
    return table.concat(out, ",")
end

test("after enable, each module is subscribed to exactly its own set of wire names", function()
    local inst = T.load(true, true)
    local reg = inst.mocks.__msgRegistry
    local EXPECTED = {
        IconGrid  = "Ka0s_KickCD_CombatState,Ka0s_KickCD_ConfigChanged,"
                 .. "Ka0s_KickCD_ProfileChanged,Ka0s_KickCD_SpellState",
        Cooldowns = "Ka0s_KickCD_ConfigChanged,Ka0s_KickCD_ProfileChanged",
        Castbar   = "Ka0s_KickCD_CombatState,Ka0s_KickCD_ConfigChanged,"
                 .. "Ka0s_KickCD_GridLayout,Ka0s_KickCD_ProfileChanged",
        UnitLabel = "Ka0s_KickCD_ConfigChanged,Ka0s_KickCD_GridLayout,Ka0s_KickCD_ProfileChanged",
    }
    for name, want in pairs(EXPECTED) do
        assertEqual(registeredFor(reg, inst.NS:GetModule(name)), want, name)
    end
end)

-- ── The catalog: declared once, typed nowhere else (architecture-§4) ───────

test("NS.MSG declares the five bus messages with the wire names the modules use", function()
    -- The subscription-map case above spells the wire; this one ties each key to it, so a
    -- constant that drifted from the wire would fail here rather than in-game.
    local want = {
        SPELL_STATE     = "Ka0s_KickCD_SpellState",
        CONFIG_CHANGED  = "Ka0s_KickCD_ConfigChanged",
        PROFILE_CHANGED = "Ka0s_KickCD_ProfileChanged",
        GRID_LAYOUT     = "Ka0s_KickCD_GridLayout",
        COMBAT_STATE    = "Ka0s_KickCD_CombatState",
    }
    local n = 0
    for k, v in pairs(T.NS.MSG) do
        n = n + 1
        assertEqual(v, want[k], "NS.MSG." .. tostring(k))
    end
    assertEqual(n, 5, "NS.MSG must declare exactly the five messages")
end)

test("no authored file types a bus message literal outside the catalog", function()
    -- A literal at a call site is the typo nothing reports: a publisher sends to nobody, a
    -- subscriber waits for nothing. The catalog in core/Constants.lua is the one place.
    -- red under: restoring NS:SendMessage("Ka0s_KickCD_CombatState", ...) in core/State.lua
    local seen, offenders = 0, {}
    for _, rel in ipairs(T.tocFiles) do
        if not rel:match("^libs[/\\]") and rel:match("%.lua$") then
            local fh = assert(io.open(T.root .. "/" .. rel, "r"))
            local n = 0
            for line in fh:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                for _ in code:gmatch("[\"']Ka0s_KickCD_") do
                    if rel == "core/Constants.lua" then seen = seen + 1
                    else offenders[#offenders + 1] = rel .. ":" .. n end
                end
            end
            fh:close()
        end
    end
    assertEqual(#offenders, 0, "bus literal outside the catalog: " .. table.concat(offenders, ", "))
    assertEqual(seen, 5, "core/Constants.lua must type each of the five names exactly once")
end)

-- ── LibKa0s-Bus-1.0's Catalog, and the plain table without it ───────────────

test("with LibKa0s present, reading an undeclared NS.MSG key raises at the call site", function()
    -- The half the constant alone does not close: a mistyped key used to be a nil name, and
    -- CallbackHandler sends a nil name to nobody without a word.
    -- red under: `NS.MSG = MSG` in core/Constants.lua (the plain table, no Catalog)
    local inst = T.load(false)
    assertTrue(inst.mocks.LibStub("LibKa0s-Bus-1.0", true) ~= nil, "the live load must register LibKa0s-Bus-1.0")
    local ok, err = pcall(function() return inst.NS.MSG.SPELL_STATES end)
    assertFalse(ok, "an undeclared key must raise")
    assertTrue(tostring(err):find("KickCD: no bus message named SPELL_STATES", 1, true) ~= nil, tostring(err))
end)

test("with LibKa0s absent, NS.MSG is the plain table with the same keys and wire names", function()
    -- The degraded arm keeps every sender and receiver wired: only the strict read is lost.
    -- red under: a degraded arm that leaves NS.MSG nil or drops a key
    local live = T.load(false)
    local degraded = T.load(false, false, nil, { libFiles = {} })
    assertTrue(degraded.mocks.LibStub("LibKa0s-Bus-1.0", true) == nil,
        "the degraded load registered LibKa0s-Bus-1.0; the empty file list did not take")
    assertTrue(getmetatable(degraded.NS.MSG) == nil, "the degraded NS.MSG is the plain table")
    local n = 0
    for k, v in pairs(live.NS.MSG) do
        n = n + 1
        assertEqual(rawget(degraded.NS.MSG, k), v, "NS.MSG." .. k)
    end
    for k in pairs(degraded.NS.MSG) do
        n = n - 1
        assertTrue(rawget(live.NS.MSG, k) ~= nil, "degraded NS.MSG." .. k .. " is not declared live")
    end
    assertEqual(n, 0, "the two arms declare the same keys")
end)
