-- tests/test_icongrid_buildlist.lua — IconGrid:BuildActiveList.
--
-- This decides WHICH icons exist at all: it walks the player's saved list for
-- the active class+spec, drops what they can't cast, and produces the ordered
-- set every later stage (layout, glow, cooldown state) operates on. If it is
-- wrong, nothing downstream can be right.
--
-- Three rules are pinned in particular:
--   * availability, not mere existence — an unpicked talent choice-node
--     sibling is in the spell DB but must not render (Blood DK's Gorefiend's
--     Grasp vs Abomination Limb are both default-listed because either could
--     be picked; only the chosen one is castable);
--   * duplicate spellIDs are skipped, because AcquireIcon keys the pool by ID
--     and a second widget for the same ID orphans the first — leaving it
--     visible but permanently frozen, since it stops receiving SPELL_STATE;
--   * a SECRET icon texture is skipped rather than passed to SetTexture,
--     which would error out of the build partway and leave a half-built grid.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

--- A fresh enabled addon plus the target instance, with the player's saved
--- spell list replaced by `entries`. The mock player is a Beast Mastery
--- Hunter, so that is the (class, spec) the build reads.
local function withList(entries)
    local inst     = T.load(true, true)
    local NS       = inst.NS
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = entries
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    return gi, IconGrid, NS, inst.mocks
end

local function entry(spellID, over)
    local e = { spellID = spellID, category = "interrupt", enabled = true }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
end

