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
    enabled  = true,
    locked   = true,
    scale    = 1.0,
    alpha    = 1.0,
    debugLog = false,

    icons = {
        primarySize      = 48,
        secondarySize    = 0.7,        -- multiplier of primary
        -- Anchor of the secondary block on the primary. The first word
        -- (TOP/BOTTOM/LEFT/RIGHT) picks the side of the primary the block
        -- attaches to; the second (CENTER plus the perpendicular axis
        -- alignment, LEFT/RIGHT for TOP/BOTTOM sides, TOP/BOTTOM for
        -- LEFT/RIGHT sides) picks where on that side. 12 valid values.
        anchor           = "RIGHT_CENTER",
        gap              = 4,
        zoom             = 0.08,        -- 0..0.25 — TexCoord inset that crops the Blizzard icon border
        readyAlpha       = 1.0,
        cooldownAlpha    = 0.4,
        cooldownTint     = { 1, 0.4, 0.4, 1 },
        borderShow       = false,
        borderColor      = { 0, 0, 0, 1 },
        borderSize       = 1,
        showCooldownText = false,
        cooldownTextFont = "Friz Quadrata TT",
        cooldownTextSize = 14,
        cooldownTextFlags = "OUTLINE", -- "NONE"|"OUTLINE"|"THICKOUTLINE"|"MONOCHROME"
        showCharges      = true,
        -- Hover-tooltip on individual icons. The grid swallows mouse for
        -- drag while unlocked, so tooltips only fire while locked AND
        -- this flag is true (see modules/IconGrid.lua:ApplyLock).
        showTooltip      = false,
        -- Secondary-icon block. `rows × cols` capacity, geometric:
        --   * `rows` = vertical extent (number of horizontal lines, up/down).
        --   * `cols` = horizontal extent (number of vertical lines, left/right).
        -- secondaryGrow is a compound "<primary>_<secondary>" picking the
        -- fill direction inside the block (any of 8 combinations of
        -- right/left/down/up). It's independent of `anchor`: anchor places
        -- the block, grow arranges icons within it.
        -- secondaryOffsetX/Y shift the entire block by N pixels from where
        -- it would naturally land. Positive X = right, positive Y = down
        -- (screen convention; converted to WoW's y-up internally).
        secondaryRows    = 1,
        secondaryCols    = 6,
        secondaryGrow    = "right_down",
        secondaryOffsetX = 0,
        secondaryOffsetY = 0,
    },

    castbar = {
        enabled      = true,
        width        = 250,
        height       = 24,
        iconSize     = 24,
        iconPosition = "LEFT",      -- "LEFT", "RIGHT", or "OFF"
        showSpark    = true,
        showName     = true,
        showTime     = true,
        font         = "Friz Quadrata TT",
        fontSize     = 12,
        fontFlags    = "OUTLINE",

        -- Per-text-element anchor + offset. Position is one of
        -- "INSIDE_LEFT", "INSIDE_RIGHT", "CENTER", "OUTSIDE_LEFT",
        -- "OUTSIDE_RIGHT". OffsetX/Y are pixel deltas applied on top
        -- of the anchor.
        namePosition = "INSIDE_LEFT",
        nameOffsetX  = 0,
        nameOffsetY  = 0,
        timePosition = "INSIDE_RIGHT",
        timeOffsetX  = 0,
        timeOffsetY  = 0,

        -- Per-state appearance (interruptible vs uninterruptible casts).
        -- Switched at render time via C_CurveUtil.EvaluateColorValueFromBoolean
        -- on the cast's secret notInterruptible bool — see modules/Castbar.lua.
        interruptible = {
            statusBarTexture = "Blizzard",
            barColor         = { 1,    0.85, 0.05, 1   },  -- yellow
            bgColor          = { 0,    0,    0,    0.5 },
            nameTextColor    = { 1,    1,    1,    1   },
            borderShow       = false,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { 0,    0,    0,    1   },
            borderSize       = 1,
        },
        uninterruptible = {
            statusBarTexture = "Blizzard",
            barColor         = { 0.85, 0.10, 0.10, 1   },  -- red
            bgColor          = { 0,    0,    0,    0.5 },
            nameTextColor    = { 1,    1,    1,    1   },
            borderShow       = true,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { 1,    0.20, 0.20, 1   },
            borderSize       = 2,
        },
    },

    anchors = {
        icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 },
        castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 },
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

