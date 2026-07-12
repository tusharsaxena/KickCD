-- tests/test_database.lua — defaults shape + migration runner (core/Database.lua)
local T = _G.KICKCD_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("DEFAULT_PROFILE carries the expected top-level shape", function()
    local d = NS.DEFAULT_PROFILE
    assertTrue(d ~= nil, "DEFAULT_PROFILE must be exposed")
    assertEqual(d.enabled, true)
    assertEqual(d.locked, true)
    assertEqual(d.scale, 1.0)
    assertEqual(d.visibility, "target_casting_interruptible")
    assertTrue(type(d.icons) == "table", "icons sub-table must exist")
    assertTrue(type(d.anchors) == "table", "anchors sub-table must exist")
end)

test("OnInitialize built a live db with a merged profile", function()
    assertTrue(NS.db and NS.db.profile, "NS.db.profile must exist after init")
    assertEqual(NS.db.profile.scale, 1.0, "profile must carry merged defaults")
    assertEqual(NS.db.profile.icons.primarySize, 64)
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

test("MigrateProfile treats a missing version as v1 and stamps global", function()
    local inst = T.load(true)
    local ns = inst.NS
    ns.db.global.schemaVersion = nil
    ns.db.profile.dbVersion = nil
    ns.Database:MigrateProfile()
    assertEqual(ns.db.global.schemaVersion, 1, "migration must stamp v1 when unversioned")
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
    assertEqual(ns.db.global.schemaVersion, 1, "adopted version migrates forward to the current version")
    assertEqual(ns.db.profile.dbVersion, nil, "orphaned per-profile field must be cleared")
end)

test("GetSpellList returns nil for an unseeded class/spec", function()
    assertEqual(NS.Database:GetSpellList("NOSUCHCLASS", "NOSUCHSPEC"), nil)
end)
