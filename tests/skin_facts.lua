-- tests/skin_facts.lua — KickCD's facts for the kit's two skin gates (kit revision 50, skinning-§1;
-- FS-KC-GATE of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING). Not a suite: tests/run.lua calls
-- it with the instance factory and hands the answer to Kit.skinValues and Kit.skinSwitch.
--
-- THE ROWS. What no kit category takes, each with the cause that leaves it alone. A typed value with
-- a token goes through the token instead of getting a row.
--
-- THE SURFACES. One entry per thing KickCD paints itself; what the library paints for it (the debug
-- console, the Steps panel, the options chrome) is the library's own suite's. On one instance of its
-- own, enabled, so a surface with no `paint` is redrawn by the real listener, the OnSkinLooksChanged
-- of IconGrid, Castbar and UnitLabel, and a listener dropped goes red here. A `paint` is there only
-- for a redraw that has no listener: a settings row (the page re-renders), the name a live cast
-- colors, and a glow the driver holds.
--
-- THE CAST BAR'S FILL COLORS AND THE COOLDOWN TINT ARE NOT HERE. They carry a meaning (MC), so no
-- skin moves them. The bar's fill TEXTURE is here, per state. Both cast-bar borders are the icon
-- family (KC-A1), so S.BarBorder and the bar family's None and real-style arms have no reader here.

local loadInstance = ...

local inst

--- The one enabled instance, built on first use.
local function live()
    if not inst then
        inst = loadInstance(true, true, function(m)
            m.NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 13, "OUTLINE" end }
        end)
    end
    return inst
end

local function target() return live().NS.db.profile.units.target end

--- A companion writer: `path` is relative to the unit, and each is set to `on`.
local function rows(...)
    local paths = { ... }
    return function(on)
        for _, path in ipairs(paths) do
            local t, leaf = target(), nil
            for seg in path:gmatch("[^%.]+") do
                if leaf then t = t[leaf] end
                leaf = seg
            end
            t[leaf] = on
        end
    end
end

--- Target's first live icon, shown ready and glowing.
local function liveIcon()
    local NS = live().NS
    local gi = NS:GetModule("IconGrid"):GetInstance("target")
    local i = assert(gi.ordered[1], "the grid has no icon")
    target().icons.primaryGlowTrigger = "always"
    i:Apply({ ready = true }, true)
    return i
end

--- Target's cast bar with its frame built, the same instance every call.
local function castbar()
    local Castbar = live().NS:GetModule("Castbar")
    local cb = Castbar:GetInstance("target")
    Castbar:EnsureFrame(cb)
    Castbar:Reskin(cb, true)
    return Castbar, cb
end

--- A stand-in for what the glow driver draws: GlowLib.Start is handed the color and keeps no region
--- this suite could spy on, so the color lands on a texture-shaped proxy, through the host's real
--- call. `glowUndo` puts the driver back after the surface.
local glowUndo

local function glowProxy()
    local NS = live().NS
    local proxy = { SetVertexColor = function() end }
    local start = NS.GlowLib.Start
    NS.GlowLib.Start = function(_, _, opts)
        proxy:SetVertexColor(unpack(opts.color))
        return true
    end
    glowUndo = function() NS.GlowLib.Start = start end
    return proxy
end

