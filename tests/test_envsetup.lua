-- tests/test_envsetup.lua — core/EnvSetup.lua, the LibKa0s-Env-1.0 seam.
--
-- What is asserted here is THE SEAM, not the library. The library's own suite covers the ladder
-- inside GetAddOnMetadata, and a second copy of those cases here is exactly the consumer-side
-- duplication testing-§8 forbids. What only THIS repo can check is that the seam answers what the
-- three inline copies it replaced answered, that it is bound to this addon's own folder name, and
-- that a fourth inline copy cannot appear without a case going red.
--
-- THE COPIES THIS REPLACED WERE INLINE. Not one of them was in core/Compat.lua — they sat in
-- core/KickCD.lua, core/PerfSetup.lua and settings/Slash.lua, which is why an audit of the shim
-- files across the collection counted six copies when there were eleven. That is also why this
-- file has no "the shim is gone from Compat" case: this addon's Compat never carried one.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local NS, mocks = T.NS, T.mocks

-- The three files that each carried their own copy of the C_AddOns ladder.
local FORMER_COPIES = { "core/KickCD.lua", "core/PerfSetup.lua", "settings/Slash.lua" }

test("EnvSetup: NS.Meta reads THIS addon's TOC manifest", function()
    -- The binding, not the ladder. LibKa0s is VENDORED and cannot know which folder it was copied
    -- into, so the seam hands it `addonName` — the first vararg, which is the FOLDER name and not
    -- the "[KCD]" prefix or the "Ka0s KickCD" title. A wrong name reads another addon's manifest,
    -- or none, and answers nil without raising a thing. `## Title` is the field that catches it:
    -- it is this addon's alone, where a version number could belong to anything.
    assertEqual(NS.Meta("Title"), "Ka0s KickCD")
end)

test("EnvSetup: the TOC version and the in-code stamp cannot drift", function()
    -- Two spellings of one fact, in two files. The whole reason every call site prefers the
    -- manifest (slash-commands-§3) is that the packager stamps it; NS.VERSION is the constant
    -- somebody has to remember to edit. This is what notices when only one of them was.
    assertEqual(NS.Meta("Version"), NS.VERSION)
end)

test("EnvSetup: NS.Version answers the TOC version", function()
    assertEqual(NS.Version(), NS.Meta("Version"))
end)

test("EnvSetup: NS.Version falls back to this addon's own NS.VERSION stamp", function()
    -- The fallback lives at the call site rather than in the library, because which constant this
    -- addon falls back to is genuinely its own business — so it is the seam's job to prove it still
    -- works. Reached by removing the reader, which is what a client that cannot answer looks like
    -- (an older client, or the headless harness before the mock grew a manifest reader).
    local saved = mocks.C_AddOns
    mocks.C_AddOns = nil
    local ok, v = pcall(NS.Version)
    mocks.C_AddOns = saved
    assertTrue(ok, "NS.Version raised with no metadata reader: " .. tostring(v))
    assertEqual(v, NS.VERSION)
    assertTrue(v ~= nil and v ~= "", "a version string, never nil — it goes straight into a banner")
end)

test("EnvSetup: no file inlines its own C_AddOns ladder any more", function()
    -- The three copies this seam replaced were INLINE, which is why no audit of core/Compat.lua
    -- ever found them. This case is the only thing that stops a fourth appearing.
    local hits = 0
    for _, path in ipairs(FORMER_COPIES) do
        local f = assert(io.open((T.root or ".") .. "/" .. path))
        local body = f:read("*a"); f:close()
        local _, n = body:gsub("C_AddOns%s*and%s*C_AddOns%.GetAddOnMetadata", "")
        hits = hits + n
    end
    assertEqual(hits, 0, "the ladder belongs in core/EnvSetup.lua and nowhere else")
end)

test("EnvSetup: with no LibKa0s the seam still reads this addon's own TOC", function()
    -- Exercised by a REAL load with the library absent rather than by stubbing the member under
    -- test (testing-§8), the same way tests/test_mediasetup.lua checks its degraded path. The two
    -- seams degrade differently and both are correct: Media has nothing to fall back TO, because
    -- the art is inside the missing payload, while the TOC is this addon's own file and was being
    -- read here long before LibKa0s existed. A degraded install must therefore still get its real
    -- version, not "?" — the number goes into a chat banner and a perf capture record, and a
    -- record that cannot name its own build is unattributable the moment it leaves the session.
    local inst = T.load(false, false, nil, { libFiles = {} })
    assertTrue(inst.mocks.LibStub("LibKa0s-Env-1.0", true) == nil, "the library was still loaded")
    assertEqual(inst.NS.Meta("Title"), "Ka0s KickCD")
    assertEqual(inst.NS.Version(), inst.NS.VERSION)

    -- And with the reader gone too — an older client, which is the bottom rung of the ladder the
    -- three inline copies ran — the in-code stamp, still never nil.
    local saved = inst.mocks.C_AddOns
    inst.mocks.C_AddOns = nil
    local v = inst.NS.Version()
    inst.mocks.C_AddOns = saved
    assertEqual(v, inst.NS.VERSION)
end)
