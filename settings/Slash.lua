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
-- ── THE THREE ADAPTERS, and why each is host-shaped rather than a library gap
--
-- 1. groupKey. KickCD's schema rows carry `panel`, not `page`. The library
--    defaults groupKey to `row.page or "settings"`, so without the override
--    every row in the addon would list under one "settings" heading.
--
-- 2. The colour codec. This one fails SILENTLY and only in game, which is why
--    it has its own case in tests/test_slash.lua. KickCD stores colours as a
--    POSITIONAL array {r,g,b,a} (see NS.Util.Unpack, and every default in
--    settings/*.lua); the library's ParseValue returns and its FormatValue reads
--    the KEYED {r=,g=,b=,a=} shape. Left alone, every saved colour would render
--    as {0.00, 0.00, 0.00, 1.00} and every `set` would write a table the addon
--    cannot unpack.
--
--    LibKa0s-Options-1.0 solves exactly this with descriptor colorDecode /
--    colorEncode fields. LibKa0s-Slash-1.0 HAS NO EQUIVALENT: lib.FormatValue is
--    lib-level and reached directly from the instance's kv(), with no seam a
--    host can inject a codec into. Considered adding one and rejected it — the
--    misfit is expressible as closures here, over `get` and `parse`, and the
--    adoption rule is that a descriptor gap you can close in the setup file is
--    not a library change. It IS reported as the place the contract did not fit.
--
-- 3. The parser override. Two things ride on it: the colour encode above, and
--    the `valueGate` hint machinery, which explains WHY a dropdown value was
--    rejected by probing what the gating sibling setting would allow. That is
--    genuinely this addon's (growDirection's UP/DOWN vs RIGHT/LEFT depends on
--    castbar.orientation) and the library has no hook for it, so it stays here
--    behind the descriptor's documented `parse` seam rather than forking the
--    dispatcher.

local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

local function helpers()
    return NS.Settings and NS.Settings.Helpers
end

local function out(line)
    if NS.Util and NS.Util.print then NS.Util.print(line) end
end

local function addonVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = get and get(addonName, "Version")
    if type(v) == "string" and v ~= "" then return v end
    return NS.VERSION
end
NS.Slash.Version = addonVersion

-- ---------------------------------------------------------------------
-- Adapter 2 — the colour codec
-- ---------------------------------------------------------------------

local function isColorRow(path)
    local H = helpers()
    local def = H and H.FindSchema and H.FindSchema(path)
    return def and def.type == "color" or false
end

--- Stored (positional) -> the keyed shape lib.FormatValue reads.
--- Only colour rows are translated; everything else passes through untouched,
--- so a number stays a number and a bool stays a bool.
local function readForLib(path)
    local H = helpers()
    if not (H and H.Get) then return nil end
    local v = H.Get(path)
    if isColorRow(path) and type(v) == "table" then
        return { r = v[1] or 0, g = v[2] or 0, b = v[3] or 0, a = v[4] or 1 }
    end
    return v
end

--- The library's parser, then the keyed colour it returns folded back into this
--- addon's positional storage shape. The failure signal — a nil first return
--- plus a reason — is preserved exactly; folding it into an `and`/`or` chain
--- would turn a legitimately stored `false` into a parse failure.
local function parseForHost(row, text)
    local v, err = SlashLib.ParseValue(row, text)
    if v == nil then return nil, err end
    if row.type == "color" and type(v) == "table" then
        return { v.r, v.g, v.b, v.a }
    end
    return v
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
    local missing = " is unavailable: the LibKa0s library is missing from this installation "
        .. "of KickCD (expected in libs/LibKa0s)."
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
    version = addonVersion,

    -- Adapter 2 on the read side: colours come back keyed so lib.FormatValue can
    -- render them; everything else passes through.
    get = readForLib,

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
