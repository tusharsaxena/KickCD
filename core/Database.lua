-- core/Database.lua
--
-- Owns the AceDB-3.0 instance, the defaults table, and profile
-- callbacks. The `spells` sub-table is left empty here on purpose —
-- defaults/Spells.lua populates KickCD.DefaultSpells at file-load time,
-- and Database:BuildSpells() merges that into the profile only on
-- first creation so user edits are never stomped.

local addonName, NS = ...

local Database = {}
NS.Database = Database

-- ---------------------------------------------------------------------------
-- Defaults (DEFAULT_PROFILE shape — see docs/saved-variables.md)
-- ---------------------------------------------------------------------------

-- Schema version. Increment whenever a non-additive change is made to
-- DEFAULT_PROFILE's shape (rename, restructure, type change). Additive
-- changes (new leaf settings) are absorbed by AceDB's defaults merge
-- and don't need a version bump. The version is an addon-wide integer
-- stored in db.global.schemaVersion (§2.2 / §5.1) — NOT per-profile.
-- Database:MigrateProfile reads it on Init and on every profile swap and
-- walks any required migrations forward. v2 folds the legacy top-level
-- icons/castbar/anchors tables into units.target (see migrations[1] /
-- Database:FoldLegacyUnits below). v3 rekeys profile.spells from localised
-- spec NAMES to numeric spec IDs (see migrations[2] /
-- Database:MigrateSpecKeys below).
local CURRENT_DB_VERSION = 3

-- File-local recursive deep-copy. Deliberately independent of NS.Util —
-- Database.lua is one of the first files to load and must stay
-- self-contained rather than depend on load order.
local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end

-- Per-unit appearance defaults, defined once and deep-copied per unit
-- (target / focus) so profiles never alias the same sub-table.
local ICONS_DEFAULT = {
        primarySize      = 64,
        secondarySize    = 0.5,        -- multiplier of primary
        -- Anchor of the secondary block on the primary. The first word
        -- (TOP/BOTTOM/LEFT/RIGHT) picks the side of the primary the block
        -- attaches to; the second (MIDDLE plus the perpendicular axis
        -- alignment, LEFT/RIGHT for TOP/BOTTOM sides, TOP/BOTTOM for
        -- LEFT/RIGHT sides) picks where on that side. A 13th value,
        -- plain CENTER, stacks the block on top of the primary at the
        -- grid's centerpoint.
        --
        -- Legacy "_CENTER" tokens still parse — modules/IconGrid.lua's
        -- parseAnchor accepts MIDDLE and CENTER as synonyms — so saved
        -- profiles built before this rename keep working.
        anchor           = "RIGHT_MIDDLE",
        gap              = 0,
        zoom             = 0.10,        -- 0..0.25 — TexCoord inset that crops the Blizzard icon border
        readyAlpha       = 1.0,
        cooldownAlpha    = 0.25,
        cooldownTint     = { 1, 0.4, 0.4, 1 },
        -- When true, the cooldown swipe + countdown text are hidden
        -- during the global cooldown period (≤ ~1.6s remaining); only
        -- real cooldowns render the swipe/text. The icon-body alpha and
        -- tint already treat GCD as "ready" via curve evaluation; this
        -- toggle extends the same suppression to the swipe and text.
        suppressGCDSwipe = true,
        borderShow       = true,
        -- LSM "border" key, fed verbatim into LSM:Fetch("border", ...) and
        -- written onto the per-icon BackdropTemplate's edgeFile. Castbar
        -- uses the same default for visual consistency between the two
        -- pieces of UI.
        borderTexture    = "Blizzard Tooltip",
        borderColor      = { 0, 0, 0, 1 },
        borderSize       = 2,
        showCooldownText = true,
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
        secondaryRows    = 2,
        secondaryCols    = 3,
        secondaryGrow    = "down_right",
        secondaryOffsetX = 0,
        secondaryOffsetY = 0,

        -- Per-icon ready glow. The trigger picks WHEN the glow fires and
        -- the type picks WHICH visual. Trigger values:
        --   * "never"                       — glow off
        --   * "always"                      — glow whenever the spell is ready
        --   * "target_casting"              — only while target is casting
        --   * "target_casting_interruptible" — only for interruptible target casts
        -- Type values map to LibCustomGlow's four glow effects:
        --   * "button"   — Blizzard's spell-activation rotating rays + spark
        --   * "proc"     — Blizzard's modern proc flipbook
        --   * "pixel"    — animated pixel-art border
        --   * "autocast" — pet auto-cast sparkle particles
        -- Primary and secondary icons each carry their own trigger / type /
        -- color so a player can flag the primary with one style and the
        -- supports with another.
        primaryGlowTrigger   = "never",
        primaryGlowType      = "pixel",
        primaryGlowColor     = { 1, 1, 0, 1 },
        secondaryGlowTrigger = "never",
        secondaryGlowType    = "pixel",
        secondaryGlowColor   = { 1, 1, 0, 1 },
}

