-- tests/test_skin_hud.lua — the HUD on the skin (KC-03 of Ka0sAddonsCommonTasks
-- docs/2026-10-29-SKINNING_ROLLOUT; skinning-§6).
--
-- What this pins:
--   * the sixteen "Use the skin's ..." companions (eight per unit: the icon border and countdown
--     font, the cast bar's font and both states' bar texture and border, the label font) exist as
--     schema rows from the composers' `fromSkin`, default TRUE (DECISIONS X3) in the rows and in
--     defaults/Profile.lua alike, and the icon border's companion is the ICON family, so it
--     governs the thickness slider too, and so are the cast bar's two (KC-A1);
--   * the HUD draws what NS.SkinResolve answers: the skin's hud.font, bar.texture and
--     icon.borderStyle / icon.borderSize (the icon border AND both cast-bar borders, KC-A1) while a
--     companion is set, the stored pick when it is off, and the charges badge in the skin's face (D4);
--   * a skin switch reaches the HUD through the owner's OnLooksChanged, with no stored value moved;
--   * the one-time reset (owner ruling O2): NS.SCHEMA_VERSION 6, migrations[5], once per profile
--     and recorded per profile (skin.hudReset), so a pick the player turns off later is kept; a
--     profile that was not active at the upgrade is reset when it becomes active; and without the
--     library the step still sets the companions;
--   * "Copy from Target" carries the companions with the pickers.
--
-- The fetches are read where they happen: each instance's LibSharedMedia fake records every
-- Fetch key, so "drew the skin's texture" is the key handed to LibSharedMedia, not a path the
-- fake happens to answer.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local assertFalse = T.assertFalse

local OWNER = "KickCD"
local UNITS = { "target", "focus" }

--- A fresh enabled instance with NumberFontNormal, an optional saved
--- KickCDDB, and every LibSharedMedia Fetch recorded as "<kind>:<key>".
local function boot(saved, opts)
    local fetched = {}
    local inst = T.load(true, true, function(m)
        m.NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 13, "OUTLINE" end }
        if saved then m.KickCDDB = saved end
        local LSM = m.__libs["LibSharedMedia-3.0"]
        local fetch = LSM.Fetch
        LSM.Fetch = function(self, kind, key, ...)
            fetched[#fetched + 1] = tostring(kind) .. ":" .. tostring(key)
            return fetch(self, kind, key, ...)
        end
    end, opts)
    return inst, fetched
end

local function has(list, want)
    for _, v in ipairs(list) do if v == want then return true end end
    return false
end

local function clear(list) for i = #list, 1, -1 do list[i] = nil end end

--- The value at a dotted path under `t`, or nil.
local function at(t, path)
    for seg in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[seg]
    end
    return t
end

--- Set a dotted path under `t`.
local function put(t, path, v)
    local parent, leaf = t, nil
    for seg in path:gmatch("[^%.]+") do
        if leaf then parent = parent[leaf] end
        leaf = seg
    end
    parent[leaf] = v
end

-- ── the companions ──────────────────────────────────────────────────────────

test("HUD skin: every HUD media pick has a companion row, default true in the row and the defaults", function()
    -- red under: a composer call without `fromSkin`, a companion defaulting false (X3), or a
    -- schema default that disagrees with defaults/Profile.lua
    local inst = boot()
    local NS = inst.NS
    local rels = NS.Database.HUD_SKIN_COMPANIONS
    assertEqual(#rels, 8, "eight companions per unit")
    for _, unit in ipairs(UNITS) do
        for _, rel in ipairs(rels) do
            local path = "units." .. unit .. "." .. rel
            local row = NS.Settings.Store.FindRow(path)
            assertTrue(row ~= nil, "no schema row at " .. path)
            assertEqual(row.type, "bool", path)
            assertEqual(row.default, true, path .. " row default")
            assertEqual(at(NS.DEFAULT_PROFILE, path), true, path .. " defaults/Profile.lua")
            assertEqual(at(NS.db.profile, path), true, path .. " live profile")
        end
    end
end)

test("HUD skin: the icon border follows the ICON family, governing its thickness too", function()
    -- red under: the icon BorderGroup on `fromSkin = true` (the bar family, whose Ka0s Default
    -- edge is None and whose companion leaves the thickness slider live)
    local NS = boot().NS
    local Store = NS.Settings.Store
    local companion = "units.target.icons.borderTextureFromSkin"
    assertEqual(Store.FindRow("units.target.icons.borderTexture").disabledIf, companion)
    assertEqual(Store.FindRow("units.target.icons.borderSize").disabledIf, companion,
        "the icon family governs the thickness slider")
    -- The cast bar's borders are the icon family too (KC-A1, the owner's ruling): every skin's
    -- bar.borderStyle is "None", so the bar family would leave the cast bar with no edge.
    for _, state in ipairs({ "interruptible", "uninterruptible" }) do
        local cb = "units.target.castbar." .. state .. "."
        assertEqual(Store.FindRow(cb .. "borderTexture").disabledIf, cb .. "borderTextureFromSkin", state)
        assertEqual(Store.FindRow(cb .. "borderSize").disabledIf, cb .. "borderTextureFromSkin",
            state .. ": the icon family governs the cast bar's thickness slider too")
    end
end)

