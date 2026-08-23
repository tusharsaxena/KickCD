-- core/Constants.lua
--
-- Named constants pulled out of individual modules so the value lives
-- in exactly one place and a reader doesn't have to puzzle out a magic
-- number's meaning at the use site. Loads early in the TOC (right after
-- core/Compat.lua) so every consumer can read KickCD.Const.* without
-- an existence check.
--
-- This file is intentionally tiny — it MUST stay free of any logic
-- (event registration, frame creation, etc.) so that loading it
-- early has no side effects. Add a constant here only if it is used
-- across modules or a comment at the use site has to explain it.

local addonName, NS = ...
local Const = {}
NS.Const = Const

-- Chat tag prepended to every user-facing chat line (slash-commands-§4). Single source of
-- truth: core/Util.lua's print() and any other chat-writing site reference
-- KickCD.PREFIX rather than hand-duplicating the escape sequence. Becomes
-- NS.PREFIX after the private-namespace migration.
NS.PREFIX = "|cff00ffff[KCD]|r"

-- Gray color opener for de-emphasized "notice" chat lines — an action the
-- user should see but not be alarmed by (e.g. a refused settings-open in
-- combat). Wrap the message BODY only (`GRAY .. text .. "|r"`); the cyan
-- [KCD] tag stays full-color. Canonical Ka0s notice styling (options-ui-§2).
NS.GRAY = "|cff9d9d9d"

-- ---------------------------------------------------------------------------
-- IconGrid: cooldown curve threshold
-- ---------------------------------------------------------------------------

-- Upper bound on the global cooldown duration. WoW's GCD is haste-modified
-- (typically 1.0–1.5s); 1.6s comfortably covers the unhasted case plus a
-- small fp epsilon. The alpha / tint / GCD-suppress curves in IconGrid are
-- evaluated against the cooldown's TOTAL length: a total ≤ this value is
-- "GCD only — show as ready", a total above it is "real CD — apply visual
-- states." Reading the REMAINING time instead conflates the tail of a real
-- cooldown with a GCD and brightens the icon ~1.5s early; see
-- evaluateByTotal in modules/IconGrid_Render.lua. Sub-second precision
-- isn't critical because the transition is a step, not a gradient.
Const.GCD_UPPER = 1.6

-- ---------------------------------------------------------------------------
-- Castbar: spell-name FontString insets
-- ---------------------------------------------------------------------------

-- Pixel inset used when the cast bar's name FontString is anchored
-- INSIDE the bar itself (the default position for HORIZONTAL bars).
-- Distance from the bar's edge to the text — visually the gap that
-- prevents the name from touching the bar border.
Const.CASTBAR_INSIDE_INSET  = 4

-- Pixel inset used when the cast bar's name FontString is anchored
-- OUTSIDE the bar (e.g. the "name floats above the bar" layout for
-- vertical orientations). Symmetric to CASTBAR_INSIDE_INSET so the
-- visual gap is identical regardless of which side the text lives on.
Const.CASTBAR_OUTSIDE_INSET = 4

-- ---------------------------------------------------------------------------
-- Settings panel: header layout
-- ---------------------------------------------------------------------------

-- PANEL_PADDING_X is deliberately absent. The horizontal inset from the
-- panel's left and right edges to its header / divider / body is
-- LibKa0s-Options-1.0's, published on the instance as `Helpers.PADDING_X`
-- and applied by the library's own header and EnsureScroll. options-ui-§8
-- forbids a host copy: the host copy is the one that goes stale, and the
-- whole point of extracting the panel chrome is that the panels cannot
-- drift apart. Read it off the instance; never restate the number here.

-- Vertical inset of the title (and the per-panel "Defaults" button next
-- to it) from the top of the panel. Roughly half the height of the
-- GameFontNormalHuge title glyph so the header doesn't crowd the
-- panel's top edge.
Const.PANEL_HEADER_TOP    = 20

-- Distance from the top of the panel to the divider underneath the
-- title. Sits in lockstep with PANEL_HEADER_TOP so the title-to-divider
-- gap (and divider-to-body gap below it) stay unchanged when the header
-- block is repositioned vertically.
Const.PANEL_HEADER_HEIGHT = 54

-- Width of the per-panel "Defaults" button in the header. Wide enough
-- to comfortably fit "Restore Defaults" in en-US without truncation.
Const.PANEL_DEFAULTS_W    = 110

-- ---------------------------------------------------------------------------
-- Debug console: shipped monospace font
-- ---------------------------------------------------------------------------

