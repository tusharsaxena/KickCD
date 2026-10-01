-- settings/Spells.lua
--
-- Per-class+spec spell-list editor. Uses the unified canvas panel
-- header (title + Defaults button + divider) from Panel.lua, then draws the
-- page the way every other page in this addon is drawn (options-ui-§13/options-ui-§14):
--
--   * the spec picker and Add spell in a page-wide CHROME BLOCK (H.PageHeader)
--     -- both apply to every tab, so neither may live in the scroll;
--   * a one-tab STRIP under it (H.TabStrip). A page with one section still
--     draws a strip; the tab is what names the list;
--   * the rows in the library's own scroll (H.EnsureScroll), which anchors
--     itself under whatever band the two above reserved.
--
-- The rows DRAG (LibKa0s-Widgets-1.0's ReorderList, options-ui-§18). The paired
-- up/down arrows that used to sit on each row are gone, and so is the row
-- background: the library owns the handle, the bounded box, the ghost, the
-- insertion line and the index arithmetic.
--
-- The "Defaults" button in the header runs the existing reset-to-defaults
-- StaticPopup for the currently selected class+spec.
--
-- The page and its popups write the stored list in place, then call
-- commitSoon, a 50 ms throttle that fires Ka0s_KickCD_ConfigChanged
-- { section = "spells" }; the page's own subscriber re-renders the rows.

local _, NS = ...

local L      = NS.L      or setmetatable({}, { __index = function(_, k) return k end })
local Compat = NS.Compat or {}
local Util   = NS.Util   or {}

local Spells = {}

-- Published so the headless suites can drive the editor's selection state
-- (which is otherwise file-local). Not part of the inter-module contract —
-- nothing in the addon reads this; the message bus stays the only channel
-- between modules (architecture-§4).
NS.Settings = NS.Settings or {}
NS.Settings.SpellsPanel = Spells

-- The closed category set. Mirrors the keys in locales/enUS.lua.
local CATEGORIES = {
    "interrupt", "stun", "knockback", "incapacitate",
    "silence", "root", "fear", "displace", "racial", "other",
}

-- ---------------------------------------------------------------------------
-- The chrome band's height (options-ui-§14)
-- ---------------------------------------------------------------------------
--
-- ADDED UP FROM ITS PARTS RATHER THAN TUNED. It was a hand-picked 44, then 72, then 96, and the
-- third one was nine pixels short of its own content without anything saying so -- a written
-- status line drew straight over the library's divider and into the tab strip, because
-- SimpleGroup does not clip. A number nobody can check is a number that goes wrong quietly, so
-- each term below names the widget it pays for and where that widget's height comes from.
--
-- THE BAND GROWS RATHER THAN THE CONTROL MOVING, and that is options-ui-§14's call, not a preference:
-- "Controls that apply to every tab MUST sit in that band too, above the strip -- never in the
-- scroll below it", and the band "MUST carry the identity controls -- the picker, and the create
-- control where the page has one". Adding a spell is this page's create control. The cost is the
-- one that section warns about -- every row below sits permanently lower -- and the escape options-ui-§14
-- offers is for the ACTS (rename, copy, reset, delete), explicitly not for these two.
--
-- THE BAND IS TWO ROWS, WHICH options-ui-§14 SAYS IT SHOULD NOT BE. Filed as an accepted deviation in
-- docs/ARCHITECTURE.md -> Documented deviations, with its re-check trigger.

-- AceGUI's labeled Dropdown sets its own frame to 40 (AceGUIWidget-DropDown.lua's SetLabel:
-- `self:SetHeight(40)`; 26 without a label). Read, not chosen.
local HEADER_PICKER_H  = 40
-- The gap between the band's two rows. Small enough that they read as one block of chrome and
-- not as two, which is the thing options-ui-§14 warns a growing band turns into.
local HEADER_ROW_GAP   = 6
-- AceGUI's labeled EditBox sets its frame to 44 (AceGUIWidget-EditBox.lua's SetLabel), of which
-- 18 is the caption, 19 the box, and 7 is the widget's own bottom padding. The Add button beside
-- it is 24 and does not raise the row.
local HEADER_ADD_ROW_H = 44
-- AceGUI's Flow layout puts exactly 3 between one row and the next (`height + rowheight + 3`).
-- The status line is full width, so it always wraps to a row of its own.
local HEADER_FLOW_GAP  = 3
-- What the status line needs when it SAYS something. Empty, AceGUI floors a Label at 1px, so
-- reserving nothing looked fine in every screenshot and broke on the one frame that mattered:
-- the refusal ("no spell named ...") the add box writes when a name resolves to nothing. One
-- line of GameFontHighlightSmall, which the Label takes by default.
local HEADER_STATUS_H  = 12

local HEADER_BLOCK_H = HEADER_PICKER_H + HEADER_ROW_GAP
    + HEADER_ADD_ROW_H + HEADER_FLOW_GAP + HEADER_STATUS_H

-- ---------------------------------------------------------------------------
-- Module-private state
-- ---------------------------------------------------------------------------

