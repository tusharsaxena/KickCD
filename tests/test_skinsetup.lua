-- tests/test_skinsetup.lua — the LibKa0s-Skin-1.0 seam (core/SkinSetup.lua, skinning-§1, §2, §3).
--
-- What this addon owes the skin engine, and nothing the library pins itself: the owner is
-- registered under the folder name with this addon's read and write seams; the seven skin.* keys
-- default to Ka0s Default and are skipRender schema rows on the General page's Skin tab; the
-- profile's skin, Scope and overrides are applied right after AceDB exists and on every profile
-- event; one `/kcd set` is one repaint; and the owner reaches every library factory that builds a
-- frame for KickCD.
--
-- On its own instance, so a skin moved here never leaks into the shared one later suites read.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local inst = T.load(true, true)
local NS, mocks = inst.NS, inst.mocks
local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "KickCD"

-- ONE listener for the whole file: the library keeps a listener for the session, so each case
-- resets the counter instead of registering again.
local looks = 0
NS.Skin.OnLooksChanged(function() looks = looks + 1 end)

--- Run a slash line with chat silenced.
local function quiet(line)
    local cf = mocks.DEFAULT_CHAT_FRAME
    local add = cf.AddMessage
    cf.AddMessage = function() end
    local ok, err = pcall(NS.OnSlashCommand, NS, line)
    cf.AddMessage = add
    if not ok then error(err, 0) end
end

--- Back on Ka0s Default with the Scope's defaults, stored and applied, the counter cleared.
local function reset()
    NS.WriteSkinChoice("ka0s", "ka0s", { panel = true, fonts = false }, { font = false, texture = false })
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    Skin:SetIgnore(OWNER, true, false)
    Skin:SetOverride(OWNER, false, false)
    if mocks.__fireTimers then mocks.__fireTimers() end
    looks = 0
end

local function clean(fn)
    return function()
        reset()
        local ok, err = pcall(fn)
        reset()
        if not ok then error(err, 0) end
    end
end

-- ── the owner ────────────────────────────────────────────────────────────────────────────────

test("Skin seam: the owner is the folder name, and NS.Skin is its facade", function()
    -- red under: registering under the brand or a typo (the library keys every frame and every
    -- listener by owner), or publishing a facade of some other owner.
    assertTrue(Skin:IsOwner(OWNER), "core/SkinSetup.lua did not register the owner")
    assertTrue(rawequal(NS.Skin, Skin:For(OWNER)), "NS.Skin is not Skin:For(\"KickCD\")")
    assertEqual(NS.Skin.owner, OWNER)
    assertEqual(Skin:OwnerLabel(OWNER), "Ka0s KickCD", "the copy confirmation names the addon by its brand")
end)

test("Skin seam: the read answers Ka0s Default before the profile store exists", function()
    -- RegisterOwner calls `get` at FILE LOAD, before Database:Init; a getter that raised there
    -- would be a visible Lua error on every login.
    local db = NS.db
    NS.db = nil
    local ok, source, skin = pcall(NS.SkinChoice)
    NS.db = db
    assertTrue(ok, "NS.SkinChoice raised without a store: " .. tostring(source))
    assertEqual(source, "ka0s")
    assertEqual(skin, "ka0s")
end)

-- ── the keys and the rows ────────────────────────────────────────────────────────────────────

test("Skin seam: the eight skin keys default to Ka0s Default, today's Scope and All text", function()
    -- red under: a default other than today's look, or pickerSeen true (owner ruling O3: the
    -- first-run picker shows once on every profile, old and new).
    local d = NS.DEFAULT_PROFILE.skin
    assertEqual(d.source, "ka0s")
    assertEqual(d.skin, "ka0s")
    assertEqual(d.ignorePanel, true)
    assertEqual(d.ignoreFonts, false)
    assertEqual(d.font, "")
    assertEqual(d.texture, "")
    assertEqual(d.outline, "all", "the Font outline: All text, the library's default (D-06)")
    assertEqual(d.pickerSeen, false)
end)