-- ── the draw ────────────────────────────────────────────────────────────────

test("HUD skin: the cast bar draws the skin's face, texture and border while following", function()
    -- red under: Castbar_Skin.lua fetching the stored pick (c.font, sc.statusBarTexture,
    -- sc.borderTexture) instead of NS.SkinResolve's answer
    local inst, fetched = boot()
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    clear(fetched)
    Castbar:Reskin(cb, true)
    assertTrue(has(fetched, "font:Ka0s Oxanium SemiBold"), "hud.font on Ka0s Default")
    assertTrue(has(fetched, "statusbar:Ka0s Default"), "bar.texture on Ka0s Default")
    assertTrue(has(fetched, "border:Solid"), "icon.borderStyle on Ka0s Default (KC-A1)")
    assertFalse(has(fetched, "border:None"), "not bar.borderStyle, which draws no edge")
    assertFalse(has(fetched, "statusbar:Blizzard Raid Bar"), "the stored pick is not drawn")
end)

test("HUD skin: a companion turned off draws the player's stored pick again", function()
    -- red under: resolving with `fromSkin` always true, or ignoring the companion
    local inst, fetched = boot()
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local c = NS.db.profile.units.target.castbar
    c.fontFromSkin = false
    c.interruptible.statusBarTextureFromSkin = false
    c.interruptible.borderTextureFromSkin = false
    clear(fetched)
    Castbar:Reskin(Castbar:GetInstance("target"), true)
    assertTrue(has(fetched, "font:Friz Quadrata TT"), "the stored face")
    assertTrue(has(fetched, "statusbar:Blizzard Raid Bar"), "the stored texture")
    assertTrue(has(fetched, "border:Blizzard Tooltip"), "the stored border")
    -- The other state still follows: each companion governs its own pick.
    assertTrue(has(fetched, "statusbar:Ka0s Default"), "the uninterruptible bar still follows")
end)

test("HUD skin: the icon border takes the skin's icon family, style and thickness", function()
    -- red under: ApplyAppearance reading cfg.borderTexture / cfg.borderSize straight
    local inst = boot()
    local NS = inst.NS
    local IG = NS:GetModule("IconGrid")
    local icon = IG.CreateIconWidget(inst.mocks.CreateFrame("Frame"))
    icon.unit = "target"
    local bd
    icon.border.SetBackdrop = function(_, t) bd = t end
    local cfg = NS.db.profile.units.target.icons
    icon:ApplyAppearance(cfg)
    assertEqual(bd.edgeFile, "Interface\\Buttons\\WHITE8X8", "Solid, Ka0s Default's icon border")
    assertEqual(bd.edgeSize, 2, "icon.borderSize")
    cfg.borderTextureFromSkin = false
    cfg.borderSize = 5
    icon:ApplyAppearance(cfg)
    assertEqual(bd.edgeSize, 5, "off: the player's thickness")
end)

