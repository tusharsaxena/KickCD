-- tests/test_settings_spells_editor.lua — the Spells editor's add path and row builder
--
-- Characterization coverage for the three parts of settings/Spells.lua that had
-- none: the Cooldown Manager spell-set memo, the Add-spell popup's OnAccept
-- (validation, the class/spec-scoped gate, re-enable vs. append) and the AceGUI
-- row builder (column order, the tuned widths, the move/remove bounds).
--
-- Written and run green against the UNREFACTORED code, so the CCN split of those
-- functions is verifiable rather than merely plausible. Everything here drives
-- the real entry points — the registered StaticPopup handler and a real
-- RefreshRows against a shown panel — rather than reaching for file-locals.

local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

local SHAMAN_CLASS_ID = 7
local ELEMENTAL, ENHANCEMENT = 262, 263

--- A fully-enabled instance whose Settings panels exist and are shown, with the
--- editor seeded to the player's own Elemental Shaman. Every panel is shown
--- rather than only the Spells one because the panel frame the editor holds is
--- file-local — RefreshRows is gated on `panel:IsShown()`, and showing all of
--- them is the honest way to reach that gate from outside.
local function editorInstance(specIndex)
    local inst = T.load(true, true, function(mocks)
        mocks.UnitClass = function() return "Shaman", "SHAMAN", SHAMAN_CLASS_ID end
        mocks.__setPlayerSpec(SHAMAN_CLASS_ID, specIndex or 1)
    end)
    -- No explicit registration call: `enable = true` runs the AceAddon OnEnable
    -- cascade, and OnEnable is where NS.CreateOptionsPanel() lives. This line
    -- used to read `inst.NS.Settings.Register()` — the private registry's entry
    -- point, deleted with the registry itself (KCD-A-09).
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
    local p = inst.NS.Settings.SpellsPanel
    p:SeedSelectionToPlayer()
    return inst, p
end

local function activeList(inst)
    local class, spec = inst.NS.Settings.SpellsPanel:GetSelection()
    return inst.NS.Database:GetSpellList(class, spec)
end

--- Drive the registered Add-spell popup exactly as the OK button does.
local function addSpell(inst, input)
    local dlg = inst.mocks.StaticPopupDialogs["KICKCD_ADD_SPELL"]
    dlg.OnAccept({ editBox = { GetText = function() return input end } })
end

local function capture(inst, fn)
    local lines = {}
    local frame = inst.mocks.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local ok, err = pcall(fn)
    frame.AddMessage = orig
    if not ok then error(err, 0) end
    return lines
end

local function found(lines, needle)
    for _, line in ipairs(lines) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

local function hasSpell(list, id)
    local n = 0
    for _, e in ipairs(list) do if e.spellID == id then n = n + 1 end end
    return n
end

