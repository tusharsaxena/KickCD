-- tests/test_skin_fonts.lua — LibKa0s v1.82.0 on this addon's seam (KC-01 of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK): the Font outline, the reserved `skin` verb, the Font
-- flags' From skin and the HUD size scale.
--
-- What this pins:
--   * the Font outline (ruling D-06): skin.outline ("all" by default, "hud", "off") stored through
--     the skin write seam (NS.WriteSkinChoice's media.outline), applied with Skin:SetOutline at load,
--     on every profile event and on the row's own write, and a quiet no-op without the skin engine;
--   * `/kcd skin` (D-16): the row right after config with the library's help words, NS.RunSkinVerb
--     handing O.SkinVerb this addon's picker spec, the picker on a profile that has closed it, and
--     the library-absent line without LibKa0s (the disabled refusal is test_disabled.lua's, driven
--     off NS.COMMANDS);
--   * From skin (D-07): every Font flags row offers "@skin" first and defaults to it, the HUD draws
--     it through the Font outline, a picked flag wins, and the one-time step moves a stored OUTLINE
--     (the old default) onto it once per profile, recorded per profile (skin.flagsReset);
--   * the HUD size scale (D-09): a text on the skin's face stored at 12 draws at 13 under Obsidian
--     and at 12 with its own face or under Ignore fonts; the stored size never moves.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local assertFalse = T.assertFalse

local OWNER = "KickCD"
local UNITS = { "target", "focus" }
local FLAG_RELS = { "icons.cooldownTextFlags", "castbar.fontFlags", "label.style.flags" }

--- A fresh enabled instance with NumberFontNormal and an optional saved KickCDDB.
local function boot(saved, opts)
    return T.load(true, true, function(m)
        m.NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 13, "OUTLINE" end }
        if saved then m.KickCDDB = saved end
    end, opts)
end

local function skinLib(inst) return inst.mocks.LibStub("LibKa0s-Skin-1.0") end

--- The value at a dotted path under `t`, or nil.
local function at(t, path)
    for seg in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[seg]
    end
    return t
end

--- Every line NS.Util.print printed while `fn` ran.
local function say(inst, fn)
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

-- ── the Font outline ────────────────────────────────────────────────────────────────────────

test("outline: a fresh profile stores All text, the library's default, and wears it", function()
    local inst = boot()
    assertEqual(inst.NS.db.profile.skin.outline, "all")
    assertEqual(inst.NS.db.profile.skin.outline, skinLib(inst).OUTLINE_DEFAULT)
    assertEqual(skinLib(inst):GetOutline(OWNER), "all")
end)

test("outline: the schema row offers the library's three modes, in its order", function()
    local inst = boot()
    local row = inst.NS.Settings.Store.FindRow("skin.outline")
    assertTrue(row ~= nil, "a skin.outline row")
    assertTrue(row.skipRender == true, "the Skin tab draws it")
    assertEqual(table.concat(row.sorting, ","), table.concat(skinLib(inst).OUTLINE_MODES, ","))
end)

test("outline: the write seam stores media.outline, and leaves it alone when it is nil", function()
    -- red under: WriteSkinChoice dropping media.outline (the Skin tab's Font outline and another
    -- addon's copy would move the look and never store it)
    local NS = boot().NS
    NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false, outline = "hud" })
    assertEqual(NS.db.profile.skin.outline, "hud")
    NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false })
    assertEqual(NS.db.profile.skin.outline, "hud", "a media without outline leaves it")
    NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false, outline = "off" })
    assertEqual(NS.db.profile.skin.outline, "off")
end)

test("outline: another addon's copy reaches the store through WriteChoice", function()
    local inst = boot()
    skinLib(inst):WriteChoice(OWNER, "ka0s", "ember", nil, { font = false, texture = false, outline = "off" })
    assertEqual(inst.NS.db.profile.skin.outline, "off")
end)

