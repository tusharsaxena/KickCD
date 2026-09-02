-- tests/test_database.lua — defaults shape + migration runner (core/Database.lua)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("DEFAULT_PROFILE carries the expected top-level shape", function()
    local d = NS.DEFAULT_PROFILE
    assertTrue(d ~= nil, "DEFAULT_PROFILE must be exposed")
    assertEqual(d.enabled, true)
    assertEqual(d.locked, false)
    assertEqual(d.scale, 1.0)
    assertEqual(d.visibility, "target_casting_interruptible")
    assertTrue(type(d.units) == "table", "units sub-table must exist")
    assertTrue(type(d.units.target.icons) == "table", "units.target.icons sub-table must exist")
    assertTrue(type(d.units.target.anchors) == "table", "units.target.anchors sub-table must exist")
end)

test("OnInitialize built a live db with a merged profile", function()
    assertTrue(NS.db and NS.db.profile, "NS.db.profile must exist after init")
    assertEqual(NS.db.profile.scale, 1.0, "profile must carry merged defaults")
    assertEqual(NS.db.profile.units.target.icons.primarySize, 64)
end)

test("Schema version lives in db.global, not the profile (KCD-20)", function()
    assertTrue(NS.db.global ~= nil, "db.global must exist")
    assertTrue(NS.db.global.schemaVersion ~= nil, "global.schemaVersion must be set")
    assertEqual(NS.db.profile.dbVersion, nil, "profile must NOT carry a schema version")
end)

test("MigrateProfile is a no-op at the current schema version", function()
    local before = NS.db.global.schemaVersion
    NS.Database:MigrateProfile()
    assertEqual(NS.db.global.schemaVersion, before, "migration must not change an already-current account")
end)

test("MigrateProfile treats a missing version as v1 and walks forward to current", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.db.global.schemaVersion = nil
    ns.db.profile.dbVersion = nil
    ns.Database:MigrateProfile()
    -- CURRENT_DB_VERSION is 5 (units fold, spec-key rekey, color reshape, font-flag
    -- token) — an unversioned account is treated as v1 and walked forward through
    -- every step.
    assertEqual(ns.db.global.schemaVersion, 5, "migration must stamp v1 then walk to current")
end)

test("MigrateProfile adopts a legacy per-profile dbVersion even past AceDB backfill (KCD-20)", function()
    local inst = T.load(true)
    local ns = inst.NS
    -- Regression guard: AceDB's defaults merge backfills db.global.schemaVersion
    -- to the CURRENT value on first access, so a legacy account arrives here with
    -- global.schemaVersion ALREADY set (not nil). Simulate that with a bogus high
    -- value alongside a legacy per-profile dbVersion. The per-profile version MUST
    -- win over the backfilled global value (otherwise legacy migrations are skipped).
    ns.db.global.schemaVersion = 99
    ns.db.profile.dbVersion = 1
    ns.Database:MigrateProfile()
    assertTrue(ns.db.global.schemaVersion ~= 99, "legacy dbVersion must override the backfilled global value")
    -- CURRENT_DB_VERSION is 5 — the adopted v1 account walks forward through
    -- migrations[1] (FoldLegacyUnits), [2] (MigrateSpecKeys), [3]
    -- (MigrateColorShape) and [4] (MigrateFontFlags) to the current version.
    assertEqual(ns.db.global.schemaVersion, 5, "adopted version migrates forward to the current version")
    assertEqual(ns.db.profile.dbVersion, nil, "orphaned per-profile field must be cleared")
end)

test("GetSpellList returns nil for an unseeded class/spec", function()
    assertEqual(NS.Database:GetSpellList("NOSUCHCLASS", -1), nil)
end)

