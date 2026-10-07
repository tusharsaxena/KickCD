-- core/Database.lua
--
-- Owns the AceDB-3.0 instance and profile callbacks; the migrations are
-- core/Database_Migrations.lua's (#29). The defaults tree
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
-- Database:FoldLegacyUnits in core/Database_Migrations.lua). v3 rekeys profile.spells from localized
-- spec NAMES to numeric spec IDs (see migrations[2] /
-- Database:MigrateSpecKeys). v4 moves every stored color to the keyed
-- { r =, g =, b =, a = } shape (migrations[3] / Database:MigrateColorShape).
-- v5 rewrites the "NONE" font-flag token to the empty string the client's
-- SetFont actually spells it with (migrations[4] / Database:MigrateFontFlags).
-- The migration runner's target, under the name savedvariables-§1 gives it.
-- core/Database_Migrations.lua walks the stamp up to it, and `/kcd
-- diagnostics` prints it beside the stored db.global.schemaVersion.
NS.SCHEMA_VERSION = 5

-- The one and only Ka0s_KickCD_ProfileChanged emitter (architecture-§4:
-- one sender per message). Both paths that make the active profile a
-- different thing — an AceDB swap/copy/reset, and a spells re-seed — route
-- here rather than each writing its own SendMessage, so the bus catalog in
-- docs/ARCHITECTURE.md names one site and stays true.
local function fireProfileChanged(key)
    if NS and NS.SendMessage then
        NS:SendMessage(NS.MSG.PROFILE_CHANGED, { newProfileKey = key })
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
-- core/Database_Migrations.lua (#29) takes the same copy off the table at load,
-- rather than a second definition that could drift from this one.
Database._copy = copy

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
        -- profile (savedvariables-§1). See Database:MigrateProfile for the
        -- one-shot adoption of a legacy per-profile dbVersion.
        --
        -- The default is 0, NEVER NS.SCHEMA_VERSION (savedvariables-§1 at
        -- v2.65.0). AceDB's removeDefaults strips a stored value equal to its
        -- default at logout, so a current-version default never persists; and
        -- AceDB backfills a declared default onto a legacy account that has no
        -- stamp, which a current-version default would mask as already
        -- current. A 0 has neither problem: the runner owns the stamp, and a
        -- fresh (or stripped-stamp) account walks every step, each idempotent
        -- against a default profile.
        global = {
            schemaVersion = 0,
            -- LibDBIcon-1.0's OWN table, and the declared default is what
            -- materializes it (architecture-§5) -- nothing seeds or backfills it
            -- by hand, here or anywhere, because it is a path a schema row
            -- addresses. `hide` is the row's; `minimapPos` is the library's,
            -- written when the player drags the button, and needs no row.
            --
            -- GLOBAL rather than profile, and that is launcher-§3's decision
            -- rather than an accident of where the other rows live: a minimap
            -- button belongs to the INSTALLATION, so a profile switch must not
            -- move a player's buttons and options-ui-§12's `Reset all settings`
            -- -- a profile reset by definition -- must not un-hide one they
            -- deliberately hid.
            --
            -- NO MIGRATION and no schemaVersion bump: this addon has never
            -- stored a minimap table, so there is no stored path moving. (The
            -- collection's one profile -> global move is Multi Meters'.)
            minimap = { hide = false },
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
    -- one line rather than a line per list (debug-logging-§9). Counted only with the flag on.
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
-- The customized-list count (read-only, for `/kcd diagnostics`)
-- ---------------------------------------------------------------------------
--
-- How many class+spec lists differ from what a reset would give them. The
-- comparison list is built by the SAME seed routine and racial rule the resets
-- use, into a scratch table, so "customized" means exactly "a per-spec Defaults
-- would change this". Nothing here writes the profile or creates a list.

local function sameEntries(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if x.spellID ~= y.spellID or x.category ~= y.category
            or (x.enabled ~= false) ~= (y.enabled ~= false) then
            return false
        end
    end
    return true
end

--- The list a reset would give (class, spec), built into a scratch table.
local function defaultListFor(class, spec, racialID, racialClass)
    local list = {}
    local byClass = NS.DefaultSpells and NS.DefaultSpells[class]
    seedList(list, byClass and byClass[spec])
    if racialID and racialClass == class then appendRacial(list, racialID) end
    return list
end

--- Every (class, spec) pair the profile or the defaults name, once each.
local function everyPair(stored)
    local seen, out = {}, {}
    for _, source in ipairs({ stored, NS.DefaultSpells or {} }) do
        for class, specs in pairs(source) do
            for spec in pairs(type(specs) == "table" and specs or {}) do
                local key = tostring(class) .. "/" .. tostring(spec)
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { class, spec }
                end
            end
        end
    end
    return out
end

--- @return number customized, number stored  lists that differ from their
---         defaults, and lists the profile holds
function Database:CountCustomizedSpellLists()
    local stored = self.db and self.db.profile and self.db.profile.spells
    if type(stored) ~= "table" then return 0, 0 end
    local racialID, racialClass = playerRacial()
    local customized, total = 0, 0
    for _, pair in ipairs(everyPair(stored)) do
        local list = self:GetSpellList(pair[1], pair[2])
        if list then total = total + 1 end
        if not sameEntries(list or {}, defaultListFor(pair[1], pair[2], racialID, racialClass)) then
            customized = customized + 1
        end
    end
    return customized, total
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
-- flow, traced once by the registry writer under debug-logging-§8; a bulk rewrite is a debug-logging-§8 data
-- mutation). Because the trace lives in the writer, the Spells page and
-- `/kcd spells` log the same line for the same act, and neither caller logs it
-- again. The per-entry writes are traced too: they produce no [Set] line, so this
-- is the only place they can show up in the log. Nothing is formatted with the
-- flag off. A write a guard REFUSED logs one line naming that guard
-- (debug-logging-§8, refusals: the report is "nothing happened", and the guard
-- is the answer), here for the same reason: the page and the slash verb share it.
local function trace(fmt, ...)
    if NS.State and NS.State.debug and NS.Debug then NS.Debug("Spells", fmt, ...) end
end

local function where(class, spec)
    local sd = NS.Util and NS.Util.SpecDisplay
    return tostring(class) .. "/" .. (sd and sd(spec) or tostring(spec))
end

-- The refusal line. `a` is the spellID, or with `b` the from/to pair of a move;
-- everything is formatted behind the gate.
local function refused(act, class, spec, guard, a, b)
    if not (NS.State and NS.State.debug) then return end
    local subject = b ~= nil and (tostring(a) .. " -> " .. tostring(b)) or tostring(a)
    trace("%s %s in %s refused: %s", act, subject, where(class, spec), guard)
end

local NO_LIST = "no spell list for that class/spec"

local function findEntry(list, spellID)
    if not (list and spellID) then return nil end
    for i, e in ipairs(list) do
        if e.spellID == spellID then return e, i end
    end
end

--- Is `class` a class file token this addon can key a list by? A key of the
--- shipped defaults, or a token the client's own class list reports. Anything
--- else ("WARLORD", a typo) would lazy-create an orphan list in SavedVariables
--- that no character ever reads (KICKCD-R-18).
-- @param class string|nil
-- @return boolean
function Database.IsKnownClass(class)
    if type(class) ~= "string" or class == "" then return false end
    if NS.DefaultSpells and NS.DefaultSpells[class] then return true end
    if not (_G.GetNumClasses and _G.GetClassInfo) then return false end
    for classID = 1, _G.GetNumClasses() do
        local _, classFile = _G.GetClassInfo(classID)
        if classFile == class then return true end
    end
    return false
end

--- Add a spell to one list, or re-enable it IN PLACE when it is already there:
--- the list is the render order, and a second entry for one spellID would give
--- the icon grid two buttons for one cooldown. Lazy-creates the list -- but only
--- for a class Database.IsKnownClass accepts.
-- @return "added" | "enabled"; or nil when there is nowhere to write, plus
--   "unknown class" when the class token is the reason
function Database:AddSpell(class, spec, spellID)
    if not spellID then
        refused("add", class, spec, "no spellID", spellID)
        return nil
    end
    if class ~= nil and not Database.IsKnownClass(class) then
        refused("add", class, spec, "unknown class", spellID)
        return nil, "unknown class"
    end
    local list = self:EnsureSpellList(class, spec)
    if not list then
        refused("add", class, spec, "no class/spec, or the profile is not ready", spellID)
        return nil
    end
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
    if not index then
        refused("remove", class, spec, list and "not in the list" or NO_LIST, spellID)
        return false
    end
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
    if not list then
        refused("move", class, spec, NO_LIST, from, to)
        return false
    end
    if type(from) ~= "number" or type(to) ~= "number" then
        refused("move", class, spec, "an index is not a number", from, to)
        return false
    end
    local n = #list
    if from < 1 or from > n or to < 1 or to > n then
        if NS.State and NS.State.debug then
            refused("move", class, spec, "index out of range (the list has " .. n .. ")", from, to)
        end
        return false
    end
    if from == to then
        refused("move", class, spec, "same position", from, to)
        return false
    end
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
    local list = self:GetSpellList(class, spec)
    local entry = findEntry(list, spellID)
    if not entry then
        refused(enabled and "enable" or "disable", class, spec, list and "not in the list" or NO_LIST, spellID)
        return false
    end
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
    local list = self:GetSpellList(class, spec)
    local entry = findEntry(list, spellID)
    if not entry then
        refused("category", class, spec, list and "not in the list" or NO_LIST, spellID)
        return false
    end
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
    if not list then
        if NS.State and NS.State.debug then
            trace("reset %s refused: no class/spec, or the profile is not ready", where(class, spec))
        end
        return nil
    end
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
-- Profile migration: core/Database_Migrations.lua (#29)
-- ---------------------------------------------------------------------------
-- The shape-driven migrators (FoldLegacyUnits, BackfillLabelStyle,
-- MigrateSpecKeys, MigrateColorShape, MigrateFontFlags), the `migrations`
-- ladder and its runner, Database:MigrateProfile. Init and OnProfileChanged
-- below call them as methods at run time.

-- ---------------------------------------------------------------------------
-- Profile callbacks
-- ---------------------------------------------------------------------------

-- The rows a profile reset changed, counted before it ran by the Reset all path
-- that drove it (settings/OptionsSetup.lua, through the schema seam's
-- Store.ResetCounted), and taken once. nil for a reset driven straight at the db
-- -- AceDBOptions' Reset Profile, a `/run` -- which nothing counted: the line
-- then carries no count rather than a wrong one (debug-logging-§10). Never the
-- schema's size: that is every row the profile stores, not the rows the reset
-- changed. Taking it also tells an open bulk bracket that this act reset the
-- profile, so the handler's line is the act's only one.
local function consumeResetCount()
    local S = NS.Settings and NS.Settings.Store
    return S and S.ConsumeResetCount() or nil
end

-- The one line a profile event logs, worded by the event (debug-logging-§10). A
-- reset and a copy replace the profile's rows wholesale, so each is one [Set]
-- line and no bulk bracket adds a second; a switch rewrites no row and keeps
-- the [Profile] trace it always had.
local function traceProfileEvent(event, key, source)
    -- Taken whatever the debug state, so a count never outlives its reset.
    local count = event == "OnProfileReset" and consumeResetCount() or nil
    if not (NS.State and NS.State.debug) then return end
    if event == "OnProfileReset" and count then
        NS.Debug("Set", "reset profile '%s' to defaults (%d rows)", tostring(key), count)
    elseif event == "OnProfileReset" then
        NS.Debug("Set", "reset profile '%s' to defaults", tostring(key))
    elseif event == "OnProfileCopied" then
        NS.Debug("Set", "copied profile '%s' → '%s'", tostring(source), tostring(key))
    else
        NS.Debug("Profile", "switched to '%s'", tostring(key))
    end
end

function Database:OnProfileChanged(event, db, arg)
    -- AceDB hands (event, db, newProfileKey) for OnProfileChanged,
    -- (event, db, sourceProfileKey) for OnProfileCopied and (event, db) for
    -- OnProfileReset. Only a switch names the profile that is now active: a copy
    -- and a reset leave it where it was, so both announce the active key.
    local active = (db and db.keys and db.keys.profile) or "Default"
    local key = active
    if event ~= "OnProfileCopied" and event ~= "OnProfileReset" then key = arg or active end
    traceProfileEvent(event, key, arg)

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
    -- Per-profile, so they have to run on every swap — see MigrateSpecKeys
    -- and MigrateColorShape (KICKCD-R-01: a stamp-gated color or font-flag
    -- step converted only the profile active at the upgrade).
    self:MigrateSpecKeys(self.db)
    self:MigrateColorShape(self.db)
    self:MigrateFontFlags(self.db)
    self:BuildSpells()
    self:MigrateProfile()

    -- THE MASTER SWITCH CAN HAVE MOVED WITH THE PROFILE (slash-commands-§7).
    --
    -- `enabled` is a stored setting like any other, so a switch, a copy or a
    -- reset can flip it with no checkbox ticked and no verb typed. A player
    -- switching to a profile where the addon is enabled expects it to come up,
    -- and one switching to a profile where it is off expects it to go inert --
    -- which is why AceDB's three profile callbacks are on slash-commands-§7's list of things a
    -- disabled addon MUST keep. Re-read the path and settle the latch; it fires a
    -- callback only on an actual edge, so a profile that agrees with the last one
    -- costs nothing.
    --
    -- BEFORE the bus announcement, for the reason settings/Panel.lua's write seam
    -- gives: the modules re-render off that message, and re-rendering an addon
    -- that is about to stand down draws a frame of something that is already off.
    if NS.RefreshEnabledHold then NS.RefreshEnabledHold() end

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

    -- The color-shape and font-flag steps, for the same per-profile reason:
    -- the ladder runs them once per account, and this is what reaches the
    -- profiles that were not active then (KICKCD-R-01). Both idempotent.
    self:MigrateColorShape(db)
    self:MigrateFontFlags(db)

    -- First-creation seeding. Database:BuildSpells() is a no-op for already
    -- populated profiles, so it's safe on every login. Profile changes
    -- re-trigger it via OnProfileChanged.
    self:BuildSpells()

    -- Walk any required account-level migrations forward (the stamp).
    self:MigrateProfile()

    -- Wire profile callbacks. AceDB calls these as `obj:method(event, db, key)`
    -- when we register with (self, "OnProfileChanged", "OnProfileChanged").
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
end


