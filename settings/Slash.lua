local addonName, NS = ...
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
--    explains WHY a dropdown value was rejected by probing what the gating
--    sibling setting would allow. That is genuinely this addon's
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

--- The keys a dropdown row currently offers, resolved at call time because a
--- media list is populated by another addon and is not knowable when the row is
--- declared. Same resolution the library's own parser does.
local function allowedKeys(row)
    local v = type(row.values) == "function" and row.values() or row.values or {}
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

--- Why a dropdown value was rejected, when a sibling setting is what rejected it.
---
--- `valueGate` names the setting whose current value gates this row's option
--- list — the cast bar's growDirection offers UP/DOWN or RIGHT/LEFT depending on
--- castbar.orientation. Without this, a user who types a perfectly sensible
--- value gets "Allowed values: LEFT, RIGHT" and no clue why UP vanished.
---
--- The probe is real rather than modeled: swap the gate's stored value to each
--- other candidate, re-ask the row's own `values` function, and restore. That is
--- the only way to answer it without duplicating the gating rule here, and the
--- swap is transient — one call between mutate and restore, with no message-bus
--- dispatch in between.
---
--- The one call in that window is `row.values()`, addon-authored and free to
--- raise (an LSM row asks another addon's table). If it did, the restore below
--- would never run and the swapped-in candidate would stay in SavedVariables —
--- silently, with no onChange and no panel refresh, from a READ-ONLY hint. So
--- the probe runs under `pcall`: the restore is unconditional, and a raising
--- `values` costs the user one missing hint clause rather than a changed
--- setting. tests/test_color_shape.lua pins that.
function NS.Slash.GateHint(row)
    local H = helpers()
    if not (H and H.Get and H.FindSchema and H.Resolve) then return "" end

    local gateVal = H.Get(row.valueGate)
    local msg = (" (depends on %s = %s)"):format(row.valueGate, tostring(gateVal))

    local gateDef = H.FindSchema(row.valueGate)
    if not gateDef then return msg end
    local gateValues = type(gateDef.values) == "function" and gateDef.values() or gateDef.values
    if type(gateValues) ~= "table" then return msg end

    local parent, key = H.Resolve(row.valueGate)
    if not (parent and key) then return msg end

    local hints = {}
    for candidate in pairs(gateValues) do
        if candidate ~= gateVal then
            parent[key] = candidate
            local ok, alt = pcall(allowedKeys, row)
            parent[key] = gateVal
            if ok and #alt > 0 then
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
-- something has to answer it. The host verbs never went to the library, so they
-- keep working untouched; what is lost is the schema CLI, and each of those
-- verbs names the missing library rather than going quiet.
--
-- Note what is NOT here: no copy of the row formatter, no copy of the parser, no
-- copy of the key/value shape. Hand-copying the strings whose drift the
-- extraction exists to end is the one duplicate testing-§8 most specifically
-- forbids, so a degraded help row renders plainly and says so.
if not SlashLib then
    -- The cause half is core/CoreSetup.lua's shared clause (NS.LIBKA0S_MISSING);
    -- only the consequence is this seam's. This is the one of the five whose
    -- consequence comes FIRST — the verb has to lead, or "/kcd list" is buried
    -- mid-sentence — so it reads "<verb> is unavailable. <cause>." AbsorbTracker
    -- inverts it the same way for the same reason, in its own
    -- ../AbsorbTracker/settings/Slash.lua `missing` stub.
    local missing = " is unavailable. " .. NS.LIBKA0S_MISSING .. "."
    SlashLib = {}
    SlashLib.ParseValue = function() return nil, "the LibKa0s library is missing" end

    function SlashLib:New(d)
        local stub = { SetRowAnnotator = function() end }
        local function absent(verb)
            return function() out("/kcd " .. verb .. missing) end
        end
        for _, verb in ipairs({ "List", "Get", "Set", "Reset", "ResetAll" }) do
            stub["Cli" .. verb] = absent(verb:lower())
        end
        stub.CliVersion = function() out("v" .. tostring(d.version and d.version() or "?")) end
        stub.LandingRows = function()
            local rows = {}
            for _, e in ipairs(d.commands or {}) do
                rows[#rows + 1] = d.slash .. " " .. e[1] .. " \226\128\148 " .. e[2]
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
        stub.OnSlash = function(_, msg)
            local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
            if raw == "" then return stub.PrintHelp() end
            local cmd, rest = raw:match("^(%S+)%s*(.*)$")
            cmd = (cmd or ""):lower()
            cmd = (d.aliases or {})[cmd] or cmd
            for _, e in ipairs(d.commands or {}) do
                if e[1] == cmd then return e[3](rest or "") end
            end
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

NS.Slash.cli = SlashLib:New({
    slash        = "/kcd",
    slashAliases = { "/kickcd" },
    commands     = NS.COMMANDS,
    aliases      = { options = "config" },   -- back-compat: `/kcd options` -> `config`

    print   = function(line) out(line) end,
    version = NS.Version,

    -- The plain host reader. No translation: colors are stored in the keyed
    -- shape the library already parses into and renders from.
    get = function(path)
        local H = helpers()
        return H and H.Get and H.Get(path) or nil
    end,

    -- The single write seam. SetAndRefresh — not the 3-arg Helpers.Set — because
    -- it is the one path that fires CONFIG_CHANGED with the row's section, runs
    -- the row's onChange and refreshes any open panel. A `/kcd set` then takes
    -- exactly the path a panel checkbox takes, which is the point of the rule.
    set = function(path, v)
        local H = helpers()
        if H and H.SetAndRefresh then H.SetAndRefresh(path, v) end
    end,

    findRow = function(path)
        local H = helpers()
        return H and H.FindSchema and H.FindSchema(path) or nil
    end,

    applyDefault = function(row)
        local H = helpers()
        if not (H and H.SetAndRefresh) then return end
        -- DeepCopy, because a default that is a table (an RGBA array) would
        -- otherwise be shared by every profile that reset to it.
        local d = row.default
        H.SetAndRefresh(row.path, type(d) == "table" and NS.Util.DeepCopy(d) or d)
    end,

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
function NS.Slash:PrintHelp() return NS.Slash.cli:PrintHelp() end
