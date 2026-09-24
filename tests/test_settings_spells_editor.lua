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

--- Add through the chrome band's add box, exactly as pressing Enter in it does.
---
--- WAS THE STATIC POPUP's OnAccept until the box replaced it. Every case below calls this and none
--- of them changed: what they assert about an add -- the validation, the Cooldown Manager refusal,
--- the duplicate handling -- is the same question through a different door. What the POPUP owned
--- and the box does not is the parsing: the library resolves a name, a link or an id to a number
--- before `onAdd` is reached, so the cases that typed nonsense now exercise the library's refusal
--- rather than this addon's.
local function addSpell(inst, input)
    local eb
    for _, w in ipairs(inst.mocks.__aceGUI.__created) do
        if w.type == "EditBox" and w.labelText == inst.NS.L["Add a spell"] then eb = w end
    end
    assert(eb, "the add box was not drawn")
    eb:__fire("OnEnterPressed", tostring(input))
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

--- Rebuild the panel and hand back the ROW groups created by that rebuild.
---
--- NOT EVERY SimpleGroup A REBUILD MAKES IS A ROW, since the add control moved into the chrome
--- band: `RefreshRows` builds the band first (the case below pins that order), and the band holds
--- a SimpleGroup of its own to give O.IdInput an AceGUI container to AddChild into. Taking every
--- group would count it as a row, which shifts every index by one and makes an empty list look
--- like a list of one.
---
--- Told apart by what a ROW carries: a row's first child is the reorder handle or the spell icon,
--- never an EditBox. The add host's is the library's box.
--- TWO groups, not one: this page parents a SimpleGroup into the band to give O.IdInput an AceGUI
--- container, and O.IdInput then builds its OWN row group inside it (`startRow`, then
--- `parent:AddChild(group)`). So the EditBox sits one level below the host, and a check that only
--- looked at direct children would catch the inner group and count the outer one as a row.
local function holdsEditBox(w, depth)
    for _, kid in ipairs(w.children or {}) do
        if kid.type == "EditBox" then return true end
        if depth > 0 and kid.children and holdsEditBox(kid, depth - 1) then return true end
    end
    return false
end

local function isAddHost(w)
    return holdsEditBox(w, 1)
end

