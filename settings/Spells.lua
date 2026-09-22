-- settings/Spells.lua
--
-- Per-class+spec spell-list editor. Uses the unified canvas panel
-- header (title + Defaults button + divider) from Panel.lua, then draws the
-- page the way every other page in this addon is drawn (options-ui-§13/§14):
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
-- commitSoon, a 50 ms throttle that re-renders the rows and fires
-- Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }.

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

-- Status-glyph textures for the "known to the player?" indicator on each
-- row. Matches the In-bags / Not-in-bags glyphs ConsumableMaster uses
-- (Interface\RaidFrame\ReadyCheck-Ready / -NotReady) so the visual
-- vocabulary is consistent across the user's addons.
local SPELL_KNOWN_ICON     = [[Interface\RaidFrame\ReadyCheck-Ready]]
local SPELL_NOT_KNOWN_ICON = [[Interface\RaidFrame\ReadyCheck-NotReady]]

-- The height of the page-wide chrome block (options-ui-§14): one labeled AceGUI
-- Dropdown, which renders its label above the control, plus the Add-spell button
-- beside it. The library owns the band arithmetic around it -- the divider, the
-- gaps and the scroll's top edge -- so this is the block's own height and
-- nothing else.
-- The chrome band's height. 44 held a labeled dropdown and a button on one row; the add
-- control that replaced the button is an EditBox with its own label AND a status line under it,
-- which is where the library writes a refusal ("no spell named ...").
--
-- THE BAND GROWS RATHER THAN THE CONTROL MOVING, and that is options-ui-14's call, not a
-- preference: "Controls that apply to every tab MUST sit in that band too, above the strip --
-- never in the scroll below it", and the band "MUST carry the identity controls -- the picker,
-- and the create control where the page has one". Adding a spell is this page's create control.
--
-- The cost is real and is the one that section warns about: every row below moves down by the
-- difference, permanently, for a control a player touches occasionally. It is paid because the
-- alternative the section names -- moving page-wide acts to a `General` first tab -- is for the
-- ACTS (rename, copy, reset, delete), and explicitly not for the picker and the create control.
local HEADER_BLOCK_H = 72

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

local function validateSpellInput(input)
    if not input or input == "" then return nil end
    local id = tonumber(input)
    if id then
        local name = getSpellName(id)
        if name then return id, name end
        return nil
    end
    if Compat.GetSpellInfo then
        local name, _, _, _, _, resolvedID = Compat.GetSpellInfo(input)
        if name and resolvedID then return resolvedID, name end
    end
    return nil
end

-- Build the set of spellIDs the Blizzard Cooldown Manager would surface for
-- the currently selected (class, spec). Walks every CooldownViewerCategory
-- enum value and unions the spellIDs they expose. Returns nil when the API
-- is unavailable (older clients) so callers can fall back to lenient
-- validation.
--
-- Memoized in `_cmCache` because the walk is non-trivial (every enum value
-- × every cdID) and the result is stable for the lifetime of a (login ×
-- spec). Invalidated by the bootstrap below on TRAIT_CONFIG_UPDATED and
-- PLAYER_SPECIALIZATION_CHANGED. Stored as a marker table even when the
-- API returned no useful data, so the next call doesn't re-walk for
-- nothing — a sentinel field distinguishes "computed, set was empty"
-- from "not computed yet."
local _cmCache         -- { set | EMPTY_SENTINEL } once populated; nil otherwise
local _CM_EMPTY = {}   -- sentinel: API returned no data; don't recompute

-- The two C_CooldownViewer entry points the walk needs, or nil when this client
-- can't answer. Older clients have no C_CooldownViewer at all, and the Enum the
-- category walk iterates arrived with it.
local function cooldownViewerApi()
    if not C_CooldownViewer then return nil end
    local getCategorySet = C_CooldownViewer.GetCooldownViewerCategorySet
    local getInfo        = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not (getCategorySet and getInfo and Enum and Enum.CooldownViewerCategory) then
        return nil
    end
    return getCategorySet, getInfo
