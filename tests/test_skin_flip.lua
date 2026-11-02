-- tests/test_skin_flip.lua — the HUD's colors and shadows follow the skin (FS-KC-FLIP, causes D2, D4,
-- D5 and D6 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING).
--
-- What this addon owes (LibKa0s Options doc, "Moving to this version"): each color and shadow has a
-- "Use the skin's ..." companion, default on, drawn after the class color and before the stored
-- swatch; Ka0s Default keeps this addon's pixels; the cooldown tint and the cast bar's fill colors,
-- which carry a meaning, are not touched; and the one per-profile step moves existing profiles,
-- naming companions and Font flags only, so every stored pick and color survives.
--
-- A skin-switch case spies on the drawing setters: comparing getters proves nothing, because the
-- base mock's region answers whatever the last call stored and a getter cannot tell a repaint from
-- a value left over. Every case leaves the skin on Ka0s Default.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local OWNER = "KickCD"
local UNITS = { "target", "focus" }

local function boot(saved, opts)
    return T.load(true, true, function(m)
        m.NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 13, "OUTLINE" end }
        if saved then m.KickCDDB = saved end
    end, opts)
end

local function lib(inst) return inst.mocks.LibStub("LibKa0s-Skin-1.0") end

local function onSkin(inst, key, body)
    local Skin = lib(inst)
    Skin:SetChoice(OWNER, "ka0s", key)
    local ok, err = pcall(body)
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    if not ok then error(err, 0) end
end

local function at(t, path)
    for seg in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[seg]
    end
    return t
end

local function rgba(...) return table.concat({ ... }, ",") end

--- A token's value as the setters take it, four channels.
local function token(c) return rgba(c[1], c[2], c[3], c[4] or 1) end

--- Spy on `method` of `obj`: answers a table whose `last` is the last call's arguments, joined.
local function spy(obj, method)
    local rec = { calls = 0 }
    obj[method] = function(_, ...)
        rec.calls = rec.calls + 1
        rec.last = rgba(...)
    end
    return rec
end