local surfaces = {
    { name = "an icon's border",
      companion = rows("icons.borderColorFromSkin", "icons.borderTextureFromSkin"),
      build = function() return liveIcon().border end },
    { name = "an icon's countdown",
      companion = rows("icons.cooldownTextColorFromSkin", "icons.cooldownTextShadowFromSkin",
          "icons.cooldownTextFontFromSkin"),
      build = function() return liveIcon().cooldownText end },
    { name = "an icon's charges badge", build = function() return liveIcon().chargesText end },
    { name = "the primary icon's ready glow",
      companion = rows("icons.primaryGlowColorFromSkin"),
      build = function()
          local proxy = glowProxy()
          liveIcon()
          return proxy
      end },
    { name = "a secondary icon's ready glow",
      companion = rows("icons.secondaryGlowColorFromSkin"),
      build = function()
          local proxy = glowProxy()
          local NS, cfg = live().NS, target().icons
          local i = NS:GetModule("IconGrid").CreateIconWidget(live().mocks.CreateFrame("Frame"))
          i.unit, i.cfg, i._isPrimary = "target", cfg, false
          i.glow = live().mocks.CreateFrame("Frame")
          cfg.secondaryGlowTrigger = "always"
          i:UpdateGlow({ ready = true })
          proxy.icon = i
          return proxy
      end,
      paint = function(proxy) proxy.icon:UpdateGlow({ ready = true }) end },
    { name = "the cast time",
      companion = rows("castbar.textColorFromSkin", "castbar.fontFromSkin", "castbar.fontShadowFromSkin"),
      build = function()
          local _, cb = castbar()
          return cb.frame.timeText
      end },
    { name = "the spell name on a live cast",
      companion = rows("castbar.interruptible.nameTextColorFromSkin", "castbar.fontFromSkin",
          "castbar.fontShadowFromSkin"),
      build = function()
          local _, cb = castbar()
          cb.current = { notInterruptible = false }
          return cb.frame.nameText
      end,
      paint = function()
          local Castbar, cb = castbar()
          Castbar:ApplyState(cb)
      end },
    { name = "the unit label",
      companion = rows("label.style.colorFromSkin", "label.style.shadowFromSkin", "label.style.fontFromSkin"),
      build = function()
          local UL = live().NS:GetModule("UnitLabel")
          local li = UL:GetInstance("target")
          UL:Apply(li)
          return li.text
      end },
    -- The Spells page. A row draws once and the page re-renders on a skin change, so these paint.
    { name = "a Spells row's known glyph", scope = "panel",
      build = function()
          local tex = live().mocks.CreateFrame("Frame"):CreateTexture()
          live().NS.Settings.SpellsPanel.StatusGlyphMark({ image = tex }, true)
          return tex
      end },
    { name = "a Spells row's Remove mark", scope = "panel",
      build = function() return live().mocks.CreateFrame("Frame"):CreateTexture() end,
      paint = function(tex) tex:SetVertexColor(live().NS.SkinColor("close.hot")) end },
    { name = "a Spells row's own tooltip hint", scope = "panel",
      build = function() return live().mocks.CreateFrame("Frame"):CreateFontString() end,
      paint = function(fs) fs:SetTextColor(live().NS.SkinColor("gtip.title")) end },
    { name = "the add box's not-tracked tag", scope = "panel",
      build = function() return live().mocks.CreateFrame("Frame"):CreateFontString() end,
      paint = function(fs) fs:SetText(live().NS.SkinEscape("sem.warn") .. "not tracked|r") end },
    { name = "the Spells page's no-AceGUI line", scope = "panel",
      build = function()
          local fs = live().mocks.CreateFrame("Frame"):CreateFontString()
          live().NS.Skin.Text(fs, "accent", { panel = true })
          return fs
      end },
}

-- One per cast-bar state. The state's fill color is a meaning, so it has no surface.
for _, state in ipairs({ "interruptible", "uninterruptible" }) do
    local caps = state:sub(1, 1):upper() .. state:sub(2)
    local rel = "castbar." .. state .. "."
    surfaces[#surfaces + 1] = {
        name = "the " .. state .. " background",
        companion = rows(rel .. "bgColorFromSkin"),
        build = function()
            local _, cb = castbar()
            return cb.frame["bg" .. caps]
        end,
    }
    surfaces[#surfaces + 1] = {
        name = "the " .. state .. " border",
        companion = rows(rel .. "borderColorFromSkin", rel .. "borderTextureFromSkin"),
        build = function()
            local _, cb = castbar()
            return cb.frame["border" .. caps]
        end,
    }
    surfaces[#surfaces + 1] = {
        name = "the " .. state .. " fill's texture",
        companion = rows(rel .. "statusBarTextureFromSkin"),
        build = function()
            local _, cb = castbar()
            return cb.frame.bar[state]
        end,
    }
end

return {
    values = {
        rows = {
            { file = "core/Constants.lua", substring = 'NS.GRAY = "|cff9d9d9d"',
              why = "the gray of a refused-action notice in chat, which the standard fixes and no skin reaches",
              cause = "L13" },
            { file = "modules/IconGrid_Render.lua", substring = "CreateColor(1, 1, 1, 1)",
              why = "the cooldown tint curve's ready half: white leaves the spell icon its own colors, "
                  .. "and the tint is a meaning no skin moves",
              cause = "MC" },
        },
    },
    switch = {
        owner = "KickCD",
        skin = function() return live().mocks.LibStub("LibKa0s-Skin-1.0") end,
        surfaces = surfaces,
        reset = function()
            if glowUndo then glowUndo(); glowUndo = nil end
            local cb = live().NS:GetModule("Castbar"):GetInstance("target")
            cb.current = nil
        end,
    },
}
