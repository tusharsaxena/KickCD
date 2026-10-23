-- tests/test_sim_world.lua — the simulated world (modules/SimWorld.lua) and its seam providers.
--
-- KC-04 (KickCD#38; the Sim major's host contract H1). While a session runs, every client read the
-- engine makes is answered by the world on NS.SimHost.world, through providers registered once on
-- NS.SimSeam at file load: the player's cooldowns, the GCD and charges, and the target and focus
-- enemies with their casts. Spell identity (GetSpellInfo, the texture, availability, the spec) is
-- not provided: it answers live, the player's real spells (design D4).
--
-- Until modules/Sim.lua (KC-05) builds the live host, the session these cases run under is
-- tests/sim_support.lua's throwaway one (S.testSession), on each environment's own seam.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local KICK, CC = S.KICK, S.CC

--- A fresh environment with the clock moved off zero, so a start time of 0 never passes for t.
local function fresh(opts)
    local env = S.load(opts)
    env.advance(100)
    return env
end

--- Install a fresh world on env, run fn(env, world) inside a test session, then drop the world.
local function inWorld(env, fn)
    local NS = env.NS
    NS.SimHost.world = NS.SimWorld.Build({})
    local ok, err = pcall(S.withTestSession, env, { { kind = "Noop" } }, function(sim)
        fn(env, NS.SimHost.world, sim)
    end)
    NS.SimHost.world = nil
    if not ok then error(err, 0) end
end

--- Spy on NS.DeliverEvent: answers the count table and a restore function. The real dispatch still
--- runs, so the engine's handlers re-read the world exactly as they would in game.
local function spyDeliver(NS)
    local counts, real = {}, NS.DeliverEvent
    local order = {}
    NS.DeliverEvent = function(event, ...)
        counts[event] = (counts[event] or 0) + 1
        order[#order + 1] = event
        return real(event, ...)
    end
    return counts, order, function() NS.DeliverEvent = real end
end

--- Pack every return with its count.
local function pack(...) return { n = select("#", ...), ... } end

-- ── the module ──────────────────────────────────────────────────────────────

test("SimWorld: Build answers the empty world shape", function()
    local w = fresh().NS.SimWorld.Build({})
    assertTrue(type(w.units) == "table" and type(w.enemies) == "table" and type(w.spells) == "table")
    assertTrue(type(w.timers) == "table")
    assertNil(w.gcd)
    assertEqual(w.combat, false)
end)

test("TOC: modules/SimWorld.lua loads straight after modules/UnitLabel.lua", function()
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/UnitLabel.lua" then at = i end end
    assertTrue(at ~= nil, "modules/UnitLabel.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at + 1], "modules/SimWorld.lua")
end)

-- ── 1. cooldowns ────────────────────────────────────────────────────────────

test("SimWorld cooldowns: an idle spell answers ready, usable and a zeroed duration", function()
    inWorld(fresh(), function(env)
        local C = env.NS.Compat
        local r = pack(C.GetSpellCooldown(KICK))
        assertEqual(r.n, 5)
        assertEqual(r[1], 0); assertEqual(r[2], 0); assertEqual(r[3], false)
        assertEqual(r[4], 1); assertEqual(r[5], false)
        local u, noMana = C.IsSpellUsable(KICK)
        assertEqual(u, true); assertEqual(noMana, false)
        local d = C.GetSpellCooldownDuration(KICK)
        assertTrue(d ~= nil, "an idle spell answers a live but zeroed duration, never nil")
        assertEqual(d:GetTotalDuration(), 0)
    end)
end)

test("SimWorld cooldowns: StartCooldown answers t, 12, true, 1, true and a 12 s duration", function()
    inWorld(fresh(), function(env)
        local NS, t = env.NS, env.mocks.__now
        NS.SimWorld.StartCooldown(KICK, 12)
        local r = pack(NS.Compat.GetSpellCooldown(KICK))
        assertEqual(r[1], t); assertEqual(r[2], 12); assertEqual(r[3], true)
        assertEqual(r[4], 1); assertEqual(r[5], true)
        local d = NS.Compat.GetSpellCooldownDuration(KICK)
        assertEqual(d:GetTotalDuration(), 12)
        assertEqual(d:GetStartTime(), t)
    end)
end)

test("SimWorld cooldowns: the expiry timer clears the cooldown and fires SPELL_UPDATE_COOLDOWN once", function()
    inWorld(fresh(), function(env)
        local NS = env.NS
        NS.SimWorld.StartCooldown(KICK, 12)
        local counts, _, restore = spyDeliver(NS)
        env.advance(11)
        assertNil(counts.SPELL_UPDATE_COOLDOWN, "fired before the cooldown ran out")
        assertEqual(select(5, NS.Compat.GetSpellCooldown(KICK)), true)
        env.advance(1)
        restore()
        assertEqual(counts.SPELL_UPDATE_COOLDOWN, 1)
        assertEqual(select(5, NS.Compat.GetSpellCooldown(KICK)), false)
        assertNil(env.NS.SimHost.world.timers[KICK], "the handle outlived its timer")
    end)
end)

test("SimWorld cooldowns: ClearCooldown ends it at once and cancels the expiry timer", function()
    inWorld(fresh(), function(env)
        local NS = env.NS
        NS.SimWorld.StartCooldown(KICK, 12)
        NS.SimWorld.ClearCooldown(KICK)
        assertEqual(select(5, NS.Compat.GetSpellCooldown(KICK)), false)
        local counts, _, restore = spyDeliver(NS)
        env.advance(20)
        restore()
        assertNil(counts.SPELL_UPDATE_COOLDOWN, "a cleared cooldown's timer still fired")
    end)
end)

-- ── 2. GCD ──────────────────────────────────────────────────────────────────

test("SimWorld GCD: an on-GCD spell answers the GCD, an offGcd spell answers ready", function()
    inWorld(fresh(), function(env)
        local NS, t = env.NS, env.mocks.__now
        NS.SimWorld.MarkOffGcd(KICK)
        NS.SimWorld.StartGcd(1.5)
        local r = pack(NS.Compat.GetSpellCooldown(CC))
        assertEqual(r[1], t); assertEqual(r[2], 1.5); assertEqual(r[5], true)
        assertEqual(NS.Compat.GetSpellCooldownDuration(CC):GetTotalDuration(), 1.5)
        assertEqual(select(5, NS.Compat.GetSpellCooldown(KICK)), false)
        env.advance(1.5)
        assertEqual(select(5, NS.Compat.GetSpellCooldown(CC)), false, "the GCD outlived its 1.5 s")
    end)
end)

test("SimWorld GCD: an on-GCD spell's own longer cooldown wins over the GCD", function()
    inWorld(fresh(), function(env)
        local NS = env.NS
        NS.SimWorld.StartCooldown(CC, 60)
        NS.SimWorld.StartGcd(1.5)
        local r = pack(NS.Compat.GetSpellCooldown(CC))
        assertEqual(r[2], 60); assertEqual(r[5], true)
        assertEqual(NS.Compat.GetSpellCooldownDuration(CC):GetTotalDuration(), 60)
    end)
end)

-- ── 3. charges ──────────────────────────────────────────────────────────────

test("SimWorld charges: SetCharges, UseCharge, the recharge timer and the 0-charge lockout", function()
    inWorld(fresh(), function(env)
        local NS, W, C = env.NS, env.NS.SimWorld, env.NS.Compat
        assertNil(C.GetSpellCharges(KICK), "a spell without charges answers nil")
        W.SetCharges(KICK, 2)
        local r = pack(C.GetSpellCharges(KICK))
        assertEqual(r[1], 2); assertEqual(r[2], 2); assertEqual(r[3], 0); assertEqual(r[4], 0)

        local t = env.mocks.__now
        W.UseCharge(KICK, 15)
        r = pack(C.GetSpellCharges(KICK))
        assertEqual(r[1], 1); assertEqual(r[2], 2); assertEqual(r[3], t); assertEqual(r[4], 15)
        assertEqual(select(5, C.GetSpellCooldown(KICK)), false, "one charge left is not a lockout")

        W.UseCharge(KICK, 15)
        r = pack(C.GetSpellCooldown(KICK))
        assertEqual(r[5], true, "at 0 charges GetSpellCooldown answers isActive")
        assertEqual(r[1], t); assertEqual(r[2], 15)

        local counts, order, restore = spyDeliver(NS)
        env.advance(15)
        assertEqual(counts.SPELL_UPDATE_CHARGES, 1)
        assertEqual(order[1], "SPELL_UPDATE_CHARGES", "charges fire before the cooldown update")
        assertEqual(C.GetSpellCharges(KICK), 1)
        env.advance(15)
        restore()
        assertEqual(counts.SPELL_UPDATE_CHARGES, 2)
        r = pack(C.GetSpellCharges(KICK))
        assertEqual(r[1], 2); assertEqual(r[2], 2); assertEqual(r[3], 0); assertEqual(r[4], 0)
    end)
end)

-- ── 4. units and casts ──────────────────────────────────────────────────────

test("SimWorld units: target exists, is attackable and alive; party1 is absent; player exists", function()
    inWorld(fresh(), function(env)
        local W, C = env.NS.SimWorld, env.NS.Compat
        env.mocks.UnitExists = function() return true end   -- the live client must not leak in
        assertEqual(C.UnitExists("target"), false, "no enemy set: target is empty")
        W.SetUnit("target", "casterA")
        assertEqual(C.UnitExists("target"), true)
        assertEqual(C.UnitCanAttack("target"), true)
        assertEqual(C.UnitIsDead("target"), false)
        assertEqual(C.UnitExists("party1"), false)
        assertEqual(C.UnitExists("player"), true)
        assertEqual(C.UnitExists("focus"), false)
        W.Kill("casterA")
        assertEqual(C.UnitIsDead("target"), true)
        W.SetUnit("target", nil)
        assertEqual(C.UnitExists("target"), false)
    end)
end)

test("SimWorld casts: UnitCastingInfo answers the client's nine positions and a 3 s duration", function()
    inWorld(fresh(), function(env)
        local W, C = env.NS.SimWorld, env.NS.Compat
        W.AddEnemy("casterA", { name = "Caster A", hostile = true })
        W.SetUnit("target", "casterA")
        local t = env.mocks.__now
        W.StartCast("casterA", { spellID = 12345, name = "Shadow Bolt", texture = 136197,
            duration = 3, notInterruptible = false })
        local r = pack(C.UnitCastingInfo("target"))
        assertEqual(r.n, 9)
        assertEqual(r[1], "Shadow Bolt")
        assertEqual(r[3], 136197)
        assertEqual(r[4], t * 1000); assertEqual(r[5], (t + 3) * 1000)
        assertEqual(r[8], false)
        assertEqual(r[9], 12345)
        assertNil(C.UnitChannelInfo("target"))
        local d = C.UnitCastingDuration("target")
        assertEqual(d:GetTotalDuration(), 3)
        assertNil(C.UnitChannelDuration("target"))

        local rec = C.GetCastingInfo("target")
        assertTrue(rec ~= nil, "GetCastingInfo did not compose the cast")
        assertEqual(rec.name, "Shadow Bolt"); assertEqual(rec.spellID, 12345)
        assertEqual(rec.notInterruptible, false); assertEqual(rec.isChannel, false)
        assertEqual(rec.duration:GetTotalDuration(), 3)

        W.SetInterruptible("casterA", false)
        assertEqual(select(8, C.UnitCastingInfo("target")), true)
        W.EndCast("casterA")
        assertNil(C.UnitCastingInfo("target"))
        assertNil(C.GetCastingInfo("target"))
    end)
end)

test("SimWorld casts: a channel answers through UnitChannelInfo and nil through UnitCastingInfo", function()
    inWorld(fresh(), function(env)
        local W, C = env.NS.SimWorld, env.NS.Compat
        W.SetUnit("target", "casterB")
        W.StartCast("casterB", { spellID = 777, name = "Drain", texture = 1, duration = 5,
            notInterruptible = true, isChannel = true })
        assertNil(C.UnitCastingInfo("target"))
        local r = pack(C.UnitChannelInfo("target"))
        assertEqual(r[1], "Drain")
        assertEqual(r[7], true)
        assertEqual(r[8], 777)
        assertEqual(C.UnitChannelDuration("target"):GetTotalDuration(), 5)
        assertNil(C.UnitCastingDuration("target"))
        local rec = C.GetCastingInfo("target")
        assertEqual(rec.isChannel, true); assertEqual(rec.spellID, 777)
    end)
end)

test("SimWorld casts: the same enemy set as focus answers the same cast on focus", function()
    inWorld(fresh(), function(env)
        local W, C = env.NS.SimWorld, env.NS.Compat
        W.SetUnit("target", "casterA")
        W.SetUnit("focus", "casterA")
        W.StartCast("casterA", { spellID = 42, name = "Fireball", duration = 3 })
        assertEqual(C.UnitExists("focus"), true)
        assertEqual(select(9, C.UnitCastingInfo("focus")), 42)
        assertEqual(select(9, C.UnitCastingInfo("target")), 42)
        assertEqual(C.GetCastingInfo("focus").name, "Fireball")
    end)
end)

-- ── 5-7. idle seam, no world, CanBuild ──────────────────────────────────────

test("SimWorld idle: with no session every member answers the live client", function()
    local env = fresh()
    local NS, C = env.NS, env.NS.Compat
    NS.SimHost.world = NS.SimWorld.Build({})
    NS.SimWorld.SetUnit("target", "casterA")
    env.mocks.UnitExists = function(unit) return unit == "party1" end
    env.mocks.UnitCastingInfo = function() return "Live" end
    assertEqual(C.UnitExists("party1"), true)
    assertEqual(C.UnitExists("target"), false)
    assertEqual(C.UnitCastingInfo("target"), "Live")
    NS.SimHost.world = nil
end)

test("SimWorld no world while active: the providers answer fallback(...)", function()
    local env = fresh()
    local NS, C = env.NS, env.NS.Compat
    env.mocks.UnitExists = function(unit) return unit == "party1" end
    env.mocks.UnitCastingInfo = function() return "Live" end
    S.withTestSession(env, { { kind = "Noop" } }, function(sim)
        assertTrue(sim:IsActive(), "sanity: the session is running")
        assertNil(NS.SimHost.world)
        assertEqual(C.UnitExists("party1"), true)
        assertEqual(C.UnitExists("player"), false)
        assertEqual(C.UnitCastingInfo("target"), "Live")
        local live = pack(NS.SimSeam:Live(C.GetSpellCooldown, KICK))
        local seen = pack(C.GetSpellCooldown(KICK))
        assertEqual(seen.n, live.n)
        for i = 1, live.n do assertEqual(seen[i], live[i]) end
    end)
end)

test("SimWorld.CanBuild: true with a duration constructor, false when NewDuration answers nil", function()
    assertEqual(fresh().NS.SimWorld.CanBuild(), true)
    local env = fresh({ mutate = function(mocks) mocks.C_DurationUtil = nil end })
    assertNil(env.NS.Compat.NewDuration(1, 1), "sanity: no constructor on this client")
    assertEqual(env.NS.SimWorld.CanBuild(), false)
end)

test("SimWorld: the mutators are no-ops with no world installed", function()
    local NS = fresh().NS
    local W = NS.SimWorld
    W.SetUnit("target", "x"); W.AddEnemy("x", {}); W.Kill("x")
    W.StartCast("x", { duration = 1 }); W.EndCast("x"); W.SetInterruptible("x", true)
    W.StartCooldown(KICK, 1); W.ClearCooldown(KICK); W.StartGcd(1.5)
    W.SetCharges(KICK, 2); W.UseCharge(KICK, 1); W.MarkOffGcd(KICK)
    assertNil(NS.SimHost.world, "a mutator built a world of its own")
    assertFalse(NS.SimWorld.CanBuild() == nil, "CanBuild answers a boolean")
end)
