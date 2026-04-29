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

    -- Slash commands. Both /kickcd and /kcd dispatch to OnSlashCommand,
    -- which prints the help index when called bare and routes to the
    -- COMMANDS / DEBUG_COMMANDS dispatch tables otherwise.
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
--
-- Two ordered tables drive the entire slash UX: COMMANDS for top-level
-- subcommands and DEBUG_COMMANDS for /kcd debug ... Each entry is
-- {name, description, fn}. The dispatcher (a) prints the help index when
-- invoked with no args, (b) looks up by name, (c) re-prints help on an
-- unknown name. Help text is generated from the same tables, so adding a
-- command means adding a single row.

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function p(self, ...)
    local fn = self.Util and self.Util.print or print
    fn(...)
end

-- Set db.profile.locked and notify IconGrid via the closed CONFIG_CHANGED
-- message (section "general"). IconGrid listens for that section and re-runs
-- ApplyLock to flip EnableMouse / RegisterForDrag.
local function setLocked(self, value)
    if not (self.db and self.db.profile) then
        return p(self, "|cff00ff00KickCD|r: db not initialized yet")
    end
    self.db.profile.locked = value and true or false
    self:SendMessage("KickCD_CONFIG_CHANGED", { section = "general" })
    p(self, "|cff00ff00KickCD|r: icon grid " .. (value and "locked" or "unlocked"))
end

-- Forward declarations so command tables and dispatchers can reference each
-- other without ordering pain.
local printHelp, runDebug

local COMMANDS = {
    {"help",   "List available commands",
        function(self) printHelp(self) end},
    {"config", "Open the settings panel",
        function(self) self:OpenSettings() end},
    {"lock",   "Lock the icon grid in place",
        function(self) setLocked(self, true) end},
    {"unlock", "Unlock the icon grid for dragging",
        function(self) setLocked(self, false) end},
    {"toggle", "Toggle the icon grid lock state",
        function(self)
            local cur = self.db and self.db.profile and self.db.profile.locked
            setLocked(self, not cur)
        end},
    {"debug",  "Debug subcommands — try `/kcd debug` for the list",
        function(self, rest) runDebug(self, rest) end},
}

local DEBUG_COMMANDS = {
    {"spells", "Print the watched spell list with cooldown state",
        function(self)
            local m = self:GetModule("Cooldowns", true)
            if m and m.DebugDump then m:DebugDump()
            else p(self, "Cooldowns module not loaded") end
        end},
    {"log",    "Toggle internal-message logging",
        function(self)
            self._debugLog = not self._debugLog
            p(self, "internal-message logging " .. (self._debugLog and "ON" or "OFF"))
        end},
}

local function findCommand(list, name)
    for _, entry in ipairs(list) do
        if entry[1] == name then return entry end
    end
end

function printHelp(self)
    p(self, "|cff00ff00KickCD|r v" .. KickCD.VERSION .. " — slash commands:")
    for _, entry in ipairs(COMMANDS) do
        p(self, ("  /kcd %-7s — %s"):format(entry[1], entry[2]))
    end
end

function runDebug(self, rest)
    if rest == nil or rest == "" then
        p(self, "|cff00ff00KickCD|r debug subcommands:")
        for _, entry in ipairs(DEBUG_COMMANDS) do
            p(self, ("  /kcd debug %-7s — %s"):format(entry[1], entry[2]))
        end
        return
    end
    local entry = findCommand(DEBUG_COMMANDS, rest)
    if entry then return entry[3](self) end
    p(self, "|cff00ff00KickCD|r: unknown debug subcommand '" .. rest .. "'")
    runDebug(self, "")
end

function KickCD:OnSlashCommand(input)
    local msg = trim(input):lower()
    if msg == "" then return printHelp(self) end

    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    -- Backward-compat alias.
    if cmd == "options" then cmd = "config" end

    local entry = findCommand(COMMANDS, cmd)
    if entry then return entry[3](self, rest) end

    p(self, "|cff00ff00KickCD|r: unknown command '" .. cmd .. "'")
    printHelp(self)
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
