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
--- @return table env  the sandbox global table (env.KickCD is the namespace pre-migration)
--- @return table NS   the private namespace table passed as the 2nd vararg
local function loadAll(root, mocks)
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

    for _, rel in ipairs(readTOCOrder(root)) do
        local path = root .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("loader: failed to load " .. rel .. ": " .. tostring(err)) end
        setfenv(chunk, env)
        local ok, perr = pcall(chunk, ADDON_NAME, NS)
        if not ok then error("loader: error executing " .. rel .. ": " .. tostring(perr)) end
    end

    return env, NS
end

return {
    ADDON_NAME = ADDON_NAME,
    readTOCOrder = readTOCOrder,
    loadAll = loadAll,
}
