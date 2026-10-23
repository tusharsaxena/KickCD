-- tests/test_sim_drivers.lua — the simulator's step drivers (modules/SimDrivers.lua).
--
-- KC-07 (KickCD#38; design-kc-sim §5.3). One driver per step kind: each edits the world through the
-- NS.SimWorld mutators, then fires the client's events in client order through NS.Sim:Fire, and
-- answers the step's one-line detail. The drivers are STATE-DRIVEN: a kick reads the world first, so
-- a paused run, a click-ahead or a long step delay never prints a false `[sim]` line.
--
-- Every case runs inside the addon's own NS.Sim on tests/sim_support.lua's injected `test` scenario
-- (bare hooks), with a fresh world installed and "your kick" / "your CC" resolved to the fixture's
-- Wind Shear and Capacitor Totem. NS.DeliverEvent is spied (the real dispatch still runs) and
-- NS.Util.print captured, so each case asserts the exact event sequence, the world edit, the detail
-- and the narration.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local S = dofile(T.root .. "/tests/sim_support.lua")

local KICK, CC = S.KICK, S.CC
local ENEMY_SPELL, CHANNEL_SPELL = 300001, 300002

--- A fresh environment with the clock moved off zero.
local function fresh(opts)
    local env = S.load(opts)
    env.advance(100)
    return env
end

--- Run fn(ctx) inside a test session over a fresh world. ctx = { env, NS, D, W, world, sim,
--- events (each { name, args... }), lines (printed), play(step) -> detail, names() }.
local function inSession(fn, opts)
    local env = fresh(opts)
    local NS = env.NS
    local ctx = { env = env, NS = NS, D = NS.SimDrivers, W = NS.SimWorld, events = {}, lines = {} }
    local realDeliver, realPrint = NS.DeliverEvent, NS.Util.print
    NS.DeliverEvent = function(event, ...)
        ctx.events[#ctx.events + 1] = { event, ... }
        return realDeliver(event, ...)
    end
    NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        ctx.lines[#ctx.lines + 1] = table.concat(parts, " ")
    end
    function ctx.play(step) return ctx.D.DRIVERS[step.kind](step) end
    function ctx.names()
        local out = {}
        for i, e in ipairs(ctx.events) do out[i] = e[1] end
        return table.concat(out, ",")
    end
    function ctx.reset() ctx.events, ctx.lines = {}, {} end
    local ok, err = pcall(S.withTestSession, env, { { kind = "Noop" } }, function(sim)
        ctx.sim = sim
        NS.SimHost.world = NS.SimWorld.Build({})
        NS.SimHost.kick, NS.SimHost.cc = KICK, CC
        NS.SimWorld.MarkOffGcd(KICK)
        ctx.world = NS.SimHost.world
        ctx.reset()
        fn(ctx)
    end)
    NS.DeliverEvent, NS.Util.print = realDeliver, realPrint
    NS.SimHost.world = nil
    if not ok then error(err, 0) end
end

--- The `[sim] ...` line for `fmt` formatted with the rest, as the host prints it.
local function simLine(NS, fmt, ...)
    return NS.L["[sim] %s"]:format(NS.L[fmt]:format(...))
end

local function spellName(NS, id) return (NS.Compat.GetSpellInfo(id)) end

--- Put enemy `key` on `units` (a list of "target" / "focus") and start a cast on it.
local function casting(ctx, key, units, castStep)
    for _, unit in ipairs(units) do ctx.play({ kind = unit == "target" and "Target" or "Focus", enemy = key }) end
    ctx.play(castStep or { kind = "CastStart", enemy = key, spell = ENEMY_SPELL, duration = 3 })
    ctx.reset()
end

-- ── the module ──────────────────────────────────────────────────────────────

test("SimDrivers: the module publishes DRIVERS and EVENTS, one EVENTS row per driver", function()
    local NS = fresh().NS
    local D = NS.SimDrivers
    assertTrue(type(D) == "table" and type(D.DRIVERS) == "table" and type(D.EVENTS) == "table")
    for _, kind in ipairs({ "Setup", "Combat", "Target", "Focus", "CastStart", "ChannelStart", "Interruptible",
        "Kick", "PartyKick", "Complete", "Cc", "Die", "Leave", "Expire" }) do
        assertTrue(type(D.DRIVERS[kind]) == "function", "no driver for " .. kind)
        assertTrue(type(D.EVENTS[kind]) == "table" and #D.EVENTS[kind] > 0, "no EVENTS row for " .. kind)
    end
    for kind in pairs(D.EVENTS) do assertTrue(D.DRIVERS[kind] ~= nil, "EVENTS row without a driver: " .. kind) end
    assertEqual(D.KICK_CD, 15); assertEqual(D.CC_CD, 30); assertEqual(D.GCD, 1.5); assertEqual(D.RECHARGE, 15)
end)

test("TOC: modules/SimDrivers.lua loads between modules/SimWorld.lua and modules/Sim.lua", function()
    local at
    for i, rel in ipairs(T.tocFiles) do if rel == "modules/SimDrivers.lua" then at = i end end
    assertTrue(at ~= nil, "modules/SimDrivers.lua is not in KickCD.toc")
    assertEqual(T.tocFiles[at - 1], "modules/SimWorld.lua")
    assertEqual(T.tocFiles[at + 1], "modules/Sim.lua")
end)

test("SimDrivers: the host's Play runs the driver and the step tip names its events", function()
    inSession(function(ctx)
        local NS = ctx.NS
        local detail = NS.SimHost.Play({ kind = "Combat", on = true })
        assertEqual(detail, NS.L["in combat"])
        local tip = NS.SimHost.StepTip({ kind = "Combat" })
        assertEqual(tip[1][1], NS.L["Fires"])
        assertTrue(tip[1][2]:find("PLAYER_REGEN_DISABLED", 1, true) ~= nil)
    end)
end)

-- ── combat and unit changes ─────────────────────────────────────────────────

test("SimDrivers Combat: on fires PLAYER_REGEN_DISABLED, marks the session, and the engine enters combat", function()
    inSession(function(ctx)
        local NS = ctx.NS
        local detail = ctx.play({ kind = "Combat", on = true })
        assertEqual(ctx.names(), "PLAYER_REGEN_DISABLED")
        assertEqual(ctx.world.combat, true)
        assertEqual(NS.Sim:Session().simCombat, true)
        assertEqual(NS.State.inCombat, true)
        assertEqual(detail, NS.L["in combat"])
        ctx.reset()
        assertEqual(ctx.play({ kind = "Combat", on = false }), NS.L["out of combat"])
        assertEqual(ctx.names(), "PLAYER_REGEN_ENABLED")
        assertEqual(ctx.world.combat, false)
        assertEqual(NS.Sim:Session().simCombat, false)
        assertEqual(NS.State.inCombat, false)
        assertEqual(#ctx.lines, 0)
    end)
end)

test("SimDrivers Setup: your kick gets the step's charges, all ready, then SPELL_UPDATE_CHARGES", function()
    inSession(function(ctx)
        local NS = ctx.NS
        local detail = ctx.play({ kind = "Setup", charges = 2 })
        assertEqual(ctx.names(), "SPELL_UPDATE_CHARGES")
        local s = ctx.world.spells[KICK]
        assertEqual(s.maxCharges, 2); assertEqual(s.charges, 2)
        assertEqual(s.offGcd, true, "the kick stays off the GCD")
        assertEqual((NS.Compat.GetSpellCharges(KICK)), 2)
        assertEqual(detail, NS.L["%s: %d charges"]:format(spellName(NS, KICK), 2))
        assertEqual(#ctx.lines, 0)
        ctx.reset()
        NS.SimHost.kick = nil
        assertEqual(ctx.play({ kind = "Setup", charges = 2 }), NS.L["no kick tracked"])
        assertEqual(ctx.names(), "", "with no kick resolved Setup fires nothing")
    end)
end)

test("SimDrivers Target / Focus: set the unit (named from the scenario's enemies) and fire the change", function()
    inSession(function(ctx)
        local NS = ctx.NS
        NS.SimScenario = { ENEMIES = { casterA = { name = "Shadowcaster" } }, PARTY = {} }
        local detail = ctx.play({ kind = "Target", enemy = "casterA" })
        assertEqual(ctx.names(), "PLAYER_TARGET_CHANGED")
        assertEqual(ctx.world.units.target, "casterA")
        assertEqual(ctx.world.enemies.casterA.name, "Shadowcaster")
        assertEqual(detail, NS.L["target: %s"]:format("Shadowcaster"))
        assertTrue(NS.Compat.UnitExists("target"))
        ctx.reset()
        ctx.play({ kind = "Focus", enemy = "casterB" })
        assertEqual(ctx.names(), "PLAYER_FOCUS_CHANGED")
        assertEqual(ctx.world.units.focus, "casterB")
        assertEqual(ctx.world.enemies.casterB.name, "casterB")
        ctx.reset()
        assertEqual(ctx.play({ kind = "Focus" }), NS.L["focus cleared"])
        assertEqual(ctx.names(), "PLAYER_FOCUS_CHANGED")
        assertNil(ctx.world.units.focus)
        assertFalse(NS.Compat.UnitExists("focus"))
    end)
end)

-- ── an enemy cast begins or changes ─────────────────────────────────────────

test("SimDrivers CastStart: fires UNIT_SPELLCAST_START for every unit showing the enemy", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.play({ kind = "Target", enemy = "a" })
        ctx.play({ kind = "Focus", enemy = "a" })
        ctx.reset()
        local detail = ctx.play({ kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3 })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_START,UNIT_SPELLCAST_START")
        local guid = ctx.world.enemies.a.cast.castGUID
        assertTrue(type(guid) == "string" and guid:find("^Cast%-sim%-%d+$") ~= nil, "castGUID " .. tostring(guid))
        assertEqual(ctx.events[1][2], "target"); assertEqual(ctx.events[1][3], guid)
        assertEqual(ctx.events[1][4], ENEMY_SPELL)
        assertEqual(ctx.events[2][2], "focus")
        assertEqual(ctx.world.enemies.a.cast.notInterruptible, false)
        assertEqual(ctx.world.enemies.a.cast.isChannel, false)
        assertEqual(ctx.world.enemies.a.cast.name, spellName(NS, ENEMY_SPELL))
        assertEqual(select(9, NS.Compat.UnitCastingInfo("target")), ENEMY_SPELL)
        assertEqual(detail, NS.L["%s casts %s"]:format("a", spellName(NS, ENEMY_SPELL)))
    end)
end)

test("SimDrivers CastStart: an uninterruptible cast, shown on no unit, fires nothing", function()
    inSession(function(ctx)
        ctx.play({ kind = "CastStart", enemy = "b", spell = ENEMY_SPELL, duration = 3, uninterruptible = true })
        assertEqual(ctx.names(), "")
        assertEqual(ctx.world.enemies.b.cast.notInterruptible, true)
    end)
end)

test("SimDrivers ChannelStart: fires UNIT_SPELLCAST_CHANNEL_START with (unit, castGUID, spellID)", function()
    inSession(function(ctx)
        ctx.play({ kind = "Focus", enemy = "b" })
        ctx.reset()
        ctx.play({ kind = "ChannelStart", enemy = "b", spell = CHANNEL_SPELL, duration = 5 })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_CHANNEL_START")
        assertEqual(ctx.events[1][2], "focus")
        assertEqual(ctx.events[1][4], CHANNEL_SPELL)
        assertEqual(ctx.world.enemies.b.cast.isChannel, true)
        assertEqual(select(8, ctx.NS.Compat.UnitChannelInfo("focus")), CHANNEL_SPELL)
    end)
end)

test("SimDrivers Interruptible: flips the flag and fires UNIT_SPELLCAST_INTERRUPTIBLE", function()
    inSession(function(ctx)
        casting(ctx, "a", { "target" },
            { kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3, uninterruptible = true })
        ctx.play({ kind = "Interruptible", enemy = "a" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_INTERRUPTIBLE")
        assertEqual(ctx.events[1][2], "target")
        assertEqual(ctx.world.enemies.a.cast.notInterruptible, false)
    end)
end)

-- ── the player's kick ───────────────────────────────────────────────────────

test("SimDrivers Kick (a): no cast narrates, fires nothing, and answers `no cast`", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.play({ kind = "Target", enemy = "a" })
        ctx.reset()
        local detail = ctx.play({ kind = "Kick", enemy = "a" })
        assertEqual(ctx.names(), "")
        assertEqual(detail, NS.L["no cast"])
        assertEqual(table.concat(ctx.lines, "\n"),
            simLine(NS, "%s: %s is not casting, so there is nothing to kick.", spellName(NS, KICK), "a"))
        assertNil(ctx.world.spells[KICK].start, "a refused kick must not start the cooldown")
    end)
end)

test("SimDrivers Kick (b): an uninterruptible cast narrates and fires nothing", function()
    inSession(function(ctx)
        local NS = ctx.NS
        casting(ctx, "a", { "target" },
            { kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3, uninterruptible = true })
        assertEqual(ctx.play({ kind = "Kick", enemy = "a" }), NS.L["uninterruptible"])
        assertEqual(ctx.names(), "")
        assertEqual(#ctx.lines, 1)
        assertTrue(ctx.lines[1]:find("cast is uninterruptible", 1, true) ~= nil, ctx.lines[1])
        assertTrue(ctx.world.enemies.a.cast ~= nil, "the cast goes on")
    end)
end)

test("SimDrivers Kick (d): lands: cooldown, then SUCCEEDED, SPELL_UPDATE_COOLDOWN and INTERRUPTED per unit", function()
    inSession(function(ctx)
        local NS = ctx.NS
        casting(ctx, "a", { "target", "focus" })
        local guid = ctx.world.enemies.a.cast.castGUID
        local detail = ctx.play({ kind = "Kick", enemy = "a" })
        assertEqual(ctx.names(),
            "UNIT_SPELLCAST_SUCCEEDED,SPELL_UPDATE_COOLDOWN,UNIT_SPELLCAST_INTERRUPTED,UNIT_SPELLCAST_INTERRUPTED")
        assertEqual(ctx.events[1][2], "player"); assertEqual(ctx.events[1][4], KICK)
        assertTrue(ctx.events[1][3] ~= guid)
        assertEqual(ctx.events[3][2], "target"); assertEqual(ctx.events[3][3], guid)
        assertEqual(ctx.events[3][4], ENEMY_SPELL)
        assertEqual(ctx.events[4][2], "focus")
        assertNil(ctx.world.enemies.a.cast)
        local start, dur = NS.Compat.GetSpellCooldown(KICK)
        assertTrue(start > 0); assertEqual(dur, 15)
        assertEqual(detail, NS.L["kicked %s"]:format("a"))
        assertEqual(#ctx.lines, 0)
    end)
end)

test("SimDrivers Kick (d): a channel ends with UNIT_SPELLCAST_CHANNEL_STOP", function()
    inSession(function(ctx)
        casting(ctx, "b", { "focus" }, { kind = "ChannelStart", enemy = "b", spell = CHANNEL_SPELL, duration = 5 })
        ctx.play({ kind = "Kick", enemy = "b" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_SUCCEEDED,SPELL_UPDATE_COOLDOWN,UNIT_SPELLCAST_CHANNEL_STOP")
        assertNil(ctx.world.enemies.b.cast)
    end)
end)

test("SimDrivers Kick (c): on cooldown narrates the seconds left, fires nothing, and the cast goes on", function()
    inSession(function(ctx)
        local NS = ctx.NS
        casting(ctx, "a", { "target" })
        ctx.play({ kind = "Kick", enemy = "a" })
        ctx.env.advance(4)
        ctx.play({ kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3 })
        ctx.reset()
        assertEqual(ctx.play({ kind = "Kick", enemy = "a" }), NS.L["on cooldown"])
        assertEqual(ctx.names(), "")
        assertEqual(table.concat(ctx.lines, "\n"),
            simLine(NS, "%s: your kick is on cooldown (%ds).", spellName(NS, KICK), 11))
        assertTrue(ctx.world.enemies.a.cast ~= nil)
    end)
end)

test("SimDrivers Kick (d): a charge spell spends a charge and also fires SPELL_UPDATE_CHARGES", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.W.SetCharges(KICK, 2)
        casting(ctx, "a", { "target" })
        ctx.play({ kind = "Kick", enemy = "a" })
        assertEqual(ctx.names(),
            "UNIT_SPELLCAST_SUCCEEDED,SPELL_UPDATE_COOLDOWN,SPELL_UPDATE_CHARGES,UNIT_SPELLCAST_INTERRUPTED")
        assertEqual((NS.Compat.GetSpellCharges(KICK)), 1)
        assertEqual(ctx.world.spells[KICK].chargeDuration, 15)
        -- The last charge goes, then a third kick finds none left: refused with the recharge time.
        ctx.play({ kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3 })
        ctx.play({ kind = "Kick", enemy = "a" })
        assertEqual((NS.Compat.GetSpellCharges(KICK)), 0)
        ctx.play({ kind = "CastStart", enemy = "a", spell = ENEMY_SPELL, duration = 3 })
        ctx.reset()
        assertEqual(ctx.play({ kind = "Kick", enemy = "a" }), NS.L["on cooldown"])
        assertEqual(ctx.names(), "")
        assertEqual(table.concat(ctx.lines, "\n"),
            simLine(NS, "%s: your kick is on cooldown (%ds).", spellName(NS, KICK), 15))
    end)
end)

test("SimDrivers Kick: with no kick resolved it narrates and fires nothing", function()
    inSession(function(ctx)
        local NS = ctx.NS
        NS.SimHost.kick = nil
        casting(ctx, "a", { "target" })
        assertEqual(ctx.play({ kind = "Kick", enemy = "a" }), NS.L["no kick tracked"])
        assertEqual(ctx.names(), "")
        assertEqual(table.concat(ctx.lines, "\n"), simLine(NS, "No kick is tracked, so nothing is kicked."))
    end)
end)

-- ── a party member's kick, a completed cast, crowd control ──────────────────

local PARTY = { thrall = { name = "Thrall", spec = "Enhancement", spell = 57994 } }

test("SimDrivers PartyKick: narrates the member, spec, enemy and spell, then fires INTERRUPTED", function()
    inSession(function(ctx)
        local NS = ctx.NS
        NS.SimScenario = { PARTY = PARTY, ENEMIES = { a = { name = "Shadowcaster" } } }
        casting(ctx, "a", { "target" })
        local detail = ctx.play({ kind = "PartyKick", member = "thrall", enemy = "a" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_INTERRUPTED")
        assertEqual(table.concat(ctx.lines, "\n"),
            simLine(NS, "%s (%s) interrupts %s with %s.", "Thrall", "Enhancement", "Shadowcaster",
                spellName(NS, 57994)))
        assertNil(ctx.world.enemies.a.cast)
        assertEqual(detail, NS.L["%s interrupts"]:format("Thrall"))
        assertNil(ctx.world.spells[KICK].start, "a party kick never touches your cooldowns")
    end)
end)

test("SimDrivers PartyKick: with no cast only narrates", function()
    inSession(function(ctx)
        local NS = ctx.NS
        NS.SimScenario = { PARTY = PARTY, ENEMIES = {} }
        ctx.play({ kind = "Target", enemy = "a" })
        ctx.reset()
        assertEqual(ctx.play({ kind = "PartyKick", member = "thrall", enemy = "a" }), NS.L["no cast"])
        assertEqual(ctx.names(), "")
        assertEqual(table.concat(ctx.lines, "\n"),
            simLine(NS, "%s (%s) has nothing to interrupt on %s.", "Thrall", "Enhancement", "a"))
    end)
end)

test("SimDrivers Complete: fires SUCCEEDED then STOP for each unit and ends the cast", function()
    inSession(function(ctx)
        casting(ctx, "a", { "target" })
        ctx.play({ kind = "Complete", enemy = "a" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_SUCCEEDED,UNIT_SPELLCAST_STOP")
        assertEqual(ctx.events[1][2], "target"); assertEqual(ctx.events[1][4], ENEMY_SPELL)
        assertNil(ctx.world.enemies.a.cast)
        ctx.reset()
        casting(ctx, "b", { "focus" }, { kind = "ChannelStart", enemy = "b", spell = CHANNEL_SPELL, duration = 5 })
        ctx.play({ kind = "Complete", enemy = "b" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_SUCCEEDED,UNIT_SPELLCAST_CHANNEL_STOP")
        ctx.reset()
        assertEqual(ctx.play({ kind = "Complete", enemy = "b" }), ctx.NS.L["no cast"])
        assertEqual(ctx.names(), "")
    end)
end)

test("SimDrivers Cc: starts the 30 s CC cooldown and a 1.5 s GCD, fires SUCCEEDED and the cooldown update", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.play({ kind = "Target", enemy = "a" })
        ctx.reset()
        ctx.play({ kind = "Cc", enemy = "a" })
        assertEqual(ctx.names(), "UNIT_SPELLCAST_SUCCEEDED,SPELL_UPDATE_COOLDOWN")
        assertEqual(ctx.events[1][2], "player"); assertEqual(ctx.events[1][4], CC)
        local _, dur = NS.Compat.GetSpellCooldown(CC)
        assertEqual(dur, 30)
        assertEqual(ctx.world.gcd.duration, 1.5)
        local _, hexDur = NS.Compat.GetSpellCooldown(S.HEX)
        assertEqual(hexDur, 1.5, "an on-GCD spell shows the GCD")
        assertEqual((select(2, NS.Compat.GetSpellCooldown(KICK))), 0, "the kick is off the GCD")
        assertEqual(table.concat(ctx.lines, "\n"), simLine(NS, "You use %s on %s.", spellName(NS, CC), "a"))
    end)
end)

test("SimDrivers Cc: no CC resolved narrates only; a CC still cooling refuses truthfully", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.play({ kind = "Cc", enemy = "a" })
        ctx.reset()
        assertEqual(ctx.play({ kind = "Cc", enemy = "a" }), NS.L["on cooldown"])
        assertEqual(ctx.names(), "")
        NS.SimHost.cc = nil
        ctx.reset()
        assertEqual(ctx.play({ kind = "Cc", enemy = "a" }), NS.L["no crowd control tracked"])
        assertEqual(ctx.names(), "")
        assertEqual(table.concat(ctx.lines, "\n"), simLine(NS, "No crowd control is tracked, so nothing is cast on %s.", "a"))
    end)
end)

-- ── other world changes ─────────────────────────────────────────────────────

test("SimDrivers Die: kills, ends the cast with STOP, and clears target and focus that show it", function()
    inSession(function(ctx)
        local NS = ctx.NS
        casting(ctx, "a", { "target", "focus" })
        ctx.play({ kind = "Die", enemy = "a" })
        assertEqual(ctx.names(),
            "UNIT_SPELLCAST_STOP,UNIT_SPELLCAST_STOP,PLAYER_TARGET_CHANGED,PLAYER_FOCUS_CHANGED")
        assertEqual(ctx.world.enemies.a.dead, true)
        assertNil(ctx.world.enemies.a.cast)
        assertNil(ctx.world.units.target); assertNil(ctx.world.units.focus)
        assertFalse(NS.Compat.UnitExists("target"))
    end)
end)

test("SimDrivers Die: an enemy shown on no unit and not casting fires nothing", function()
    inSession(function(ctx)
        ctx.play({ kind = "Target", enemy = "a" })
        ctx.reset()
        ctx.play({ kind = "Die", enemy = "b" })
        assertEqual(ctx.names(), "")
        assertEqual(ctx.world.units.target, "a")
    end)
end)

test("SimDrivers Leave: narrates, then fires GROUP_ROSTER_UPDATE to no handler without raising", function()
    inSession(function(ctx)
        local NS = ctx.NS
        NS.SimScenario = { PARTY = { valeera = { name = "Valeera", spec = "Subtlety", spell = 1766 } } }
        local detail = ctx.play({ kind = "Leave", member = "valeera" })
        assertEqual(ctx.names(), "GROUP_ROSTER_UPDATE")
        assertEqual(table.concat(ctx.lines, "\n"), simLine(NS, "%s (%s) leaves the party.", "Valeera", "Subtlety"))
        assertEqual(NS.Sim:Fire("GROUP_ROSTER_UPDATE"), 0)
        assertEqual(detail, NS.L["%s left"]:format("Valeera"))
        assertTrue(NS.Sim:IsActive(), "a simulated roster update never stops the session")
    end)
end)

test("SimDrivers Expire: kick: cancels the timer, clears the cooldown and fires SPELL_UPDATE_COOLDOWN", function()
    inSession(function(ctx)
        local NS = ctx.NS
        casting(ctx, "a", { "target" })
        ctx.play({ kind = "Kick", enemy = "a" })
        ctx.reset()
        ctx.play({ kind = "Expire", spell = "kick" })
        assertEqual(ctx.names(), "SPELL_UPDATE_COOLDOWN")
        assertEqual((select(2, NS.Compat.GetSpellCooldown(KICK))), 0)
        assertNil(ctx.world.timers[KICK])
        ctx.reset()
        ctx.env.advance(20)
        assertEqual(ctx.names(), "", "the canceled timer never fires")
    end)
end)

test("SimDrivers Expire: a charge spell is back to full and fires CHARGES then COOLDOWN; cc resolves too", function()
    inSession(function(ctx)
        local NS = ctx.NS
        ctx.W.SetCharges(KICK, 2)
        casting(ctx, "a", { "target" })
        ctx.play({ kind = "Kick", enemy = "a" })
        ctx.reset()
        ctx.play({ kind = "Expire", spell = "kick" })
        assertEqual(ctx.names(), "SPELL_UPDATE_CHARGES,SPELL_UPDATE_COOLDOWN")
        assertEqual((NS.Compat.GetSpellCharges(KICK)), 2)
        ctx.play({ kind = "Cc", enemy = "a" })
        ctx.reset()
        ctx.play({ kind = "Expire", spell = "cc" })
        assertEqual(ctx.names(), "SPELL_UPDATE_COOLDOWN")
        assertNil(ctx.world.spells[CC].start, "the CC's own cooldown is gone (the GCD may still run)")
    end)
end)
