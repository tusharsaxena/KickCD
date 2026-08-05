-- tests/run.lua — the headless runner (testing-§1).
--
--   lua tests/run.lua            -- from the repo root; exits non-zero on any failure
--   lua tests/run.lua --list     -- emit docs/test-cases.md's body and exit 0
--
-- The registry, the assertion set, the skip status, the suite-inventory gate, the `--list` renderer
-- and the source loader are all the VENDORED KIT's (tests/_kit/, from LibKa0s — never edited here;
-- tests/test_vendor_sync.lua is the byte-identity gate). What stays in this file is what is
-- genuinely KickCD's: the library load list, the instance factory, and the suite list.
--
-- COLLECT-THEN-RUN. This file used to carry its own `test()` which pcall'd the case body AT
-- REGISTRATION TIME and short-circuited it under `--list` (KCD-R-08). Two things were wrong with
-- that. `--list` was a second code path through the same function, so the inventory could disagree
-- with the run it claims to enumerate; and a case body ran while its own suite file was still being
-- dofile'd, which makes "what has already happened when this case runs?" depend on where in the
-- file the case sits. The kit's `test()` only records, and nothing executes until `Kit.run`.

-- Resolve the repo root from this script's path so it runs from anywhere.
local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/run%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local Kit     = dofile(root .. "/tests/_kit/framework.lua")
local Loader  = dofile(root .. "/tests/_kit/loader.lua")
-- loadfile-and-call rather than dofile, so the mock builder is handed `root` and can resolve
-- tests/_kit/mock_base.lua — the base it layers over — without assuming the process's CWD.
local mockmod = assert(loadfile(root .. "/tests/wow_mock.lua"))(root)

-- Every addon chunk is called as chunk("KickCD", NS), reproducing the client's
-- `local addonName, NS = ...` header. Library chunks ignore the varargs.
Loader.addonName = "KickCD"

-- ---------------------------------------------------------------------------
-- The vendored library load list
-- ---------------------------------------------------------------------------
--
-- The vendored library files, in libs/LibKa0s/LibKa0s.xml's own order — DERIVED FROM THE XML, not
-- typed here (testing-§9).
--
-- The TOC pulls the whole module in through that one `.xml`, which Loader.tocFiles deliberately
-- skips, so every runner in the collection re-typed the same eight-entry list. Eight hand-typed
-- copies of one list is eight chances to drop an entry, and one of them did: a sibling addon's
-- runner named six of the eight and nothing noticed, because a SHORT load list does not raise. It
-- leaves the dependent major unregistered, the host's setup file falls back to its stub, and the
-- suite happily measures the stub — green, and testing nothing.
--
-- Order comes out of the XML and matters: Core registers first because the other four `return`
-- before LibStub:NewLibrary without it, and the two Options attach files must follow their shell.
-- Loader.xmlFiles preserves XML order and raises on a missing XML rather than returning an empty
-- list, which would load nothing at all and read exactly like a clean run.
--
-- Already resolved against `root` — xmlFiles prefixes each entry with the XML's own directory —
-- so, unlike the TOC list below, these are handed to the loader as they come.
local LIB_FILES = Loader.xmlFiles(root .. "/libs/LibKa0s/LibKa0s.xml")

-- The addon's own files, in TOC order. Repo-relative (`core/Compat.lua`), because that is what the
-- TOC says; the loader is the only thing that needs them resolved.
local TOC_FILES = Loader.tocFiles(root .. "/KickCD.toc")

--- Repo-relative paths resolved against the root this script was invoked through.
local function rooted(list)
    local out = {}
    for i, rel in ipairs(list) do out[i] = root .. "/" .. rel end
    return out
end

