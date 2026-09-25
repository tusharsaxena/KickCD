-- tests/test_compat_api.lua — core/Compat.lua's spell + cast/channel shims.
--
-- Companion to test_compat.lua, which covers only the spec shims. Compat is
-- the addon's ONE seam onto the deprecated/renamed client APIs (compat), and
-- almost every function is a modern-first, deprecated-fallback pair. Neither
-- half is exercised in the client the developer happens to be running, so
-- both branches have to be pinned here: an unreachable fallback is a broken
-- addon the day Blizzard removes the modern call, and an unreachable modern
-- path is a deprecation warning nobody sees.
--
-- The record-building shims (GetCastingInfo / GetChannelInfo) additionally
-- carry the 12.0 secret-value contract: values come out of the Unit* APIs and
-- go into the record UNINSPECTED. Tests below feed them values that error on
-- any read, which is the only way to prove the shim didn't peek.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

--- Fresh instance with reshapeable APIs. Compat reads _G.* at call time, so
--- post-load mock edits take effect.
local function fresh()
    local inst = T.load(false)
    return inst.NS.Compat, inst.mocks
end

--- A value that errors on every Lua operation Blizzard's secret protection
--- covers. Standing in for a secret-tainted return: if a shim touches it in
--- any way beyond passing it along, the test fails loudly instead of silently
--- passing on a mock that was too permissive.
local function landmine(label)
    return setmetatable({}, {
        __tostring = function() error("tostring() on " .. label, 0) end,
        __concat   = function() error("concat on " .. label, 0) end,
        __len      = function() error("# on " .. label, 0) end,
        __add      = function() error("arithmetic on " .. label, 0) end,
        __lt       = function() error("compare on " .. label, 0) end,
        __le       = function() error("compare on " .. label, 0) end,
    })
end

-- ── _firstReturn ────────────────────────────────────────────────────────────

test("Compat._firstReturn tolerates a nil API (pre-12.0 client)", function()
    local Compat = fresh()
    assertNil(Compat._firstReturn(nil, "target"))
end)

test("Compat._firstReturn collapses a multi-return to position 1", function()
    -- The whole reason it exists: callers truth-test the NAME slot, and a
    -- bare call in a boolean context would test the whole tuple.
    local Compat = fresh()
    assertEqual(Compat._firstReturn(function() return "first", "second" end), "first")
end)

test("Compat._firstReturn forwards its arguments to the API", function()
    local Compat = fresh()
    assertEqual(Compat._firstReturn(function(a, b) return a .. b end, "tar", "get"), "target")
end)

test("Compat._firstReturn returns a nil first value even when later ones are set", function()
    local Compat = fresh()
    assertNil(Compat._firstReturn(function() return nil, "texture", 42 end))
end)

-- ── GetSpellCooldown ────────────────────────────────────────────────────────

test("GetSpellCooldown reads the modern C_Spell info table", function()
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCooldown = function()
        return { startTime = 100, duration = 30, isEnabled = true, modRate = 1.5, isActive = true }
    end
    local s, d, e, m, active = Compat.GetSpellCooldown(1)
    assertEqual(s, 100); assertEqual(d, 30); assertEqual(e, true)
    assertEqual(m, 1.5); assertEqual(active, true)
end)

test("GetSpellCooldown returns the inert tuple when the API yields no info", function()
    -- Callers destructure five values unconditionally; a bare nil here would
    -- turn every consumer into a nil-index error.
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCooldown = function() return nil end
    local s, d, e, m, active = Compat.GetSpellCooldown(1)
    assertEqual(s, 0); assertEqual(d, 0); assertEqual(e, false)
    assertEqual(m, 1); assertEqual(active, false)
end)

test("GetSpellCooldown treats a missing isEnabled as enabled, missing isActive as inactive", function()
    -- The two defaults are deliberately asymmetric: `isEnabled ~= false` and
    -- `isActive == true`. Flipping either changes which icons render.
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCooldown = function() return {} end
    local _, _, e, m, active = Compat.GetSpellCooldown(1)
    assertEqual(e, true)
    assertEqual(m, 1)
    assertEqual(active, false)
end)

test("GetSpellCooldown coerces a non-boolean isActive to false", function()
    -- `isActive == true` is a strict identity check on purpose — a truthy
    -- non-boolean must not read as "on cooldown".
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCooldown = function() return { isActive = 1 } end
    local _, _, _, _, active = Compat.GetSpellCooldown(1)
    assertEqual(active, false)
end)

