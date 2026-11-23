-- tests/test_class_color_follow.lua — "Use class color" as it draws (FB-KC-01, finding K of
-- Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH).
--
-- The owner, on a hunter, with Unit > Text label > "Use class color" on, saw the stored gold label
-- color, not hunter green. Three causes, one case group each:
--   1. THE LADDER. NS.SkinHudColor skipped the skin rung whenever the class toggle was on, so an
--      unresolved class (no target, an NPC) landed on the swatch. The collection's order is a class
--      that resolved, then the skin's color while its companion is on, then the swatch
--      (options-ui-§17, standard v2.119.0; LibKa0s FollowColor, Core minor 20).
--   2. THE PREVIEW. Unlocked (KickCD's preview) or in Sim mode with no target, the described unit
--      does not exist, so its class never resolved. A preview resolves the stand-in, the player.
--   3. THE REPAINT. Nothing repainted the label or the cast bar's colors on a target or focus swap,
--      so both kept the class of whatever was targeted at the last config apply.

local T = _G.KICKCD_TEST
local test, assertEqual = T.test, T.assertEqual

local HUNTER = { r = 0.67, g = 0.83, b = 0.45 }
local ROGUE  = { r = 1, g = 0.96, b = 0.41 }
local MAGE   = { r = 0.25, g = 0.78, b = 0.92 }
local GOLD   = { r = 0.9, g = 0.7, b = 0.1, a = 1 }

local function rgba(...) return table.concat({ ... }, ",") end
local function c4(c, a) return rgba(c.r, c.g, c.b, a or 1) end
local function c3(c) return rgba(c.r, c.g, c.b) end
--- The three color channels of a joined setter call.
local function rgb(joined) return joined and joined:match("^([^,]+,[^,]+,[^,]+)") end

--- A hunter player; `world.target` / `world.focus` is the class token of that unit, or nil for no
--- such unit. `world.npc` makes every non-player unit exist with no class.
local function boot(world)
    return T.load(true, true, function(m)
        m.RAID_CLASS_COLORS = { HUNTER = HUNTER, ROGUE = ROGUE, MAGE = MAGE }
        m.UnitExists = function(unit)
            if unit == "player" then return true end
            return world.npc == true or world[unit] ~= nil
        end
        m.UnitClass = function(unit)
            if unit == "player" then return "Hunter", "HUNTER", 3 end
            local tok = world[unit]
            if tok then return tok, tok, 1 end
            return nil
        end
    end, T.ka0sDefault())
end

local function textColor(fs) return rgba(fs:GetTextColor()) end

local function label(NS, unit, over)
    local UnitLabel = NS:GetModule("UnitLabel")
    local style = NS.Units.LabelStyle(unit)
    style.color = GOLD
    for k, v in pairs(over or {}) do style[k] = v end
    local li = UnitLabel:GetInstance(unit)
    UnitLabel:Apply(li)
    return li
end

-- ── 1. the ladder ───────────────────────────────────────────────────────────────

test("class follow: an unresolved class falls to the skin's color while its companion is on", function()
    -- red under: NS.SkinHudColor skipping the skin whenever useClass is on (the swatch drew)
    local inst = boot({ npc = true })
    local NS = inst.NS
    NS.db.profile.locked = true
    local want = rgba(NS.Skin.HudLabelColor())
    assertEqual(rgba(NS.SkinHudColor(GOLD, true, "target", true, "HudLabelColor")), want, "the skin rung")
    local li = label(NS, "target", { useClassColor = true, colorFromSkin = true })
    assertEqual(textColor(li.text), want, "the label, an NPC targeted")
end)

test("class follow: a class that resolved still comes first, skin companion on or off", function()
    local inst = boot({ target = "ROGUE" })
    local NS = inst.NS
    NS.db.profile.locked = true
    for _, fromSkin in ipairs({ true, false }) do
        local li = label(NS, "target", { useClassColor = true, colorFromSkin = fromSkin })
        assertEqual(textColor(li.text), c4(ROGUE), "skin companion " .. tostring(fromSkin))
    end
end)

test("class follow: the ladder answers four numbers, never the rung's name", function()
    -- FollowColor answers a fifth value ("class"/"skin"/"stored"); a setter spy joins every argument.
    local inst = boot({ target = "ROGUE" })
    assertEqual(select("#", inst.NS.SkinHudColor(GOLD, true, "target", true, "HudLabelColor")), 4)
end)

-- ── 2. the preview ──────────────────────────────────────────────────────────────

test("class follow: unlocked with no target, the Target and Focus labels draw the player's class", function()
    -- red under: no stand-in (the class of an absent unit is nil, so the gold swatch drew)
    local inst = boot({})
    local NS = inst.NS
    NS.db.profile.locked = false
    for _, unit in ipairs({ "target", "focus" }) do
        for _, fromSkin in ipairs({ true, false }) do
            local li = label(NS, unit, { useClassColor = true, colorFromSkin = fromSkin })
            assertEqual(textColor(li.text), c4(HUNTER), unit .. ", skin companion " .. tostring(fromSkin))
        end
    end
end)

test("class follow: locked with no target there is no stand-in; the skin, then the swatch", function()
    local inst = boot({})
    local NS = inst.NS
    NS.db.profile.locked = true
    local li = label(NS, "target", { useClassColor = true, colorFromSkin = false })
    assertEqual(textColor(li.text), c4(GOLD), "the swatch")
    li = label(NS, "target", { useClassColor = true, colorFromSkin = true })
    assertEqual(textColor(li.text), rgba(NS.Skin.HudLabelColor()), "the skin")
end)

test("class follow: NS.ClassStandIn is the player while unlocked or in Sim mode, else nil", function()
    local inst = boot({})
    local NS = inst.NS
    NS.db.profile.locked = false
    assertEqual(NS.ClassStandIn(), "player")
    NS.db.profile.locked = true
    assertEqual(NS.ClassStandIn(), nil)
    local real = NS.IsSimMode
    NS.IsSimMode = function() return true end
    local got = NS.ClassStandIn()
    NS.IsSimMode = real
    assertEqual(got, "player", "Sim mode previews too")
end)

--- A live cast bar with its color setters spied on, Reskin forced.
local function castbar(NS, unit)
    local Castbar = NS:GetModule("Castbar")
    local cb = Castbar:GetInstance(unit or "target")
    Castbar:EnsureFrame(cb)
    local f, rec = cb.frame, {}
    local function spy(obj, method, key)
        obj[method] = function(_, ...) rec[key] = rgba(...) end
    end
    spy(f.timeText, "SetTextColor", "time")
    spy(f.bar.interruptible, "SetStatusBarColor", "fillInt")
    spy(f.bar.uninterruptible, "SetStatusBarColor", "fillUnint")
    spy(f.bgInterruptible, "SetColorTexture", "bgInt")
    return Castbar, cb, rec
end

test("class follow: unlocked with no target, the cast bar's fill, background and time text draw the player's class", function()
    -- red under: no stand-in in ReskinColors (NS.ResolveColor / NS.SkinHudColor on an absent unit)
    local inst = boot({})
    local NS = inst.NS
    NS.db.profile.locked = false
    local c = NS.Units.Castbar("target")
    c.useClassColorText, c.textColorFromSkin = true, false
    local ic = c.interruptible
    ic.useClassColorBar, ic.useClassColorBgColor, ic.bgColorFromSkin = true, true, true
    local Castbar, cb, rec = castbar(NS)
    Castbar:Reskin(cb, true)
    assertEqual(rgb(rec.fillInt), c3(HUNTER), "the fill")
    assertEqual(rgb(rec.time), c3(HUNTER), "the time")
    assertEqual(rgb(rec.bgInt), c3(HUNTER), "the background")
end)

-- ── 3. the repaint ──────────────────────────────────────────────────────────────

test("class follow: a target swap repaints the Target label's class color", function()
    -- red under: UnitLabel registering PLAYER_ENTERING_WORLD alone
    local world = { target = "MAGE" }
    local inst = boot(world)
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    local NS = inst.NS
    NS.db.profile.locked = true
    local li = label(NS, "target", { useClassColor = true, colorFromSkin = false })
    assertEqual(textColor(li.text), c4(MAGE), "before")
    world.target = "ROGUE"
    NS.DeliverEvent("PLAYER_TARGET_CHANGED")
    assertEqual(textColor(li.text), c4(ROGUE), "after the swap")
end)

test("class follow: a focus swap repaints the Focus label's class color", function()
    local world = { focus = "MAGE" }
    local inst = boot(world)
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    local NS = inst.NS
    NS.db.profile.locked = true
    local li = label(NS, "focus", { useClassColor = true, colorFromSkin = false })
    world.focus = "ROGUE"
    NS.DeliverEvent("PLAYER_FOCUS_CHANGED")
    assertEqual(textColor(li.text), c4(ROGUE), "after the swap")
end)

test("class follow: a target swap reruns the cast bar's colors", function()
    -- red under: Castbar:OnTargetChanged running Reevaluate alone
    local world = { target = "MAGE" }
    local inst = boot(world)
    inst.mocks.__fireEvent("PLAYER_LOGIN")
    local NS = inst.NS
    NS.db.profile.locked = true
    local c = NS.Units.Castbar("target")
    c.useClassColorText, c.textColorFromSkin = true, false
    c.interruptible.useClassColorBar = true
    local Castbar, cb, rec = castbar(NS)
    Castbar:Reskin(cb, true)
    assertEqual(rgb(rec.fillInt), c3(MAGE), "before")
    world.target = "ROGUE"
    NS.DeliverEvent("PLAYER_TARGET_CHANGED")
    assertEqual(rgb(rec.fillInt), c3(ROGUE), "the fill after the swap")
    assertEqual(rgb(rec.time), c3(ROGUE), "the time text after the swap")
end)