end

-- Union one category's spellIDs into `set`; returns whether it contributed any.
-- Both pcalls are load-bearing: C_CooldownViewer throws on some category values
-- in some client builds, and one bad category must not abort the whole walk.
local function collectCategorySpells(getCategorySet, getInfo, category, set)
    local ok, ids = pcall(getCategorySet, category)
    if not (ok and type(ids) == "table") then return false end
    local added = false
    for _, cdID in ipairs(ids) do
        local ok2, info = pcall(getInfo, cdID)
        if ok2 and type(info) == "table" and info.spellID then
            set[info.spellID] = true
            added = true
        end
    end
    return added
end

local function getCooldownManagerSpellSet()
    if _cmCache == _CM_EMPTY then return nil end
    if _cmCache then return _cmCache end

    local getCategorySet, getInfo = cooldownViewerApi()
    if not getCategorySet then
        _cmCache = _CM_EMPTY
        return nil
    end

    local set = {}
    local seenAny = false
    for _, category in pairs(Enum.CooldownViewerCategory) do
        -- Deliberately NOT `seenAny = seenAny or collect(...)`: that
        -- short-circuits and stops walking once anything has been found.
        if collectCategorySpells(getCategorySet, getInfo, category, set) then
            seenAny = true
        end
    end

    if not seenAny then
        _cmCache = _CM_EMPTY
        return nil
    end
    _cmCache = set
    return set
end

-- Invalidate the cooldown-manager spell-set cache. Triggered on talent
-- swaps and spec changes — both events flip the C_CooldownViewer
-- contents, so a cached set from before the event is stale by the time
-- the panel reopens.
local function invalidateCmCache()
    _cmCache = nil
end

-- Bootstrap: a private frame owns the cache-invalidation events. Kept
-- at module scope (rather than inside ensurePanel) so the cache stays
-- correct even when the user never opens the Spells panel — we don't
-- want a panel-open after a spec change to read stale data because the
-- listener was lazy-registered.
local cacheEvents = CreateFrame("Frame")
cacheEvents:SetScript("OnEvent", invalidateCmCache)

--- Arm the cache invalidator. Split out of the bootstrap so the stand-down can
--- release it and the stand-up can put it back (slash-commands-§7).
local function armCacheEvents()
    cacheEvents:RegisterEvent("TRAIT_CONFIG_UPDATED")
    cacheEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

armCacheEvents()

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

local function doCommit()
    if panel and panel:IsShown() then Spells:RefreshRows() end
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
-- is DROPPED and the add falls through to the lenient validateSpellInput path
-- (which already confirmed the spell exists in the spell DB).
local function editorIsActiveSpec()
    local playerClass  = playerClassFile()
    local playerSpecID = NS.Util.PlayerSpecID()
    if playerClass and selectedClass and playerClass == selectedClass
       and playerSpecID and selectedSpec and playerSpecID == selectedSpec then
        return true
    end
    if NS.State and NS.State.debug then
        NS.Debug("Spells", ("Editing %s/%s ≠ player %s/%s; skipping cooldown-manager gate.")
            :format(tostring(selectedClass), NS.Util.SpecDisplay(selectedSpec),
                    tostring(playerClass), NS.Util.SpecDisplay(playerSpecID)))
    end
    return false
end

-- True when the Blizzard Cooldown Manager does not track this spell for the
-- player's active spec, so the add should be refused. An UNAVAILABLE API is
-- lenient by design: no set means no opinion, never a rejection.
local function cooldownManagerRejects(id, resolvedName)
    local cmSet = getCooldownManagerSpellSet()
    if not cmSet then
        if NS.State and NS.State.debug then
            NS.Debug("Spells", "C_CooldownViewer unavailable; skipping cooldown-manager validation for spell " .. tostring(id))
        end
        return false
    end
    if cmSet[id] then return false end
    local name = resolvedName or getSpellName(id) or tostring(id)
    notify(("Spell %s (#%d) is not tracked by the Blizzard Cooldown Manager for this specialization."):format(name, id))
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
    local cmSet = getCooldownManagerSpellSet()
    if not cmSet or cmSet[id] then return nil end
    return "|cffff8000" .. L["not tracked"] .. "|r"
