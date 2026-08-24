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
-- there is NO _G.KickCD rebind; the namespace stays private (architecture-§1).
-- The return value is deliberately discarded: NewAddon promotes the table it
-- is handed, so it hands back the very NS we passed in. Capturing it (as the
-- former NS.addon field did) only created a self-reference with no callers.
LibStub("AceAddon-3.0"):NewAddon(
    NS,
    "KickCD",
    "AceConsole-3.0",
    "AceEvent-3.0")

-- Public version stamp.
NS.VERSION = "1.2.1"

-- Fresh AceEvent-embedded table for a message-bus / event RECEIVER (architecture-§4).
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
    -- every load — it is NEVER read back from SavedVariables (debug-logging-§5). No
    -- seeding here on purpose.

    -- Slash commands. Both /kickcd and /kcd dispatch to OnSlashCommand,
    -- which prints the help index when called bare and routes to the
    -- COMMANDS / DEBUG_COMMANDS dispatch tables otherwise.
    self:RegisterChatCommand("kickcd", "OnSlashCommand")
    self:RegisterChatCommand("kcd",    "OnSlashCommand")
end

function NS:OnEnable()
    -- Modules register themselves via NewModule(...) and AceAddon
    -- auto-enables them.

    -- Build the options surface (settings/OptionsSetup.lua -> the library's
    -- O.CreateOptionsPanel): resolve AceGUI, validate the assembled schema,
    -- register the parent canvas category, then drain the six page builders
    -- queued by settings/<page>.lua's NS.RegisterOptionsPage calls.
    --
    -- Here rather than in a private bootstrap frame of its own, because
    -- options-ui-§5 puts registration at PLAYER_LOGIN and AceAddon's OnEnable
    -- IS PLAYER_LOGIN. The call is idempotent (the library refuses to register
    -- a second Blizzard category), so a re-enable is harmless.
    if NS.CreateOptionsPanel then NS.CreateOptionsPanel() end
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

-- (`trim` lived here to strip the raw slash input. LibKa0s-Slash-1.0's OnSlash
-- does that itself, so the last caller went with the dispatcher.)

local function p(self, ...)
    local fn = self.Util and self.Util.print or print
    fn(...)
end

-- (The `version` verb reads NS.Version(), the core/EnvSetup.lua seam. The
-- six-line C_AddOns ladder that used to sit here was one of THREE inline copies
-- in this addon and one of eleven across the collection; it lives in
-- LibKa0s-Env-1.0 now, with the same TOC-then-NS.VERSION preference and the
-- same refusal to touch the deprecated global. settings/Slash.lua and
-- core/PerfSetup.lua went the same way, so the three cannot disagree.)

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
        -- Announce through the one sender (settings/Panel.lua's
        -- Helpers.FireConfigChanged), never with a second SendMessage of our
        -- own: architecture-Â§4 wants one emitter per message.
        if H and H.FireConfigChanged then H.FireConfigChanged("general") end
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
-- Handlers take (rest) — everything after the verb, case and internal spacing
-- preserved — because that is what LibKa0s-Slash-1.0's dispatcher calls them
-- with (slash-commands-§3). They used to take (self, rest); `self` was always
-- NS, so each closure now names NS directly. A handler still expecting `self`
-- would read the REST of the line as its self and the argument as nil, which is
-- silently wrong rather than an error — hence the case in tests/test_slash.lua.
local COMMANDS = {
    {"help",          "List available commands",
        function() printHelp(NS) end},
    {"version",       "Print the addon version",
        function() p(NS, "v" .. NS.Version()) end},
    {"config",        "Open the settings panel",
        function() NS:OpenSettings() end},
    {"lock",          "Lock the icon grid in place",
        function() setLocked(NS, true) end},
    {"unlock",        "Unlock the icon grid for dragging",
        function() setLocked(NS, false) end},
    {"toggle",        "Toggle the icon grid lock state",
        function()
            local cur = NS.db and NS.db.profile and NS.db.profile.locked
            setLocked(NS, not cur)
        end},
    {"list",          "List every setting and its current value",
        function() listSettings(NS) end},
    {"get",           "Print a setting's current value — `/kcd get <path>`",
        function(rest) getSetting(NS, rest) end},
    {"set",           "Set a setting — `/kcd set <path> <value>` (try /kcd list)",
        function(rest) setSetting(NS, rest) end},
    {"reset",         "Reset one setting to its default — `/kcd reset <path>`",
        function(rest) runReset(NS, rest) end},
    {"resetall",      "Reset every schema-driven panel AND every spec's spell list to defaults",
        function() runResetAll(NS) end},
    {"resetposition", "Restore the icon grid to its default screen position",
        function() runResetPosition(NS) end},
    {"spells",        "Spell-list editor — try `/kcd spells` for the list",
        function(rest) runSpells(NS, rest) end},
    {"debug",         "Debug subcommands — try `/kcd debug` for the list",
        function(rest) runDebug(NS, rest) end},
    -- `perf` is a RESERVED verb across the collection (slash-commands-§2) and
    -- must be registered by the addon, never by the library: the lib returns
    -- lines and we print them through the tagged printer.
    {"perf",          "Measure performance — try `/kcd perf` for the workflow",
        function(rest)
            for _, line in ipairs(NS.Perf.OnCommand(rest or "")) do p(NS, line) end
        end},
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
    -- The header, the rows and their colors are LibKa0s-Slash-1.0's one
    -- formatter now (settings/Slash.lua). The two-space chat indent is the
    -- library's HelpRows form; the settings landing page renders the SAME rows
    -- through LandingRows, un-indented, so the two can no longer drift.
    if NS.Slash and NS.Slash.cli then return NS.Slash.cli:PrintHelp() end
    p(self, "slash help is unavailable \226\128\148 the settings layer failed to load")
end

function runDebug(self, rest)
    -- Debug subcommands are all-lowercase identifiers; lowercase the
    -- first token so callers don't have to (now that OnSlashCommand
    -- preserves case in `rest` for schema paths).
    local sub = (rest or ""):match("^(%S*)") or ""
    sub = sub:lower()
    if sub == "" then
        -- Bare `/kcd debug` toggles the console window (debug-logging-§5); the flag is
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