local function rebuildRows(inst, p)
    local g = inst.mocks.__aceGUI
    local mark = #g.__created
    p:RefreshRows()
    local rows = {}
    for i = mark + 1, #g.__created do
        local w = g.__created[i]
        if w.type == "SimpleGroup" and not isAddHost(w) then rows[#rows + 1] = w end
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
    -- THE REFUSAL MOVED, and that is the point of the control. It used to be a chat line printed
    -- behind a modal the player had to dismiss first; it is now the library's status line under
    -- the box, where the text that caused it is still on screen. So this asserts the list is
    -- untouched -- which is the behavior -- and that nothing reached chat.
    local lines = capture(inst, function() addSpell(inst, "") end)
    assertEqual(#list, before, "a rejected input must not touch the list")
    assertEqual(#lines, 0, "and the refusal is on the box's status line, not in chat")
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

-- The suggestion row's own warning (LibKa0s v1.51.0's `kind.suggestTag`). The refusal below fires
-- at the ADD, in chat -- correct, but after the player has chosen. This marks the row while they
-- are still choosing, and it is effective on THIS page precisely because the spells in question
-- are in the spellbook, so they reach the suggestion index at all.
--
-- It lives with the gate's other cases because it needs the same stub: without C_CooldownViewer
-- the tag answers nil for everything, and a case that did not stub it would pass for the wrong
-- reason on every assertion.
-- Both alignments the owner reported from the live panel (2026-09-22). Neither is visible to the
-- suite as a PIXEL -- the fake draws nothing -- so each is pinned at the number that decides it.
test("the band stacks the picker over the add box, each on its own row", function()
    local inst, p = editorInstance()
    p:RefreshRows()
    -- EVERY host across every render, not the first one found: a case runs more than one render
    -- and a `host or w` took the earliest, which belongs to a render this case is not about.
    local anchors = {}
    for _, w in ipairs(inst.mocks.__aceGUI.__created) do
        if w.type == "SimpleGroup" and w.__stackedUnder then
            anchors[#anchors + 1] = tostring(w.__stackedUnder)
        end
    end
    -- red under the marker being dropped, which is how a rewrite would silently stop saying where
    -- the box hangs at all.
    assertTrue(#anchors > 0, "the add control records which edge it hangs off")
    -- SIDE BY SIDE COULD NOT BE ALIGNED, which is why they are stacked: each block is a caption
    -- over a control and the two controls are different heights, so aligning the captions left the
    -- controls off and aligning the controls left the captions off. Stacked, neither has anything
    -- to line up with. red under TOPRIGHT, which is both shapes that failed.
    for _, rel in ipairs(anchors) do
        assertTrue(rel:find("BOTTOM", 1, true) ~= nil,
            "the add box hangs BELOW the picker, not beside it: " .. rel)
    end
end)

--- The whole of `libs/AceGUI-3.0/<rel>`, so a case can assert against the vendored source rather
--- than against a number copied out of it once.
local function aceSource(rel)
    local root = _G.KICKCD_TEST_ROOT or "."
    local f = assert(io.open(root .. "/libs/AceGUI-3.0/" .. rel, "r"),
        "vendored AceGUI is missing: " .. rel)
    local src = f:read("*a")
    f:close()
    return src
end

test("the chrome band reserves room for the status line it writes refusals on", function()
    -- THE BUG THIS PINS. The band was a hand-picked 96 while its content adds up to 105, and the
    -- nine missing pixels were invisible in every screenshot because an EMPTY AceGUI Label is
    -- floored at 1px. The frame that mattered was the one after a bad name: the library writes
    -- "no spell named ..." on that Label, it grows to a line of GameFontHighlightSmall, and
    -- SimpleGroup does not clip -- so the refusal drew over the library's divider and into the tab
    -- strip. A height nobody can check is a height that goes wrong quietly.
    --
    -- red under HEADER_BLOCK_H going back to any hand-picked number, and red under a vendored
    -- AceGUI bump that changes a widget height the sum is built from.
    local inst, p = editorInstance()
    local H = inst.NS.Settings.Helpers
    local asked
    local real = H.PageHeader
    H.PageHeader = function(ctx, spec)
        asked = spec and spec.height
        return real(ctx, spec)
    end
    p:RefreshRows()
    H.PageHeader = real
    assertTrue(type(asked) == "number", "the page reserved a chrome band")

    -- Each term read out of the vendored widget that charges it, so this dies on a bump rather
    -- than drifting quietly past one.
    local dropdown = aceSource("widgets/AceGUIWidget-DropDown.lua")
    local editbox  = aceSource("widgets/AceGUIWidget-EditBox.lua")
    local core     = aceSource("AceGUI-3.0.lua")
    assertTrue(dropdown:find("self:SetHeight(40)", 1, true) ~= nil,
        "AceGUI's labeled Dropdown is still 40 tall")
    assertTrue(editbox:find("self:SetHeight(44)", 1, true) ~= nil,
        "AceGUI's labeled EditBox is still 44 tall")
    assertTrue(core:find("height = height + rowheight + 3", 1, true) ~= nil,
        "AceGUI's Flow still puts 3 between one row and the next")

    -- 40 picker + 6 inter-row gap + 44 add row + 3 Flow gap + 12 status line.
    assertEqual(asked, 105, "the band is the sum of what it holds, with the status line paid for")

    -- The part that is actually load-bearing, stated without the arithmetic: whatever the terms
    -- become, a written status line must still fit under the add row. 40 + 6 + 44 + 3 = 93.
    assertTrue(asked - 93 >= 12,
        "a one-line refusal fits under the add box instead of over the divider")
end)

test("an Icon in a row lines its ART up with the checkbox, not its frame", function()
    local inst, p = editorInstance()
    p:RefreshRows()
    local icons = {}
    for _, w in ipairs(inst.mocks.__aceGUI.__created) do
        if w.type == "Icon" and w.alignoffset then icons[#icons + 1] = w end
    end
    assertTrue(#icons > 0, "the rows drew icons")
    -- AceGUI hangs an Icon's texture 5px below its frame top and sizes it smaller than the frame,
    -- so half the frame is NOT the middle of the art: a 20px image in a 24px frame has its middle
    -- at 15 where the frame's is 12. Flow aligns on `alignoffset`, so naming 5 + art/2 puts the ART
    -- on the row's line. red under no alignoffset at all, which is what made the rows look crooked.
    for _, ic in ipairs(icons) do
        local art = ic.imageHeight or ic.__imageHeight
        if art then
            assertEqual(ic.alignoffset, 5 + art / 2, "the art's middle is the alignment point")
        end
    end
end)

test("a spell the Cooldown Manager does not track is tagged before the click", function()
    local inst = editorInstance()
    stubCooldownViewer(inst, { 111 })
    -- AND IT IS WIRED, not merely published. Calling the function alone passed even with the
    -- `suggestTag` line deleted from the H.IdInput spec, which is a test proving nothing -- so the
    -- spec the control was actually handed is captured and asserted first.
    local H = inst.NS.Settings.Helpers
    local realIdInput, handed = H.IdInput, nil
    H.IdInput = function(ctx, parent, spec)
        handed = spec
        return realIdInput(ctx, parent, spec)
    end
    local ok, err = pcall(function() inst.NS.Settings.SpellsPanel:RefreshRows() end)
    H.IdInput = realIdInput
    if not ok then error(err, 0) end
    local tag = inst.NS.Settings.SpellsPanel.SuggestTag
    assertTrue(type(tag) == "function", "the page publishes its tag")
    assertEqual(handed and handed.suggestTag, tag, "and hands it to the add control")
    -- red under a tag that answers for everything: a correct list would wear a warning per row.
    assertNil(tag(111), "a spell the Cooldown Manager tracks wears nothing")
    local untracked = tag(12345)
    assertTrue(untracked ~= nil and untracked:find("not tracked", 1, true) ~= nil,
        "one it does not track is marked: " .. tostring(untracked))
end)

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

test("a spell row carries its eight widgets in the visual column order", function()
    -- AddChild order IS the column order, and the widths are tuned: 30 for the
    -- drag handle's gutter (read off LibKa0s-Widgets' ROW_BOX.HANDLE_W, never
    -- restated), 238 for the name label, 22 so the status glyph's box hugs its
    -- 20 px image, 14 for the gap before the category dropdown.
    --
    -- NINE BECAME EIGHT, and it is one deletion plus one addition: the two
    -- move-arrow Icons went (options-ui-§18, anti-pattern #75) and the handle
    -- gutter arrived at the FAR LEFT, which is where the library parents its
    -- handle and therefore the one place the row must leave clear.
    -- red under: dropping the leading gutter spacer, which puts the spell icon
    -- underneath the drag handle
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    assertTrue(#rows > 0, "the fixture must render at least one row")
    local kids = rows[1].children
    assertEqual(#kids, 8, "eight widgets per row")
    local want = {
        { "Label", 30 }, { "Icon", 28 }, { "InteractiveLabel", 238 }, { "CheckBox", 40 },
        { "Icon", 22 }, { "Label", 14 }, { "Dropdown", 120 }, { "Icon", 30 },
    }
    for i, spec in ipairs(want) do
        assertEqual(kids[i].type, spec[1], "column " .. i .. " type")
        assertEqual(kids[i].width, spec[2], "column " .. i .. " width")
    end
    assertEqual(kids[1].text, "", "the handle gutter is an empty-text label")
    assertEqual(kids[6].text, "", "the spacer is an empty-text label")
end)

test("every row in the list is the same height, which the drop arithmetic needs",
function()
    -- options-ui-§18: the drop position is arithmetic on the row STRIDE, never a
    -- hit test, so a list of unequal rows drops in the wrong place. Nothing in
    -- the row builder varies the height today; this is what says so.
    -- red under: sizing a row from its content instead of ROW_HEIGHT
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    assertTrue(#rows >= 2, "the fixture needs at least two rows")
    for i, row in ipairs(rows) do
        assertEqual(row.height, rows[1].height, "row " .. i .. " is a different height")
    end
end)

test("the row's status glyph reflects Compat.IsSpellAvailable and does not gate the row", function()
    local inst, p = editorInstance()
    inst.NS.Compat.IsSpellAvailable = function() return false end
    local rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[5].image[1], [[Interface\RaidFrame\ReadyCheck-NotReady]])
    assertTrue(rows[1].children[4].value ~= nil, "the checkbox is still live")

    inst.NS.Compat.IsSpellAvailable = function() return true end
    rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[5].image[1], [[Interface\RaidFrame\ReadyCheck-Ready]])
end)

test("the row checkbox writes the entry's enabled flag as a real boolean", function()
    -- `value and true or false`: AceGUI hands back nil for an unchecked box on
    -- some widget versions, and a nil `enabled` reads as ENABLED everywhere
    -- else in the addon (`entry.enabled ~= false`).
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    rows[1].children[4]:__fire("OnValueChanged", nil)
    assertEqual(list[1].enabled, false, "an unchecked box must store a real false")
    rebuildRows(inst, p)[1].children[4]:__fire("OnValueChanged", true)
    assertEqual(list[1].enabled, true)
end)

test("a disabled row renders its spell icon and checkbox from the stored flag", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    list[1].enabled = false
    local rows = rebuildRows(inst, p)
    assertEqual(rows[1].children[4].value, false, "the checkbox reflects the entry")
    assertEqual(rows[2].children[4].value, true)
end)

-- ── the drag reorder (options-ui-§18) ───────────────────────────────────────
--
-- The gesture itself is the library's and is tested there. What a finished drag
-- WRITES is Database:MoveSpell's splice, pinned with its range guards and the
-- page's real onMove in tests/test_spell_registry.lua.

test("no row carries a move button any more", function()
    -- red under: re-adding the arrow pair as a degraded-path fallback, which
    -- options-ui-§18 forbids outright -- a host-drawn alternative is the drift
    -- the shared widget exists to end.
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    for _, row in ipairs(rows) do
        for i, kid in ipairs(row.children) do
            local img = kid.image and kid.image[1]
            if type(img) == "string" then
                assertTrue(not img:find("ChatIcon-Scroll", 1, true),
                    "row widget #" .. i .. " is still a scroll arrow: " .. img)
            end
        end
    end
end)

test("Remove deletes exactly the row's entry", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local before, victim = #list, list[2].spellID
    local rows = rebuildRows(inst, p)
    rows[2].children[8]:__fire("OnClick")
    assertEqual(#list, before - 1)
    assertEqual(hasSpell(list, victim), 0)
end)

test("the category dropdown writes the entry's category", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    rows[1].children[7]:__fire("OnValueChanged", "silence")
    assertEqual(list[1].category, "silence")
end)

-- ── pooled frames, tooltips, the remove mark (KICKCD-R-02, KICKCD-A-14) ─────
--
-- AceGUI hands its frames out of one process-global pool, and a hook laid on
-- one cannot be taken off: it follows the frame into the next widget that
-- acquires it, in whichever addon that is. So the row reaches the pointer
-- through widget callbacks, which Release clears, and never through a hook.

test("no Spells row widget hooks its pooled frame", function()
    -- red under: the old name Label's label.frame:HookScript pair, or the
    -- category dropdown's dd.frame:HookScript pair
    -- The ROWS, and every widget in them. The chrome band above them is the
    -- library's (O.IdInput) and is not this page's to answer for.
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    assertTrue(#rows > 0, "the fixture must render at least one row")
    local function noHooks(w, where)
        local hooks = w.frame and rawget(w.frame, "__hooks")
        assertNil(hooks and hooks[1],
            where .. " (" .. tostring(w.type) .. ") hooked its pooled frame")
        for c, kid in ipairs(w.children or {}) do noHooks(kid, where .. "." .. c) end
    end
    for i, row in ipairs(rows) do noHooks(row, "row " .. i) end
    assertEqual(rows[1].children[3].type, "InteractiveLabel",
        "the name is an InteractiveLabel, which carries its own OnEnter/OnLeave callbacks")
    assertEqual(#rows[1].children[3].__highlight, 0,
        "SetHighlight(nil): no highlight texture on the name")
end)

test("hovering the spell name shows the spell tooltip", function()
    local inst, p = editorInstance()
    local list = activeList(inst)
    local tip, shown = inst.mocks.GameTooltip, nil
    local saved = rawget(tip, "SetSpellByID")
    rawset(tip, "SetSpellByID", function(_, id) shown = id end)
    local ok, err = pcall(function()
        rebuildRows(inst, p)[1].children[3]:__fire("OnEnter")
    end)
    rawset(tip, "SetSpellByID", saved)
    assertTrue(ok, tostring(err))
    assertEqual(shown, list[1].spellID)
end)

test("hovering the category dropdown shows the category tooltip", function()
    -- red under: the dd.frame:HookScript pair. AceGUI's Dropdown frame is never
    -- mouse-enabled (the button and its cover take the pointer), so that hook
    -- never fired in the client and the tooltip was dead.
    local inst, p = editorInstance()
    local L = inst.NS.L
    local tip, title, lines = inst.mocks.GameTooltip, nil, {}
    local savedText, savedLine = rawget(tip, "SetText"), rawget(tip, "AddLine")
    rawset(tip, "SetText", function(_, text) title = text end)
    rawset(tip, "AddLine", function(_, text) lines[#lines + 1] = text end)
    local ok, err = pcall(function()
        rebuildRows(inst, p)[1].children[7]:__fire("OnEnter")
    end)
    rawset(tip, "SetText", savedText)
    rawset(tip, "AddLine", savedLine)
    assertTrue(ok, tostring(err))
    assertEqual(title, L["Category"])
    assertEqual(lines[1], L["Category for future filtering. Currently informational only."])
end)

--- Give every Icon a texture region the row builder can dress, since the kit's
--- recording Icon has none: SetImage then writes the path onto that texture
--- instead of replacing it, so a case can read the atlas, the path and the tint
--- off one object.
local function iconsWithTextures(inst)
    local g = inst.mocks.__aceGUI
    local create = g.Create
    g.Create = function(self, wtype)
        local w = create(self, wtype)
        if wtype == "Icon" then
            w.image = inst.mocks.CreateFrame("Frame"):CreateTexture()
            function w.SetImage(widget, path) widget.image:SetTexture(path); return widget end
        end
        return w
    end
    return function() g.Create = create end
end

test("the remove button draws the catalog mark, and the atlas only without LibKa0s", function()
    -- library-stack-§8 / AP #63: a Blizzard atlas only where the catalog has no
    -- mark. Catalog marks are white in the alpha, so the button tints it red.
    -- red under: atlas = "transmog-icon-remove" unconditionally
    local inst, p = editorInstance()
    local restore = iconsWithTextures(inst)
    local ok, err = pcall(function()
        local mark = inst.NS.Icon("close")
        assertTrue(mark ~= nil, "the live load resolves the catalog's close mark")
        local img = rebuildRows(inst, p)[1].children[8].image
        assertEqual(img:GetTexture(), mark, "the remove button draws the catalog mark")
        assertNil(img:GetAtlas(), "and no Blizzard atlas")
        local r, gr, b = img:GetVertexColor()
        assertTrue(r > gr and r > b, "the white mark is tinted red")

        -- NS.Icon answering nil is the degraded install's answer (below).
        local liveIcon = inst.NS.Icon
        inst.NS.Icon = function() return nil end
        img = rebuildRows(inst, p)[1].children[8].image
        inst.NS.Icon = liveIcon
        assertEqual(img:GetAtlas(), "transmog-icon-remove", "the fallback is the Blizzard atlas")
        assertNil(img:GetTexture(), "with no catalog path")
        assertEqual(select(1, img:GetVertexColor()), 1, "and no tint over the red atlas")
    end)
    restore()
    assertTrue(ok, tostring(err))

    local degraded = T.load(false, false, nil, { libFiles = {} })
    assertNil(degraded.NS.Icon("close"), "without LibKa0s NS.Icon answers nil")
end)

test("a reorder drag never writes a row frame's OnUpdate", function()
    -- LK-21 consumer pin (LibKa0s-Widgets minor 10): the drag polls on the
    -- library's own ghost frame. Before it, `row.frame:SetScript("OnUpdate")`
    -- on the HOST's row frame -- a pooled AceGUI frame -- wiped whatever was
    -- there. Characterization: green on v1.56.0.
    local inst, p = editorInstance()
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0", true)
    local realReorder, ctl = W.ReorderList, nil
    W.ReorderList = function(opts) ctl = realReorder(opts); return ctl end
    local rows = rebuildRows(inst, p)
    W.ReorderList = realReorder
    assertTrue(ctl ~= nil and ctl.rows[1] and ctl.rows[1].handle ~= nil,
        "the page built a controller and a handle on row 1")
    inst.mocks.GetCursorPosition = function() return 0, 300 end
    local handle = ctl.rows[1].handle
    handle:GetScript("OnMouseDown")(handle)
    assertTrue(ctl.dragging ~= nil, "the drag started")
    for i, row in ipairs(rows) do
        assertNil(row.frame:GetScript("OnUpdate"), "row " .. i .. "'s frame carries an OnUpdate")
    end
    ctl:Cancel()
end)

-- ── the panel rebuild ───────────────────────────────────────────────────────

test("RefreshRows builds the chrome block, then the rows, in that order", function()
    -- ORDER IS THE ASSERTION. The spec picker and Add spell go into the page's
    -- chrome block ABOVE the strip (options-ui-§14) and the block has to be
    -- drawn BEFORE the strip, because the strip's own band reservation reads the
    -- one the block already claimed. The scroll is NOT in this list: it is the
    -- library's now and is created once per ctx, not once per render.
    local inst, p = editorInstance()
    local list = activeList(inst)
    local g = inst.mocks.__aceGUI
    local mark = #g.__created
    p:RefreshRows()
    local types = {}
    for i = mark + 1, #g.__created do types[#types + 1] = g.__created[i].type end
    assertEqual(types[1], "Dropdown", "the spec dropdown leads the chrome block")
    -- The add control is the library's IdInput now, not a Button: a SimpleGroup holding the box,
    -- its Add button and its status line. Its HOST group comes first, then the row the library
    -- builds inside it.
    assertEqual(types[2], "SimpleGroup", "then the add control's host group")
    assertEqual(types[3], "SimpleGroup", "and the row O.IdInput builds inside it")
    assertEqual(types[4], "EditBox", "whose first child is the box itself")
    -- Counted from the third SimpleGroup on: the first two are the add control's host and the row
    -- the library builds inside it, neither of which is a list row. `rebuildRows` tells them apart
    -- properly (by the EditBox they carry); this case is about ORDER, so it counts positionally
    -- and says why the offset is two.
    local groups = 0
    for _, ty in ipairs(types) do
        if ty == "SimpleGroup" then groups = groups + 1 end
    end
    assertEqual(groups - 2, #list, "one row group per list entry, after the add control's two")
end)

test("the page draws its strip, and the rows land in the LIBRARY's scroll", function()
    -- options-ui-§13: a page with one section still draws a one-tab strip, and
    -- this page is the addon's only fully bespoke one -- it had none at all.
    -- red under: deleting the H.TabStrip call from Spells:RefreshRows
    local inst, p = editorInstance()
    p:RefreshRows()
    local ctx
    for _, c in ipairs(inst.NS.Settings.Helpers.__panels()) do
        if c.pageKey == "spells" then ctx = c end
    end
    assertTrue(ctx ~= nil, "the Spells page must have a library ctx")
    assertTrue(#(ctx.__tabKids or {}) > 0, "the Spells page draws no tab strip")
    assertTrue(ctx.scroll ~= nil, "the rows must go into the library's scroll")
    assertTrue(#ctx.scroll.children > 0, "the library scroll holds the rows")
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

-- ── one render per commit, and a guard a raise cannot latch (KICKCD-R-08) ────

--- Count H.PageHeader calls -- one per render -- while fn runs.
local function countRenders(inst, fn)
    local H = inst.NS.Settings.Helpers
    local real, n = H.PageHeader, 0
    H.PageHeader = function(...) n = n + 1; return real(...) end
    local ok, err = pcall(fn)
    H.PageHeader = real
    if not ok then error(err, 0) end
    return n
end

test("one commitSoon flush renders the Spells page once", function()
    -- doCommit used to render AND fire CONFIG_CHANGED, whose own subscriber on this page renders
    -- again: every edit drew the page twice.
    local inst, p = editorInstance()
    local rows = rebuildRows(inst, p)
    local n = countRenders(inst, function()
        rows[1].children[4]:__fire("OnValueChanged", false)
        inst.mocks.__flushTimers()
    end)
    assertEqual(n, 1, "one edit, one render")
end)

test("a raising render does not latch the guard", function()
    -- rebuildScheduled was cleared on the explicit returns only, so a raise mid-render left it set
    -- and every later RefreshRows returned early for the rest of the session.
    local inst, p = editorInstance()
    local H = inst.NS.Settings.Helpers
    local real = H.EnsureScroll
    H.EnsureScroll = function() H.EnsureScroll = real; error("boom", 0) end
    T.assertError(function() p:RefreshRows() end, "the raise reaches the caller")
    H.EnsureScroll = real
    assertEqual(countRenders(inst, function() p:RefreshRows() end), 1,
        "the next refresh still renders")
end)

test("while stood down a commit still repaints the open page", function()
    -- Spells.StandDown unregisters the CONFIG_CHANGED subscriber, so while the addon is down the
    -- direct render in doCommit is the only one the page gets.
    local inst, p = editorInstance()
    inst.NS.Settings.Helpers.SetAndRefresh("enabled", false)
    inst.mocks.__flushTimers()
    assertTrue(inst.NS.IsDown(), "the addon is stood down")
    for _, ctx in ipairs(inst.NS.Settings.Helpers.__panels()) do ctx.panel:Show() end
    local rows = rebuildRows(inst, p)
    local n = countRenders(inst, function()
        rows[1].children[4]:__fire("OnValueChanged", false)
        inst.mocks.__flushTimers()
    end)
    assertEqual(n, 1, "the page repaints once with no subscriber to do it")
end)

test("a rebuild drains the scroll before building a new tree into it", function()
    -- The scroll is the library's and is REUSED across renders, so what has to
    -- happen is a drain (H.ClearScroll) rather than a release -- and it has to
    -- stay ahead of any new widget creation or the AceGUI pool leaks a full tree
    -- per refresh. Counted at the moment the drain lands, not at the end: a
    -- second RefreshRows refills it immediately.
    local inst, p = editorInstance()
    p:RefreshRows()
    local ctx
    for _, c in ipairs(inst.NS.Settings.Helpers.__panels()) do
        if c.pageKey == "spells" then ctx = c end
    end
    local container = ctx.scroll
    assertTrue(container ~= nil)
    local before = #container.children
    assertTrue(before > 0, "the container holds the rendered rows")

    local drained
    local realClear = inst.NS.Settings.Helpers.ClearScroll
    inst.NS.Settings.Helpers.ClearScroll = function(c)
        realClear(c)
        if c == ctx then drained = #container.children end
    end
    p:RefreshRows()
    inst.NS.Settings.Helpers.ClearScroll = realClear
    assertEqual(drained, 0, "the previous tree must have been drained")
    assertEqual(#container.children, before, "and the same number of rows rebuilt")
end)

test("a re-render cancels the reorder controller BEFORE it clears the tree", function()
    -- options-ui-§18's shipped-bug lesson, and the one thing about this adoption
    -- that cannot be seen by looking at the finished page. Handles and row boxes
    -- are POOLED and parented to the row frames; those frames go back to AceGUI
    -- on the clear. A Cancel that runs after it reclaims a handle from whatever
    -- widget took the frame next.
    -- red under: moving cancelReorder() below releaseAceGUITree() in RefreshRows
    local inst, p = editorInstance()
    p:RefreshRows()
    local ctx
    for _, c in ipairs(inst.NS.Settings.Helpers.__panels()) do
        if c.pageKey == "spells" then ctx = c end
    end
    local seq = {}
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0", true)
    local realReorder = W.ReorderList
    W.ReorderList = function(opts)
        local ctl = realReorder(opts)
        local realCancel = ctl.Cancel
        ctl.Cancel = function(self) seq[#seq + 1] = "cancel"; return realCancel(self) end
        return ctl
    end
    local realClear = inst.NS.Settings.Helpers.ClearScroll
    inst.NS.Settings.Helpers.ClearScroll = function(c)
        if c == ctx then seq[#seq + 1] = "clear" end
        return realClear(c)
    end

    p:RefreshRows()   -- builds a controller whose Cancel we can see
    p:RefreshRows()   -- ...and cancels it on the way in

    W.ReorderList = realReorder
    inst.NS.Settings.Helpers.ClearScroll = realClear
    assertEqual(seq[1], "clear", "the first render only clears; nothing to cancel yet")
    assertEqual(seq[2], "cancel", "the second render must cancel FIRST")
    assertEqual(seq[3], "clear", "and clear after")
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

test("a stale remove click after a rebuild cannot run off the end of the list", function()
    -- The remove callback closes over `index`, which is only valid until the
    -- next rebuild. table.remove past the end is a no-op rather than a raise,
    -- and this is what says the list is not corrupted by one.
    local inst, p = editorInstance()
    local list = activeList(inst)
    local rows = rebuildRows(inst, p)
    local staleRemove = rows[#rows].children[8]
    -- Shrink the list under the captured index, then fire the stale handler.
    for i = #list, 2, -1 do table.remove(list, i) end
    staleRemove:__fire("OnClick")
    assertEqual(#list, 1, "the stale click must not eat the surviving row")
end)

test("hiding the page cancels the reorder controller too", function()
    -- A hide hands every row frame back to AceGUI's pool exactly as a re-render
    -- does, so it is the same bug by the other door: a handle still parented to
    -- one goes into the pool with it and reappears on whatever takes that frame
    -- next -- possibly in another addon.
    -- red under: dropping cancelReorder() from the panel's OnHide
    local inst, p = editorInstance()
    p:RefreshRows()
    local canceled = 0
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0", true)
    local realReorder = W.ReorderList
    W.ReorderList = function(opts)
        local ctl = realReorder(opts)
        local realCancel = ctl.Cancel
        ctl.Cancel = function(self) canceled = canceled + 1; return realCancel(self) end
        return ctl
    end
    p:RefreshRows()          -- build a controller we can watch
    W.ReorderList = realReorder

    for _, c in ipairs(inst.NS.Settings.Helpers.__panels()) do
        if c.pageKey == "spells" then c.panel:Hide() end
    end
    assertEqual(canceled, 1, "the hide must reclaim the handles and boxes")
end)

-- ── kit reach: AceGUI:Release (#21) ─────────────────────────────────────────

test("kit reach: a rebuild hands the previous header widgets back through AceGUI:Release", function()
    -- settings/Spells.lua's releaseAceGUITree calls the guarded `w:Release()` on
    -- the header widgets of the render it replaces. Before #21 the harness's own
    -- AceGUI had no Release, so the guard skipped it and nothing here could see
    -- a double release or a widget handed back still carrying its callbacks.
    local inst, p = editorInstance()
    local g = inst.mocks.__aceGUI
    p:RefreshRows()
    local before = #g.__released
    p:RefreshRows()
    assertTrue(#g.__released > before, "the second rebuild must release the first rebuild's header widgets")
    for i = before + 1, #g.__released do
        local w = g.__released[i]
        assertTrue(w.__released, "each released widget is marked by the kit")
        assertNil(next(w.callbacks), "a released widget carries no callbacks")
    end
end)
