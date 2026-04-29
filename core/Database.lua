-- core/Database.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.2 and §4
--
-- Owns the AceDB-3.0 instance, the defaults table, profile callbacks,
-- and the migration scaffold. The defaults shape mirrors §4 of the
-- design doc exactly. The `spells` sub-table is left empty here on
-- purpose — defaults/Spells.lua (Agent A3) populates KickCD.DefaultSpells
-- at file-load time, and Database:BuildSpells() merges that into the
-- profile only on first creation so user edits are never stomped.

KickCD = KickCD or {}

local Database = {}
KickCD.Database = Database

-- ---------------------------------------------------------------------------
-- Defaults (DEFAULT_PROFILE shape per TECHNICAL_DESIGN §4)
-- ---------------------------------------------------------------------------

local DEFAULT_PROFILE = {
    enabled = true,
    locked  = true,
    scale   = 1.0,
    alpha   = 1.0,

    icons = {
        primarySize      = 48,
        secondarySize    = 0.7,        -- multiplier of primary
        layout           = "horizontal", -- "horizontal" | "vertical"
        primaryAnchor    = "left",      -- "left"|"right"|"top"|"bottom"
        gap              = 4,
        readyAlpha       = 1.0,
        cooldownAlpha    = 0.4,
        cooldownTint     = { 1, 0.4, 0.4, 1 },
        showCooldownText = false,
        cooldownTextFont = "Friz Quadrata TT",
        cooldownTextSize = 14,
        showCharges      = true,
    },

    anchors = {
        icons = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 },
    },

    -- spells[CLASS][SPEC] = { { spellID, category, enabled }, ... } in priority order.
    -- Populated by Database:BuildSpells() on first profile creation by deep-copying
    -- KickCD.DefaultSpells (provided by defaults/Spells.lua which loads AFTER core/).
    spells = {},
}

local DEFAULTS = {
    profile = DEFAULT_PROFILE,
    global  = {
        dbVersion = 0,  -- bumped to LATEST_VERSION by RunMigrations()
    },
}

-- Expose for any caller that needs to deep-copy-on-demand (e.g. the Spells
-- editor's "Reset to defaults" button).
KickCD.DEFAULT_PROFILE = DEFAULT_PROFILE

-- ---------------------------------------------------------------------------
-- Migrations
-- ---------------------------------------------------------------------------

local LATEST_VERSION = 1

-- Migration[N] runs to take the schema from version N-1 → N.
-- v0.1 ships at version 1 with no actual transformation work — the table
-- structure was right from the start. Future patches add entries here.
local Migrations = {
    [1] = function(db) end,  -- initial — no-op
    -- [2] = function(db) ... end,
}

function Database:RunMigrations()
    if not self.db then return end
    local current = self.db.global.dbVersion or 0
    for v = current + 1, LATEST_VERSION do
        local fn = Migrations[v]
        if fn then
            local ok, err = pcall(fn, self.db)
            if not ok and KickCD.Util then
                KickCD.Util.print("migration v" .. v .. " failed:", err)
            end
        end
        self.db.global.dbVersion = v
    end
end

Database.LATEST_VERSION = LATEST_VERSION
Database.Migrations     = Migrations

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

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = deepCopy(vv) end
    return out
end

local function isEmpty(t)
    if type(t) ~= "table" then return true end
    return next(t) == nil
end

--- Populate the active profile's spells from KickCD.DefaultSpells, and
--- append the racial cast-stopper for the player's race. Idempotent for
--- already-populated profiles — only runs once per profile.
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

    local source = KickCD.DefaultSpells
    if type(source) ~= "table" then
        -- defaults/Spells.lua hasn't loaded yet, or failed to load.
        -- Leave spells empty; the spells module will treat that as "track nothing".
        return
    end

    -- Deep-copy each {spellID, category} entry into a profile-shaped record
    -- with enabled=true. The defaults file uses positional pairs to stay
    -- compact; the profile uses named fields so user edits in the UI are
    -- self-describing in the saved-variable file.
    for class, specs in pairs(source) do
        profile.spells[class] = profile.spells[class] or {}
        for spec, list in pairs(specs) do
            local out = {}
            for i, entry in ipairs(list) do
                local id  = entry.spellID  or entry[1]
                local cat = entry.category or entry[2]
                if id then
                    out[i] = {
                        spellID  = id,
                        category = cat or "other",
                        enabled  = entry.enabled ~= false,
                    }
                end
            end
            profile.spells[class][spec] = out
        end
    end

    -- Append the racial cast-stopper into every spec list of the player's
    -- own class. Only on first creation — see method docstring.
    local racials = KickCD.RaceCastStoppers
    if type(racials) == "table" then
        local _, race = UnitRace("player")
        local _, classFile = UnitClass("player")
        local racialID = racials[race]
        if racialID and classFile and profile.spells[classFile] then
            for _, list in pairs(profile.spells[classFile]) do
                -- Avoid appending if it's already in the list (defensive —
                -- some default lists may already include it via PvE bias).
                local already = false
                for _, e in ipairs(list) do
                    if e.spellID == racialID then already = true; break end
                end
                if not already then
                    table.insert(list, {
                        spellID  = racialID,
                        category = "racial",
                        enabled  = true,
                    })
                end
            end
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

    -- A reset wipes the profile back to defaults (which leaves spells = {}).
    -- Re-seed spells so the user gets a working list immediately, just like
    -- a fresh profile would.
    self:BuildSpells()

    -- Fire the closed internal message — see TECHNICAL_DESIGN §1.
    -- This is the only message Database is allowed to emit.
    if KickCD and KickCD.SendMessage then
        KickCD:SendMessage("KickCD_PROFILE_CHANGED", { newProfileKey = key })
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Build the AceDB instance and run migrations. Called once from
--- KickCD:OnInitialize().
function Database:Init()
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB then
        if KickCD.Util then KickCD.Util.print("AceDB-3.0 missing — bailing") end
        return
    end

    -- The third positional argument `true` makes per-character the default
    -- profile scope on first login (FR-10.2): a Mage and a DH on the same
    -- account get their own configs out of the box, then the user can
    -- switch to "Default" / per-class / per-realm via the Profiles panel.
    local db = AceDB:New("KickCDDB", DEFAULTS, true)
    self.db    = db
    KickCD.db  = db

    -- Run forward-only migrations against db.global.dbVersion before any
    -- module reads from the profile. Safe even on first install — the loop
    -- runs from 1..LATEST_VERSION starting from a stored 0.
    self:RunMigrations()

    -- First-creation seeding. Database:BuildSpells() is a no-op for already
    -- populated profiles, so it's safe on every login. Profile changes
    -- re-trigger it via OnProfileChanged.
    self:BuildSpells()

    -- Wire profile callbacks. AceDB calls these as `obj:method(event, db, key)`
    -- when we register with (self, "OnProfileChanged", "OnProfileChanged").
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
end