local CASTBAR_DEFAULT = {
        enabled      = true,
        width        = 250,
        height       = 24,
        iconSize     = 24,
        iconPosition = "OFF",       -- "LEFT", "RIGHT", or "OFF"
        showSpark    = true,
        showName     = true,
        showTime     = true,
        font         = "Friz Quadrata TT",
        fontSize     = 10,
        fontFlags    = "OUTLINE",

        -- Anchoring. "FREE" = a free-floating frame the user drags around
        -- (saved to anchors.castbar). "PRIMARY" = anchored to the icon grid's
        -- primary icon at (anchorPoint, castbarPoint, offset). Anchoring to
        -- the primary icon button means the cast bar follows the grid for
        -- free if the user drags the grid; the cast bar itself becomes
        -- non-draggable in this mode.
        --
        -- anchorPoint  picks one of 13 anchor points on the primary
        --              icon's frame. Tokens follow `<SIDE>_<ALIGN>`
        --              (TOP_MIDDLE, BOTTOM_LEFT, …) plus a plain
        --              `CENTER` whole-frame option. Same set as the
        --              Icons grid's `icons.anchor` dropdown.
        -- castbarPoint is the same 13-option anchor on the cast bar
        --              itself.
        --
        -- Both are translated to SetPoint-compatible 9-point names by
        -- modules/Castbar.lua at runtime; legacy 9-point tokens
        -- (TOP, TOPLEFT, BOTTOM, …) still pass through unchanged.
        anchorMode    = "PRIMARY",
        anchorPoint   = "BOTTOM_LEFT",
        castbarPoint  = "TOP_LEFT",
        anchorOffsetX = 0,
        anchorOffsetY = -1,

        -- Orientation + growth. Driven via StatusBar:SetOrientation and
        -- SetReverseFill so all the per-frame arithmetic stays C-side.
        --
        -- HORIZONTAL + RIGHT: cast fills left → right (default).
        -- HORIZONTAL + LEFT:  cast fills right → left.
        -- VERTICAL + UP:      cast fills bottom → top.
        -- VERTICAL + DOWN:    cast fills top → bottom.
        --
        -- Channels drain in the same direction the equivalent cast would fill.
        orientation   = "HORIZONTAL",
        growDirection = "RIGHT",

        -- Auto-size to the icon grid's matching dimension. When ON and the
        -- bar is anchored to the primary icon, horizontal bars take the
        -- icon grid's full width and vertical bars take its full height —
        -- the orthogonal dimension stays the user-configured width/height.
        autoSize     = true,

        -- Per-text-element anchor + offset. Position is one of
        -- "INSIDE_LEFT", "INSIDE_RIGHT", "CENTER", "OUTSIDE_LEFT",
        -- "OUTSIDE_RIGHT". OffsetX/Y are pixel deltas applied on top
        -- of the anchor.
        namePosition = "CENTER",
        nameOffsetX  = 0,
        nameOffsetY  = 0,
        -- Maximum visible characters in the spell name before
        -- replacing the tail with an ellipsis. 0 disables
        -- truncation entirely (full name shown). Length is byte-
        -- counted via `#`; multi-byte localized names may truncate
        -- mid-character at the edge but won't error.
        nameTruncate = 0,
        timePosition = "CENTER",
        timeOffsetX  = 0,
        timeOffsetY  = -20,

        -- Per-state appearance (interruptible vs uninterruptible casts).
        -- Switched at render time via C_CurveUtil.EvaluateColorValueFromBoolean
        -- on the cast's secret notInterruptible bool — see modules/Castbar.lua.
        interruptible = {
            statusBarTexture = "Blizzard Raid Bar",
            barColor         = { 1,    0.85, 0.05, 1   },  -- yellow
            bgColor          = { 0,    0,    0,    0.5 },
            nameTextColor    = { 1,    1,    1,    1   },
            borderShow       = true,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { 0,    0,    0,    1   },
            borderSize       = 2,
        },
        uninterruptible = {
            statusBarTexture = "Blizzard Raid Bar",
            barColor         = { 0.85, 0.10, 0.10, 1   },  -- red
            bgColor          = { 0,    0,    0,    0.5 },
            nameTextColor    = { 1,    1,    1,    1   },
            borderShow       = true,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { 0,    0,    0,    1   },
            borderSize       = 2,
        },
}

