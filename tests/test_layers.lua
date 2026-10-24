-- tests/test_layers.lua — the frame-layering map (frame-layering, standard v2.88.0; item 030, KC-ZS).
--
-- WHAT IT PINS. The strata and frame level of every frame class KickCD draws, read back through the
-- kit's frame-layer recorder (tests/_kit/mock_layers.lua), against the one table that names them,
-- NS.Const.LAYERS (core/Constants.lua). The ORDER is what matters and what each case states:
--
--   * inside an icon:     swipe < border < glow host < glow effect < text overlay  (KIC-Z01..Z03, CALL-06)
--   * inside a cast bar:  fill < border < spark/name/time overlay                  (KIC-Z04)
--   * across one unit:    grid content < cast bar < label < drag handles < sim strip (KIC-Z05..Z08)
--
-- WHY THE RECORDER AND NOT THE PLAIN MOCK. tests/wow_mock_frames.lua answers GetFrameLevel with the
-- frame's OWN stored level, 0 at birth, so a child is never "parent + 1" and a level set before a
-- SetParent survives it. Both are what the client does NOT do, and both are the facts this map
-- rests on. The recorder models them; the base's `__level = 0` seed is cleared at creation so the
-- recorder sees a frame with no explicit level as one (the shim in `fresh` below).
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local ROOT = T.root or "."

--- A fresh enabled instance whose every frame records layers. The install runs in the mutate hook,
--- before any source loads, so every frame the enable cascade builds is a recording one.
local function fresh()
    local inst = T.load(true, true, function(mocks)
        local base = mocks.CreateFrame
        mocks.CreateFrame = function(...)
            local f = base(...)
            if type(f) == "table" then
                rawset(f, "__level", nil)
                -- The base answers EnableMouse with a no-op; record it, so "takes no mouse" is
                -- assertable.
                rawset(f, "EnableMouse", function(self, b) rawset(self, "__mouse", b and true or false) end)
            end
            return f
        end
        rawset(mocks.UIParent, "__level", nil)
        dofile(ROOT .. "/tests/_kit/mock_layers.lua")(mocks)
    end)
    return inst.NS, inst.mocks
end

local function level(f) return f:GetFrameLevel() end

-- ── the table ───────────────────────────────────────────────────────────────

test("LAYERS names the HUD strata once, as MEDIUM", function()
    local NS = fresh()
    local LAYERS = NS.Const.LAYERS
    assertTrue(type(LAYERS) == "table", "core/Constants.lua must publish NS.Const.LAYERS")
    assertEqual(LAYERS.STRATA.HUD, "MEDIUM")
end)

test("LAYERS orders the icon ladder fill < border < effect < effect frames < overlay", function()
    local I = fresh().Const.LAYERS.LEVEL.ICON
    assertTrue(I.FILL < I.BORDER and I.BORDER < I.EFFECT, "fill < border < effect")
    assertTrue(I.EFFECT + I.GLOW < I.OVERLAY, "the glow's own frames must stay under the text overlay")
end)

test("LAYERS puts the cast bar band above every grid level and the handles above both", function()
    local L = fresh().Const.LAYERS.LEVEL
    local gridTop = L.HUD.GRID + 1 + L.ICON.OVERLAY     -- an icon's text overlay
    local barTop  = L.HUD.CASTBAR + L.CASTBAR.CONTAINER + L.CASTBAR.OVERLAY
    assertTrue(L.HUD.CASTBAR > gridTop, "the cast bar must clear the grid's whole content band")
    assertTrue(L.HUD.GRID + L.HUD.LABEL > barTop, "the label must clear the cast bar's content")
    assertTrue(L.HUD.HANDLE > L.HUD.GRID + L.HUD.LABEL, "the drag handles must clear the label")
    assertTrue(L.HUD.MARKER > barTop, "the sim strip must clear every display")
end)

-- ── the icon grid ───────────────────────────────────────────────────────────

test("the grid is a MEDIUM, clamped root at UIParent + HUD.GRID", function()
    local NS, mocks = fresh()
    local grid = NS:GetModule("IconGrid"):GetGridFrame("target")
    local s = mocks.__layers(grid)
    assertEqual(s.strata, "MEDIUM")
    assertTrue(s.clamped, "the grid is clamped to the screen")
    assertEqual(s.level, level(mocks.UIParent) + NS.Const.LAYERS.LEVEL.HUD.GRID)
end)

