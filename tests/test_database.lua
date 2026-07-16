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
    -- CURRENT_DB_VERSION is 2 (units migration registered) — an unversioned
    -- account is treated as v1 and walked forward through migrations[1].
    assertEqual(ns.db.global.schemaVersion, 2, "migration must stamp v1 then walk to current")
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
    -- CURRENT_DB_VERSION is 2 — the adopted v1 account walks forward through
    -- migrations[1] (FoldLegacyUnits) to the current version.
    assertEqual(ns.db.global.schemaVersion, 2, "adopted version migrates forward to the current version")
    assertEqual(ns.db.profile.dbVersion, nil, "orphaned per-profile field must be cleared")
end)

test("GetSpellList returns nil for an unseeded class/spec", function()
    assertEqual(NS.Database:GetSpellList("NOSUCHCLASS", "NOSUCHSPEC"), nil)
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
    -- Simulate a legacy v1 profile: customised top-level icons/castbar/anchors.
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
    p.units.target.label.style.size = 22   -- user customised
    ns.Database:BackfillLabelStyle(ns.db)
    ns.Database:BackfillLabelStyle(ns.db)
    assertEqual(p.units.target.label.style.size, 22, "existing style not overwritten")
end)

test("BackfillLabelStyle key-fills a missing field onto an existing style, leaving other keys untouched", function()
    local inst = T.load(true)
    local ns = inst.NS
    local p = ns.db.profile
    p.units.target.label.style.size = 22   -- user customised, existing key
    p.units.target.label.style.color = nil -- simulate a profile saved before `color` existed
    ns.Database:BackfillLabelStyle(ns.db)
    assertTrue(type(p.units.target.label.style.color) == "table", "missing color key backfilled")
    assertEqual(p.units.target.label.style.color[1], 1,    "backfilled color matches LABELSTYLE_DEFAULT")
    assertEqual(p.units.target.label.style.color[2], 0.82, "backfilled color matches LABELSTYLE_DEFAULT")
    assertEqual(p.units.target.label.style.size, 22, "existing key untouched by key-fill")

    -- Idempotent + non-destructive: a second pass with a user-edited color stays put.
    p.units.target.label.style.color = { 0, 1, 0, 1 }
    ns.Database:BackfillLabelStyle(ns.db)
    assertEqual(p.units.target.label.style.color[2], 1, "user color value not overwritten")
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