--- Rebuild the panel and hand back the row groups created by that rebuild.
local function rebuildRows(inst, p)
    local g = inst.mocks.__aceGUI
    local mark = #g.__created
    p:RefreshRows()
    local rows = {}
    for i = mark + 1, #g.__created do
        local w = g.__created[i]
        if w.type == "SimpleGroup" then rows[#rows + 1] = w end
    end
    return rows
end

-- ── the Add-spell popup ─────────────────────────────────────────────────────

test("the Add-spell popup appends a validated spell to the selected list", function()
    local inst = editorInstance()
    local list = activeList(inst)
    local before = #list
    addSpell(inst, "12345")
    assertEqual(#list, before + 1, "the spell must be appended")
    local e = list[#list]
    assertEqual(e.spellID, 12345)
    assertEqual(e.category, "other", "a new entry defaults to the `other` category")
    assertEqual(e.enabled, true)
end)

test("input the spell DB does not resolve is refused and nothing is added", function()
    local inst = editorInstance()
    local list = activeList(inst)
    local before = #list
    local lines = capture(inst, function() addSpell(inst, "") end)
    assertEqual(#list, before, "a rejected input must not touch the list")
    assertTrue(found(lines, "Invalid spell: "), "the refusal must name the input")
end)

test("re-adding a spell already in the list re-enables it in place", function()
    -- Never a duplicate: the list is the render order, and a second entry for
    -- the same spellID would give IconGrid two buttons for one cooldown.
    local inst = editorInstance()
    local list = activeList(inst)
    local id = list[1].spellID
    list[1].enabled = false
    local before = #list
    addSpell(inst, tostring(id))
    assertEqual(#list, before, "an existing spell must not be appended again")
    assertEqual(hasSpell(list, id), 1)
    assertEqual(list[1].enabled, true, "it must be re-enabled in place")
end)

test("adding to a spec the user has never customized lazy-creates its list", function()
    -- The mutator path deliberately uses EnsureSpellList: a spec with no saved
    -- table must gain a fresh one rather than failing silently on a nil read.
    local inst, p = editorInstance()
    local spells = inst.NS.db.profile.spells
    spells.SHAMAN = spells.SHAMAN or {}
    spells.SHAMAN[ENHANCEMENT] = nil
    inst.mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 2)
    p:SeedSelectionToPlayer()
    assertEqual(select(2, p:GetSelection()), ENHANCEMENT)

    addSpell(inst, "12345")
    local list = inst.NS.Database:GetSpellList("SHAMAN", ENHANCEMENT)
    assertTrue(list ~= nil, "the list must have been created")
    assertEqual(hasSpell(list, 12345), 1)
end)

-- ── the Cooldown Manager gate ───────────────────────────────────────────────

--- Stub C_CooldownViewer so it tracks exactly `ids`. The Enum stub is part of
--- it: the default mock's Enum answers every field but iterates empty, so the
--- category walk would find nothing at all.
local function stubCooldownViewer(inst, ids)
    local calls = 0
    inst.mocks.Enum = { CooldownViewerCategory = { ESSENTIAL = 1 } }
    inst.mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function()
            calls = calls + 1
            local out = {}
            for i in ipairs(ids) do out[i] = i end
            return out
        end,
        GetCooldownViewerCooldownInfo = function(cdID)
            return { spellID = ids[cdID] }
        end,
    }
    return function() return calls end
end

test("a spell the Cooldown Manager does not track for the player's own spec is refused", function()
    local inst = editorInstance()
    stubCooldownViewer(inst, { 111 })
    local list = activeList(inst)
    local before = #list
    local lines = capture(inst, function() addSpell(inst, "12345") end)
    assertEqual(#list, before, "the gate must refuse the add")
    assertTrue(found(lines,
        "Spell Spell12345 (#12345) is not tracked by the Blizzard Cooldown Manager for this specialization."),
        "the refusal message is a user-facing contract")
end)

test("a spell the Cooldown Manager does track passes the gate", function()
    local inst = editorInstance()
    stubCooldownViewer(inst, { 111 })
    local list = activeList(inst)
    local before = #list
    addSpell(inst, "111")
    assertEqual(#list, before + 1, "a tracked spell must be added")
    assertEqual(list[#list].spellID, 111)
end)

test("the gate is DROPPED when the editor is not on the player's live spec", function()
    -- C_CooldownViewer has no class/spec parameter — it answers for the
    -- logged-in player's ACTIVE spec. Applying it to another spec's list would
    -- stop a Mage from adding a single Hunter spell.
    local inst, p = editorInstance()
    stubCooldownViewer(inst, { 111 })
    -- The player respecs; the editor stays on the spec the user is looking at.
    inst.mocks.__setPlayerSpec(SHAMAN_CLASS_ID, 2)
    assertEqual(select(2, p:GetSelection()), ELEMENTAL,
        "sanity: the selection must still differ from the player's live spec")

    local list = activeList(inst)
    local before = #list
    addSpell(inst, "12345")
    assertEqual(#list, before + 1, "the cross-spec add must fall through leniently")
end)

test("an absent C_CooldownViewer falls through leniently rather than refusing", function()
    local inst = editorInstance()
    assertNil(inst.mocks.C_CooldownViewer, "sanity: the default client has no viewer API")
    local list = activeList(inst)
    local before = #list
    addSpell(inst, "12345")
    assertEqual(#list, before + 1)
end)

test("an API that answers nothing is remembered as empty and never re-walked", function()
    -- The three-state memo: nil = not computed, the sentinel = computed and
    -- empty, a table = a real set. Collapsing empty to nil re-walks every
    -- category on every call.
    local inst = editorInstance()
    local callCount = stubCooldownViewer(inst, {})
    local list = activeList(inst)
    local before = #list
    addSpell(inst, "12345")
    addSpell(inst, "12346")
    assertEqual(#list, before + 2, "an empty result must not gate anything")
    assertEqual(callCount(), 1, "the walk must happen once, not once per add")
end)

test("a category the client throws on is survived rather than aborting the walk", function()
    -- Both pcalls are load-bearing: C_CooldownViewer throws on some category
    -- values in some client builds.
    local inst = editorInstance()
    inst.mocks.Enum = { CooldownViewerCategory = { BAD = 1, GOOD = 2 } }
    inst.mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(category)
            if category == 1 then error("no such category") end
            return { 7 }
        end,
        GetCooldownViewerCooldownInfo = function() return { spellID = 111 } end,
    }
    local list = activeList(inst)
    local before = #list
    addSpell(inst, "111")
    assertEqual(#list, before + 1, "the surviving category must still have been read")
end)

-- ── the row builder ─────────────────────────────────────────────────────────

test("a spell row carries its nine widgets in the visual column order", function()
    -- AddChild order IS the column order, spacer included, and the widths are
    -- tuned: 238 for the name label, 22 so the status glyph's box hugs its
    -- 20 px image, 14 for the gap before the category dropdown.
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    assertTrue(#rows > 0, "the fixture must render at least one row")
    local kids = rows[1].children
    assertEqual(#kids, 9, "nine widgets per row")
    local want = {
        { "Icon", 28 }, { "Label", 238 }, { "CheckBox", 40 }, { "Icon", 22 },
        { "Label", 14 }, { "Dropdown", 120 }, { "Icon", 30 }, { "Icon", 30 },
        { "Icon", 30 },
    }
    for i, spec in ipairs(want) do
        assertEqual(kids[i].type, spec[1], "column " .. i .. " type")
        assertEqual(kids[i].width, spec[2], "column " .. i .. " width")
    end
    assertEqual(kids[5].text, "", "the spacer is an empty-text label")
end)

test("the row's status glyph reflects Compat.IsSpellAvailable and does not gate the row", function()
    local inst, p = editorInstance()
    inst.NS.Compat.IsSpellAvailable = function() return false end
    local rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[4].image[1], [[Interface\RaidFrame\ReadyCheck-NotReady]])
    assertTrue(rows[1].children[3].value ~= nil, "the checkbox is still live")

    inst.NS.Compat.IsSpellAvailable = function() return true end
    rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[4].image[1], [[Interface\RaidFrame\ReadyCheck-Ready]])
end)

test("the row checkbox writes the entry's enabled flag as a real boolean", function()
    -- `value and true or false`: AceGUI hands back nil for an unchecked box on
    -- some widget versions, and a nil `enabled` reads as ENABLED everywhere
    -- else in the addon (`entry.enabled ~= false`).
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    rows[1].children[3]:__fire("OnValueChanged", nil)
    assertEqual(list[1].enabled, false, "an unchecked box must store a real false")
    rebuildRows(inst, p)[1].children[3]:__fire("OnValueChanged", true)
    assertEqual(list[1].enabled, true)
end)

test("a disabled row renders its spell icon and checkbox from the stored flag", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    list[1].enabled = false
    local rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[3].value, false, "the checkbox reflects the entry")
    assertEqual(rows[2].children[3].value, true)
end)

test("the move buttons are disabled at the list edges, not merely inert", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    assertTrue(#list >= 2, "the fixture needs at least two rows")
    local rows = rebuildRows(inst, p)
    assertNil(rows[1].children[7].callbacks.OnClick,
        "the first row's Move up must carry no click action at all")
    assertNil(rows[#rows].children[8].callbacks.OnClick,
        "the last row's Move down must carry no click action at all")
    assertTrue(rows[2].children[7].callbacks.OnClick ~= nil,
        "an interior row's Move up must be live")
end)

test("Move up swaps the entry with the one above it", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local first, second = list[1].spellID, list[2].spellID
    local rows = rebuildRows(inst, p)
    rows[2].children[7]:__fire("OnClick")
    assertEqual(list[1].spellID, second)
    assertEqual(list[2].spellID, first)
end)

test("Move down swaps the entry with the one below it", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local first, second = list[1].spellID, list[2].spellID
    local rows = rebuildRows(inst, p)
    rows[1].children[8]:__fire("OnClick")
    assertEqual(list[1].spellID, second)
    assertEqual(list[2].spellID, first)
end)

test("Remove deletes exactly the row's entry", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local before, victim = #list, list[2].spellID
    local rows = rebuildRows(inst, p)
    rows[2].children[9]:__fire("OnClick")
    assertEqual(#list, before - 1)
    assertEqual(hasSpell(list, victim), 0)
end)

test("the category dropdown writes the entry's category", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    rows[1].children[6]:__fire("OnValueChanged", "silence")
    assertEqual(list[1].category, "silence")
end)

-- ── the panel rebuild ───────────────────────────────────────────────────────

test("RefreshRows builds the header, the scroll container and one row per entry", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local g = inst.mocks.__aceGUI
    local mark = #g.__created
    p:RefreshRows()
    local types = {}
    for i = mark + 1, #g.__created do types[#types + 1] = g.__created[i].type end
    assertEqual(types[1], "Dropdown", "the spec dropdown leads the header")
    assertEqual(types[2], "Button", "then the Add spell button")
    assertEqual(types[3], "ScrollFrame", "then the scroll container")
    local rows = 0
    for _, ty in ipairs(types) do if ty == "SimpleGroup" then rows = rows + 1 end end
    assertEqual(rows, #list, "one row group per list entry")
end)

test("an empty list renders the guidance label instead of rows", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    for i = #list, 1, -1 do table.remove(list, i) end
    local rows = rebuildRows(inst, p)
    assertEqual(#rows, 0, "no row groups for an empty list")
    local g = inst.mocks.__aceGUI
    local last = g.__created[#g.__created]
    assertEqual(last.type, "Label")
    assertTrue(last.text:find("No spells tracked.", 1, true) ~= nil,
        "the empty list must say what to do; got: " .. tostring(last.text))
    assertEqual(last.fullWidth, true)
end)

test("RefreshRows refuses to run against a hidden panel", function()
    local inst, p = editorInstance()
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Hide() end
    local g = inst.mocks.__aceGUI
    local mark = #g.__created
    p:RefreshRows()
    assertEqual(#g.__created, mark, "a hidden panel must build no widgets")
end)

test("a rebuild releases the previous widget tree before building a new one", function()
    -- releaseAceGUITree must stay ahead of any new widget creation or the
    -- AceGUI pool leaks a full tree per refresh.
    local inst, p = editorInstance()
    p:RefreshRows()
    local g = inst.mocks.__aceGUI
    local container
    for i = #g.__created, 1, -1 do
        if g.__created[i].type == "ScrollFrame" then container = g.__created[i] break end
    end
    assertTrue(container ~= nil)
    assertTrue(#container.children > 0, "the container holds the rendered rows")
    p:RefreshRows()
    assertEqual(#container.children, 0, "the previous container must have been released")
end)

test("the selection cascade falls back to the first sorted class the defaults know", function()
    -- The player's own class wins when the defaults carry it; otherwise the
    -- first sorted class, so the panel always has something to render rather
    -- than coming up blank.
    local inst, p = editorInstance()
    inst.mocks.UnitClass = function() return "Tinker", "NOTACLASS", 99 end
    p:SeedSelectionToPlayer()
    assertNil((p:GetSelection()), "sanity: an unrenderable class seeds no selection")

    p:RefreshRows()
    local class, spec = p:GetSelection()
    local sorted = p.SortedKeys(inst.NS.DefaultSpells)
    assertEqual(class, sorted[1], "the cascade lands on the first sorted class")
    assertEqual(spec, p.SpecOrder(class)[1], "and on that class's first spec")
end)

test("a stale move click after a rebuild cannot run off the end of the list", function()
    -- The move/remove callbacks close over `index`, which is only valid until
    -- the next rebuild. The bounds checks inside them are the guard against a
    -- click landing on a row that no longer exists.
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    local staleDown = rows[#rows - 1].children[8]
    -- Shrink the list under the captured index, then fire the stale handler.
    for i = #list, 2, -1 do table.remove(list, i) end
    staleDown:__fire("OnClick")
    assertEqual(#list, 1, "the stale click must be a no-op, not a swap with nil")
end)