--- The entry point AceConsole's RegisterChatCommand resolves by name, kept here
--- so the registration in OnInitialize is unaffected by the dispatcher moving.
---
--- Dispatch itself is LibKa0s-Slash-1.0's (settings/Slash.lua): the empty-line
--- help, the verb lowercasing that deliberately does NOT touch `rest` (schema
--- paths are case-sensitive and a color is several tokens), the `options` ->
--- `config` alias, and the unknown-verb line followed by the help index. NS.Slash
--- is reached at CALL time, so settings/ loading after core/ costs nothing.
function NS:OnSlashCommand(input)
    if NS.Slash and NS.Slash.OnSlash then return NS.Slash:OnSlash(input) end
    -- settings/ never loaded. Say so rather than swallowing the command.
    p(self, "slash commands are unavailable \226\128\148 the settings layer failed to load")
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

-- The schema CLI is LibKa0s-Slash-1.0's (settings/Slash.lua): the value
-- formatter, the `key = value` pair, the type-aware parser with its clamping and
-- enum validation, and the list/get/set verbs themselves. What used to live here
-- was ~215 lines of the same thing, one of four-plus divergent copies across the
-- collection.
--
-- Two pieces did NOT generalize and moved to settings/Slash.lua rather than
-- disappearing: the positional-{r,g,b,a} color codec, and the `valueGate` hint
-- that explains which sibling setting is gating a rejected dropdown value.

function listSettings(self)
    if NS.Slash and NS.Slash.cli then return NS.Slash.cli:CliList() end
    p(self, "Settings layer not ready yet")
end

function getSetting(self, rest)
    if NS.Slash and NS.Slash.cli then return NS.Slash.cli:CliGet(rest) end
    p(self, "Settings layer not ready yet")
end

function setSetting(self, rest)
    if NS.Slash and NS.Slash.cli then return NS.Slash.cli:CliSet(rest) end
    p(self, "Settings layer not ready yet")
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

