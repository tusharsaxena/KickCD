-- core/Database.lua
--
-- Owns the AceDB-3.0 instance and profile callbacks. The defaults tree
-- itself lives in defaults/Profile.lua, which is the only place a profile
-- default is hardcoded (savedvariables-§2). The `spells` sub-table is left
-- empty there on purpose — defaults/Spells.lua populates
-- KickCD.DefaultSpells at file-load time, and Database:BuildSpells() merges
-- that into the profile only on first creation so user edits are never
-- stomped.

local _, NS = ...

local Database = {}
NS.Database = Database

-- ---------------------------------------------------------------------------
-- Schema version (the defaults tree is defaults/Profile.lua — see
-- docs/schema.md)
-- ---------------------------------------------------------------------------

-- Schema version. Increment whenever a non-additive change is made to
-- DEFAULT_PROFILE's shape (rename, restructure, type change). Additive
-- changes (new leaf settings) are absorbed by AceDB's defaults merge
-- and don't need a version bump. The version is an addon-wide integer
-- stored in db.global.schemaVersion (toc-file-§2 / savedvariables-§1) — NOT per-profile.
-- Database:MigrateProfile reads it on Init and on every profile swap and
-- walks any required migrations forward. v2 folds the legacy top-level
-- icons/castbar/anchors tables into units.target (see migrations[1] /
-- Database:FoldLegacyUnits below). v3 rekeys profile.spells from localized
-- spec NAMES to numeric spec IDs (see migrations[2] /
-- Database:MigrateSpecKeys below). v4 moves every stored color to the keyed
-- { r =, g =, b =, a = } shape (migrations[3] / Database:MigrateColorShape).
-- v5 rewrites the "NONE" font-flag token to the empty string the client's
-- SetFont actually spells it with (migrations[4] / Database:MigrateFontFlags).
local CURRENT_DB_VERSION = 5

-- The one and only Ka0s_KickCD_PROFILE_CHANGED emitter (architecture-§4:
-- one sender per message). Both paths that make the active profile a
-- different thing — an AceDB swap/copy/reset, and a spells re-seed — route
-- here rather than each writing its own SendMessage, so the bus catalog in
-- docs/ARCHITECTURE.md names one site and stays true.
local function fireProfileChanged(key)
    if NS and NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_PROFILE_CHANGED", { newProfileKey = key })
    end
end

-- File-local recursive deep-copy. Deliberately independent of NS.Util —
-- Database.lua is one of the first files to load and must stay
-- self-contained rather than depend on load order.
local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end

--- The AceDB defaults table, assembled at CALL time.
---
--- `profile` is defaults/Profile.lua's tree, and the TOC loads `# Defaults`
--- AFTER `# Core` — so this file cannot capture it in a file-scope local.
--- InitDB runs from NS:OnInitialize, long after every file has loaded, which
--- is where NS.DEFAULT_PROFILE resolves.
local function aceDBDefaults()
    return {
        profile = NS.DEFAULT_PROFILE,
        -- Addon-wide (account) scope. The schema version lives here, not on the
        -- profile, so a migration runs once per account rather than once per
        -- profile (savedvariables-§1). See Database:MigrateProfile for the one-shot adoption
        -- of a legacy per-profile dbVersion.
        global = {
            schemaVersion = CURRENT_DB_VERSION,
        },
    }
end

-- ---------------------------------------------------------------------------
-- Spell-list traversal helpers
-- ---------------------------------------------------------------------------
--
-- Every lookup of one spec's spell list goes through these two helpers, so
-- the `db.profile.spells[CLASS][specID]` walk lives in one place. They only
-- find or create a list. Every write to one is a verb further down this
-- file ("The registry writer"), and docs/ARCHITECTURE.md -> Settings schema
-- names this module as the one writer (architecture-§5).
--
-- The split between read-only and lazy-create matters: getActiveList in
-- the panel fires on every dropdown browse, and lazy-creating an empty
-- per-spec table on every browse pollutes the saved-vars file with
-- 13 classes × 4 specs of empty tables. The read-only helper returns nil
-- for missing entries so consumers can short-circuit without touching
-- the profile shape.
--
-- Callers:
--   * GetSpellList:    Cooldowns:Rebuild, IconGrid:BuildActiveList,
--                      the racial pass and the writer's verbs below,
--                      core/KickCD.lua getSpellList (list, and the
--                      "no list" answers of remove / enable / disable /
--                      category), settings/Spells.lua getActiveList.
--   * EnsureSpellList: Database:BuildSpells (the seed), and the two
--                      verbs that may create a list: AddSpell and
--                      ResetSpellList. Nothing outside this file.

