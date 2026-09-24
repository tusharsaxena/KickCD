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

local _, NS = ...

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
NS.VERSION = "1.3.0"

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

    -- The combat listener (core/State.lua). Armed here rather than at State.lua's
    -- file load because it registers through NS.RegisterEventList, which
    -- core/CoreSetup.lua defines after State.lua loads. ADDON_LOADED always
    -- precedes PLAYER_LOGIN, so the login seed is never missed.
    if NS.State and NS.State.Arm then NS.State.Arm() end

    -- Debug logging is a session-only flag (KickCD.State.debug) seeded off on
    -- every load — it is NEVER read back from SavedVariables (debug-logging-§5). No
    -- seeding here on purpose.

    -- Slash commands. Both /kickcd and /kcd dispatch to OnSlashCommand,
    -- which runs `config` when called bare and routes to the
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

    -- The launcher (core/LauncherSetup.lua): one LibDataBroker object, handed to
    -- LibDBIcon (launcher-§1). HERE rather than in OnInitialize because Register
    -- resolves `db.global.minimap` and OnInitialize is what builds the db. It is
    -- idempotent, so a re-enable costs nothing.
    if NS.Launcher then NS.Launcher:Register() end

    -- THE STORED MASTER SWITCH, TAKEN FOR THE FIRST TIME THIS SESSION
    -- (slash-commands-§7). The `disabled` hold persists by being re-taken at
    -- load from the store, which is the whole of how a disabled addon stays
    -- disabled across a /reload -- the latch itself persists nothing.
    --
    -- HERE, and it has to be here rather than in OnInitialize: AceAddon runs this
    -- function and THEN enables the modules, so the hold is taken before a single
    -- module's OnEnable runs and each of them finds NS.IsDown() already true and
    -- registers nothing. Taken in OnInitialize it would be a hold over an addon
    -- whose db had just been built and whose modules had not run at all; taken
    -- after the cascade there is no such moment to take it in.
    if NS.RefreshEnabledHold then NS.RefreshEnabledHold() end
end

-- ---------------------------------------------------------------------------
-- Slash command dispatch
-- ---------------------------------------------------------------------------
--
-- Two ordered tables drive the entire slash UX: COMMANDS for top-level
-- subcommands and DEBUG_COMMANDS for /kcd debug ... Each entry is
-- {name, description, fn}. The dispatcher (a) runs `config` (the settings
-- landing page) when invoked with no args, (b) looks up by name, (c) prints help on an
-- unknown name. Help text is generated from the same tables, so adding a
-- command means adding a single row.

-- (`trim` lived here to strip the raw slash input. LibKa0s-Slash-1.0's OnSlash
-- does that itself, so the last caller went with the dispatcher.)