test("outline: the row's write applies the mode live", function()
    local inst = boot()
    local H, Skin = inst.NS.Settings.Helpers, skinLib(inst)
    H.SetAndRefresh("skin.outline", "hud")
    assertEqual(Skin:GetOutline(OWNER), "hud")
    assertEqual(inst.NS.Skin.Token("hud.outline"), "OUTLINE", "the HUD keeps it")
    H.SetAndRefresh("skin.outline", "off")
    assertEqual(inst.NS.Skin.Token("hud.outline"), "", "Off takes it")
end)

test("outline: /kcd set refuses a mode the library does not know", function()
    local inst = boot()
    say(inst, function() inst.NS:OnSlashCommand("set skin.outline thick") end)
    assertEqual(inst.NS.db.profile.skin.outline, "all")
end)

test("outline: the stored mode is applied at load and on a profile switch", function()
    -- red under: ApplySkinChoice's whole-pair path not applying the stored outline
    local saved = { profiles = { Default = { skin = { outline = "off" } }, Alt = {} } }
    local inst = boot(saved)
    local Skin = skinLib(inst)
    assertEqual(Skin:GetOutline(OWNER), "off", "the load")
    inst.NS.db:SetProfile("Alt")
    assertEqual(Skin:GetOutline(OWNER), "all", "Alt keeps the default")
    inst.NS.db:SetProfile("Default")
    assertEqual(Skin:GetOutline(OWNER), "off", "Default's is back")
end)

test("outline: without the skin engine the apply is a quiet no-op", function()
    local NS = boot(nil, { libFiles = {} }).NS
    assertEqual(NS.ApplySkinOutline(), false)
    assertEqual(NS.SkinOutline(), "all")
end)

-- ── /kcd skin ───────────────────────────────────────────────────────────────────────────────

test("skin verb: the row sits right after config, with the library's help words", function()
    local inst = boot()
    local at_
    for i, c in ipairs(inst.NS.COMMANDS) do if c[1] == "skin" then at_ = i end end
    assertTrue(at_ ~= nil, "a skin row")
    assertEqual(inst.NS.COMMANDS[at_ - 1][1], "config", "after config")
    local O = inst.mocks.LibStub("LibKa0s-Options-1.0")
    assertEqual(inst.NS.COMMANDS[at_][2], O.SKIN_PICKER_STRINGS.VERB_HELP, "one wording for every host")
end)

test("skin verb: NS.RunSkinVerb hands O.SkinVerb this addon's picker spec", function()
    local inst = boot()
    local NS, H = inst.NS, inst.NS.Settings.Helpers
    local live, seen = H.SkinVerb, nil
    H.SkinVerb = function(spec) seen = spec; return nil, "queued" end
    local ok, err = pcall(function()
        local win, why = NS.RunSkinVerb()
        assertEqual(win, nil)
        assertEqual(why, "queued", "the library's reason, passed on")
    end)
    H.SkinVerb = live
    if not ok then error(err, 0) end
    assertEqual(seen.owner, OWNER)
    assertTrue(seen.get == NS.SkinChoice and seen.set == NS.WriteSkinChoice, "this addon's seams")
    assertEqual(seen.page, "general")
    assertEqual(seen.tab, "Appearance")
end)

test("skin verb: /kcd skin shows the picker on a profile that has closed it", function()
    -- red under: no skin row (the dispatcher answers "unknown command")
    local inst = boot()
    local NS = inst.NS
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    NS.HideSkinPicker()
    NS.db.profile.skin.pickerSeen = true
    local lines = say(inst, function() NS:OnSlashCommand("skin") end)
    for _, l in ipairs(lines) do assertFalse(l:find("unknown command", 1, true) ~= nil, l) end
    local O = NS.Settings.Helpers
    local win = select(1, O.SkinVerb(NS.SkinPickerSpec()))
    assertTrue(win ~= nil and win:IsShown(), "the picker is up")
    NS.HideSkinPicker()
end)

