-- tests/test_compat.lua — deprecated-API routing through core/Compat.lua (KCD-10)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Compat = NS.Compat

test("Compat exposes the spec shims", function()
    assertTrue(type(Compat.GetSpecialization) == "function")
    assertTrue(type(Compat.GetSpecializationInfo) == "function")
end)

test("GetSpecialization prefers C_SpecializationInfo", function()
    assertEqual(Compat.GetSpecialization(), 1)
end)

test("GetSpecializationInfo passes the multi-return through", function()
    local id, name = Compat.GetSpecializationInfo(1)
    assertEqual(id, 253)
    assertEqual(name, "Beast Mastery")
end)

test("GetSpecialization falls back to the deprecated global when C_ is absent", function()
    local inst = T.load(false)
    inst.mocks.C_SpecializationInfo = nil
    inst.mocks.GetSpecialization = function() return 7 end
    assertEqual(inst.NS.Compat.GetSpecialization(), 7)
end)

test("GetSpecializationInfo falls back to the deprecated global when C_ is absent", function()
    local inst = T.load(false)
    inst.mocks.C_SpecializationInfo = nil
    inst.mocks.GetSpecializationInfo = function(i) return 100 + i, "Fallback" end
    local id, name = inst.NS.Compat.GetSpecializationInfo(3)
    assertEqual(id, 103)
    assertEqual(name, "Fallback")
end)

-- ---------------------------------------------------------------------------
-- Compat.DebugDuration — the 12.0 DurationObject capability probe
-- ---------------------------------------------------------------------------
--
-- Blizzard documents the DurationObject methods but NOT which of them return
-- secret-tainted values in combat, and midnight-quirks.md is a catalog of
-- APIs that look fine out of combat and error the moment it opens. This probe
-- answers that in-game without risking an error: every call is pcall'd and
-- every result rendered through the issecretvalue gate.

--- Build a mock DurationObject factory that mints a FRESH object per call,
--- matching the live API. `secretMethods` names methods whose return should
--- be treated as secret-tainted; `missing` names methods to omit entirely.
local function installDurationMock(inst, secretMethods, missing)
    local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
    inst.mocks.issecretvalue = function(v) return v == SECRET end
    secretMethods, missing = secretMethods or {}, missing or {}

    inst.mocks.C_Spell = inst.mocks.C_Spell or {}
    inst.mocks.C_Spell.GetSpellCooldownDuration = function()
        local o = {}
        local function def(name, value)
            if missing[name] then return end
            o[name] = function() if secretMethods[name] then return SECRET end return value end
        end
        def("HasSecretValues", false)
        def("GetRemainingDuration", 42.5)
        def("GetTotalDuration", 60)
        def("GetStartTime", 100)
        def("GetEndTime", 160)
        def("HasExpired", false)
        def("IsActive", true)
        def("IsZero", false)
        if not missing.Copy   then o.Copy   = function() return {} end end
        if not missing.Assign then o.Assign = function() return true end end
        return o
    end
end

local function runDebugVerb(inst, input)
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, msg) lines[#lines + 1] = msg end
    inst.NS:OnSlashCommand(input)
    frame.AddMessage = orig
    return table.concat(lines, "\n")
end

test("`/kcd debug duration` reports the API is unavailable on a pre-12.0 client", function()
    local inst = T.load(true)
    inst.mocks.C_Spell.GetSpellCooldownDuration = nil
    local out = runDebugVerb(inst, "debug duration 192058")
    assertTrue(out:find("unavailable", 1, true) ~= nil,
        "must say so plainly rather than erroring; got: " .. out)
end)

test("`/kcd debug duration` renders a secret return as <secret> instead of erroring", function()
    local inst = T.load(true)
    installDurationMock(inst, { GetRemainingDuration = true })
    local out = runDebugVerb(inst, "debug duration 192058")
    assertTrue(out:find("GetRemainingDuration", 1, true) ~= nil, "must probe the method")
    assertTrue(out:find("<secret>", 1, true) ~= nil,
        "a secret return must render as <secret>; got: " .. out)
end)

test("`/kcd debug duration` reports a plain return with its value", function()
    local inst = T.load(true)
    installDurationMock(inst)
    local out = runDebugVerb(inst, "debug duration 192058")
    assertTrue(out:find("GetTotalDuration", 1, true) ~= nil, "must probe GetTotalDuration")
    assertTrue(out:find("60", 1, true) ~= nil, "a plain value must be printed; got: " .. out)
end)

test("`/kcd debug duration` flags a method the client does not implement", function()
    local inst = T.load(true)
    installDurationMock(inst, nil, { HasSecretValues = true })
    local out = runDebugVerb(inst, "debug duration 192058")
    assertTrue(out:find("MISSING", 1, true) ~= nil,
        "an absent method must be called out; got: " .. out)
end)

test("`/kcd debug duration` confirms the API mints a fresh object per call", function()
    -- The whole reason StateChanged's identity compare spams: two fetches
    -- describing the same cooldown are never ==.
    local inst = T.load(true)
    installDurationMock(inst)
    local out = runDebugVerb(inst, "debug duration 192058")
    assertTrue(out:find("distinct", 1, true) ~= nil,
        "the identity check must be reported; got: " .. out)
end)