local ctx              -- the H.CreatePanel context (panel + body + cursor + ...)
local panel            -- ctx.panel — the canvas Frame
local body             -- ctx.body — frame below the unified header
local container        -- the library's AceGUI ScrollFrame (ctx.scroll)
local headerWidgets    -- AceGUI dropdowns/button — released on hide
-- The drag-reorder controller for the CURRENT render. One per render, never one
-- per list: it holds the rows of the pass that built it (libs/LibKa0s/Widgets.lua),
-- and a repaint builds a new one.
local reorder
local fallbackLabel    -- shown when AceGUI isn't available
local selectedClass
local selectedSpec
local rebuildScheduled
-- True until the first OnShow consumes it. Re-armed in OnHide whenever
-- the entire Settings UI hides (full close), so the next /kcd config
-- re-seeds selectedClass/Spec to the player's current pair via
-- seedSelectionToPlayer(). False during tab swaps within an open
-- Settings session, so the user's dropdown choice survives them.
local freshOpen = true

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    if type(t) == "table" then
        for k in pairs(t) do keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- Spec IDs for a class, in the order the dropdown should list them.
--
-- Prefers Blizzard's own spec order (matching the character sheet, so
-- Elemental/Enhancement/Restoration rather than 262/263/264 happening to
-- sort that way by luck), intersected with what defaults/Spells.lua
-- actually ships so the editor never offers a spec it can't render.
-- Falls back to sorted numeric keys when the client can't be queried.
local function specOrder(classFile)
    local specs = NS.DefaultSpells and NS.DefaultSpells[classFile]
    if type(specs) ~= "table" then return {} end
    local blizzOrder = NS.Util and NS.Util.SpecOrderForClass
        and NS.Util.SpecOrderForClass(classFile)
    if not blizzOrder then return sortedKeys(specs) end
    local out = {}
    for _, specID in ipairs(blizzOrder) do
        if specs[specID] then out[#out + 1] = specID end
    end
    -- Anything defaults ships that Blizzard didn't enumerate (a spec added
    -- to defaults ahead of a client patch) still has to appear.
    if #out < #sortedKeys(specs) then
        local seen = {}
        for _, id in ipairs(out) do seen[id] = true end
        for _, id in ipairs(sortedKeys(specs)) do
            if not seen[id] then out[#out + 1] = id end
        end
    end
    return out
end

-- Resolve the player's CURRENT class file token (e.g. "MAGE") and the
-- NUMERIC specID of their active spec (e.g. 64). Both gated by the
-- corresponding KickCD.DefaultSpells presence so callers never set a
-- (class, spec) pair the editor can't render. Returns (class, specID) or
-- (class, nil) for classes whose current spec isn't in defaults, or
-- (nil, nil) when the spec API is unavailable.
local function getPlayerClassSpec()
    -- `UnitClass and UnitClass("player")` would truncate to UnitClass's
    -- FIRST return (the localized name); the file token we need is the
    -- second. Guard without collapsing the multi-return.
    local classFile
    if _G.UnitClass then
        local _, cf = _G.UnitClass("player")
        classFile = cf
    end
    if not (classFile and NS.DefaultSpells
            and NS.DefaultSpells[classFile]) then
        return nil, nil
    end
    local specID = NS.Util and NS.Util.PlayerSpecID and NS.Util.PlayerSpecID()
    if specID and not NS.DefaultSpells[classFile][specID] then
        specID = nil
    end
    return classFile, specID
end

-- Reset the editor's selection to the player's current class+spec.
-- Called whenever the Spells editor should "default to my own spec":
--   * on initial panel build (so the first /kcd config lands on the
--     right spec without requiring user interaction)
--   * when the entire Settings UI closes (so the next /kcd config
--     resets — within an open Settings session, switching tabs
--     preserves whatever spec the user picked from the dropdown)
local function seedSelectionToPlayer()
    selectedClass, selectedSpec = nil, nil
    local classFile, specID = getPlayerClassSpec()
    if not classFile then return end
    selectedClass = classFile
    selectedSpec = specID or specOrder(classFile)[1]
end

--- Current editor selection, as (classFile, specID).
-- @return string|nil, number|nil
function Spells:GetSelection()
    return selectedClass, selectedSpec
end

--- Re-seed the selection to the player's live class+spec. Exposed for the
--- headless suites; in-game this is reached via OnPlayerSpecChanged and the
--- fresh-open path in the panel's OnShow.
function Spells:SeedSelectionToPlayer()
    seedSelectionToPlayer()
end

--- PLAYER_SPECIALIZATION_CHANGED handler.
---
--- Regression fix: swapping spec with Settings > Spells already open used to
--- leave the dropdown pinned to the old spec. Selection was only re-seeded on
--- a FRESH open (freshOpen, re-armed solely on a full Settings close), and the
--- panel's SPELLS_CHANGED / TRAIT_CONFIG_UPDATED handlers only re-rendered the
--- existing rows — nothing re-read the player's spec.
---
--- Following the live spec deliberately overrides a spec the user picked from
--- the dropdown by hand: they just changed spec in-game, which is the stronger
--- signal of what they want to look at. When the panel is closed we still
--- re-seed, so the next open is correct without waiting for the fresh-open
--- path.
function Spells:OnPlayerSpecChanged()
    seedSelectionToPlayer()
    if panel and panel:IsShown() then
        self:RefreshRows()
    end
end

-- Read-only active-list lookup. Never lazy-creates the per-class /
-- per-spec table — browsing the dropdown across 13 classes × 4 specs
-- would otherwise pollute saved-vars with empty tables (CR-22).
--
-- The page READS the list and never writes it. Every write -- add, remove,
-- move, the per-spec reset, and an entry's enabled / category -- is a
-- core/Database.lua verb, called through `writer` below for the selected
-- (class, spec). Database is the spell lists' one writer (architecture-§5).
local function getActiveList()
    if not (selectedClass and selectedSpec) then return nil end
    if not NS.Database then return nil end
    return NS.Database:GetSpellList(selectedClass, selectedSpec)
end

-- Call a Database verb on the selected (class, spec) list. Returns whatever the
-- verb returned, or nil when there is no selection or no Database.
local function writer(verb, ...)
    if not (selectedClass and selectedSpec and NS.Database) then return nil end
    return NS.Database[verb](NS.Database, selectedClass, selectedSpec, ...)
end

local function getSpellName(id)
    if not id then return nil end
    if Compat.GetSpellInfo then
        local name = Compat.GetSpellInfo(id)
        if name then return name end
    end
    return nil
end

local function getSpellIcon(id)
    if not id then return nil end
    if Compat.GetSpellTexture then return Compat.GetSpellTexture(id) end
    return nil
end

-- The resolver, the Cooldown Manager set and its invalidator live in
-- core/SpellInput.lua, shared with `/kcd spells add` (KICKCD-R-05). The
-- invalidator is an AceEvent target armed at THAT file's load, so the cache is
-- dropped on a spec or talent change whether or not this page is ever built
-- (KICKCD-A-04).
local SpellInput = NS.SpellInput

-- ---------------------------------------------------------------------------
-- Throttled commit pipeline
-- ---------------------------------------------------------------------------
--
-- Throttle (not debounce) is the right semantic here: the editor
-- coalesces a burst of edits (e.g. holding the spinner button,
-- toggling several rows in quick succession) into a single bus
-- dispatch per 50 ms window — we want a steady cadence during the
-- burst, not a quiet-period wait that delays the first commit
-- indefinitely.

local function FireConfigChanged()
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("spells") end
end

local commitSoon

-- ONE render per commit. While the addon is up, FireConfigChanged's own
-- CONFIG_CHANGED subscriber on this page renders it; rendering here as well drew
-- the page twice per edit (KICKCD-R-08). While it is stood down that subscriber
-- is unregistered (Spells.StandDown), so the direct render is the only one.
local function doCommit()
    if NS.IsDown and NS.IsDown() and panel and panel:IsShown() then
        Spells:RefreshRows()
    end
    FireConfigChanged()
end

if Util.Throttle then
    commitSoon = Util.Throttle(50, doCommit)
else
    commitSoon = doCommit
end

-- ---------------------------------------------------------------------------
-- StaticPopups (Add spell / Reset to defaults)
-- ---------------------------------------------------------------------------

-- The Add-spell accept path, as file-locals. A StaticPopup handler is written
-- inline as a table field, so nothing in it can be reached — by a reader or by
-- the harness — until it is lifted out here.

local function notify(msg)
    if NS.Util and NS.Util.print then NS.Util.print(msg) end
end

-- The player's CURRENT class file token, or nil. `UnitClass and
-- UnitClass("player")` would truncate to UnitClass's FIRST return (the
-- localized name); the file token we need is the second.
local function playerClassFile()
    if not _G.UnitClass then return nil end
    local _, cf = _G.UnitClass("player")
    return cf
end

-- Is the editor's selected (class, spec) the player's own live pair?
--
-- Cooldown-manager gating only applies when it is. The C_CooldownViewer API has
-- no class/spec parameter — it returns the set for the LOGGED-IN player's
-- currently-active spec. So a Mage editing HUNTER/BEASTMASTERY would otherwise
-- be blocked from adding any Hunter spell. When the pair doesn't match, the gate
-- is DROPPED and the add goes through leniently (the resolver has already
-- confirmed the spell exists in the spell DB). SpellInput.IsLivePair is the
-- test; this wrapper adds only the page's debug line.
local function editorIsActiveSpec()
    if SpellInput.IsLivePair(selectedClass, selectedSpec) then return true end
    if NS.State and NS.State.debug then
        local playerClass  = playerClassFile()
        local playerSpecID = NS.Util.PlayerSpecID()
        NS.Debug("Spells", "Editing %s/%s ≠ player %s/%s; skipping cooldown-manager gate.",
            tostring(selectedClass), NS.Util.SpecDisplay(selectedSpec),
            tostring(playerClass), NS.Util.SpecDisplay(playerSpecID))
    end
    return false
end

-- True when the Blizzard Cooldown Manager does not track this spell for the
-- player's active spec, so the add should be refused -- and says why in chat.
-- The verdict is core/SpellInput.lua's, the one `/kcd spells add` asks too.
local function cooldownManagerRejects(id)
    local ok, why = SpellInput.Admissible(id, selectedClass, selectedSpec)
    if ok then return false end
    notify(why)
    return true
end

-- Database:AddSpell lazy-creates the list on first add, so a spec the user has
-- never customized gains one rather than failing silently, and re-enables a
-- spell already in the list IN PLACE rather than appending a duplicate.
local function addOrEnableSpell(id)
    if writer("AddSpell", id) then commitSoon() end
end

--- The add control's own words, through the locale. The library's defaults are English literals,
--- so a localized build would show them untranslated beside this page's own strings.
local ADD_STRINGS = {
    add       = L["Add"],
    -- WHERE A NAME CAN COME FROM, routed. The library has its own sentence for a spell kind and
    -- ends its refusal with it -- but as an English LITERAL, so a localized build would show it
    -- untranslated beside this page's own strings. Aura Master localizes the same sentence for the
    -- same reason (its NAME_HINT); this is that, for the one kind this page uses.
    nameHint  = L["Names work for spells in your spellbook and ones this list knows; otherwise use the id or shift-click a link."],
    empty     = L["Type a spell id, a spell link or a spell name."],
    notFound  = L["No spell named '{text}' in your spellbook."],
    ambiguous = L["Several spells are named '{text}' — pick one from the list, or use the id."],
    unknown   = L["Unknown spell {id}"],
    looking   = L["Looking up spells..."],
}

--- The ids this spec already lists, for the add box's suggestions.
---
--- The SPELLBOOK comes with `kind = "spell"` and is not repeated here. What this adds is the
--- spells already on the list -- so a player retyping one they disabled sees it offered instead of
--- hunting the id -- and it is exactly the set the list is drawn from, so it cannot drift from it.
local function currentSpellIds()
    local out = {}
    local list = getActiveList()
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        local id = type(e) == "table" and e.spellID or e
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out
end

--- The word a suggestion row wears when the Cooldown Manager does not track that spell for the
--- spec being edited.
---
--- LIFTED OUT AND PUBLISHED, for the reason this file's header already gives about the popup's
--- handler: written inline as a table field it could not be reached by a reader or by the harness.
---
--- Nil in every case but the one it is for: another spec's list (the refusal below only fires for
--- the active spec, so a tag on a list the player is only editing would claim something this
--- addon does not check), a client with no C_CooldownViewer, and a spell the set holds.
function Spells.SuggestTag(id)
    if not editorIsActiveSpec() then return nil end
    local cmSet = SpellInput.CooldownManagerSet()
    if not cmSet or cmSet[id] then return nil end
    return "|cffff8000" .. L["not tracked"] .. "|r"
end

--- The add box's accept path: the same two steps the StaticPopup ran, minus the parsing the
--- library now owns.
---
--- The library has already resolved a name, a link or an id to a NUMBER by the time this is
--- called, so `SpellInput.Resolve` has nothing left to do -- what stays is this addon's own
--- question, which the library cannot ask: does the Blizzard Cooldown Manager track this spell for
--- the spec being edited. That refusal still speaks in chat rather than on the box's status line,
--- because it is about the game's state and not about what was typed.
local function addFromBox(id)
    if editorIsActiveSpec() and cooldownManagerRejects(id) then return end
    addOrEnableSpell(id)
end

StaticPopupDialogs["KICKCD_RESET_SPELLS"] = {
    text         = L["Reset all spells for this spec to addon defaults?"],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    -- The same verb `/kcd spells reset` calls: the selected spec from the
    -- defaults, plus the player's racial when it is their own class. The
    -- [Spells] trace is the writer's (core/Database.lua), not this handler's.
    OnAccept = function()
        if writer("ResetSpellList") then commitSoon() end
    end,
}

-- ---------------------------------------------------------------------------
-- AceGUI rows
-- ---------------------------------------------------------------------------

-- The row builders (buildRow and the per-widget builders under it) and
-- ROW_HEIGHT live in settings/Spells_Rows.lua, published as Spells.BuildRow
-- and Spells.ROW_HEIGHT. What they read of this file is Spells.__rowDeps,
-- filled at the end of this file.

-- The dropdown's items/order are a constant — the closed CATEGORIES set, keyed
-- through the locale table — so they are built once on first use rather than
-- twice per row per refresh. Built lazily rather than at file load because the
-- original resolved L[cat] at row-build time. AceGUI's Dropdown only reads the
-- pair it is handed, so one shared copy is safe.
local CATEGORY_ITEMS, CATEGORY_ORDER

local function categoryList()
    if not CATEGORY_ITEMS then
        CATEGORY_ITEMS, CATEGORY_ORDER = {}, {}
        for i, cat in ipairs(CATEGORIES) do
            CATEGORY_ITEMS[cat] = L[cat] or cat
            CATEGORY_ORDER[i]   = cat
        end
    end
    return CATEGORY_ITEMS, CATEGORY_ORDER
end

-- The paired up/down arrow buttons that used to live here are gone
-- (options-ui-§18, anti-pattern #75): two clicks per position, no feedback about
-- where an item is going, and a different set of arrows drawn in every addon
-- that had them. The list drags now, through LibKa0s-Widgets-1.0's ReorderList,
-- and a finished drag is one Database:MoveSpell -- a splice to the index, not a
-- run of swaps (the reasoning sits on the verb).

--- Stop any drag in flight and give every pooled handle and row box back.
---
--- CALLED AT THE TOP OF THE RENDER, before the first widget is created -- not
--- merely before the list is rebuilt (options-ui-§18). Handles and boxes are
--- pooled and parented to the host's row frames, and those frames go back into
--- AceGUI's pool the moment releaseAceGUITree runs. A Cancel after that point
--- reclaims a handle from a widget that by then belongs to something else, which
--- is the single most common way an adoption of this widget goes wrong.
local function cancelReorder()
    if reorder then
        reorder:Cancel()
        reorder = nil
    end
end


-- ---------------------------------------------------------------------------
-- Rebuild
-- ---------------------------------------------------------------------------

-- The scroll itself is the LIBRARY's now (H.EnsureScroll), and it is reused
-- across renders exactly as every other page's is -- so this drains its children
-- through H.ClearScroll rather than releasing the ScrollFrame. The header
-- widgets are still ours: they live inside the page's chrome block, which is
-- rebuilt whole on every render.
local function releaseAceGUITree()
    if ctx then
        local H = NS.Settings and NS.Settings.Helpers
        if H and H.ClearScroll then H.ClearScroll(ctx) end
    end
    container = nil
    if headerWidgets then
        for _, w in ipairs(headerWidgets) do
            if w and w.Release then w:Release() end
        end
        headerWidgets = nil
    end
end

-- The chrome block's builders (the class / spec labels and icons, the spec
-- entries, the picker and the add box) live in settings/Spells_Header.lua (#28),
-- published as Spells.BuildHeader; renderRows below calls it at render time.

-- The AceGUI-is-absent arm: a plain FontString saying so, built once and
-- re-shown thereafter.
local function showAceGUIMissing()
    if not fallbackLabel then
        fallbackLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fallbackLabel:SetPoint("CENTER", body, "CENTER", 0, 0)
        fallbackLabel:SetText("AceGUI not loaded")
    end
    fallbackLabel:Show()
end

-- Default the class/spec selection so the panel always has something to render.
-- Prefers the player's own class when the defaults ship it, falling back to the
-- first sorted class otherwise.
local function ensureSelection(classes)
    if not selectedClass or not (NS.DefaultSpells and NS.DefaultSpells[selectedClass]) then
        local _, classFile = _G.UnitClass("player")
        if classFile and NS.DefaultSpells and NS.DefaultSpells[classFile] then
            selectedClass = classFile
        else
            selectedClass = classes[1]
        end
    end
    if selectedClass and not selectedSpec then
        selectedSpec = specOrder(selectedClass)[1]
    end
end

-- (buildScrollContainer is GONE. This page hand-built an AceGUI ScrollFrame
-- anchored to ctx.body at a hardcoded -56 top inset, which is exactly the band
-- the chrome now occupies -- and that number cannot be right for both a page
-- with a chrome block and one without. H.EnsureScroll anchors under
-- ctx.chromeHeight, which H.PageHeader and H.TabStrip have already set, and it
-- carries the always-shown scrollbar patch this page used to apply by hand.)

--- Paint the rows, and hand each one to the reorder controller.
---
--- WITHOUT LibKa0s-Widgets there is no handle and no row box, and the list is
--- not reorderable. That is an accepted cosmetic degradation (options-ui-§18)
--- and the arrows are deliberately NOT re-added as a fallback -- a host-drawn
--- alternative is the drift the shared widget exists to end.
---
--- No row background or border is drawn here either. The library owns the
--- bounded box now, and a host box under it would stack two fills.
-- The guidance an empty list shows, as RenderGrid's one wide item. Names the control that is
-- actually there. It read "Click Add spell..." until the button became the band's add box, which
-- would have sent a player looking for a button.
local function emptyListItem(AceGUI)
    return { wide = true, path = "spells.empty", make = function(_, into)
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["No spells tracked. Type one into Add a spell above, or press Defaults."])
        lbl:SetFullWidth(true)
        into:AddChild(lbl)
        return true
    end }
end

-- One wide item per entry. The row is built INTO the group RenderGrid hands `make`, so that group
-- is the row: the one child the scroll's List layout stacks, exactly ROW_HEIGHT tall, and the
-- frame the reorder controller is handed. Each built group is noted in `built` because the
-- controller can only take it AFTER RenderGrid has added it to the scroll -- the handle and the
-- box are parented to the row frame, which has no parent of its own until then. A row that cannot
-- be built answers false, and the grid releases its group rather than leaving a blank slot.
local function spellItems(AceGUI, list, built)
    local items = {}
    for i = 1, #list do
        items[i] = { wide = true, path = "spells[" .. i .. "]", make = function(_, into)
            if not Spells.BuildRow(AceGUI, list, i, into) then return false end
            built[#built + 1] = { group = into, index = i }
            return true
        end }
    end
    return items
end

local function newReorder()
    local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
    if not (W and W.ReorderList) then return nil end
    return W.ReorderList{
        -- Uniform rows, so the stride IS the row height: AceGUI's List layout stacks children
        -- with no gap of its own, and RenderGrid is called with `gap = false` so it adds none.
        stride        = Spells.ROW_HEIGHT,
        -- No `boundary`: one flat priority list, with no section a drag must not cross.
        handleIcon    = NS.Icon and NS.Icon("segment") or nil,
        handleTooltip = L["Drag to reorder"],
        onMove        = function(from, to)
            -- ONE write, ONE re-render, however far the row traveled.
            -- The [Spells] move line is the writer's (core/Database.lua).
            if writer("MoveSpell", from, to) then commitSoon() end
        end,
        debug = function(fmt, ...)
            if NS.State and NS.State.debug then NS.Debug("Spells", fmt, ...) end
        end,
    }
end

--- Paint the rows through H.RenderGrid, and hand each one to the reorder controller.
---
--- `gap = false` because the stride is arithmetic: RenderGrid's default spacer after every row
--- would put each drop target 8px further off per row (KickCD#10). RenderGrid does not lay out;
--- renderRows calls container:DoLayout() after this returns.
---
--- WITHOUT LibKa0s-Widgets there is no handle and no row box, and the list is
--- not reorderable. That is an accepted cosmetic degradation (options-ui-§18)
--- and the arrows are deliberately NOT re-added as a fallback -- a host-drawn
--- alternative is the drift the shared widget exists to end.
---
--- No row background or border is drawn here either. The library owns the
--- bounded box now, and a host box under it would stack two fills.
local function fillRows(AceGUI, scroll, list)
    local H = NS.Settings and NS.Settings.Helpers
    if not list or #list == 0 then
        H.RenderGrid(ctx, { emptyListItem(AceGUI) }, scroll, { gap = false })
        return
    end

    reorder = newReorder()
    local built = {}
    H.RenderGrid(ctx, spellItems(AceGUI, list, built), scroll, { gap = false })
    if not reorder then return end
    for _, b in ipairs(built) do
        local id = list[b.index].spellID
        reorder:AddRow(b.group.frame, { ghostText = getSpellName(id) or ("#" .. tostring(id)) })
    end
    reorder:Finish(scroll.content or scroll.frame)
end

local function renderRows()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then
        showAceGUIMissing()
        return
    end

    -- FIRST, before releaseAceGUITree and before any widget is created. The
    -- handles and row boxes this reclaims are parented to row frames that
    -- releaseAceGUITree is about to hand back to AceGUI's pool; cancel after
    -- that and they stay attached to whatever takes those frames next
    -- (options-ui-§18).
    cancelReorder()

    -- Release before creating anything new, or the AceGUI pool leaks a whole
    -- widget tree per refresh.
    releaseAceGUITree()

    ensureSelection(sortedKeys(NS.DefaultSpells))

    local H = NS.Settings and NS.Settings.Helpers

    -- The chrome band, then the strip, then the content -- in that order,
    -- because the strip's own reservation reads the band the block already
    -- claimed (options-ui-§14). The spec picker and Add spell are page-wide, so
    -- they go ABOVE the strip rather than into the scroll.
    H.PageHeader(ctx, {
        height = HEADER_BLOCK_H,
        build  = function(headerCtx, frame) Spells.BuildHeader(AceGUI, headerCtx, frame) end,
    })

    -- ONE TAB, and it draws a strip anyway (options-ui-§13). "A single tab is
    -- chrome for its own sake" is a true sentence about this page and the wrong
    -- rule for a panel: every other page in this addon meets the reader with a
    -- strip, and the one that has none is the one that looks broken. The tab is
    -- also the only thing left naming what the list below it IS.
    --
    -- Not RenderTabbedSchema: this page has no schema rows at all, so there is
    -- nothing for the flow engine to partition. The strip is drawn directly and
    -- there is only ever one value to select, so onSelect has nothing to do.
    H.TabStrip(ctx, {
        tabs  = { { key = "list", label = L["Spell list"],
                    tooltip = L["The tracked spells for the selected specialization, in priority order."] } },
        value = "list",
        onSelect = function() end,
    })

    container = H.EnsureScroll(ctx)
    if not container then
        showAceGUIMissing()
        return
    end
    fillRows(AceGUI, container, getActiveList())
    if container.DoLayout then container:DoLayout() end
end

-- The re-entrancy guard is reset by the pcall, not by each exit of the body: a
-- raise mid-render would otherwise leave it set and every later refresh would
-- return early for the rest of the session (KICKCD-R-08). The error is re-raised
-- unchanged.
function Spells:RefreshRows()
    if not panel or not panel:IsShown() or rebuildScheduled then return end
    rebuildScheduled = true
    local ok, err = pcall(renderRows)
    rebuildScheduled = false
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- Panel registration
-- ---------------------------------------------------------------------------

local function ensurePanel()
    if panel then return panel end

    local H = NS.Settings and NS.Settings.Helpers
    if not (H and H.CreatePanel) then return nil end

    ctx = H.CreatePanel("KickCDSpellsPanel", L["Spells"], {
        pageKey        = "spells",
        defaultsButton = true,
    })
    panel = ctx.panel
    body  = ctx.body

    -- Parked, not wired: the Defaults button doesn't exist until the
    -- panel's first OnShow (H.EnsureDefaultsButton).
    panel.defaultsOnClick = function()
        StaticPopup_Show("KICKCD_RESET_SPELLS")
    end

    -- Through H.SetRenderer rather than a parked OnShow (options-ui-§11,
    -- CX03). The library builds the Defaults button and refuses to render in
    -- combat, which is the point: the Blizzard AddOns sidebar reaches a canvas
    -- panel without going through OpenOptionsPanel, so the handler this
    -- replaces was the one way into the Spells page with no combat guard on
    -- it, on the path a player is most likely to take mid-fight.
    --
    -- This page renders on EVERY show, not only the first: OnHide below hands
    -- the whole widget tree back to AceGUI's pool, so a second show that
    -- skipped the renderer would draw nothing at all. It says so through
    -- H.RefreshPanel there rather than by reaching for the library's dirty
    -- flag directly.
    H.SetRenderer(ctx, function()
        -- "Fresh open" = the user just brought the entire Settings UI
        -- back up (vs. just switching tabs within an already-open
        -- session). Re-seed the spec dropdown to the player's CURRENT
        -- spec on every fresh open so it tracks in-game spec changes
        -- that happened while Settings was closed. Within an open
        -- session, tab-swapping preserves whatever spec the user
        -- selected in the dropdown.
        if freshOpen then
            seedSelectionToPlayer()
            freshOpen = false
        end
        Spells:RefreshRows()
    end)
    panel:SetScript("OnHide", function()
        -- Ahead of releaseAceGUITree here for the same reason it is ahead of it
        -- in RefreshRows: a hide hands every row frame back to AceGUI's pool,
        -- and a handle still parented to one goes with it (options-ui-§18).
        cancelReorder()
        releaseAceGUITree()
        if fallbackLabel then fallbackLabel:Hide() end
        -- Distinguish "user closed the entire Settings UI" from "user
        -- switched to another tab": SettingsPanel:IsShown() is false in
        -- the first case, true in the second. Arm the fresh-open flag
        -- only on full close so the next OnShow re-queries the player's
        -- current spec; tab swaps leave the flag false and the user's
        -- dropdown choice survives.
        if not (SettingsPanel and SettingsPanel:IsShown()) then
            freshOpen = true
        end
        -- The tree released above is the page's entire body, so the next show
        -- MUST re-render. Marking the hidden page dirty is how a host says that
        -- to the library (H.RefreshPanel, structural); the renderer is skipped
        -- on a show that finds the page neither unrendered nor dirty.
        H.RefreshPanel(ctx, true)
    end)

    Spells.RegisterPanelEvents()

    return panel
end

-- The page's GAME events, as `{ event, handler }` rows for NS.RegisterEventList.
-- The handlers used to be closures built inside RegisterPanelEvents; they read
-- only `panel` and `Spells`, both file-scope upvalues, so they live here and the
-- list with them. MODULE SCOPE so a stand-up allocates nothing (anti-patterns
-- #43), and one refused name costs only its own row (events-frames-taint-§1).
--
-- Talent / spellbook changes flip the per-row known/unknown glyph. Refresh while
-- the panel is open so the indicators stay in sync with what IconGrid is rendering.
local function refreshIfShown()
    if panel and panel:IsShown() then Spells:RefreshRows() end
end

-- Spec swaps move the SELECTION, not just the rows — see
-- Spells:OnPlayerSpecChanged. The event fires for any unit, so filter to the
-- player before re-seeding.
local function onSpecChanged(_, unit)
    if unit and unit ~= "player" then return end
    Spells:OnPlayerSpecChanged()
end

local PANEL_EVENTS = {
    { "SPELLS_CHANGED",                refreshIfShown },
    { "TRAIT_CONFIG_UPDATED",          refreshIfShown },
    { "PLAYER_SPECIALIZATION_CHANGED", onSpecChanged },
}

--- The page's own subscriptions, split out of ensurePanel so that the latch can
--- put them back after a stand-down (slash-commands-§7, Spells.StandUp). Every
--- registration is idempotent -- AceEvent keys on (event, target) -- so calling
--- this twice is harmless, which is what lets ensurePanel and the stand-up both
--- reach it.
---
--- The Spells panel is a plain-table module, not an AceAddon submodule, so it
--- owns a PRIVATE AceEvent target (architecture-§4 / KCD-09). Registering these
--- receivers on the shared KickCD addon object would risk clobbering a future
--- receiver of the same message.
function Spells.RegisterPanelEvents()
    Spells.__ev = Spells.__ev or (NS.NewBusTarget and NS.NewBusTarget())
    local ev = Spells.__ev
    if ev then
        ev:RegisterMessage(NS.MSG.PROFILE_CHANGED, function()
            if panel and panel:IsShown() then Spells:RefreshRows() end
        end)
        -- Slash-command mutations (`/kcd spells add/remove/...`) and the
        -- panel's own commitSoon both fire Ka0s_KickCD_ConfigChanged with
        -- section="spells". Subscribing here is what closes the bus
        -- contract — the slash layer no longer reaches across to call
        -- our RefreshRows directly (CR-7).
        ev:RegisterMessage(NS.MSG.CONFIG_CHANGED, function(_, payload)
            if payload and payload.section == "spells"
               and panel and panel:IsShown() then
                Spells:RefreshRows()
            end
        end)

        -- The three game events: PANEL_EVENTS above.
        NS.RegisterEventList(ev, PANEL_EVENTS)
    end
end

local function Build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end
    if not ensurePanel() then return nil end

    -- selectedClass / selectedSpec are seeded by the OnShow handler the
    -- first time the user enters the Spells tab (freshOpen starts true).
    -- The OnHide handler re-arms freshOpen on full Settings close so
    -- subsequent /kcd config re-queries the player's current spec.

    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, panel, L["Spells"])
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("spells", L["Spells"], Build)
end

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- Pure helpers behind the editor's input handling and spec ordering,
-- published so the harness can reach them without building an AceGUI tree
-- (same idiom as Castbar.AutoSizeLong).
-- ---------------------------------------------------------------------------
-- The stand-down (slash-commands-§7)
-- ---------------------------------------------------------------------------
--
-- THE PANEL SURVIVES; ITS SUBSCRIPTIONS DO NOT, and the line between the two is
-- worth stating because both halves are in slash-commands-§7. What survives is the settings
-- registration and the panel BODY: a disabled addon stays in Blizzard's AddOns
-- tree, this page still opens, still draws every row, and still writes every
-- edit -- which is the whole reason the disabled slash surface keeps `get`,
-- `set` and `/kcd spells`. What does not survive is a REGISTRATION: these five
-- exist to react to GAME events (a spec swap, a talent change) and slash-commands-§7's
-- "actually UNREGISTERED" is unqualified. A handler that early-returns on
-- `panel:IsShown()` is the draw gate in miniature -- the addon did not stop
-- watching, it stopped reacting, and the client still walks the list.
--
-- The cost is two things. First, a spec change made WHILE the addon is off and
-- WHILE this page is open does not re-render the rows under the player's cursor;
-- reopening the page does. Second, the Cooldown Manager cache is dropped on the
-- way back up (core/SpellInput.lua's StandUp), because nothing invalidated it
-- while the addon was down, so the first read after re-enabling rebuilds it.
--
-- `commitSoon` is deliberately NOT canceled here. It is armed by the player
-- typing in this editor, never by a game event, and a stand-down that threw away
-- an edit in flight would lose data the player just entered -- "no SavedVariables
-- write FROM A GAME EVENT" does not reach a write the player is in the middle of
-- making.

--- Release the page's game-event subscriptions. Called by the latch's standDown.
function Spells.StandDown()
    local ev = Spells.__ev
    if ev then
        if ev.UnregisterAllEvents   then ev:UnregisterAllEvents()   end
        if ev.UnregisterAllMessages then ev:UnregisterAllMessages() end
    end
end

--- Re-arm them. The Cooldown Manager cache is not this page's any more: it and
--- its invalidator are core/SpellInput.lua's, stood down and up beside this one
--- by core/LifecycleSetup.lua.
function Spells.StandUp()
    Spells.RegisterPanelEvents()
end

Spells.ValidateSpellInput = SpellInput.Resolve
Spells.SpecOrder          = specOrder
Spells.SortedKeys         = sortedKeys
-- Spells.TitleCaseToken / .ClassDisplayName are published by settings/Spells_Header.lua.

-- The page's file-locals the row builders in settings/Spells_Rows.lua call,
-- handed over once here at file end -- commitSoon is bound above by now -- and
-- read by that file at call time.
Spells.__rowDeps = {
    writer       = writer,
    commitSoon   = commitSoon,
    getSpellName = getSpellName,
    getSpellIcon = getSpellIcon,
    categoryList = categoryList,
}

-- The same hand-over for the chrome block's builders in settings/Spells_Header.lua
-- (#28). The selection and the header-widget list are this file's mutable
-- state, so the builder reaches them through these two closures (and
-- Spells:GetSelection) at call time rather than holding a copy that goes stale.
Spells.__headerDeps = {
    sortedKeys       = sortedKeys,
    specOrder        = specOrder,
    currentSpellIds  = currentSpellIds,
    addFromBox       = addFromBox,
    ADD_STRINGS      = ADD_STRINGS,
    HEADER_ROW_GAP   = HEADER_ROW_GAP,
    newHeaderWidgets = function() headerWidgets = {}; return headerWidgets end,
    setSelection     = function(classFile, specID) selectedClass, selectedSpec = classFile, specID end,
}
