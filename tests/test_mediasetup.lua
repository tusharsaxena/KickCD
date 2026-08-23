-- tests/test_mediasetup.lua — core/MediaSetup.lua, the LibKa0s-Media-1.0 seam.
--
-- THE CASE THAT EARNS THIS FILE is the catalog cross-check. The art this addon's
-- windows draw is named as plain strings — here, and inside a library that lives
-- in ANOTHER REPO — and resolved against a catalog that repo owns. If the library
-- renames a mark, or a re-vendor drops a file, the answer is nil or a path to
-- nothing, the control quietly stops being the icon it was, and every suite stays
-- green: a texture that does not load draws nothing and raises nothing.
--
-- The font half matters for the same reason from the other direction. SetFont
-- accepts a path to a file that is not there and simply does not draw, so a
-- FONT_MONO that resolved to a dead path would be an empty debug console with no
-- error anywhere.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local NS, mocks = T.NS, T.mocks

local VENDORED = "Interface\\AddOns\\KickCD\\libs\\LibKa0s\\media\\"

-- The marks this addon puts on screen. It never calls NS.Icon itself: the two
-- seams that say who is asking — core/CoreSetup.lua's MakeCloseButton wrapper and
-- core/DebugLogSetup.lua's `addonName` — hand the folder name to the library, and
-- the library resolves these three names against ITS OWN catalog using it. Which
-- is precisely why they are pinned here rather than left implicit: nothing else in
-- this repo would notice `copy` being renamed upstream.
local DRAWN = { "close", "copy", "clear" }

-- ── the seam ────────────────────────────────────────────────────────────────

test("MediaSetup: NS.Icon answers the vendored path, extensionless", function()
    -- Extensionless is not a preference. The client appends the extension itself,
    -- and a path carrying `.tga` is one of the two spellings that draw nothing.
    assertEqual(NS.Icon("close"), VENDORED .. "icons\\close")
end)

test("MediaSetup: an icon the library does not ship answers nil", function()
    -- nil is a value a caller can branch on. A plausible path to a texture that is
    -- not there is a control that is simply absent, forever, silently.
    assertNil(NS.Icon("nosuchicon"))
end)

test("MediaSetup: NS.MediaFont answers the vendored face, and only a face it ships", function()
    assertEqual(NS.MediaFont("JetBrains Mono"),
        VENDORED .. "fonts\\JetBrainsMono-Regular.ttf")
    assertNil(NS.MediaFont("Comic Sans"))
end)

test("MediaSetup: the font this addon names is a face the library actually registers", function()
    -- Two names for one thing, in two repos. Const.FONT_MONO_NAME is the key
    -- LibSharedMedia is asked for; the library's FONTS is what RegisterLSM
    -- registers. A profile naming a key nobody registered renders in Blizzard's
    -- fallback face — the exact outcome shipping a monospace font was meant to
    -- prevent, and it says nothing on the way past.
    local Media = mocks.LibStub("LibKa0s-Media-1.0", true)
    assertTrue(Media ~= nil, "the vendored library did not load")
    assertTrue(Media.FONTS[NS.Const.FONT_MONO_NAME] ~= nil,
        "FONT_MONO_NAME is '" .. tostring(NS.Const.FONT_MONO_NAME)
        .. "', which the library's FONTS does not carry")
    assertEqual(NS.Const.FONT_MONO, NS.MediaFont(NS.Const.FONT_MONO_NAME))
end)

test("MediaSetup: the face is registered with LibSharedMedia at file load", function()
    -- AT LOAD, not at PLAYER_LOGIN: defaults/Profile.lua names fonts at load time
    -- too, and deferring would open a window in which a shipped default named a
    -- face LSM had never heard of.
    local LSM = mocks.LibStub("LibSharedMedia-3.0", true)
    assertTrue(LSM ~= nil, "the mock has no LibSharedMedia")
    assertEqual(LSM:Fetch("font", NS.Const.FONT_MONO_NAME), NS.Const.FONT_MONO)
end)

-- ── the catalog, against what this addon actually puts on screen ─────────────

test("MediaSetup: every mark this addon's windows draw is one the library ships", function()
    -- red under: any name here the catalog does not carry — an upstream rename, or
    -- a mark this addon asked for that was never shipped.
    local Media = mocks.LibStub("LibKa0s-Media-1.0", true)
    local known = {}
    for _, name in ipairs(Media.ICONS) do known[name] = true end
    for _, name in ipairs(DRAWN) do
        assertTrue(known[name] == true,
            "this addon draws '" .. name .. "', which LibKa0s-Media does not ship")
        assertTrue(NS.Icon(name) ~= nil, "NS.Icon answered nil for " .. name)
    end
end)

test("MediaSetup: every name the library ships has a file in the vendored copy", function()
    -- The library's own suite checks its catalog against its own directory. This
    -- checks THE COPY: a re-vendor that dropped a file, or a packaging step that
    -- filtered media/ out, leaves a catalog naming art this build does not carry.
    local Media = mocks.LibStub("LibKa0s-Media-1.0", true)
    local root = (T.root or ".") .. "/libs/LibKa0s/media/icons/"
    local missing = {}
    for _, name in ipairs(Media.ICONS) do
        local fh = io.open(root .. name .. ".tga", "rb")
        if fh then fh:close() else missing[#missing + 1] = name end
    end
    assertEqual(table.concat(missing, ", "), "")
end)

-- ── degraded ────────────────────────────────────────────────────────────────

test("MediaSetup: with no library there is no art and no face, and that is not an error", function()
    -- The art and the bytes of the font are INSIDE the payload that is missing, so
    -- a degraded install has neither. Both seams answer nil, which is what sends
    -- core/Constants.lua to the client's own STANDARD_TEXT_FONT and leaves the
    -- library's own controls on their multiplication sign.
    local inst = T.load(false, false, nil, { libFiles = {} })
    assertNil(inst.NS.Icon("close"))
    assertNil(inst.NS.MediaFont("JetBrains Mono"))
    assertTrue(inst.NS.Const.FONT_MONO ~= nil,
        "FONT_MONO must still be a usable face with no library")
    assertNil(inst.NS.Const.FONT_MONO:match("LibKa0s"),
        "the degraded fallback must be a real client font, never a dead vendored path")
end)
