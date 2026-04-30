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
    -- live AceDB object — a contract relied on by every module.
    if self.Database and self.Database.Init then
        self.Database:Init()
    end

    -- Restore the persisted debug-log preference. Both the slash command and
    -- the Settings checkbox keep db.profile.debugLog in sync; this seeds the
    -- runtime flag from whatever the profile was last saved with.
    if self.db and self.db.profile then
        self._debugLog = self.db.profile.debugLog and true or false
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
local printHelp, runDebug, listSettings, getSetting, setSetting

local COMMANDS = {
    {"help",   "List available commands",
        function(self) printHelp(self) end},
    {"config", "Open the settings panel",
        function(self)
            if InCombatLockdown and InCombatLockdown() then
                p(self, "|cff00ff00KickCD|r: " ..
                    (self.L and self.L["Cannot open settings during combat."]
                     or "Cannot open settings during combat."))
                return
            end
            self:OpenSettings()
        end},
    {"lock",   "Lock the icon grid in place",
        function(self) setLocked(self, true) end},
    {"unlock", "Unlock the icon grid for dragging",
        function(self) setLocked(self, false) end},
    {"toggle", "Toggle the icon grid lock state",
        function(self)
            local cur = self.db and self.db.profile and self.db.profile.locked
            setLocked(self, not cur)
        end},
    {"list",   "List every setting and its current value",
        function(self) listSettings(self) end},
    {"get",    "Print a setting's current value — `/kcd get <path>`",
        function(self, rest) getSetting(self, rest) end},
    {"set",    "Set a setting — `/kcd set <path> <value>` (try /kcd list)",
        function(self, rest) setSetting(self, rest) end},
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
            -- Persist + notify the settings checkbox so /kcd debug log and
            -- the General > Debug toggle stay in sync.
            if self.db and self.db.profile then
                self.db.profile.debugLog = self._debugLog
                self:SendMessage("KickCD_CONFIG_CHANGED", { section = "general" })
            end
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
    -- Debug subcommands are all-lowercase identifiers; lowercase the
    -- first token so callers don't have to (now that OnSlashCommand
    -- preserves case in `rest` for schema paths).
    local sub = (rest or ""):match("^(%S*)") or ""
    sub = sub:lower()
    if sub == "" then
        p(self, "|cff00ff00KickCD|r debug subcommands:")
        for _, entry in ipairs(DEBUG_COMMANDS) do
            p(self, ("  /kcd debug %-7s — %s"):format(entry[1], entry[2]))
        end
        return
    end
    local entry = findCommand(DEBUG_COMMANDS, sub)
    if entry then return entry[3](self) end
    p(self, "|cff00ff00KickCD|r: unknown debug subcommand '" .. sub .. "'")
    runDebug(self, "")
end

function KickCD:OnSlashCommand(input)
    local raw = trim(input)
    if raw == "" then return printHelp(self) end

    -- Lowercase only the command name; preserve case in the rest so
    -- schema paths like `icons.primarySize` survive `/kcd set ...`.
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd  = (cmd or ""):lower()
    rest = rest or ""
    -- Backward-compat alias.
    if cmd == "options" then cmd = "config" end

    local entry = findCommand(COMMANDS, cmd)
    if entry then return entry[3](self, rest) end

    p(self, "|cff00ff00KickCD|r: unknown command '" .. cmd .. "'")
    printHelp(self)
end

-- ---------------------------------------------------------------------------
-- Schema-driven /kcd list|get|set
-- ---------------------------------------------------------------------------
--
-- Every entry in KickCD.Settings.Schema (built up by settings/General.lua,
-- settings/Icons.lua and any future schema-driven panel) automatically
-- gets `/kcd get <path>` and `/kcd set <path> <value>` for free, plus
-- shows up in `/kcd list`. Adding a new option = one schema row; the
-- slash UI and the panel widgets are wired from the same source.

local function helpers()
    return KickCD.Settings and KickCD.Settings.Helpers
end

local function formatValue(def, v)
    if v == nil then return "nil" end
    if def.type == "color" and type(v) == "table" then
        return ("{%.2f, %.2f, %.2f, %.2f}"):format(
            v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 1)
    end
    if def.type == "number" then
        if def.fmt then return def.fmt:format(v) end
        return tostring(v)
    end
    return tostring(v)
end

local function dropdownAllowed(def)
    local values = type(def.values) == "function" and def.values() or def.values or {}
    local out = {}
    for i, item in ipairs(values) do out[i] = tostring(item.value) end
    return out
end

