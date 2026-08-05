std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/", "docs/audits/", "_dev/", "tests/", "docs/reviews/" }
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