test("an icon's swipe, border, glow host and text overlay sit on the named rungs", function()
    local NS = fresh()
    local IconGrid = NS:GetModule("IconGrid")
    local I = NS.Const.LAYERS.LEVEL.ICON
    local btn = IconGrid.CreateIconWidget(IconGrid:GetGridFrame("target"))
    local b = level(btn)
    assertEqual(level(btn.cooldown), b + I.FILL, "the swipe has an explicit FILL level")
    assertEqual(level(btn.border), b + I.BORDER, "the border sits above the swipe, no tie")
    assertEqual(level(btn.glow), b + I.EFFECT, "the glow host")
    assertTrue(btn.textLayer ~= nil, "the icon carries a text overlay frame")
    assertEqual(level(btn.textLayer), b + I.OVERLAY, "the text overlay tops the icon")
end)

test("the countdown and the charges badge draw on the text overlay, which takes no mouse", function()
    local NS = fresh()
    local IconGrid = NS:GetModule("IconGrid")
    local btn = IconGrid.CreateIconWidget(IconGrid:GetGridFrame("target"))
    assertTrue(rawequal(btn.cooldownText.__parent, btn.textLayer), "countdown on the overlay")
    assertTrue(rawequal(btn.chargesText.__parent, btn.textLayer), "charges on the overlay")
    assertTrue(btn.textLayer.__mouse == false, "the overlay must not steal the icon's hover")
end)

test("the glow is started with the named ICON.GLOW frame level, not LibCustomGlow's +8", function()
    local NS = fresh()
    local IconGrid = NS:GetModule("IconGrid")
    local btn = IconGrid.CreateIconWidget(IconGrid:GetGridFrame("target"))
    btn.unit = "target"
    local seen
    local prev = NS.GlowLib.Start
    NS.GlowLib.Start = function(frame, _style, _knobs, _key, frameLevel)
        seen = { frame = frame, frameLevel = frameLevel }
        return true
    end
    local ok, err = pcall(btn.StartGlow, btn, "pixel", { 1, 1, 0, 1 })
    NS.GlowLib.Start = prev
    if not ok then error(err, 0) end
    assertTrue(seen ~= nil, "StartGlow must reach the glow library")
    assertTrue(rawequal(seen.frame, btn.glow))
    assertEqual(seen.frameLevel, NS.Const.LAYERS.LEVEL.ICON.GLOW)
end)

-- ── the cast bar ────────────────────────────────────────────────────────────

local function castbar(NS)
    local Castbar = NS:GetModule("Castbar")
    return Castbar:EnsureFrame(Castbar:GetInstance("target"))
end

test("the cast bar is a MEDIUM, clamped root at UIParent + HUD.CASTBAR, above its grid", function()
    local NS, mocks = fresh()
    local frame = castbar(NS)
    local s = mocks.__layers(frame)
    assertEqual(s.strata, "MEDIUM")
    assertTrue(s.clamped)
    assertEqual(s.level, level(mocks.UIParent) + NS.Const.LAYERS.LEVEL.HUD.CASTBAR)
    local IconGrid = NS:GetModule("IconGrid")
    local btn = IconGrid.CreateIconWidget(IconGrid:GetGridFrame("target"))
    assertTrue(s.level > level(btn.textLayer), "the bar draws over every grid level where they overlap")
end)

test("the cast bar's spark and text overlay sit above its borders, which sit above the fill", function()
    local NS = fresh()
    local frame = castbar(NS)
    local fill = level(frame.bar.interruptible)
    assertEqual(fill, level(frame.bar.uninterruptible), "the two state bars share one level")
    assertTrue(level(frame.borderInterruptible) > fill, "the border stays above the fill (no tint)")
    assertEqual(level(frame.borderInterruptible), level(frame.borderUninterruptible))
    assertTrue(level(frame.overlay) > level(frame.borderInterruptible),
        "the spark and the name/time text draw over the border edge")
end)

-- ── the drag handles ────────────────────────────────────────────────────────

