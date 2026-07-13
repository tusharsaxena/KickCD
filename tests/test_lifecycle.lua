-- tests/test_lifecycle.lua — module OnEnable / lifecycle coverage (§14A.1)
--
-- Closes the harness blind spot that let the IconGrid.Layout method-vs-table
-- clobber (KCD-05) ship green: a load-only harness runs OnInitialize and stops,
-- never reaching the OnEnable cascade AceAddon fires on PLAYER_LOGIN — the exact
-- path where self:Layout() blew up in-game. These tests load a FRESH instance
-- and run that cascade (T.load(true, true)) so every module's OnEnable executes
-- headlessly, then assert the bus wiring OnEnable is supposed to install.
local T = _G.KICKCD_TEST
local test, assertTrue, assertEqual = T.test, T.assertTrue, T.assertEqual

-- Modules that define OnEnable (grep: core/ modules/ for "function .*:OnEnable").
-- Keep this list in lockstep with the addon so a newly-added lifecycle module
-- is deliberately wired into coverage rather than silently skipped.
local LIFECYCLE_MODULES = { "IconGrid", "Cooldowns", "Castbar" }

-- IconGrid's closed-list subscriptions (modules/IconGrid.lua:OnEnable). If the
-- Layout method were clobbered, OnEnable would throw at self:Layout() BEFORE
-- reaching these RegisterMessage calls, so their presence double-proves OnEnable
-- ran to completion.
local ICONGRID_MESSAGES = {
    "Ka0s_KickCD_SPELL_STATE",
    "Ka0s_KickCD_CONFIG_CHANGED",
    "Ka0s_KickCD_PROFILE_CHANGED",
    "Ka0s_KickCD_COMBAT_STATE",
}

test("addon + all modules enable cleanly on the Ace3 login path", function()
    -- Any OnEnable throwing (Layout clobber, nil method, bad message name)
    -- propagates out of __enableAll and fails this test with the real error.
    local inst = T.load(true, true)
    assertTrue(inst.NS ~= nil, "addon namespace must load")
    for _, name in ipairs(LIFECYCLE_MODULES) do
        local m = inst.NS:GetModule(name)
        assertTrue(m ~= nil, name .. " module must exist")
        assertEqual(m.enabledState, true, name .. " must be enabled after the cascade")
    end
end)

test("IconGrid:OnEnable installs its bus subscriptions", function()
    local inst = T.load(true, true)
    local reg = inst.mocks.__busRegistry
    local ig = inst.NS:GetModule("IconGrid")
    for _, msg in ipairs(ICONGRID_MESSAGES) do
        assertTrue(reg[msg] and reg[msg][ig] ~= nil,
            "IconGrid must be subscribed to " .. msg .. " after OnEnable")
    end
end)

test("Cooldowns and Castbar subscribe to CONFIG_CHANGED after enable", function()
    local inst = T.load(true, true)
    local reg = inst.mocks.__busRegistry["Ka0s_KickCD_CONFIG_CHANGED"]
    assertTrue(reg ~= nil, "CONFIG_CHANGED must have subscribers")
    assertTrue(reg[inst.NS:GetModule("Cooldowns")] ~= nil, "Cooldowns must subscribe to CONFIG_CHANGED")
    assertTrue(reg[inst.NS:GetModule("Castbar")] ~= nil, "Castbar must subscribe to CONFIG_CHANGED")
end)

test("post-enable CONFIG_CHANGED re-layout runs end-to-end without error", function()
    -- Fans out to every subscriber's handler, which re-run IconGrid:Layout /
    -- Castbar:Reskin against the live (mock) frames — the same self:Layout()
    -- call sites (IconGrid.lua:627/633/661) the crash hid behind.
    local inst = T.load(true, true)
    inst.NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "icons" })
    inst.NS:SendMessage("Ka0s_KickCD_PROFILE_CHANGED")
    if inst.mocks.__flushTimers then inst.mocks.__flushTimers() end
end)
