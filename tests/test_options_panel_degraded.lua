-- tests/test_options_panel_degraded.lua
-- Split from tests/test_options_panel.lua (#31): the Options wiring when it is
-- NOT the full library -- the library-absent degraded stub (options-ui-§1, WS-02)
-- -- and the linked-Focus page, which draws the strip inert with only the link
-- note. Case names and bodies are unchanged by the move; each degraded case
-- builds its own instance with T.load.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil
local NS = T.NS
local H  = NS.Settings.Helpers

-- ── the degraded path ───────────────────────────────────────────────────────

test("with LibKa0s absent the schema loads complete BAR the composed blocks", function()
    -- THE case options-ui-§1's degradation rule exists for, and the reason this
    -- stub is load-completing rather than member-answering: page files call
    -- Helpers.LSMValues, Helpers.AnchorValues AND the five schema composers
    -- inside schema-row literals AT FILE LOAD. With any of them nil the page
    -- file raises, its rows never register, and `/kcd list`, `get`, `set`,
    -- `reset` and the profile defaults all break with it — silently.
    --
    -- WHAT CHANGED, AND WHY IT IS NOT A WEAKENING. This used to assert the two
    -- row counts were EQUAL, which they were while the host declared 100% of its
    -- rows by hand. The canonical font / border / bar / color-pair /
    -- master-controls blocks live in libs/LibKa0s/OptionsCompose.lua now
    -- (options-ui-§16, options-ui-§17), and a host copy of them in the stub is precisely
    -- the drift the composers were extracted to end (anti-pattern #73) — the
    -- same argument options-ui-§1 already makes against copying a widget maker
    -- or a layout constant into this stub. So the stub's composers are hollow,
    -- and the degraded schema is short by EXACTLY the composed rows.
    --
    -- The delta is pinned by its own fingerprint rather than by a number typed
    -- here: every composed row carries an `order`, which no hand-written row in
    -- this addon sets. So this says three things the old equality could not —
    -- how many rows the library composes, that every surviving degraded row is
    -- host-declared, and that nothing ELSE went missing.
    -- red under: deleting Helpers.LSMValues, Helpers.AnchorValues or any
    -- composer from settings/OptionsSetup.lua's stub, which takes a whole page
    -- file's rows with it rather than just that block's
    local full     = T.load(true)
    local degraded = T.load(true, false, nil, { libFiles = {} })
    assertNil(degraded.mocks.LibStub("LibKa0s-Options-1.0", true),
        "sanity: the degraded load must not have the major")

    local composed, hostDeclared = 0, 0
    for _, row in ipairs(full.NS.Settings.Schema) do
        if row.order ~= nil then composed = composed + 1 else hostDeclared = hostDeclared + 1 end
    end
    assertTrue(composed > 0, "sanity: this addon must actually compose something")

    assertEqual(#degraded.NS.Settings.Schema, hostDeclared,
        "the degraded load must register every row the HOST declares")
    for _, row in ipairs(degraded.NS.Settings.Schema) do
        assertNil(row.order,
            "a composed row survived the library's absence: " .. tostring(row.path))
    end
    assertEqual(#full.NS.Settings.Schema - #degraded.NS.Settings.Schema, composed,
        "the degraded load is short by more than the composed blocks")
end)

test("the hollow composers cost the degraded path no CLI reach beyond WS-02's route (a)",
function()
    -- THE BLAST RADIUS OF THE options-ui-§1 DEVIATION, measured rather than
    -- argued -- and it is smaller than the deviation row used to claim.
    --
    -- options-ui-§1's stated harm is that a short schema takes `list`, `get`, `set`, `reset`
    -- and the profile defaults down with it, silently. Neither half is reachable
    -- here, and this case is what says so rather than a paragraph:
    --
    --   1. THE SCHEMA CLI IS NOT RUNNING ON THIS LOAD. LibKa0s-Slash-1.0 lives
    --      in the same libs/LibKa0s/ folder as LibKa0s-Options-1.0, which
    --      options-ui-§1 requires be vendored WHOLE (anti-pattern #48), so the
    --      load that loses the composers loses the CLI in the same breath.
    --      settings/Slash.lua's stub answers `get`/`list`/`reset` with the
    --      library-absent line, and `set` too -- for a HOST-DECLARED row exactly
    --      as for a composed one -- with ONE exception, WS-02's route (a): a bool
    --      literal for a path on NS.Settings.WRITE_THROUGH (`enabled`, `locked`)
    --      is written through the Schema stub, so `/kcd enable` and `/kcd
    --      disable` keep the addon's one switch two-way. Those two paths are the
    --      only composed paths addressable on this load, and they are stored.
    --   2. The profile defaults are defaults/Profile.lua's, merged by AceDB in
    --      core/Database.lua's aceDBDefaults, and never read off the schema. A
    --      composed setting a player already made keeps being honored.
    --
    -- What the deviation does cost is #NS.Settings.Schema being short by 116 rows
    -- on a load where the only three things that read it -- the CLI, the panel and
    -- RestoreAllDefaults' sessionOnly walk -- are respectively absent, absent, and
    -- looking for `state.debugConsole`, whose console window is unavailable on
    -- this path too (core/DebugLogSetup.lua:70-72).
    --
    -- red under: settings/Slash.lua's stub CliSet widening past the writeThrough
    -- list (a host-declared row written), or narrowing below it (`enabled`
    -- refused, the switch one-way)
    local inst = T.load(true, false, nil, { libFiles = {} })
    assertNil(inst.mocks.LibStub("LibKa0s-Slash-1.0", true),
        "sanity: the degraded load must not have the slash major either")

    -- A row that SURVIVES the library's absence, so the only thing under test is
    -- whether the CLI can reach anything at all.
    local path = "units.target.enabled"
    assertTrue(inst.NS.Settings.Store.FindRow(path) ~= nil,
        "precondition: this witness must be a host-declared row, present on both paths")

    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS:OnSlashCommand("set " .. path .. " false")
    frame.AddMessage = orig

    assertEqual(inst.NS.Settings.Store.Get(path), true,
        "the degraded `/kcd set` must not write -- for a surviving row either")
    local said = false
    for _, line in ipairs(lines) do
        if tostring(line):find("unavailable", 1, true) then said = true end
    end
    assertTrue(said, "the degraded `/kcd set` must name the missing library, not go quiet")

    -- ...and the route-(a) reach: `enabled` is composed, row-less here, and written.
    frame.AddMessage = function() end
    inst.NS:OnSlashCommand("set enabled false")
    frame.AddMessage = orig
    assertEqual(inst.NS.db.profile.enabled, false,
        "the degraded `/kcd set enabled false` must write through (WS-02 route (a))")
end)

test("the degraded stub keeps the global reset real", function()
    -- options-ui-§1: a user whose panel will not open is exactly the user who
    -- needs "reset everything", and the schema loaded fine, so it still works.
    local inst = T.load(true, false, nil, { libFiles = {} })
    local H2 = inst.NS.Settings.Helpers
    local S2 = inst.NS.Settings.Store
    assertEqual(type(H2.RestoreAllDefaults), "function")
    -- A HOST-DECLARED row, deliberately: `locked` used to be the witness here and
    -- is a COMPOSED row now, so it does not exist on the degraded path at all
    -- (see the case above for why that is the measured cost rather than a bug).
    -- The per-unit enable is hand-written in settings/General.lua and is present
    -- on both paths, which is what makes it a witness for the reset itself.
    local path = "units.target.enabled"
    inst.NS.Settings.Helpers.SetAndRefresh(path, false)
    assertEqual(S2.Get(path), false, "precondition: the write landed")
    H2.RestoreAllDefaults()
    assertEqual(S2.Get(path), inst.NS.Settings.Store.FindRow(path).default,
        "the reset must still reach the profile with no panel at all")
end)

test("the degraded stub opens no panel and says so once", function()
    local inst = T.load(true, false, nil, { libFiles = {} })
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    inst.NS.OpenOptionsPanel()
    frame.AddMessage = orig
    assertTrue(#lines > 0 and table.concat(lines, "\n"):find("LibKa0s", 1, true) ~= nil,
        "the stub must name the missing library")
end)

-- The link note draws NO hover highlight, and that is a fix rather than a
-- preference: it shipped with `SetHighlight(1, 1, 1, 0.12)`, which AceGUI forwards
-- to Texture:SetTexture -- whose four-number form is the deprecated color API --
-- and the client painted a solid BRIGHT GREEN block over the whole line on
-- mouseover. The line stays clickable; it simply does not light up.
--
-- red under: re-adding SetHighlight in any form, or dropping the OnClick with it.
test("the linked-Focus note has no hover highlight but is still clickable", function()
    -- Both parked pieces of shared state go through the runner's guaranteed-run
    -- wrappers. They used to be put back by the last two statements of this body,
    -- which tests/_kit/framework.lua pcalls -- so the case could only clean up
    -- after itself on the green path, which is the path where cleaning up matters
    -- least.
    T.withFocusLink(true, function()
        T.withViewedUnit(function()
            local AceGUI = T.mocks.LibStub("AceGUI-3.0")
            local ctx = H.CreatePanel("KickCDNoteHL", "castbar", { pageKey = "castbar" })
            ctx.scroll = AceGUI:Create("ScrollFrame")
            H.SetViewedUnit("focus")
            H.RenderUnitPanel(ctx, "castbar")

            local note
            for _, child in ipairs(ctx.scroll.children) do
                if type(child.text) == "string"
                   and child.text:find("Linked to Target", 1, true) then note = child end
            end
            assertTrue(note ~= nil, "the linked page must draw the note")
            assertNil(note.__highlight,
                "the note must set no hover highlight; AceGUI paints a solid green block for one")
            assertTrue(note.callbacks and note.callbacks.OnClick ~= nil,
                "…and it must still be clickable")
        end)
    end)
end)

-- The link note GOES somewhere. Naming a destination and not being able to reach
-- it is the failure this replaced -- the note named a control and a page and left
-- the reader to find both by hand, two categories away in Blizzard's list.
--
-- Driven through the real click: the assertion is that Blizzard's category switch
-- is called with the General page's OWN category id, and that the page is put on
-- the Units tab BEFORE the switch rather than a frame later.
--
-- red under: dropping the OpenPageTab wiring, opening the parent category instead
-- of the page's own, or setting the tab after the switch.
test("the linked-Focus note opens General on its Units tab", function()
    local opened
    local inst = T.load(true, true, function(mocks)
        local Stg = mocks.Settings
        Stg.OpenToCategory = function(id) opened = id end
    end)
    local iNS = inst.NS
    local iH  = iNS.Settings.Helpers

    local general = iNS.Settings.categoryFor and iNS.Settings.categoryFor.general
    assertTrue(general ~= nil, "the General page's category must be recorded")

    local cfg = iNS.Units.Config("focus")
    if cfg then cfg.link = true end
    iH.SetViewedUnit("focus")

    local ctx = iH.__panelFor("grid")
    assertTrue(ctx ~= nil, "the Grid page must be registered")
    assertTrue(iH.SelectSection("castbar"), "the Grid page lists no Cast bar entry")
    ctx.panel:Show()
    iH.RefreshPanel(ctx, true)

    local note
    for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
        if type(child.text) == "string"
           and child.text:find("Linked to Target", 1, true) then note = child end
    end
    assertTrue(note ~= nil, "the linked page must draw the note")

    note:__fire("OnClick")

    assertEqual(opened, general:GetID(),
        "the click must open the General page's own category")
    local generalCtx = iH.__panelFor("general")
    assertEqual(generalCtx and generalCtx.activeTab, iNS.L["Units"],
        "…already on the Units tab, not on whatever it was last left on")

    if cfg then cfg.link = false end
    iH.SetViewedUnit("target")
end)

-- KC-20's characterization: the whole linked-Focus page in one case, on all three
-- unit pages. The strip is FULL (one tab per schema group, as the unlinked page
-- draws), every tab is INERT (disabled and desaturated), and the content is the
-- link note ALONE -- one LinkRow and no schema widget, because a linked Focus
-- renders with Target's tables and an editable row here would write to a table
-- nothing reads.
--
-- It pins the page's behavior independently of who draws it. KC-20 evaluated
-- moving this page onto the library's RenderTabbedSchema(opts) and declined: its
-- disabledFor draws the rows (disabled) UNDER the notice rather than replacing
-- them, and its disabledNotice is a plain TextRow, not a link (issue cited at
-- Helpers.RenderLinkedUnit in settings/Panel_Render.lua). A later adoption has to
-- keep this case green unchanged.
--
-- red under: rendering the page's styled rows, dropping the note, drawing a
-- partial strip, or dropping the disable pass.
local SCHEMA_WIDGET_TYPES = {
    CheckBox = true, Slider = true, Dropdown = true, ColorPicker = true,
    EditBox = true, MultiLineEditBox = true, Button = true,
}
test("a linked Focus page draws the full strip, inert, and only the link note", function()
    T.withFocusLink(true, function()
        T.withViewedUnit(function()
            local AceGUI = T.mocks.LibStub("AceGUI-3.0")
            for _, page in ipairs({ "icons", "castbar", "label" }) do
                local ctx = H.CreatePanel("KickCDLinkedChar" .. page, page, { pageKey = page })
                ctx.scroll = AceGUI:Create("ScrollFrame")
                H.SetViewedUnit("focus")
                H.RenderUnitPanel(ctx, page)

                local groups, seen = 0, {}
                for _, def in ipairs(H.SchemaForPanel(page, "focus")) do
                    if def.group and not seen[def.group] then
                        seen[def.group] = true
                        groups = groups + 1
                    end
                end
                local buttons = (ctx.__tabLayout or {}).buttons or {}
                assertTrue(groups > 0, page .. ": sanity, the page has schema groups")
                assertEqual(#buttons, groups, page .. ": one tab per schema group")
                for i, b in ipairs(buttons) do
                    local dim = false
                    for _, r in ipairs(b.__regions or {}) do
                        if r.__desaturated then dim = true end
                    end
                    assertTrue(b.__enabled == false or dim,
                        page .. ": tab " .. i .. " is operable and undimmed")
                end

                -- Walked recursively: paired rows sit inside flow groups, so the
                -- scroll's direct children alone would miss every widget in them.
                local links, widgets = 0, 0
                local function walk(container)
                    for _, child in ipairs(container.children or {}) do
                        if type(child.text) == "string"
                           and child.text:find("Linked to Target", 1, true) then
                            links = links + 1
                        elseif SCHEMA_WIDGET_TYPES[child.type] then
                            widgets = widgets + 1
                        end
                        walk(child)
                    end
                end
                walk(ctx.scroll)
                assertEqual(links, 1, page .. ": exactly one link note")
                assertEqual(widgets, 0, page .. ": no schema widget on a linked page")
            end
        end)
    end)
end)

-- The Focus link's two controls are ONE LINE: [Use same styling as Target]
-- [Copy styling from Target]. They were two -- a half-width tick, then a button
-- pair holding a single button -- and a button on its own line reads as belonging
-- to whatever follows it rather than to the tick above.
--
-- Driven through a real render rather than scanned, because the claim is about
-- LAYOUT: both must land in ONE Flow row, which is a fact about the widget tree
-- and not about the source.
--
-- red under: going back to SessionToggle + InlineButtonPair (two rows), or
-- dropping either cell's `make` return, which leaves RenderGrid counting the row
-- half-filled and puts the next item beside the tick.
test("the Focus link's tick and its Copy button share one row", function()
    local inst = T.load(true, true)
    local iH = inst.NS.Settings.Helpers
    local ctx = iH.__panelFor("general")
    assertTrue(ctx ~= nil, "the General page must be registered")

    ctx.activeTab = inst.NS.L["Units"]
    ctx.panel:Show()            -- the body is built lazily, on first OnShow
    iH.RefreshPanel(ctx, true)

    local tickLabel = inst.NS.L["Use same styling as Target"]
    local btnLabel  = inst.NS.L["Copy styling from Target"]
    local paired
    for _, child in ipairs((ctx.scroll and ctx.scroll.children) or {}) do
        local sawTick, sawBtn = false, false
        for _, w in ipairs(child.children or {}) do
            if w.labelText == tickLabel then sawTick = true end
            if w.text == btnLabel then sawBtn = true end
        end
        if sawTick and sawBtn then paired = child end
    end
    assertTrue(paired ~= nil,
        "the tick and the Copy button must be two children of ONE row")
end)

test("the degraded stub carries no widget maker or layout constant", function()
    -- options-ui-§1 is explicit: MUST NOT carry a copy of a widget maker, the
    -- flow engine, the header, or any of the library's layout constants.
    local fh = assert(io.open(T.root .. "/settings/OptionsSetup.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    assertNil(src:match('AceGUI:Create'), "the stub reaches for AceGUI")
    assertNil(src:match("ROW_VSPACER%s*="), "the stub copies a layout constant")
    assertNil(src:match("0%.492"), "the stub copies BUTTON_PAIR_REL")
    -- The three constants the tabbed page and the banner added (options-ui-§13 / options-ui-§14). They are
    -- exempted from the surface-parity sweep in tests/test_surface_parity.lua PRECISELY because
    -- copying them here is forbidden, so the exemption and this scan are two halves of one rule:
    -- without the scan, "exempt" would read as "optional".
    assertNil(src:match("BANNER_H%s*="), "the stub copies the banner height")
    assertNil(src:match("CHROME_GAP%s*="), "the stub copies the chrome gap")
    assertNil(src:match("TAB_H%s*="), "the stub copies the tab height")
end)
