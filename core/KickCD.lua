-- core/KickCD.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.1
--
-- AceAddon bootstrap: turns the plain `KickCD` table that Compat / Util /
-- Database have been hanging fields on into the actual AceAddon object,
-- preserving every prior field. Registers slash commands and exposes
-- KickCD:OpenSettings().

-- ---------------------------------------------------------------------------
-- Promote the bootstrap table to an AceAddon
-- ---------------------------------------------------------------------------
--
-- Earlier core/* files have written to a plain `_G.KickCD` table. AceAddon
-- accepts a pre-existing object as its first argument and adds AceAddon /
-- mixin methods directly onto it, so passing _G.KickCD here gives us a
-- single object that has both KickCD.Compat / KickCD.Util / KickCD.Database
-- (set earlier) AND KickCD:RegisterChatCommand / SendMessage / NewModule /
-- ... (set by the mixins). The global rebinding makes downstream code that
-- looks up `KickCD` from _G see the mixed-in version.

local existing = _G.KickCD or {}

local addon = LibStub("AceAddon-3.0"):NewAddon(
    existing,
    "KickCD",
    "AceConsole-3.0",
    "AceEvent-3.0")

-- AceAddon returns the same table we passed in, with mixin methods stamped
-- on it. Re-bind the global so anyone reading _G.KickCD sees the addon
-- object, not whatever copy they had cached.
_G.KickCD = addon
local KickCD = addon

-- Public version stamp.
KickCD.VERSION = "0.1.0"

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function KickCD:OnInitialize()
    -- Database:Init() builds the AceDB instance, runs migrations, and seeds
    -- spells from defaults/Spells.lua. After this returns, KickCD.db is the
    -- live AceDB object — a contract relied on by every module (see
    -- EXECUTION_PLAN §9 #2).
    if self.Database and self.Database.Init then
        self.Database:Init()
    end

    -- Slash commands. Both /kickcd and /kcd open the settings panel by
    -- default; subcommands route to OnSlashCommand for diagnostics.
    self:RegisterChatCommand("kickcd", "OnSlashCommand")
    self:RegisterChatCommand("kcd",    "OnSlashCommand")
end

function KickCD:OnEnable()
    -- Modules register themselves via NewModule(...) and AceAddon
    -- auto-enables them. Nothing to do here for v0.1.
end

-- ---------------------------------------------------------------------------
-- Slash command dispatch
-- ---------------------------------------------------------------------------

local DEBUG_HELP = {
    "|cff00ff00KickCD|r debug subcommands:",
    "  /kickcd debug spells  — print active spell list + cooldown state",
    "  /kickcd debug target  — print Tracker's view of the current target",
    "  /kickcd debug log     — toggle internal-message logging",
}

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function KickCD:OnSlashCommand(input)
    local msg = trim(input):lower()

    if msg == "" or msg == "config" or msg == "options" then
        return self:OpenSettings(msg)
    end

    if msg == "test" then
        if self.ToggleTestMode then
            self:ToggleTestMode()
        else
            (self.Util and self.Util.print or print)("test mode module not loaded")
        end
        return
    end

    -- /kickcd debug ... — split out the subcommand.
    local sub = msg:match("^debug%s+(%S+)") or (msg == "debug" and "" or nil)
    if sub then
        return self:OnDebugCommand(sub)
    end

    -- Unknown — print usage.
    local p = self.Util and self.Util.print or print
    p("|cff00ff00KickCD|r v" .. KickCD.VERSION
        .. " — /kickcd [config|test|debug spells|debug target|debug log]")
end

-- The actual debug helpers are implemented by the modules that own the data
-- (Cooldowns owns spell state, Tracker owns target state). We invoke a
-- conventional Debug() method on each module if it exists, so this file
-- doesn't have to know module internals. Modules that haven't implemented
-- Debug() simply get a "not available" message.
function KickCD:OnDebugCommand(sub)
    local p = self.Util and self.Util.print or print

    if sub == "" then
        for _, line in ipairs(DEBUG_HELP) do p(line) end
        return
    end

    if sub == "spells" then
        local m = self:GetModule("Cooldowns", true)
        if m and m.DebugDump then m:DebugDump()
        else p("Cooldowns module not loaded") end
        return
    end

    if sub == "target" then
        local m = self:GetModule("Tracker", true)
        if m and m.DebugDump then m:DebugDump()
        else p("Tracker module not loaded") end
        return
    end

    if sub == "log" then
        self._debugLog = not self._debugLog
        p("internal-message logging " .. (self._debugLog and "ON" or "OFF"))
        return
    end

    p("unknown debug subcommand: " .. sub)
    for _, line in ipairs(DEBUG_HELP) do p(line) end
end

-- ---------------------------------------------------------------------------
-- Settings entry point
-- ---------------------------------------------------------------------------

--- Open the Blizzard Settings panel to KickCD's category.
-- Settings layer is set up by settings/Panel.lua, which assigns
-- KickCD.SettingsCategoryID. If that hasn't run yet we print rather than
-- error so this is safe to call at any time after PLAYER_LOGIN.
-- @param input slash-command tail (ignored for v0.1)
function KickCD:OpenSettings(input)
    local p = self.Util and self.Util.print or print
    if Settings and Settings.OpenToCategory and self.SettingsCategoryID then
        Settings.OpenToCategory(self.SettingsCategoryID)
        return
    end
    p("Settings not yet registered")
end
