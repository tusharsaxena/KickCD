std = "lua51"
max_line_length = false
codes = true
-- libs/ holds vendored code, including libs/LibKa0s/ whose upstream is the LibKa0s repo, so it is
-- linted there and not here. tests/_kit/ is the same fact one level down: it is a byte copy of the
-- library's testkit/, linted in LibKa0s as source, and linting the copy too would report every
-- finding twice while letting the copy drift green as the original went red -- the one state
-- tests/test_vendor_sync.lua exists to make impossible. Everything else under tests/ is ours and
-- is linted (lint-§1). Under docs/ only the FROZEN evidence bundles are excluded; a blanket docs/
-- exclude would silently drop any Lua a future doc directory carries out of the gate.
exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/_kit/", "docs/reviews/" }
ignore = {
  "212/self",       -- unused argument self
  "212/event",      -- unused argument event
  "211/addonName",  -- `local addonName, NS = ...` bootstrap header; addonName often unused
}
read_globals = {
  -- core Lua/WoW globals
  "_G", "LibStub", "CreateFrame", "GetTime", "GetTimePreciseSec",
  "UIParent", "GameTooltip", "GameFontNormal", "GameFontHighlight", "GameFontDisable",
  "STANDARD_TEXT_FONT",
  "hooksecurefunc", "securecallfunction", "issecretvalue",
  -- Perf bracket timer (performance-§2). The bracket CALL SITES are addon
  -- code and are linted, even though the lib under libs/ is not.
  "debugprofilestop",
  "C_Timer", "C_Spell", "C_SpecializationInfo", "C_AddOns",
  "GetLocale", "GetSpellInfo", "GetSpecialization", "GetSpecializationInfo",
  "InCombatLockdown", "PlaySound",
  -- units / spells / combat
  "UnitCastingInfo", "UnitChannelInfo", "UnitExists", "UnitCanAttack",
  "UnitClass", "UnitIsUnit", "UnitGUID", "UnitName", "UnitRace", "UnitIsDead",
  "IsLoggedIn",
  "IsPlayerSpell", "IsSpellKnown", "IsSpellKnownOrOverridesKnown",
  "GetSpecializationInfoForClassID", "GetNumSpecializationsForClassID",
  -- settings panel
  "Settings", "SettingsPanel",
  "DEFAULT_CHAT_FRAME", "UISpecialFrames", "UIDropDownMenu_AddButton",
  -- color / util
  "CreateColor", "CreateColorFromHexString", "WrapTextInColorCode",
  "CopyTable", "wipe", "tContains", "tinsert", "tremove", "strsplit", "strtrim", "strjoin",
  "date", "time",
  -- fonts / textures used in DebugLog / panels
  "BackdropTemplateMixin", "Mixin", "CreateFromMixins",
  "NORMAL_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "RED_FONT_COLOR", "GREEN_FONT_COLOR",
  -- class / spell / cooldown data APIs
  "C_CooldownViewer", "Enum", "GetNumClasses", "GetClassInfo",
  "LOCALIZED_CLASS_NAMES_MALE", "RAID_CLASS_COLORS", "CreateAtlasMarkup",
  -- static popups
  "StaticPopup_Show",
}
globals = {
  "KickCDDB",           -- SavedVariables write target
  "StaticPopupDialogs", -- addon registers named popups by adding fields to this table
  "KickCDPerfDB",       -- LibKa0s-Perf capture ring; a SECOND top-level SV global,
                        -- deliberately outside the AceDB tree so "copy profile" does
                        -- not clone it and "reset profile" does not wipe it
}

-- The harness publishes its exposed table under a per-repo global, written at tests/run.lua:217
-- and read back by every suite file. It is declared HERE, in a files["tests/"] stanza, rather
-- than in the top-level `read_globals` above, and the difference is not cosmetic: a name granted
-- at the top level is granted to core/, modules/ and settings/ as much as to a suite, and a
-- shipped file reaching for the test harness is exactly what this gate exists to refuse.
-- `globals` rather than `read_globals` because tests/run.lua is the writer, and spelt as a _G.
-- field because that is how run.lua writes it and every suite reads it.
--
-- The two SavedVariables tables are NOT named here. No suite in this repo touches either through
-- _G: the fixtures hand each instance its own inst.mocks.KickCDDB, and test_perfsetup.lua asserts
-- on KickCDPerfDB as a STRING inside the TOC. Declaring them would grant a permission nothing
-- uses, which is how a stanza stops describing the tree it guards.
files["tests/"] = {
  globals = { "_G.KICKCD_TEST" },
}
