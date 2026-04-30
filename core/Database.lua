-- core/Database.lua — KickCD v0.1
--
-- Owns the AceDB-3.0 instance, the defaults table, and profile
-- callbacks. The `spells` sub-table is left empty here on purpose —
-- defaults/Spells.lua populates KickCD.DefaultSpells at file-load time,
-- and Database:BuildSpells() merges that into the profile only on
-- first creation so user edits are never stomped.

KickCD = KickCD or {}

local Database = {}
KickCD.Database = Database

-- ---------------------------------------------------------------------------
-- Defaults (DEFAULT_PROFILE shape per TECHNICAL_DESIGN §4)
-- ---------------------------------------------------------------------------

local DEFAULT_PROFILE = {
    enabled    = true,
    locked     = true,
    scale      = 1.0,
    alpha      = 1.0,
    debugLog   = false,
    -- "always" | "in_combat" | "target_casting"
    -- Controls when the icon grid is visible. "always" is the v0.1
    -- behavior; "in_combat" gates on InCombatLockdown(); "target_casting"
    -- gates on UnitCastingInfo("target") / UnitChannelInfo("target") being
    -- non-nil. Master enable still wins — disabled = always hidden.
    visibility = "always",

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
        -- When true, the cooldown swipe + countdown text are hidden
        -- during the global cooldown period (≤ ~1.6s remaining); only
        -- real cooldowns render the swipe/text. The icon-body alpha and
        -- tint already treat GCD as "ready" via curve evaluation; this
        -- toggle extends the same suppression to the swipe and text.
        suppressGCDSwipe = true,
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
        primaryGlowType      = "proc",
        primaryGlowColor     = { 0.95, 0.95, 0.32, 1 },
        secondaryGlowTrigger = "never",
        secondaryGlowType    = "proc",
        secondaryGlowColor   = { 0.95, 0.95, 0.32, 1 },
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

        -- Anchoring. "FREE" = a free-floating frame the user drags around
        -- (saved to anchors.castbar). "PRIMARY" = anchored to the icon grid's
        -- primary icon at (anchorPoint, castbarPoint, offset). Anchoring to
        -- the primary icon button means the cast bar follows the grid for
        -- free if the user drags the grid; the cast bar itself becomes
        -- non-draggable in this mode.
        --
        -- anchorPoint  is the standard 9-point anchor (TOPLEFT/TOP/TOPRIGHT/
        --              LEFT/CENTER/RIGHT/BOTTOMLEFT/BOTTOM/BOTTOMRIGHT) on the
        --              primary icon's frame.
        -- castbarPoint is the same 9-point anchor on the cast bar itself.
        anchorMode    = "FREE",
        anchorPoint   = "TOP",
        castbarPoint  = "BOTTOM",
        anchorOffsetX = 0,
        anchorOffsetY = 8,

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
        autoSize     = false,

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
}

-- Expose for any caller that needs to deep-copy-on-demand (e.g. the Spells
-- editor's "Reset to defaults" button).
KickCD.DEFAULT_PROFILE = DEFAULT_PROFILE

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

--- Build the AceDB instance. Called once from KickCD:OnInitialize().
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