--- Read-only spell-list lookup. Returns the entry array (or nil if no
--- list exists for this class+spec). Never mutates the profile shape,
--- so safe to call from browse paths that flip class/spec dropdowns.
-- @param class string normalized class file token (e.g. "HUNTER")
-- @param spec  number numeric spec ID, the list's storage key (e.g. 253)
-- @return table|nil — the list or nil
function Database:GetSpellList(class, spec)
    if not (class and spec and self.db and self.db.profile) then return nil end
    local spells = self.db.profile.spells
    if type(spells) ~= "table" then return nil end
    local byClass = spells[class]
    if type(byClass) ~= "table" then return nil end
    local list = byClass[spec]
    if type(list) ~= "table" then return nil end
    return list
end

--- Lazy-create spell-list lookup. Creates the per-class and per-spec
--- tables if missing, then returns the list. Use this only on a path
--- that is about to write the list (add, the per-spec reset, the seed),
--- where an empty list IS the right post-condition for an unseeded spec.
--- It creates empty containers and writes no entry itself. Browse-only
--- consumers should use GetSpellList instead.
-- @param class string normalized class file token (e.g. "HUNTER")
-- @param spec  number numeric spec ID, the list's storage key (e.g. 253)
-- @return table|nil — the list, or nil if the profile isn't ready
function Database:EnsureSpellList(class, spec)
    if not (class and spec and self.db and self.db.profile) then return nil end
    local profile = self.db.profile
    profile.spells = profile.spells or {}
    profile.spells[class] = profile.spells[class] or {}
    profile.spells[class][spec] = profile.spells[class][spec] or {}
    return profile.spells[class][spec]
end

-- ---------------------------------------------------------------------------
-- Spells default-merge
-- ---------------------------------------------------------------------------
--
-- AceDB's normal "defaults" mechanism would fold defaults.profile.spells
-- into every new profile, but we want the spells list to be (a) sourced
-- from defaults/Spells.lua which loads after this file, and (b) appended
-- with the player's racial only on first profile creation. So we do the
-- merge ourselves. We detect "first creation" by checking for an empty
-- spells table on the active profile.

local function isEmpty(t)
    if type(t) ~= "table" then return true end
    return next(t) == nil
end

