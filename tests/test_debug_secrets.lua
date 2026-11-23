-- tests/test_debug_secrets.lua -- the two cast dumps against TYPED secrets, and the whole name
-- (MKF-KC-06, the WoW Forever port; critic C5, kc-code 3.1).
--
-- A client secret keeps its underlying type, so type() answers "boolean" for a secret boolean. The
-- older suites (test_castbar_debug, test_compat_debug) stand a secret in with a table, whose type is
-- "table", so a dump that dispatched on type() before it asked IsSecret looked safe there and
-- printed a secret as a plain value in the client; `/kcd diagnostics` reuses the dump. Every case
-- here installs typed secrets (T.typedSecrets), so the stand-in answers type() as the client does.
-- A unit's name is its whole character name, First Surname on WoW Forever (forever-quirks-§4), and
-- the header's other client reads (UnitIsUnit, UnitCanAttack) are tested for a secret before any
-- branch on them. Both clients.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

--- The chat lines of `run(NS)`, prefix stripped, on an instance staged by `stage(mocks)`.
local function lines(stage, run, opts)
    local inst = T.load(true, false, function(m)
        T.typedSecrets(m)
        m.UnitExists = function() return true end
        m.UnitCanAttack = function() return true end
        if stage then stage(m) end
    end, opts)
    local out = {}
    inst.mocks.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) out[#out + 1] = msg end }
    run(inst.NS)
    local prefix = inst.NS.PREFIX .. " "
    for i, line in ipairs(out) do
        out[i] = (tostring(line):gsub("^" .. prefix:gsub("[%%%|%[%]%(%)%.%+%-%*%?%^%$]", "%%%0"), ""))
    end
    return out
end

local function has(out, pattern)
    for _, line in ipairs(out) do
        if line:find(pattern) then return line end
    end
    return nil
end

--- Castbar:DebugDump on target, with a tracked cast whose flag is `nint`.
local function castbarDump(nint, stage, opts)
    return lines(stage, function(NS)
        local Castbar = NS:GetModule("Castbar")
        local inst = Castbar:GetInstance("target")
        inst.current = { isChannel = false, notInterruptible = nint, name = "Bolt", texture = 1, spellID = 686 }
        Castbar:DebugDump("target")
    end, opts)
end

-- ── /kcd debug castbar ──────────────────────────────────────────────────────────────────────────

test("castbar dump: a secret notInterruptible is reported secret, never as a plain value", function()
    -- red under: NINT_REPORT keyed on type() before the IsSecret test
    local out = castbarDump(T.secret(true))
    assertNil(has(out, "plain value"), "a secret boolean reached the plain-value arm")
    assertTrue(has(out, "secret%-tainted") ~= nil, "the secret arm")
    assertTrue(has(out, "isSecret=true") ~= nil)
end)

test("castbar dump: a plain flag still reports its value", function()
    assertTrue(has(castbarDump(false), "plain value = false") ~= nil)
    assertTrue(has(castbarDump(nil), "plain nil") ~= nil)
end)

test("castbar dump: a secret unit name is rendered secret, never joined", function()
    -- red under: `UnitName(unit) .. ...`, which raises on the stand-in
    local out = castbarDump(false, function(m) m.UnitName = function() return T.secret("Boss") end end)
    assertEqual(out[2], "  target = <secret>, isUnit=other, canAttack=true")
end)

test("castbar dump: a secret UnitIsUnit or UnitCanAttack is reported secret, never branched on", function()
    local out = castbarDump(false, function(m)
        m.UnitName = function() return "Boss" end
        m.UnitIsUnit = function() return T.secret(true) end
        m.UnitCanAttack = function() return T.secret(false) end
    end)
    assertEqual(out[2], "  target = Boss, isUnit=<secret>, canAttack=<secret>")
end)

test("castbar dump: the unit is named in full, First Surname on WoW Forever", function()
    local out = castbarDump(false, nil, { world = "forever" })
    assertEqual(out[2], "  target = Mock Mockwood, isUnit=other, canAttack=true")
    local retail = castbarDump(false, function(m) m.UnitName = function() return "Boss", "Realm" end end)
    assertEqual(retail[2], "  target = Boss, isUnit=other, canAttack=true", "Retail: the name, not the realm")
end)

-- ── /kcd debug interrupt ────────────────────────────────────────────────────────────────────────

local function interruptDump(stage, opts)
    return lines(stage, function(NS) NS.Compat.DebugInterrupt("target") end, opts)
end

test("interrupt dump: the header names the unit in full, First Surname on WoW Forever", function()
    local out = interruptDump(nil, { world = "forever" })
    assertEqual(out[1], 'DebugInterrupt: unit=target name="Mock Mockwood" canAttack=true')
end)

test("interrupt dump: a secret canAttack is rendered secret, never branched on", function()
    local out = interruptDump(function(m)
        m.UnitName = function() return "Boss" end
        m.UnitCanAttack = function() return T.secret(true) end
    end)
    assertEqual(out[1], 'DebugInterrupt: unit=target name="Boss" canAttack=<secret>')
end)

test("interrupt dump: a typed secret flag at position 8 is described as secret", function()
    local out = interruptDump(function(m)
        m.UnitName = function() return "Boss" end
        m.UnitCastingInfo = function() return "Bolt", "Bolt", 1, 0, 1, false, 7, T.secret(false), 686 end
    end)
    local line = has(out, "8 notInterruptible")
    assertTrue(line ~= nil, "the position line")
    assertTrue(line:find("isSecret=true", 1, true) ~= nil and line:find("value=<secret>", 1, true) ~= nil, line)
end)