--- A deep, order-free print of `v`, so "byte-identical" means every leaf.
local function dump(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. dump(v[k]) end
    return "{" .. table.concat(out, ";") .. "}"
end

local function deep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end

--- A live, shown cast bar with its setters spied on.
local function castbar(inst, unit)
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance(unit or "target")
    Castbar:EnsureFrame(cb)
    Castbar:Reskin(cb, true)
    local f = cb.frame
    return Castbar, cb, {
        name = spy(f.nameText, "SetTextColor"), time = spy(f.timeText, "SetTextColor"),
        bgInt = spy(f.bgInterruptible, "SetColorTexture"), bgUnint = spy(f.bgUninterruptible, "SetColorTexture"),
        borderInt = spy(f.borderInterruptible, "SetBackdropBorderColor"),
        borderUnint = spy(f.borderUninterruptible, "SetBackdropBorderColor"),
        fillInt = spy(f.bar.interruptible, "SetStatusBarColor"),
        fillUnint = spy(f.bar.uninterruptible, "SetStatusBarColor"),
    }
end

--- A pooled icon of Target's, its setters spied on.
local function icon(inst)
    local NS = inst.NS
    local IG = NS:GetModule("IconGrid")
    local i = IG.CreateIconWidget(inst.mocks.CreateFrame("Frame"))
    i.unit = "target"
    i.border = inst.mocks.CreateFrame("Frame")
    return i, NS.db.profile.units.target.icons, {
        text = spy(i.cooldownText, "SetTextColor"), charges = spy(i.chargesText, "SetTextColor"),
        border = spy(i.border, "SetBackdropBorderColor"),
    }
end

--- The live primary icon of Target's enabled grid, ready and glowing, its setters spied on. Nothing
--- here calls the icon again: a skin switch has to reach it through IconGrid:OnSkinLooksChanged.
local function liveIcon(inst)
    local NS = inst.NS
    local gi = NS:GetModule("IconGrid"):GetInstance("target")
    assertTrue(gi.enabled, "sanity: the grid is up")
    local i = gi.ordered[1]
    assertTrue(i ~= nil, "sanity: the grid has an icon")
    NS.db.profile.units.target.icons.primaryGlowTrigger = "always"
    i:Apply({ ready = true }, true)
    return i, {
        text = spy(i.cooldownText, "SetTextColor"), charges = spy(i.chargesText, "SetTextColor"),
        border = spy(i.border, "SetBackdropBorderColor"),
    }
end

--- Run `body` with NS.GlowLib.Start recording the color it is handed; `body` gets the record, whose
--- `n` counts the starts and whose `last` is the last color.
local function onGlowSpy(NS, body)
    local rec = { n = 0 }
    local start = NS.GlowLib.Start
    NS.GlowLib.Start = function(_, _, opts)
        rec.n = rec.n + 1
        rec.last = rgba(unpack(opts.color))
        return true
    end
    local ok, err = pcall(body, rec)
    NS.GlowLib.Start = start
    if not ok then error(err, 0) end
end

-- ── the rows and the defaults ───────────────────────────────────────────────

local COLOR_ROWS = {
    ["icons.borderColorFromSkin"] = "icons.borderColor",
    ["icons.cooldownTextColorFromSkin"] = "icons.cooldownTextColor",
    ["icons.cooldownTextShadowFromSkin"] = "icons.cooldownTextShadow",
    ["icons.primaryGlowColorFromSkin"] = "icons.primaryGlowColor",
    ["icons.secondaryGlowColorFromSkin"] = "icons.secondaryGlowColor",
    ["castbar.textColorFromSkin"] = "castbar.textColor",
    ["castbar.fontShadowFromSkin"] = "castbar.fontShadow",
    ["castbar.interruptible.bgColorFromSkin"] = "castbar.interruptible.bgColor",
    ["castbar.interruptible.nameTextColorFromSkin"] = "castbar.interruptible.nameTextColor",
    ["castbar.interruptible.borderColorFromSkin"] = "castbar.interruptible.borderColor",
    ["castbar.uninterruptible.bgColorFromSkin"] = "castbar.uninterruptible.bgColor",
    ["castbar.uninterruptible.nameTextColorFromSkin"] = "castbar.uninterruptible.nameTextColor",
    ["castbar.uninterruptible.borderColorFromSkin"] = "castbar.uninterruptible.borderColor",
    ["label.style.colorFromSkin"] = "label.style.color",
    ["label.style.shadowFromSkin"] = "label.style.shadow",
}

test("skin flip: every color and shadow companion is a bool row defaulting on, in both places", function()
    -- red under: a composer call without its `extra`, or defaults/Profile.lua and the row disagreeing
    local NS = boot().NS
    for _, unit in ipairs(UNITS) do
        for rel, governed in pairs(COLOR_ROWS) do
            local path = "units." .. unit .. "." .. rel
            local row = NS.Settings.Store.FindRow(path)
            assertTrue(row ~= nil, "no row at " .. path)
            assertEqual(row.type, "bool", path)
            assertEqual(row.default, true, path .. " on the row")
            assertEqual(at(NS.DEFAULT_PROFILE, path), true, path .. " in AceDB's defaults")
            assertTrue(row.desc:find("not read while this is on", 1, true) ~= nil, path .. "'s tooltip")
            -- A swatch stays live and keeps its value (options-ui-§17).
            local swatch = NS.Settings.Store.FindRow("units." .. unit .. "." .. governed)
            assertEqual(swatch.disabledIf, nil, governed .. " carries no disabledIf")
        end
    end
end)

test("skin flip: a meaning color has no companion, and no class toggle has one", function()
    -- red under: a companion on the cooldown tint (D5: glow only), the cast bar's fills (MC) or a toggle
    local NS = boot().NS
    for _, rel in ipairs({ "icons.cooldownTintFromSkin", "castbar.interruptible.barColorFromSkin",
        "castbar.uninterruptible.barColorFromSkin", "icons.useClassColorBorderFromSkin" }) do
        assertEqual(NS.Settings.Store.FindRow("units.target." .. rel), nil, rel)
        assertEqual(at(NS.DEFAULT_PROFILE, "units.target." .. rel), nil, rel)
    end
    assertEqual(NS.DEFAULT_PROFILE.skin.ignorePanel, true, "the settings panel stays stock by default")
    assertEqual(NS.DEFAULT_PROFILE.skin.ignoreFonts, false)
end)

test("skin flip: the picks' defaults moved to the Ka0s picks, in both places", function()
    -- red under: a composer's spec.defaults still stating the client pick, which wins over the Ka0s one
    local NS = boot().NS
    for rel, want in pairs({
        ["icons.cooldownTextFont"] = "Ka0s Prototype", ["castbar.font"] = "Ka0s Prototype",
        ["label.style.font"] = "Ka0s Prototype", ["castbar.interruptible.statusBarTexture"] = "Ka0s Default",
        ["castbar.uninterruptible.statusBarTexture"] = "Ka0s Default",
        ["icons.cooldownTextFlags"] = "@skin", ["castbar.fontFlags"] = "@skin", ["label.style.flags"] = "@skin",
    }) do
        local path = "units.target." .. rel
        assertEqual(NS.Settings.Store.FindRow(path).default, want, path .. " on the row")
        assertEqual(at(NS.DEFAULT_PROFILE, path), want, path .. " in AceDB's defaults")
    end
end)

-- ── what the HUD draws ──────────────────────────────────────────────────────

test("skin flip: Ka0s Default keeps this addon's pixels, with no shadow", function()
    -- red under: an owner token dropped (the glow reads glow.color's gold) or a companion on the wrong token
    local inst = boot()
    local NS = inst.NS
    local Castbar, cb, s = castbar(inst)
    Castbar:Reskin(cb)
    assertEqual(s.name.last, rgba(1, 1, 1, 1), "the spell name")
    assertEqual(s.time.last, rgba(1, 1, 1, 1), "the cast time")
    assertEqual(s.bgInt.last, rgba(0, 0, 0, 0.5), "the background")
    assertEqual(s.borderInt.last, rgba(0, 0, 0, 1), "the border")
    local i, cfg, is = icon(inst)
    i:ApplyAppearance(cfg)
    i:ApplyTextConfig(cfg)
    assertEqual(is.border.last, rgba(0, 0, 0, 1), "the icon border")
    assertEqual(is.text.last, rgba(1, 1, 1, 1), "the countdown")
    assertEqual(is.charges.last, rgba(1, 1, 1, 1), "the charges badge, as NumberFontNormal draws it")
    assertEqual(rgba(NS:GetModule("IconGrid").UnpackGlowColor(cfg.primaryGlowColor, false, true)),
        rgba(1, 1, 0, 1), "the ready glow keeps its yellow, not the skin's gold")
    assertEqual(NS.Skin.HudShadow(), false, "Ka0s Default draws no HUD shadow")
    local UL = NS:GetModule("UnitLabel")
    local li = UL:GetInstance("target")
    UL:Apply(li)
    local label = spy(li.text, "SetTextColor")
    UL:Apply(li)
    assertEqual(label.last, rgba(1, 0.82, 0, 1), "the label's gold")
end)

test("skin flip: a skin switch redraws every flipped surface with the skin's tokens", function()
    -- red under: a surface still reading the stored swatch, or IconGrid:OnSkinLooksChanged not reaching
    -- the live grid: nothing below calls an icon by hand
    local inst = boot()
    local NS = inst.NS
    local T2 = lib(inst):ResolveSkin("obsidian")
    local _, _, s = castbar(inst)
    assertTrue(token(T2["hud.text"]) ~= rgba(1, 1, 1, 1), "sanity: Obsidian's HUD text is not white")
    assertTrue(token(T2["hud.label"]) ~= rgba(1, 0.82, 0, 1), "sanity: its label is not gold")
    assertTrue(token(T2["glow.color"]) ~= rgba(1, 1, 0, 1), "sanity: its glow is not yellow")
    local UL = NS:GetModule("UnitLabel")
    local li = UL:GetInstance("target")
    UL:Apply(li)
    local label = spy(li.text, "SetTextColor")
    onGlowSpy(NS, function(glow)
        local _, is = liveIcon(inst)
        onSkin(inst, "obsidian", function()
            assertEqual(s.name.last, token(T2["hud.text"]), "the spell name")
            assertEqual(s.time.last, token(T2["hud.text"]), "the cast time")
            assertEqual(s.bgInt.last, token(T2["bar.bg"]), "the interruptible background")
            assertEqual(s.bgUnint.last, token(T2["bar.bg"]), "the uninterruptible background")
            assertEqual(s.borderInt.last, token(T2["icon.border"]), "the interruptible border")
            assertEqual(s.borderUnint.last, token(T2["icon.border"]), "the uninterruptible border")
            assertEqual(label.last, token(T2["hud.label"]), "the label")
            assertEqual(is.border.last, token(T2["icon.border"]), "the icon border")
            assertEqual(is.text.last, token(T2["hud.text"]), "the countdown")
            assertEqual(is.charges.last, token(T2["hud.text"]), "the charges badge")
            assertEqual(glow.last, token(T2["glow.color"]), "the running ready glow")
        end)
    end)
end)

test("skin flip: a live cast's spell name follows the skin through the curve, per state", function()
    -- red under: applyLiveVisuals reading the stored color on either state, where only a real cast
    -- shows it: the preview branch never reaches the curve
    local inst = boot()
    local NS = inst.NS
    local T2 = lib(inst):ResolveSkin("obsidian")
    local Castbar, cb, s = castbar(inst)
    local c = NS.db.profile.units.target.castbar
    local curve = inst.mocks.C_CurveUtil
    local eval = curve.EvaluateColorValueFromBoolean
    local pairsSeen = {}
    curve.EvaluateColorValueFromBoolean = function(flag, whenTrue, whenFalse)
        pairsSeen[#pairsSeen + 1] = { whenTrue, whenFalse }
        return eval(flag, whenTrue, whenFalse)
    end
    --- The last four pairs are the name's channels: whenTrue is the uninterruptible state's.
    local function channels(which)
        local out = {}
        for n = #pairsSeen - 3, #pairsSeen do out[#out + 1] = pairsSeen[n][which] end
        return rgba(unpack(out))
    end
    local ok, err = pcall(function()
        cb.current = { notInterruptible = false }
        onSkin(inst, "obsidian", function()
            Castbar:ApplyState(cb)
            assertEqual(channels(1), token(T2["hud.text"]), "the uninterruptible name, on the curve")
            assertEqual(channels(2), token(T2["hud.text"]), "the interruptible name, on the curve")
            assertEqual(s.name.last, token(T2["hud.text"]), "and what the string took")
            c.interruptible.nameTextColorFromSkin = false
            c.interruptible.nameTextColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
            c.uninterruptible.nameTextColorFromSkin = false
            c.uninterruptible.nameTextColor = { r = 0.5, g = 0.6, b = 0.7, a = 0.8 }
            Castbar:ApplyState(cb)
            assertEqual(channels(1), rgba(0.5, 0.6, 0.7, 0.8), "companion off: the stored uninterruptible")
            assertEqual(channels(2), rgba(0.1, 0.2, 0.3, 0.4), "companion off: the stored interruptible")
            assertEqual(s.name.last, rgba(0.1, 0.2, 0.3, 0.4), "and what an interruptible cast draws")
            cb.current = { notInterruptible = true }
            Castbar:ApplyState(cb)
            assertEqual(s.name.last, rgba(0.5, 0.6, 0.7, 0.8), "and an uninterruptible one")
        end)
    end)
    curve.EvaluateColorValueFromBoolean = eval
    cb.current = nil
    if not ok then error(err, 0) end
end)

test("skin flip: each slot's glow reaches the driver in the skin's color through UpdateGlow", function()
    -- red under: glowConfig not answering a slot's companion, or UpdateGlow not handing it to StartGlow:
    -- the glow then draws the stored yellow on every skin, and the idempotency gate, comparing that same
    -- yellow, leaves the old glow running through a switch
    local inst = boot()
    local NS = inst.NS
    local T2 = lib(inst):ResolveSkin("obsidian")
    local yellow = rgba(1, 1, 0, 1)
    for slot, keys in pairs({
        primary = { trigger = "primaryGlowTrigger", companion = "primaryGlowColorFromSkin" },
        secondary = { trigger = "secondaryGlowTrigger", companion = "secondaryGlowColorFromSkin" },
    }) do
        local i, cfg = icon(inst)
        i.cfg, i._isPrimary = cfg, slot == "primary"
        i.glow = inst.mocks.CreateFrame("Frame")
        cfg[keys.trigger] = "always"
        onGlowSpy(NS, function(glow)
            i:UpdateGlow({ ready = true })
            assertEqual(glow.last, yellow, slot .. ": sanity, Ka0s Default's yellow")
            local n = glow.n
            i:UpdateGlow({ ready = true })
            assertEqual(glow.n, n, slot .. ": the gate holds on a repeat")
            onSkin(inst, "obsidian", function()
                i:UpdateGlow({ ready = true })
                assertTrue(glow.n > n, slot .. ": a skin switch restarts it")
                assertEqual(glow.last, token(T2["glow.color"]), slot .. ": in the skin's color")
                cfg[keys.companion] = false
                i:UpdateGlow({ ready = true })
                assertEqual(glow.last, yellow, slot .. ": the companion off draws the stored color")
            end)
        end)
    end
end)

test("skin flip: the meaning colors do not move with the skin", function()
    -- red under: the cast bar's fill colors, or the cooldown tint, put on a token
    local inst = boot()
    local NS = inst.NS
    local _, _, s = castbar(inst)
    local before = NS.db.profile.units.target.icons.cooldownTint
    onSkin(inst, "obsidian", function()
        assertEqual(s.fillInt.last, rgba(1, 0.85, 0.05, 1), "the interruptible yellow")
        assertEqual(s.fillUnint.last, rgba(0.85, 0.1, 0.1, 1), "the uninterruptible red")
    end)
    assertEqual(dump(before), dump({ r = 1, g = 0.4, b = 0.4, a = 1 }), "the cooldown tint is stored as it was")
end)

test("skin flip: a companion off draws the stored swatch under every skin", function()
    -- red under: reading the skin with the companion ignored
    local inst = boot()
    local NS = inst.NS
    local u = NS.db.profile.units.target
    local c, sc = u.castbar, u.castbar.interruptible
    c.textColorFromSkin, c.textColor = false, { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
    sc.nameTextColorFromSkin, sc.nameTextColor = false, { r = 0.5, g = 0.6, b = 0.7, a = 0.8 }
    sc.bgColorFromSkin, sc.bgColor = false, { r = 0.2, g = 0.3, b = 0.4, a = 0.5 }
    sc.borderColorFromSkin, sc.borderColor = false, { r = 0.3, g = 0.4, b = 0.5, a = 0.6 }
    local Castbar, cb, s = castbar(inst)
    onSkin(inst, "obsidian", function()
        Castbar:Reskin(cb)
        assertEqual(s.time.last, rgba(0.1, 0.2, 0.3, 0.4), "the cast time")
        assertEqual(s.name.last, rgba(0.5, 0.6, 0.7, 0.8), "the spell name")
        assertEqual(s.bgInt.last, rgba(0.2, 0.3, 0.4, 0.5), "the background")
        assertEqual(s.borderInt.last, rgba(0.3, 0.4, 0.5, 0.6), "the border")
        local swatch = { r = 0.9, g = 0.8, b = 0.7, a = 1 }
        assertEqual(rgba(NS:GetModule("IconGrid").UnpackGlowColor(swatch, false, false)),
            rgba(0.9, 0.8, 0.7, 1), "the glow")
    end)
end)

test("skin flip: a class color comes first, whatever the companion says", function()
    -- red under: the companion read ahead of useClassColor
    local inst = T.load(true, true, function(m)
        m.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 0.9, b = 0.8 } }
        m.UnitClass = function() return "Priest", "PRIEST", 5 end
    end)
    local NS = inst.NS
    onSkin(inst, "obsidian", function()
        local stored = { r = 0, g = 0, b = 0, a = 0.5 }
        assertEqual(rgba(NS.SkinHudColor(stored, true, "target", true, "HudTextColor")), rgba(1, 0.9, 0.8, 0.5))
        assertEqual(rgba(NS:GetModule("IconGrid").UnpackGlowColor(stored, true, true)), rgba(1, 0.9, 0.8, 0.5))
    end)
end)

test("skin flip: the shadow lands on a font object on all three texts", function()
    -- red under: SetShadow* left on the FontString, which a 12.0.7 client does not draw
    local inst = boot()
    local NS = inst.NS
    local objects = {}
    local saved = rawget(_G, "CreateFont")
    rawset(_G, "CreateFont", function(name)
        local o = { name = name }
        for _, m in ipairs({ "SetFont", "SetShadowColor", "SetShadowOffset" }) do
            o[m] = function(_, ...) o[m .. "Args"] = rgba(...); if m == "SetFont" then o.face = { ... } end end
        end
        -- A real font object answers its face (LibKa0s R3-DR-1L reads it back to hold the face).
        o.GetFont = function() return unpack(o.face or {}) end
        objects[#objects + 1] = o
        return o
    end)
    local ok, err = pcall(function()
        local Castbar, cb = castbar(inst)
        local f = cb.frame
        local handed = {}
        f.nameText.SetFontObject = function(_, o) handed.name = o end
        f.timeText.SetFontObject = function(_, o) handed.time = o end
        local i, cfg = icon(inst)
        i.cooldownText.SetFontObject = function(_, o) handed.icon = o end
        local UL = NS:GetModule("UnitLabel")
        local li = UL:GetInstance("target")
        UL:Apply(li)
        li.text.SetFontObject = function(_, o) handed.label = o end
        -- Stored on, companion off: the stored row draws, under every skin.
        local unit = NS.db.profile.units.target
        unit.castbar.fontShadow, unit.castbar.fontShadowFromSkin = true, false
        unit.icons.cooldownTextShadow, unit.icons.cooldownTextShadowFromSkin = true, false
        unit.label.style.shadow, unit.label.style.shadowFromSkin = true, false
        Castbar:Reskin(cb, true)
        i:ApplyTextConfig(cfg)
        UL:Apply(li)
        for _, key in ipairs({ "name", "time", "icon", "label" }) do
            local o = handed[key]
            assertTrue(o ~= nil, key .. " took a font object")
            assertEqual(o.SetShadowOffsetArgs, rgba(1, -1), key .. "'s shadow")
            assertEqual(o.SetShadowColorArgs, rgba(0, 0, 0, 1), key .. "'s shadow color")
        end
        -- One object per look, shared (SkinPaintExtras minor 16): the bar's two strings are one look.
        assertTrue(handed.name == handed.time, "two strings of one look share an object")
        unit.label.style.size = 31
        UL:Apply(li)
        assertTrue(handed.label ~= handed.name, "another look takes another object")
    end)
    rawset(_G, "CreateFont", saved)
    assertTrue(#objects >= 2, "a font object per look")
    if not ok then error(err, 0) end
end)

test("skin flip: Ignore fonts leaves the stored shadow standing", function()
    -- red under: S.HudShadow's nil read as no shadow
    local inst = boot()
    local NS = inst.NS
    local Skin = lib(inst)
    NS.db.profile.units.target.castbar.fontShadow = true
    Skin:SetIgnore(OWNER, nil, true)
    local ok, err = pcall(function()
        local Castbar, cb = castbar(inst)
        Castbar:Reskin(cb, true)
        local x, y = cb.frame.nameText:GetShadowOffset()
        assertEqual(rgba(x, y), rgba(1, -1), "the stored row draws")
    end)
    Skin:SetIgnore(OWNER, nil, false)
    if not ok then error(err, 0) end
end)

test("skin flip: a shadow alone moves the guarded half of the cast bar's re-skin", function()
    -- red under: a structure signature that signs tostring(c.fontShadow) and not S.HudShadow's answer:
    -- two skins alike in face, size and flags leave the old shadow up (the Options doc, section 5).
    local inst = boot()
    local NS = inst.NS
    local Castbar, cb = castbar(inst)
    local font = NS.Skin.HudFont
    local calls = 0
    local f = cb.frame
    NS.Skin.HudFont = function(fs, opts)
        if fs == f.nameText or fs == f.timeText then calls = calls + 1 end
        return font(fs, opts)
    end
    local shadow = NS.Skin.HudShadow
    local ok, err = pcall(function()
        Castbar:Reskin(cb)
        assertEqual(calls, 0, "sanity: an unchanged signature skips the font pass")
        NS.Skin.HudShadow = function() return 2, -2, 0, 0, 0, 1 end
        Castbar:OnSkinLooksChanged()
        assertEqual(calls, 2, "both strings redrew for the shadow alone")
        NS.Skin.HudShadow = function() return nil end
        Castbar:OnSkinLooksChanged()
        assertEqual(calls, 4, "and for Ignore fonts' nil")
    end)
    NS.Skin.HudFont, NS.Skin.HudShadow = font, shadow
    if not ok then error(err, 0) end
end)

test("skin flip: the companion toggle moves the signature too", function()
    local inst = boot()
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local c = NS.db.profile.units.target.castbar
    local i, u = Castbar.INT_FALLBACK, Castbar.UNINT_FALLBACK
    local before = Castbar.StructureSignature(c, i, u, 250, 24)
    c.fontShadowFromSkin = false
    assertTrue(Castbar.StructureSignature(c, i, u, 250, 24) ~= before, "the companion is signed")
end)

test("skin flip: with no library HudFont still draws and the stored colors stand", function()
    -- red under: a no-op HudFont, which leaves the HUD with no face, or "@skin" handed to SetFont
    local inst = boot(nil, { libFiles = {} })
    local S = inst.NS.Skin
    local calls = {}
    local fs = {}
    for _, m in ipairs({ "SetFont", "SetShadowColor", "SetShadowOffset" }) do
        fs[m] = function(_, ...) calls[m] = rgba(...) end
    end
    S.HudFont(fs, { face = "Fonts\\Host.ttf", size = 14, flags = "@skin", shadow = true })
    assertEqual(calls.SetFont, rgba("Fonts\\Host.ttf", 14, "OUTLINE"), "the sentinel resolved")
    assertEqual(calls.SetShadowOffset, rgba(1, -1))
    S.HudFont(fs, { face = "Fonts\\Host.ttf", size = 14, flags = "OUTLINE", shadow = false })
    assertEqual(calls.SetShadowColor, rgba(0, 0, 0, 0), "the off arm writes")
    assertEqual(rgba(inst.NS.SkinHudColor({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 }, false, nil, true, "HudTextColor")),
        rgba(0.1, 0.2, 0.3, 0.4), "the stored color is the fallback")
    assertEqual(S.MarkText("p", 12), "|Tp:12:12|t", "a string a caller concatenates")
end)

-- ── gloss (FS-KC-FIX, cause A3) ─────────────────────────────────────────────

--- A live cast bar on the kit's paint recorder: the base mock's bars are no StatusBar, and the
--- library leaves those alone, so a gloss test without it passes vacuously.
local function paintedBars()
    local inst = boot()
    local NS = inst.NS
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    Castbar:EnsureFrame(cb)
    -- After the load, because the recorder is strict about regions the HUD's own build touches: two
    -- real status bars in place of the base mock's.
    local restore = dofile("tests/_kit/mock_paint.lua")(inst.mocks)
    cb.frame.bar.interruptible = inst.mocks.CreateFrame("StatusBar")
    cb.frame.bar.uninterruptible = inst.mocks.CreateFrame("StatusBar")
    restore()
    Castbar:Reskin(cb, true)
    local Skin = lib(inst)
    local function gloss(state)
        local rec = Skin.painted[cb.frame.bar[state]]
        return rec and rec.regions.gloss
    end
    return inst, Castbar, cb, gloss
end

test("skin gloss: a glossy skin shines both states' fills; Ka0s Default does not", function()
    -- red under: a bar that never reads bar.gloss, or only one of the two stacked bars called
    local inst, Castbar, cb, gloss = paintedBars()
    assertEqual(cb.frame.bar.interruptible:GetObjectType(), "StatusBar", "sanity: the recorder took")
    assertEqual(gloss("interruptible"), nil, "Ka0s Default has none")
    onSkin(inst, "glass", function()
        Castbar:Reskin(cb)
        assertTrue(gloss("interruptible") ~= nil, "Glass shines the interruptible fill")
        assertTrue(gloss("uninterruptible") ~= nil, "and the uninterruptible one")
        assertEqual(gloss("interruptible"):IsShown(), true)
    end)
    assertEqual(gloss("interruptible"):IsShown(), false, "a switch away takes it off")
end)

for _, states in ipairs({ { "interruptible", "uninterruptible" }, { "uninterruptible", "interruptible" } }) do
    local own, other = states[1], states[2]
    test("skin gloss: a player's own " .. own .. " texture stays plain, through a replay", function()
        -- red under: S.BarGloss called without this state's companion, which a replay would shine again
        local inst, Castbar, cb, gloss = paintedBars()
        local state = inst.NS.db.profile.units.target.castbar[own]
        onSkin(inst, "glass", function()
            state.statusBarTextureFromSkin = false
            Castbar:Reskin(cb)
            assertEqual(gloss(other):IsShown(), true, "the other state still follows")
            local mine = gloss(own)
            assertTrue(mine == nil or mine:IsShown() == false, "the player's own texture stays plain")
            lib(inst):SetChoice(OWNER, "ka0s", "obsidian")
            lib(inst):SetChoice(OWNER, "ka0s", "glass")
            mine = gloss(own)
            assertTrue(mine == nil or mine:IsShown() == false, "and through a skin switch's replay")
            state.statusBarTextureFromSkin = true
            Castbar:Reskin(cb)
            assertEqual(gloss(own):IsShown(), true, "the companion back on")
        end)
    end)
end

-- ── the Spells rows' status glyph (FS-KC-FIX, cause L6) ─────────────────────

test("skin marks: the known glyph is the Ka0s mark in its meaning's color, the client's while ignored", function()
    -- red under: the glyph left on ReadyCheck art with the Scope cleared, or S.Mark without `panel`,
    -- which would restyle the default, stock settings panel
    local NS = T.load(true, true).NS
    local marks, released, forgotten = {}, {}, {}
    local mark, onRelease, forget = NS.Skin.Mark, NS.SkinOnRelease, NS.SkinForget
    NS.Skin.Mark = function(tex, opts) marks[#marks + 1] = { tex = tex, opts = opts } end
    NS.SkinOnRelease = function(_, fn) released[#released + 1] = fn end
    NS.SkinForget = function(tex) forgotten[#forgotten + 1] = tex end
    local ok, err = pcall(function()
        local Rows = NS.Settings.SpellsPanel
        local yes = Rows.StatusGlyphMark({ image = { name = "known" } }, true)
        local no = Rows.StatusGlyphMark({ image = { name = "unknown" } }, false)
        assertTrue(yes and no, "both rows were marked")
        assertEqual(marks[1].opts.token, "sem.good")
        assertEqual(marks[2].opts.token, "sem.bad")
        assertEqual(marks[1].opts.art, NS.Icon("confirm"), "the Ka0s tick")
        assertEqual(marks[2].opts.art, NS.Icon("close"), "the Ka0s cross")
        assertEqual(marks[1].opts.panel, true, "on the settings panel, so it obeys the Scope")
        local set
        marks[2].opts.stock({ SetTexture = function(_, art) set = art end })
        assertEqual(set, [[Interface\RaidFrame\ReadyCheck-NotReady]], "stock puts the client's art back")
        -- AceGUI pools widgets across addons, so a released row must not stay on the skin's replay.
        local white
        released[1]({ image = { SetVertexColor = function(_, ...) white = rgba(...) end } })
        assertEqual(#forgotten, 1, "a released row is forgotten")
        assertEqual(white, rgba(1, 1, 1, 1), "and its tint given back")
    end)
    NS.Skin.Mark, NS.SkinOnRelease, NS.SkinForget = mark, onRelease, forget
    if not ok then error(err, 0) end
end)

test("skin marks: a built Spells row marks its known glyph", function()
    -- red under: rowKnownGlyph not calling Spells.StatusGlyphMark, which leaves every row on the
    -- client's art under every Scope
    local inst = T.load(true, true)
    local NS = inst.NS
    local Rows = NS.Settings.SpellsPanel
    local marks = {}
    local mark, acquire = NS.Skin.Mark, Rows.Acquire
    NS.Skin.Mark = function(_, opts) marks[#marks + 1] = opts end
    -- The kit's AceGUI Icon has no texture; the real widget's `image` is what the mark paints.
    Rows.Acquire = function(gui, kind)
        local w = acquire(gui, kind)
        if kind == "Icon" then w.image = w.image or {} end
        return w
    end
    local ok, err = pcall(function()
        Rows.BuildRow(inst.mocks.__aceGUI, { { spellID = 1766 } }, 1)
        assertEqual(#marks, 1, "the row's one glyph")
        assertTrue(marks[1].token == "sem.good" or marks[1].token == "sem.bad", "on a meaning token")
    end)
    NS.Skin.Mark, Rows.Acquire = mark, acquire
    if not ok then error(err, 0) end
end)

test("skin marks: the seam forgets a texture, with the library and without", function()
    local inst = boot()
    local Skin = lib(inst)
    local tex = inst.mocks.CreateFrame("Frame")
    Skin.painted[tex] = { owner = OWNER, calls = {}, order = {} }
    inst.NS.SkinForget(tex)
    assertEqual(Skin.painted[tex], nil, "no replay reaches it")
    boot(nil, { libFiles = {} }).NS.SkinForget({})
end)

-- ── the one step ────────────────────────────────────────────────────────────

local function partial()
    return {
        skin = { source = "ka0s", skin = "obsidian", ignorePanel = false, ignoreFonts = true },
        units = {
            target = {
                icons = {
                    cooldownTextFont = "My Font", cooldownTextFontFromSkin = false, cooldownTextSize = 15,
                    cooldownTextColor = { r = 0.9 }, cooldownTextShadow = true, cooldownTextFlags = "THICKOUTLINE",
                    borderColor = { g = 0.5 }, borderColorFromSkin = false, useClassColorBorder = true,
                    primaryGlowColor = { r = 0.2, g = 0.3, b = 0.4, a = 1 }, cooldownTint = { r = 0.1 },
                    borderTexture = "My Border",
                },
                castbar = {
                    font = "My Font", fontShadow = true, fontShadowFromSkin = false, fontFlags = "MONOCHROME",
                    interruptible = { barColor = { r = 0.1 }, bgColor = { a = 0.2 }, statusBarTexture = "My Bar",
                        useClassColorBar = true, nameTextColorFromSkin = false },
                    -- uninterruptible: the whole sub-table is missing.
                },
                label = { style = { color = { b = 0.6 }, colorFromSkin = false, font = "Ka0s Kait", flags = "" } },
            },
            -- A unit with no tables at all, and one whose label has no style.
            focus = { link = false, label = {} },
        },
    }
end

--- The profile's stored values, companions and the three flags keys taken out.
local function picks(p)
    local kept = deep(p)
    local function strip(t)
        for k, v in pairs(t) do
            if type(k) == "string" and (k:match("FromSkin$") or k == "cooldownTextFlags"
                or k == "fontFlags" or k == "flags") then
                t[k] = nil
            elseif type(v) == "table" then
                strip(v)
            end
        end
    end
    strip(kept.units)
    kept.skin.fullSkinReset = nil
    return dump(kept.units) .. dump(kept.skin)
end

test("the step: every listed key follows and every stored pick and color is byte-identical", function()
    -- red under: a bare color key in the list, which takes "@skin", or a list that misses a companion
    local NS = boot().NS
    local p = partial()
    local before = picks(p)
    assertEqual(NS.Database:MigrateFullSkin({ profile = p }), true, "it ran")
    assertEqual(picks(p), before, "no pick, color, toggle or size moved")
    assertEqual(p.skin.fullSkinReset, true, "recorded per profile")
    for _, rel in ipairs(NS.Database.FULL_SKIN_RELS) do
        local v = at(p, "units.target." .. rel)
        if rel:match("FromSkin$") then
            if rel:find("uninterruptible", 1, true) then
                assertEqual(v, nil, rel .. ": a path through a missing table is skipped")
            else
                assertEqual(v, true, rel)
            end
        else
            assertEqual(v, "@skin", rel .. ": a flags key the step names")
        end
    end
    assertEqual(p.units.focus.icons, nil, "no table is created on the way")
    assertEqual(p.units.focus.label.style, nil)
    assertEqual(p.units.target.skin, nil, "no stray skin table on an entry")
    assertEqual(p.units.focus.skin, nil)
    assertEqual(p.units.target.icons.useClassColorBorder, true, "a class toggle stays")
    assertEqual(p.skin.ignorePanel, false, "skin.ignorePanel stays")
    assertEqual(p.skin.ignoreFonts, true, "skin.ignoreFonts stays")
end)

test("the step holds the sentinel to the flags keys alone", function()
    local NS = boot().NS
    local p = partial()
    NS.Database:MigrateFullSkin({ profile = p })
    local function walk(t, name)
        for k, v in pairs(t) do
            if type(v) == "table" then
                walk(v, name .. "." .. tostring(k))
            elseif v == "@skin" then
                assertTrue(k == "cooldownTextFlags" or k == "fontFlags" or k == "flags", name .. "." .. tostring(k))
            end
        end
    end
    walk(p, "profile")
end)

test("the step names no size, meaning color, class toggle, Scope key, color or pick", function()
    -- red under: any of these in FULL_SKIN_RELS
    local NS = boot().NS
    local allowed = { cooldownTextFlags = true, fontFlags = true, flags = true }
    for _, rel in ipairs(NS.Database.FULL_SKIN_RELS) do
        local leaf = rel:match("([^.]+)$")
        assertTrue(leaf:match("FromSkin$") ~= nil or allowed[leaf] == true, rel)
        assertTrue(leaf:find("useClassColor", 1, true) == nil, rel)
    end
    assertEqual(#NS.Database.FULL_SKIN_RELS, 26, "fifteen new, eight kept and three flags")
    assertEqual(#NS.Database.FULL_SKIN_PATHS, 52, "per unit, from the profile's root")
end)

test("a second run writes nothing, and a companion turned off afterwards stays off", function()
    local NS = boot().NS
    local p = partial()
    local db = { profile = p }
    NS.Database:MigrateFullSkin(db)
    local once = dump(p)
    assertEqual(NS.Database:MigrateFullSkin(db), false, "the record stops it")
    assertEqual(dump(p), once, "a second run writes nothing")
    p.units.target.castbar.textColorFromSkin = false
    p.units.target.castbar.fontFlags = "OUTLINE"
    assertEqual(NS.Database:MigrateFullSkin(db), false)
    assertEqual(p.units.target.castbar.textColorFromSkin, false, "the player's later choice stays")
    assertEqual(p.units.target.castbar.fontFlags, "OUTLINE", "and a flag picked later")
end)

test("no schema row walks the record, so a companion off survives another page's Defaults", function()
    -- red under: skin.fullSkinReset given a schema row, which a Defaults walk puts back to false: the
    -- AbsorbTracker pilot's bug. The next profile event would force every companion on again.
    local inst = boot()
    local NS = inst.NS
    local H = NS.Settings.Helpers
    assertEqual(NS.Settings.Store.FindRow("skin.fullSkinReset"), nil, "no row")
    local p = NS.db.profile
    assertEqual(p.skin.fullSkinReset, true, "sanity: a new profile has been through the step")
    p.units.target.castbar.textColorFromSkin = false
    p.units.target.icons.cooldownTextFlags = "OUTLINE"
    H.RestoreDefaults("general")
    H.RestoreDefaults("label")
    assertEqual(p.skin.fullSkinReset, true, "the record survives each press")
    NS.Database:MigrateProfile()
    NS.Database:OnProfileChanged("OnProfileChanged", NS.db, "Default")
    assertEqual(p.units.target.castbar.textColorFromSkin, false, "the companion stayed off")
    assertEqual(p.units.target.icons.cooldownTextFlags, "OUTLINE", "and the flag the player picked")
end)

test("the v8 -> v9 upgrade moves the active profile, and a profile change moves another", function()
    -- red under: the step left off Database:OnProfileChanged. Not under the ladder row or the Init
    -- call alone: at stamp 8 each covers for the other, so each has a case of its own below.
    local saved = { global = { schemaVersion = 8 }, profiles = {
        Default = { skin = { hudReset = true, flagsReset = true, fontPicksKept = true },
            units = { target = { castbar = { textColorFromSkin = false, fontFlags = "THICKOUTLINE" } } } },
        Alt = { skin = { hudReset = true, flagsReset = true, fontPicksKept = true },
            units = { focus = { icons = { cooldownTextColorFromSkin = false } } } },
    } }
    local NS = boot(saved).NS
    assertEqual(NS.SCHEMA_VERSION, 9)
    assertEqual(NS.db.global.schemaVersion, 9)
    assertEqual(NS.db.profile.skin.fullSkinReset, true, "the active profile")
    assertEqual(NS.db.profile.units.target.castbar.textColorFromSkin, true)
    assertEqual(NS.db.profile.units.target.castbar.fontFlags, "@skin", "the named flag")
    NS.db:SetProfile("Alt")
    assertEqual(NS.db.profile.skin.fullSkinReset, true, "the profile not active at the upgrade")
    assertEqual(NS.db.profile.units.focus.icons.cooldownTextColorFromSkin, true)
end)

test("the ladder's v8 row runs the step", function()
    -- red under: the step left off migrations[8]
    local NS = boot().NS
    local real = NS.Database.MigrateFullSkin
    local calls = 0
    NS.Database.MigrateFullSkin = function(self, db)
        calls = calls + 1
        return real(self, db)
    end
    NS.db.global.schemaVersion = 8
    NS.Database:MigrateProfile()
    NS.Database.MigrateFullSkin = real
    assertEqual(calls, 1, "the ladder ran it")
    assertEqual(NS.db.global.schemaVersion, 9)
end)

test("a stamp already at 9 still moves a login profile with no record", function()
    -- red under: the step left off Database:Init: the ladder runs no step at this stamp, and the stamp is
    -- per account where the record is per profile, so another character's profile can arrive here
    local saved = { global = { schemaVersion = 9 }, profiles = {
        Default = { skin = { hudReset = true, flagsReset = true, fontPicksKept = true },
            units = { target = { castbar = { textColorFromSkin = false, fontFlags = "THICKOUTLINE" } } } },
    } }
    local NS = boot(saved).NS
    assertEqual(NS.db.profile.skin.fullSkinReset, true, "the login profile")
    assertEqual(NS.db.profile.units.target.castbar.textColorFromSkin, true)
    assertEqual(NS.db.profile.units.target.castbar.fontFlags, "@skin", "the named flag")
end)

test("a player's picked face goes back on the skin, the pick kept, with the rulings of 2026-11-01", function()
    -- red under: the step ahead of MigrateSkinFontPicks in Init, which would leave the box off
    local saved = { global = { schemaVersion = 7 }, profiles = { Default = {
        skin = { hudReset = true, flagsReset = true },
        units = { target = { label = { style = { font = "Ka0s Kait" } } } },
    } } }
    local NS = boot(saved).NS
    local style = NS.db.profile.units.target.label.style
    assertEqual(style.fontFromSkin, true, "overwriting a player's choice is accepted")
    assertEqual(style.font, "Ka0s Kait", "and the pick waits for the box to go off")
end)

test("the step creates the record's table on a raw profile with none", function()
    local NS = boot().NS
    local p = { units = { target = { castbar = { textColorFromSkin = false } } } }
    assertEqual(NS.Database:MigrateFullSkin({ profile = p }), true)
    assertEqual(p.skin.fullSkinReset, true, "recorded")
    assertEqual(p.units.target.castbar.textColorFromSkin, true)
    assertEqual(NS.Database:MigrateFullSkin({ profile = p }), false, "and the record stops the next one")
end)

test("the step is the same write with the library absent", function()
    -- red under: an absent-library arm that creates a table, or writes something ResetToSkin would not
    local live = boot().NS
    local bare = boot(nil, { libFiles = {} }).NS
    local p, q = partial(), partial()
    assertEqual(live.Database:MigrateFullSkin({ profile = p }), true)
    assertEqual(bare.Database:MigrateFullSkin({ profile = q }), true)
    assertEqual(dump(q), dump(p), "by hand and through FollowOnce agree")
    assertEqual(bare.Database:MigrateFullSkin({ profile = q }), false, "gated on the record there too")
end)
