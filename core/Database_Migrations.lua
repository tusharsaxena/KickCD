-- core/Database_Migrations.lua -- the profile migrations (peeled from core/Database.lua, #29)
--
-- Every shape-driven migrator (FoldLegacyUnits, BackfillLabelStyle,
-- MigrateSpecKeys, MigrateColorShape, MigrateFontFlags), the `migrations` ladder
-- and its runner, Database:MigrateProfile, kept together so the step order reads
-- in one place. A pure move: core/Database.lua had grown to 1121 lines, inside
-- layout-§1's 1000-1500 band.
--
-- The migrators are methods on NS.Database, which core/Database.lua creates; this
-- file defines them on that table at load, so it sits directly after it in the
-- TOC. Database:Init and Database:OnProfileChanged call them at run time. The
-- shared pieces come off NS and the table: NS.SCHEMA_VERSION (the runner's
-- target, published by core/Database.lua) and its deep copy (Database._copy).

local _, NS = ...

local Database           = NS.Database
local SCHEMA_VERSION     = NS.SCHEMA_VERSION
local copy               = Database._copy

-- ---------------------------------------------------------------------------
-- Profile migration
-- ---------------------------------------------------------------------------
--
-- Schema changes that aren't pure additions need a migration: the
-- previous shape stays in saved-vars for any user who had the addon
-- installed at the older version, and a new install writes the latest.
-- This is the extension point. Each step in `migrations` is a PURE,
-- idempotent function of the db and writes no stamp: MigrateProfile owns
-- db.global.schemaVersion and advances it only past a step that returned
-- without raising (savedvariables-§1). Adding a v6 step means: append
-- `migrations[5] = function(db) ... end` below and bump NS.SCHEMA_VERSION
-- at the top of core/Database.lua. No bootstrap changes required.
--
-- A step whose data is per-PROFILE must not rely on the per-ACCOUNT stamp
-- alone: it would convert only the profile active on the day the account
-- crossed that version. Such a step is also shape-driven and runs from
-- Database:Init and every OnProfileChanged (FoldLegacyUnits,
-- BackfillLabelStyle, MigrateSpecKeys, MigrateColorShape, MigrateFontFlags).

-- The legacy top-level tables that fold into units.target. The same two names
-- appear one level down under `p.anchors`, which folds separately because it
-- merges into an existing sub-table rather than moving wholesale.
local LEGACY_TOPLEVEL = { "icons", "castbar" }

-- Merge the legacy top-level `anchors` table INTO units.target.anchors rather
-- than replacing it — a profile can already carry a per-unit anchors table and
-- overwriting it would drop a saved position — then clear the legacy one.
local function foldAnchors(p, t)
    t.anchors = t.anchors or {}
    for _, k in ipairs(LEGACY_TOPLEVEL) do
        if p.anchors[k] ~= nil then t.anchors[k] = p.anchors[k] end
    end
    p.anchors = nil
end

--- Fold a legacy pre-units profile (top-level icons/castbar/anchors) into
--- units.target. Idempotent and SHAPE-DRIVEN, not version-gated: a v1 account
--- that stored schemaVersion as the default never persisted it, so AceDB's
--- defaults merge backfills it to the new CURRENT value and masks the account
--- as already-current (the same KCD-20 backfill trap documented in
--- MigrateProfile). Keying on the presence of the old top-level tables detects
--- exactly the accounts that carry customized legacy data; a fresh v2 install
--- has no top-level icons/castbar/anchors and is a no-op.
function Database:FoldLegacyUnits(db)
    db = db or self.db
    if not (db and db.profile) then return end
    local p = db.profile
    if p.icons == nil and p.castbar == nil and p.anchors == nil then return end
    p.units = p.units or {}
    p.units.target = p.units.target or {}
    local t = p.units.target
    for _, k in ipairs(LEGACY_TOPLEVEL) do
        if p[k] ~= nil then t[k] = p[k]; p[k] = nil end
    end
    if p.anchors ~= nil then foldAnchors(p, t) end
    if t.enabled == nil then t.enabled = true end
end

--- Backfill units.<unit>.label.style on a profile saved before the single
--- text-label feature, AND key-fill any individual style fields added since
--- (e.g. `color`). Idempotent and SHAPE-DRIVEN (keyed on style == nil, or on
--- individual keys missing from an existing style), not version-gated —
--- same rationale as FoldLegacyUnits (AceDB defaults merge would mask the
--- account as already-current). show/text are left exactly as saved; the
--- whole style is filled from LABELSTYLE_DEFAULT when missing, and — for a
--- profile that already has a style table — only keys ABSENT from it are
--- copied in, so a user's customized values are never overwritten. A fresh
--- install already has every key and is a no-op.
function Database:BackfillLabelStyle(db)
    db = db or self.db
    if not (db and db.profile and db.profile.units) then return end
    -- Read at CALL time: defaults/Profile.lua loads after core/ (see aceDBDefaults).
    local LABELSTYLE_DEFAULT = NS.LABELSTYLE_DEFAULT or {}
    for _, unit in ipairs({ "target", "focus" }) do
        local u = db.profile.units[unit]
        if u then
            u.label = u.label or {}
            if u.label.style == nil then
                u.label.style = copy(LABELSTYLE_DEFAULT)
            else
                for k, v in pairs(LABELSTYLE_DEFAULT) do
                    if u.label.style[k] == nil then
                        u.label.style[k] = copy(v)
                    end
                end
            end
        end
    end
end

-- Every line the spec-key migration logs sits behind the same debug guard;
-- one place for it keeps the three outcome arms readable.
local function migrateDebug(fmt, ...)
    if NS.State and NS.State.debug then
        NS.Debug("Migrate", fmt, ...)
    end
end

-- Snapshot the string-typed keys before anything mutates: rekeying a table
-- while pairs() walks it is undefined behavior in Lua.
local function collectStringKeys(bySpec)
    local rekey = {}
    for specKey, list in pairs(bySpec) do
        if type(specKey) == "string" then
            rekey[#rekey + 1] = { key = specKey, list = list }
        end
    end
    return rekey
end

-- Move one collected entry onto its numeric specID. Data safety: a key that
-- can't be resolved is LEFT IN PLACE rather than dropped, and an incoming key
-- never overwrites an existing numeric one.
local function rekeyOne(bySpec, entry, classFile)
    local specID = NS.Util.ResolveSpecID(entry.key, classFile)
    if not specID then
        migrateDebug("spells: %s/%s unresolved, left as-is",
            tostring(classFile), tostring(entry.key))
    elseif bySpec[specID] ~= nil then
        migrateDebug("spells: %s/%s collides with %d, left as-is",
            tostring(classFile), tostring(entry.key), specID)
    else
        bySpec[specID] = entry.list
        bySpec[entry.key] = nil
        migrateDebug("spells: %s/%s -> %d",
            tostring(classFile), tostring(entry.key), specID)
    end
end

--- Rekey `profile.spells[CLASS]` from spec NAME tokens to numeric spec IDs.
---
--- Up to v2 the spec key was the player's localized spec name, uppercased
--- and whitespace-stripped. That silently broke every non-English client:
--- a frFR Elemental Shaman derived "ELEMENTAIRE" and never matched the
--- "ELEMENTAL" key the defaults shipped, so the addon tracked nothing
--- (issue #8). v3 keys on the numeric specID instead, which is invariant.
---
--- Idempotent and SHAPE-DRIVEN (keyed on the key TYPE, not the schema
--- version) for the same reason as FoldLegacyUnits / BackfillLabelStyle:
--- the version is per-ACCOUNT but spells are per-PROFILE, so a
--- version-gated step would migrate only whichever profile happened to be
--- active at upgrade time and leave every other profile broken. Running it
--- unconditionally on each profile swap catches them all as they load.
---
--- Data safety: a key that can't be resolved is LEFT IN PLACE rather than
--- dropped, and an incoming key never overwrites an existing numeric one.
--- Losing a user's customized list is worse than leaving a stale key.
function Database:MigrateSpecKeys(db)
    db = db or self.db
    if not (db and db.profile) then return end
    local spells = db.profile.spells
    if type(spells) ~= "table" then return end

    local Util = NS.Util
    if not (Util and Util.ResolveSpecID) then return end

    for classFile, bySpec in pairs(spells) do
        if type(bySpec) == "table" then
            for _, entry in ipairs(collectStringKeys(bySpec)) do
                rekeyOne(bySpec, entry, classFile)
            end
        end
    end
end

-- The color-shape step's three helpers; the docstring below states the rule.
local function looksLikeColor(v)
    if type(v) ~= "table" then return false end
    local n = #v
    if n < 3 or n > 4 then return false end
    for i = 1, n do
        local c = v[i]
        if type(c) ~= "number" or c < 0 or c > 1 then return false end
    end
    return true
end

local function keyedEquals(v, d)
    return v.r == d.r and v.g == d.g and v.b == d.b and v.a == d.a
end

-- The resolved value for one array-bearing color `v` whose declared default
-- is `d` (nil when the path has none). The rule is MigrateColorShape's, below.
local function reshapeColor(v, d)
    if v.r == nil or type(d) ~= "table" or keyedEquals(v, d) then
        return { r = v[1], g = v[2], b = v[3], a = v[4] or 1 }
    end
    for i = 4, 1, -1 do v[i] = nil end
    return v
end

--- v3 -> v4: colors move from a positional { r, g, b, a } array to the keyed
--- { r =, g =, b =, a = } table.
---
--- The shape is the collection's: LibKa0s-Slash-1.0 parses into it and renders
--- from it, and LibKa0s-Options-1.0's color picker decodes and encodes it. The
--- alternative was translating at every seam, in both libraries, forever.
---
--- Walks the whole profile rather than a hardcoded path list. A path list would
--- have to be kept in step with every color row added to the schema, and a row
--- missed there is a color that silently reads nil on every channel and renders
--- as the fallback — the exact failure this migration exists to prevent, moved
--- one release later. The shape test is deliberately narrow: a table whose array
--- part is 3 or 4 long and holds only numbers in 0..1 (keys beside it are
--- allowed; see the hybrid below). That cannot match an anchor table ({ point =, x =, y = }), a spell list
--- (array of tables), or a curve (values outside 0..1 and longer).
--- CRITICAL: by the time this runs, AceDB has ALREADY merged the new keyed
--- defaults into the saved table. `copyDefaults` fills any key the saved table
--- lacks, and a saved positional array lacks r/g/b/a — so a pre-migration color
--- arrives here as a HYBRID: `{ 0.25, 0.5, 0.75, 0.5, r = 1, g = 0.4, ... }`,
--- carrying the user's values in the array part and the DEFAULTS in the keys.
---
--- Detecting "already keyed" by the mere presence of `.r` would therefore skip
--- every row it was written to convert, and every one would silently read back
--- as its default. The array part is the tell: if `[1]` is a number, an
--- array is there to resolve, and WHICH half is the user's depends on the keys:
---
---   * the keyed part equals the declared default at the same path (compared
---     channel by channel, SameValue on numbers), or there is no declared
---     default there, or no keyed part at all: the keys are AceDB's backfill
---     and the array is the user's color. Convert array -> keys.
---   * the keyed part differs from the default: the keys are a post-upgrade
---     edit (the profile was converted once, then edited, and an array part
---     lingered). Keep the keys and drop [1]..[4]; converting would roll the
---     player's newer choice back to an older one.
---
--- Runs from Database:Init and every OnProfileChanged as well as from the
--- ladder (KICKCD-R-01): the stamp is per-account, colors are per-profile, and
--- a stamp-gated step converted only the profile active at the upgrade. Every
--- rule above is idempotent, so running it on every load costs one walk.
--- docs/schema.md -> "Migration: positional colors to the keyed shape" states
--- the same rule.
function NS.Database:MigrateColorShape(db)
    if not (db and db.profile) then return end

    local converted = 0
    -- `d` is NS.DEFAULT_PROFILE's subtree at the same key as `t`, or nil.
    local function walk(t, d, depth)
        -- Bounded: the profile is a shallow settings tree, and an unbounded
        -- recursion over user data is a hang rather than an error.
        if type(t) ~= "table" or depth > 12 then return end
        for k, v in pairs(t) do
            local dv = type(d) == "table" and d[k] or nil
            if looksLikeColor(v) then
                t[k] = reshapeColor(v, dv)
                converted = converted + 1
            elseif type(v) == "table" then
                walk(v, dv, depth + 1)
            end
        end
    end

    walk(db.profile, NS.DEFAULT_PROFILE, 0)
    if converted > 0 and NS.Debug then
        NS.Debug("Init", "migrated %s color(s) to the keyed shape", converted)
    end
end

--- v4 -> v5: the "NONE" font-flag token becomes the empty string.
---
--- A STORED-VALUE TYPE CHANGE, so it takes the full savedvariables treatment
--- rather than an edit to defaults/Profile.lua: the three font-flag dropdowns
--- now offer LibKa0s' canonical set (options-ui-§16), where "None" is the EMPTY
--- STRING because that is what FontString:SetFont spells "no outline, no
--- monochrome" as. This addon shipped the literal "NONE", which SetFont did not
--- recognize and therefore ignored -- so the rendering is unchanged either way,
--- and what the migration fixes is the DROPDOWN: a stored "NONE" matches no key
--- in the new list, and the control would have opened showing nothing.
---
--- Every unit, both cast-bar text and the icon countdown and the label. Walked
--- by explicit path rather than by shape, unlike MigrateColorShape: a bare
--- "NONE" string is not distinguishable from a legitimate user value anywhere
--- else in the profile, and three known paths per unit is not a list that needs
--- deriving.
function NS.Database:MigrateFontFlags(db)
    local p = db and db.profile
    if not (p and p.units) then return end

    local converted = 0
    local function fix(t, key)
        if type(t) == "table" and t[key] == "NONE" then
            t[key] = ""
            converted = converted + 1
        end
    end

    for _, unit in pairs(p.units) do
        if type(unit) == "table" then
            fix(unit.icons, "cooldownTextFlags")
            fix(unit.castbar, "fontFlags")
            fix(unit.label and unit.label.style, "flags")
        end
    end

    if converted > 0 and NS.Debug then
        NS.Debug("Init", "migrated %s font-flag token(s) off \"NONE\"", converted)
    end
end

local migrations = {
    -- [from-version] = function(db) ... end: a pure step from `from` to
    -- `from + 1`. It writes NO stamp: MigrateProfile advances
    -- db.global.schemaVersion past it only when it returns without raising.
    [1] = function(db) NS.Database:FoldLegacyUnits(db) end,
    [2] = function(db) NS.Database:MigrateSpecKeys(db) end,
    [3] = function(db) NS.Database:MigrateColorShape(db) end,
    [4] = function(db) NS.Database:MigrateFontFlags(db) end,
}

-- A step that raised: one chat line the player sees, plus the gated trace.
local function reportMigrationFailure(from, err)
    local msg = string.format("settings migration v%d -> v%d failed: %s",
        from, from + 1, tostring(err))
    if NS.Util and NS.Util.print then NS.Util.print(msg) end
    migrateDebug("%s", msg)
end

--- Migrate the account forward to NS.SCHEMA_VERSION. The schema version is
--- addon-wide (db.global.schemaVersion), so this runs once per account and
--- is idempotent once at the current version. Called on Init and on every
--- profile swap.
---
--- The runner owns the stamp (savedvariables-§1): a stored 0 (a fresh
--- install, or a stamp AceDB stripped) starts at v1, because every step is
--- idempotent against a default profile; each step runs under pcall, and the
--- stamp advances only past one that returned. A step that raises prints one
--- line, leaves the stamp at the last completed step, and stops the walk, so
--- the next load retries it.
---
--- One-shot legacy adoption: installs that pre-date this change stamped the
--- version per-profile (profile.dbVersion). The first time global.schemaVersion
--- is unset we adopt the active profile's dbVersion (defaulting to v1) so live
--- profiles aren't re-migrated from scratch, then drop the orphaned per-profile
--- field so it doesn't linger in SavedVariables.
function Database:MigrateProfile()
    if not (self.db and self.db.global) then return end
    local g = self.db.global
    local profile = self.db.profile

    -- Legacy accounts (pre-KCD-20) stamped the version PER-PROFILE. We CANNOT
    -- detect them by `g.schemaVersion == nil`: AceDB's defaults merge backfills
    -- db.global.schemaVersion to its declared default the moment db.global is
    -- first accessed (copyDefaults rawsets the scalar default). That default
    -- is 0 now, so a backfill can no longer mask an account as current, but the
    -- old per-profile field is still the only record of how far a legacy
    -- profile got. A fresh install has no dbVersion, reads 0, and walks every
    -- step (each idempotent against a default profile) to NS.SCHEMA_VERSION.
    if profile and profile.dbVersion ~= nil then
        g.schemaVersion = profile.dbVersion   -- adopt the legacy version...
        profile.dbVersion = nil               -- ...and drop the orphaned field.
    end
    local v = g.schemaVersion or 0
    if v < 1 then v = 1 end

    while v < SCHEMA_VERSION do
        local step = migrations[v]
        if not step then
            -- No registered migrator for this jump — bump to avoid an
            -- infinite loop and stop. A real schema change would have
            -- registered the step before bumping NS.SCHEMA_VERSION.
            g.schemaVersion = SCHEMA_VERSION
            break
        end
        local ok, err = pcall(step, self.db)
        if not ok then
            reportMigrationFailure(v, err)
            break
        end
        g.schemaVersion = v + 1
        migrateDebug("v%d -> v%d", v, v + 1)
        v = v + 1
    end
end