local LATEST_VERSION = 7

-- Migration[N] runs to take the schema from version N-1 → N.
-- v0.1 ships at version 1 with no actual transformation work — the table
-- structure was right from the start. Future patches add entries here.
local Migrations = {
    [1] = function(db) end,  -- initial — no-op

    -- v2: reworked the icons.* layout model.
    --   * primaryAnchor (corner-anchored 2D grid pivot) replaced by an
    --     axis-aware grow direction (left/right/up/down); drop the
    --     stored value so /kcd list and saved-vars reflect the live shape.
    --   * secondaryGrow's enum changed from "horizontal"/"vertical" to
    --     "right"/"left"/"down"/"up". Old values map: horizontal→right,
    --     vertical→down.
    --   * secondaryRows / secondaryCols stay in the model (rebuilt as
    --     part of the rework), so leave any saved values alone.
    [2] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local icons = profile.icons
            if type(icons) == "table" then
                icons.primaryAnchor = nil
                local g = icons.secondaryGrow
                if g == "horizontal" then
                    icons.secondaryGrow = "right"
                elseif g == "vertical" then
                    icons.secondaryGrow = "down"
                end
            end
        end
    end,

    -- v3: secondaryGrow gained a wrap-direction component. The single-axis
    -- enum ("right"/"left"/"down"/"up") was replaced by a compound form
    -- "<primary>_<secondary>" that also picks which side extra rows/cols
    -- accumulate. Old values map to the most natural wrap (down for
    -- horizontal, right for vertical):
    --   right → right_down,  left → left_down
    --   down  → down_right,  up   → up_right
    [3] = function(db)
        local map = {
            right = "right_down",
            left  = "left_down",
            down  = "down_right",
            up    = "up_right",
        }
        for _, profile in pairs(db.profiles or {}) do
            local icons = profile.icons
            if type(icons) == "table" then
                local g = icons.secondaryGrow
                if map[g] then icons.secondaryGrow = map[g] end
            end
        end
    end,

    -- v4: replaced `layout` (horizontal/vertical) with `anchor` — a
    -- 12-option enum that names which corner/edge of the primary the
    -- secondary block attaches to ({TOP,BOTTOM,LEFT,RIGHT}_{CENTER,...}).
    -- The old behavior placed the block adjacent to the primary on the
    -- side picked by `secondaryGrow`'s primary axis, with perpendicular
    -- centering when the perpendicular extent was 1 and corner alignment
    -- otherwise. Translate that to an anchor value here so the rendered
    -- block looks identical after the upgrade.
    [4] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local icons = profile.icons
            if type(icons) == "table" then
                local grow    = icons.secondaryGrow or "right_down"
                local primary = grow:match("^(%a+)_") or "right"
                local second  = grow:match("_(%a+)$")
                local rows    = icons.secondaryRows or 1
                local cols    = icons.secondaryCols or 6

                local side, perp, alignByDir
                if primary == "right" then
                    side, perp = "RIGHT", rows
                    alignByDir = (second == "down") and "TOP" or "BOTTOM"
                elseif primary == "left" then
                    side, perp = "LEFT", rows
                    alignByDir = (second == "down") and "TOP" or "BOTTOM"
                elseif primary == "down" then
                    side, perp = "BOTTOM", cols
                    alignByDir = (second == "right") and "LEFT" or "RIGHT"
                else  -- up
                    side, perp = "TOP", cols
                    alignByDir = (second == "right") and "LEFT" or "RIGHT"
                end
                icons.anchor = side .. "_" .. ((perp == 1) and "CENTER" or alignByDir)
                icons.layout = nil
            end
        end
    end,

    -- v5: introduced the cast-bar module. Existing profiles get the
    -- castbar sub-table seeded with the same defaults a fresh profile
    -- would pick up, plus the castbar anchor entry.
    [5] = function(db)
        local function castbarDefaults()
            return {
                enabled          = true,
                width            = 250,
                height           = 24,
                iconSize         = 24,
                iconPosition     = "LEFT",
                showSpark        = true,
                showName         = true,
                showTime         = true,
                font             = "Friz Quadrata TT",
                fontSize         = 12,
                fontFlags        = "OUTLINE",
                statusBarTexture = "Blizzard",
                barColor         = { 0.7, 0.2, 0.2, 1 },
                bgColor          = { 0,   0,   0,   0.5 },
                borderShow       = false,
                borderColor      = { 0,   0,   0,   1 },
                borderSize       = 1,
            }
        end
        for _, profile in pairs(db.profiles or {}) do
            if not profile.castbar then
                profile.castbar = castbarDefaults()
            end
            profile.anchors = profile.anchors or {}
            if not profile.anchors.castbar then
                profile.anchors.castbar =
                    { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 }
            end
        end
    end,

    -- v6: nested the cast-bar appearance fields under .interruptible /
    -- .uninterruptible so each cast state can have its own bar texture,
    -- color, background, name-text color, and border styling. Pre-v6
    -- profiles' flat castbar.barColor / .statusBarTexture / .bgColor /
    -- .borderShow / .borderColor / .borderSize move into .interruptible.*
    -- (treated as the previously-uniform "all casts" appearance), and a
    -- red-themed default block seeds .uninterruptible.* — borders default
    -- to ON for uninterruptible to make non-interruptable casts pop.
    -- The new fields nameTextColor and borderTexture are added on both
    -- sides with sensible defaults.
    [6] = function(db)
        local function uninterruptibleDefaults()
            return {
                statusBarTexture = "Blizzard",
                barColor         = { 0.85, 0.10, 0.10, 1   },
                bgColor          = { 0,    0,    0,    0.5 },
                nameTextColor    = { 1,    1,    1,    1   },
                borderShow       = true,
                borderTexture    = "Blizzard Tooltip",
                borderColor      = { 1,    0.20, 0.20, 1   },
                borderSize       = 2,
            }
        end
        for _, profile in pairs(db.profiles or {}) do
            local cb = profile.castbar
            if type(cb) == "table" then
                cb.interruptible = cb.interruptible or {
                    statusBarTexture = cb.statusBarTexture or "Blizzard",
                    barColor         = cb.barColor         or { 1, 0.85, 0.05, 1   },
                    bgColor          = cb.bgColor          or { 0, 0,    0,    0.5 },
                    nameTextColor    = { 1, 1, 1, 1 },
                    borderShow       = cb.borderShow == true,
                    borderTexture    = "Blizzard Tooltip",
                    borderColor      = cb.borderColor      or { 0, 0,    0,    1   },
                    borderSize       = cb.borderSize       or 1,
                }
                cb.uninterruptible = cb.uninterruptible or uninterruptibleDefaults()
                -- Strip the old flat fields so /kcd list and saved-vars
                -- reflect the live nested shape.
                cb.statusBarTexture = nil
                cb.barColor         = nil
                cb.bgColor          = nil
                cb.borderShow       = nil
                cb.borderColor      = nil
                cb.borderSize       = nil
            end
        end
    end,

    -- v7: added per-text-element position anchors plus X/Y offset for
    -- the spell-name and remaining-time labels on the cast bar. Default
    -- positions match the v6 layout: name inside-left, time inside-right.
    -- Also added the "OFF" option to iconPosition (no migration needed —
    -- old "LEFT" / "RIGHT" values still parse fine; the dropdown just
    -- gains a new value).
    [7] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local cb = profile.castbar
            if type(cb) == "table" then
                if cb.namePosition == nil then cb.namePosition = "INSIDE_LEFT"  end
                if cb.nameOffsetX  == nil then cb.nameOffsetX  = 0              end
                if cb.nameOffsetY  == nil then cb.nameOffsetY  = 0              end
                if cb.timePosition == nil then cb.timePosition = "INSIDE_RIGHT" end
                if cb.timeOffsetX  == nil then cb.timeOffsetX  = 0              end
                if cb.timeOffsetY  == nil then cb.timeOffsetY  = 0              end
            end
        end
    end,
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