test("skin verb: without LibKa0s it prints the library-absent line", function()
    local inst = boot(nil, { libFiles = {} })
    local lines = say(inst, function() inst.NS.RunSkinVerb() end)
    assertEqual(#lines, 1)
    assertTrue(lines[1]:find("/kcd skin is unavailable: the LibKa0s library did not load.", 1, true) ~= nil,
        lines[1])
end)

-- ── From skin ───────────────────────────────────────────────────────────────────────────────

test("From skin: every Font flags row leads with @skin and defaults to it, in the row and the defaults", function()
    -- red under: a FontGroup without flagsFromSkin, or a default left at OUTLINE
    local inst = boot()
    local Store = inst.NS.Settings.Store
    for _, unit in ipairs(UNITS) do
        for _, rel in ipairs(FLAG_RELS) do
            local path = "units." .. unit .. "." .. rel
            local row = Store.FindRow(path)
            assertTrue(row ~= nil, path)
            assertEqual(row.default, "@skin", path .. ": the row's default")
            assertTrue(row.values["@skin"] ~= nil, path .. ": offers From skin")
            assertEqual(at(inst.NS.DEFAULT_PROFILE, "units." .. unit .. "." .. rel) or
                at(inst.NS.DEFAULT_PROFILE, "units.target." .. rel), "@skin", path .. ": defaults/Profile.lua")
        end
    end
end)

test("From skin: the HUD draws the Font outline's flags, and a picked flag wins", function()
    local inst = boot()
    local NS = inst.NS
    assertEqual(NS.SkinFontFlags("@skin"), "OUTLINE", "All text")
    NS.Settings.Helpers.SetAndRefresh("skin.outline", "off")
    assertEqual(NS.SkinFontFlags("@skin"), "", "Off")
    assertEqual(NS.SkinFontFlags("THICKOUTLINE"), "THICKOUTLINE", "a pick wins")
    assertEqual(NS.SkinFontFlags(""), "", "None is a pick")
    assertEqual(NS.SkinFontFlags("NONE"), "", "the pre-v5 token")
    -- And the cast bar draws it: both texts.
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    Castbar:Reskin(cb, true)
    assertEqual(select(3, cb.frame.nameText:GetFont()), "", "the cast bar under Off")
    NS.Settings.Helpers.SetAndRefresh("skin.outline", "all")
    Castbar:Reskin(cb, true)
    assertEqual(select(3, cb.frame.nameText:GetFont()), "OUTLINE", "and under All text")
end)

test("From skin: without the library From skin draws OUTLINE, a pick as stored", function()
    local NS = boot(nil, { libFiles = {} }).NS
    assertEqual(NS.SkinFontFlags("@skin"), "OUTLINE")
    assertEqual(NS.SkinFontFlags(nil), "OUTLINE")
    assertEqual(NS.SkinFontFlags("MONOCHROME"), "MONOCHROME")
end)

--- An account whose Default profile stored OUTLINE (the old default) on every flags row of both
--- units, one THICKOUTLINE pick, and no record: only a pre-v1.82.0 store looks like this.
local function oldFlagsSaved(extraProfiles)
    local units = {}
    for _, unit in ipairs(UNITS) do
        units[unit] = { icons = { cooldownTextFlags = "OUTLINE" }, castbar = { fontFlags = "OUTLINE" },
                        label = { style = { flags = "OUTLINE" } } }
    end
    units.focus.castbar.fontFlags = "THICKOUTLINE"
    local profiles = { Default = { skin = { hudReset = true }, units = units } }
    for k, v in pairs(extraProfiles or {}) do profiles[k] = v end
    return { global = { schemaVersion = 6 }, profiles = profiles }
end

test("From skin: the step moves a stored OUTLINE onto From skin once, and keeps a pick", function()
    -- red under: no step, a step that rewrote THICKOUTLINE, or no record
    local NS = boot(oldFlagsSaved()).NS
    for _, unit in ipairs(UNITS) do
        assertEqual(NS.db.profile.units[unit].icons.cooldownTextFlags, "@skin", unit .. " countdown")
        assertEqual(NS.db.profile.units[unit].label.style.flags, "@skin", unit .. " label")
    end
    assertEqual(NS.db.profile.units.target.castbar.fontFlags, "@skin")
    assertEqual(NS.db.profile.units.focus.castbar.fontFlags, "THICKOUTLINE", "a flag the player changed stays")
    assertEqual(NS.db.profile.skin.flagsReset, true, "the profile records the step")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
end)

test("From skin: an OUTLINE picked after the step is never moved again", function()
    local inst = boot(oldFlagsSaved())
    local NS = inst.NS
    NS.db.profile.units.target.castbar.fontFlags = "OUTLINE"
    NS.Database:MigrateFlagsFromSkin(NS.db)
    NS.Database:OnProfileChanged("OnProfileChanged", NS.db, "Default")
    assertEqual(NS.db.profile.units.target.castbar.fontFlags, "OUTLINE", "kept across a profile event")
end)

test("From skin: a profile that was not active at the upgrade is moved when it becomes active", function()
    local alt = { units = { target = { castbar = { fontFlags = "OUTLINE" } } } }
    local NS = boot(oldFlagsSaved({ Alt = alt })).NS
    NS.db:SetProfile("Alt")
    assertEqual(NS.db.profile.units.target.castbar.fontFlags, "@skin")
    assertEqual(NS.db.profile.skin.flagsReset, true)
end)

-- ── the HUD size scale ──────────────────────────────────────────────────────────────────────

test("HUD size: on the skin's face 12 draws at 13 under Obsidian, 12 on its own face or under Ignore fonts", function()
    -- red under: a HUD text drawing its stored size, or scaling a text on its own face
    local inst = boot()
    local NS = inst.NS
    local Skin = skinLib(inst)
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    assertEqual(NS.SkinHudSize(12, true), 13, "the skin's face, scaled")
    assertEqual(NS.SkinHudSize(12, nil), 13, "an absent companion follows the skin")
    assertEqual(NS.SkinHudSize(12, false), 12, "its own face, as stored")
    NS.ApplySkinIgnore(nil, true)
    assertEqual(NS.SkinHudSize(12, true), 12, "Ignore fonts, as stored")
    NS.ApplySkinIgnore(nil, false)
    -- The cast bar, the countdown and the label draw it; the stored size never moves.
    local c = NS.db.profile.units.target.castbar
    c.fontSize = 12
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    Castbar:Reskin(cb, true)
    assertEqual(select(2, cb.frame.nameText:GetFont()), 13, "the cast bar")
    assertEqual(c.fontSize, 12, "the stored size is kept")
    c.fontFromSkin = false
    Castbar:Reskin(cb, true)
    assertEqual(select(2, cb.frame.nameText:GetFont()), 12, "its own face")
    c.fontFromSkin = true
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    Castbar:Reskin(cb, true)
    assertEqual(select(2, cb.frame.nameText:GetFont()), 12, "Ka0s Default, the baseline")
end)

test("HUD size: without the library a size is drawn as stored", function()
    local NS = boot(nil, { libFiles = {} }).NS
    assertEqual(NS.SkinHudSize(14, true), 14)
    assertEqual(NS.SkinHudSize(nil, true), 12)
end)

-- ── the skin's font kept off a face the player picked (KC-03, D-15) ────────────────────────

--- A v7 account (the Font flags step already run) whose Default profile follows the skin's font on
--- every text, with picks: Ka0s Kait on Target's label (the owner's pick), Arial Narrow on Focus's cast
--- bar, Ka0s Default's own face on Focus's countdown, a retired skin face on Target's countdown, and
--- the stored default, Friz Quadrata, on Target's cast bar.
local function v7Saved(extraProfiles, skinKey)
    local profile = { skin = { hudReset = true, flagsReset = true, skin = skinKey }, units = {
        target = { icons = { cooldownTextFont = "Ka0s Oxanium SemiBold", cooldownTextFontFromSkin = true },
                   castbar = { font = "Friz Quadrata TT", fontFromSkin = true },
                   label = { style = { font = "Ka0s Kait", fontFromSkin = true } } },
        focus  = { link = false,
                   icons = { cooldownTextFont = "Ka0s Prototype", cooldownTextFontFromSkin = true },
                   castbar = { font = "Arial Narrow", fontFromSkin = true },
                   label = { style = { fontFromSkin = true } } },
    } }
    local profiles = { Default = profile }
    for k, v in pairs(extraProfiles or {}) do profiles[k] = v end
    return { global = { schemaVersion = 7 }, profiles = profiles }
