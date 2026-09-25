-- tests/test_launcher.lua
-- LibKa0s-Launcher-1.0 wiring — the minimap button and the broker plugin.
--
-- launcher-§1 is written around ONE object registered twice, because the wiring
-- underneath is identical in eleven addons and written as two features it drifts
-- on the first behavior change (anti-pattern #81). So the cases here are about
-- the things that drift: that there is one object and not two, that it is keyed
-- by the FOLDER name (LibDBIcon saves the button's position under it), that the
-- table LibDBIcon holds IS the table the settings row writes, and that each
-- options-menu entry drives the addon's EXISTING switch rather than a copy of it.
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

test("the broker label is the BRAND NAME in plain text, `Ka0s KickCD`", function()
    -- launcher-§1 (v2.54.0). `label` is what a broker display prints in its own
    -- row, beside the other ten Ka0s addons, so it is the one field that decides
    -- whether the collection reads as one collection in Titan Panel. Across eleven
    -- adoptions it came out three ways -- "Absorb Tracker", "Ka0s KickCD",
    -- "Ka0s Pretty Chat" -- and a display sorting alphabetically files the odd one
    -- under A while the rest sit together under K.
    -- red under: the folder name, an ad-hoc spelling, or anything wired to the Title
    local obj = T.load(true, true).NS.Launcher:Object()
    assertEqual(obj.label, "Ka0s KickCD")
    assertNil(obj.label:find("|", 1, true),
        "no escape sequence of any kind -- a Title carrying one splatters across a broker row")
    assertTrue(obj.label ~= FOLDER, "the folder name is `name`, not `label` (anti-pattern #84)")
end)

test("`label` and the TOC's ## Title are NOT wired to each other", function()
    -- They read the same here, which is exactly when a host is tempted to derive
    -- one from the other. launcher-§1 forbids it because a Title MAY carry color
    -- escapes: Ka0s Pretty Chat's does, and the day this addon's Title grows one
    -- the broker row would inherit it silently.
    -- red under: label = GetAddOnMetadata(name, "Title"), or a shared constant
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local toc = fh:read("*a"); fh:close()
    assertTrue(toc:match("##%s*Title:%s*([^\r\n]+)") ~= nil, "the TOC must declare a Title")
    local src = assert(io.open(T.root .. "/core/LauncherSetup.lua", "r"))
    local body = src:read("*a"); src:close()
    assertTrue(body:find('label = "Ka0s KickCD"', 1, true) ~= nil,
        "the label must be a plain literal in the descriptor")
    assertNil(body:match('label%s*=%s*[^"\r\n]*Metadata'),
        "the label must not be read off the TOC")
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

-- ── the two buttons (launcher-§2, standard v2.67.0; Launcher version 4) ─────
--
-- The LIBRARY owns both buttons: left-click opens the settings panel in either
-- state, right-click opens the client's context menu built from the pairs this
-- addon passes. What is ours is WHICH pairs, and what each toggle calls. KickCD
-- has two states the menu can show, Enabled and Locked (WowAddonStandards
-- ADDONS.md's row): no Test mode, since unlocking IS the preview
-- (options-ui-§15's exemption), and no primary window. Each toggle is the SAME
-- function the slash verb runs: Enabled -> NS.SetMasterEnabled (`/kcd enable` /
-- `disable`), Locked -> NS.ToggleLock (`/kcd toggle`).

-- The library's own MenuUtil stand-in (LibKa0s tests/mock_menu.lua, copied whole).
local MockMenu = assert(loadfile(T.root .. "/tests/mock_menu.lua"))()

--- Install the fake context-menu API into THIS instance's client. Resolved by
--- the library at click time, so installing after the load is enough.
local function menuFor(inst) return MockMenu(inst.mocks) end

-- A stand-in for the minimap button the client hands OnClick as its owner.
local OWNER = { __name = "LibDBIcon10_KickCD" }

--- Right-click, and the menu it opened (nil when none did).
local function rightClick(inst, menu)
    menu.reset()
    captured(inst, function() inst.NS.Launcher:Object().OnClick(OWNER, "RightButton") end)
    return menu.last
end

--- Count NS:OpenSettings calls while `fn` runs.
local function countOpens(inst, fn)
    local NS = inst.NS
    local opened, realOpen = 0, NS.OpenSettings
    NS.OpenSettings = function(self) opened = opened + 1; return realOpen(self) end
    local ok, err = pcall(fn)
    NS.OpenSettings = realOpen
    if not ok then error(err, 0) end
    return opened
end

test("LEFT click opens the settings panel and touches nothing else", function()
    -- launcher-§2 (v2.67.0): the left button opens settings on every addon. The
    -- rung (b) lock toggle it used to run is now the menu's Locked entry.
    -- red under: an onClick the library still honored, or a left click that writes
    local inst = T.load(true, true)
    local NS = inst.NS
    local locked, enabled = NS.db.profile.locked, NS.db.profile.enabled
    local opened = countOpens(inst, function()
        captured(inst, function() NS.Launcher:Object().OnClick(OWNER, "LeftButton") end)
    end)
    assertEqual(opened, 1, "left click must open the panel")
    assertEqual(NS.db.profile.locked, locked, "and must NOT touch the lock")
    assertEqual(NS.db.profile.enabled, enabled, "nor the master switch")
end)

test("RIGHT click opens the options menu: the label, then Enabled and Locked, nothing else", function()
    -- The menu entries are ADDONS.md's row for KickCD, in the library's order.
    -- red under: passing a test-mode or window pair, dropping setEnabled or
    -- toggleLock, or a right click that still opens the panel
    local inst = T.load(true, true)
    local menu = menuFor(inst)
    local m
    local opened = countOpens(inst, function() m = rightClick(inst, menu) end)
    assertTrue(m ~= nil, "right click must open the context menu")
    assertEqual(opened, 0, "and must not open the panel as well")
    assertTrue(m.owner == OWNER, "anchored to the button that was clicked")
    assertEqual(m.titles[1], "Ka0s KickCD", "titled with the plain-text label")
    local texts = m:Texts()
    assertEqual(#texts, 2, "exactly two entries: " .. table.concat(texts, " / "))
    assertEqual(texts[1], "Enabled")
    assertEqual(texts[2], "Locked")
end)

test("the menu reads the state when it opens, every time", function()
    -- Never cached: the menu opened after `/kcd unlock` must show it unlocked.
    -- red under: an accessor answering a value captured at file load
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    NS.db.profile.enabled = true
    NS.db.profile.locked = true
    local m = rightClick(inst, menu)
    assertTrue(m:Checked("Enabled"), "enabled reads checked")
    assertTrue(m:Checked("Locked"), "locked reads checked")
    captured(inst, function() NS:OnSlashCommand("unlock") end)
    m = rightClick(inst, menu)
    assertFalse(m:Checked("Locked"), "the next open reads the unlock")
end)

test("Enabled routes to the handler `/kcd enable` and `/kcd disable` run", function()
    -- One function behind three surfaces: the verbs, the menu entry and (through
    -- `set enabled`) the Master-controls row. Proven by spying on the handler and
    -- seeing BOTH the verb and the menu arrive there, then by the stored value.
    -- red under: setEnabled writing db.profile.enabled itself, or calling a
    -- second path the verbs do not
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    local seen, real = {}, NS.SetMasterEnabled
    NS.SetMasterEnabled = function(on) seen[#seen + 1] = on; return real(on) end
    NS.db.profile.enabled = true
    local m = rightClick(inst, menu)
    captured(inst, function() m:Click("Enabled") end)
    assertEqual(#seen, 1, "the menu called the handler once")
    assertEqual(seen[1], false, "handed the state it moves TO")
    assertEqual(NS.db.profile.enabled, false, "and the addon is off")
    captured(inst, function() NS:OnSlashCommand("enable") end)
    assertEqual(seen[2], true, "`/kcd enable` reaches the same handler")
    captured(inst, function() NS:OnSlashCommand("disable") end)
    assertEqual(seen[3], false, "and so does `/kcd disable`")
    NS.SetMasterEnabled = real
    m = rightClick(inst, menu)
    captured(inst, function() m:Click("Enabled") end)
    assertEqual(NS.db.profile.enabled, true, "the menu turns a disabled addon back on")
end)

test("Enabled writes through the single write seam, one write on the `enabled` row", function()
    -- options-ui-§1: the verbs are ALIASES for `/kcd set enabled`, so the menu is too.
    -- red under: a second path to db.profile.enabled anywhere in the launcher
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    local H = NS.Settings.Helpers
    local seen, real = {}, H.SetAndRefresh
    H.SetAndRefresh = function(path, value) seen[#seen + 1] = path; return real(path, value) end
    local m = rightClick(inst, menu)
    captured(inst, function() m:Click("Enabled") end)
    H.SetAndRefresh = real
    assertEqual(#seen, 1, "one write, not two")
    assertEqual(seen[1], "enabled", "and it is the Master-controls row's path")
end)

test("Locked routes to NS.ToggleLock, the handler `/kcd toggle` runs", function()
    -- red under: toggleLock writing db.profile.locked directly
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    local calls, real = 0, NS.ToggleLock
    NS.ToggleLock = function(...) calls = calls + 1; return real(...) end
    local before = NS.db.profile.locked
    local m = rightClick(inst, menu)
    captured(inst, function() m:Click("Locked") end)
    assertEqual(calls, 1, "the menu called the handler once")
    assertEqual(NS.db.profile.locked, not before, "and the lock flipped")
    captured(inst, function() NS:OnSlashCommand("toggle") end)
    NS.ToggleLock = real
    assertEqual(calls, 2, "`/kcd toggle` reaches the same handler")
    assertEqual(NS.db.profile.locked, before, "and flips it back")
end)

test("Locked goes through the SAME write seam the Lock frame checkbox does", function()
    -- options-ui-§1: one writer. The seam is NS.Settings.Store.Set: the checkbox
    -- reaches it through Helpers.SetAndRefresh, and setLocked calls it directly
    -- so that the lock verbs still write on a library-absent load (WS-02 route (a)).
    -- red under: a second path to db.profile.locked anywhere in the launcher
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    local S = NS.Settings.Store
    local seen, real = {}, S.Set
    S.Set = function(path, value, ...)
        seen[#seen + 1] = { path, value }
        return real(path, value, ...)
    end
    local m = rightClick(inst, menu)
    captured(inst, function() m:Click("Locked") end)
    S.Set = real
    assertEqual(#seen, 1, "exactly one write")
    assertEqual(seen[1][1], "locked", "and it is the `locked` row's own path")
end)

test("with no client menu API the right click falls back to the settings panel", function()
    -- The library resolves MenuUtil on every click; a client without it gets the
    -- panel, which holds every toggle the menu would have.
    -- red under: a host-built menu or click route (anti-pattern #81)
    local inst = T.load(true, true)
    local NS = inst.NS
    local locked = NS.db.profile.locked
    local opened = countOpens(inst, function()
        captured(inst, function() NS.Launcher:Object().OnClick(OWNER, "RightButton") end)
    end)
    assertEqual(opened, 1, "right click with no MenuUtil must open the panel")
    assertEqual(NS.db.profile.locked, locked, "and must NOT touch the lock")
end)

-- ── the status tooltip (launcher-§1; Launcher version 3, hints fixed at version 4) ──
--
-- The LIBRARY draws it, in one shape across all eleven addons, and draws it
-- while the addon is disabled. What is ours is the answers: the version and the
-- Enabled and Locked readers. KickCD has no Test mode (unlocking IS the
-- preview), so it has no Test mode line, and it has no extra lines of its own,
-- so it passes no onTooltipShow.

--- The tooltip's lines, drawn through the object's own OnTooltipShow, with the
--- status colors stripped so the cases read the words.
local function tooltipLines(inst)
    local lines = {}
    local tt = { AddLine = function(_, s) lines[#lines + 1] = s end }
    inst.NS.Launcher:Object().OnTooltipShow(tt)
    for i, s in ipairs(lines) do
        lines[i] = (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
    return lines
end

--- The descriptor source, for the fields whose ABSENCE is the contract.
local function launcherSource()
    local fh = assert(io.open(T.root .. "/core/LauncherSetup.lua", "r"))
    local body = fh:read("*a"); fh:close()
    return body
end

test("the descriptor passes the pairs KickCD has, and no retired or absent field", function()
    -- launcher-§2 (v2.67.0): a pair ONLY for a state the addon really has, and
    -- the four fields Launcher version 4 retired are deleted, not left as dead
    -- configuration (launcher-§5). No onTooltipShow: the library draws the title
    -- and hints, and a host copy of either is anti-pattern #89.
    -- red under: passing a test-mode or window pair, or keeping onClick
    local body = launcherSource()
    for _, field in ipairs({ "version", "isEnabled", "setEnabled", "isLocked", "toggleLock" }) do
        assertTrue(body:find("\n%s*" .. field .. "%s*=") ~= nil, "the descriptor must pass `" .. field .. "`")
    end
    for _, field in ipairs({ "isTestMode", "toggleTestMode", "isWindowShown", "toggleWindow",
                             "onTooltipShow", "onClick", "leftClickLabel", "disabledLine", "slash" }) do
        assertNil(body:find("\n%s*" .. field .. "%s*="), "the descriptor must not pass `" .. field .. "`")
    end
end)

test("the tooltip, enabled and locked: title with the TOC version, Enabled, Locked, the fixed hints",
function()
    -- red under: no `version` (the title reads the label alone), no isEnabled
    -- (Enabled is Yes forever), or no isLocked (no Locked line)
    local inst = T.load(true, true)
    local NS = inst.NS
    NS.db.profile.enabled = true
    NS.db.profile.locked = true
    local lines = tooltipLines(inst)
    assertEqual(#lines, 5, "title, Enabled, Locked, Left-click, Right-click: " .. table.concat(lines, " / "))
    assertEqual(lines[1], "Ka0s KickCD  v" .. NS.Version(), "the title carries the TOC's version")
    assertEqual(lines[2], "Enabled: Yes")
    assertEqual(lines[3], "Locked: Yes")
    assertEqual(lines[4], "Left-click: Open settings")
    assertEqual(lines[5], "Right-click: Options menu")
    for _, s in ipairs(lines) do
        assertNil(s:find("Test mode", 1, true), "no Test mode line: this addon has no test mode")
    end
end)

test("the tooltip reads the lock on EVERY show", function()
    -- Never cached (launcher-§1): the hover after a menu click must say so.
    -- red under: isLocked a value rather than a function
    local inst = T.load(true, true)
    local NS = inst.NS
    local menu = menuFor(inst)
    NS.db.profile.locked = false
    assertEqual(tooltipLines(inst)[3], "Locked: No")
    local m = rightClick(inst, menu)
    captured(inst, function() m:Click("Locked") end)
    assertEqual(tooltipLines(inst)[3], "Locked: Yes", "the menu locked it, and the next hover says so")
end)

test("the version is the TOC's ## Version, not a second constant", function()
    -- `version` from the TOC metadata (launcher-§1). NS.Version() reads the TOC
    -- first and only falls back to NS.VERSION, the same answer `/kcd version`
    -- and a capture record give.
    -- red under: version = "1.3.0", or any literal
    local fh = assert(io.open(T.root .. "/KickCD.toc", "r"))
    local toc = fh:read("*a"); fh:close()
    local tocVersion = toc:match("##%s*Version:%s*([^\r\n]+)")
    local inst = T.load(true, true)
    assertEqual(inst.NS.Version(), tocVersion)
    assertEqual(tooltipLines(inst)[1], "Ka0s KickCD  v" .. tocVersion)
end)

test("the tooltip still shows while DISABLED: Enabled: No, the same hints", function()
    -- The owner's M5 ruling: the button ALWAYS answers a hover, disabled
    -- included, since that is when a player most needs to ask. Since version 4
    -- both buttons work in either state, so the hints do not change.
    -- red under: no isEnabled (Enabled: Yes while off)
    local inst = T.load(true, true)
    local NS = inst.NS
    NS.db.profile.enabled = false
    NS.db.profile.locked = true
    local lines = tooltipLines(inst)
    assertEqual(#lines, 5, table.concat(lines, " / "))
    assertEqual(lines[1], "Ka0s KickCD  v" .. NS.Version())
    assertEqual(lines[2], "Enabled: No")
    assertEqual(lines[3], "Locked: Yes", "the lock is still reported while disabled")
    assertEqual(lines[4], "Left-click: Open settings")
    assertEqual(lines[5], "Right-click: Options menu")
end)

-- ── the Minimap button row (launcher-§3) ────────────────────────────────────

test("the row's get INVERTS LibDBIcon's `hide`, so the label can say shown", function()
    -- There is one boolean and the library writes it too, from its own
    -- right-click menu; a second `minimap.show` beside it would be free to
    -- disagree (anti-pattern #81). The cost is this inversion.
    -- red under: reading db.global.minimap.hide straight into the checkbox
    local inst = T.load(true, true)
    local S = inst.NS.Settings.Store
    inst.NS.db.global.minimap.hide = false
    assertEqual(S.Get("global.minimap.shown"), true, "hidden=false reads as SHOWN")
    inst.NS.db.global.minimap.hide = true
    assertEqual(S.Get("global.minimap.shown"), false, "hidden=true reads as not shown")
end)

test("the row's set inverts AND moves the button, in the one write seam", function()
    -- launcher-§3 wants the button to follow the checkbox immediately rather
    -- than at the next reload, and wants that to happen on the addon's single
    -- write seam like every other row (options-ui-§1).
    -- red under: writing `hide` without calling LibDBIcon, or vice versa
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("global.minimap.shown", false)
    assertEqual(inst.NS.db.global.minimap.hide, true, "unticked stores hide = true")
    assertFalse(dbicon(inst).__shown[FOLDER], "and hides the button now, not at reload")
    assertFalse(inst.NS.Launcher:IsShown())
    H.SetAndRefresh("global.minimap.shown", true)
    assertEqual(inst.NS.db.global.minimap.hide, false, "ticked stores hide = false")
    assertTrue(dbicon(inst).__shown[FOLDER], "and shows it again")
    assertTrue(inst.NS.Launcher:IsShown())
end)

test("`/kcd get global.minimap.shown` answers true while minimap.hide is false", function()
    -- launcher-§3 (v2.65.0): the row's schema path IS its CLI name, so it is
    -- spelled in the row's own sense. Before the rename the path was the stored
    -- key, and `/kcd get global.minimap.hide` answered true while the button
    -- was ON the minimap -- a player reading the verb got the opposite answer.
    -- The old path is not kept as an alias: it answers the unknown-setting
    -- refusal like any other path the schema does not declare.
    -- red under: a path spelled after LibDBIcon's key rather than the row's sense
    local inst = T.load(true, true)
    inst.NS.db.global.minimap.hide = false
    local lines = captured(inst, function() inst.NS:OnSlashCommand("get global.minimap.shown") end)
    local out = table.concat(lines, "\n")
    assertTrue(out:find("true", 1, true) ~= nil and out:find("not found", 1, true) == nil,
        "the button shows and the verb did not answer true: " .. out)
    inst.NS.db.global.minimap.hide = true
    out = table.concat(captured(inst, function()
        inst.NS:OnSlashCommand("get global.minimap.shown") end), "\n")
    assertTrue(out:find("false", 1, true) ~= nil, "a hidden button must read false: " .. out)
    out = table.concat(captured(inst, function()
        inst.NS:OnSlashCommand("get global.minimap.hide") end), "\n")
    assertTrue(out:find("Setting not found", 1, true) ~= nil,
        "the retired path still answers: " .. out)
end)

test("`/kcd set global.minimap.shown false` stores hide = true", function()
    -- The CLI and the panel are two surfaces over one writer, which is the
    -- whole of options-ui-§1 -- and the reason the composed row is addressable
    -- by its verbatim global path at all. The STORE did not move: the write
    -- lands on LibDBIcon's own `hide`, and no `shown` key ever appears beside
    -- it (a second copy of one boolean, anti-pattern #81).
    -- red under: a CLI branch of its own for the global store, or a stored `shown`
    local inst = T.load(true, true)
    captured(inst, function() inst.NS:OnSlashCommand("set global.minimap.shown false") end)
    assertEqual(inst.NS.db.global.minimap.hide, true)
    assertNil(inst.NS.db.global.minimap.shown, "a `shown` key was written beside `hide` (#81)")
    assertFalse(dbicon(inst).__shown[FOLDER])
    captured(inst, function() inst.NS:OnSlashCommand("set global.minimap.shown true") end)
    assertEqual(inst.NS.db.global.minimap.hide, false)
    assertTrue(dbicon(inst).__shown[FOLDER])
end)

test("a legacy store keeps its setting across the CLI rename, with no migration", function()
    -- Only the CLI name moved; the stored key is still LibDBIcon's `hide`, so
    -- an existing player's `hide = true` reads as shown = false with no
    -- SavedVariables migration and no schemaVersion bump, LibDBIcon's dragged
    -- `minimapPos` is untouched, and no write ever plants a `shown` key in the
    -- raw SavedVariables.
    -- red under: a migration that rewrites the table, or a stored `shown`
    local inst = T.load(true, true, function(m)
        m.KickCDDB = { global = { schemaVersion = 5, minimap = { hide = true, minimapPos = 200 } },
            profiles = { Default = {} } }
    end)
    local raw = inst.mocks.KickCDDB.global.minimap
    local H = inst.NS.Settings.Helpers
    local S = inst.NS.Settings.Store
    assertEqual(S.Get("global.minimap.shown"), false, "a legacy hide = true reads as not shown")
    local out = table.concat(captured(inst, function()
        inst.NS:OnSlashCommand("get global.minimap.shown") end), "\n")
    assertTrue(out:find("false", 1, true) ~= nil, "the CLI must read the legacy button as hidden: " .. out)
    assertFalse(dbicon(inst).__shown[FOLDER], "the legacy hidden button came back on the rename")
    assertEqual(raw.minimapPos, 200, "the dragged angle moved")
    captured(inst, function() inst.NS:OnSlashCommand("set global.minimap.shown false") end)
    H.SetAndRefresh("global.minimap.shown", true)
    H.SetAndRefresh("global.minimap.shown", false)
    assertNil(raw.shown, "a `shown` key was written to the raw SV (#81)")
    assertEqual(raw.hide, true)
    assertEqual(raw.minimapPos, 200, "a write moved the dragged angle")
    assertFalse(dbicon(inst).__shown[FOLDER])
end)

test("`Reset all settings` does NOT un-hide a button the player hid", function()
    -- launcher-§3 makes this a PROPERTY of the setting -- a per-installation
    -- display preference, like the position LibDBIcon keeps in the same table --
    -- rather than something derived from the store it sits in. Here the property
    -- happens to hold three times over, and the case is written so that losing any
    -- one of them is still red: the walk narrows to `sessionOnly` and this row is
    -- STORED, `vetoedFromResetAll` answers true for it, and the reset itself is
    -- db:ResetProfile() while the table is db.GLOBAL. The page-scoped Defaults
    -- button is a different route entirely and has its own case below.
    -- red under: storing the table under db.profile, or marking the row sessionOnly
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("global.minimap.shown", false)
    captured(inst, function() H.RestoreAllDefaults() end)
    assertEqual(inst.NS.db.global.minimap.hide, true, "the button stays hidden")
end)

test("the General page's DEFAULTS button does NOT un-hide a button the player hid", function()
    -- THE ONE launcher-§3 (v2.54.0) made a PROPERTY rather than a derivation, and
    -- the one this addon was actually failing. The old sentence argued that
    -- `Reset all settings` is a profile reset and the table is global, so no reset
    -- can reach the row -- but that argument was only ever about THAT button. The
    -- page-scoped Defaults walks `rowsForPage("general")`, which is where the
    -- composed `Minimap button` row LIVES, and libs/LibKa0s/Options.lua's
    -- O.RestoreDefaults consults no veto at all: `skipRestoreAll` is read by
    -- RestoreAllDefaults and by nothing else. So one press of Defaults on General
    -- put the button back, at LibDBIcon's default angle, for a player who had
    -- deliberately removed it.
    -- red under: dropping settings/OptionsSetup.lua's applyDefault exemption
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    H.SetAndRefresh("global.minimap.shown", false)
    assertEqual(inst.NS.db.global.minimap.hide, true, "sanity: the player hid it")
    captured(inst, function() H.RestoreDefaults("general") end)
    assertEqual(inst.NS.db.global.minimap.hide, true,
        "the page's Defaults must leave the hidden button hidden")
    assertFalse(dbicon(inst).__shown[FOLDER], "and must not put it back on the ring")
end)

test("nor does it RE-HIDE a button the player is happy with", function()
    -- The rule runs both ways: neither reset may un-hide a hidden button, and
    -- neither may hide a shown one (launcher-§3). The default is SHOWN, so this
    -- direction cannot fail by writing the default -- it fails if the exemption is
    -- ever written as "force hide" rather than "do not touch".
    -- red under: an exemption that writes anything at all
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    assertEqual(inst.NS.db.global.minimap.hide, false, "sanity: shown by default")
    captured(inst, function() H.RestoreDefaults("general") end)
    assertEqual(inst.NS.db.global.minimap.hide, false)
    assertTrue(dbicon(inst).__shown[FOLDER])
end)

test("the exemption is ONE row — the page's Defaults still resets everything else", function()
    -- An exemption that quietly widened would be a Defaults button that stopped
    -- working, which is a worse bug than the one it fixed and would go unnoticed
    -- for exactly as long.
    -- red under: vetoing by page, by section, or by "every global path"
    local inst = T.load(true, true)
    local H = inst.NS.Settings.Helpers
    local S = inst.NS.Settings.Store
    H.SetAndRefresh("global.minimap.shown", false)
    H.SetAndRefresh("locked", not S.FindRow("locked").default)
    H.SetAndRefresh("visibility", "always")
    captured(inst, function() H.RestoreDefaults("general") end)
    assertEqual(S.Get("locked"), S.FindRow("locked").default,
        "`locked` is a General row and must be back at its default")
    assertEqual(S.Get("visibility"), "target_casting_interruptible",
        "and so is `visibility`")
    assertEqual(inst.NS.db.global.minimap.hide, true, "only the one row is exempt")
end)

test("`/kcd resetall` does not un-hide it either — the SECOND reset, by its own route", function()
    -- `/kcd resetall` is a host verb that reaches Helpers.ResetAll rather than the
    -- library's walk directly, so the case above proves nothing about it. Exercised
    -- through the slash surface because that is the route a player takes.
    -- red under: a resetall path of its own that writes the row's default
    local inst = T.load(true, true)
    inst.NS.Settings.Helpers.SetAndRefresh("global.minimap.shown", false)
    captured(inst, function() inst.NS:OnSlashCommand("resetall") end)
    assertEqual(inst.NS.db.global.minimap.hide, true, "the button stays hidden")
    assertFalse(dbicon(inst).__shown[FOLDER])
end)

test("a profile switch does not move the player's button", function()
    -- A minimap button belongs to the INSTALLATION, not to a profile: the ring
    -- of buttons is furniture the player arranged once (launcher-§3).
    -- red under: db.profile.minimap
    local inst = T.load(true, true)
    inst.NS.Settings.Helpers.SetAndRefresh("global.minimap.shown", false)
    inst.NS.db:SetProfile("a-second-profile")
    assertEqual(inst.NS.db.global.minimap.hide, true)
end)

-- ── the reserved verbs (slash-commands-§2) ──────────────────────────────────

test("`/kcd enable` and `/kcd disable` write the Enable row's own stored path", function()
    -- ALIASES, not a second switch: the same stored path through the same single
    -- write seam the checkbox writes through.
    -- red under: either verb writing a key of its own
    local inst = T.load(true, true)
    local NS = inst.NS
    captured(inst, function() NS:OnSlashCommand("disable") end)
    assertEqual(NS.db.profile.enabled, false)
    captured(inst, function() NS:OnSlashCommand("enable") end)
    assertEqual(NS.db.profile.enabled, true)
end)

test("the verbs hold NO state of their own — the checkbox and the CLI cannot disagree",
function()
    -- red under: an NS.enabled local, a session flag, or a second key beside the row
    local inst = T.load(true, true)
    local NS = inst.NS
    local H = NS.Settings.Helpers
    local S = NS.Settings.Store
    local seen, real = {}, H.SetAndRefresh
    H.SetAndRefresh = function(path, value)
        seen[#seen + 1] = path
        return real(path, value)
    end
    captured(inst, function() NS:OnSlashCommand("disable") end)
    H.SetAndRefresh = real
    assertEqual(#seen, 1, "one write, not two")
    assertEqual(seen[1], "enabled", "and it is the Master-controls row's path")
    -- The panel reads the same answer back through the same seam.
    assertEqual(S.Get("enabled"), false)
end)

test("the disable confirmation reports FALSE, not `nil`", function()
    -- The host `get` used to be `H and H.Get and H.Get(path) or nil`, which
    -- folds a stored false to nil, and the library prints nil as the literal
    -- "nil" — so the one line telling the player the addon is off said the
    -- setting was unset.
    -- red under: restoring the `and ... or nil` idiom in either descriptor
    local inst = T.load(true, true)
    local lines = captured(inst, function() inst.NS:OnSlashCommand("disable") end)
    assertEqual(#lines, 1, "one tagged line")
    assertTrue(lines[1]:find("false", 1, true) ~= nil, "it must say false: " .. lines[1])
    assertNil(lines[1]:find("nil", 1, true), "and must not say nil: " .. lines[1])
end)

test("the dispatcher answers while the addon is DISABLED, so the pair is never one-way",
function()
    -- Disabled means the addon stands its FEATURES down. The chat command, the
    -- COMMANDS table and the dispatcher are SETUP: they come up in either state
    -- and stay up, or the player turns the addon off and the verb that turns it
    -- back on is gone (slash-commands-§2).
    -- red under: gating RegisterChatCommand, COMMANDS or OnSlashCommand on `enabled`
    local inst = T.load(true, true)
    local NS = inst.NS
    captured(inst, function() NS:OnSlashCommand("disable") end)
    assertEqual(NS.db.profile.enabled, false, "sanity: the addon is off")
    for _, verb in ipairs({ "help", "version", "config", "" }) do
        local lines = captured(inst, function() NS:OnSlashCommand(verb) end)
        assertTrue(#lines > 0 or verb == "config" or verb == "",
            "`/kcd " .. verb .. "` must still answer while disabled")
    end
    captured(inst, function() NS:OnSlashCommand("enable") end)
    assertEqual(NS.db.profile.enabled, true, "`enable` above all must still work")
end)

test("both verbs are registered on the COMMANDS table, so `/kcd help` lists them", function()
    -- Reserved verbs are registered by the ADDON through its own COMMANDS table
    -- (slash-commands-§2/slash-commands-§3), which is also what makes them discoverable.
    -- red under: wiring them straight into the dispatcher
    local want = { enable = false, disable = false }
    for _, entry in ipairs(T.NS.COMMANDS) do
        if want[entry[1]] ~= nil then want[entry[1]] = true end
    end
    for verb, found in pairs(want) do
        assertTrue(found, "`" .. verb .. "` must be a COMMANDS row")
    end
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
    local S = inst.NS.Settings.Store
    assertEqual(S.Get("global.minimap.shown"), true)
    H.SetAndRefresh("global.minimap.shown", false)
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
    -- calls NS.Launcher:SetShown on every `global.minimap.shown` write, so a nil
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