-- THE SEED ROUTINE, shared by the load pass (BuildSpells), the every-list
-- reset (ResetAllSpells, through BuildSpells) and the one-list reset
-- (ResetSpellList). architecture-§5 lets a registry reset call the seed routine
-- the load pass calls; sharing it is also what keeps the three from drifting,
-- which is how the per-spec resets came to drop the racial (#16).
--
-- Rebuild `target` IN PLACE from one defaults list: wiping rather than
-- replacing keeps any reference held downstream valid. The defaults file writes
-- named fields; the `[1]` / `[2]` fallbacks still read the older positional
-- { spellID, category } pairs. The profile keeps named fields so its entries
-- are self-describing in the saved-variable file.
local function seedList(target, source)
    for i = #target, 1, -1 do target[i] = nil end
    for _, entry in ipairs(source or {}) do
        local id  = entry.spellID  or entry[1]
        local cat = entry.category or entry[2]
        if id then
            target[#target + 1] = {
                spellID  = id,
                category = cat or "other",
                enabled  = entry.enabled ~= false,
            }
        end
    end
end

-- The player's racial cast-stopper and class file token, or nil when their
-- race has none.
local function playerRacial()
    local racials = NS.RaceCastStoppers
    if type(racials) ~= "table" then return nil end
    local _, race = UnitRace("player")
    local _, classFile = UnitClass("player")
    local racialID = racials[race]
    if not (racialID and classFile) then return nil end
    return racialID, classFile
end

-- Append the racial to one list unless it is already there (defensive -- some
-- default lists may already include it via PvE bias).
local function appendRacial(list, racialID)
    for _, e in ipairs(list) do
        if e.spellID == racialID then return end
    end
    list[#list + 1] = { spellID = racialID, category = "racial", enabled = true }
end

--- Populate the active profile's spells from KickCD.DefaultSpells, and
--- append the racial cast-stopper for the player's race. Idempotent for
--- already-populated profiles — only runs once per profile.
---
--- "No re-seed if non-empty" is a deliberate policy, not an oversight.
--- A user who has customized any class+spec (even by clearing every row
--- of an active spec) has signaled intent: subsequent logins must NOT
--- silently re-seed their work. The empty check is on the WHOLE
--- `profile.spells` table — if any class entry exists at all, every
--- spec list is left alone, including ones the user hasn't touched.
---
--- Recovery path for users who DO want defaults back:
---   * `/kcd spells resetall`           — wipe all class+spec lists and
---                                        re-seed from defaults +
---                                        racial. Fires through
---                                        Database:ResetAllSpells.
---   * `/kcd spells reset [CLASS SPEC]` — restore a single spec list to
---                                        defaults; leaves every other
---                                        spec untouched.
--- The settings panel's per-spec "Defaults" button (KICKCD_RESET_SPELLS
--- popup) maps to the second form.
function Database:BuildSpells()
    if not (self.db and self.db.profile) then return end

    local profile = self.db.profile
    profile.spells = profile.spells or {}

    -- Only seed if the profile has never been populated. Once the user
    -- has any class entry, we leave their data alone — including for
    -- classes they haven't customized yet, since they may have intentionally
    -- emptied a list.
    if not isEmpty(profile.spells) then
        return
    end

    local source = NS.DefaultSpells
    if type(source) ~= "table" then
        -- defaults/Spells.lua hasn't loaded yet, or failed to load.
        -- Leave spells empty; the spells module will treat that as "track nothing".
        return
    end

    -- EnsureSpellList lazy-creates the per-class / per-spec containers; the
    -- seed routine then fills each one in place.
    for class, specs in pairs(source) do
        for spec, list in pairs(specs) do
            seedList(self:EnsureSpellList(class, spec), list)
        end
    end

    -- Append the racial cast-stopper into every spec list of the player's
    -- own class. Only on first creation — see method docstring.
    local racialID, classFile = playerRacial()
    if racialID and profile.spells[classFile] then
        for spec in pairs(profile.spells[classFile]) do
            local list = self:GetSpellList(classFile, spec)
            if list then appendRacial(list, racialID) end
        end
    end
end

--- Wipe the active profile's spells and re-seed from KickCD.DefaultSpells +
--- racial through BuildSpells, the seed routine the load pass also runs.
--- Backs `/kcd spells resetall` (core/KickCD.lua), so the player gets the
--- current addon defaults across every class and spec, not just the one
--- selected in the Spells editor. The General > "Reset all settings"
--- action no longer calls it: that is a profile reset, and
--- OnProfileChanged re-seeds from there. BuildSpells() is idempotent on
--- populated profiles, so we have to clear first.
function Database:ResetAllSpells()
    if not (self.db and self.db.profile) then return end
    self.db.profile.spells = {}
    self:BuildSpells()
    -- The bulk rewrite, traced once (debug-logging-§8), with the counts in the
    -- one line rather than a line per list (§9). Counted only with the flag on.
    if NS.State and NS.State.debug and NS.Debug then
        local lists, spells = 0, 0
        for _, specs in pairs(self.db.profile.spells) do
            for _, l in pairs(specs) do lists = lists + 1; spells = spells + #l end
        end
        NS.Debug("Spells", "resetall: %d lists, %d spells", lists, spells)
    end
    fireProfileChanged((self.db.keys and self.db.keys.profile) or "Default")
end

-- ---------------------------------------------------------------------------
-- The registry writer (architecture-§5)
-- ---------------------------------------------------------------------------
--
-- Every runtime write to a stored spell list is one of these verbs, alongside
-- ResetAllSpells above. The Spells page (settings/Spells.lua) and the
-- `/kcd spells` handlers (core/KickCD.lua) call them and never append to,
-- splice, remove from or edit an entry of a list themselves;
-- tests/test_spell_registry.lua scans both files for exactly that.
--
-- Each verb writes and returns. Announcing the change stays the caller's, so
-- the page keeps its throttled commit and the slash layer its immediate one.
--
-- The per-entry `enabled` and `category` writes are here too. They are player
-- preferences rather than membership, and they stay bespoke controls with no
-- schema row under an architecture-§5 register row in docs/ARCHITECTURE.md ->
-- Documented deviations (#17); living here is what gives them one writer.

-- ONE gated [Spells] line per write, emitted HERE and nowhere else
-- (debug-logging-§10: a structural registry's create or delete is a functional
-- flow, traced once by the registry writer under §8; a bulk rewrite is a §8 data
-- mutation). Because the trace lives in the writer, the Spells page and
-- `/kcd spells` log the same line for the same act, and neither caller logs it
-- again. The per-entry writes are traced too: they produce no [Set] line, so this
-- is the only place they can show up in the log. Nothing is formatted with the
-- flag off, and a verb that writes nothing logs nothing.
local function trace(fmt, ...)
    if NS.State and NS.State.debug and NS.Debug then NS.Debug("Spells", fmt, ...) end
end

local function where(class, spec)
    local sd = NS.Util and NS.Util.SpecDisplay
    return tostring(class) .. "/" .. (sd and sd(spec) or tostring(spec))
end

local function findEntry(list, spellID)
    if not (list and spellID) then return nil end
    for i, e in ipairs(list) do
        if e.spellID == spellID then return e, i end
    end
end

--- Add a spell to one list, or re-enable it IN PLACE when it is already there:
--- the list is the render order, and a second entry for one spellID would give
--- the icon grid two buttons for one cooldown. Lazy-creates the list.
-- @return "added" | "enabled", or nil when there is nowhere to write
function Database:AddSpell(class, spec, spellID)
    if not spellID then return nil end
    local list = self:EnsureSpellList(class, spec)
    if not list then return nil end
    local existing = findEntry(list, spellID)
    if existing then
        existing.enabled = true
        if NS.State and NS.State.debug then
            trace("add %s to %s: already there, enable in place", tostring(spellID), where(class, spec))
        end
        return "enabled"
    end
    list[#list + 1] = { spellID = spellID, category = "other", enabled = true }
    if NS.State and NS.State.debug then
        trace("add %s to %s: %d spells", tostring(spellID), where(class, spec), #list)
    end
    return "added"
end

--- Remove a spell from one list. Never creates a list.
-- @return true if an entry was removed
function Database:RemoveSpell(class, spec, spellID)
    local list = self:GetSpellList(class, spec)
    local _, index = findEntry(list, spellID)
    if not index then return false end
    table.remove(list, index)
    if NS.State and NS.State.debug then
        trace("remove %s from %s: %d spells", tostring(spellID), where(class, spec), #list)
    end
    return true
end

--- Move the entry at `from` to `to` in one list -- the whole of what a drag
--- writes, and one write. A SPLICE, deliberately not a run of adjacent swaps:
--- a four-position move expressed as swaps is four mutations, and four
--- re-renders pulling the page out from under a gesture still finishing. A
--- stale drop after a rebuild can name an index the list no longer has, so
--- anything out of range writes nothing.
-- @return true if the list changed
function Database:MoveSpell(class, spec, from, to)
    local list = self:GetSpellList(class, spec)
    if not list then return false end
    if type(from) ~= "number" or type(to) ~= "number" then return false end
    local n = #list
    if from < 1 or from > n or to < 1 or to > n or from == to then return false end
    table.insert(list, to, table.remove(list, from))
    if NS.State and NS.State.debug then
        trace("move %d -> %d in %s", from, to, where(class, spec))
    end
    return true
end

--- Set one entry's `enabled` flag. Stores a real boolean: AceGUI hands back nil
--- for an unchecked box on some widget versions, and a nil reads as ENABLED
--- everywhere else in the addon (`entry.enabled ~= false`).
-- @return true if the entry exists
function Database:SetSpellEnabled(class, spec, spellID, enabled)
    local entry = findEntry(self:GetSpellList(class, spec), spellID)
    if not entry then return false end
    entry.enabled = enabled and true or false
    if NS.State and NS.State.debug then
        trace("%s %s in %s", entry.enabled and "enable" or "disable", tostring(spellID), where(class, spec))
    end
    return true
end

--- Set one entry's `category`. The caller validates the value against the
--- closed category set; the category is informational only.
-- @return true if the entry exists
function Database:SetSpellCategory(class, spec, spellID, category)
    local entry = findEntry(self:GetSpellList(class, spec), spellID)
    if not entry then return false end
    entry.category = category
    if NS.State and NS.State.debug then
        trace("category %s = %s in %s", tostring(spellID), tostring(category), where(class, spec))
    end
    return true
end

--- Rebuild ONE (class, spec) list from KickCD.DefaultSpells, in place, through
--- the seed routine the load pass uses -- and, for the player's own class,
--- re-append their racial exactly as BuildSpells and `/kcd spells resetall` do.
--- Backs the Spells page's Defaults popup and `/kcd spells reset`. Lazy-creates
--- the list; a spec with no defaults comes back empty (plus the racial, for the
--- player's own class).
-- @return the list, or nil when the profile is not ready
function Database:ResetSpellList(class, spec)
    local list = self:EnsureSpellList(class, spec)
    if not list then return nil end
    local byClass = NS.DefaultSpells and NS.DefaultSpells[class]
    seedList(list, byClass and byClass[spec])
    local racialID, classFile = playerRacial()
    if racialID and classFile == class then appendRacial(list, racialID) end
    if NS.State and NS.State.debug then
        trace("reset %s: %d spells", where(class, spec), #list)
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Profile migration
-- ---------------------------------------------------------------------------
--
-- Schema changes that aren't pure additions need a migration: the
-- previous shape stays in saved-vars for any user who had the addon
-- installed at the older version, and a new install writes the latest.
-- This is the extension point. Each migration is idempotent and walks
-- profile.dbVersion forward by exactly one step; MigrateProfile loops
-- until the profile reports the current version. Adding a v2 migration
-- means: append a `migrations[1] = function(p) ...; p.dbVersion = 2 end`
-- entry below and bump CURRENT_DB_VERSION at the top of this file. No
-- bootstrap changes required.
--
-- For v1 the migrator is a no-op — every shipped DEFAULT_PROFILE field
-- is treated as v1's shape. The scaffold exists so the next change
-- ships next to its migrator and reviewers don't have to wire one up
-- under deadline pressure.

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
--- one release later. The shape test is deliberately narrow: a table with a
--- numeric [1] AND no .r, of length 3 or 4, whose entries are all numbers in
--- 0..1. That cannot match an anchor table ({ point =, x =, y = }), a spell list
--- (array of tables), or a curve (values outside 0..1 and longer).
--- CRITICAL: by the time this runs, AceDB has ALREADY merged the new keyed
--- defaults into the saved table. `copyDefaults` fills any key the saved table
--- lacks, and a saved positional array lacks r/g/b/a — so a pre-migration color
--- arrives here as a HYBRID: `{ 0.25, 0.5, 0.75, 0.5, r = 1, g = 0.4, ... }`,
--- carrying the user's values in the array part and the DEFAULTS in the keys.
---
--- Detecting "already keyed" by the mere presence of `.r` would therefore skip
--- every row it was written to convert, and every one would silently read back
--- as its default. The array part is the tell: if `[1]` is a number, the user's
--- real color is there and the keys are contamination.
function NS.Database:MigrateColorShape(db)
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

    local converted = 0
    local function walk(t, depth)
        -- Bounded: the profile is a shallow settings tree, and an unbounded
        -- recursion over user data is a hang rather than an error.
        if type(t) ~= "table" or depth > 12 then return end
        for k, v in pairs(t) do
            if looksLikeColor(v) then
                t[k] = { r = v[1], g = v[2], b = v[3], a = v[4] or 1 }
                converted = converted + 1
            elseif type(v) == "table" then
                walk(v, depth + 1)
            end
        end
    end

    walk(db.profile, 0)
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
    -- [from-version] = function(db) ... db.global.schemaVersion = from + 1 end
    -- Each step bumps db.global.schemaVersion to the from-version+1 and may
    -- read/write db.profile as needed.
    [1] = function(db) NS.Database:FoldLegacyUnits(db); db.global.schemaVersion = 2 end,
    [2] = function(db) NS.Database:MigrateSpecKeys(db); db.global.schemaVersion = 3 end,
    [3] = function(db) NS.Database:MigrateColorShape(db); db.global.schemaVersion = 4 end,
    [4] = function(db) NS.Database:MigrateFontFlags(db); db.global.schemaVersion = 5 end,
}

--- Migrate the account forward to CURRENT_DB_VERSION. The schema version is
--- addon-wide (db.global.schemaVersion), so this runs once per account and
--- is idempotent once at the current version. Called on Init and on every
--- profile swap.
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
    -- db.global.schemaVersion to CURRENT_DB_VERSION the moment db.global is first
    -- accessed (copyDefaults rawsets the scalar default), which would mask a
    -- legacy account as already-current and skip its migrations. So key legacy
    -- detection on the presence of the old per-profile field instead. A fresh
    -- install has no dbVersion and is correctly born at CURRENT_DB_VERSION (via
    -- the global default) with nothing to migrate.
    if profile and profile.dbVersion ~= nil then
        g.schemaVersion = profile.dbVersion   -- adopt the legacy version...
        profile.dbVersion = nil               -- ...and drop the orphaned field.
    end
    g.schemaVersion = g.schemaVersion or 1

    while g.schemaVersion < CURRENT_DB_VERSION do
        local step = migrations[g.schemaVersion]
        if not step then
            -- No registered migrator for this jump — bump to avoid an
            -- infinite loop and stop. A real schema change would have
            -- registered the step before bumping CURRENT_DB_VERSION.
            g.schemaVersion = CURRENT_DB_VERSION
            break
        end
        local from = g.schemaVersion
        step(self.db)
        if NS.State and NS.State.debug then
            NS.Debug("Migrate", "v%d -> v%d", from, from + 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Profile callbacks
-- ---------------------------------------------------------------------------

function Database:OnProfileChanged(_, db, newProfileKey)
    -- AceDB hands us (event, db, newProfileKey) for OnProfileChanged/Copied.
    -- For OnProfileReset the third arg is nil; substitute the active key.
    local key = newProfileKey or (db and db.keys and db.keys.profile) or "Default"

    if NS.State and NS.State.debug then
        NS.Debug("Profile", "switched to '%s'", tostring(key))
    end

    -- A reset wipes the profile back to defaults (which leaves spells = {}).
    -- Re-seed spells so the user gets a working list immediately, just like
    -- a fresh profile would. Then run any pending migrations on the
    -- newly-active profile (a copied profile may have been authored at
    -- an older schema version). FoldLegacyUnits runs unconditionally first —
    -- shape-driven, not version-gated (see FoldLegacyUnits docstring) — since
    -- a copied/reset profile can carry legacy top-level tables regardless of
    -- what global.schemaVersion reports.
    self:FoldLegacyUnits(self.db)
    self:BackfillLabelStyle(self.db)
    -- Per-profile, so it has to run on every swap — see MigrateSpecKeys.
    self:MigrateSpecKeys(self.db)
    self:BuildSpells()
    self:MigrateProfile()

    -- Fire the closed internal message — see docs/message-bus.md, through
    -- the file's single fireProfileChanged emitter.
    fireProfileChanged(key)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Build the AceDB instance. Called once from KickCD:OnInitialize().
function Database:Init()
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB then
        if NS.Util then NS.Util.print("AceDB-3.0 missing — bailing") end
        return
    end

    -- Pass `true` as the third argument so AceDB uses the shared
    -- "Default" profile as the default scope on first login (AceDB-3.0
    -- expands `true` → "Default"; omitting the argument falls back to
    -- the per-character profile, which contradicts the docs and was
    -- the source of "every fresh character lands on its own profile"
    -- reports). Every character on the account now starts on the same
    -- "Default" profile; the user can opt into per-character /
    -- per-class / per-realm via the Profiles panel.
    local db = AceDB:New("KickCDDB", aceDBDefaults(), true)
    self.db    = db
    NS.db  = db

    -- Fold any legacy pre-units top-level icons/castbar/anchors into
    -- units.target before anything else touches the profile shape.
    -- Shape-driven and unconditional (not version-gated) — see the
    -- FoldLegacyUnits docstring for why version-gating would miss the
    -- KCD-20 backfill trap.
    self:FoldLegacyUnits(db)

    -- Backfill units.<unit>.label.style on profiles saved before the
    -- single text-label feature. Shape-driven and idempotent like
    -- FoldLegacyUnits — keyed on style == nil to detect legacy profiles.
    self:BackfillLabelStyle(db)

    -- Rekey any localized spec-name spell keys to numeric spec IDs before
    -- anything reads profile.spells. Shape-driven and unconditional for the
    -- same reason as the two above, plus one specific to spells: the schema
    -- version is per-ACCOUNT but spells are per-PROFILE, so version-gating
    -- would migrate only the profile active at upgrade time (issue #8).
    self:MigrateSpecKeys(db)

    -- First-creation seeding. Database:BuildSpells() is a no-op for already
    -- populated profiles, so it's safe on every login. Profile changes
    -- re-trigger it via OnProfileChanged.
    self:BuildSpells()

    -- Walk any required migrations forward. For v1 this is a no-op,
    -- but every Init runs through the same code path so a future v2
    -- ships its migrator in one place.
    self:MigrateProfile()

    -- Wire profile callbacks. AceDB calls these as `obj:method(event, db, key)`
    -- when we register with (self, "OnProfileChanged", "OnProfileChanged").
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
end