end

--- The add box's accept path: the same two steps the StaticPopup ran, minus the parsing the
--- library now owns.
---
--- The library has already resolved a name, a link or an id to a NUMBER by the time this is
--- called, so `validateSpellInput` has nothing left to do -- what stays is this addon's own
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

-- Builds a row action button (Move up / Move down / Remove) as an AceGUI Icon
-- widget so the row matches ConsumableMaster's iconography rather than the
-- old "Up" / "Dn" / "X" text labels. opts.image is a texture path; opts.atlas
-- swaps in a Blizzard atlas via the inner texture's SetAtlas — needed for
-- transmog-icon-remove (the red "no entry" glyph) which has no plain path.
local function makeRowIconBtn(AceGUI, opts)
    local btn = AceGUI:Create("Icon")
    btn:SetImageSize(22, 22)
    btn:SetWidth(30)
    btn:SetHeight(26)
    if opts.atlas and btn.image and btn.image.SetAtlas then
        btn.image:SetAtlas(opts.atlas)
    elseif opts.image then
        btn:SetImage(opts.image)
    end
    if opts.disabled then
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(true) end
            if btn.image.SetVertexColor then btn.image:SetVertexColor(0.45, 0.45, 0.45) end
        end
    else
        if btn.image then
            if btn.image.SetDesaturated then btn.image:SetDesaturated(false) end
            if btn.image.SetVertexColor then btn.image:SetVertexColor(1, 1, 1) end
        end
        btn:SetCallback("OnClick", opts.onClick)
    end
    if opts.tooltip then
        btn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip)
            GameTooltip:Show()
        end)
        btn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

-- One builder per row widget, below. buildRow itself then reads as the column
-- order it renders — and AddChild ORDER *is* that column order, spacer
-- included, so the sequence of calls at the bottom is the layout.

-- The spell icon, plus the two tooltip closures the name label reuses so
-- hovering either one shows the same spell tooltip.
local function rowSpellIcon(AceGUI, entry)
    local icon = AceGUI:Create("Icon")
    icon:SetImage(getSpellIcon(entry.spellID) or 134400)
    icon:SetImageSize(20, 20)
    icon:SetWidth(28)
    icon:SetHeight(24)
    icon:SetCallback("OnClick", function() end)
    if icon.image and icon.image.SetDesaturated then
        icon.image:SetDesaturated(entry.enabled == false)
    end
    local function showSpellTooltip(widget)
        if not entry.spellID then return end
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(entry.spellID)
        GameTooltip:Show()
    end
    local function hideSpellTooltip() GameTooltip:Hide() end
    icon:SetCallback("OnEnter", showSpellTooltip)
    icon:SetCallback("OnLeave", hideSpellTooltip)
    return icon, showSpellTooltip, hideSpellTooltip
end

local function rowNameLabel(AceGUI, entry, showSpellTooltip, hideSpellTooltip)
    local label = AceGUI:Create("Label")
    local name = getSpellName(entry.spellID) or ("#" .. tostring(entry.spellID))
    label:SetText(name)
    -- Was 190 (trimmed from 220 to make room for the known/unknown
    -- status glyph). Bumped 25% to 238 to take advantage of the empty
    -- space on the right of each row — long spell names like
    -- "Counterspell" or "Shockwave (talented)" no longer truncate.
    label:SetWidth(238)
    if label.frame and label.frame.HookScript then
        label.frame:EnableMouse(true)
        label.frame:HookScript("OnEnter", function() showSpellTooltip(label) end)
        label.frame:HookScript("OnLeave", hideSpellTooltip)
    end
    return label
