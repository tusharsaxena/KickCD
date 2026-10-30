-- tests/test_skin_picker.lua — the first-run skin picker on this addon's seam (KC-04;
-- core/SkinSetup.lua, LibKa0s OptionsSkinPicker 1, the rollout's O3 / X6).
--
-- What this addon owes the picker, and nothing the library pins itself: the spec it hands the
-- Options instance's SkinPicker (its owner, its two seams, General's Skin tab, no eye, the close);
-- WHEN it shows (a profile whose `skin.pickerSeen` is false, at login and after every profile
-- event, never while the addon stands down, held through combat); and that only the player's close
-- marks it seen. The trigger cases spy on SkinPicker; the last cases drive the library's real
-- window: Apply saving through NS.WriteSkinChoice, the close control saving nothing, the gear
-- opening General on its Skin tab, the eye absent, and the stand-down taking the window down unseen.
--
-- Modeled on LootHistory's tests/test_skin_picker.lua, the reference adopter. On its own instance,
-- with the enable cascade run (so the login showing has happened and the panel is registered);
-- every case leaves the skin on Ka0s Default, the picker down and marked unseen.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Every frame built on this instance, by parent, so a case can reach the picker list's rows: the
-- shared mock's frames do not list their children, and the picker builds its window, rows
-- included, on its first show, which is the login showing inside the load below.
local childrenOf = setmetatable({}, { __mode = "k" })
local inst = T.load(true, true, function(mocks)
    local create = mocks.CreateFrame
    mocks.CreateFrame = function(frameType, name, parent, ...)
        local f = create(frameType, name, parent, ...)
        if parent ~= nil then
            local list = childrenOf[parent] or {}
            childrenOf[parent] = list
            list[#list + 1] = f
        end
        return f
    end
end)
local NS, mocks = inst.NS, inst.mocks
local O = NS.Settings.Helpers
local Store = NS.Settings.Store
local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "KickCD"
local PATH = "skin.pickerSeen"

local function seen() return Store.Get(PATH) end
local function worn() return select(2, Skin:GetChoice(OWNER)) end
local function stored() return select(2, NS.SkinChoice()) end

--- Run `fn` with chat swallowed.
local function quietly(fn)
    local real = NS.Util.print
    NS.Util.print = function() end
    local ok, err = pcall(fn)
    NS.Util.print = real
    if not ok then error(err, 0) end
end

--- Run `fn(calls)` with the instance's SkinPicker replaced by a recorder: each call's spec.
local function spying(fn)
    local real = O.SkinPicker
    local calls = {}
    O.SkinPicker = function(spec)
        calls[#calls + 1] = spec
        return { spy = true }
    end
    local ok, err = pcall(fn, calls)
    O.SkinPicker = real
    if not ok then error(err, 0) end
end

--- Run `fn` with InCombatLockdown answering `on` until `fn` flips it through the setter it is handed.
local function inCombat(fn)
    local real = mocks.InCombatLockdown
    local state = true
    mocks.InCombatLockdown = function() return state end
    local ok, err = pcall(fn, function(v) state = v end)
    mocks.InCombatLockdown = real
    if not ok then error(err, 0) end
end

--- The picker down (quietly), the profile back on Default with its key false and its skin Ka0s
--- Default, stored and worn, the addon enabled, whatever `fn` raised.
local function clean(fn)
    return function()
        NS.HideSkinPicker()
        quietly(function() Store.Set(PATH, false) end)
        local ok, err = pcall(fn)
        NS.HideSkinPicker()
        quietly(function()
            if not NS.Lifecycle:IsHeld("disabled") then return end
            NS.SetMasterEnabled(true)
        end)
        quietly(function()
            if NS.db:GetCurrentProfile() ~= "Default" then NS.db:SetProfile("Default") end
            Store.Set(PATH, false)
            NS.WriteSkinChoice("ka0s", "ka0s")
        end)
        Skin:SetChoice(OWNER, "ka0s", "ka0s")
        if mocks.__fireTimers then mocks.__fireTimers() end
        if not ok then error(err, 0) end
    end
end

-- ── the spec ─────────────────────────────────────────────────────────────────────────────────

test("Skin picker: the spec names this owner, its seams, General's Skin tab, and no eye", function()
    -- red under: a set that is not the write seam (Apply would never reach the profile), a page key
    -- RegisterOptionsPage was not given (the gear would open nothing), or an eye (X6: KickCD has no
    -- window and no test mode to preview in; its preview is unlocking, a stored write).
    local spec = NS.SkinPickerSpec()
    assertEqual(spec.owner, OWNER)
    assertTrue(rawequal(spec.get, NS.SkinChoice), "get is the read seam")
    assertTrue(rawequal(spec.set, NS.WriteSkinChoice), "set is the write seam")
    assertEqual(spec.page, "general", "the key settings/General.lua gave RegisterOptionsPage")
    assertEqual(spec.tab, "Appearance", "the Skin tab's key")
    assertEqual(spec.onPreview, nil, "no eye: this addon has no window or test mode to preview in")
    assertEqual(type(spec.onClose), "function")
end)

-- ── when it shows ────────────────────────────────────────────────────────────────────────────

test("Skin picker: the login showing happened on the unseen default profile", function()
    -- red under: dropping the call from NS:OnEnable (no profile would ever see it). The load above
    -- ran the enable cascade; the first case left the window as the login put it up.
    assertEqual(seen(), false, "a fresh profile has not seen the picker")
    local f = NS.MaybeShowSkinPicker()
    assertTrue(f ~= nil and f:IsShown(), "the picker is up on an unseen profile")
    NS.HideSkinPicker()
    assertEqual(seen(), false, "this addon's own hide marks nothing")
end)

test("Skin picker: an unseen profile shows it; a seen one does not", clean(function()
    spying(function(calls)
        NS.MaybeShowSkinPicker()
        assertEqual(#calls, 1, "pickerSeen false: the picker shows")
        assertEqual(calls[1].owner, OWNER)
        quietly(function() Store.Set(PATH, true) end)
        NS.MaybeShowSkinPicker()
        assertEqual(#calls, 1, "pickerSeen true: it does not show again")
    end)
end))

test("Skin picker: it shows from NS:OnEnable", clean(function()
    spying(function(calls)
        quietly(function() NS:OnEnable() end)
        assertEqual(#calls, 1, "OnEnable shows the picker on an unseen profile")
    end)
end))

test("Skin picker: in combat a start waits for PLAYER_REGEN_ENABLED, once", clean(function()
    inCombat(function(setCombat)
        spying(function(calls)
            assertEqual(NS.MaybeShowSkinPicker(), nil)
            NS.MaybeShowSkinPicker()
            assertEqual(#calls, 0, "nothing shows in combat")
            setCombat(false)
            mocks.__fireEvent("PLAYER_REGEN_ENABLED")
            assertEqual(#calls, 1, "the combat edge shows it, once for two held starts")
            mocks.__fireEvent("PLAYER_REGEN_ENABLED")
            assertEqual(#calls, 1, "the one-shot target is gone")
        end)
    end)
end))

test("Skin picker: the combat edge shows it even while State still reads in combat", clean(function()
    -- red under: gating on NS.State.inCombat, which core/State.lua clears on the same edge, maybe
    -- after this handler: the held start would wait for the NEXT combat to end.
    inCombat(function(setCombat)
        spying(function(calls)
            NS.MaybeShowSkinPicker()
            setCombat(false)
            local was = NS.State.inCombat
            NS.State.inCombat = true
            local ok, err = pcall(mocks.__fireEvent, "PLAYER_REGEN_ENABLED")
            NS.State.inCombat = was
            if not ok then error(err, 0) end
            assertEqual(#calls, 1, "the held start shows on the edge")
        end)
    end)
end))

test("Skin picker: a held start is dropped by HideSkinPicker", clean(function()
    inCombat(function(setCombat)
        spying(function(calls)
            NS.MaybeShowSkinPicker()
            NS.HideSkinPicker()
            setCombat(false)
            mocks.__fireEvent("PLAYER_REGEN_ENABLED")
            assertEqual(#calls, 0, "a dropped start must not fire on the combat edge")
        end)
    end)
end))

test("Skin picker: never while the addon is switched off", clean(function()
    quietly(function()
        spying(function(calls)
            NS.SetMasterEnabled(false)
            assertTrue(NS.IsDown(), "the switch stood the addon down")
            NS.MaybeShowSkinPicker()
            assertEqual(#calls, 0, "a disabled addon shows no picker")
        end)
    end)
end))

test("Skin picker: a new profile and a reset profile show it again", clean(function()
    -- Both start from the defaults, pickerSeen false (O3). red under: no call on
    -- Database:OnProfileChanged's path.
    local db = NS.db
    quietly(function()
        Store.Set(PATH, true)
        spying(function(calls)
            db:SetProfile("PickerProbe")
            assertEqual(#calls, 1, "a new profile shows the picker")
            Store.Set(PATH, true)
            db:ResetProfile()
            assertEqual(#calls, 2, "a reset profile shows it again")
            Store.Set(PATH, true)
            db:SetProfile("Default")
            assertEqual(#calls, 2, "back on a profile that has seen it: no picker")
        end)
    end)
    if db.DeleteProfile then pcall(db.DeleteProfile, db, "PickerProbe", true) end
end))

-- ── the real window ──────────────────────────────────────────────────────────────────────────

--- Run `fn(f)` on this addon's real picker, shown.
local function onWindow(fn)
    return clean(function()
        quietly(function()
            local f = NS.MaybeShowSkinPicker()
            assertTrue(f ~= nil and f:IsShown(), "the library's picker did not show")
            fn(f)
        end)
    end)
end

--- Open the window's list and click the row for skin `key`, as the player does. This addon's mock
--- frames run their scripts through `_run` (tests/wow_mock_frames.lua), not the kit's `__fire`.
local function pickRow(f, key)
    f.dd:_run("OnClick")
    for _, r in ipairs(childrenOf[f.list] or {}) do
        if r.key == key then r:_run("OnClick"); return end
    end
    error("no row for " .. key, 0)
end

test("Skin picker: the title is Choose a skin, this addon's name is on its own line, and the eye is hidden",
    onWindow(function(f)
    -- The shared mock's FontString keeps no text, so the title and the owner line are read off
    -- their SetText: a repeat call while the window is up re-reads the spec and sets both again.
    -- LibKa0s v1.81.0 (OptionsSkinPicker minor 2, R-11) moved the name off the title, which a
    -- long label overran, onto frame.ownerLabel above the dropdown.
    assertTrue(f.ownerLabel ~= nil, "the window carries the owner line")
    local text, label = nil, nil
    local ownTitle, ownLabel = rawget(f.title, "SetText"), rawget(f.ownerLabel, "SetText")
    f.title.SetText = function(_, v) text = v end
    f.ownerLabel.SetText = function(_, v) label = v end
    assertTrue(rawequal(NS.MaybeShowSkinPicker(), f), "a repeat call answers the same window")
    rawset(f.title, "SetText", ownTitle)
    rawset(f.ownerLabel, "SetText", ownLabel)
    assertEqual(text, "Choose a skin")
    assertEqual(label, "Ka0s KickCD")
    assertTrue(f.preview == nil or not f.preview:IsShown(), "no onPreview: the eye is hidden")
end))

test("Skin picker: the player's close marks it seen; this addon's own hide does not", clean(function()
    quietly(function()
        local f = NS.MaybeShowSkinPicker()
        assertTrue(f ~= nil and f:IsShown(), "the library's picker did not show")
        NS.HideSkinPicker()
        assertTrue(not f:IsShown(), "HideSkinPicker takes it down")
        assertEqual(seen(), false, "this addon's own hide is not the player's close")
        f = NS.MaybeShowSkinPicker()
        assertTrue(f ~= nil and f:IsShown(), "it shows again while unseen")
        O.HideSkinPicker()
        assertEqual(seen(), true, "the player's close sets pickerSeen")
        assertEqual(NS.MaybeShowSkinPicker(), nil, "and it does not show again")
    end)
end))

test("Skin picker: a profile that has seen it takes a shown picker down, unmarked", onWindow(function(f)
    NS.db.profile.skin.pickerSeen = true
    NS.MaybeShowSkinPicker()
    assertTrue(not f:IsShown(), "the picker stayed up on a profile that has seen it")
end))

test("Skin picker: the stand-down takes the picker down, unseen", onWindow(function(f)
    NS.SetMasterEnabled(false)
    assertTrue(not f:IsShown(), "a disabled addon keeps no picker up")
    assertEqual(seen(), false, "the stand-down is not the player's close")
end))

test("Skin picker: a pick previews, unsaved; Apply saves it and marks the picker seen", onWindow(function(f)
    -- red under: a spec.set that is not the write seam, or an onClose that writes no pickerSeen.
    pickRow(f, "obsidian")
    assertEqual(worn(), "obsidian", "the pick is worn at once")
    assertEqual(stored(), "ka0s", "a pick alone writes nothing to the profile")
    assertEqual(seen(), false, "a pick does not end the showing")
    f.apply:_run("OnClick")
    assertTrue(not f:IsShown(), "Apply closes the window")
    assertEqual(stored(), "obsidian", "Apply saves through NS.WriteSkinChoice")
    assertEqual(seen(), true, "Apply marks the picker seen")
end))

test("Skin picker: the close control puts the old skin back, saves nothing, and marks it seen", onWindow(function(f)
    pickRow(f, "obsidian")
    f.close:_run("OnClick")
    assertTrue(not f:IsShown(), "the close control closes the window")
    assertEqual(worn(), "ka0s", "closing puts back the stored skin")
    assertEqual(stored(), "ka0s", "and writes nothing")
    assertEqual(seen(), true, "a close by the player still counts as seen")
end))

test("Skin picker: the gear saves the pick and opens General on its Skin tab", onWindow(function(f)
    -- red under: a page key the library cannot open, or a tab key that is not the Skin tab's.
    local realOpen, realSelect = O.OpenOptionsPanel, O.SelectTab
    local opened, selected = {}, {}
    O.OpenOptionsPanel = function(page) opened[#opened + 1] = page; return true end
    O.SelectTab = function(page, tab) selected[#selected + 1] = { page, tab }; return true end
    local ok, err = pcall(function()
        pickRow(f, "obsidian")
        f.settings:_run("OnClick")
        assertEqual(opened[1], "general", "the gear opens the General page")
        assertTrue(selected[1] ~= nil, "the gear selects a tab")
        assertEqual(selected[1][1], "general")
        assertEqual(selected[1][2], "Appearance", "the Skin tab")
        assertEqual(stored(), "obsidian", "the gear saves the pending pick")
        assertEqual(seen(), true, "and marks the picker seen")
    end)
    O.OpenOptionsPanel, O.SelectTab = realOpen, realSelect
    if not ok then error(err, 0) end
end))
