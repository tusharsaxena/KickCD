-- tests/test_skin_settings.lua — this addon's own settings surfaces on the skin (KC-02;
-- core/SkinSetup.lua's NS.SkinPaintAce / NS.SkinPaintAceTree / NS.SkinColor / NS.SkinEscape over
-- LibKa0s-Skin-1.0, skinning-§3).
--
-- What this pins: every AceGUI widget the Spells page acquires itself (the rows and the chrome
-- block, read straight from LibStub past the Options instance's owner proxy) is painted for this
-- owner under a non-default skin with the settings panel skinned, and released stock; the Units
-- band's widgets (acquired through the proxy) are too; the Profiles page paints the tree
-- AceConfigDialog drew; nothing is painted under the defaults (Ka0s Default, the settings panel
-- left the client's); and the typed look values the pages carried are tokens now, each equal on
-- Ka0s Default to the literal it replaced: the Remove mark's close.hot red, the add box's sem.warn
-- "not tracked" tag, the rows' tooltip hints in gtip.title, and the AceGUI-missing label's accent,
-- which is on the settings panel (S.Text's `panel`), so Ignore settings panel leaves it stock.
--
-- The kit's widgets are recorders without AceGUI's regions, so "painted" is read where the library
-- keeps it: `Skin.__ace[widget].owner` (SkinAce.lua's weak state table), set while owned and
-- cleared by the restore. On its own instance, so a skin moved here never leaks into the shared
-- one later suites read.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local SHAMAN_CLASS_ID = 7
local OWNER = "KickCD"

local inst = T.load(true, true, function(mocks)
    mocks.UnitClass = function() return "Shaman", "SHAMAN", SHAMAN_CLASS_ID end
    mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 1)
    -- The harness's AceConfigDialog is a no-op lib: this Open draws two rows into the container,
    -- from raw AceGUI, as the real one acquires past the owner proxy.
    mocks.__libs["AceConfigDialog-3.0"].Open = function(_, _, container)
        local AceGUI = mocks.__libs["AceGUI-3.0"]
        container:AddChild(AceGUI:Create("Dropdown"))
        container:AddChild(AceGUI:Create("Button"))
    end
end)
local NS, mocks = inst.NS, inst.mocks
local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local Spells = NS.Settings.SpellsPanel
for _, ctx in ipairs(NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
Spells:SeedSelectionToPlayer()

-- The types SkinAce has a painter for; a SimpleGroup has none and is never owned.
local PAINTED = { Button = true, CheckBox = true, Label = true, InteractiveLabel = true,
    Icon = true, Dropdown = true, EditBox = true }

local function ownerOf(w)
    local st = Skin.__ace and Skin.__ace[w]
    return st and st.owner or nil
end

--- Back on Ka0s Default with the Scope's defaults (the settings panel left the client's).
local function reset()
    NS.WriteSkinChoice("ka0s", "ka0s", { panel = true, fonts = false }, { font = false, texture = false })
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    Skin:SetIgnore(OWNER, true, false)
    if mocks.__fireTimers then mocks.__fireTimers() end
end

--- Run `fn` on `skin` with the settings panel skinned (or left the client's when `ignorePanel`),
--- and put the defaults back whatever `fn` raised.
local function onSkin(skin, ignorePanel, fn)
    reset()
    local ok, err = pcall(function()
        Skin:SetChoice(OWNER, "ka0s", skin)
        Skin:SetIgnore(OWNER, ignorePanel == true, false)
        if mocks.__fireTimers then mocks.__fireTimers() end
        fn()
    end)
    reset()
    if not ok then error(err, 0) end
end

--- Re-render the Spells page and answer the widgets of a painted type it acquired.
local function spellsWidgets()
    local g = mocks.__aceGUI
    local mark = #g.__created
    Spells:RefreshRows()
    if mocks.__fireTimers then mocks.__fireTimers() end
    local out = {}
    for i = mark + 1, #g.__created do
        local w = g.__created[i]
        if PAINTED[w.type] then out[#out + 1] = w end
    end
    return out
end

local function count(ws, want)
    local n = 0
    for _, w in ipairs(ws) do if ownerOf(w) == want then n = n + 1 end end
    return n
end

-- ── the Spells page's own widgets ───────────────────────────────────────────────────────────────

test("skin settings: under a non-default skin the Spells rows and chrome block paint, past the proxy", function()
    -- red under: dropping NS.SkinPaintAce from Spells.Acquire (the page reads raw AceGUI, which
    -- paints nothing of its own).
    onSkin("obsidian", false, function()
        local ws, seen = spellsWidgets(), {}
        assertTrue(#ws > 0, "the Spells page acquired no widget of a painted type")
        for _, w in ipairs(ws) do
            -- The add box is the library's own (H.IdInput), painted by its owner-aware factory.
            if w.type ~= "EditBox" then
                assertEqual(ownerOf(w), OWNER, "a " .. w.type .. " on the Spells page is painted for this owner")
                seen[w.type] = true
            end
        end
        for _, t in ipairs({ "Dropdown", "Icon", "InteractiveLabel", "CheckBox", "Label" }) do
            assertTrue(seen[t], "a " .. t .. " was acquired and painted")
        end
    end)
end)

test("skin settings: a release hands the Spells widgets back stock", function()
    -- red under: a host that replaced the widget's OnRelease outright (the restore never runs).
    onSkin("obsidian", false, function()
        local ws = spellsWidgets()
        local owned = {}
        for _, w in ipairs(ws) do if ownerOf(w) == OWNER then owned[#owned + 1] = w end end
        assertTrue(#owned > 0, "something was painted before the release")
        spellsWidgets()   -- the next render releases the last one's tree first
        for _, w in ipairs(owned) do
            if not w.__released then mocks.__aceGUI:Release(w) end
            assertEqual(ownerOf(w), nil, "a released " .. w.type .. " carries no owner to its next acquirer")
        end
    end)
end)

test("skin settings: under the defaults nothing on the Spells page is painted", function()
    -- Ka0s Default with the settings panel left the client's: the page looks as it did before skins.
    onSkin("ka0s", true, function()
        local ws = spellsWidgets()
        assertTrue(#ws > 0, "the Spells page acquired widgets")
        assertEqual(count(ws, OWNER), 0, "no Spells widget is painted under the defaults")
    end)
end)

-- ── the Units band and the Profiles page ────────────────────────────────────────────────────────

test("skin settings: the Units band's picker and Copy from Target paint through the proxy", function()
    -- red under: the band reading raw AceGUI instead of the Options instance's owner proxy.
    onSkin("obsidian", false, function()
        local H = NS.Settings.Helpers
        local ctx = H.__panelFor("grid") or H.__panelFor("units")
        assertTrue(ctx ~= nil, "the Units page registered")
        local g = mocks.__aceGUI
        local mark = #g.__created
        NS.Settings.Helpers.SetViewedUnit("focus")
        H.RefreshAllPanels()
        if mocks.__fireTimers then mocks.__fireTimers() end
        local dd, btn
        for i = mark + 1, #g.__created do
            local w = g.__created[i]
            if w.type == "Dropdown" and w.labelText == NS.L["Unit"] then dd = w end
            if w.type == "Button" and w.text == NS.L["Copy from Target"] then btn = w end
        end
        NS.Settings.Helpers.SetViewedUnit("target")
        assertTrue(dd ~= nil and btn ~= nil, "the band drew its picker and its Copy from Target button")
        assertEqual(ownerOf(dd), OWNER, "the Unit picker is painted for this owner")
        assertEqual(ownerOf(btn), OWNER, "Copy from Target is painted for this owner")
    end)
end)

test("skin settings: the Profiles page paints the tree AceConfigDialog drew", function()
    -- red under: dropping NS.SkinPaintAceTree from settings/Profiles.lua's renderer.
    onSkin("obsidian", false, function()
        local ctx = NS.Settings.Helpers.__panelFor("profiles")
        assertTrue(ctx ~= nil, "the Profiles page registered")
        local g = mocks.__aceGUI
        local mark = #g.__created
        NS.Settings.Helpers.RefreshPanel(ctx, true)
        ctx.panel:Hide()
        ctx.panel:Show()
        local drawn = {}
        for i = mark + 1, #g.__created do
            local w = g.__created[i]
            if w.type == "Dropdown" or w.type == "Button" then drawn[#drawn + 1] = w end
        end
        assertTrue(#drawn >= 2, "AceConfigDialog drew its rows")
        for _, w in ipairs(drawn) do
            assertEqual(ownerOf(w), OWNER, "the Profiles " .. w.type .. " is painted for this owner")
        end
    end)
end)

-- ── the typed values are tokens ─────────────────────────────────────────────────────────────────

--- Give every Icon a texture region the row builder can dress, since the kit's recording Icon has
--- none (tests/test_settings_spells_editor.lua's iconsWithTextures), then render the page and
--- answer the first row's Remove button.
local function removeButton()
    local g = mocks.__aceGUI
    local create = g.Create
    g.Create = function(self, wtype)
        local w = create(self, wtype)
        if wtype == "Icon" then
            w.image = mocks.CreateFrame("Frame"):CreateTexture()
            function w.SetImage(widget, path) widget.image:SetTexture(path); return widget end
        end
        return w
    end
    local ok, ws = pcall(spellsWidgets)
    g.Create = create
    if not ok then error(ws, 0) end
    local mark = NS.Icon and NS.Icon("close")
    for _, w in ipairs(ws) do
        if w.type == "Icon" and w.image and w.image.GetTexture and w.image:GetTexture() == mark then
            return w
        end
    end
end

test("skin settings: the Remove mark is close.hot, { 1, 0.3, 0.3 } on Ka0s Default", function()
    -- red under: the REMOVE_TINT literal, which a skin switch never reaches.
    onSkin("ka0s", true, function()
        local btn = removeButton()
        assertTrue(btn ~= nil, "a row drew its Remove mark")
        local r, g, b = btn.image:GetVertexColor()
        assertEqual(r, 1); assertEqual(g, 0.3); assertEqual(b, 0.3)
    end)
    -- Azeroth's close-hot red (#FF6B4A) is its own; most skins inherit Ka0s Default's.
    onSkin("azeroth", false, function()
        local btn = removeButton()
        local r, g, b = NS.Skin.Color("close.hot")
        assertTrue(r ~= 1 or g ~= 0.3 or b ~= 0.3, "Azeroth's close.hot differs from Ka0s Default's")
        local vr, vg, vb = btn.image:GetVertexColor()
        assertEqual(vr, r, "the red follows the skin"); assertEqual(vg, g); assertEqual(vb, b)
    end)
end)

test("skin settings: the not-tracked tag is sem.warn, ff8000 on Ka0s Default", function()
    -- red under: the "|cffff8000" literal, which a skin switch never reaches. The Cooldown Manager
    -- tracks only 111 here (tests/test_settings_spells_editor.lua's stub), so 12345 is tagged.
    mocks.Enum = { CooldownViewerCategory = { ESSENTIAL = 1 } }
    mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function() return { 1 } end,
        GetCooldownViewerCooldownInfo = function() return { spellID = 111 } end,
    }
    if NS.SpellInput and NS.SpellInput.StandDown then NS.SpellInput.StandDown() end
    onSkin("ka0s", true, function()
        assertEqual(Spells.SuggestTag(12345), "|cffff8000" .. NS.L["not tracked"] .. "|r",
            "Ka0s Default keeps the bytes")
    end)
    -- Every shipped skin inherits Ka0s Default's sem.warn, so a skin that draws it otherwise is
    -- stood in for by the facade's Color, which the tag reads at call time.
    -- With the settings panel skinned: while the Scope ignores it the page stays the client's.
    local S = NS.Skin
    local color = S.Color
    S.Color = function(name)
        if name == "sem.warn" then return 0, 1, 0, 1 end
        return color(name)
    end
    local ok, err = pcall(onSkin, "ka0s", false, function()
        assertEqual(Spells.SuggestTag(12345), "|cff00ff00" .. NS.L["not tracked"] .. "|r",
            "the tag follows the skin's sem.warn")
    end)
    S.Color = color
    if not ok then error(err, 0) end
end)

test("skin settings: a row's own tooltip hint is titled in gtip.title", function()
    -- red under: GameTooltip:SetText(text) with no color, which no skin can reach.
    onSkin("ka0s", true, function()
        local btn = removeButton()
        local tip = mocks.GameTooltip
        local realSet, got = tip.SetText, nil
        tip.SetText = function(_, text, r, g, b) got = { text, r, g, b } end
        btn:__fire("OnEnter")
        tip.SetText = realSet
        assertTrue(got ~= nil, "the hint was drawn")
        assertEqual(got[1], NS.L["Remove"])
        assertEqual(got[2], 1); assertEqual(got[3], 0.82); assertEqual(got[4], 0)
    end)
end)

test("skin settings: the host copy carries every token the settings pages read", function()
    -- red under: a converted surface whose token the degraded facade cannot answer.
    for _, name in ipairs({ "close.hot", "sem.warn", "gtip.title", "text.accent" }) do
        assertTrue(NS.SKIN_FALLBACK[name] ~= nil, name .. " is in NS.SKIN_FALLBACK")
    end
end)

test("skin settings: with Ignore settings panel on, the page's tokens stay Ka0s Default's", function()
    -- red under: NS.SkinColor / NS.SkinEscape reading the skin straight through S.Color, which does
    -- not consult the Scope: under Azeroth with the panel ignored, the Remove mark took Azeroth's
    -- close.hot while every other widget on the page stayed stock (the KC-02 review, finding 3).
    onSkin("azeroth", true, function()
        local r = NS.Skin.Color("close.hot")
        assertTrue(r ~= nil, "Azeroth answers close.hot")
        local btn = removeButton()
        assertTrue(btn ~= nil, "a row drew its Remove mark")
        local vr, vg, vb = btn.image:GetVertexColor()
        assertEqual(vr, 1, "the Remove mark keeps Ka0s Default's red"); assertEqual(vg, 0.3); assertEqual(vb, 0.3)
        local tip = mocks.GameTooltip
        local realSet, got = tip.SetText, nil
        tip.SetText = function(_, text, tr, tg, tb) got = { text, tr, tg, tb } end
        btn:__fire("OnEnter")
        tip.SetText = realSet
        assertTrue(got ~= nil, "the hint was drawn")
        assertEqual(got[2], 1); assertEqual(got[3], 0.82); assertEqual(got[4], 0)
        -- A skin whose sem.warn differs, stood in for by the facade's Color: the tag keeps ff8000.
        local S = NS.Skin
        local color = S.Color
        S.Color = function(name)
            if name == "sem.warn" or name == "gtip.title" then return 0, 1, 0, 1 end
            return color(name)
        end
        local ok, err = pcall(function()
            assertEqual(NS.SkinEscape("sem.warn"), "|cffff8000", "the tag keeps Ka0s Default's bytes")
            local gr, gg, gb = NS.SkinColor("gtip.title")
            assertEqual(gr, 1); assertEqual(gg, 0.82); assertEqual(gb, 0)
        end)
        S.Color = color
        if not ok then error(err, 0) end
    end)
end)

test("skin settings: the AceGUI-missing label is on the settings panel, so Ignore settings panel leaves it stock", function()
    -- red under: NS.Skin.Text(fallbackLabel, "accent") without { panel = true }. S.Text paints
    -- window strings too, so it wears the skin whatever the Scope says unless the host puts the
    -- string on its settings panel (LibKa0s v1.81.0, SkinPaintExtras minor 6, decision D-02).
    onSkin("azeroth", true, function()
        local ar, ag, ab = NS.Skin.Color("text.accent")
        assertTrue(ar ~= nil and not (ar == 1 and ag == 1 and ab == 1), "sanity: Azeroth's accent is a color")
        local S, text, label, opts = NS.Skin, NS.Skin.Text, nil, nil
        S.Text = function(fs, role, o) label, opts = fs, o; return text(fs, role, o) end
        local stub = mocks.LibStub
        mocks.LibStub = setmetatable({}, { __index = stub, __call = function(_, name, silent)
            if name == "AceGUI-3.0" then return nil end
            return stub(name, silent)
        end })
        local ok, err = pcall(function() Spells:RefreshRows() end)
        mocks.LibStub = stub
        S.Text = text
        if not ok then error(err, 0) end
        assertTrue(label ~= nil, "the AceGUI-missing label was colored through S.Text")
        assertTrue(type(opts) == "table" and opts.panel == true, "it is put on the settings panel")
        local r, g, b = label:GetTextColor()
        assertTrue(not (r == ar and g == ag and b == ab), "the panel ignored: not Azeroth's accent")
        Skin:SetIgnore(OWNER, false, false)
        r, g, b = label:GetTextColor()
        assertEqual(r, ar, "the panel skinned: Azeroth's accent, live"); assertEqual(g, ag); assertEqual(b, ab)
    end)
end)

-- ── the icon rule (R5-ICON; LibKa0s docs/api/README.md "Icon art: the rule") ───────────────────

--- Texture-backed Icons whose SetImage keeps AceGUI's texcoord arm (four or eight numbers set the
--- coords, none puts them back to 0..1), then render the page and answer every Icon it acquired.
local function icons()
    local g = mocks.__aceGUI
    local create = g.Create
    g.Create = function(self, wtype)
        local w = create(self, wtype)
        if wtype == "Icon" then
            w.image = mocks.CreateFrame("Frame", nil, w.frame):CreateTexture()
            function w.SetImage(widget, path, ...)
                widget.image:SetTexture(path)
                local n = select("#", ...)
                widget.__coords = (n == 4 or n == 8) and { ... } or { 0, 1, 0, 1 }
                return widget
            end
        end
        return w
    end
    local ok, ws = pcall(spellsWidgets)
    g.Create = create
    if not ok then error(ws, 0) end
    local out = {}
    for _, w in ipairs(ws) do if w.type == "Icon" then out[#out + 1] = w end end
    return out
end

--- The row's spell icon: the one Icon drawing the spell's own art (the mock's 12345).
local function spellIcons(ws)
    local out = {}
    for _, w in ipairs(ws) do
        if w.image and w.image.GetTexture and w.image:GetTexture() == 12345 then out[#out + 1] = w end
    end
    return out
end

--- Run fn with NS.Skin.IconBorder spied: each call's target and opts, the real one still painting.
local function spyEdge(fn)
    local S = NS.Skin
    local real, calls = S.IconBorder, {}
    S.IconBorder = function(target, opts)
        calls[#calls + 1] = { target = target, opts = opts }
        return real(target, opts)
    end
    local ok, err = pcall(fn, calls)
    S.IconBorder = real
    if not ok then error(err, 0) end
end

test("icon rule: a row's spell icon is cropped 0.07 a side through SetImage, panel skinned or not", function()
    -- red under: icon:SetImage(art) with no texcoords, the Blizzard art's rough edge left showing
    for _, ignorePanel in ipairs({ true, false }) do
        onSkin("ka0s", ignorePanel, function()
            local rows = spellIcons(icons())
            assertTrue(#rows > 0, "the rows drew a spell icon")
            for _, w in ipairs(rows) do
                local c = w.__coords
                assertEqual(#c, 4, "four texcoords")
                assertEqual(c[1], 0.07); assertEqual(c[2], 0.93); assertEqual(c[3], 0.07); assertEqual(c[4], 0.93)
            end
        end)
    end
end)

test("icon rule: on a skinned panel the spell icon is edged in icon.outline on KickCD's own frame", function()
    -- red under: no S.IconBorder on the row icon (a bare art square in a window), and under an edge
    -- recorded on the pooled AceGUI image, which another addon acquires next
    onSkin("ka0s", false, function()
        spyEdge(function(calls)
            local all = icons()
            local rows = spellIcons(all)
            assertTrue(#rows > 0, "the rows drew a spell icon")
            for _, w in ipairs(rows) do
                local hit
                for _, c in ipairs(calls) do
                    if c.target == w.__kcdIconEdge then hit = c end
                    assertTrue(c.target ~= w.image, "never an edge on the pooled image")
                end
                assertTrue(hit ~= nil, "the spell icon took one edge")
                assertEqual(hit.opts.fromSkin, true, "the skin's 1 px outline")
                assertTrue(not hit.opts.hud, "a settings page draws icon.outline, never the HUD's icon.border")
                assertEqual(hit.opts.zoom, false, "the crop is SetImage's, so the edge zooms nothing")
                assertTrue(hit.target:GetParent() == w.frame, "on a frame laid over the widget's own")
                assertTrue(hit.target:IsShown(), "shown while the row is drawn")
            end
            -- Only the spell icon: the Remove mark and the known glyph are Ka0s catalog marks.
            assertEqual(#calls, #rows, "one edge per spell icon and none on a catalog mark")
            local w = rows[1]
            local edge = w.__kcdIconEdge
            mocks.__aceGUI:Release(w)
            assertTrue(not edge:IsShown(), "the release hides the edge")
            assertEqual(w.__kcdIconEdge, nil, "and takes it off the pooled widget")
        end)
    end)
end)

test("icon rule: with the settings panel left the client's the spell icon takes no edge", function()
    -- red under: an edge drawn whatever the Scope says, on a page meant to stay stock
    onSkin("obsidian", true, function()
        spyEdge(function(calls)
            local rows = spellIcons(icons())
            assertTrue(#rows > 0, "the rows drew a spell icon")
            assertEqual(#calls, 0, "no edge on a stock settings page")
            for _, w in ipairs(rows) do assertEqual(w.__kcdIconEdge, nil) end
        end)
    end)
end)

test("icon rule: the spec picker's inline spec and class icons are cropped 5..59 of 64", function()
    -- red under: |T<icon>:16:16:0:0|t, the full art with its rough edge
    local function specLabels()
        for _, w in ipairs(spellsWidgets()) do
            if w.type == "Dropdown" and w.labelText == NS.L["Class and specialization"] then return w.list end
        end
    end
    local list = specLabels()
    assertTrue(type(list) == "table" and next(list) ~= nil, "the spec picker carries entries")
    local cropped = 0
    for _, label in pairs(list) do
        if label:find("|T12345:16:16:0:0:64:64:5:59:5:59|t", 1, true) then cropped = cropped + 1 end
        assertTrue(label:find(":16:16:0:0|t", 1, true) == nil, "no uncropped icon markup: " .. label)
    end
    -- The harness knows the specs of a few classes only; a spec it has no art for draws no icon.
    assertTrue(cropped > 0, "a spec icon was drawn, cropped")
    -- The ClassIcon_ art is the fallback where the client has no class atlas.
    local atlas = mocks.CreateAtlasMarkup
    mocks.CreateAtlasMarkup = nil
    local ok, got = pcall(specLabels)
    mocks.CreateAtlasMarkup = atlas
    if not ok then error(got, 0) end
    for _, label in pairs(got) do
        assertTrue(label:find("^|TInterface\\Icons\\ClassIcon_%a+:16:16:0:0:64:64:5:59:5:59|t") ~= nil,
            "the fallback class icon is cropped: " .. label)
    end
end)