local function idsOf(gi)
    local out = {}
    for _, btn in ipairs(gi.ordered) do out[#out + 1] = btn.spellID end
    return out
end

-- ── Ordering and basic selection ────────────────────────────────────────────

test("BuildActiveList renders one icon per enabled entry", function()
    local gi = withList({ entry(1766), entry(47528), entry(19647) })
    assertEqual(#gi.ordered, 3)
end)

test("BuildActiveList preserves the saved list's ORDER", function()
    -- Index 1 is the primary interrupt and gets the large slot, so a
    -- reordering here silently demotes the user's chosen kick.
    local gi = withList({ entry(47528), entry(1766), entry(19647) })
    local ids = idsOf(gi)
    assertEqual(ids[1], 47528); assertEqual(ids[2], 1766); assertEqual(ids[3], 19647)
end)

test("the first entry becomes the primary icon the cast bar anchors to", function()
    local gi, IconGrid = withList({ entry(47528), entry(1766) })
    assertTrue(rawequal(IconGrid:GetPrimaryIcon("target"), gi.ordered[1]))
end)

test("BuildActiveList replaces the previous list rather than appending to it", function()
    -- It runs on every spec change, talent change and settings edit; appending
    -- would grow the grid without bound over a session.
    local gi, IconGrid = withList({ entry(1766), entry(47528) })
    IconGrid:BuildActiveList(gi)
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 2)
end)

test("an empty list produces an empty grid, not an error", function()
    local gi = withList({})
    assertEqual(#gi.ordered, 0)
end)

-- ── The enabled flag ────────────────────────────────────────────────────────

test("a disabled entry is skipped", function()
    local gi = withList({ entry(1766), entry(47528, { enabled = false }), entry(19647) })
    local ids = idsOf(gi)
    assertEqual(#ids, 2)
    assertEqual(ids[1], 1766); assertEqual(ids[2], 19647)
end)

test("an entry with no enabled field is treated as enabled", function()
    -- The check is `enabled ~= false`, so a list written by an older build
    -- that omitted the field still renders.
    local gi = withList({ { spellID = 1766, category = "interrupt" } })
    assertEqual(#gi.ordered, 1)
end)

test("an entry with no spellID is skipped rather than acquiring a nil-keyed icon", function()
    local gi = withList({ entry(1766), { category = "interrupt", enabled = true } })
    assertEqual(#gi.ordered, 1)
end)

-- ── Availability filtering ──────────────────────────────────────────────────

test("a spell the player cannot currently cast is not rendered", function()
    -- The choice-node case: both siblings ship in the defaults, only the
    -- picked one may appear.
    local gi, IconGrid, _, mocks = withList({ entry(108199), entry(1263569) })
    mocks.IsPlayerSpell = function(id) return id == 108199 end
    mocks.IsSpellKnown = function() return false end
    IconGrid:BuildActiveList(gi)
    local ids = idsOf(gi)
    assertEqual(#ids, 1)
    assertEqual(ids[1], 108199)
end)

test("a spell missing from the client's spell DB is not rendered", function()
    -- Availability alone isn't enough — a nil name means there is nothing to
    -- draw or tooltip.
    local gi, IconGrid, _, mocks = withList({ entry(1766), entry(999999) })
    mocks.C_Spell.GetSpellInfo = function(id)
        if id == 999999 then return nil end
        return { name = "Spell" .. id, iconID = 1, spellID = id }
    end
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 1)
end)

test("a pet spell appears only while its pet is out", function()
    -- Counter Shot / Spell Lock come and go with the pet; the grid follows.
    local gi, IconGrid, _, mocks = withList({ entry(147362) })
    mocks.IsPlayerSpell = function() return false end
    mocks.IsSpellKnown = function() return false end
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 0)

    mocks.IsSpellKnown = function(_, pet) return pet == true end
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 1)
end)

-- ── Duplicate spellIDs ──────────────────────────────────────────────────────

test("a duplicate spellID is skipped, keeping the pool 1:1 with the ID", function()
    -- A second widget for the same ID overwrites pool.active[id] and orphans
    -- the first, which stays on screen but never updates again.
    local gi = withList({ entry(1766), entry(47528), entry(1766) })
    local ids = idsOf(gi)
    assertEqual(#ids, 2)
    assertEqual(ids[1], 1766); assertEqual(ids[2], 47528)
end)

test("the FIRST occurrence of a duplicated spellID is the one kept", function()
    -- Position matters: index 1 is the primary slot.
    local gi = withList({ entry(1766), entry(1766), entry(47528) })
    assertEqual(idsOf(gi)[1], 1766)
    assertEqual(#gi.ordered, 2)
end)

test("a duplicate that is DISABLED doesn't suppress the enabled original", function()
    -- The dedupe is applied to entries that pass the enabled gate, so a
    -- disabled twin must be irrelevant.
    local gi = withList({ entry(1766), entry(1766, { enabled = false }) })
    assertEqual(#gi.ordered, 1)
end)

test("a duplicate is reported to the debug console when logging is on", function()
    -- Silent skipping would make a hand-edited SavedVariables file look like
    -- the addon simply lost a spell.
    local raw = T.load(true, true)
    local NS = raw.NS
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = { entry(1766), entry(1766) }
    local DebugLog = NS.DebugLog
    DebugLog:SetEnabled(true)
    DebugLog:Clear()
    IconGrid:BuildActiveList(IconGrid:GetInstance("target"))
    assertTrue(DebugLog:FindLine("duplicate spellID 1766") ~= nil,
        "the skipped duplicate must be surfaced in the console")
    DebugLog:SetEnabled(false)
end)

-- ── Secret textures ─────────────────────────────────────────────────────────

test("a SECRET icon texture is skipped instead of erroring the whole build", function()
    -- SetTexture rejects a secret from tainted execution. Blanking one icon is
    -- survivable; aborting mid-list leaves a half-built grid.
    local gi, IconGrid, _, mocks = withList({ entry(1766), entry(47528) })
    local secret = setmetatable({}, {
        __tostring = function() error("tostring() on a secret texture", 0) end,
    })
    mocks.C_Spell.GetSpellTexture = function(id)
        if id == 47528 then return secret end
        return 12345
    end
    mocks.issecretvalue = function(v) return rawequal(v, secret) end
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 2, "every icon must still be built")
    mocks.issecretvalue = function() return false end
end)

test("a plain texture IS applied to the icon widget", function()
    -- The counterpart: the skip must be conditional on secrecy, not blanket.
    local gi, IconGrid, _, mocks = withList({ entry(1766) })
    mocks.C_Spell.GetSpellTexture = function() return "Interface\\Icons\\Kick" end
    IconGrid:BuildActiveList(gi)
    assertEqual(gi.ordered[1].icon:GetTexture(), "Interface\\Icons\\Kick")
end)

-- ── Missing data ────────────────────────────────────────────────────────────

test("a class+spec with no saved list renders nothing and creates no entry", function()
    -- The read is deliberately non-lazy: lazily creating the table here would
    -- write an empty list into SavedVariables for every spec ever inspected.
    local raw = T.load(true, true)
    local NS = raw.NS
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = nil
    local gi = IconGrid:GetInstance("target")
    IconGrid:BuildActiveList(gi)
    assertEqual(#gi.ordered, 0)
    assertTrue(NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] == nil,
        "the read must not lazy-create a spec entry")
end)

test("BuildActiveList caches the unit's resolved icon config on the instance", function()
    -- Later stages (layout, per-slot glow) read inst.cfg rather than
    -- re-resolving the link every time.
    local gi, _, NS = withList({ entry(1766) })
    assertTrue(rawequal(gi.cfg, NS.Units.Icons("target")))
end)

test("each unit builds from its own resolved config", function()
    -- Target and focus can have independent icon settings unless linked.
    local raw = T.load(true, true)
    local NS = raw.NS
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.units.focus.link = false
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = { entry(1766) }
    local t = IconGrid:GetInstance("target")
    local f = IconGrid:GetInstance("focus")
    IconGrid:BuildActiveList(t)
    IconGrid:BuildActiveList(f)
    assertFalse(rawequal(t.cfg, f.cfg), "an unlinked focus resolves its own config")
end)