local function p(self, ...)
    local fn = self.Util and self.Util.print or _G.print
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
-- `locked` schema row fires here too.
--
-- The helper or nothing (architecture-§5, #20). When SetAndRefresh cannot
-- take the write -- the settings layer is not loaded yet, or it finds no
-- `locked` row because that row is composed by LibKa0s-Options-1.0's Master
-- controls block and a load without the library has none -- this says so, the
-- way runResetPosition does, and writes nothing. It used to fall back to
-- `db.profile.locked = v`, which kept one composed setting writable around
-- the helper on the very load options-ui-§1 expects to lose it.
local function setLocked(self, value)
    if not (self.db and self.db.profile) then
        return p(self, "db not initialized yet")
    end
    local v = value and true or false
    local H = self.Settings and self.Settings.Helpers
    if not (H and H.SetAndRefresh and H.SetAndRefresh("locked", v)) then
        return p(self, "Settings layer not ready yet")
    end
    p(self, "icon grid " .. (v and "locked" or "unlocked"))
end

--- Flip the lock, through the one writer above.
---
--- Published because it has TWO callers now and they must not be two
--- implementations: `/kcd toggle` below, and the minimap button's left click
--- (core/LauncherSetup.lua). launcher-§2 puts this addon on rung (b) -- no
--- primary window, and Lock frame is the preview switch since unlocking IS the
--- preview -- and says in as many words that the launcher drives the addon's
--- EXISTING switch through the same seam rather than holding a copy of it. This
--- is that seam, and it holds no state: it reads db.profile.locked and hands the
--- negation to setLocked, which writes through Helpers.SetAndRefresh like the
--- `Lock frame` checkbox and `/kcd set locked` do.
function NS.ToggleLock()
    local cur = NS.db and NS.db.profile and NS.db.profile.locked
    setLocked(NS, not cur)
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
    -- RESERVED verbs (slash-commands-§2), and ALIASES rather than a switch of
    -- their own. Every addon already carries the addon-wide `Enable KickCD`
    -- checkbox as the first row of General > Master controls (options-ui-§15);
    -- what was missing was the CLI route to it, so the answer to "turn this off
    -- without opening anything" was "find the panel first".
    --
    -- They dispatch into setSetting, which IS `/kcd set` -- same stored path,
    -- same single write seam (options-ui-§1), same onChange, and the §5 `set`
    -- confirmation line for free. So they hold NO state of their own: no second
    -- key, no session flag, no NS.enabled, and the checkbox and the verbs cannot
    -- show the player two different answers.
    --
    -- `/kcd` and these two keep working while the addon is DISABLED, and that is
    -- what stops the pair being one-way. The registration is in OnInitialize and
    -- is unconditional, and nothing in this addon tears down the chat command,
    -- this table or the dispatcher when `enabled` goes false -- the modules stand
    -- their DRAWING down and nothing else. Setup, not a feature
    -- (slash-commands-§2), and tests/test_slash.lua pins it.
    {"enable",        "Enable KickCD",
        function() setSetting(NS, "enabled true") end},
    {"disable",       "Disable KickCD — `/kcd enable` turns it back on",
        function() setSetting(NS, "enabled false") end},
    {"lock",          "Lock the icon grid in place",
        function() setLocked(NS, true) end},
    {"unlock",        "Unlock the icon grid for dragging",
        function() setLocked(NS, false) end},
    {"toggle",        "Toggle the icon grid lock state",
        function() NS.ToggleLock() end},
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

-- ---------------------------------------------------------------------------
-- The disabled state: the gate is the LIBRARY's, the judgment is ours
-- ---------------------------------------------------------------------------
--
-- While `enabled` is false, a verb that DRIVES THE ADDON'S FEATURES answers on
-- ONE tagged line naming `/kcd enable` and does nothing else (slash-commands-§2's
-- SHOULD). Acting is the wrong answer twice over -- the player asked for
-- something the addon is standing down from doing, and a silent no-op leaves
-- them with no clue why nothing happened.
--
-- THE GATE ITSELF IS NO LONGER HERE. This file used to wrap every entry in the
-- table below in a closure that checked the stored flag, because
-- LibKa0s-Slash-1.0 had no gate to hand it to. It has one now (minor 14 at v1.42.0):
-- settings/Slash.lua passes `isEnabled` and `brandName`, and the dispatcher
-- refuses the host's own feature verbs after the COMMANDS lookup -- which is one
-- behavior the host wrapper never got right, since a wrapper on the table cannot
-- tell a TYPO from a verb (a misspelling deserves `unknown command`, not "the
-- addon is disabled", which tells a player who mistyped that their spelling was
-- fine). The refusal LINE is the library's too, and deliberately: it is one
-- sentence, the collection spells it once, and eleven addons each wording it
-- their own way is exactly the drift the shared printer exists to end. So there
-- is no locale key for it here any more either.
--
-- WHAT STAYS OURS IS WHICH VERBS ARE LIVE. The library ships the standard's
-- twelve reserved verbs (`help`, `config`, `version`, `enable`, `disable`,
-- `debug`, `perf`, `get`, `set`, `list`, `reset`, `resetall`) and the bare `/kcd`
-- opens the panel in either state. The set below is what THIS addon adds to that
-- twelve, and settings/Slash.lua unions the two rather than re-typing them --
-- a narrowed copy of the library's list is the one thing a host MUST NOT pass.
--
-- `spells` IS THE THIRTEENTH, and it is this addon's own judgment rather than
-- the standard's list. The per-spec spell lists are stored ARRAYS, and an array
-- is addressable as a whole while its members deliberately are not -- so no
-- schema row covers them and `/kcd get|set|list|reset` cannot reach them at all.
-- `/kcd spells` is their ONLY CLI route, which makes it the schema CLI for that
-- data rather than a feature verb: refusing it would put "read and repair your
-- settings while the addon is off" out of reach for the one part of the
-- configuration that needs it most, which is the exact thing the live set exists
-- to protect. It configures; it does not drive.
--
-- WHAT IS LEFT REFUSED IS FOUR, and each really does drive the display. `lock`,
-- `unlock` and `toggle` flip the addon's PREVIEW SWITCH -- launcher-§2 puts
-- KickCD on rung (b) precisely because unlocking IS this addon's preview -- and
-- with the addon off there is no grid and no placeholder to unlock
-- (slash-commands-§8 says so in as many words). And `resetposition` re-anchors
-- the icon grid and fires CONFIG_CHANGED so the live grids move, then echoes
-- "icon grid position reset" at a player who can see no grid: an acknowledgment
-- of something that visibly did not happen.
NS.EXTRA_LIVE_VERBS = { "spells" }

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
    -- events-frames-taint-§1: the names NS.RegisterEventList recorded because
    -- this client raised on them. Session-only, like the list it reads.
    {"events", "List event names this client refused to register",
        function(self)
            local rejected = self.State and self.State.rejectedEvents or {}
            if #rejected == 0 then return p(self, "no rejected events") end
            for _, name in ipairs(rejected) do p(self, "rejected event: " .. name) end
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
--- Dispatch itself is LibKa0s-Slash-1.0's (settings/Slash.lua): bare input
--- running `config`, the verb lowercasing that deliberately does NOT touch `rest` (schema
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
    if _G.UnitClass then
        local _, cf = _G.UnitClass("player")
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

-- These handlers READ a list through Database:GetSpellList, which never
-- creates one, and write it only through core/Database.lua's verbs (AddSpell,
-- RemoveSpell, SetSpellEnabled, SetSpellCategory, ResetSpellList,
-- ResetAllSpells). Database is the spell lists' one writer: see the Writer line
-- under docs/ARCHITECTURE.md -> Settings schema (architecture-§5).

local function getSpellList(class, spec)
    if not NS.Database then return nil end
    return NS.Database:GetSpellList(class, spec)
end

-- Mutation commit: fire the closed message; the Spells panel now
-- subscribes to Ka0s_KickCD_ConfigChanged { section = "spells" } in its own
-- ensurePanel hook so a slash-driven mutation refreshes the open editor
-- without a direct cross-module call from this layer (closed-bus
-- contract — see docs/message-bus.md).
local function commitSpellsChange()
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("spells") end
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

-- The spell and its [CLASS SPEC] go through core/SpellInput.lua, the resolver
-- the Spells page's add box uses too: a multi-word name ("Wind Shear") is one
-- name, a trailing CLASS / SPEC is validated rather than trusted, and the
-- Blizzard Cooldown Manager gate applies on the player's live pair exactly as it
-- does on the page (KICKCD-R-05, KICKCD-R-18).
local function spellsAdd(self, rest)
    local SI = NS.SpellInput
    local id, name, class, spec = SI.ParseTail(tokenize(rest))
    if not id then return p(self, name) end
    local ok, why = SI.Admissible(id, class, spec)
    if not ok then return p(self, why) end
    local result = self.Database and self.Database:AddSpell(class, spec, id)
    if not result then return p(self, "db not ready") end
    commitSpellsChange()
    if result == "enabled" then
        return p(self, ("%s (#%d) already in %s/%s, re-enabled")
                  :format(name or "?", id, class, sd(spec)))
    end
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
    if not self.Database:RemoveSpell(class, spec, id) then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
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
    if not self.Database:SetSpellEnabled(class, spec, id, enabled) then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
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
    if not self.Database:SetSpellCategory(class, spec, id, cat) then
        return p(self, ("Spell #%d not in %s/%s"):format(id, class, sd(spec)))
    end
    commitSpellsChange()
    p(self, ("#%d category = %s in %s/%s"):format(
        id, cat, class, sd(spec)))
end

-- Per-spec reset: rebuild this single (class, spec) list through
-- Database:ResetSpellList, the same verb the Spells panel's Defaults popup
-- (KICKCD_RESET_SPELLS) calls. Narrower than `/kcd spells resetall`
-- (Database:ResetAllSpells, which wipes every class+spec); both re-append the
-- player's racial on their own class.
local function spellsReset(self, rest)
    local args = tokenize(rest)
    local class, spec = resolveClassSpec(args, 1)
    if not (class and spec) then
        return p(self, "Could not determine class+spec")
    end
    if not (self.Database and self.Database:ResetSpellList(class, spec)) then
        return p(self, "db not ready")
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
            p(self, ("  (default class/spec when omitted: %s/%s)"):format(cls, sd(spc)))
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
