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

-- NO TOP-LEVEL `ignore`, and none is coming back (lint-§1, `M4-11`). This file carried
-- `ignore = { "212/self", "212/event", "211/addonName" }` until `M4c-06`. Every entry was already
-- in the `<code>/<variable>` form, which reads like the narrow spelling and is not: at the TOP
-- level it still reaches all 93 files, so those three names were silenced in every file that has
-- no business producing them as much as in the handful that earn them. That is exactly what the
-- rule calls an ignore that silences the wall -- it reads as coverage and provides none.
--
-- Removing the three lines took `luacheck .` from 0/0 to SIXTY-ONE warnings, and THIRTY-TWO of
-- those were defects rather than conventions, fixed at source by `M4c-06` rather than moved into
-- a narrower suppression:
--
--   * Twenty-nine files opened `local addonName, NS = ...` over a folder name they never read.
--     Five files in this addon do read it -- CoreSetup, EnvSetup, MediaSetup, DebugLogSetup and
--     PerfSetup, each handing it to a vendored LibKa0s payload that cannot infer which folder it
--     was copied into. The other twenty-nine had the line because it was copied, and they now
--     open `local _, NS = ...`, which is how core/PoolSetup.lua already spelt it.
--
--   * Two receivers in the test tree were named and never read: the mock module method in
--     tests/test_util.lua and `t.SendMessage` in tests/wow_mock.lua. Both are spelt `_` now,
--     which keeps the arity the mocked signature owes and stops claiming a sender is consulted.
--
--   * One dead function. `settings/Slash.lua` carried a `NS.Slash:PrintHelp()` forwarder nothing
--     called -- core/KickCD.lua reaches `NS.Slash.cli:PrintHelp()` directly behind the same
--     guard -- and the blanket hid it, because with the receiver unreported it read like the
--     third member of a trio. Deleted.
--
-- `212/event` is worth its own line: it matched NOTHING in this tree. It was carried for a
-- convention no file here actually produces, which is the other half of what a blanket costs --
-- nobody can tell a live suppression from a stale one while it is switched on everywhere.
--
-- The twenty-nine that remain are all `212/self`, and they are answered by the `files[...]`
-- stanzas at the foot of this file, one per file, each with the calling convention that forces
-- the receiver written beside it.

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

-- ---------------------------------------------------------------------------
-- The narrowed 212s (lint-§1, `M4c-06`)
-- ---------------------------------------------------------------------------
--
-- Every stanza below names ONE file and the code AND the variable, in luacheck's
-- `<code>/<variable>` form. That is the whole difference from the blanket it replaced: an
-- argument that falls out of use under any other name, in any of these nine files or in any of
-- the other 84, still reports.
--
-- Measured rather than assumed, and measured for the RIGHT thing. A dead argument under a new
-- name always reported here -- the old entries were already `<code>/<variable>`, so adding a
-- `deadArg` to `Castbar:GetCastbarFrame` goes red under both configs, and quoting that as the
-- proof would have proved nothing. What the old config swallowed is the NAME it listed, in
-- every file: `function NS.Util:DeadProbe()` appended to core/Util.lua reports
-- `core/Util.lua:429:17: (W212) unused argument 'self'` under this config and reports nothing
-- under the old one. The twenty-nine `addonName` headers are the same fact at scale -- they
-- were there all along, under a green 0/0.
--
-- Each entry is a receiver a CALLING CONVENTION forces on a body with no use for it, which is the
-- only shape that earns a stanza. Anything else -- an argument or a function this addon chose to
-- keep and then never read -- is dead code, and `M4c-06` deleted or renamed thirty-two of those
-- rather than listing them here.

-- The two version-gated migrators, `Database:MigrateColorShape` and `Database:MigrateFontFlags`.
-- Both read the AceDB instance they are handed and nothing off the Database table, but both are
-- reached with the colon -- from the `migrations` scaffold at core/Database.lua:527-528 and from
-- tests/test_database.lua -- and they sit in a family with FoldLegacyUnits, BackfillLabelStyle
-- and MigrateSpecKeys, which do read it. A migrator family whose signatures disagree is worse
-- than two unused receivers.
files["core/Database.lua"] = {
  ignore = { "212/self" },
}

-- AceAddon calls `NS:OnEnable()` on the addon object at PLAYER_LOGIN. The body builds the options
-- surface through `NS.CreateOptionsPanel`, which is a file-local upvalue, not a member.
files["core/KickCD.lua"] = {
  ignore = { "212/self" },
}

-- The three per-unit modules. Each is an AceAddon module object, and every method listed here is
-- reached as `Module:Method(...)` -- from inside the module through `self:`, from the sibling
-- modules across files (UnitLabel asks IconGrid for `GetGridFrame`, Castbar asks it for
-- `GetPrimaryIcon`), and from the suites. The per-unit state they read lives in each file's own
-- `instances` upvalue rather than on the module table, so the receiver arrives unread. Dropping it
-- would mean rewriting every call site to the dot form and would put the module surface out of
-- step with the sibling methods that do read `self`.
--
-- `IconGrid:OnSpellState` is the sharper case: it is registered BY NAME at modules/IconGrid.lua
-- :769 (`self:RegisterMessage("Ka0s_KickCD_SPELL_STATE", "OnSpellState")`), and AceEvent-3.0
-- invokes a name-registered handler as `self[method](self, ...)`. The receiver is not this
-- addon's choice at all.
files["modules/Castbar.lua"]         = { ignore = { "212/self" } }
files["modules/Cooldowns.lua"]       = { ignore = { "212/self" } }
files["modules/IconGrid.lua"]        = { ignore = { "212/self" } }
files["modules/UnitLabel.lua"]       = { ignore = { "212/self" } }

-- `IconGrid:_RegisterTextIcon` / `_UnregisterTextIcon` keep the text-icon registry in
-- modules/IconGrid.lua's own upvalue, so neither reads the module. They are still methods because
-- the button handlers at modules/IconGrid_Render.lua:360 and :364 have the module in scope and
-- nothing else, and modules/IconGrid.lua:272 calls the unregister half through `self:`.
files["modules/IconGrid_Render.lua"] = { ignore = { "212/self" } }

-- Three receivers the settings layer does not choose. `SlashLib:New(d)` at settings/Slash.lua:223
-- is the degradation stub standing in for `LibKa0s-Slash-1.0`'s constructor, so it takes the
-- receiver the real one takes or the live and degraded paths stop being callable the same way --
-- which is the single fact tests/test_surface_parity.lua exists to hold. The two `NS.Slash`
-- forwarders below it are method-sugar on the host table, reached with the colon from
-- settings/Panel.lua:492 and core/KickCD.lua:288; they forward to `NS.Slash.cli`, a file-local,
-- not to anything on `self`.
files["settings/Slash.lua"] = {
  ignore = { "212/self" },
}

-- The spells page. `GetSelection`, `SeedSelectionToPlayer` and `RefreshRows` all work on the
-- panel state held in settings/Spells.lua's own upvalues, but every call site uses the colon --
-- `self:RefreshRows()` from inside the file, `Spells:RefreshRows()` from its own refresh hooks,
-- and `p:GetSelection()` from tests/test_settings_spells*.lua, which reach the page through
-- `NS.Settings.SpellsPanel` and have no other handle on it.
files["settings/Spells.lua"] = {
  ignore = { "212/self" },
}