test("GetSpellCooldown passes SECRET timings through without touching them", function()
    -- startTime / duration / modRate are secret-tainted for protected spells.
    -- The shim must hand them on verbatim for a C-side consumer.
    local Compat, mocks = fresh()
    local secretStart, secretDur = landmine("startTime"), landmine("duration")
    mocks.C_Spell.GetSpellCooldown = function()
        return { startTime = secretStart, duration = secretDur, isActive = true }
    end
    local s, d = Compat.GetSpellCooldown(1)
    assertTrue(rawequal(s, secretStart), "startTime must pass through untouched")
    assertTrue(rawequal(d, secretDur), "duration must pass through untouched")
end)

test("GetSpellCooldown falls back to the deprecated global on a pre-12.0 client", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = function() return 5, 12, true, 1 end
    local s, d, e, m, active = Compat.GetSpellCooldown(1)
    assertEqual(s, 5); assertEqual(d, 12); assertEqual(e, true); assertEqual(m, 1)
    assertEqual(active, true, "the legacy path derives isActive from a positive duration")
end)

test("GetSpellCooldown's legacy path reports a zero duration as off cooldown", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = function() return 0, 0, true, 1 end
    local _, _, _, _, active = Compat.GetSpellCooldown(1)
    assertEqual(active, false)
end)

test("GetSpellCooldown's legacy path reads an isEnabled of 0 as DISABLED, nil as enabled", function()
    -- The deprecated global historically answered 1/0. `e ~= false` read 0 as enabled; the
    -- library takes the other copy's reading (LibKa0s docs/api/Compat/version-1-docs.md).
    -- red under: returning `e ~= false` from the legacy rung
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = function() return 5, 12, 0, 1 end
    local _, _, e = Compat.GetSpellCooldown(1)
    assertEqual(e, false)
    mocks.GetSpellCooldown = function() return 5, 12, nil, 1 end
    _, _, e = Compat.GetSpellCooldown(1)
    assertEqual(e, true)
end)

test("GetSpellCooldown's legacy path refuses to compare a secret duration", function()
    -- `d > 0` on a secret errors. The guard must skip the derivation and
    -- report inactive rather than throw.
    local Compat, mocks = fresh()
    local secretDur = landmine("legacy duration")
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = function() return 0, secretDur, true, 1 end
    mocks.issecretvalue = function(v) return rawequal(v, secretDur) end
    local _, d, _, _, active = Compat.GetSpellCooldown(1)
    assertTrue(rawequal(d, secretDur))
    assertEqual(active, false)
end)

test("GetSpellCooldown returns the inert tuple when NO cooldown API exists", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = nil
    local s, d, e, m, active = Compat.GetSpellCooldown(1)
    assertEqual(s, 0); assertEqual(d, 0); assertEqual(e, false)
    assertEqual(m, 1); assertEqual(active, false)
end)

test("GetSpellCooldown answers exactly five values on every branch", function()
    -- Callers destructure five and modules/Cooldowns.lua reads position 5; the count is the
    -- contract whichever rung answered. Pinned before the ladder moved to LibKa0s-Compat-1.0.
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCooldown = function() return { isActive = true } end
    assertEqual(select("#", Compat.GetSpellCooldown(1)), 5, "modern rung")
    mocks.C_Spell.GetSpellCooldown = function() return nil end
    assertEqual(select("#", Compat.GetSpellCooldown(1)), 5, "modern rung, no info")
    mocks.C_Spell = {}
    mocks.GetSpellCooldown = function() return 5, 12, true, 1 end
    assertEqual(select("#", Compat.GetSpellCooldown(1)), 5, "legacy rung")
    mocks.GetSpellCooldown = nil
    assertEqual(select("#", Compat.GetSpellCooldown(1)), 5, "no rung")
end)

-- ── GetSpellCooldownDuration ────────────────────────────────────────────────

test("GetSpellCooldownDuration hands back the opaque handle unchanged", function()
    -- The handle goes straight into Cooldown:SetCooldownFromDurationObject;
    -- wrapping or copying it would break the C-side secret handling.
    local Compat, mocks = fresh()
    local handle = {}
    mocks.C_Spell.GetSpellCooldownDuration = function() return handle end
    assertTrue(rawequal(Compat.GetSpellCooldownDuration(1), handle))
end)

