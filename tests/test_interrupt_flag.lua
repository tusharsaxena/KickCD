-- tests/test_interrupt_flag.lua -- a cast's notInterruptible when the client hands nil
-- (MKF-KC-05, the WoW Forever port; kc-code 3.1, factcheck 20 and 43).
--
-- UnitCastingInfo's notInterruptible (position 8) and UnitChannelInfo's (position 7) are documented
-- `Nilable = true` on both clients, while the two sinks they feed take `bool, Nilable = false`:
-- Frame:SetAlphaFromBoolean and C_CurveUtil.EvaluateColorValueFromBoolean. Retail evidently never
-- hands nil for a live cast; on WoW Forever it is UNKNOWN. So a PLAIN nil reads false (the cast is
-- interruptible, as `not nil` already read it in the grid's gate), and a secret passes through
-- untouched, tested before anything else looks at it. Both clients, one rule.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local CLIENTS = { { label = "retail" }, { label = "forever", world = "forever" } }

--- An instance whose target is a hostile caster whose flag is `flag` (nil included), on a cast or
--- a channel; typed secrets installed, so a secret flag is a real stand-in.
local function caster(client, flag, channel)
    return T.load(false, false, function(m)
        T.typedSecrets(m)
        m.UnitExists = function(unit) return unit == "target" end
        m.UnitCanAttack = function() return true end
        if channel then
            m.UnitChannelInfo = function() return "Drain", "Drain", 136, 0, 3000, false, flag, 689 end
        else
            m.UnitCastingInfo = function() return "Bolt", "Bolt", 136, 0, 2500, false, 77, flag, 686 end
        end
    end, { world = client.world })
end

test("GetCastingInfo: a plain nil notInterruptible reads false, on both clients", function()
    for _, client in ipairs(CLIENTS) do
        local rec = caster(client, nil).NS.Compat.GetCastingInfo("target")
        assertTrue(rec ~= nil, client.label .. ": a cast")
        assertEqual(rec.notInterruptible, false, client.label .. ": nil is interruptible")
    end
end)

test("GetChannelInfo: a plain nil notInterruptible reads false, on both clients", function()
    for _, client in ipairs(CLIENTS) do
        local rec = caster(client, nil, true).NS.Compat.GetChannelInfo("target")
        assertEqual(rec.notInterruptible, false, client.label)
    end
end)

test("the cast record keeps a plain flag, and a secret one untouched", function()
    for _, client in ipairs(CLIENTS) do
        assertEqual(caster(client, true).NS.Compat.GetCastingInfo("target").notInterruptible, true, client.label)
        assertEqual(caster(client, false).NS.Compat.GetCastingInfo("target").notInterruptible, false, client.label)
        local secret = T.secret(true)
        local rec = caster(client, secret).NS.Compat.GetCastingInfo("target")
        assertTrue(rawequal(rec.notInterruptible, secret), client.label .. ": the secret reaches the sink as it came")
    end
end)

test("ApplyInterruptibleAlpha hands SetAlphaFromBoolean false for a plain nil, on both clients", function()
    for _, client in ipairs(CLIENTS) do
        for _, channel in ipairs({ false, true }) do
            local NS = caster(client, nil, channel).NS
            local seen = {}
            local frame = { SetAlphaFromBoolean = function(_, flag) seen[#seen + 1] = { flag } end }
            assertTrue(NS.State.ApplyInterruptibleAlpha(frame, "target", 1))
            assertEqual(seen[1][1], false, client.label .. (channel and " channel" or " cast") .. ": never a nil")
        end
    end
end)

test("ApplyInterruptibleAlpha passes a secret flag through untouched", function()
    local secret = T.secret(false)
    local NS = caster(CLIENTS[2], secret).NS
    local seen
    local frame = { SetAlphaFromBoolean = function(_, flag) seen = flag end }
    assertTrue(NS.State.ApplyInterruptibleAlpha(frame, "target", 1))
    assertTrue(rawequal(seen, secret))
end)
