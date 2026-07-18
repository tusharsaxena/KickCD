-- core/KickCD.lua
-- See docs/module-map.md.
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

local addonName, NS = ...

-- AceAddon stamps its mixin methods onto NS in place. NS is the private
-- namespace table WoW passes as the second vararg to every file, and the
-- core/* files loaded earlier have already hung Compat / Util / Database /
-- Const / State onto this same NS. After this call NS IS the addon object —
-- there is NO _G.KickCD rebind; the namespace stays private (§4.1).
local addon = LibStub("AceAddon-3.0"):NewAddon(
    NS,
    "KickCD",
    "AceConsole-3.0",
    "AceEvent-3.0")
NS.addon = addon

-- Public version stamp.
NS.VERSION = "1.2.0"

-- Fresh AceEvent-embedded table for a message-bus / event RECEIVER (§4.4).
-- Any consumer that is NOT itself an AceAddon module (which already gets its
-- own AceEvent embed) MUST own a private target from this factory rather than
-- registering on the shared addon object: CallbackHandler keys callbacks by
-- (message, target), so two receivers of one message on the SAME object would
-- silently clobber — only the last registrant would fire (AP-32 / KCD-09).
function NS.NewBusTarget()
    local AceEvent = LibStub("AceEvent-3.0", true)
    if not AceEvent then return nil end
    local t = {}
    AceEvent:Embed(t)
    return t
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function NS:OnInitialize()
    -- Database:Init() builds the AceDB instance and seeds spells from
    -- defaults/Spells.lua. After this returns, KickCD.db is the live
    -- AceDB object — a contract relied on by every module.
    if self.Database and self.Database.Init then
        self.Database:Init()
    end

    -- Debug logging is a session-only flag (KickCD.State.debug) seeded off on
    -- every load — it is NEVER read back from SavedVariables (§12.5). No
    -- seeding here on purpose.

    -- Slash commands. Both /kickcd and /kcd dispatch to OnSlashCommand,
    -- which prints the help index when called bare and routes to the
    -- COMMANDS / DEBUG_COMMANDS dispatch tables otherwise.
    self:RegisterChatCommand("kickcd", "OnSlashCommand")
    self:RegisterChatCommand("kcd",    "OnSlashCommand")
end

function NS:OnEnable()
    -- Modules register themselves via NewModule(...) and AceAddon
    -- auto-enables them. Nothing to do here.
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

-- Addon version for the `version` verb and the help header (slash-commands-§3).
-- Prefer the TOC manifest so the reported version can't drift from the packaged
-- build; fall back to the in-code NS.VERSION stamp when the metadata API is
-- unavailable (older clients, or the headless test harness). 12.0 exposes the
-- reader under C_AddOns; the bare _G.GetAddOnMetadata is deprecated, so we don't
-- touch it (§4.1 no-deprecated-globals).
local function addonVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = get and get(addonName, "Version")
    if type(v) == "string" and v ~= "" then return v end
    return NS.VERSION
end

-- Set db.profile.locked through the schema's write+notify+refresh path
-- (Helpers.SetAndRefresh). That path mirrors what `/kcd set locked
-- true` and the General > "Lock frame" checkbox do, so an open
-- settings panel re-syncs and any future onChange wired onto the
-- `locked` schema row fires here too. Falls back to a direct write
-- only if the settings layer isn't loaded yet (early-boot edge).
local function setLocked(self, value)
    if not (self.db and self.db.profile) then
        return p(self, "db not initialized yet")
    end
    local v = value and true or false
    local H = self.Settings and self.Settings.Helpers
    if not (H and H.SetAndRefresh and H.SetAndRefresh("locked", v)) then
        self.db.profile.locked = v
        self:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })
    end
    p(self, "icon grid " .. (v and "locked" or "unlocked"))
end

-- Forward declarations so command tables and dispatchers can reference each
-- other without ordering pain.
local printHelp, runDebug, listSettings, getSetting, setSetting
local runReset, runResetAll, runResetPosition, runSpells

-- Published on KickCD as KickCD.COMMANDS at the bottom of this block so
-- the settings panel's main page can render the same list /kcd help
-- prints. Single-source-of-truth: a new entry surfaces in chat output AND
-- in the Settings UI without further plumbing.
local COMMANDS = {
    {"help",          "List available commands",
        function(self) printHelp(self) end},
    {"version",       "Print the addon version",
        function(self) p(self, "v" .. addonVersion()) end},
    {"config",        "Open the settings panel",
        function(self) self:OpenSettings() end},
    {"lock",          "Lock the icon grid in place",
        function(self) setLocked(self, true) end},
    {"unlock",        "Unlock the icon grid for dragging",
        function(self) setLocked(self, false) end},
    {"toggle",        "Toggle the icon grid lock state",
        function(self)
            local cur = self.db and self.db.profile and self.db.profile.locked
            setLocked(self, not cur)
        end},
    {"list",          "List every setting and its current value",
        function(self) listSettings(self) end},
    {"get",           "Print a setting's current value — `/kcd get <path>`",
        function(self, rest) getSetting(self, rest) end},
    {"set",           "Set a setting — `/kcd set <path> <value>` (try /kcd list)",
        function(self, rest) setSetting(self, rest) end},
    {"reset",         "Reset a panel to defaults. `/kcd reset spells` rebuilds EVERY spec's list — for one spec, use `/kcd spells reset`.",
        function(self, rest) runReset(self, rest) end},
    {"resetall",      "Reset every schema-driven panel AND every spec's spell list to defaults",
        function(self) runResetAll(self) end},
    {"resetposition", "Restore the icon grid to its default screen position",
        function(self) runResetPosition(self) end},
    {"spells",        "Spell-list editor — try `/kcd spells` for the list",
        function(self, rest) runSpells(self, rest) end},
    {"debug",         "Debug subcommands — try `/kcd debug` for the list",
        function(self, rest) runDebug(self, rest) end},
}
NS.COMMANDS = COMMANDS

local DEBUG_COMMANDS = {
    {"spells", "Print the watched spell list with cooldown state",
        function(self)
            local m = self:GetModule("Cooldowns", true)
            if m and m.DebugDump then m:DebugDump()
            else p(self, "Cooldowns module not loaded") end
        end},
    {"castbar", "Print the current target cast bar state",
        function(self)
            local m = self:GetModule("Castbar", true)
            if m and m.DebugDump then m:DebugDump()
            else p(self, "Castbar module not loaded") end
        end},
    {"interrupt", "Dump the target's UnitCastingInfo / UnitChannelInfo positions (type + secret-tainted flag) plus what the visibility logic decides — use to diagnose 12.0 secret-value handling",
        function(self)
            if NS.Compat and NS.Compat.DebugInterrupt then
                NS.Compat.DebugInterrupt("target")
            else
                p(self, "Compat.DebugInterrupt unavailable")
            end
        end},
    {"window", "Toggle the debug console window",
        function(self)
            if self.DebugLog then self.DebugLog:Toggle()
            else p(self, "DebugLog module not loaded") end
        end},
    {"on",     "Enable debug logging (session only)",
        function(self)
            if self.DebugLog then self.DebugLog:SetEnabled(true)
            else p(self, "DebugLog module not loaded") end
        end},
    {"off",    "Disable debug logging",
        function(self)
            if self.DebugLog then self.DebugLog:SetEnabled(false)
            else p(self, "DebugLog module not loaded") end
        end},
    {"toggle", "Toggle debug logging (session only)",
        function(self)
            if self.DebugLog then
                self.DebugLog:SetEnabled(not (self.State and self.State.debug))
            else p(self, "DebugLog module not loaded") end
        end},
}

local function findCommand(list, name)
    for _, entry in ipairs(list) do
        if entry[1] == name then return entry end
    end
end

function printHelp(self)
    p(self, "v" .. addonVersion() .. " slash commands (|cffffff00/kickcd|r is an alias for |cffffff00/kcd|r)")
    for _, entry in ipairs(COMMANDS) do
        p(self, ("  |cffffff00/kcd %s|r — |cffffffff%s|r"):format(entry[1], entry[2]))
    end
end

function runDebug(self, rest)
    -- Debug subcommands are all-lowercase identifiers; lowercase the
    -- first token so callers don't have to (now that OnSlashCommand
    -- preserves case in `rest` for schema paths).
    local sub = (rest or ""):match("^(%S*)") or ""
    sub = sub:lower()
    if sub == "" then
        -- Bare `/kcd debug` toggles the console window (§12.5); the flag is
        -- untouched. Print the verb list alongside so it stays discoverable.
        if self.DebugLog then self.DebugLog:Toggle() end
        p(self, "debug subcommands")
        for _, entry in ipairs(DEBUG_COMMANDS) do
            p(self, ("  |cffffff00/kcd debug %s|r — |cffffffff%s|r"):format(entry[1], entry[2]))
        end
        return
    end
    local entry = findCommand(DEBUG_COMMANDS, sub)
    if entry then return entry[3](self) end
    p(self, "unknown debug subcommand '" .. sub .. "'")
    runDebug(self, "")
end

function NS:OnSlashCommand(input)
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

    p(self, "unknown command '" .. cmd .. "'")
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
    return NS.Settings and NS.Settings.Helpers
end

-- Single shared value formatter for /kcd list|get|set (slash-commands §5):
-- type-aware, unit-annotated (via the schema row's `fmt`), never hand-formatted
-- per call site. list and get/set both route through this so their value
-- strings can never diverge.
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
    if def.type == "bool" then
        return v and "true" or "false"
    end
    if def.type == "string" and (v == nil or v == "") then
        return "(none)"
    end
    return tostring(v)
end

-- Shared `path = value` formatter for schema output (slash-commands §5): key
-- gold (ffff00), value white (ffffff), ` = ` separator uncoloured. Reused by
-- the /kcd list rows and the /kcd get | set single-line echo so the colouring
-- can never drift between them. No trailing colon (house style).
local function FormatKV(path, valueStr)
    return ("|cffffff00%s|r = |cffffffff%s|r"):format(path, valueStr)
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
            local msg = (L["Allowed values: %s"] or "Allowed values: %s")
                :format(table.concat(allowed, ", "))
            -- def.valueGate (optional) names a sibling setting whose
            -- current value gates the option list returned by def.values.
            -- Surfacing it tells a confused user *why* their value is
            -- rejected — e.g. growDirection's UP/DOWN vs RIGHT/LEFT
            -- depends on castbar.orientation.
            --
            -- We append:
            --   * The gate's current value (so the user understands
            --     which side of the gate they're on right now).
            --   * For every OTHER value the gate could take, the
            --     option list this dropdown would expose under that
            --     gate value. Probing relies on the dropdown's
            --     `values` function reading the live profile, so we
            --     swap the gate's profile slot to each candidate
            --     value, re-query, restore, and tabulate. The swap
            --     is purely transient (single call between mutate +
            --     restore; no message bus dispatch).
            if def.valueGate then
                local H = helpers()
                local gateVal = H and H.Get and H.Get(def.valueGate)
                msg = msg .. (" (depends on %s = %s)")
                    :format(def.valueGate, tostring(gateVal))
                local gateDef = H and H.FindSchema and H.FindSchema(def.valueGate)
                if gateDef and H and H.Get and H.Set then
                    local gateValues = type(gateDef.values) == "function"
                        and gateDef.values() or gateDef.values
                    if type(gateValues) == "table" then
                        local hints = {}
                        for _, item in ipairs(gateValues) do
                            local candidate = item.value
                            if candidate ~= nil and candidate ~= gateVal then
                                local profile = self.db and self.db.profile
                                local parent, key = H.Resolve(def.valueGate)
                                if parent and key and profile then
                                    parent[key] = candidate
                                    local altList = dropdownAllowed(def)
                                    parent[key] = gateVal
                                    if #altList > 0 then
                                        hints[#hints + 1] = ("flip %s to %s for %s")
                                            :format(def.valueGate, tostring(candidate),
                                                    table.concat(altList, "/"))
                                    end
                                end
                            end
                        end
                        if #hints > 0 then
                            msg = msg .. "; " .. table.concat(hints, "; ")
                        end
                    end
                end
            end
            return fail(msg)
        end
        newValue = v
    elseif def.type == "color" then
        local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
        local a = tonumber(args[4]) or 1
        if not (r and g and b) then return fail("expected: r g b [a] (each 0-1)") end
        -- Clamp each channel to [0, 1]. Without this, `/kcd set
        -- icons.cooldownTint 5 5 5 5` writes garbage that the texture
        -- driver renders as overbright nonsense and the color picker
        -- can't represent.
        local function clamp01(n) return math.max(0, math.min(1, n)) end
        newValue = { clamp01(r), clamp01(g), clamp01(b), clamp01(a) }
    else
        return fail("unknown setting type '" .. tostring(def.type) .. "'")
    end

    H.Set(def.path, def.section, newValue)
    if def.onChange then
        local ok, err = pcall(def.onChange, newValue)
        if not ok then p(self, "onChange failed: " .. tostring(err)) end
    end
    if H.RefreshAllPanels then H.RefreshAllPanels() end

    -- Echo the STORED value (post-clamp/coerce) via the shared key=value
    -- formatter, so /kcd set reads identically to /kcd get and /kcd list.
    p(self, FormatKV(def.path, formatValue(def, H.Get(def.path))))
end

function listSettings(self)
    local H = helpers()
    if not (H and NS.Settings and NS.Settings.Schema) then
        return p(self, "Settings layer not ready yet")
    end
    -- Colour scheme (slash-commands §5): header green (33ff99), [page] group
    -- headers azure (3399ff), key/value via FormatKV. No trailing colons.
    p(self, "|cff33ff99" .. (self.L and self.L["Available settings"] or "Available settings") .. "|r")
    -- Group by panel for readable output.
    local byPanel = {}
    for _, def in ipairs(NS.Settings.Schema) do
        local key = def.panel or "?"
        byPanel[key] = byPanel[key] or {}
        table.insert(byPanel[key], def)
    end
    for _, key in ipairs({ "general", "icons", "castbar", "spells", "profiles" }) do
        local list = byPanel[key]
        if list then
            p(self, "  |cff3399ff[" .. key .. "]|r")
            for _, def in ipairs(list) do
                p(self, "    " .. FormatKV(def.path, formatValue(def, H.Get(def.path))))
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
    p(self, FormatKV(def.path, formatValue(def, H.Get(def.path))))
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
-- /kcd reset, /kcd resetall, /kcd resetposition
-- ---------------------------------------------------------------------------
--
-- CLI parity for the panel's Defaults buttons. `/kcd reset <panel>`
-- mirrors the per-tab Defaults button; `/kcd resetall` mirrors the
-- General > "Reset all settings" popup (no confirmation in CLI — the
-- shell history IS the confirmation); `/kcd resetposition` mirrors
-- the General > "Reset position" button.

local RESET_PANELS = {
    general = true, icons = true, castbar = true, label = true, spells = true,
}

function runReset(self, rest)
    local panelName = (rest or ""):match("^(%S+)")
    panelName = panelName and panelName:lower() or ""
    if panelName == "" then
        return p(self, "Usage: /kcd reset <general|icons|castbar|label|spells>")
    end
    if not RESET_PANELS[panelName] then
        return p(self, "Unknown panel '" .. panelName .. "'. "
                 .. "Valid: general, icons, castbar, label, spells")
    end
    if panelName == "spells" then
        if self.Database and self.Database.ResetAllSpells then
            self.Database:ResetAllSpells()
            return p(self, "spells reset to defaults")
        end
        return p(self, "Database not ready")
    end
    local H = helpers()
    if not (H and H.RestoreDefaults) then
        return p(self, "Settings layer not ready yet")
    end
    -- Pass the live panel ctx so its widget refreshers re-sync if the
    -- tab is open. RestoreDefaults tolerates a nil ctx (closed panel).
    local ctx
    for _, c in ipairs(NS.Settings._panels or {}) do
        if c.panelKey == panelName then ctx = c; break end
    end
    H.RestoreDefaults(panelName, ctx)
    p(self, ("%s panel reset to defaults"):format(panelName))
end

function runResetAll(self)
    local H = helpers()
    if not (H and H.ResetAll) then
        return p(self, "Settings layer not ready yet")
    end
    H.ResetAll()
    p(self, "all settings + spells reset to defaults")
end

function runResetPosition(self)
    local H = helpers()
    if not (H and H.ResetIconPosition) then
        return p(self, "Settings layer not ready yet")
    end
    H.ResetIconPosition()
    p(self, "icon grid position reset")
end

-- ---------------------------------------------------------------------------
-- /kcd spells — per-class+spec spell-list editor (CLI parity for the
-- Spells panel)
-- ---------------------------------------------------------------------------
--
-- The on-disk shape is db.profile.spells[CLASS][SPEC] = {
--   { spellID=..., category=..., enabled=true|false }, ...
-- } in priority order. CLASS is the upper-case class file token
-- (WARRIOR, DEATHKNIGHT, …) and SPEC is the upper-case localized spec
-- name with whitespace stripped (FROST, BEASTMASTERY, …) — see
-- defaults/Spells.lua for the exact key set.
--
-- Every subcommand accepts an optional trailing `[CLASS SPEC]`; when
-- omitted, both default to the player's current class+spec.

local function lowerFirst(rest)
    local first, remainder = (rest or ""):match("^(%S*)%s*(.*)$")
    return (first or ""):lower(), remainder or ""
end

local function tokenize(rest)
    local out = {}
    for w in (rest or ""):gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- Normalize a user-supplied class/spec token to the casing used by
-- defaults/Spells.lua (uppercase, no whitespace). Routes through
-- Util.NormalizeSpecToken so all spec-key derivations across the addon
-- share one source of truth — important for whitespace-bearing
-- localised names ("Beast Mastery", non-English specs) that would
-- otherwise miss the no-whitespace defaults keys.
local function normToken(s)
    if not s or s == "" then return nil end
    return NS.Util.NormalizeSpecToken(s)
end

-- Resolve [class spec] starting at args[idx]. Empty positions fall
-- back to the player's class+spec.
local function resolvePlayerClassSpec()
    local classFile
    if UnitClass then
        local _, cf = UnitClass("player")
        classFile = cf
    end
    local specToken
    local Compat = NS.Compat
    local idx = Compat and Compat.GetSpecialization()
    if idx then
        local _, specName = Compat.GetSpecializationInfo(idx)
        specToken = normToken(specName)
    end
    return classFile, specToken
end

local function resolveClassSpec(args, idx)
    local class = normToken(args[idx])
    local spec  = normToken(args[idx + 1])
    if class and spec then return class, spec end
    local pClass, pSpec = resolvePlayerClassSpec()
    return class or pClass, spec or pSpec
end

-- Spell-list traversal funnels through Database:GetSpellList /
-- :EnsureSpellList so the slash-command layer matches the read/lazy-
-- create policy used by Cooldowns / IconGrid / settings/Spells.lua.
-- Read-only callers (list/remove/enable/disable/category) use
-- GetSpellList; mutators that should create a fresh list when none
-- exists (add / reset) use EnsureSpellList.

local function getSpellList(class, spec)
    if not NS.Database then return nil end
    return NS.Database:GetSpellList(class, spec)
end

local function ensureSpellList(class, spec)
    if not NS.Database then return nil end
    return NS.Database:EnsureSpellList(class, spec)
end

-- Mutation commit: fire the closed message; the Spells panel now
-- subscribes to Ka0s_KickCD_CONFIG_CHANGED { section = "spells" } in its own
-- ensurePanel hook so a slash-driven mutation refreshes the open editor
-- without a direct cross-module call from this layer (closed-bus
-- contract — see docs/message-bus.md).
local function commitSpellsChange()
    if NS and NS.SendMessage then
        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "spells" })
    end
end

local function resolveSpellInput(input)
    if not input or input == "" then return nil end
    local Compat = NS.Compat or {}
    local id = tonumber(input)
    if id then
        local name = Compat.GetSpellInfo and Compat.GetSpellInfo(id) or nil
        if name then return id, name end
        return nil
    end
    if Compat.GetSpellInfo then
        local name, _, _, _, _, resolvedID = Compat.GetSpellInfo(input)
        if name and resolvedID then return resolvedID, name end
    end
    return nil
end

local function findSpellEntry(list, id)
    if not list then return nil end
    for i, e in ipairs(list) do
        if e.spellID == id then return e, i end
    end
end

local CATEGORIES = {
    interrupt = true, stun = true, knockback = true, incapacitate = true,
    silence = true, root = true, fear = true, displace = true,
    racial = true, other = true,
}

-- Per-subcommand handlers --------------------------------------------------

local function spellsList(self, rest)
    local args = tokenize(rest)
    local class, spec = resolveClassSpec(args, 1)
    if not (class and spec) then
        return p(self, "Could not determine class+spec; specify them: "
                 .. "/kcd spells list <CLASS> <SPEC>")
    end
    local list = getSpellList(class, spec)
    if not list or #list == 0 then
        return p(self, ("no spells tracked for %s/%s")
                  :format(class, spec))
    end
    p(self, ("spells for %s/%s"):format(class, spec))
    local Compat = self.Compat or {}
    for i, e in ipairs(list) do
        local name = (Compat.GetSpellInfo and Compat.GetSpellInfo(e.spellID))
                     or "?"
        local flag = e.enabled == false and " (disabled)" or ""
        p(self, ("  %2d. #%-7d %s [%s]%s"):format(
            i, e.spellID, name, e.category or "other", flag))
    end
end

local function spellsAdd(self, rest)
    local args = tokenize(rest)
    if not args[1] then
        return p(self, "Usage: /kcd spells add <id|name> [CLASS SPEC]")
    end
    local id, name = resolveSpellInput(args[1])
    if not id then
        return p(self, "Unknown spell: " .. tostring(args[1]))
    end
    local class, spec = resolveClassSpec(args, 2)
    if not (class and spec) then
        return p(self, "Could not determine class+spec")
    end
    local list = ensureSpellList(class, spec)
    if not list then return p(self, "db not ready") end
    local existing = findSpellEntry(list, id)
    if existing then
        existing.enabled = true
        commitSpellsChange()
        return p(self, ("%s (#%d) already in %s/%s, re-enabled")
                  :format(name or "?", id, class, spec))
    end
    list[#list + 1] = { spellID = id, category = "other", enabled = true }
    commitSpellsChange()
    p(self, ("added %s (#%d) to %s/%s")
        :format(name or "?", id, class, spec))
end

local function spellsRemove(self, rest)
    local args = tokenize(rest)
    local id = tonumber(args[1])
    if not id then
        return p(self, "Usage: /kcd spells remove <id> [CLASS SPEC]")
    end
    local class, spec = resolveClassSpec(args, 2)
    local list = getSpellList(class, spec)
    if not list then
        return p(self, ("No spell list for %s/%s"):format(
                  tostring(class), tostring(spec)))
    end
    local _, idx = findSpellEntry(list, id)
    if not idx then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, spec))
    end
    table.remove(list, idx)
    commitSpellsChange()
    p(self, ("removed #%d from %s/%s"):format(id, class, spec))
end

local function spellsSetEnabled(self, rest, enabled)
    local args = tokenize(rest)
    local id = tonumber(args[1])
    if not id then
        return p(self, ("Usage: /kcd spells %s <id> [CLASS SPEC]")
                  :format(enabled and "enable" or "disable"))
    end
    local class, spec = resolveClassSpec(args, 2)
    local list = getSpellList(class, spec)
    if not list then
        return p(self, ("No spell list for %s/%s"):format(
                  tostring(class), tostring(spec)))
    end
    local entry = findSpellEntry(list, id)
    if not entry then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, spec))
    end
    entry.enabled = enabled and true or false
    commitSpellsChange()
    p(self, ("#%d %s in %s/%s"):format(
        id, enabled and "enabled" or "disabled", class, spec))
end

local function spellsSetCategory(self, rest)
    local args = tokenize(rest)
    local id = tonumber(args[1])
    local cat = args[2] and args[2]:lower() or nil
    if not (id and cat) then
        return p(self, "Usage: /kcd spells category <id> <cat> [CLASS SPEC]")
    end
    if not CATEGORIES[cat] then
        local names = {}
        for k in pairs(CATEGORIES) do names[#names + 1] = k end
        table.sort(names)
        return p(self, "Unknown category. Allowed: " .. table.concat(names, ", "))
    end
    local class, spec = resolveClassSpec(args, 3)
    local list = getSpellList(class, spec)
    if not list then
        return p(self, ("No spell list for %s/%s"):format(
                  tostring(class), tostring(spec)))
    end
    local entry = findSpellEntry(list, id)
    if not entry then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, spec))
    end
    entry.category = cat
    commitSpellsChange()
    p(self, ("#%d category = %s in %s/%s"):format(
        id, cat, class, spec))
end

-- Per-spec reset: rebuild this single (class, spec) list from
-- KickCD.DefaultSpells. Mirrors the Spells panel's Defaults popup
-- (KICKCD_RESET_SPELLS) — which is intentionally narrower than
-- `/kcd reset spells` (the latter calls Database:ResetAllSpells and
-- wipes every class+spec).
local function spellsReset(self, rest)
    local args = tokenize(rest)
    local class, spec = resolveClassSpec(args, 1)
    if not (class and spec) then
        return p(self, "Could not determine class+spec")
    end
    local list = ensureSpellList(class, spec)
    if not list then return p(self, "db not ready") end
    -- Wipe in place rather than reassigning so any reference held by
    -- BuildSpells / consumers stays valid.
    for i = #list, 1, -1 do list[i] = nil end
    local source = self.DefaultSpells
                   and self.DefaultSpells[class]
                   and self.DefaultSpells[class][spec]
    if source then
        for i, e in ipairs(source) do
            list[i] = {
                spellID  = e.spellID  or e[1],
                category = e.category or e[2] or "other",
                enabled  = e.enabled ~= false,
            }
        end
    end
    commitSpellsChange()
    p(self, ("reset %s/%s to defaults"):format(class, spec))
end

local SPELLS_COMMANDS = {
    {"list",     "List spells — `... list [CLASS SPEC]`",
        function(self, rest) spellsList(self, rest) end},
    {"add",      "Add a spell — `... add <id|name> [CLASS SPEC]`",
        function(self, rest) spellsAdd(self, rest) end},
    {"remove",   "Remove a spell — `... remove <id> [CLASS SPEC]`",
        function(self, rest) spellsRemove(self, rest) end},
    {"enable",   "Enable a spell — `... enable <id> [CLASS SPEC]`",
        function(self, rest) spellsSetEnabled(self, rest, true) end},
    {"disable",  "Disable a spell — `... disable <id> [CLASS SPEC]`",
        function(self, rest) spellsSetEnabled(self, rest, false) end},
    {"category", "Set category — `... category <id> <cat> [CLASS SPEC]`",
        function(self, rest) spellsSetCategory(self, rest) end},
    {"reset",    "Reset one spec to defaults — `... reset [CLASS SPEC]`",
        function(self, rest) spellsReset(self, rest) end},
}

function runSpells(self, rest)
    local sub, rem = lowerFirst(rest)
    if sub == "" then
        p(self, "spells subcommands")
        for _, entry in ipairs(SPELLS_COMMANDS) do
            p(self, ("  |cffffff00/kcd spells %s|r — |cffffffff%s|r"):format(entry[1], entry[2]))
        end
        local cls, spc = resolvePlayerClassSpec()
        if cls and spc then
            p(self, ("  (default class/spec when omitted: %s/%s)"):format(cls, spc))
        end
        return
    end
    local entry = findCommand(SPELLS_COMMANDS, sub)
    if entry then return entry[3](self, rem) end
    p(self, "unknown spells subcommand '" .. sub .. "'")
    runSpells(self, "")
end

-- ---------------------------------------------------------------------------
-- Settings entry point
-- ---------------------------------------------------------------------------

--- Open the Blizzard Settings panel to KickCD's parent page.
-- Settings layer is set up by settings/Panel.lua, which assigns
-- KickCD.Settings.main. If that hasn't run yet we schedule a deferred
-- retry (3 attempts, 0.5s apart) and ultimately print rather than
-- error so this is safe to call at any time after PLAYER_LOGIN.
-- @param input slash-command tail (ignored)
local OPEN_SETTINGS_MAX_RETRIES = 3
local OPEN_SETTINGS_RETRY_DELAY = 0.5

-- Force-expand the parent category in the Blizzard Settings left tree
-- so every sub-page is visible after we open the parent (Blizzard's
-- CategoryList only auto-expands a parent's tree when one of its
-- *children* is selected, never on parent self-select). The whole
-- thing is wrapped in pcall: SettingsPanel internals
-- (CategoryList / GetCategoryList / GetCategoryEntry / SetExpanded)
-- are private API and could shift between patches; if any call goes
-- missing we fall through to "parent opened, tree collapsed" rather
-- than erroring out — the user is then one click away from what they
-- wanted, same as if we hadn't tried at all.
local function expandMainCategory(main)
    if not (main and SettingsPanel) then return end
    pcall(function()
        local list = SettingsPanel.GetCategoryList
            and SettingsPanel:GetCategoryList()
            or SettingsPanel.CategoryList
        if not (list and list.GetCategoryEntry) then return end
        local entry = list:GetCategoryEntry(main)
        if entry and entry.SetExpanded then
            entry:SetExpanded(true)
        end
    end)
end

function NS:OpenSettings(input)
    local p = self.Util and self.Util.print or print
    -- Settings panel registration touches protected frames; opening it in
    -- combat would taint the dropdown / category tree. Gate here so every
    -- entry point (slash, deferred retry, future callers) shares the check.
    local inCombat = (self.State and self.State.inCombat)
        or (_G.InCombatLockdown and _G.InCombatLockdown())
    if inCombat then
        self._openRetries = nil
        -- Grey "notice" styling: the body is de-emphasised (this is expected,
        -- not an error) while Util.print keeps the [KCD] tag full-colour.
        local msg = (self.L and self.L["Cannot open settings during combat."])
            or "cannot open settings during combat — Blizzard's category-switch is protected"
        p(self, (NS.GREY or "") .. msg .. "|r")
        return
    end
    if Settings and Settings.OpenToCategory then
        local main = self.Settings and self.Settings.main
        if main and main.GetID then
            self._openRetries = nil
            if NS.State and NS.State.debug then NS.Debug("Open", "settings panel") end
            Settings.OpenToCategory(main:GetID())
            expandMainCategory(main)
            return
        end
        -- Settings layer not registered yet. Defer rather than printing
        -- "not registered" — a /kcd config the moment after login can
        -- race the PLAYER_LOGIN-deferred RegisterPanel.
        self._openRetries = (self._openRetries or 0) + 1
        if self._openRetries <= OPEN_SETTINGS_MAX_RETRIES and C_Timer and C_Timer.After then
            p("Settings still loading, opening shortly…")
            C_Timer.After(OPEN_SETTINGS_RETRY_DELAY, function()
                self:OpenSettings(input)
            end)
            return
        end
        self._openRetries = nil
    end
    p("Settings not yet registered")
end