-- ---------------------------------------------------------------------------
-- MigrateSpecKeys — v2 string spec keys -> numeric spec IDs (issue #8)
-- ---------------------------------------------------------------------------

test("MigrateSpecKeys rewrites an English spec-name key to its numeric spec ID", function()
    local ns = T.load(true).NS
    ns.db.profile.spells = { SHAMAN = { ELEMENTAL = { { spellID = 51490, enabled = true } } } }
    ns.Database:MigrateSpecKeys(ns.db)
    assertEqual(ns.db.profile.spells.SHAMAN.ELEMENTAL, nil, "the string key must be gone")
    local list = ns.db.profile.spells.SHAMAN[262]
    assertTrue(type(list) == "table", "the list must live under specID 262")
    assertEqual(list[1].spellID, 51490, "entries must survive the rekey untouched")
end)

test("MigrateSpecKeys rewrites a LOCALIZED spec-name key to its numeric spec ID (issue #8)", function()
    -- The French reporter's own saved data: /kcd spells add wrote under the
    -- localized token, so the migration has to recognize it too.
    local inst = T.load(true, false, function(mocks)
        mocks.__setPlayerSpec(7, 1, { [262] = "Élémentaire" })
        mocks.GetLocale = function() return "frFR" end
    end)
    local ns = inst.NS
    ns.db.profile.spells = { SHAMAN = { ["ÉLÉMENTAIRE"] = { { spellID = 51490, enabled = true } } } }
    ns.Database:MigrateSpecKeys(ns.db)
    assertEqual(ns.db.profile.spells.SHAMAN["ÉLÉMENTAIRE"], nil, "the localized key must be gone")
    assertTrue(type(ns.db.profile.spells.SHAMAN[262]) == "table",
        "a localized key must map to the same specID as the English one")
end)

test("MigrateSpecKeys is idempotent on an already-numeric profile", function()
    local ns = T.load(true).NS
    ns.db.profile.spells = { SHAMAN = { [262] = { { spellID = 51490, enabled = true } } } }
    ns.Database:MigrateSpecKeys(ns.db)
    ns.Database:MigrateSpecKeys(ns.db)
    assertEqual(#ns.db.profile.spells.SHAMAN[262], 1, "a second pass must not duplicate or drop entries")
end)

test("MigrateSpecKeys leaves an unmappable key in place rather than dropping data", function()
    local ns = T.load(true).NS
    ns.db.profile.spells = { SHAMAN = { GIBBERISH = { { spellID = 51490 } } } }
    ns.Database:MigrateSpecKeys(ns.db)
    assertTrue(type(ns.db.profile.spells.SHAMAN.GIBBERISH) == "table",
        "an unrecognized key must be preserved, not silently deleted")
end)

test("MigrateSpecKeys does not clobber an existing numeric key on collision", function()
    local ns = T.load(true).NS
    ns.db.profile.spells = {
        SHAMAN = {
            [262]      = { { spellID = 111 } },
            ELEMENTAL  = { { spellID = 222 } },
        },
    }
    ns.Database:MigrateSpecKeys(ns.db)
    assertEqual(ns.db.profile.spells.SHAMAN[262][1].spellID, 111,
        "the already-migrated numeric list must win")
end)

test("DEFAULT_PROFILE nests appearance under units.target / units.focus", function()
    local d = NS.DEFAULT_PROFILE
    assertEqual(d.icons, nil, "top-level icons must be removed from defaults")
    assertEqual(d.castbar, nil, "top-level castbar must be removed from defaults")
    assertEqual(d.anchors, nil, "top-level anchors must be removed from defaults")
    assertTrue(type(d.units) == "table", "units sub-table must exist")
    assertTrue(type(d.units.target.icons) == "table", "units.target.icons must exist")
    assertEqual(d.units.target.icons.primarySize, 64)
    assertEqual(d.units.target.enabled, true)
    assertEqual(d.units.focus.enabled, true, "focus defaults on")
    assertEqual(d.units.focus.link, true, "focus defaults linked to target")
    assertTrue(type(d.units.target.anchors.icons) == "table")
end)

test("FoldLegacyUnits moves a legacy top-level config under units.target", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    -- Simulate a legacy v1 profile: customized top-level icons/castbar/anchors.
    p.icons   = { primarySize = 48, borderColor = { 1, 0, 0, 1 } }
    p.castbar = { width = 300 }
    p.anchors = { icons = { point = "TOP", relativePoint = "TOP", x = 5, y = -5 },
                  castbar = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 10 } }
    ns.db.profile.units = nil
    ns.Database:FoldLegacyUnits(ns.db)
    assertEqual(p.icons, nil, "top-level icons cleared after fold")
    assertEqual(p.castbar, nil, "top-level castbar cleared after fold")
    assertEqual(p.anchors, nil, "top-level anchors cleared after fold")
    assertEqual(p.units.target.icons.primarySize, 48, "user icons preserved under units.target")
    assertEqual(p.units.target.castbar.width, 300, "user castbar preserved")
    assertEqual(p.units.target.anchors.icons.x, 5, "user grid anchor preserved")
    assertEqual(p.units.target.anchors.castbar.y, 10, "user castbar anchor preserved")
end)

test("FoldLegacyUnits is idempotent and leaves a fresh v2 profile untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    local sizeBefore = p.units.target.icons.primarySize
    ns.Database:FoldLegacyUnits(ns.db)   -- no top-level keys → no-op
    ns.Database:FoldLegacyUnits(ns.db)   -- run twice
    assertEqual(p.icons, nil)
    assertEqual(p.units.target.icons.primarySize, sizeBefore, "fresh profile unchanged")
end)

test("DEFAULT_PROFILE ships an identical label.style for target and focus", function()
    local d = NS.DEFAULT_PROFILE
    assertTrue(type(d.units.target.label.style) == "table", "target label.style must exist")
    assertTrue(type(d.units.focus.label.style)  == "table", "focus label.style must exist")
    assertEqual(d.units.target.label.style.attach,   "icons")
    assertEqual(d.units.target.label.style.relPoint, "TOP")
    -- style ships identical (only text differs). Table-valued fields (e.g.
    -- color) are deep-copied per unit, so compare element-wise rather than
    -- by identity.
    for k, v in pairs(d.units.target.label.style) do
        local fv = d.units.focus.label.style[k]
        if type(v) == "table" then
            for i, x in ipairs(v) do
                assertEqual(fv[i], x, "focus style differs at key " .. tostring(k) .. "[" .. i .. "]")
            end
        else
            assertEqual(fv, v, "focus style differs at key " .. tostring(k))
        end
    end
    assertEqual(d.units.target.label.text, "Target")
    assertEqual(d.units.focus.label.text,  "Focus")
end)

test("BackfillLabelStyle adds a missing label.style and preserves show/text", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label = { show = true, text = "TANK" }   -- legacy: no style
    p.units.focus.label  = { show = false, text = "Focus" }
    p.units.focus.label.style = nil
    ns.Database:BackfillLabelStyle(ns.db)
    assertTrue(type(p.units.target.label.style) == "table", "style backfilled")
    assertEqual(p.units.target.label.show, true,  "show preserved")
    assertEqual(p.units.target.label.text, "TANK", "text preserved")
    assertEqual(p.units.target.label.style.attach, "icons", "style is the default")
end)

test("BackfillLabelStyle is idempotent and leaves an existing style untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label.style.size = 22   -- user customized
    ns.Database:BackfillLabelStyle(ns.db)
    ns.Database:BackfillLabelStyle(ns.db)
    assertEqual(p.units.target.label.style.size, 22, "existing style not overwritten")
end)

test("BackfillLabelStyle key-fills a missing field onto an existing style, leaving other keys untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label.style.size = 22   -- user customized, existing key
    p.units.target.label.style.color = nil -- simulate a profile saved before `color` existed
    ns.Database:BackfillLabelStyle(ns.db)
    assertTrue(type(p.units.target.label.style.color) == "table", "missing color key backfilled")
    assertEqual(p.units.target.label.style.color.r, 1,    "backfilled color matches LABELSTYLE_DEFAULT")
    assertEqual(p.units.target.label.style.color.g, 0.82, "backfilled color matches LABELSTYLE_DEFAULT")
    assertEqual(p.units.target.label.style.size, 22, "existing key untouched by key-fill")

    -- Idempotent + non-destructive: a second pass with a user-edited color stays put.
    p.units.target.label.style.color = { r = 0, g = 1, b = 0, a = 1 }
    ns.Database:BackfillLabelStyle(ns.db)
    assertEqual(p.units.target.label.style.color.g, 1, "user color value not overwritten")
end)

test("DB label.style.color default matches the settings schema color row default (DB<->schema sync)", function()
    local schemaColor
    for _, row in ipairs(NS.Settings.Schema) do
        if row.path == "units.target.label.style.color" then schemaColor = row.default end
    end
    assertTrue(type(schemaColor) == "table", "schema color row found")
    local dbColor = NS.DEFAULT_PROFILE.units.target.label.style.color
    for i = 1, 4 do
        assertEqual(dbColor[i], schemaColor[i], "DB/schema color mismatch at index " .. i)
    end
    -- Single-sourced: both units ship the identical color.
    local focusColor = NS.DEFAULT_PROFILE.units.focus.label.style.color
    for i = 1, 4 do
        assertEqual(dbColor[i], focusColor[i], "target/focus color mismatch at index " .. i)
    end
end)

-- ── v4 -> v5: the font-flag token ───────────────────────────────────────────
--
-- The three font-flag dropdowns now offer LibKa0s' canonical set
-- (options-ui-§16), where "None" is the EMPTY STRING because that is what
-- FontString:SetFont spells it as. This addon shipped the literal "NONE", which
-- SetFont did not recognise and therefore ignored — so the RENDERING is
-- identical either way and what the migration saves is the control: a stored
-- "NONE" matches no key in the new list, and the dropdown would have come up
-- showing nothing.

test("a stored NONE font flag reads back as the empty string after migration", function()
    -- red under: deleting migrations[4], or narrowing MigrateFontFlags to one
    -- of the three paths
    local inst = T.load(true)
    local ns = inst.NS
    for _, unit in ipairs({ "target", "focus" }) do
        local u = ns.db.profile.units[unit]
        u.icons.cooldownTextFlags = "NONE"
        u.castbar.fontFlags       = "NONE"
        u.label.style.flags       = "NONE"
    end
    ns.db.global.schemaVersion = 4
    ns.Database:MigrateProfile()

    assertEqual(ns.db.global.schemaVersion, 5)
    for _, unit in ipairs({ "target", "focus" }) do
        local u = ns.db.profile.units[unit]
        assertEqual(u.icons.cooldownTextFlags, "", unit .. " icons")
        assertEqual(u.castbar.fontFlags, "", unit .. " castbar")
        assertEqual(u.label.style.flags, "", unit .. " label")
    end
end)

test("the font-flag migration leaves every other token exactly as it found it", function()
    -- It rewrites ONE value, not "anything that looks like a flag": OUTLINE and
    -- the new combination token must survive it untouched.
    local inst = T.load(true)
    local ns = inst.NS
    local u = ns.db.profile.units.target
    u.icons.cooldownTextFlags = "THICKOUTLINE"
    u.castbar.fontFlags       = "OUTLINE, MONOCHROME"
    u.label.style.flags       = ""
    ns.Database:MigrateFontFlags(ns.db)
    assertEqual(u.icons.cooldownTextFlags, "THICKOUTLINE")
    assertEqual(u.castbar.fontFlags, "OUTLINE, MONOCHROME")
    assertEqual(u.label.style.flags, "")
end)

test("the font-flag migration is idempotent and survives a half-built profile", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.db.profile.units.target.icons.cooldownTextFlags = "NONE"
    ns.db.profile.units.focus.label = nil          -- a profile mid-backfill
    ns.Database:MigrateFontFlags(ns.db)
    ns.Database:MigrateFontFlags(ns.db)
    assertEqual(ns.db.profile.units.target.icons.cooldownTextFlags, "")
end)