end

-- The enable checkbox. It desaturates the icon it was handed, which is why the
-- icon has to be built first.
local function rowEnableCheck(AceGUI, entry, icon)
    local check = AceGUI:Create("CheckBox")
    check:SetLabel("")
    check:SetValue(entry.enabled ~= false)
    check:SetWidth(40)
    check:SetCallback("OnValueChanged", function(_, _, value)
        writer("SetSpellEnabled", entry.spellID, value)
        if icon.image and icon.image.SetDesaturated then
            icon.image:SetDesaturated(not value)
        end
        commitSoon()
    end)
    return check
end

-- "Known to the player?" status glyph. Reads Compat.IsSpellAvailable
-- (the same predicate IconGrid:BuildActiveList and Cooldowns:PollSpell
-- use to decide whether to render the spell), so the green check ↔
-- red X toggle is the user-facing reflection of "this row will / will
-- not appear on the icon grid right now."
--
-- The check is global to the logged-in player, not scoped to the
-- selected (class, spec) in the dropdown — so when the user is
-- browsing another class's spec list, every spell will read as red,
-- which is the correct fact ("you can't cast any of these"). The
-- glyph is informational only; it doesn't gate enable/disable.
local function rowKnownGlyph(AceGUI, entry)
    local known = Compat.IsSpellAvailable
        and Compat.IsSpellAvailable(entry.spellID) or false
    local statusIcon = AceGUI:Create("Icon")
    statusIcon:SetImage(known and SPELL_KNOWN_ICON or SPELL_NOT_KNOWN_ICON)
    statusIcon:SetImageSize(20, 20)
    -- Box width hugs the 20 px image (1 px padding each side instead of 4).
    -- AceGUI's Icon widget anchors the texture to TOP center, so a narrower
    -- box pulls the visible glyph closer to the checkbox on its left —
    -- which is the "reduce spacing before the icon" half of the request.
    statusIcon:SetWidth(22)
    statusIcon:SetHeight(24)
    -- No OnClick — the glyph is purely informational. AceGUI's Icon
    -- still renders a clickable region without a callback, but the
    -- click is a no-op which matches what we want.
    local statusTooltip = known and L["Spell known"] or L["Spell not known"]
    statusIcon:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(statusTooltip)
        GameTooltip:Show()
    end)
    statusIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    return statusIcon
end

-- Empty-text Label as a fixed-width spacer — the "increase spacing after
-- the icon" half. AceGUI's Flow layout has no inter-widget gap of its
-- own, so the canonical way to inject horizontal whitespace between two
-- adjacent widgets is an invisible filler. Width covers the lost
-- padding from the narrowed icon box plus the requested extra gap
-- before the category dropdown.
local function rowSpacer(AceGUI, width)
    local spacer = AceGUI:Create("Label")
    spacer:SetText("")
    spacer:SetWidth(width)
    return spacer
end

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

local function rowCategoryDropdown(AceGUI, entry)
    local dd = AceGUI:Create("Dropdown")
    dd:SetList(categoryList())
    dd:SetValue(entry.category or "other")
    dd:SetWidth(120)
    dd:SetCallback("OnValueChanged", function(_, _, value)
        if writer("SetSpellCategory", entry.spellID, value) then commitSoon() end
    end)
    if dd.frame and dd.frame.HookScript then
        dd.frame:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Category for future filtering. Currently informational only."])
            GameTooltip:Show()
        end)
        dd.frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return dd
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

local function rowRemoveButton(AceGUI, list, index)
    return makeRowIconBtn(AceGUI, {
        atlas   = "transmog-icon-remove",
        tooltip = L["Remove"],
        -- By the spellID the row showed, read at click time. `index` is only
        -- valid until the next rebuild, so a stale click past the end of a list
        -- that has since shrunk reads nil and removes nothing.
        onClick = function()
            local removedId = list[index] and list[index].spellID
            if writer("RemoveSpell", removedId) then commitSoon() end
        end,
    })