test("GetSpellCooldownDuration is nil on a client without the 12.0 API", function()
    -- There is no pre-12.0 equivalent, so nil is the correct degradation.
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    assertNil(Compat.GetSpellCooldownDuration(1))
end)

-- ── GetSpellTexture / GetSpellInfo ──────────────────────────────────────────

test("GetSpellTexture prefers C_Spell and falls back to the global", function()
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellTexture = function() return 111 end
    assertEqual(Compat.GetSpellTexture(1), 111)

    local Compat2, mocks2 = fresh()
    mocks2.C_Spell = {}
    mocks2.GetSpellTexture = function() return 222 end
    assertEqual(Compat2.GetSpellTexture(1), 222)
end)

test("GetSpellTexture is nil when neither API exists", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellTexture = nil
    assertNil(Compat.GetSpellTexture(1))
end)

test("GetSpellInfo flattens the modern info table into the legacy tuple order", function()
    -- Callers were written against the old positional API; the shim's job is
    -- to keep that contract while the underlying call returns a table.
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellInfo = function()
        return { name = "Kick", iconID = 7, castTime = 0, minRange = 0, maxRange = 5, spellID = 1766 }
    end
    local name, icon, castTime, minR, maxR, id = Compat.GetSpellInfo(1766)
    assertEqual(name, "Kick"); assertEqual(icon, 7); assertEqual(castTime, 0)
    assertEqual(minR, 0); assertEqual(maxR, 5); assertEqual(id, 1766)
end)

test("GetSpellInfo resolves a typed NAME and hands back the spellID at position 6", function()
    -- settings/Spells.lua and core/KickCD.lua resolve a name the player typed through
    -- GetSpellInfo(input) and read the ID off position 6, so a string identifier has to reach the
    -- client and the sixth return has to be the spellID.
    local Compat, mocks = fresh()
    local seen
    mocks.C_Spell.GetSpellInfo = function(id)
        seen = id
        return { name = "Kick", iconID = 7, castTime = 0, minRange = 0, maxRange = 5, spellID = 1766 }
    end
    local id = select(6, Compat.GetSpellInfo("Kick"))
    assertEqual(seen, "Kick", "the typed name must reach the client unchanged")
    assertEqual(id, 1766)
end)

test("GetSpellInfo is nil for an unknown spell, without falling through", function()
    -- Once C_Spell exists it is authoritative: a nil result means "no such
    -- spell", not "try the deprecated API".
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellInfo = function() return nil end
    mocks.GetSpellInfo = function() return "SHOULD NOT BE REACHED" end
    assertNil(Compat.GetSpellInfo(1))
end)

test("GetSpellInfo falls back to the deprecated global's multi-return", function()
    -- The global's REAL shape is name, rank, icon, castTime, ... -- this fixture used to encode
    -- `"Legacy", 9, 1.5`, rank-as-icon, which is the drift LibKa0s-Compat-1.0 resolved. The rank
    -- slot is nil here and the assertions are the ones the old fixture made.
    -- red under: passing the legacy multi-return through without dropping the rank
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellInfo = function() return "Legacy", nil, 9, 1.5 end
    local name, icon, castTime = Compat.GetSpellInfo(1)
    assertEqual(name, "Legacy"); assertEqual(icon, 9); assertEqual(castTime, 1.5)
end)

test("GetSpellInfo's legacy rung drops a real rank rather than reporting it as the icon", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellInfo = function() return "Legacy", "Rank 3", 9, 1.5, 0, 5, 1766 end
    local name, icon, castTime, minR, maxR, id = Compat.GetSpellInfo(1)
    assertEqual(name, "Legacy"); assertEqual(icon, 9); assertEqual(castTime, 1.5)
    assertEqual(minR, 0); assertEqual(maxR, 5); assertEqual(id, 1766)
end)

test("GetSpellTexture answers exactly one value when the client answers two", function()
    -- C_Spell.GetSpellTexture's second return is the original icon. A caller that spreads the
    -- result into the last argument of a C call must never forward it.
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellTexture = function() return 111, 222 end
    assertEqual(select("#", Compat.GetSpellTexture(1)), 1)
    assertEqual(Compat.GetSpellTexture(1), 111)
end)