test("Skin seam: every skin key is a skipRender row of the General page's Skin tab", function()
    local Store = NS.Settings.Store
    assertEqual(#NS.SKIN_PATHS, 8, "eight stored keys")
    for _, path in ipairs(NS.SKIN_PATHS) do
        local row = Store.FindRow(path)
        assertTrue(row ~= nil, path .. " is not a schema row")
        assertEqual(row.panel, "general", path .. ": panel")
        assertEqual(row.group, "Appearance", path .. ": the library tab's key")
        assertTrue(row.skipRender == true, path .. ": the tab draws it, so it must be skipRender")
    end
end)

test("Skin seam: the skin row's values are every registered skin, in the library's order", function()
    local skins = Skin:Skins()
    assertEqual(#NS.SKIN_ORDER, #skins, "one value per registered skin")
    for i, def in ipairs(skins) do
        assertEqual(NS.SKIN_ORDER[i], def.key, "value " .. i)
        assertTrue(NS.SKIN_VALUES[def.key] ~= nil, def.key .. " has a label")
    end
    assertEqual(NS.SKIN_ORDER[1], "ka0s", "Ka0s Default first")
end)

-- ── the write seam and the CLI ───────────────────────────────────────────────────────────────

test("Skin seam: /kcd set refuses an unregistered skin and applies a registered one", clean(function()
    quiet("set skin.skin no-such-skin")
    assertEqual(NS.db.profile.skin.skin, "ka0s", "an unknown skin was stored")
    assertEqual(looks, 0, "a refused set repainted")
    quiet("set skin.skin obsidian")
    assertEqual(NS.db.profile.skin.skin, "obsidian", "a registered skin was refused")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "obsidian", "a bare set must move the applied skin")
    assertEqual(looks, 1, "one set, one repaint")
end))

test("Skin seam: the registered setter writes through the store, and a copy repaints once", clean(function()
    -- The library's copy to every Ka0s addon calls SetChoice for this owner, then WriteChoice,
    -- which reaches NS.WriteSkinChoice; each row's onChange then finds its half applied already.
    Skin:SetChoice(OWNER, "ka0s", "ember")
    assertTrue(Skin:WriteChoice(OWNER, "ka0s", "ember"), "the copy's write did not reach this addon's setter")
    assertEqual(looks, 1, "a copy must repaint this addon exactly once")
    assertEqual(NS.db.profile.skin.skin, "ember", "the copy did not land in the profile")
end))

test("Skin seam: /kcd set reaches an exception, and only its own half", clean(function()
    quiet("set skin.ignoreFonts true")
    local panel, fonts = Skin:GetIgnore(OWNER)
    assertEqual(fonts, true, "the set applied")
    assertEqual(panel, true, "the other half untouched")
end))

test("Skin seam: /kcd set reaches an override, and an empty one is the skin's own", clean(function()
    quiet("set skin.texture Solid")
    local _, texture = Skin:GetOverride(OWNER)
    assertEqual(texture, "Solid", "the texture override applied")
    NS.Settings.Store.Set("skin.texture", "")
    _, texture = Skin:GetOverride(OWNER)
    assertTrue(not texture, "an empty override clears to the skin's own")
end))

-- ── the profile events ───────────────────────────────────────────────────────────────────────

test("Skin seam: a profile switch applies the new profile's skin, Scope and overrides", clean(function()
    local db = NS.db
    local ok, err = pcall(function()
        db:SetProfile("SkinProbe")
        db.profile.skin.skin = "glass"
        db.profile.skin.ignoreFonts = true
        db.profile.skin.font = "Friz Quadrata TT"
        db:SetProfile("Default")
        assertEqual(select(2, Skin:GetChoice(OWNER)), "ka0s", "back on Default, Default's skin")
        looks = 0
        db:SetProfile("SkinProbe")
        assertEqual(select(2, Skin:GetChoice(OWNER)), "glass", "the switch did not move the applied skin")
        assertEqual(select(2, Skin:GetIgnore(OWNER)), true, "the stored fonts exception")
        assertEqual((Skin:GetOverride(OWNER)), "Friz Quadrata TT", "the stored font override")
        assertTrue(looks >= 1, "the switch repainted")
    end)
    if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
    if db.DeleteProfile then pcall(db.DeleteProfile, db, "SkinProbe", true) end
    if not ok then error(err, 0) end
end))

test("Skin seam: a profile reset takes the skin back to Ka0s Default", clean(function()
    NS.Settings.Store.Set("skin.skin", "obsidian")
    NS.db:ResetProfile()
    assertEqual(NS.db.profile.skin.skin, "ka0s")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "ka0s", "the reset did not repaint to Ka0s Default")
end))

-- ── the owner handed to the library's factories ──────────────────────────────────────────────

test("Skin seam: every LibKa0s-Widgets factory call names the owner", function()
    -- red under: a new DragHandle / TestStrip / ReorderList built unowned, which the library paints
    -- in no addon's skin. A source scan: the descriptor's first lines carry `owner = addonName`.
    local SITES = {
        { "modules/Castbar_Handle.lua", "KW%.DragHandle%(" },
        { "modules/IconGrid_Handle.lua", "KW%.DragHandle%(" },
        { "settings/Spells.lua", "W%.ReorderList%s*{" },
        { "modules/Sim.lua", "Lib:New%(" },
    }
    for _, site in ipairs(SITES) do
        local fh = assert(io.open(T.root .. "/" .. site[1], "r"))
        local src = fh:read("*a")
        fh:close()
        local at = src:find(site[2])
        assertTrue(at ~= nil, site[1] .. ": the factory call moved; update this list")
        local head = src:sub(at, at + 400)
        assertTrue((head:find("owner%s*=%s*addonName") or head:find("name%s*=%s*addonName")) ~= nil, site[1] .. ": the factory is not handed the owner")
    end
end)

test("Skin seam: the debug console, its copy window and the perf panel take the owner from addonName", function()
    -- red under: a descriptor that drops `addonName` (KC-04). LibKa0s-DebugLog and -Perf take the
    -- skin owner from the descriptor's `addonName` (the console's copy window with it), so a
    -- descriptor without it would paint those windows in no addon's skin. A source scan of each
    -- descriptor's body, up to its closing `})`.
    for _, site in ipairs({
        { "core/DebugLogSetup.lua", "NS%.DebugLog = lib:New%(" },
        { "core/PerfSetup.lua", "NS%.Perf = lib:New%(" },
    }) do
        local fh = assert(io.open(T.root .. "/" .. site[1], "r"))
        local src = fh:read("*a")
        fh:close()
        local at = src:find(site[2])
        assertTrue(at ~= nil, site[1] .. ": the descriptor moved; update this list")
        local stop = src:find("\n})", at, true)
        assertTrue(stop ~= nil, site[1] .. ": the descriptor's end was not found")
        local body = src:sub(at, stop)
        assertTrue(body:find("\n%s*addonName%s*=%s*addonName") ~= nil,
            site[1] .. ": the descriptor does not carry addonName = addonName")
    end
end)