end

test("skin font kept: a picked face other than the skin's turns Use the skin's font off, once", function()
    -- red under: no step, a step that also turned off the default or the skin's own face, or one
    -- that rewrote a stored pick
    local NS = boot(v7Saved()).NS
    local u = NS.db.profile.units
    assertEqual(u.target.label.style.fontFromSkin, false, "Ka0s Kait comes back")
    assertEqual(u.target.label.style.font, "Ka0s Kait", "the pick is kept")
    assertEqual(u.focus.castbar.fontFromSkin, false, "Arial Narrow comes back")
    assertEqual(u.focus.icons.cooldownTextFontFromSkin, true, "Ka0s Default's own face keeps following")
    assertEqual(u.target.castbar.fontFromSkin, true, "the stored default is not a pick")
    assertEqual(u.target.icons.cooldownTextFontFromSkin, true, "a retired skin face keeps following")
    assertEqual(NS.db.profile.skin.fontPicksKept, true, "the profile records the step")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    assertTrue(NS.SCHEMA_VERSION >= 8, "migrations[7] is on the ladder")
end)

test("skin font kept: the skin's own face is the one the profile wears", function()
    -- Under Obsidian its own face, Expressway, keeps following; Ka0s Default's Prototype is a pick.
    local saved = v7Saved(nil, "obsidian")
    saved.profiles.Default.units.target.castbar.font = "Ka0s Expressway"
    local NS = boot(saved).NS
    local u = NS.db.profile.units
    assertEqual(u.target.castbar.fontFromSkin, true, "Obsidian's own face")
    assertEqual(u.focus.icons.cooldownTextFontFromSkin, false, "Prototype is not Obsidian's face")
end)

test("skin font kept: a box ticked again after the step is never turned off again", function()
    local NS = boot(v7Saved()).NS
    NS.db.profile.units.target.label.style.fontFromSkin = true
    NS.Database:MigrateSkinFontPicks(NS.db)
    NS.Database:OnProfileChanged("OnProfileChanged", NS.db, "Default")
    assertEqual(NS.db.profile.units.target.label.style.fontFromSkin, true, "kept across a profile event")
end)

test("skin font kept: a profile that was not active at the upgrade is stepped when it becomes active", function()
    local alt = { units = { target = { label = { style = { font = "Ka0s Kait", fontFromSkin = true } } } } }
    local NS = boot(v7Saved({ Alt = alt })).NS
    NS.db:SetProfile("Alt")
    assertEqual(NS.db.profile.units.target.label.style.fontFromSkin, false)
    assertEqual(NS.db.profile.skin.fontPicksKept, true)
end)

test("skin font kept: without the library the step still keeps the picks", function()
    local NS = boot(v7Saved(), { libFiles = {} }).NS
    assertEqual(NS.db.profile.units.target.label.style.fontFromSkin, false)
    assertEqual(NS.db.profile.units.focus.icons.cooldownTextFontFromSkin, true, "Ka0s Default's face")
end)
