-- tests/test_launcher.lua
-- LibKa0s-Launcher-1.0 wiring — the minimap button and the broker plugin.
--
-- launcher-§1 is written around ONE object registered twice, because the wiring
-- underneath is identical in eleven addons and written as two features it drifts
-- on the first behavior change (anti-pattern #81). So the cases here are about
-- the things that drift: that there is one object and not two, that it is keyed
-- by the FOLDER name (LibDBIcon saves the button's position under it), that the
-- table LibDBIcon holds IS the table the settings row writes, and that the left
-- button drives the addon's EXISTING switch rather than a copy of it.
--
-- testing-§8's four per-module obligations are here too: the descriptor is
-- well-formed, every declared seam is reached by a real call, the inversion is
-- exercised in both directions, and the degraded paths answer rather than
-- erroring. There are THREE degraded paths, not one — no LibKa0s, no
-- LibDataBroker-1.1, no LibDBIcon-1.0 — and only the first is this addon's own.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local FOLDER = "KickCD"

--- An instance whose mock client has neither broker library, built through the
--- `mutate` hook so they are gone BEFORE any source loads — the load order the
--- player with neither addon actually has.
local function withoutBrokers(...)
    local drop = { ... }
    return T.load(true, true, function(mocks)
        for _, name in ipairs(drop) do mocks.__libs[name] = nil end
    end)
end

local function dbicon(inst) return inst.mocks.__libs["LibDBIcon-1.0"] end
local function ldb(inst)    return inst.mocks.__libs["LibDataBroker-1.1"] end

--- Everything NS.Util.print emits while `fn` runs.
local function captured(inst, fn)
    local lines, real = {}, inst.NS.Util.print
    inst.NS.Util.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    inst.NS.Util.print = real
    if not ok then error(err, 0) end
    return lines
end

-- ── the object ──────────────────────────────────────────────────────────────

test("the launcher is ONE LibDataBroker object of type `launcher`, wearing the addon's own logo",
function()
    -- red under: `type = "data source"`, which promises a `text` value this
    -- object has not got, so a broker display draws an empty value cell beside
    -- the icon forever; or a Blizzard icon path / file id, anti-pattern #82.
    local inst = T.load(true, true)
    local obj = inst.NS.Launcher:Object()
    assertTrue(obj ~= nil, "Register must have built the broker object")
    assertEqual(obj.type, "launcher")
    assertEqual(obj.icon,
        "Interface\\AddOns\\KickCD\\media\\logos\\kickcd.logo.128.tga",
        "the icon MUST be the file ## IconTexture names (launcher-§4)")
    assertEqual(type(obj.OnClick), "function", "one click implementation, and it is the library's")
end)

test("the TOC's ## IconTexture and the launcher's icon are the SAME file", function()
    -- One file is the addon's face in three places — the AddOns list, the
    -- minimap button and a broker display — so a player who has seen the addon
    -- once recognizes it in all three (launcher-§4). Two spellings is two faces.
    -- red under: pointing either at Interface\Icons\ability_kick again
    local inst = T.load(true, true)
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local toc = fh:read("*a"); fh:close()
    local icon = toc:match("##%s*IconTexture:%s*([^\r\n]+)")
    assertTrue(icon ~= nil, "the TOC must declare ## IconTexture")
    assertEqual(icon, inst.NS.Launcher:Object().icon)
    assertNil(icon:match("^Interface\\Icons\\"),
        "a borrowed Blizzard icon makes the addon look like something else (anti-pattern #82)")
end)

test("the 128 logo is on disk, uncompressed 32-bit TGA at 128x128", function()
    -- A launcher whose icon file is missing, or is there in the wrong format,
    -- draws NOTHING and raises NOTHING — no gate in the client would report it,
    -- which is why this one is here (layout-§4, anti-pattern #82).
    -- red under: an RLE (type 10) export, a 24-bit one, or a 300x300 resize
    local fh = assert(io.open(T.root .. "/media/logos/kickcd.logo.128.tga", "rb"))
    local head = fh:read(18); fh:close()
    assertTrue(head ~= nil and #head == 18, "the file must carry a TGA header")
    local function b(i) return head:byte(i + 1) end
    assertEqual(b(2), 2, "TGA image type must be 2 (uncompressed true-color)")
    assertEqual(b(16), 32, "and 32 bits per pixel")
    assertEqual(b(12) + b(13) * 256, 128, "width")
    assertEqual(b(14) + b(15) * 256, 128, "height")
end)

test("it registers under the addon's FOLDER name, with the table the settings row writes",
function()
    -- Neither half is cosmetic. LibDBIcon keys the button's SAVED POSITION by
    -- the name, so a second spelling drops the angle the player dragged it to;
    -- and it writes `hide` and `minimapPos` into the table it was handed, so a
    -- copy would be two records of one state (launcher-§3, anti-pattern #81).
    -- red under: passing the ## Title, or capturing db.global.minimap at file load
    local inst = T.load(true, true)
    local reg = dbicon(inst).__registered[FOLDER]
    assertTrue(reg ~= nil, "LibDBIcon must hold a registration under the folder name")
    assertEqual(reg.object, inst.NS.Launcher:Object(), "the SAME object, not a second one")
    assertTrue(reg.db == inst.NS.db.global.minimap,
        "the SAME table — a captured one is the table AceDB later replaces")
end)

test("Register is idempotent: a second call builds no second button", function()
    -- A host may call it from OnInitialize and again from a login handler, and
    -- LibDBIcon's Register on a name it already holds would build a second
    -- button over the first.
    -- red under: dropping the library's `if object and iconLib then return true end`
    local inst = T.load(true, true)
    local L = inst.NS.Launcher
    local first = L:Object()
    assertTrue(L:IsRegistered(), "OnEnable must have registered it")
    assertTrue(L:Register(), "a second Register must answer true")
    assertEqual(L:Object(), first, "and hand back the same object")
    local n = 0
    for _ in pairs(ldb(inst).__objects) do n = n + 1 end
    assertEqual(n, 1, "exactly one broker object exists under this addon's name")
end)

-- ── the rung (launcher-§2) ──────────────────────────────────────────────────

test("LEFT click toggles the lock — rung (b), through the addon's own switch", function()
    -- KickCD has no primary window and its preview IS unlocking (options-ui-§15's
    -- exemption), so the left button toggles Lock frame. It must drive
    -- NS.ToggleLock — the same seam `/kcd toggle` and the Lock frame checkbox
    -- reach — and hold no copy of the state.
    -- red under: onClick writing db.profile.locked directly, or opening the panel
    local inst = T.load(true, true)
    local NS = inst.NS
    local click = NS.Launcher:Object().OnClick
    local before = NS.db.profile.locked
    captured(inst, function() click(nil, "LeftButton") end)
    assertEqual(NS.db.profile.locked, not before, "the left click must flip the lock")
    captured(inst, function() click(nil, "LeftButton") end)
    assertEqual(NS.db.profile.locked, before, "and flip it back")
end)

test("the left click goes through the SAME write seam the Lock frame checkbox does", function()
    -- options-ui-§1: one writer. Proven by swapping the seam out and watching
    -- the click arrive there, rather than by reading the source.
    -- red under: a second path to db.profile.locked anywhere in the launcher
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local seen, real = {}, H.SetAndRefresh
    H.SetAndRefresh = function(path, value)
        seen[#seen + 1] = { path, value }
        return real(path, value)
    end
    captured(inst, function() NS.Launcher:Object().OnClick(nil, "LeftButton") end)
    H.SetAndRefresh = real
    assertEqual(#seen, 1, "exactly one write")
    assertEqual(seen[1][1], "locked", "and it is the `locked` row's own path")
end)

test("RIGHT click opens the settings panel, whatever the left button does", function()
    -- The panel is therefore never more than one click away, which is what lets
    -- rung (b) spend the left button on the lock (launcher-§2).
    -- red under: onClick being consulted for the right button too
    local inst = T.load(true, true)
    local NS = inst.NS
    local opened, realOpen = 0, NS.OpenSettings
    NS.OpenSettings = function(self) opened = opened + 1; return realOpen(self) end
    local locked = NS.db.profile.locked
    captured(inst, function() NS.Launcher:Object().OnClick(nil, "RightButton") end)
    NS.OpenSettings = realOpen
    assertEqual(opened, 1, "right click must open the panel")
    assertEqual(NS.db.profile.locked, locked, "and must NOT touch the lock")
end)

-- ── the Minimap button row (launcher-§3) ────────────────────────────────────

test("the row's get INVERTS LibDBIcon's `hide`, so the label can say shown", function()
    -- There is one boolean and the library writes it too, from its own
    -- right-click menu; a second `minimap.show` beside it would be free to
    -- disagree (anti-pattern #81). The cost is this inversion.
    -- red under: reading db.global.minimap.hide straight into the checkbox
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    inst.NS.db.global.minimap.hide = false
    assertEqual(H.Get("global.minimap.hide"), true, "hidden=false reads as SHOWN")
    inst.NS.db.global.minimap.hide = true
    assertEqual(H.Get("global.minimap.hide"), false, "hidden=true reads as not shown")
end)

test("the row's set inverts AND moves the button, in the one write seam", function()
    -- launcher-§3 wants the button to follow the checkbox immediately rather
    -- than at the next reload, and wants that to happen on the addon's single
    -- write seam like every other row (options-ui-§1).
    -- red under: writing `hide` without calling LibDBIcon, or vice versa
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("global.minimap.hide", false)
    assertEqual(inst.NS.db.global.minimap.hide, true, "unticked stores hide = true")
    assertFalse(dbicon(inst).__shown[FOLDER], "and hides the button now, not at reload")
    assertFalse(inst.NS.Launcher:IsShown())
    H.SetAndRefresh("global.minimap.hide", true)
    assertEqual(inst.NS.db.global.minimap.hide, false, "ticked stores hide = false")
    assertTrue(dbicon(inst).__shown[FOLDER], "and shows it again")
    assertTrue(inst.NS.Launcher:IsShown())
end)

test("`/kcd set global.minimap.hide` takes exactly the path the checkbox takes", function()
    -- The CLI and the panel are two surfaces over one writer, which is the
    -- whole of options-ui-§1 — and the reason the composed row is addressable
    -- by its verbatim global path at all.
    -- red under: a CLI branch of its own for the global store
    local inst = T.load(true, true)
    captured(inst, function() inst.NS:OnSlashCommand("set global.minimap.hide false") end)
    assertEqual(inst.NS.db.global.minimap.hide, true)
    assertFalse(dbicon(inst).__shown[FOLDER])
end)

test("`Reset all settings` does NOT un-hide a button the player hid", function()
    -- It is a PROFILE reset by definition (options-ui-§12), and the minimap
    -- table is GLOBAL precisely so the reset cannot reach past the settings it
    -- warned about into the frame furniture (launcher-§3).
    -- red under: storing the table under db.profile, or marking the row sessionOnly
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("global.minimap.hide", false)
    captured(inst, function() H.RestoreAllDefaults() end)
    assertEqual(inst.NS.db.global.minimap.hide, true, "the button stays hidden")
end)

test("a profile switch does not move the player's button", function()
    -- A minimap button belongs to the INSTALLATION, not to a profile: the ring
    -- of buttons is furniture the player arranged once (launcher-§3).
    -- red under: db.profile.minimap
    local inst = T.load(true, true)
    inst.NS.Settings.Helpers.SetAndRefresh("global.minimap.hide", false)
    inst.NS.db:SetProfile("a-second-profile")
    assertEqual(inst.NS.db.global.minimap.hide, true)
end)

-- ── degradation (testing-§8) ────────────────────────────────────────────────

test("a host with NEITHER broker library loads, and says so instead of raising", function()
    -- The library resolves both with LibStub(..., true) at Register time and
    -- degrades BY NAME. A hard dependency here would take the host out over a
    -- library that is optional to everything but the button.
    -- red under: LauncherSetup testing for either library itself, or a raise
    local inst = withoutBrokers("LibDataBroker-1.1", "LibDBIcon-1.0")
    local L = inst.NS.Launcher
    assertTrue(L ~= nil, "the seam must still be published")
    assertFalse(L:IsRegistered())
    assertNil(L:Object())
    -- And the row still answers, so the checkbox is not a raise inside `/kcd set`.
    local H = inst.NS.Settings.Helpers
    assertEqual(H.Get("global.minimap.hide"), true)
    H.SetAndRefresh("global.minimap.hide", false)
    assertEqual(inst.NS.db.global.minimap.hide, true, "the store still records the choice")
end)

test("a host with the broker but no LibDBIcon still gets the plugin, and reports false", function()
    -- The honest answer: the section's headline surface, the button, is not
    -- there, but a broker display will still show the addon.
    -- red under: treating LibDBIcon's absence as total failure and dropping the object
    local inst = withoutBrokers("LibDBIcon-1.0")
    local L = inst.NS.Launcher
    assertTrue(L:Object() ~= nil, "the broker object must still exist")
    assertFalse(L:IsRegistered(), "but the launcher is not fully wired")
end)

test("with LibKa0s absent the seam still answers, and the store still records the choice",
function()
    -- The stub is LOAD-COMPLETING, not silent: settings/Panel.lua's write seam
    -- calls NS.Launcher:SetShown on every `global.minimap.hide` write, so a nil
    -- here would be a raise inside `/kcd set` rather than a missing button.
    -- red under: `NS.Launcher = Launcher and Launcher:New(...)`
    local inst = T.load(true, true, nil, { libFiles = {} })
    local L = inst.NS.Launcher
    assertTrue(L ~= nil, "NS.Launcher must exist with no library at all")
    assertFalse(L:Register())
    assertFalse(L:IsRegistered())
    assertNil(L:Object())
    assertTrue(L:IsShown(), "default is SHOWN")
    L:SetShown(false)
    assertEqual(inst.NS.db.global.minimap.hide, true)
    assertFalse(L:IsShown())
end)

test("the degraded stub carries every member the addon calls on the launcher", function()
    -- A stub that omits one is not a fallback, it is a crash moved to a rarer
    -- code path (the sentence core/DebugLogSetup.lua's stub joined the list
    -- under). Checked against the LIVE instance rather than a typed list, so the
    -- next member a re-vendor adds is caught here.
    -- red under: a new Launcher member reached by host code and not stubbed
    local live = T.load(true, true).NS.Launcher
    local stub = T.load(true, true, nil, { libFiles = {} }).NS.Launcher
    for name, v in pairs(live) do
        if type(v) == "function" then
            assertEqual(type(stub[name]), "function",
                "the stub owes `" .. name .. "`")
        end
    end
end)