-- ---------------------------------------------------------------------------
-- Instance factory: a fully-loaded, isolated addon environment
-- ---------------------------------------------------------------------------
--- Load a fresh isolated addon instance under its own mock.
--- @param initDB boolean  call the AceAddon OnInitialize (builds db) when true
--- @param enable boolean  run the OnEnable lifecycle cascade (needs initDB) when true
--- @param mutate function|nil  optional (mocks) -> () hook applied to the freshly
---        built mock table BEFORE any source loads. Needed by suites that have to
---        change the simulated client *before* init-time reads happen — e.g. the
---        frFR locale suite, where BuildSpells() resolves the player's spec during
---        OnInitialize and a post-load mock swap would be too late.
--- @param opts table|nil  { libFiles = { ... } } overrides the vendored library
---        load list. Pass `{}` to load the addon with LibKa0s ABSENT — the
---        degraded scenario debug-logging-§7 and testing-§8 require to be
---        exercised by a real load rather than by hand-stubbing the member
---        under test.
--- @return table inst  { NS, mocks }
---
--- Isolation is per-instance and comes from the mock, not from the environment: the kit's loader
--- resolves every WoW global through THIS instance's `mocks` table, and every symbol the addon
--- publishes lands on THIS instance's `NS`. There is no `_G.KickCD` rebind to share (see
--- docs/ARCHITECTURE.md) and no source in this addon writes a global, so nothing crosses between
--- instances.
local function loadInstance(initDB, enable, mutate, opts)
    local mocks = mockmod.build()
    if mutate then mutate(mocks) end
    -- `_G` must resolve to a table that answers from THIS instance's mocks. Nearly every WoW-API
    -- read in this addon is written `_G.C_SpecializationInfo`, `_G.InCombatLockdown`, `_G.UnitGUID`
    -- — explicit, because §4.1 forbids the deprecated bare globals and the `_G.` prefix is what
    -- makes a Compat-bypassing read visible in review. The kit's loader gives each chunk an
    -- environment whose `__index` falls through to the real `_G`, and the real `_G` has none of the
    -- client API in it, so an unbound `_G.X` reads nil and 144 cases measure the absent-API
    -- fallback instead of the API. Publishing one such environment AS `mocks._G` closes it: the
    -- kit's own makeEnv builds it, and `_G.X` then resolves through the same mock table a bare `X`
    -- does. Per instance, so two instances never see each other's client.
    mocks._G = Loader.makeEnv(mocks)
    local NS = {}
    Loader.loadAll((opts and opts.libFiles) or LIB_FILES, NS, mocks)
    Loader.loadAll(rooted(TOC_FILES), NS, mocks)
    if initDB and NS.OnInitialize then pcall(NS.OnInitialize, NS) end
    -- Enable is NOT pcall-wrapped on purpose: a lifecycle throw (e.g. the
    -- IconGrid.Layout clobber) must surface to the calling test() so it's
    -- reported as a failure, not silently swallowed like OnInitialize.
    if enable and NS.__enableAll then
        NS:__enableAll()
        if mocks.__flushTimers then mocks.__flushTimers() end
    end
    return { NS = NS, mocks = mocks }
end

-- Shared instance most suites use (DB built once).
local shared = loadInstance(true)

-- ---------------------------------------------------------------------------
-- Suites (append new suites here as sprints add coverage)
-- ---------------------------------------------------------------------------
--
-- BASENAMES, no extension — the kit appends it. A declared suite with no file on disk is a hard
-- error, and a `tests/test_*.lua` that is not declared here is one too: Kit.run asserts the list
-- against the directory in both directions before it loads a single case.
local SUITES = {
    "test_util",
    "test_coresetup",
    "test_util_anchor",
    "test_constants",
    "test_state",
    "test_locale",
    "test_units",
    "test_schema",
    "test_database",
    "test_color_shape",
    "test_bus",
    "test_compat",
    "test_compat_api",
    "test_compat_debug",
    "test_debuglog",
    "test_debuglogsetup",
    "test_icongrid_layout",
    "test_icongrid_apply",
    "test_icongrid_visibility",
    "test_icongrid_render",
    "test_icongrid_curves",
    "test_icongrid_curve_link",
    "test_icongrid_buildlist",
    "test_icongrid_glowgate",
    "test_lifecycle",
    "test_unitlabel",
    "test_unitlabel_apply",
    "test_castbar",
    "test_castbar_helpers",
    "test_castbar_frame",
    "test_castbar_skin",
    "test_castbar_debug",
    "test_cooldowns",
    "test_cooldowns_gates",
    "test_settings_log",
    "test_settings_spells",
    "test_settings_spells_editor",
    "test_settings_widgets",
    "test_options_panel",
    "test_settings_refreshers",
    "test_flow_traces",
    "test_version",
    "test_slash_style",
    "test_slash",
    "test_opensettings",
    "test_perfsetup",
    "test_list_mode",
    "test_surface_parity",
    "test_vendor_sync",
}

_G.KICKCD_TEST = Kit.expose{
    root = root,
    -- shared instance
    NS = shared.NS,
    mocks = shared.mocks,
    -- fresh isolated instance for migration / bus / degradation tests
    load = loadInstance,
    -- The three lists testing-§9 makes assertable: the suite list, the derived library load list
    -- exactly as it was fed to the loader, and the TOC-derived addon list.
    suites = SUITES,
    libFiles = LIB_FILES,
    tocFiles = TOC_FILES,
    Loader = Loader,
}

Kit.run{ dir = root .. "/tests/", suites = SUITES }