end

-- Every row in this list is the SAME height, and that is a requirement rather
-- than a tidy coincidence: ReorderList computes the drop position as arithmetic
-- on the stride, never as a hit test, so a list of unequal rows drops in the
-- wrong place (options-ui-§18).
local ROW_HEIGHT = 28

local function buildRow(AceGUI, list, index)
    local entry = list[index]
    if not entry then return end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(ROW_HEIGHT)

    -- The drag handle owns a fixed gutter at the row's FAR LEFT and the row's
    -- contents start beyond it (options-ui-§8's `handle gutter`). The width is
    -- read off the library rather than restated, for the reason every layout
    -- constant is: a host copy is the copy that goes stale.
    local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
    row:AddChild(rowSpacer(AceGUI, (W and W.ROW_BOX and W.ROW_BOX.HANDLE_W) or 30))

    local icon, showSpellTooltip, hideSpellTooltip = rowSpellIcon(AceGUI, entry)
    row:AddChild(icon)
    row:AddChild(rowNameLabel(AceGUI, entry, showSpellTooltip, hideSpellTooltip))
    row:AddChild(rowEnableCheck(AceGUI, entry, icon))
    row:AddChild(rowKnownGlyph(AceGUI, entry))
    row:AddChild(rowSpacer(AceGUI, 14))
    row:AddChild(rowCategoryDropdown(AceGUI, entry))
    row:AddChild(rowRemoveButton(AceGUI, list, index))

    return row
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

-- Title-cases a SCREAMING_TOKEN like "DEATHKNIGHT" or "BLOOD" into "Deathknight"
-- / "Blood". Splits compound class tokens that appear glued together
-- ("DEATHKNIGHT" -> "Death Knight", "DEMONHUNTER" -> "Demon Hunter") so the
-- merged dropdown reads naturally.
local CLASS_DISPLAY_OVERRIDES = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
}

local function titleCaseToken(token)
    if not token then return "" end
    local s = token:lower():gsub("^%l", string.upper)
    return s
end

local function classDisplayName(classFile)
    if CLASS_DISPLAY_OVERRIDES[classFile] then return CLASS_DISPLAY_OVERRIDES[classFile] end
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] then
        return LOCALIZED_CLASS_NAMES_MALE[classFile]
    end
    return titleCaseToken(classFile)
end

