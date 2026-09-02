-- defaults/Profile.lua
--
-- THE profile defaults tree, and the only place a profile default value is
-- hardcoded (savedvariables-§2). core/Database.lua owns the AceDB assembly and
-- the migration runner; this file owns the shape those migrate towards.
--
-- Load order: the TOC's `# Defaults` block sits AFTER `# Core`, so
-- core/Database.lua cannot capture this tree in a file-scope local. It reaches
-- it at CALL time (Database:Init builds the AceDB defaults table, and
-- Database:BackfillLabelStyle reads NS.LABELSTYLE_DEFAULT), which is well after
-- every file has loaded. modules/ and settings/ load after this file and may
-- capture at load time, which modules/Castbar.lua does for its two per-state
-- fallbacks.
--
-- See docs/schema.md for the shape and its migration history.

local addonName, NS = ...

-- File-local recursive deep-copy. Deliberately independent of NS.Util —
-- this file loads ahead of the modules and must stay self-contained rather
-- than depend on load order.
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
        cooldownTint     = { r = 1, g = 0.4, b = 0.4, a = 1 },
        -- Every "use class color" companion in this tree is the class-color
        -- half of a swatch (options-ui-§17) and every one of them defaults OFF.
        -- On this page they resolve to the PLAYER's class: the grid draws the
        -- player's own interrupt cooldowns, whichever unit's page you set it on.
        useClassColorCooldownTint = false,
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
        borderColor      = { r = 0, g = 0, b = 0, a = 1 },
        useClassColorBorder = false,
        borderSize       = 2,
        showCooldownText = true,
        cooldownTextFont = "Friz Quadrata TT",
        cooldownTextSize = 14,
        -- ""|"OUTLINE"|"THICKOUTLINE"|"MONOCHROME"|"OUTLINE, MONOCHROME" -- the
        -- library's canonical set, where the EMPTY STRING is "None" and is a
        -- real stored value. The pre-v5 token for that was the literal "NONE",
        -- which SetFont ignored rather than honored; core/Database.lua's v4 -> v5
        -- step rewrites it.
        cooldownTextFlags = "OUTLINE",
        cooldownTextColor = { r = 1, g = 1, b = 1, a = 1 },
        useClassColorCooldownText = false,
        -- A soft drop shadow behind the countdown, for legibility over bright
        -- icon art. modules/IconGrid_Render.lua's ApplyTextConfig sets or clears
        -- it; there is no half state.
        cooldownTextShadow = false,
        showCharges      = true,
        -- The charges badge's inset from the icon's bottom-right corner, in
        -- pixels (positive X = right, positive Y = up). These two WERE the
        -- literal `-2, 2` in modules/IconGrid_Render.lua's SetPoint call and
        -- nothing else; the defaults are those exact numbers, so a profile
        -- that never touches either row draws the badge exactly where it
        -- always drew. Clamped to +/-32 on the way out (chargesOffset there),
        -- because a hand-edited SavedVariable is not an error, it is a badge
        -- parked off the icon with nothing to say why.
        chargesOffsetX   = -2,
        chargesOffsetY   = 2,
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
        primaryGlowColor     = { r = 1, g = 1, b = 0, a = 1 },
        useClassColorPrimaryGlowColor = false,
        secondaryGlowTrigger = "never",
        secondaryGlowType    = "pixel",
        secondaryGlowColor   = { r = 1, g = 1, b = 0, a = 1 },
        useClassColorSecondaryGlowColor = false,
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
        fontShadow   = false,
        -- The CAST TIME text's color. The spell name's is per-state and lives
        -- in the two tables below, because the interruptible flag that picks
        -- between them can be secret in combat and the switch is a curve
        -- evaluation -- a third writer over the same FontString would just lose
        -- to them. The cast time had no color at all before this.
        textColor         = { r = 1, g = 1, b = 1, a = 1 },
        useClassColorText = false,

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
            barColor         = { r = 1, g = 0.85, b = 0.05, a = 1 },  -- yellow
            useClassColorBar = false,
            -- How opaque the bar's FILL is. Folded into the per-state alpha
            -- curve in modules/Castbar.lua's ApplyState rather than applied as a
            -- SetAlpha of its own -- the two stacked bars are already
            -- alpha-switched off the secret notInterruptible flag, and a second
            -- multiplication would be arithmetic on a secret value.
            barAlpha         = 1,
            bgColor          = { r = 0, g = 0, b = 0, a = 0.5 },
            useClassColorBgColor = false,
            nameTextColor    = { r = 1, g = 1, b = 1, a = 1 },
            useClassColorNameTextColor = false,
            borderShow       = true,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { r = 0, g = 0, b = 0, a = 1 },
            useClassColorBorder = false,
            borderSize       = 2,
        },
        uninterruptible = {
            statusBarTexture = "Blizzard Raid Bar",
            barColor         = { r = 0.85, g = 0.10, b = 0.10, a = 1 },  -- red
            useClassColorBar = false,
            -- How opaque the bar's FILL is. Folded into the per-state alpha
            -- curve in modules/Castbar.lua's ApplyState rather than applied as a
            -- SetAlpha of its own -- the two stacked bars are already
            -- alpha-switched off the secret notInterruptible flag, and a second
            -- multiplication would be arithmetic on a secret value.
            barAlpha         = 1,
            bgColor          = { r = 0, g = 0, b = 0, a = 0.5 },
            useClassColorBgColor = false,
            nameTextColor    = { r = 1, g = 1, b = 1, a = 1 },
            useClassColorNameTextColor = false,
            borderShow       = true,
            borderTexture    = "Blizzard Tooltip",
            borderColor      = { r = 0, g = 0, b = 0, a = 1 },
            useClassColorBorder = false,
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
        flags    = "OUTLINE",     -- "" | OUTLINE | THICKOUTLINE | MONOCHROME | "OUTLINE, MONOCHROME"
        shadow   = false,
        color    = { r = 1, g = 0.82, b = 0, a = 1 }, -- Blizzard gold, matches GameFontNormal
        -- Unit-scoped, unlike the icon grid's companions: a label NAMES the unit
        -- it is drawn beside, so its class is that unit's (options-ui-§17). A
        -- linked Focus reads Target's style table and still resolves on FOCUS --
        -- the rendering unit, never the source of the table.
        useClassColor = false,
}

local DEFAULT_PROFILE = {
    enabled    = true,
    locked     = false,
    scale      = 1.0,
    alpha      = 1.0,
    -- (debug logging is a session-only flag in KickCD.State.debug, never in SV — debug-logging-§5)
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
    -- even while linked. See docs/schema.md.
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

-- Published for every caller that needs the shipped value: core/Database.lua's
-- AceDB assembly and label-style backfill, settings/Panel_Render.lua's reset
-- helpers, and modules/Castbar.lua's per-state fallbacks. NS.C is the short
-- alias the standard's `defaults/` shape names.
NS.C = DEFAULT_PROFILE
NS.DEFAULT_PROFILE   = DEFAULT_PROFILE
NS.CASTBAR_DEFAULT   = CASTBAR_DEFAULT
NS.LABELSTYLE_DEFAULT = LABELSTYLE_DEFAULT
