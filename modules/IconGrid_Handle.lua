-- modules/IconGrid_Handle.lua — the icon grid's drag strip and ApplyLock (peeled from IconGrid.lua, #25)
--
-- LibKa0s-Widgets-1.0's DragHandle wearing this addon's strings and callbacks,
-- mirroring modules/Castbar_Handle.lua: the library resolution, the strip's
-- label (handleText), where it hangs (anchorHandle), the build (buildHandle,
-- published as IconGrid._BuildHandle for EnsureGrid) and IconGrid:ApplyLock,
-- which registers and clears the drag and shows and hides the strip together.
-- A pure move, for layout-§1's cap.
--
-- The save path stays in IconGrid.lua: onDragStop is the grid frame's own
-- OnDragStop script as well as the strip's, so it is published there as
-- IconGrid._OnDragStop and read here at file load. IconGrid.lua loads first
-- (KickCD.toc's LOAD-BEARING note).

local _, NS = ...
local IconGrid = NS:GetModule("IconGrid")
local onDragStop = IconGrid._OnDragStop

-- ---------------------------------------------------------------------------
-- The drag strip
-- ---------------------------------------------------------------------------
--
-- UNTIL NOW AN UNLOCKED GRID LOOKED EXACTLY LIKE A LOCKED ONE. ApplyLock below flips EnableMouse
-- and RegisterForDrag on the grid frame itself and nothing on screen says so: the grab target is
-- whatever icons happen to be laid out, which with a one-spell list is a single 48px square and
-- with an EMPTY list is nothing at all. That last case is why Layout keeps an empty grid visible at
-- primary-icon size in the first place -- "a small invisible square", :454-457 -- a wart written
-- down as a wart because losing the only grab target was the worse of the two.
--
-- THE STRIP IS THE LIBRARY'S, NOT OURS. libs/LibKa0s/WidgetsDragHandle.lua (minor 4 vendored) ships the dark
-- fill, the 1px gold edge, the centered gold label, the help mark with its own art fallback and
-- resting tint, the tooltip bands, the drag scripts and the width arithmetic. AuraMaster
-- (modules/Anchors.lua) and ConsumableMaster (modules/MacroBar.lua) had each drawn that same widget
-- by hand, which is the argument it was published under; this file writing a third copy would have
-- been the argument again.
--
-- Resolved at file load like every other library seam in this addon. ABSENT, buildHandle answers
-- nil, inst.handle stays nil, and every use of it below is guarded -- so a degraded install loses
-- the affordance and nothing else: the grid is still SetMovable(true) (:597), still registers for
-- drag while unlocked, and still saves through IconGrid.lua's onDragStop. That is why this seam needs no
-- stub-parity case: there is no stub, because there is nothing to degrade TO.
local KW   = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
local DRAG = KW and KW.DRAG_HANDLE

--- The strip's label: this addon, then which grid the strip moves.
---
--- THE UNIT HAS TO BE IN THE TEXT. Both instances draw the same 18px gold-on-black strip and both
--- are on screen at once whenever Focus is enabled, so a strip that said only the addon's name
--- would leave the player guessing which of two identical strips moves which grid. The unit is
--- spelled the way the options panel already spells it -- settings/Panel_Render.lua:109's
--- `(u == "target") and L["Target"] or L["Focus"]` -- rather than a second wording of the same two
--- words, and the title is the key the TOC's `## Title` already carries (locales/enUS.lua).
---
--- READ AT CALL TIME, not captured at file load: locales/enUS.lua loads before this file per the
--- TOC, but a module that reaches through NS for its strings costs nothing and cannot be wrong.
local function handleText(unit)
    local L = NS.L
    return ("%s — %s"):format(L["Ka0s KickCD"], (unit == "target") and L["Target"] or L["Focus"])
end

--- Build the strip the player drags THIS unit's grid by, or nil without LibKa0s-Widgets-1.0.
---
--- PARENTED TO THE GRID, ANCHORED OUTSIDE IT. The grid frame's rect is exactly the visible icons'
--- bounding box (docs/icon-grid.md, "Visible-count sizing"), so a strip drawn OVER it would cover
--- the primary icon -- the same reason AuraMaster puts its handle outside its anchor. It sits
--- DRAG.GAP above the top edge instead and nothing inside the grid moves to make room. Parenting is
--- what makes it inherit the grid's master scale and alpha for free (ApplyGeneral's SetScale /
--- SetAlpha, :531-532) and hide with it when DisableUnit hides the grid, so there is nothing for
--- teardown to do. The point is set ONCE here because it never changes; ApplyLock only sizes and
--- shows.
---
--- THE MOVED FRAME IS THE GRID, AND THE SAVE PATH IS THE ONE THAT ALREADY EXISTS. onDragStop
--- persists the anchor and fires the `general` config message; routing the strip through it rather
--- than through a second copy is the whole point. The widget has already called
--- StopMovingOrSizing by the time it calls onDragStop, so that function's own call is a second one
--- on a frame that is no longer moving -- which the client treats as a no-op. One save path is
--- worth more than one saved line.
---
--- `canDrag` REPEATS THE LOCK CHECK onDragStart makes (:540) even though ApplyLock hides the strip
--- while locked. The widget asks on every OnDragStart, and the guard is what keeps a locked grid
--- immovable on a path nobody has written yet -- a strip left shown by some future caller must
--- still move nothing. It deliberately does NOT add a combat gate: the grid is a plain frame on
--- UIParent (:592) and dragging it in combat works today, so adding one here would be a behavior
--- change smuggled in under a widget adoption.
---
--- NO `number` GUARD AND NO `edge` PAINTER, because this addon needs neither. Both exist for
--- AuraMaster, whose anchor inherits DisableUntrustedLayoutScriptsTemplate and can therefore answer
--- a secret width and refuse a Backdrop's arithmetic. The grid is an ordinary CreateFrame("Frame",
--- frameName, UIParent) with no template, so the widget's own `tonumber` fallback and its own four
--- 1px strips are the right defaults rather than a gap.
---
--- THE TOOLTIP SITS BESIDE THE STRIP (TP-KC-01, LibKa0s v1.68.0), the same placement as the cast
--- bar's strip: `tooltipPlace` is NS.Util.PlaceTooltipBeside -- right of the strip, or left of it
--- when that would leave the screen. Above the strip (the old ANCHOR_TOP owner) is where the unit
--- label and the Focus grid stack, so a tooltip opening upward covered them.
--- @return table|nil
--- Hang the strip above the unit LABEL when there is one above this grid, else above the
--- grid itself.
---
--- The strip's natural home is the grid's TOP edge -- and so is the label's, by default, so
--- the two drew on top of each other (owner, in the client, 2026-09-21). The label is the
--- thing a player reads to tell two grids apart, so the strip is what moves.
---
--- UnitLabel answers whether its frame is up there, because the label's attach point, its
--- link-resolved show and its anchor point are all its own config to resolve -- see
--- UnitLabel:FrameAbove, which also says why that answer is read off the CONFIG rather
--- than off the frame's shown state. A nil answer, a UnitLabel module that is not loaded, or
--- a label parked on the cast bar all leave the strip exactly where it was before any of
--- this: BOTTOM to the grid's TOP, one DRAG.GAP clear.
---
--- What comes back is the label's FONTSTRING, not its frame -- the frame is 1x1 with the text
--- centered on it, so its TOP is the middle of the label. See UnitLabel:FrameAbove.
---
--- Re-run on every ApplyLock rather than only at build, because the label can be turned on,
--- moved to the cast bar or re-anchored long after the strip was made, and ApplyLock is
--- already the path every one of those config changes reaches this module through.
local function anchorHandle(inst, grid, handle)
    handle = handle or inst.handle
    if not handle then return end
    local lbl = NS:GetModule("UnitLabel", true)
    local above = lbl and lbl.FrameAbove and lbl:FrameAbove(inst.unit, "icons") or nil
    handle:ClearAllPoints()
    handle:SetPoint("BOTTOM", above or grid, "TOP", 0, DRAG.GAP)
    -- What it was anchored TO, for a harness whose fake frame records no points -- the same
    -- reason the widget records `__label`. A test can read the decision without a real UI.
    handle.__anchorTo = above or grid