-- The face, by NAME. This is what LibSharedMedia is keyed on, because a name is
-- portable across installs where a path names one addon's folder.
-- core/MediaSetup.lua registers it at load.
Const.FONT_MONO_NAME = "JetBrains Mono"

-- Monospace TTF so the debug console's timestamps and [tags] line up regardless of
-- the user's installed fonts (debug-logging-§2), applied at 10pt. The bytes ship inside
-- the VENDORED LibKa0s payload (libs/LibKa0s/media/fonts/, OFL license beside
-- them) rather than under this addon's own media/ — one copy for the whole
-- collection, one license to track. core/MediaSetup.lua resolves the path, which
-- is why its TOC line sits above this file's.
--
-- THE FALLBACK IS A REAL CLIENT FONT, never a constructed path. SetFont accepts a
-- path to a file that is not there, fails to load it, and the text simply does not
-- draw — no error, no missing-file warning. A degraded install (no LibKa0s, so no
-- payload) gets Blizzard's own face and a console that is still readable.
Const.FONT_MONO = (NS.MediaFont and NS.MediaFont(Const.FONT_MONO_NAME))
    or _G.STANDARD_TEXT_FONT

-- ---------------------------------------------------------------------------
-- Specialization IDs
-- ---------------------------------------------------------------------------
--
-- Blizzard's numeric specialization IDs -- the FIRST return of
-- GetSpecializationInfo / GetSpecializationInfoForClassID, and the only
-- locale-invariant identity a spec has.
--
-- These are the keys used by defaults/Spells.lua and by
-- db.profile.spells[CLASS][specID]. Do NOT reintroduce the localized spec
-- NAME (GetSpecializationInfo's second return) as a lookup key: that was
-- issue #8, where a frFR Elemental Shaman derived "ELEMENTAIRE" and missed
-- defaults keyed "ELEMENTAL", silently tracking nothing. Names are for
-- DISPLAY only.
--
-- Values verified against the live ChrSpecialization DB2 export
-- (https://wago.tools/db2/ChrSpecialization). Pet specs, the per-class
-- "Initial" specs and Adventurer are deliberately absent -- the player can
-- never be in one while KickCD is tracking cooldowns.
Const.SPEC = {
    -- Death Knight
    BLOOD = 250, FROST_DK = 251, UNHOLY = 252,
    -- Demon Hunter (Devourer is new in 12.0 / Midnight)
    HAVOC = 577, VENGEANCE = 581, DEVOURER = 1480,
    -- Druid
    BALANCE = 102, FERAL = 103, GUARDIAN = 104, RESTORATION_DRUID = 105,
    -- Evoker
    DEVASTATION = 1467, PRESERVATION = 1468, AUGMENTATION = 1473,
    -- Hunter
    BEASTMASTERY = 253, MARKSMANSHIP = 254, SURVIVAL = 255,
    -- Mage
    ARCANE = 62, FIRE = 63, FROST_MAGE = 64,
    -- Monk
    BREWMASTER = 268, WINDWALKER = 269, MISTWEAVER = 270,
    -- Paladin
    HOLY_PALADIN = 65, PROTECTION_PALADIN = 66, RETRIBUTION = 70,
    -- Priest
    DISCIPLINE = 256, HOLY_PRIEST = 257, SHADOW = 258,
    -- Rogue
    ASSASSINATION = 259, OUTLAW = 260, SUBTLETY = 261,
    -- Shaman
    ELEMENTAL = 262, ENHANCEMENT = 263, RESTORATION_SHAMAN = 264,
    -- Warlock
    AFFLICTION = 265, DEMONOLOGY = 266, DESTRUCTION = 267,
    -- Warrior
    ARMS = 71, FURY = 72, PROTECTION_WARRIOR = 73,
}

-- specID -> English display token, for log lines, `/kcd spells list` output
-- and the v2 -> v3 spell-key migration. Deliberately the ENGLISH token even
-- on a localized client: it is what bug reports quote and what the slash
-- commands accept, so it must not drift with the user's locale.
--
-- Four spec names are shared across classes (Frost, Holy, Protection,
-- Restoration), so Const.SPEC has to disambiguate them with a class suffix.
-- The reverse map strips that suffix back off -- the specID already carries
-- the class, so "FROST" is unambiguous once you have the number.
Const.SPEC_TOKEN = {}
for token, specID in pairs(Const.SPEC) do
    Const.SPEC_TOKEN[specID] = (token:gsub("_[A-Z]+$", ""))
end
