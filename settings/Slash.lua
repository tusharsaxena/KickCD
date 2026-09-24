local _, NS = ...
NS.Slash = NS.Slash or {}

-- settings/Slash.lua — wires the addon into LibKa0s-Slash-1.0.
--
-- The dispatcher, the help renderer, the row and key/value formatters, the list
-- builder and the type-aware value parser live in libs/LibKa0s/Slash.lua and are
-- shared across every Ka0s addon. What stays ours is what is genuinely ours: the
-- verb table (NS.COMMANDS, defined in core/KickCD.lua and passed IN, never
-- owned), the host verbs that reach into this addon's own state, and the three
-- adapters below.
--
-- TOC POSITION: settings/, after core/KickCD.lua has defined NS.COMMANDS — the
-- table is passed into the descriptor at load, so it has to exist by then.
-- core/KickCD.lua's NS:OnSlashCommand reaches NS.Slash at CALL time, so the
-- registration in OnInitialize is unaffected by the split.
--
-- ── THE TWO ADAPTERS, and why each is host-shaped rather than a library gap
--
-- 1. groupKey. KickCD's schema rows carry `panel`, not `page`. The library
--    defaults groupKey to `row.page or "settings"`, so without the override
--    every row in the addon would list under one "settings" heading.
--
-- 2. The parser override. It carries the `valueGate` hint machinery, which
--    explains WHY a dropdown value was rejected by asking what the row would
--    offer were the gating sibling setting flipped. That is genuinely this addon's
--    (growDirection's UP/DOWN vs RIGHT/LEFT depends on castbar.orientation) and
--    the library has no hook for it, so it stays here behind the descriptor's
--    documented `parse` seam rather than forking the dispatcher.
--
-- There was a third — a color codec, folding the library's keyed
-- { r =, g =, b =, a = } back into the positional array this addon used to
-- store. It is gone, and BOTH reasons it could go are worth keeping, because
-- they answer different questions.
--
-- Why it is not needed here: the STORED shape migrated (core/Database.lua's
-- v3 -> v4 step), so host and library agree and nothing translates between them.
-- That remains the better fix — a translation layer is a thing to keep correct
-- forever, whereas a migration runs once.
--
-- Why it was tolerable while it lasted, for the next host that hits a misfit:
-- it was expressible as closures over `get` and `parse`, and a misfit you can
-- close in the setup file is a setup-file concern rather than a library change.
--
-- What HAS changed since: LibKa0s-Slash-1.0 grew the codec anyway, in minor 4.
-- `colorDecode` / `colorEncode` now exist on the Slash descriptor under the
-- same names LibKa0s-Options-1.0 has always used, so a host passes one pair to
-- both majors, and `lib.FormatValue` reads the positional shape directly — the
-- common case needs no descriptor at all. So the asymmetry this paragraph used
-- to describe is closed. It went upstream because a SECOND host hit the same
-- wall (ConsumableMaster, which stores colors positionally and could not
-- migrate — the Ka0s options color widget writes that shape), and one misfit
-- is a setup-file concern while two is a library gap.

local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

local function helpers()
    return NS.Settings and NS.Settings.Helpers
end

-- The settings schema's runtime (settings/SchemaSetup.lua, which loads first in
-- the settings block): the reader, the row index and the reset funnel this
-- descriptor takes by value, and the primitives GateHint's fallback probe walks.
local Store     = NS.Settings.Store
local SchemaLib = NS.Settings.SchemaLib

local function out(line)
    if NS.Util and NS.Util.print then NS.Util.print(line) end
end

-- The version this layer reports, from core/EnvSetup.lua rather than from a
-- fourth copy of the C_AddOns ladder. Published on NS.Slash because
-- tests/test_perfsetup.lua asserts a capture record and `/kcd version` agree,
-- and they can only be checked against each other through a named surface.
NS.Slash.Version = NS.Version

-- ---------------------------------------------------------------------
-- The parser override
-- ---------------------------------------------------------------------
--
-- Only the `valueGate` hint lives here — see the header for the color codec
-- that used to sit beside it and why it isn't needed any more.