test("HUD skin: a following cast bar draws the skin's flat icon edge, style and thickness", function()
    -- red under: Castbar_Skin.lua resolving bar.borderStyle (None on every skin, so no edge) or
    -- drawing sc.borderSize while the companion is set (KC-A1)
    local inst, fetched = boot()
    local NS = inst.NS
    local Skin = inst.mocks.LibStub("LibKa0s-Skin-1.0")
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    local frame = cb.frame
    local drawn = {}
    for _, key in ipairs({ "borderInterruptible", "borderUninterruptible" }) do
        frame[key].SetBackdrop = function(_, t) drawn[key] = t end
    end
    local c = NS.db.profile.units.target.castbar
    c.interruptible.borderSize, c.uninterruptible.borderSize = 7, 7   -- the player's, not drawn
    Castbar:Reskin(cb, true)
    for _, key in ipairs({ "borderInterruptible", "borderUninterruptible" }) do
        local bd = drawn[key]
        assertTrue(bd ~= nil, key .. " drew a backdrop")
        assertEqual(bd.edgeFile, "Interface\\Buttons\\WHITE8X8", key .. ": Solid, Ka0s Default's icon edge")
        assertEqual(bd.edgeSize, 2, key .. ": icon.borderSize on Ka0s Default")
    end

    -- Another skin: its own icon edge, through the same tokens.
    local obsidian = Skin:ResolveSkin("obsidian")
    assertEqual(obsidian["bar.borderStyle"], "None", "sanity: the bar family draws no edge on Obsidian")
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    clear(fetched)
    drawn = {}
    Castbar:Reskin(cb, true)
    assertTrue(has(fetched, "border:" .. obsidian["icon.borderStyle"]), "Obsidian's icon.borderStyle")
    for _, key in ipairs({ "borderInterruptible", "borderUninterruptible" }) do
        assertEqual(drawn[key].edgeFile, "Interface\\Buttons\\WHITE8X8", key .. ": Obsidian's flat edge")
        assertEqual(drawn[key].edgeSize, obsidian["icon.borderSize"], key .. ": Obsidian's icon.borderSize")
    end

    -- Off: the player's own style and thickness again.
    c.interruptible.borderTextureFromSkin = false
    drawn = {}
    Castbar:Reskin(cb, true)
    assertEqual(drawn.borderInterruptible.edgeSize, 7, "off: the player's thickness")
    assertEqual(drawn.borderUninterruptible.edgeSize, obsidian["icon.borderSize"], "the other state still follows")
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
end)

test("HUD skin: \"Solid\" is registered as a LibSharedMedia border, the flat edge", function()
    -- red under: no registration, where a fetched Solid falls back to the tooltip edge
    local inst = boot()
    local LSM = inst.mocks.__libs["LibSharedMedia-3.0"]
    assertEqual(LSM.__registered.border and LSM.__registered.border.Solid, "Interface\\Buttons\\WHITE8X8")
end)

test("HUD skin: the countdown follows hud.font and the charges badge takes the skin's face", function()
    -- red under: ApplyTextConfig fetching cfg.cooldownTextFont straight, or the badge left on
    -- NumberFontNormal's face (D4)
    local inst, fetched = boot()
    local NS = inst.NS
    local IG = NS:GetModule("IconGrid")
    local icon = IG.CreateIconWidget(inst.mocks.CreateFrame("Frame"))
    icon.unit = "target"
    local badge
    icon.chargesText.SetFont = function(_, ...) badge = { ... } end
    local cfg = NS.db.profile.units.target.icons
    clear(fetched)
    icon:ApplyTextConfig(cfg)
    assertTrue(has(fetched, "font:Ka0s Oxanium SemiBold"), "hud.font for the countdown")
    assertFalse(has(fetched, "font:Friz Quadrata TT"), "not the stored pick")
    assertTrue(badge ~= nil, "the badge's font was set")
    local path, size, flags = badge[1], badge[2], badge[3]
    assertTrue(tostring(path):find("Oxanium", 1, true) ~= nil, "the badge's face is the skin's: " .. tostring(path))
    assertEqual(size, 13, "the badge keeps NumberFontNormal's size")
    assertEqual(flags, "OUTLINE", "and its flags")
end)