-- Apply a typed value from a string (slash-command tail).
local function applyFromText(self, def, text)
    local H = helpers()
    if not H then return p(self, "Settings layer not ready yet") end

    local args = {}
    for w in (text or ""):gmatch("%S+") do args[#args + 1] = w end

    local L = self.L or {}
    local fail = function(reason)
        p(self, (L["Invalid value for %s"] or "Invalid value for %s"):format(def.path))
        if reason and reason ~= "" then p(self, "  " .. reason) end
    end

    local newValue
    if def.type == "bool" then
        local s = (args[1] or ""):lower()
        if s == "true" or s == "1" or s == "on"  or s == "yes" then newValue = true
        elseif s == "false" or s == "0" or s == "off" or s == "no"  then newValue = false
        else return fail("expected true/false/on/off/1/0") end
    elseif def.type == "number" then
        local n = tonumber(args[1])
        if not n then return fail("expected a number") end
        if def.min then n = math.max(def.min, n) end
        if def.max then n = math.min(def.max, n) end
        newValue = n
    elseif def.type == "string" then
        local v = args[1]
        if not v then return fail("expected a value") end
        local allowed = dropdownAllowed(def)
        local ok = false
        for _, a in ipairs(allowed) do if a == v then ok = true; break end end
        if not ok then
            return fail((L["Allowed values: %s"] or "Allowed values: %s")
                :format(table.concat(allowed, ", ")))
        end
        newValue = v
    elseif def.type == "color" then
        local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
        local a = tonumber(args[4]) or 1
        if not (r and g and b) then return fail("expected: r g b [a] (each 0-1)") end
        newValue = { r, g, b, a }
    else
        return fail("unknown setting type '" .. tostring(def.type) .. "'")
    end

    H.Set(def.path, def.section, newValue)
    if def.onChange then
        local ok, err = pcall(def.onChange, newValue)
        if not ok then p(self, "onChange failed: " .. tostring(err)) end
    end
    if H.RefreshAllPanels then H.RefreshAllPanels() end

    p(self, ("|cff00ff00KickCD|r: %s = %s")
        :format(def.path, formatValue(def, H.Get(def.path))))
end

function listSettings(self)
    local H = helpers()
    if not (H and KickCD.Settings and KickCD.Settings.Schema) then
        return p(self, "Settings layer not ready yet")
    end
    p(self, self.L and self.L["Available settings:"] or "Available settings:")
    -- Group by panel for readable output.
    local byPanel = {}
    for _, def in ipairs(KickCD.Settings.Schema) do
        local key = def.panel or "?"
        byPanel[key] = byPanel[key] or {}
        table.insert(byPanel[key], def)
    end
    for _, key in ipairs({ "general", "icons", "castbar", "spells", "profiles" }) do
        local list = byPanel[key]
        if list then
            p(self, "  [" .. key .. "]")
            for _, def in ipairs(list) do
                p(self, ("    %s = %s"):format(def.path, formatValue(def, H.Get(def.path))))
            end
        end
    end
end

function getSetting(self, rest)
    local H = helpers()
    if not H then return p(self, "Settings layer not ready yet") end
    local path = (rest or ""):match("^(%S+)")
    if not path or path == "" then
        return p(self, self.L and self.L["Usage: /kcd get <path>"]
            or "Usage: /kcd get <path>")
    end
    local def = H.FindSchema(path)
    if not def then
        return p(self, (self.L and self.L["Setting not found: %s"]
            or "Setting not found: %s"):format(path))
    end
    p(self, ("%s = %s"):format(def.path, formatValue(def, H.Get(def.path))))
end

function setSetting(self, rest)
    local H = helpers()
    if not H then return p(self, "Settings layer not ready yet") end
    local path, value = (rest or ""):match("^(%S+)%s*(.*)$")
    if not path or path == "" then
        return p(self, self.L and self.L["Usage: /kcd set <path> <value>"]
            or "Usage: /kcd set <path> <value>")
    end
    local def = H.FindSchema(path)
    if not def then
        return p(self, (self.L and self.L["Setting not found: %s"]
            or "Setting not found: %s"):format(path))
    end
    applyFromText(self, def, value or "")
end

-- ---------------------------------------------------------------------------
-- Settings entry point
-- ---------------------------------------------------------------------------

--- Open the Blizzard Settings panel to KickCD's category.
-- Settings layer is set up by settings/Panel.lua, which assigns
-- KickCD.SettingsCategoryID. If that hasn't run yet we print rather than
-- error so this is safe to call at any time after PLAYER_LOGIN.
--
-- 12.0 hides a parent category's own widgets whenever the category has
-- subcategories. The Ka0s KickCD parent is therefore empty; we open the
-- General subcategory directly so users land on real controls. The parent
-- ID is the fallback when General hasn't registered yet.
-- @param input slash-command tail (ignored for v0.1)
function KickCD:OpenSettings(input)
    local p = self.Util and self.Util.print or print
    if Settings and Settings.OpenToCategory then
        local target
        local generalSub = self.Settings and self.Settings.sub
                           and self.Settings.sub.general
        if generalSub and generalSub.GetID then
            target = generalSub:GetID()
        end
        target = target or self.SettingsCategoryID
        if target then
            Settings.OpenToCategory(target)
            return
        end
    end
    p("Settings not yet registered")
end