local function classColorHex(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return "ffffffff" end
    if c.colorStr then return c.colorStr end
    return ("ff%02x%02x%02x"):format(
        math.floor((c.r or 1) * 255 + 0.5),
        math.floor((c.g or 1) * 255 + 0.5),
        math.floor((c.b or 1) * 255 + 0.5))
end

local function classIconMarkup(classFile)
    if CreateAtlasMarkup then
        local atlas = "classicon-" .. classFile:lower()
        local ok, markup = pcall(CreateAtlasMarkup, atlas, 16, 16)
        if ok and markup then return markup end
    end
    return ("|TInterface\\Icons\\ClassIcon_%s:16:16:0:0|t"):format(classFile:lower())
end

-- [classFile] = { [specID] = iconFileID }. Built lazily from
-- GetSpecializationInfoForClassID, which hands back the specID directly --
-- no name round-trip, so nothing here depends on the client's locale.
local specIconCache

local function buildSpecIconCache()
    local cache = {}
    if not (GetNumClasses and GetClassInfo
            and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID) then
        return cache
    end
    for classID = 1, GetNumClasses() do
        local _, classFile = GetClassInfo(classID)
        if classFile then
            cache[classFile] = {}
            local nSpecs = GetNumSpecializationsForClassID(classID) or 0
            for i = 1, nSpecs do
                local specID, _, _, icon = GetSpecializationInfoForClassID(classID, i)
                if specID and icon then
                    cache[classFile][specID] = icon
                end
            end
        end
    end
    return cache
end

local function specIconMarkup(classFile, specID)
    if not specIconCache then specIconCache = buildSpecIconCache() end
    local byClass = specIconCache[classFile]
    local icon = byClass and byClass[specID]
    if icon then
        return ("|T%s:16:16:0:0|t"):format(tostring(icon))
    end
    return ""
end

local function buildSpecEntries()
    local entries = {}
    if type(NS.DefaultSpells) ~= "table" then return entries end

    local classOrder = sortedKeys(NS.DefaultSpells)
    for _, classFile in ipairs(classOrder) do
        local hex       = classColorHex(classFile)
        local cIcon     = classIconMarkup(classFile)
        local className = classDisplayName(classFile)
        for _, specID in ipairs(specOrder(classFile)) do
            -- The dropdown VALUE carries the numeric specID (locale-free);
            -- the LABEL is the spec's name in the player's own language, so
            -- a French user reads "Élémentaire" while the key stays 262.
            local specName = NS.Util.SpecDisplayName(specID)
            local sIcon    = specIconMarkup(classFile, specID)
            local label    = ("%s %s |c%s%s %s|r"):format(cIcon, sIcon, hex, className, specName)
            entries[#entries + 1] = {
                value     = classFile .. "/" .. specID,
                label     = label,
                classFile = classFile,
                specID    = specID,
            }
        end
    end
    return entries
end

--- The page-wide chrome block's contents: which spec is being edited, and the
--- act of adding a spell to it (options-ui-§14).
---
--- IT IS DRAWN ABOVE THE STRIP, not in the scroll, and that is the rule rather
--- than a preference: choosing which thing the page edits and creating a new one
--- both apply to every tab, so a control for either that sits under one tab
--- reads as belonging to that tab and vanishes the moment the reader clicks a
--- different one. `parent` is the frame H.PageHeader hands over; the block owns
--- everything inside it and the library owns the band it occupies.
local function buildSpellsHeader(AceGUI, headerCtx, parent)
    local H = NS.Settings and NS.Settings.Helpers
    headerWidgets = {}

    local entries = buildSpecEntries()
    local items, order = {}, {}
    for i, e in ipairs(entries) do
        items[e.value] = e.label
        order[i]       = e.value
    end

    local specDD = AceGUI:Create("Dropdown")
    specDD:SetLabel(L["Specialization"])
    specDD:SetList(items, order)
    if selectedClass and selectedSpec then
        specDD:SetValue(selectedClass .. "/" .. selectedSpec)
    end
    specDD:SetWidth(280)
    specDD:SetCallback("OnValueChanged", function(_, _, value)
        local classFile, specID = value:match("^([^/]+)/(%d+)$")
        if classFile and specID then
            selectedClass = classFile
            selectedSpec  = tonumber(specID)
            Spells:RefreshRows()
        end
    end)
    specDD.frame:SetParent(parent)
    specDD.frame:ClearAllPoints()
    specDD.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    specDD.frame:Show()
    headerWidgets[#headerWidgets + 1] = specDD

    -- THE LIBRARY'S ADD CONTROL, where a Button and a StaticPopup used to be. What the popup
    -- could not do, and this does: resolve a typed NAME through the client, take a shift-clicked
    -- spell link, suggest as the player types (the spellbook, plus the ids this spec already
    -- lists), tell two spells of one name apart by rank, and answer a bad entry on a status line
    -- under the box instead of a chat line behind the dialog.
    --
    -- IT NEEDS AN AceGUI CONTAINER, because O.IdInput ends in `parent:AddChild(group)` -- the
    -- band hands over a raw frame, so a SimpleGroup bridges the two. Anchored LEFT..RIGHT so the
    -- box takes whatever the picker leaves, rather than a fixed width that would be wrong at two
    -- canvas widths.
    local addHost = AceGUI:Create("SimpleGroup")
    addHost:SetLayout("Flow")
    addHost.frame:SetParent(parent)
    addHost.frame:ClearAllPoints()
    -- Anchor LEFT…RIGHT against specDD.dropdown (the inner UIDropDownMenu
    -- frame) instead of specDD.frame (the outer AceGUI frame that
    -- includes the "Specialization" label above the dropdown control).
    -- The outer frame is 40 px tall when labeled (label 18 + dropdown
    -- 26) so a vertical-center anchor against it landed the button on
    -- the seam between the two — visually misaligned. Anchoring against
    -- the inner dropdown puts the button's vertical center on the
    -- dropdown control itself, ignoring the label. The -5 X offset
    -- restores the original ~12 px gap from the frame's right edge:
    -- the inner dropdown extends +17 px past the outer frame's right
    -- (decorative texture overhang), so -5 nets back to +12.
    addHost.frame:SetPoint("TOPLEFT", specDD.dropdown, "TOPRIGHT", -5, 0)
    addHost.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    addHost.frame:Show()
    headerWidgets[#headerWidgets + 1] = addHost

    H.IdInput(headerCtx, addHost, {
        -- THE LIBRARY'S OWN SPELL KIND, by name rather than a host table. A named kind needs no
        -- `base` because it IS the base: it comes with the spellbook as its suggestion source, the
        -- rank rows that tell two spells of one name apart, the client tooltip, and the name
        -- lookup. A host table would have to declare `base = "spell"` to get any of that back, and
        -- this page needs nothing a host table is for.
        kind       = "spell",
        -- WARN BEFORE THE CLICK. The Cooldown Manager refusal below fires at the ADD, in chat --
        -- correct, but after the player has chosen. This marks the row while they are still
        -- choosing. It works here precisely because the spells in question ARE in the spellbook,
        -- so they appear as suggestions; the same tag on a page whose ids are typed as digits
        -- would cover almost nothing.
        suggestTag = Spells.SuggestTag,
        label      = L["Add a spell"],
        tooltip    = L["Type a spell id or a name and pick from the list, or shift-click a spell link into the box, then press Enter or Add."],
        strings    = ADD_STRINGS,
        -- What this spec already lists, so a player retyping a spell they disabled sees it
        -- offered rather than hunting the id. The spellbook comes with `kind = "spell"` and is
        -- not repeated here.
        candidates = currentSpellIds,
        onAdd      = addFromBox,
    })
end

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
local function fillRows(AceGUI, scroll, list)
    if not list or #list == 0 then
        local lbl = AceGUI:Create("Label")
        -- Names the control that is actually there. It read "Click Add spell..." until the
        -- button became the band's add box, which would have sent a player looking for a button.
        lbl:SetText(L["No spells tracked. Type one into Add a spell above, or press Defaults."])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
    if W and W.ReorderList then
        reorder = W.ReorderList{
            -- Uniform rows, so the stride IS the row height: AceGUI's List
            -- layout stacks children with no gap of its own.
            stride        = ROW_HEIGHT,
            -- No `boundary`: one flat priority list, with no section a drag
            -- must not cross.
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

    for i = 1, #list do
        local row = buildRow(AceGUI, list, i)
        if row then
            -- AddChild FIRST: the handle and the box are parented to the row
            -- frame, and it has no parent of its own until the scroll takes it.
            scroll:AddChild(row)
            if reorder then
                reorder:AddRow(row.frame, {
                    ghostText = getSpellName(list[i].spellID)
                                or ("#" .. tostring(list[i].spellID)),
                })
            end
        end
    end
    if reorder then reorder:Finish(scroll.content or scroll.frame) end
end

function Spells:RefreshRows()
    if not panel or not panel:IsShown() then return end
    if rebuildScheduled then return end
    rebuildScheduled = true

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then
        -- The flag is cleared on EVERY exit, this one included: leave it set
        -- and the panel silently never refreshes again for the rest of the
        -- session.
        rebuildScheduled = false
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
        build  = function(headerCtx, frame) buildSpellsHeader(AceGUI, headerCtx, frame) end,
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
        rebuildScheduled = false
        showAceGUIMissing()
        return
    end
    fillRows(AceGUI, container, getActiveList())
    if container.DoLayout then container:DoLayout() end

    rebuildScheduled = false
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
        ev:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", function()
            if panel and panel:IsShown() then Spells:RefreshRows() end
        end)
        -- Slash-command mutations (`/kcd spells add/remove/...`) and the
        -- panel's own commitSoon both fire Ka0s_KickCD_CONFIG_CHANGED with
        -- section="spells". Subscribing here is what closes the bus
        -- contract — the slash layer no longer reaches across to call
        -- our RefreshRows directly (CR-7).
        ev:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED", function(_, payload)
            if payload and payload.section == "spells"
               and panel and panel:IsShown() then
                Spells:RefreshRows()
            end
        end)

        -- Talent / spellbook changes flip the per-row known/unknown glyph.
        -- Refresh while the panel is open so the indicators stay in sync
        -- with what IconGrid is rendering.
        local function refreshIfShown()
            if panel and panel:IsShown() then Spells:RefreshRows() end
        end
        ev:RegisterEvent("SPELLS_CHANGED",       refreshIfShown)
        ev:RegisterEvent("TRAIT_CONFIG_UPDATED", refreshIfShown)

        -- Spec swaps move the SELECTION, not just the rows — see
        -- Spells:OnPlayerSpecChanged. The event fires for any unit, so filter
        -- to the player before re-seeding.
        ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
            if unit and unit ~= "player" then return end
            Spells:OnPlayerSpecChanged()
        end)
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
-- worth stating because both halves are in §7. What survives is the settings
-- registration and the panel BODY: a disabled addon stays in Blizzard's AddOns
-- tree, this page still opens, still draws every row, and still writes every
-- edit -- which is the whole reason the disabled slash surface keeps `get`,
-- `set` and `/kcd spells`. What does not survive is a REGISTRATION: these five
-- exist to react to GAME events (a spec swap, a talent change) and §7's
-- "actually UNREGISTERED" is unqualified. A handler that early-returns on
-- `panel:IsShown()` is the draw gate in miniature -- the addon did not stop
-- watching, it stopped reacting, and the client still walks the list.
--
-- The cost is precisely one thing: a spec change made WHILE the addon is off and
-- WHILE this page is open does not re-render the rows under the player's cursor.
-- Reopening the page does, because the cache is invalidated on the way back up.
--
-- `commitSoon` is deliberately NOT canceled here. It is armed by the player
-- typing in this editor, never by a game event, and a stand-down that threw away
-- an edit in flight would lose data the player just entered -- "no SavedVariables
-- write FROM A GAME EVENT" does not reach a write the player is in the middle of
-- making.

--- Release the page's game-event subscriptions. Called by the latch's standDown.
function Spells.StandDown()
    cacheEvents:UnregisterAllEvents()
    local ev = Spells.__ev
    if ev then
        if ev.UnregisterAllEvents   then ev:UnregisterAllEvents()   end
        if ev.UnregisterAllMessages then ev:UnregisterAllMessages() end
    end
end

--- Re-arm them, and drop the cooldown-manager cache on the way: the spec or the
--- talent build can have changed while nothing was listening, so the next panel
--- open must read the client rather than a set cached before the addon went down.
function Spells.StandUp()
    _cmCache = nil
    armCacheEvents()
    Spells.RegisterPanelEvents()
end

Spells.ValidateSpellInput = validateSpellInput
Spells.SpecOrder          = specOrder
Spells.SortedKeys         = sortedKeys
Spells.TitleCaseToken     = titleCaseToken
Spells.ClassDisplayName   = classDisplayName