-- Single-sourced so Target and Focus ship an IDENTICAL label appearance
-- (copy()'d into each unit below). label.show/label.text stay per-unit;
-- only `style` is duplicated + link-resolved (NS.Units.LabelStyle).
local LABELSTYLE_DEFAULT = {
        attach   = "icons",       -- "castbar" | "icons"
        point    = "BOTTOM",      -- the label's own anchor point
        relPoint = "TOP",         -- point on the attach frame
        offsetX  = 0,
        offsetY  = 12,
        justifyH = "CENTER",      -- LEFT | CENTER | RIGHT
        justifyV = "MIDDLE",      -- TOP  | MIDDLE | BOTTOM
        rotation = 0,             -- degrees
        font     = "Friz Quadrata TT",
        size     = 14,
        flags    = "OUTLINE",     -- NONE | OUTLINE | THICKOUTLINE | MONOCHROME
        color    = { 1, 0.82, 0, 1 }, -- Blizzard gold, matches GameFontNormal
}

local DEFAULT_PROFILE = {
    enabled    = true,
    locked     = false,
    scale      = 1.0,
    alpha      = 1.0,
    -- (debug logging is a session-only flag in KickCD.State.debug, never in SV — §12.5)
    -- "always" | "in_combat" | "target_casting" | "target_casting_interruptible"
    -- Controls when the icon grid is visible. "in_combat" gates on
    -- InCombatLockdown(); "target_casting" gates on UnitCastingInfo /
    -- UnitChannelInfo on the target being non-nil; "target_casting_interruptible"
    -- additionally hides during uninterruptible casts via the C-side alpha
    -- mask. Master enable still wins — disabled = always hidden.
    visibility = "target_casting_interruptible",

    -- Per-unit widgets. Appearance (icons/castbar) is duplicated per unit;
    -- Focus defaults to link=true so it mirrors Target's appearance live
    -- (NS.Units resolves the link). enabled/anchors/label.text stay per-unit
    -- even while linked. See docs/saved-variables.md.
    units = {
        target = {
            enabled = true,
            link    = false,             -- target is never linked
            label   = { show = true, text = "Target", style = copy(LABELSTYLE_DEFAULT) },
            anchors = {
                icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
                castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
            },
            icons   = copy(ICONS_DEFAULT),
            castbar = copy(CASTBAR_DEFAULT),
        },
        focus = {
            enabled = true,
            link    = true,              -- mirror target appearance by default
            label   = { show = true, text = "Focus", style = copy(LABELSTYLE_DEFAULT) },
            anchors = {
                -- offset from target so the two grids don't overlap on first enable
                -- (~140px gap: ~10px clearance between the Focus timer bottom
                -- and the Target label top, given each unit's ~130px footprint)
                icons   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 260 },
                castbar = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 260 },
            },
            icons   = copy(ICONS_DEFAULT),
            castbar = copy(CASTBAR_DEFAULT),
        },
    },

    -- spells[CLASS][SPEC] = { { spellID, category, enabled }, ... } in priority order.
    -- Populated by Database:BuildSpells() on first profile creation by deep-copying
    -- KickCD.DefaultSpells (provided by defaults/Spells.lua which loads AFTER core/).
    spells = {},
}

local DEFAULTS = {
    profile = DEFAULT_PROFILE,
    -- Addon-wide (account) scope. The schema version lives here, not on the
    -- profile, so a migration runs once per account rather than once per
    -- profile (§5.1). See Database:MigrateProfile for the one-shot adoption
    -- of a legacy per-profile dbVersion.
    global = {
        schemaVersion = CURRENT_DB_VERSION,
    },
}