end

local function buildHandle(inst, grid)
    if not (KW and KW.DragHandle) then return nil end
    local label = handleText(inst.unit)
    local handle = KW.DragHandle(grid, {
        label        = label,
        moveFrame    = grid,
        helpIcon     = NS.Icon and NS.Icon("help") or nil,
        canDrag      = function()
            return not (NS.db and NS.db.profile and NS.db.profile.locked)
        end,
        onDragStop   = function() onDragStop(inst, grid) end,
        onRightClick = function() NS:OpenSettings() end,
        tooltipPlace = NS.Util.PlaceTooltipBeside,
        tooltip      = {
            title = label,
            body  = { NS.L["Drag to move. Right-click for settings."] },
        },
    })
    if not handle then return nil end
    anchorHandle(inst, grid, handle)
    return handle
end

function IconGrid:ApplyLock(inst)
    local grid = inst.grid
    if not grid then return end
    local profile  = NS.db and NS.db.profile
    local locked   = profile and profile.locked
    inst.cfg = NS.Units.Icons(inst.unit)
    local showTip  = inst.cfg and inst.cfg.showTooltip
    if locked then
        grid:RegisterForDrag()        -- clear all drag buttons
        grid:EnableMouse(false)
        -- SHOWN AND HIDDEN BY THE CALL THAT REGISTERS AND CLEARS THE DRAG, never anywhere else.
        -- A strip left up permanently would be advertising a drag the frame above has just
        -- refused; the two lines have to be the same two lines or they will drift apart.
        if inst.handle then inst.handle:Hide() end
    else
        grid:EnableMouse(true)
        grid:RegisterForDrag("LeftButton")
        -- The widget never places, sizes or shows the strip of its own accord -- see "WHAT THE HOST
        -- STILL OWNS" at the top of libs/LibKa0s/WidgetsDragHandle.lua. It is born hidden with no
        -- width, on purpose, so it cannot flash a zero-width box at its parent's center; this is
        -- the host saying when.
        --
        -- FLOORED AT ZERO, i.e. the label's own natural width, and NOT at the grid's. The tempting
        -- version is ApplyWidth(grid:GetWidth()), so the strip spans the frame it moves -- but
        -- EnableUnit runs EnsureGrid (where the grid is still the 48x48 of :594) before
        -- BuildActiveList and Layout, and never returns here afterwards; the "spells" branch of
        -- OnConfigChanged rebuilds and re-lays-out without calling ApplyLock at all. A grid-floored
        -- width would therefore be stale on both paths, and closing them means touching two more
        -- call sites for a cosmetic gain. A width that depends only on a label that never changes
        -- after birth cannot go stale, which is the property worth having here.
        if inst.handle then
            -- RE-ANCHORED ON EVERY UNLOCK, not only at build. The unit label can be turned on,
            -- moved between the grid and the cast bar, or re-anchored long after the strip was
            -- made, and every one of those config changes reaches this module through ApplyLock.
            -- Re-asking is cheap -- one config read and one SetPoint -- and it is the difference
            -- between a strip that clears the label and one that sits on top of it.
            anchorHandle(inst, grid, inst.handle)
            inst.handle:ApplyWidth(0)
            inst.handle:Show()
        end
    end
    -- Per-icon mouse follows (locked AND showTooltip): when locked the
    -- grid frame doesn't capture mouse, so individual icons can claim
    -- it for hover tooltips. When unlocked, the grid wants mouse for
    -- drag and icons must pass through.
    local enableIconMouse = (locked and showTip) and true or false
    for _, btn in ipairs(inst.ordered) do
        btn:EnableMouse(enableIconMouse)
    end
end

IconGrid._BuildHandle = buildHandle