-- `/kcd reset` takes a schema PATH now, not a page. The convergence, the
-- deprecation messages for the five retired page names, and the new home of the
-- spell-database rebuild all live in settings/Slash.lua.
function runReset(self, rest)
    if NS.Slash and NS.Slash.RunReset then return NS.Slash.RunReset(rest) end
    p(self, "Settings layer not ready yet")
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
-- The on-disk shape is db.profile.spells[CLASS][specID] = {
--   { spellID=..., category=..., enabled=true|false }, ...
-- } in priority order. CLASS is the upper-case class file token
-- (WARRIOR, DEATHKNIGHT, …) and the spec key is Blizzard's NUMERIC
-- specialization ID — see core/Constants.lua (Const.SPEC) for the set.
--
-- At the COMMAND LINE the user still types a name, not a number: SPEC
-- accepts the English token (ELEMENTAL), the spec name in the client's
-- own language (Élémentaire), or the raw ID. Util.ResolveSpecID does the
-- conversion; output always echoes back the English token so a pasted
-- bug report reads the same in every locale (issue #8).
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

-- Normalize a user-supplied CLASS token to the casing used by
-- defaults/Spells.lua. UnitClass()'s file token is already
-- locale-independent, so this is just casing.
local function normClass(s)
    if not s or s == "" then return nil end
    return NS.Util.NormalizeClassToken(s)
end

-- Human-readable spec label for command output — English token where known
-- (see Util.SpecDisplay), never the localized name.
local function sd(spec)
    return NS.Util.SpecDisplay(spec)
end

-- Resolve [class spec] starting at args[idx]. Empty positions fall
-- back to the player's class+spec.
local function resolvePlayerClassSpec()
    local classFile
    if UnitClass then
        local _, cf = UnitClass("player")
        classFile = cf
    end
    return classFile, NS.Util.PlayerSpecID()
end

local function resolveClassSpec(args, idx)
    local class = normClass(args[idx])
    local pClass, pSpec = resolvePlayerClassSpec()
    -- Resolve the spec AGAINST the class the user gave (or their own), so a
    -- name shared by several classes ("Frost", "Holy") is unambiguous. An
    -- omitted spec falls back to the player's; a spec that was SUPPLIED but
    -- didn't resolve stays nil so the caller reports it rather than silently
    -- editing the wrong list.
    local spec
    if args[idx + 1] == nil then
        spec = pSpec
    else
        spec = NS.Util.ResolveSpecID(args[idx + 1], class or pClass)
    end
    return class or pClass, spec
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
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("spells") end
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
                  :format(class, sd(spec)))
    end
    p(self, ("spells for %s/%s"):format(class, sd(spec)))
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
                  :format(name or "?", id, class, sd(spec)))
    end
    list[#list + 1] = { spellID = id, category = "other", enabled = true }
    commitSpellsChange()
    p(self, ("added %s (#%d) to %s/%s")
        :format(name or "?", id, class, sd(spec)))
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
                  tostring(class), sd(spec)))
    end
    local _, idx = findSpellEntry(list, id)
    if not idx then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
    table.remove(list, idx)
    commitSpellsChange()
    p(self, ("removed #%d from %s/%s"):format(id, class, sd(spec)))
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
                  tostring(class), sd(spec)))
    end
    local entry = findSpellEntry(list, id)
    if not entry then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
    entry.enabled = enabled and true or false
    commitSpellsChange()
    p(self, ("#%d %s in %s/%s"):format(
        id, enabled and "enabled" or "disabled", class, sd(spec)))
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
                  tostring(class), sd(spec)))
    end
    local entry = findSpellEntry(list, id)
    if not entry then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
    entry.category = cat
    commitSpellsChange()
    p(self, ("#%d category = %s in %s/%s"):format(
        id, cat, class, sd(spec)))
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
    p(self, ("reset %s/%s to defaults"):format(class, sd(spec)))
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
    -- The new home of `/kcd reset spells`. That verb was the odd one out in the
    -- old page-shaped reset: it never reset a settings page, it rebuilt EVERY
    -- spec's spell list. `reset` now takes a schema path, so the capability
    -- moved here, beside the single-spec `reset` above where it belongs.
    {"resetall", "Rebuild EVERY spec's list from the defaults — `... resetall`",
        function(self)
            if not (self.Database and self.Database.ResetAllSpells) then
                return p(self, "Database not ready")
            end
            self.Database:ResetAllSpells()
            p(self, "spells reset to defaults")
        end},
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

-- Settings panel registration touches protected frames; opening it in combat
-- would taint the dropdown / category tree. Read the state both ways so every
-- entry point (slash, a /run script, a future internal caller) shares one check.
local function inCombat(self)
    return (self.State and self.State.inCombat)
        or (_G.InCombatLockdown and _G.InCombatLockdown())
end

-- Gray "notice" styling: the body is de-emphasized (this is expected, not an
-- error) while Util.print keeps the [KCD] tag full-color. This is the reason
-- the combat gate stays HERE rather than being left to the library's own
-- refusal: the library prints its shared English string, and this addon's
-- refusal is a localized line (locales/enUS.lua's "Cannot open settings during
-- combat.").
local function combatNotice(self)
    local msg = (self.L and self.L["Cannot open settings during combat."])
        or "cannot open settings during combat — Blizzard's category-switch is protected"
    return (NS.GRAY or "") .. msg .. "|r"
end

--- Open the Blizzard Settings panel to KickCD's parent page.
--
-- This function used to BE the open path: it read KickCD.Settings.main off the
-- private registry in settings/Panel.lua, called Settings.OpenToCategory itself
-- and force-expanded the category tree through SettingsPanel's private API — a
-- line-for-line second copy of LibKa0s-Options-1.0's O.OpenOptionsPanel, which
-- the addon also shipped and never called (KCD-A-09). It also carried a
-- three-attempt, 0.5s-apart retry, for the race between `/kcd config` and the
-- PLAYER_LOGIN-deferred private RegisterPanel.
--
-- Both are gone with the registry (options-ui-§5). Registration is no longer
-- deferred behind its own frame: OnEnable calls NS.CreateOptionsPanel()
-- synchronously in the same PLAYER_LOGIN turn, before any slash input can
-- arrive, so there is nothing left to race and nothing to retry into. The open
-- itself, the ID lookup and the tree expansion are the library's.
--
-- @param input slash-command tail (ignored)
function NS:OpenSettings()
    if inCombat(self) then
        p(self, combatNotice(self))
        return
    end
    if not NS.OpenOptionsPanel then
        -- settings/OptionsSetup.lua never loaded at all. Say so rather than
        -- failing silently; the stub in that file covers "LibKa0s missing".
        return p(self, "Settings not yet registered")
    end
    if NS.State and NS.State.debug then NS.Debug("Open", "settings panel") end
    NS.OpenOptionsPanel()
end
