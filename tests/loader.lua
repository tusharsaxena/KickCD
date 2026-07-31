-- tests/loader.lua
-- Headless source loader (§14A.1).
--
-- Builds ONE shared sandbox env for a run and loads every addon source into
-- it in TOC order. WoW globals resolve to the mock table first, falling back
-- to the real _G. The sandbox's `_G` is the env itself, so the addon's
-- `_G.KickCD = addon` rebind and later `_G.KickCD` reads all see the same
-- object. Each chunk is called as chunk(addonName, NS), reproducing the
-- `local addonName, NS = ...` header (harmless for the pre-migration sources
-- that still use the global `KickCD`).

local ADDON_NAME = "KickCD"

-- The vendored library files, in libs/LibKa0s/LibKa0s.xml's own order.
--
-- Spelled out rather than derived from the TOC, because the TOC pulls the whole
-- module in through that one .xml and readTOCOrder below deliberately skips
-- `libs/`. testing-§9 requires the list to be explicit AND pinned: a library
-- file omitted here makes the dependent major refuse to register (its Core floor
-- is unmet), the host's setup file falls back to its stub, and the suite happily
-- measures the stub — green, and testing nothing. tests/test_coresetup.lua
-- compares this list against the XML file for file so the omission cannot happen
-- quietly.
--
-- Order matters and is not alphabetical: Core registers first because the other
-- four `return` before LibStub:NewLibrary without it, and the two Options attach
-- files must follow their shell.
local LIB_FILES = {
    "libs/LibKa0s/Core.lua",
    "libs/LibKa0s/DebugLog.lua",
    "libs/LibKa0s/Slash.lua",
    "libs/LibKa0s/Options.lua",
    "libs/LibKa0s/OptionsWidgets.lua",
    "libs/LibKa0s/OptionsScroll.lua",
    "libs/LibKa0s/Perf.lua",
    "libs/LibKa0s/PerfPanel.lua",
}

--- Parse the addon .lua sources out of the TOC, in load order, skipping
--- libs and .xml. Keeps the harness in lockstep with the real load order.
local function readTOCOrder(root)
    local toc = assert(io.open(root .. "/KickCD.toc", "r"))
    local order = {}
    for line in toc:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local path = line:gsub("\\", "/")
            if path:match("%.lua$") and not path:match("^libs/") then
                order[#order + 1] = path
            end
        end
    end
    toc:close()
    return order
end

--- Build a fresh sandbox env backed by `mocks`, then load every source.
--- @param root string  repo root
--- @param mocks table  from wow_mock.build()
--- @param opts table|nil  { libFiles = { ... } } overrides the vendored library
---        load list. Pass `{}` to load the addon with LibKa0s ABSENT — the
---        degraded scenario debug-logging-§7 and testing-§8 require to be
---        exercised by a real load rather than by hand-stubbing the member
---        under test.
--- @return table env  the sandbox global table (env.KickCD is the namespace pre-migration)
--- @return table NS   the private namespace table passed as the 2nd vararg
local function loadAll(root, mocks, opts)
    local realG = _G
    local env = {}
    local NS = {}   -- private namespace (post-KCD-01 target); pre-migration sources ignore it
    setmetatable(env, {
        __index = function(_, k)
            local v = mocks[k]
            if v ~= nil then return v end
            return realG[k]
        end,
    })
    env._G = env

    local function runFile(rel, ...)
        local path = root .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("loader: failed to load " .. rel .. ": " .. tostring(err)) end
        setfenv(chunk, env)
        local ok, perr = pcall(chunk, ...)
        if not ok then error("loader: error executing " .. rel .. ": " .. tostring(perr)) end
    end

    -- Libraries first, exactly as the client loads them: the TOC's `# Libraries`
    -- block precedes every addon file. A library chunk takes no arguments — the
    -- `local addonName, NS = ...` header is an addon convention — so these are
    -- called bare rather than with the namespace.
    local libFiles = (opts and opts.libFiles) or LIB_FILES
    for _, rel in ipairs(libFiles) do runFile(rel) end

    for _, rel in ipairs(readTOCOrder(root)) do
        runFile(rel, ADDON_NAME, NS)
    end

    return env, NS
end

return {
    ADDON_NAME = ADDON_NAME,
    LIB_FILES = LIB_FILES,
    readTOCOrder = readTOCOrder,
    loadAll = loadAll,
}