test("both drag handles sit at UIParent + HUD.HANDLE, above the cast bar's content", function()
    local NS, mocks = fresh()
    local frame = castbar(NS)
    local want = level(mocks.UIParent) + NS.Const.LAYERS.LEVEL.HUD.HANDLE
    local gridHandle = NS:GetModule("IconGrid"):GetInstance("target").handle
    assertTrue(gridHandle ~= nil and frame.dragHandle ~= nil, "both handles are built")
    assertEqual(level(gridHandle), want, "the grid's handle")
    assertEqual(level(frame.dragHandle), want, "the cast bar's handle")
    assertTrue(want > level(frame.overlay), "a handle is never under the cast bar it touches")
    for _, h in ipairs({ gridHandle, frame.dragHandle }) do
        if h.help then assertTrue(level(h.help) > level(h), "the help mark rides over its strip") end
    end
end)

-- ── the unit label ──────────────────────────────────────────────────────────

local function label(NS, attach)
    castbar(NS)
    NS.Units.LabelStyle("target").attach = attach
    local UnitLabel = NS:GetModule("UnitLabel")
    local inst = UnitLabel:GetInstance("target")
    UnitLabel:Apply(inst)
    return inst.frame
end

test("a label attached to the cast bar draws over the cast bar, not under it", function()
    local NS = fresh()
    local f = label(NS, "castbar")
    local frame = NS:GetModule("Castbar"):GetCastbarFrame("target")
    assertTrue(level(f) > level(frame.overlay), "the label must clear the bar's text overlay")
    assertTrue(level(f) > level(frame.borderInterruptible), "and its border")
end)

test("a label attached to the grid draws over the grid's text, and re-levels after each reparent", function()
    local NS = fresh()
    local f = label(NS, "icons")
    local IconGrid = NS:GetModule("IconGrid")
    local grid = IconGrid:GetGridFrame("target")
    local btn = IconGrid.CreateIconWidget(grid)
    assertTrue(rawequal(f:GetParent(), grid), "the holder is parented to the grid")
    assertTrue(level(f) > level(btn.textLayer))
    -- SetParent drops an explicit level (the client re-derives it); a second Apply must put it back.
    NS:GetModule("UnitLabel"):Apply(NS:GetModule("UnitLabel"):GetInstance("target"))
    assertEqual(level(f), level(grid) + NS.Const.LAYERS.LEVEL.HUD.LABEL)
end)

-- ── the sim strip ───────────────────────────────────────────────────────────

test("the sim strip is MEDIUM at UIParent + HUD.MARKER, above every HUD element", function()
    local NS, mocks = fresh()
    local frame = castbar(NS)
    local prev = NS.Sim.IsActive
    NS.Sim.IsActive = function() return true end
    local ok, err = pcall(NS.SimStrip.Refresh, NS.SimStrip)
    local strip = NS.SimStrip.__frames.target
    NS.SimStrip:Hide()
    NS.Sim.IsActive = prev
    if not ok then error(err, 0) end
    assertTrue(strip ~= nil, "the strip is built")
    local s = mocks.__layers(strip)
    assertEqual(s.strata, "MEDIUM")
    assertEqual(s.level, level(mocks.UIParent) + NS.Const.LAYERS.LEVEL.HUD.MARKER)
    assertTrue(s.level > level(frame.overlay))
end)

-- ── the source reads the table ──────────────────────────────────────────────

--- Every `SetFrameStrata(` / `SetFrameLevel(` line in the addon's own source, as "path:line: text".
local function calls(method)
    local out = {}
    local p = io.popen('grep -rn "' .. method .. '(" "' .. ROOT .. '/core" "' .. ROOT .. '/modules" "'
        .. ROOT .. '/settings" --include=*.lua')
    if not p then error("layers gate: io.popen unavailable", 0) end
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

test("every SetFrameStrata in core/, modules/ and settings/ reads LAYERS.STRATA", function()
    local found = calls("SetFrameStrata")
    assertTrue(#found > 0, "the gate found no call at all, so it is not looking")
    for _, line in ipairs(found) do
        assertTrue(line:find("STRATA%.") ~= nil, "a strata literal: " .. line)
    end
end)

test("every SetFrameLevel in core/, modules/ and settings/ names a LAYERS.LEVEL member", function()
    local found = calls("SetFrameLevel")
    assertTrue(#found > 0, "the gate found no call at all, so it is not looking")
    for _, line in ipairs(found) do
        assertTrue(line:find("LEVEL%.") ~= nil, "an unnamed level: " .. line)
        assertTrue(line:find("SetFrameLevel%(%s*%d") == nil, "an absolute level: " .. line)
    end
end)