-- Expose for any caller that needs to deep-copy-on-demand (e.g. the Spells
-- editor's "Reset to defaults" button).
NS.DEFAULT_PROFILE = DEFAULT_PROFILE

-- ---------------------------------------------------------------------------
-- Spell-list traversal helpers
-- ---------------------------------------------------------------------------
--
-- Every consumer that needs to read or mutate a spec's spell list goes
-- through these two helpers so the `db.profile.spells[CLASS][SPEC]`
-- walk lives in exactly one place. The split between read-only and
-- lazy-create matters: getActiveList in the panel fires on every
-- dropdown browse, and lazy-creating an empty per-spec table on every
-- browse pollutes the saved-vars file with 13 classes × 4 specs of
-- empty tables. The read-only helper returns nil for missing entries
-- so consumers can short-circuit without touching the profile shape.
--
-- Callers:
--   * GetSpellList:    Cooldowns:Rebuild, IconGrid:BuildActiveList,
--                      core/KickCD.lua slash-command read paths,
--                      settings/Spells.lua getActiveList.
--   * EnsureSpellList: core/KickCD.lua spellsAdd / spellsReset,
--                      settings/Spells.lua mutating popups.

--- Read-only spell-list lookup. Returns the entry array (or nil if no
--- list exists for this class+spec). Never mutates the profile shape,
--- so safe to call from browse paths that flip class/spec dropdowns.
-- @param class string normalised class file token (e.g. "HUNTER")
-- @param spec  string normalised spec token (e.g. "BEASTMASTERY")
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
--- tables if missing, then returns the list. Use this only from
--- mutators (Add / Reset / Reorder) where an empty list IS the right
--- post-condition for an unseeded spec. Browse-only consumers should
--- use GetSpellList instead.
-- @param class string normalised class file token (e.g. "HUNTER")
-- @param spec  string normalised spec token (e.g. "BEASTMASTERY")
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

--- Populate the active profile's spells from KickCD.DefaultSpells, and
--- append the racial cast-stopper for the player's race. Idempotent for
--- already-populated profiles — only runs once per profile.
---
--- "No re-seed if non-empty" is a deliberate policy, not an oversight.
--- A user who has customised any class+spec (even by clearing every row
--- of an active spec) has signalled intent: subsequent logins must NOT
--- silently re-seed their work. The empty check is on the WHOLE
--- `profile.spells` table — if any class entry exists at all, every
--- spec list is left alone, including ones the user hasn't touched.
---
--- Recovery path for users who DO want defaults back:
---   * `/kcd reset spells`              — wipe all class+spec lists and
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

    -- Deep-copy each {spellID, category} entry into a profile-shaped record
    -- with enabled=true. The defaults file uses positional pairs to stay
    -- compact; the profile uses named fields so user edits in the UI are
    -- self-describing in the saved-variable file. EnsureSpellList lazy-
    -- creates the per-class / per-spec containers before we overwrite the
    -- list with the freshly-built copy.
    for class, specs in pairs(source) do
        for spec, list in pairs(specs) do
            local target = self:EnsureSpellList(class, spec)
            -- Wipe in place rather than replacing the table — keeps any
            -- references downstream stable across the build.
            for i = #target, 1, -1 do target[i] = nil end
            for i, entry in ipairs(list) do
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
    end

    -- Append the racial cast-stopper into every spec list of the player's
    -- own class. Only on first creation — see method docstring.
    local racials = NS.RaceCastStoppers
    if type(racials) == "table" then
        local _, race = UnitRace("player")
        local _, classFile = UnitClass("player")
        local racialID = racials[race]
        if racialID and classFile and profile.spells[classFile] then
            for spec in pairs(profile.spells[classFile]) do
                local list = self:GetSpellList(classFile, spec)
                if list then
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
end

--- Wipe the active profile's spells and re-seed from KickCD.DefaultSpells +
--- racial. Used by the General > "Reset all settings" action so the user
--- gets the current addon defaults across every class and spec, not just
--- the one currently selected in the Spells editor. BuildSpells() is
--- idempotent on populated profiles, so we have to clear first.
function Database:ResetAllSpells()
    if not (self.db and self.db.profile) then return end
    self.db.profile.spells = {}
    self:BuildSpells()
    if NS and NS.SendMessage then
        local key = (self.db.keys and self.db.keys.profile) or "Default"
        NS:SendMessage("Ka0s_KickCD_PROFILE_CHANGED", { newProfileKey = key })
    end
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

--- Fold a legacy pre-units profile (top-level icons/castbar/anchors) into
--- units.target. Idempotent and SHAPE-DRIVEN, not version-gated: a v1 account
--- that stored schemaVersion as the default never persisted it, so AceDB's
--- defaults merge backfills it to the new CURRENT value and masks the account
--- as already-current (the same KCD-20 backfill trap documented in
--- MigrateProfile). Keying on the presence of the old top-level tables detects
--- exactly the accounts that carry customised legacy data; a fresh v2 install
--- has no top-level icons/castbar/anchors and is a no-op.
function Database:FoldLegacyUnits(db)
    db = db or self.db
    if not (db and db.profile) then return end
    local p = db.profile
    if p.icons == nil and p.castbar == nil and p.anchors == nil then return end
    p.units = p.units or {}
    p.units.target = p.units.target or {}
    local t = p.units.target
    if p.icons   ~= nil then t.icons   = p.icons;   p.icons   = nil end
    if p.castbar ~= nil then t.castbar = p.castbar; p.castbar = nil end
    if p.anchors ~= nil then
        t.anchors = t.anchors or {}
        if p.anchors.icons   ~= nil then t.anchors.icons   = p.anchors.icons   end
        if p.anchors.castbar ~= nil then t.anchors.castbar = p.anchors.castbar end
        p.anchors = nil
    end
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
--- copied in, so a user's customised values are never overwritten. A fresh
--- install already has every key and is a no-op.
function Database:BackfillLabelStyle(db)
    db = db or self.db
    if not (db and db.profile and db.profile.units) then return end
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

--- Rekey `profile.spells[CLASS]` from spec NAME tokens to numeric spec IDs.
---
--- Up to v2 the spec key was the player's localised spec name, uppercased
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
--- Losing a user's customised list is worse than leaving a stale key.
function Database:MigrateSpecKeys(db)
    db = db or self.db
    if not (db and db.profile) then return end
    local spells = db.profile.spells
    if type(spells) ~= "table" then return end

    local Util = NS.Util
    if not (Util and Util.ResolveSpecID) then return end

    for classFile, bySpec in pairs(spells) do
        if type(bySpec) == "table" then
            -- Collect first: mutating a table while pairs() walks it is
            -- undefined behaviour in Lua.
            local rekey = {}
            for specKey, list in pairs(bySpec) do
                if type(specKey) == "string" then
                    rekey[#rekey + 1] = { key = specKey, list = list }
                end
            end
            for _, entry in ipairs(rekey) do
                local specID = Util.ResolveSpecID(entry.key, classFile)
                if not specID then
                    if NS.State and NS.State.debug then
                        NS.Debug("Migrate", "spells: %s/%s unresolved, left as-is",
                            tostring(classFile), tostring(entry.key))
                    end
                elseif bySpec[specID] ~= nil then
                    if NS.State and NS.State.debug then
                        NS.Debug("Migrate", "spells: %s/%s collides with %d, left as-is",
                            tostring(classFile), tostring(entry.key), specID)
                    end
                else
                    bySpec[specID] = entry.list
                    bySpec[entry.key] = nil
                    if NS.State and NS.State.debug then
                        NS.Debug("Migrate", "spells: %s/%s -> %d",
                            tostring(classFile), tostring(entry.key), specID)
                    end
                end
            end
        end
    end
end

local migrations = {
    -- [from-version] = function(db) ... db.global.schemaVersion = from + 1 end
    -- Each step bumps db.global.schemaVersion to the from-version+1 and may
    -- read/write db.profile as needed.
    [1] = function(db) NS.Database:FoldLegacyUnits(db); db.global.schemaVersion = 2 end,
    [2] = function(db) NS.Database:MigrateSpecKeys(db); db.global.schemaVersion = 3 end,
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

    -- Fire the closed internal message — see docs/message-bus.md.
    -- This is the only message Database is allowed to emit.
    if NS and NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_PROFILE_CHANGED", { newProfileKey = key })
    end
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
    local db = AceDB:New("KickCDDB", DEFAULTS, true)
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

    -- Rekey any localised spec-name spell keys to numeric spec IDs before
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