-- ── The secret seam ─────────────────────────────────────────────────────────

test("IsSecret is LibKa0s-Compat-1.0's member when the payload is present", function()
    local inst = T.load(false)
    local lib = inst.mocks.LibStub("LibKa0s-Compat-1.0", true)
    assertTrue(lib ~= nil, "the live load must register LibKa0s-Compat-1.0")
    assertTrue(rawequal(inst.NS.Compat.IsSecret, lib.IsSecret))
end)

test("IsSecret answers a strict boolean, and false on a client without secrets", function()
    local Compat, mocks = fresh()
    local secret = {}
    mocks.issecretvalue = function(v) if rawequal(v, secret) then return 1 end end
    assertEqual(Compat.IsSecret(secret), true)
    assertEqual(Compat.IsSecret(42), false)
    assertEqual(Compat.IsSecret(nil), false)
    mocks.issecretvalue = nil
    assertEqual(Compat.IsSecret(secret), false)
end)

test("no authored file outside core/Compat.lua reads issecretvalue itself", function()
    -- compat: Compat.IsSecret is the seam. A module that asks the global directly is a read
    -- that bypasses it, which is what the twelve inline calls this replaced were.
    -- red under: restoring `_G.issecretvalue and _G.issecretvalue(cur)` in modules/Cooldowns.lua
    local offenders = {}
    for _, rel in ipairs(T.tocFiles) do
        if not rel:match("^libs[/\\]") and rel ~= "core/Compat.lua" and rel:match("%.lua$") then
            local fh = assert(io.open(T.root .. "/" .. rel, "r"))
            local n = 0
            for line in fh:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                if code:find("issecretvalue", 1, true) then
                    offenders[#offenders + 1] = rel .. ":" .. n
                end
            end
            fh:close()
        end
    end
    assertEqual(#offenders, 0, "issecretvalue read outside the seam: " .. table.concat(offenders, ", "))
end)

-- ── GetSpellCharges ─────────────────────────────────────────────────────────

test("GetSpellCharges flattens the modern charge table", function()
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCharges = function()
        return { currentCharges = 1, maxCharges = 2, cooldownStartTime = 10, cooldownDuration = 15 }
    end
    local cur, max, start, dur = Compat.GetSpellCharges(1)
    assertEqual(cur, 1); assertEqual(max, 2); assertEqual(start, 10); assertEqual(dur, 15)
end)

test("GetSpellCharges is nil for a spell without charges", function()
    local Compat, mocks = fresh()
    mocks.C_Spell.GetSpellCharges = function() return nil end
    assertNil(Compat.GetSpellCharges(1))
end)

test("GetSpellCharges passes a SECRET charge count through untouched", function()
    -- Charge counts are secret-tainted in combat for charged interrupts; the
    -- render path feeds them to SetFormattedText, which accepts secrets.
    local Compat, mocks = fresh()
    local secret = landmine("currentCharges")
    mocks.C_Spell.GetSpellCharges = function()
        return { currentCharges = secret, maxCharges = 2 }
    end
    local cur = Compat.GetSpellCharges(1)
    assertTrue(rawequal(cur, secret))
end)

test("GetSpellCharges falls back to the deprecated global", function()
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.GetSpellCharges = function() return 2, 3, 20, 30 end
    local cur, max = Compat.GetSpellCharges(1)
    assertEqual(cur, 2); assertEqual(max, 3)
end)

-- ── IsSpellAvailable ────────────────────────────────────────────────────────

test("IsSpellAvailable rejects a non-number spell ID outright", function()
    -- The spell editor can hand through a raw string; treating it as a spell
    -- would pass garbage into three client APIs.
    local Compat = fresh()
    assertFalse(Compat.IsSpellAvailable("1766"))
    assertFalse(Compat.IsSpellAvailable(nil))
end)

test("IsSpellAvailable is true when IsPlayerSpell says so", function()
    local Compat, mocks = fresh()
    mocks.IsPlayerSpell = function() return true end
    assertTrue(Compat.IsSpellAvailable(1766))
end)

test("IsSpellAvailable falls back to the spellbook for racials and professions", function()
    -- Some known spells never report true from IsPlayerSpell.
    local Compat, mocks = fresh()
    mocks.IsPlayerSpell = function() return false end
    mocks.IsSpellKnown = function(_, pet) return not pet end
    assertTrue(Compat.IsSpellAvailable(1766))
end)

test("IsSpellAvailable catches PET spells via the IsSpellKnown pet flag", function()
    -- Counter Shot / Spell Lock / Optical Blast only exist while the right
    -- pet is out — that branch is the reason the second call passes `true`.
    local Compat, mocks = fresh()
    mocks.IsPlayerSpell = function() return false end
    mocks.IsSpellKnown = function(_, pet) return pet == true end
    assertTrue(Compat.IsSpellAvailable(147362))
end)

test("IsSpellAvailable is false for an unpicked talent choice-node sibling", function()
    -- The case the function exists for: both siblings are in the spell DB,
    -- only the chosen one is castable, and only one may render.
    local Compat, mocks = fresh()
    mocks.IsPlayerSpell = function() return false end
    mocks.IsSpellKnown = function() return false end
    assertFalse(Compat.IsSpellAvailable(108199))
end)

-- ── IsSpellUsable ───────────────────────────────────────────────────────────

test("IsSpellUsable reads the SpellUsabilityInfo table form", function()
    local Compat, mocks = fresh()
    mocks.C_Spell.IsSpellUsable = function() return { usable = true, noMana = false } end
    local usable, noMana = Compat.IsSpellUsable(1)
    assertEqual(usable, true); assertEqual(noMana, false)
end)

test("IsSpellUsable reads the two-boolean form some Midnight builds return", function()
    -- The shim covers both shapes because the return type varies by build.
    local Compat, mocks = fresh()
    mocks.C_Spell.IsSpellUsable = function() return false, true end
    local usable, noMana = Compat.IsSpellUsable(1)
    assertEqual(usable, false); assertEqual(noMana, true)
end)

test("IsSpellUsable normalizes the legacy API's 1/nil into real booleans", function()
    -- IsUsableSpell returns 1 rather than true; callers branch on `== true`.
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.IsUsableSpell = function() return 1, nil end
    local usable, noMana = Compat.IsSpellUsable(1)
    assertEqual(usable, true); assertEqual(noMana, false)
end)

test("IsSpellUsable defaults to usable when no API is available", function()
    -- Failing open matters: failing closed would blank the whole grid on a
    -- client whose API set we didn't anticipate.
    local Compat, mocks = fresh()
    mocks.C_Spell = {}
    mocks.IsUsableSpell = nil
    local usable, noMana = Compat.IsSpellUsable(1)
    assertEqual(usable, true); assertEqual(noMana, false)
end)

-- ── GetCastingInfo / GetChannelInfo ─────────────────────────────────────────

test("GetCastingInfo builds a record from the CAST API's positions", function()
    -- Positions 1/3/8/9 are name/texture/notInterruptible/spellID.
    local Compat, mocks = fresh()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", "display", "tex", 1, 2, false, "castID", false, 116858
    end
    local rec = Compat.GetCastingInfo("target")
    assertEqual(rec.name, "Chaos Bolt")
    assertEqual(rec.texture, "tex")
    assertEqual(rec.spellID, 116858)
    assertEqual(rec.notInterruptible, false)
    assertEqual(rec.isChannel, false)
end)

test("GetCastingInfo falls through to the channel shim when not casting", function()
    local Compat, mocks = fresh()
    mocks.UnitExists = function() return true end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function()
        return "Mind Flay", "display", "tex", 1, 2, false, false, 15407
    end
    local rec = Compat.GetCastingInfo("target")
    assertEqual(rec.name, "Mind Flay")
    assertEqual(rec.isChannel, true, "the channel record must be flagged as one")
end)

test("GetCastingInfo is nil when the unit is neither casting nor channeling", function()
    local Compat, mocks = fresh()
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
    assertNil(Compat.GetCastingInfo("target"))
end)

test("GetChannelInfo reads notInterruptible from position 7, spellID from 8", function()
    -- UnitChannelInfo has no isTradeSkill slot, so every position after 5
    -- shifts down by one relative to UnitCastingInfo. Reusing the cast
    -- offsets here silently reads the wrong fields.
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return true end
    mocks.UnitChannelInfo = function()
        return "Mind Flay", "display", "tex", 1, 2, "unused6", "FLAG7", "ID8", "unused9"
    end
    local rec = Compat.GetChannelInfo("target")
    assertEqual(rec.notInterruptible, "FLAG7")
    assertEqual(rec.spellID, "ID8")
end)

test("GetChannelInfo is nil when the API itself is missing", function()
    local Compat, mocks = fresh()
    mocks.UnitChannelInfo = nil
    assertNil(Compat.GetChannelInfo("target"))
end)

test("a FRIENDLY unit's cast is forced to uninterruptible regardless of the API", function()
    -- The raw flag answers "can this spell be interrupted at all", not "can I
    -- interrupt it". Mount casts and friendly NPC casts must read as
    -- uninterruptible so the cast bar colors them that way.
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return false end
    mocks.UnitCastingInfo = function()
        return "Summon Steed", "d", "tex", 1, 2, false, "id", false, 1
    end
    assertEqual(Compat.GetCastingInfo("target").notInterruptible, true)
end)

test("a HOSTILE unit's raw notInterruptible flag is returned unchanged", function()
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", "d", "tex", 1, 2, false, "id", false, 1
    end
    assertEqual(Compat.GetCastingInfo("target").notInterruptible, false)
end)

test("the friendly override applies to CHANNELS too, not just casts", function()
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return false end
    mocks.UnitChannelInfo = function()
        return "Tranquility", "d", "tex", 1, 2, false, false, 1
    end
    assertEqual(Compat.GetChannelInfo("target").notInterruptible, true)
end)

test("the cast record carries SECRET name/texture/flag/id without inspecting them", function()
    -- This is the shim's core 12.0 contract: four fields come out of the API
    -- potentially secret-tainted and must land in the record byte-identical,
    -- with no tostring, compare or concat along the way.
    local Compat, mocks = fresh()
    local sName, sTex, sFlag, sID =
        landmine("name"), landmine("texture"), landmine("notInterruptible"), landmine("spellID")
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return sName, "display", sTex, 1, 2, false, "castID", sFlag, sID
    end
    local rec = Compat.GetCastingInfo("target")
    assertTrue(rawequal(rec.name, sName))
    assertTrue(rawequal(rec.texture, sTex))
    assertTrue(rawequal(rec.notInterruptible, sFlag))
    assertTrue(rawequal(rec.spellID, sID))
end)

test("the cast record attaches the plain-number CastingDuration object", function()
    -- Unlike the cooldown handle, the CAST duration's getters stay plain in
    -- combat, which is why the cast bar may read them.
    local Compat, mocks = fresh()
    local duration = { GetTotalDuration = function() return 2.5 end }
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", "d", "tex", 1, 2, false, "id", false, 1
    end
    mocks.UnitCastingDuration = function() return duration end
    assertTrue(rawequal(Compat.GetCastingInfo("target").duration, duration))
end)

test("a channel record sources its duration from UnitChannelDuration", function()
    -- Casts and channels have separate duration APIs; crossing them yields a
    -- bar that fills the wrong way or not at all.
    local Compat, mocks = fresh()
    local chDuration = {}
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return "Mind Flay", "d", "tex", 1, 2, false, false, 1 end
    mocks.UnitCastingDuration = function() return { WRONG = true } end
    mocks.UnitChannelDuration = function() return chDuration end
    assertTrue(rawequal(Compat.GetCastingInfo("target").duration, chDuration))
end)

test("a record survives a client with no duration API at all", function()
    -- The bar degrades to no progress rather than erroring on a nil call.
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", "d", "tex", 1, 2, false, "id", false, 1
    end
    mocks.UnitCastingDuration = nil
    local rec = Compat.GetCastingInfo("target")
    assertTrue(rec ~= nil)
    assertNil(rec.duration)
end)

test("isChannel is a real boolean on both record paths", function()
    -- Consumers branch on it directly, so a nil-vs-false leak would read as
    -- "cast" for a channel on some paths.
    local Compat, mocks = fresh()
    mocks.UnitCanAttack = function() return true end
    mocks.UnitCastingInfo = function()
        return "Chaos Bolt", "d", "tex", 1, 2, false, "id", false, 1
    end
    assertEqual(Compat.GetCastingInfo("target").isChannel, false)
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return "Mind Flay", "d", "tex", 1, 2, false, false, 1 end
    assertEqual(Compat.GetCastingInfo("target").isChannel, true)
end)