--- The keys an option list offers, sorted. Two shapes reach here, the same two
--- the library's enumList reads: a keyed map (`{ KEY = label }`) and a list of
--- `{ value =, label = }` items. The list shape is what growDirection returns,
--- and reading its keys would name the positions "1/2" rather than the values.
local function listKeys(v)
    local keys = {}
    if type(v) ~= "table" then return keys end
    if type(v[1]) == "table" and v[1].value ~= nil then
        for _, item in ipairs(v) do keys[#keys + 1] = tostring(item.value) end
    else
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    end
    table.sort(keys)
    return keys
end

--- The keys a dropdown row currently offers, resolved at call time because a
--- media list is populated by another addon and is not knowable when the row is
--- declared. Same resolution the library's own parser does.
local function allowedKeys(row)
    return listKeys(type(row.values) == "function" and row.values() or row.values)
end

--- The keys the row would offer with its gate set to `candidate`.
---
--- A row that declares `valuesFor(gateValue)` is simply asked: it is pure by
--- contract, so the live profile is never touched (KICKCD-R-15). That is the
--- path every gated row in this addon takes -- settings/Castbar.lua's
--- growDirection shares one table between its `values` and its `valuesFor`, so
--- the gating rule is still written once.
---
--- A row WITHOUT valuesFor falls back to the original probe: swap the gate's
--- stored value to the candidate, re-ask the row's own `values`, and restore.
--- The swap is transient -- one call between mutate and restore, with no
--- message-bus dispatch in between -- but that one call is addon-authored and
--- free to raise (an LSM row asks another addon's table). Unguarded, the restore
--- would be skipped and the candidate left in SavedVariables, silently, with no
--- onChange and no panel refresh, from a READ-ONLY hint. So it runs under
--- `pcall`: the restore is unconditional, and a raising `values` costs the user
--- one missing hint clause rather than a changed setting.
--- tests/test_color_shape.lua pins both paths.
---
--- Answers nil when the candidate's keys cannot be computed.
local function keysForCandidate(row, candidate, gateVal)
    if type(row.valuesFor) == "function" then
        local ok, alt = pcall(row.valuesFor, candidate)
        return ok and listKeys(alt) or nil
    end
    local profile = NS.db.profile
    SchemaLib.Write(profile, row.valueGate, candidate)
    local ok, alt = pcall(allowedKeys, row)
    SchemaLib.Write(profile, row.valueGate, gateVal)
    return ok and alt or nil
end

--- Why a dropdown value was rejected, when a sibling setting is what rejected it.
---
--- `valueGate` names the setting whose current value gates this row's option
--- list -- the cast bar's growDirection offers UP/DOWN or RIGHT/LEFT depending on
--- castbar.orientation. Without this, a user who types a perfectly sensible
--- value gets "Allowed values: LEFT, RIGHT" and no clue why UP vanished.
---
--- The answer is real rather than modeled: for each other value the gate could
--- take, keysForCandidate asks what the row would then offer -- through the
--- row's pure `valuesFor` when it has one, or the pcall-guarded swap-and-restore
--- probe when it does not. The probe reads and writes db.profile through the
--- schema major's own primitives (SchemaLib.Read / Write, the library or its
--- stub), and only a row that lacks valuesFor is refused a flip clause when the
--- gate's parent table is not there -- Write would create it, and a read-only
--- hint must not.
local function gateParentExists(path)
    local profile = NS.db and NS.db.profile
    local parts = SchemaLib.SplitPath(path)
    if type(profile) ~= "table" or #parts == 0 then return false end
    -- SplitPath's array is shared per path string, so the parent's walk is a
    -- copy one segment short rather than an edit of it.
    local up = {}
    for i = 1, #parts - 1 do up[i] = parts[i] end
    return #up == 0 or type(SchemaLib.Read(profile, up)) == "table"
end

function NS.Slash.GateHint(row)
    local gateVal = Store.Get(row.valueGate)
    local msg = (" (depends on %s = %s)"):format(row.valueGate, tostring(gateVal))

    local gateDef = Store.FindRow(row.valueGate)
    if not gateDef then return msg end
    local gateValues = type(gateDef.values) == "function" and gateDef.values() or gateDef.values
    if type(gateValues) ~= "table" then return msg end

    if type(row.valuesFor) ~= "function" and not gateParentExists(row.valueGate) then
        return msg
    end

    local hints = {}
    for candidate in pairs(gateValues) do
        if candidate ~= gateVal then
            local alt = keysForCandidate(row, candidate, gateVal)
            if alt and #alt > 0 then
                hints[#hints + 1] = ("flip %s to %s for %s")
                    :format(row.valueGate, tostring(candidate), table.concat(alt, "/"))
            end
        end
    end
    table.sort(hints)
    if #hints > 0 then msg = msg .. "; " .. table.concat(hints, "; ") end
    return msg
end

--- The library's parser, unchanged, plus this addon's own explanation of WHY a
--- dropdown value was rejected. The library has no hook for that and should not:
--- it is a fact about this addon's schema, not about parsing.
---
--- The nil-plus-reason failure signal is preserved exactly. Folding it into an
--- `and`/`or` chain would turn a legitimately parsed `false` into a failure.
local function parseForHost(row, text)
    local v, err = SlashLib.ParseValue(row, text)
    if v ~= nil then return v end
    if row.type == "string" and row.valueGate then
        return nil, (err or "") .. NS.Slash.GateHint(row)
    end
    return nil, err
end

-- ---------------------------------------------------------------------
-- The reset convergence
-- ---------------------------------------------------------------------
--
-- `/kcd reset` used to take a PAGE — general | icons | castbar | label | spells.
-- It now takes a schema PATH and resets exactly one row, which is the shape the
-- whole collection uses: a page is a property of a settings panel, not of the
-- data, and every schema-driven page here already carries a Defaults button that
-- resets it (settings/General.lua, Icons.lua, Castbar.lua, Label.lua all wire
-- one). The capability is not lost; only its CLI route is.
--
-- `reset spells` was the odd one out — it never reset a page at all, it rebuilt
-- EVERY spec's spell list through Database:ResetAllSpells. That has moved to
-- `/kcd spells resetall`, beside the existing `/kcd spells reset` which resets a
-- single class+spec pair.
--
-- Removals ship with a message, not silently: each old page name is answered
-- with where its capability went, because "Setting not found: general" is a bug
-- report waiting to happen.
local RETIRED_RESET_PAGES = {
    general = true, icons = true, castbar = true, label = true,
}

local function runReset(rest)
    local token = (rest or ""):match("^(%S+)")
    if token then
        local lowered = token:lower()
        if lowered == "spells" then
            out("`/kcd reset spells` has moved to |cFFFFFF00/kcd spells resetall|r "
                .. "\226\128\148 it rebuilds every spec's list.")
            return
        end
        if RETIRED_RESET_PAGES[lowered] then
            out(("`/kcd reset %s` is gone \226\128\148 `reset` now takes a setting path. "):format(lowered)
                .. "Use the " .. lowered .. " panel's |cFFFFFF00Defaults|r button to reset the "
                .. "whole page, or |cFFFFFF00/kcd reset <path>|r for one setting (try /kcd list).")
            return
        end
    end
    NS.Slash.cli:CliReset(rest)
end
NS.Slash.RunReset = runReset

-- ---------------------------------------------------------------------
-- The degradation stub
-- ---------------------------------------------------------------------
--
-- `/kcd` is registered unconditionally in core/KickCD.lua's OnInitialize, so
-- something has to answer it. The shape is the one slash-commands-§1 (WS-02)
-- and LibKa0s-Slash-1.0's version-15 doc ("The degradation stub") prescribe:
--
--   * minimal OnSlash dispatch, with the disabled gate: a verb on the host's
--     own NS.FEATURE_VERBS (core/KickCD.lua) is refused with DisabledLine while
--     d.isEnabled() is false. The stub does not read d.liveVerbs: that union is
--     built from lib.LIVE_VERBS, which this load has no library to read, and
--     re-typing the reserved verbs here would be a second library copy;
--   * exactly one library string carried verbatim, the disabled line's format,
--     pinned byte for byte by tests/test_slash.lua (Kit.assertLibraryConstant);
--   * no copy of the row formatter, the parser or the key/value shape, so a
--     degraded help row renders plainly as `cmd  desc`, two spaces, no color
--     and no em dash (testing-§8's forbidden duplicate);
--   * the composed-row verbs take route (a): `enable` / `disable` reach CliSet,
--     which writes a bool literal for a path on NS.Settings.WRITE_THROUGH and
--     nothing else, and `lock` / `unlock` / `toggle` write through the Schema
--     stub's own writeThrough in core/KickCD.lua's setLocked. Every other
--     schema verb prints the collection's library-absent line, never raising.
--
-- The host verbs never went to the library, so they keep working untouched.
if not SlashLib then
    -- The bytes of LibKa0s-Slash-1.0's lib.DISABLED_LINE_FORMAT (v1.56.0), the
    -- one library string this stub may carry. Exposed on the instance as
    -- `__disabledLineFormat` for the pin; the `__` prefix keeps it outside the
    -- surface-parity gate, which is about the public surface.
    local DISABLED_LINE_FORMAT = "%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"

    SlashLib = {}
    SlashLib.ParseValue = function() return nil, "the LibKa0s library is missing" end

    --- The collection's library-absent line for `verb` (e.g. "/kcd list").
    local function absentLine(verb)
        return NS.L["%s is unavailable: the LibKa0s library did not load."]:format(verb)
    end

    --- A bool literal, or nil. A literal check on purpose, not a copy of the
    --- library's parser: the only rows this stub writes are bools.
    local BOOL_LITERAL = { ["true"] = true, on = true, ["false"] = false, off = false }

    local function writeThrough(path)
        for _, p in ipairs(NS.Settings.WRITE_THROUGH or {}) do
            if p == path then return true end
        end
        return false
    end

    --- `/kcd set <path> <value>` with no library: a bool literal for a
    --- writeThrough path goes to the Schema stub; everything else, and any
    --- failure, prints the library-absent line and writes nothing.
    local function cliSet(rest)
        local path, text = (rest or ""):match("^%s*(%S+)%s*(.-)%s*$")
        local v = text and BOOL_LITERAL[text:lower()]
        local S = NS.Settings.Store
        if v ~= nil and writeThrough(path) and S and S.Set then
            local ok, stored = pcall(S.Set, path, v)
            if ok and stored then return out(path .. " = " .. tostring(v)) end
        end
        out(absentLine("/kcd set"))
    end

    function SlashLib:New(d)
        local stub = {
            SetRowAnnotator = function() end,
            __disabledLineFormat = DISABLED_LINE_FORMAT,
        }
        for _, verb in ipairs({ "List", "Get", "Reset", "ResetAll" }) do
            local line = "/kcd " .. verb:lower()
            stub["Cli" .. verb] = function() out(absentLine(line)) end
        end
        stub.CliSet = function(_, rest) return cliSet(rest) end
        stub.CliVersion = function() out("v" .. tostring(d.version and d.version() or "?")) end
        -- The same line the library builds, from the same two arguments.
        stub.DisabledLine = function()
            return DISABLED_LINE_FORMAT:format(tostring(d.brandName or d.slash), d.slash .. " enable")
        end
        stub.LandingRows = function()
            local rows = {}
            for _, e in ipairs(d.commands or {}) do
                rows[#rows + 1] = d.slash .. " " .. e[1] .. "  " .. e[2]
            end
            return rows
        end
        stub.HelpRows = function()
            local rows = {}
            for _, r in ipairs(stub.LandingRows()) do rows[#rows + 1] = "  " .. r end
            return rows
        end
        stub.PrintHelp = function()
            out("v" .. tostring(d.version and d.version() or "?") .. " slash commands")
            for _, r in ipairs(stub.HelpRows()) do out(r) end
        end
        local feature = {}
        for _, verb in ipairs(NS.FEATURE_VERBS or {}) do feature[verb] = true end
        local function find(cmd)
            for _, e in ipairs(d.commands or {}) do
                if e[1] == cmd then return e end
            end
        end
        local function refused(cmd)
            return feature[cmd] and type(d.isEnabled) == "function" and not d.isEnabled()
        end
        stub.OnSlash = function(_, msg)
            local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
            if raw == "" then
                -- Bare `/kcd` runs `config` when the host registered one and
                -- prints help otherwise, as the library's OnSlash does
                -- (slash-commands-§4). `/kcd help` is the list.
                local config = find("config")
                if config then return config[3]("") end
                return stub.PrintHelp()
            end
            local cmd, rest = raw:match("^(%S+)%s*(.*)$")
            cmd = (cmd or ""):lower()
            cmd = (d.aliases or {})[cmd] or cmd
            local e = find(cmd)
            if e and refused(cmd) then return out(stub.DisabledLine()) end
            if e then return e[3](rest or "") end
            out("unknown command '" .. cmd .. "'")
            stub.PrintHelp()
        end
        return stub
    end
end

-- ---------------------------------------------------------------------
-- The dispatcher
-- ---------------------------------------------------------------------

-- The order `/kcd list` prints its groups in. MUST cover every panel key the
-- settings layer validates: a panel missing here is silently dropped from the
-- listing even though get/set still reach its rows — which is exactly how the
-- "label" tab went unlisted for a release.
local PAGE_ORDER = { "general", "icons", "castbar", "label", "spells", "profiles" }

--- Every schema row in the order `/kcd list` should print them: page by page,
--- rows in declaration order within a page. The library groups on groupKey and
--- PRESERVES this order, so the listing still matches the panel's page order
--- rather than the schema's raw declaration order.
local function allRows()
    local schema = NS.Settings and NS.Settings.Schema or {}
    local byPanel = {}
    for _, def in ipairs(schema) do
        local key = def.panel or "?"
        byPanel[key] = byPanel[key] or {}
        table.insert(byPanel[key], def)
    end
    local outRows = {}
    for _, key in ipairs(PAGE_ORDER) do
        for _, def in ipairs(byPanel[key] or {}) do outRows[#outRows + 1] = def end
    end
    return outRows
end

-- ---------------------------------------------------------------------
-- The disabled gate's three fields
-- ---------------------------------------------------------------------
--
-- `isEnabled` closes the gate, `brandName` is what the one refusal line names,
-- and `liveVerbs` is the set that still answers. The dispatcher, the help
-- renderer and the settings registration keep working in either state -- they
-- are SETUP, not features (slash-commands-§7) -- and so does the bare `/kcd`,
-- which opens the panel: the one surface a player uses to switch the addon back
-- on by hand.
--
-- THE LIST IS A UNION, NEVER A COPY. The library's twelve are the standard's
-- reserved verbs and a host MUST NOT refuse any of them; this addon adds
-- `spells` to them (core/KickCD.lua argues why). Built here by concatenation so
-- that a thirteenth reserved verb arriving in a future LibKa0s tag is live the
-- day it is vendored, rather than silently refused because a copy of the twelve
-- was typed into this file.
-- On a library-absent load SlashLib.LIVE_VERBS is nil, so this is just the
-- extras, and the degradation stub above gates on NS.FEATURE_VERBS instead.
local function liveVerbs()
    local verbs = {}
    for _, verb in ipairs(SlashLib.LIVE_VERBS or {}) do verbs[#verbs + 1] = verb end
    for _, verb in ipairs(NS.EXTRA_LIVE_VERBS or {}) do verbs[#verbs + 1] = verb end
    return verbs
end

NS.Slash.cli = SlashLib:New({
    slash        = "/kcd",
    slashAliases = { "/kickcd" },
    commands     = NS.COMMANDS,
    aliases      = { options = "config" },   -- back-compat: `/kcd options` -> `config`

    -- Asked at DISPATCH time, never cached, so the command after a `/kcd enable`
    -- works. NS.MasterEnabled (core/LifecycleSetup.lua) is the addon's one reader
    -- of the stored path -- the same function the latch takes its hold from, so
    -- the gate and the stand-down can never disagree about whether the addon is
    -- on.
    isEnabled = function() return NS.MasterEnabled() end,
    -- THE BRAND NAME IN PLAIN TEXT, the same string core/LauncherSetup.lua gives
    -- the LDB object as its `label` (launcher-§1 forbids escape sequences there,
    -- which is what makes it safe to drop into a colored line). Never the TOC
    -- `## Title`, which MAY carry color escapes.
    brandName = "Ka0s KickCD",
    liveVerbs = liveVerbs(),

    print   = function(line) out(line) end,
    version = NS.Version,

    -- The schema seam's reader, by value. No translation: colors are stored in
    -- the keyed shape the library already parses into and renders from, and
    -- Store.Get answers a stored FALSE as false -- the old
    -- `H and H.Get and H.Get (path) or nil` folded it to nil, which the library
    -- prints as the literal "nil". tests/test_launcher.lua pins it.
    get = Store.Get,

    -- The single write seam: Store.Set, through SetAndRefresh so an open panel
    -- repaints after a `/kcd set` exactly as after a checkbox. Store.Set's
    -- `false, err, why` comes back through it, and the library prints it
    -- (Slash minor 15) instead of echoing a value that was never stored.
    set = function(path, v)
        local H = helpers()
        if H and H.SetAndRefresh then return H.SetAndRefresh(path, v) end
        return Store.Set(path, v)
    end,

    findRow = Store.FindRow,

    -- Store.ApplyDefault copies a table default in and answers false for a row
    -- with no default, which the library prints as its NO_DEFAULT line. Outside
    -- any bracket, so `/kcd reset global.minimap.shown` still resets the one row
    -- every sweep leaves alone (launcher-§3).
    applyDefault = Store.ApplyDefault,

    -- The bulk bracket (LibKa0s-Slash-1.0 minor 8) around Sl:CliResetAll, the
    -- same pair the Options descriptor takes (debug-logging-§10). Nothing here
    -- routes to CliResetAll today -- `/kcd resetall` is a host verb that reaches
    -- the Options walk -- so this keeps a future route to one line, not one per row.
    bulkBegin = Store.BulkBegin,
    bulkEnd   = Store.BulkEnd,

    allRows  = allRows,
    parse    = parseForHost,

    -- Adapter 1: KickCD rows carry `panel`, not `page`.
    groupKey = function(row) return row.panel or "?" end,

    -- The library's strings are already byte-identical to this addon's for the
    -- list header, the group heading, the not-found line and the get usage. Only
    -- the ones that genuinely differ are overridden, and none is overridden just
    -- to avoid a convergence the standard asked for.
    L = NS.L and {
        LIST_HEADER = NS.L["Available settings"]
            and ("|cff33ff99" .. NS.L["Available settings"] .. "|r") or nil,
    } or nil,
})

--- The command list the settings landing page renders. The SAME formatter
--- `/kcd help` prints through, minus the chat indent — so the panel and the help
--- block cannot drift, which they did until this landed.
function NS.Slash:LandingRows() return NS.Slash.cli:LandingRows() end

function NS.Slash:OnSlash(msg) return NS.Slash.cli:OnSlash(msg) end

--- Print the collection's one refusal line, through this addon's tagged printer.
---
--- The launcher's left click is the second call site the standard names
--- (slash-commands-§7, launcher-§2): a refused click prints the SAME line a
--- refused feature verb prints, and it prints it by asking the library for it
--- rather than by spelling it again here. One sentence, one place.
---
--- On a library-absent load the stub above answers the same line, built from its
--- one pinned copy of the library's format string (slash-commands-§1). A
--- DisabledLine that answers nothing still prints nothing rather than an empty line.
function NS.Slash.PrintDisabledLine()
    local cli = NS.Slash.cli
    if not (cli and cli.DisabledLine) then return false end
    local line = cli:DisabledLine()
    if type(line) ~= "string" or line == "" then return false end
    out(line)
    return true
end

-- There is no `NS.Slash:PrintHelp` forwarder beside these two, and its absence is deliberate:
-- `M4c-06` deleted one. `core/KickCD.lua`'s `printHelp` reaches `NS.Slash.cli:PrintHelp()`
-- directly, behind the same "did settings/ load at all" guard the forwarder carried, so
-- nothing in the addon ever called it -- and `NS` is private (there is no `_G.KickCD`), so
-- nothing outside could. The blanket `212/self` hid it: with the receiver unreported the line
-- read like the third member of a trio rather than dead code.