test("HUD skin: the unit label follows hud.font, and a false companion is the player's face", function()
    -- red under: reading the companion through sv(), whose truthiness test turns false into
    -- the fallback
    local inst, fetched = boot()
    local NS = inst.NS
    local UL = NS:GetModule("UnitLabel")
    clear(fetched)
    UL:Apply(UL:GetInstance("target"))
    assertTrue(has(fetched, "font:Ka0s Oxanium SemiBold"))
    NS.db.profile.units.target.label.style.fontFromSkin = false
    clear(fetched)
    UL:Apply(UL:GetInstance("target"))
    assertTrue(has(fetched, "font:Friz Quadrata TT"), "off: the stored face")
end)

test("HUD skin: a skin switch repaints the HUD with no stored value moved", function()
    -- red under: no OnLooksChanged subscription in the three HUD modules, or a structure
    -- signature that signs the stored picks rather than the resolved ones
    local inst, fetched = boot()
    local NS = inst.NS
    local Skin = inst.mocks.LibStub("LibKa0s-Skin-1.0")
    local want = Skin:ResolveSkin("obsidian")["bar.texture"]
    assertTrue(type(want) == "string" and want ~= "Ka0s Default", "sanity: Obsidian has a bar texture of its own")
    local Castbar = NS:GetModule("Castbar")
    Castbar:Reskin(Castbar:GetInstance("target"), true)
    clear(fetched)
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    assertTrue(has(fetched, "statusbar:" .. want), "the cast bar took Obsidian's texture")
    assertTrue(has(fetched, "font:" .. Skin:ResolveSkin("obsidian")["hud.font"]), "and its HUD face")
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
end)

test("HUD skin: no repaint while the addon is stood down", function()
    -- red under: an OnLooksChanged handler without the NS.IsDown guard, which would re-show
    -- the labels Suspend hid
    local inst, fetched = boot()
    local NS = inst.NS
    local Skin = inst.mocks.LibStub("LibKa0s-Skin-1.0")
    local down = NS.IsDown
    NS.IsDown = function() return true end
    clear(fetched)
    Skin:SetChoice(OWNER, "ka0s", "obsidian")
    NS.IsDown = down
    assertFalse(has(fetched, "font:" .. Skin:ResolveSkin("obsidian")["hud.font"]), "nothing redrew")
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
end)

-- ── the one-time reset (O2) ─────────────────────────────────────────────────

--- A v5 account whose Default profile saved every companion false and no reset record: the shape
--- only a pre-reset store could have, so the step's write is visible.
local function v5Saved(extraProfiles)
    local units = {}
    for _, unit in ipairs(UNITS) do
        units[unit] = { icons = {}, castbar = { interruptible = {}, uninterruptible = {} },
                        label = { style = {} } }
    end
    local profile = { units = units }
    local rels = { "icons.borderTextureFromSkin", "icons.cooldownTextFontFromSkin",
        "castbar.fontFromSkin", "castbar.interruptible.statusBarTextureFromSkin",
        "castbar.interruptible.borderTextureFromSkin", "castbar.uninterruptible.statusBarTextureFromSkin",
        "castbar.uninterruptible.borderTextureFromSkin", "label.style.fontFromSkin" }
    for _, unit in ipairs(UNITS) do
        for _, rel in ipairs(rels) do put(profile, "units." .. unit .. "." .. rel, false) end
    end
    profile.units.target.castbar.font = "Arial Narrow"   -- a pick of the player's own
    local profiles = { Default = profile }
    for k, v in pairs(extraProfiles or {}) do profiles[k] = v end
    return { global = { schemaVersion = 5 }, profiles = profiles }
end

test("HUD skin: the reset puts every companion on the skin once, keeps the picks, and stamps v6", function()
    -- red under: no migrations[5], NS.SCHEMA_VERSION left at 5, a reset that overwrote the
    -- stored pick, or one that missed a unit
    local inst = boot(v5Saved())
    local NS = inst.NS
    assertEqual(NS.SCHEMA_VERSION, 6)
    assertEqual(NS.db.global.schemaVersion, 6)
    for _, unit in ipairs(UNITS) do
        for _, rel in ipairs(NS.Database.HUD_SKIN_COMPANIONS) do
            local path = "units." .. unit .. "." .. rel
            assertEqual(at(NS.db.profile, path), true, path)
        end
    end
    assertEqual(NS.db.profile.units.target.castbar.font, "Arial Narrow", "the stored pick is kept")
    assertEqual(NS.db.profile.skin.hudReset, true, "the profile records the reset")
end)

test("HUD skin: a pick turned off after the reset is never reset again", function()
    -- red under: a step gated on shape or on the account stamp alone, which would put the
    -- player's later choice back on the skin at the next login or profile event
    local saved = v5Saved()
    local inst = boot(saved)
    local NS = inst.NS
    NS.db.profile.units.target.castbar.fontFromSkin = false
    NS.db.profile.units.focus.icons.borderTextureFromSkin = false
    NS.Database:MigrateHudSkin(NS.db)
    NS.Database:OnProfileChanged("OnProfileChanged", NS.db, "Default")
    assertEqual(NS.db.profile.units.target.castbar.fontFromSkin, false, "kept across a profile event")
    assertEqual(NS.db.profile.units.focus.icons.borderTextureFromSkin, false)

    -- And across a reload of the same SavedVariables (the record is stored, the companion too).
    local again = boot({ global = { schemaVersion = 6 }, profiles = { Default = {
        skin = { hudReset = true },
        units = { target = { castbar = { fontFromSkin = false } } },
    } } }).NS
    assertEqual(again.db.profile.units.target.castbar.fontFromSkin, false, "kept across a reload")
end)

test("HUD skin: a profile that was not active at the upgrade is reset when it becomes active", function()
    -- red under: MigrateHudSkin dropped from Database:OnProfileChanged (the ladder ran once, on
    -- the profile active at the upgrade)
    local alt = { units = { target = { castbar = { fontFromSkin = false } } } }
    local NS = boot(v5Saved({ Alt = alt })).NS
    assertEqual(NS.db.global.schemaVersion, 6, "sanity: the account stamp is already current")
    NS.db:SetProfile("Alt")
    assertEqual(NS.db.profile.units.target.castbar.fontFromSkin, true, "Alt was put on the skin")
    assertEqual(NS.db.profile.skin.hudReset, true)
end)

test("HUD skin: without the library the step still sets the companions", function()
    -- red under: a step that returns when LibKa0s-Skin-1.0 is absent, leaving the record unset
    -- or the companions where they were
    local inst = boot(v5Saved(), { libFiles = {} })
    local NS = inst.NS
    assertEqual(NS.db.profile.units.target.castbar.fontFromSkin, true)
    assertEqual(NS.db.profile.units.focus.label.style.fontFromSkin, true)
    assertEqual(NS.db.profile.skin.hudReset, true)
    -- And the degraded HUD draws the stored pick, the host copy holding no HUD token.
    assertEqual(NS.SkinResolve("hud.font", "Arial Narrow", true), "Arial Narrow")
end)

test("HUD skin: the step names only companions that read a boolean", function()
    -- red under: handing ResetToSkin a missing companion, which writes the FROM_SKIN sentinel
    -- into it
    local NS = boot().NS
    local db = { profile = {
        skin = { hudReset = false },
        units = { target = { castbar = { fontFromSkin = false }, label = { style = {} } } },
    } }
    NS.Database:MigrateHudSkin(db)
    assertEqual(db.profile.units.target.castbar.fontFromSkin, true, "a present companion is set")
    assertEqual(db.profile.units.target.label.style.fontFromSkin, nil, "no sentinel written")
    assertEqual(db.profile.skin.hudReset, true)
end)

-- ── Copy from Target ────────────────────────────────────────────────────────

test("HUD skin: Copy from Target carries the companions with the pickers", function()
    -- red under: a copy that walked a hand list of picker paths
    local NS = boot().NS
    NS.db.profile.units.target.castbar.interruptible.statusBarTextureFromSkin = false
    NS.db.profile.units.focus.castbar.interruptible.statusBarTextureFromSkin = true
    assertTrue(NS.Units.CopyStyling("target", "focus"), "sanity: the copy ran")
    assertEqual(NS.db.profile.units.focus.castbar.interruptible.statusBarTextureFromSkin, false)
end)
