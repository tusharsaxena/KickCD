-- modules/Castbar_Handle.lua -- the cast bar's drag strip (peeled from Castbar.lua)
--
-- LibKa0s-Widgets-1.0's DragHandle, wearing this addon's strings and callbacks:
-- the library resolution, the strip's label, and the build itself. Castbar.lua
-- keeps everything the strip calls BACK into -- whether a drag is allowed
-- (`Castbar.DragAllowed`, which the PRIMARY anchor mode refuses) and where the
-- anchor is written when one stops (`Castbar.SaveAnchor`) -- because both are
-- also the bar's own drag scripts' answers and neither is about the strip.
--
-- Peeled because adopting the widget took Castbar.lua to 1501 LOC against
-- layout-1's 1500 hard cap. modules/Castbar_Skin.lua was peeled from the same
-- file for the same reason at 1489, and its header describes the pattern this
-- one follows: shared helpers come off the module table rather than being
-- duplicated, and Castbar.lua loads first so they exist by the time anything
-- here runs.
--
-- The adoption was supposed to DELETE code, and against the hand-written hint it
-- did -- but the hint was four lines and a strip is a widget with a label, a
-- tooltip, a right-click and two gates, so the file grew. That is the honest
-- shape of this trade and it is why the peel came with it.

local _, NS = ...
local L = NS.L
local Castbar = NS:GetModule("Castbar")

-- The drag strip's library, resolved at file load beside LSM and for the same
-- reason: a VENDORED major either registered before modules/ was reached or never
-- will, so asking once is asking as often as the question can be answered.
-- LibKa0s-Widgets-1.0 publishes `lib.DragHandle` and `lib.DRAG_HANDLE` out of
-- libs/LibKa0s/WidgetsDragHandle.lua (its own minor 2, paired on the shell's) --
-- the dark fill, the 1px gold edge, the centered gold label bounded on both
-- sides, the help mark with its art fallback and its hover tint, the tooltip
-- bands, the two drag scripts and the width arithmetic. AuraMaster drew that
-- strip per container and ConsumableMaster over its macro bar; this file drew a
-- line of hint text, and the strip is what the hint is being traded for.
--
-- NIL IS A REAL ANSWER, exactly as it is for LSM above and for NS.Icon in
-- core/MediaSetup.lua: an install missing libs/LibKa0s gets a cast bar with no
-- strip, which is what buildHandle returns and what ApplyLock's
-- `if frame.dragHandle` guard already tolerates.
local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

--- The strip's label: the UNIT's, not the addon's.
---
--- Both bars can be unlocked at once and both strips are the same box in the same
--- gold, so a label reading "KickCD castbar" twice would not say which bar it
--- moves. The old hint could afford the addon's name because a FontString was all
--- there was; the strip's tooltip carries the addon name now (L["KickCD castbar"]
--- is its title, the same key RenderCast's preview still uses further down this
--- file) and the label spends its width on the thing that differs.
---
--- TWO WHOLE KEYS, not ("%s castbar"):format(unitWord). localization-§1/§2 make
--- the key the English source string, and a sentence assembled at runtime is not
--- one -- it is two fragments no translator can see the shape of. The inline
--- unit test is settings/Panel_Render.lua:109's, which picks L["Target"] /
--- L["Focus"] the same way.
local function handleLabel(unit)
    return (unit == "focus") and L["Focus castbar"] or L["Target castbar"]
end

--- Build the strip a player drags the bar by: LibKa0s-Widgets-1.0's handle,
--- wearing this addon's strings and callbacks. Parented to the BAR, so it hides,
--- restrata's and dies with it and no teardown path has to learn a new frame.
---
--- WIDTH IS NATURAL, FLOORED AT NOTHING (`ApplyWidth(0)`), and that is a
--- correctness call rather than a taste one. ConsumableMaster floors its strip at
--- the macro bar's width and AuraMaster at one element; flooring at this frame's
--- width would be wrong, because the bar's long axis SWAPS with orientation
--- (modules/Castbar_Skin.lua's applyBarGeometry: VERTICAL sets
--- frame:SetSize(barThick, barLong)), so a VERTICAL bar would floor the strip at
--- its ~20px thickness and the label would truncate inside its own reserve. The
--- label is static per unit, so the measurement is taken once here and never has
--- to be hooked into Reskin.
---
--- NO `edge` AND NO `number`: this addon has no house edge painter, and the bar is
--- a plain UIParent child -- nothing here is parented to a protected frame, so no
--- width or level read comes back secret and the widget's own tonumber guard is
--- the right one. Contrast AuraMaster, which must pass both.
---
--- THE TOOLTIP IS OWNED BY THE HOVERED FRAME (the widget's default), not by the
--- cursor: AuraMaster needs "cursor" because its anchor inherits
--- DisableUntrustedLayoutScriptsTemplate and the client refuses SetOwner under it.
--- No frame here inherits that template.
---
--- @return table|nil  nil without LibKa0s-Widgets-1.0, and in a client that
---                    cannot make the frame -- ApplyLock guards on the field.
local function buildHandle(inst, frame)
    if not (KW and KW.DragHandle) then return nil end
    local handle = KW.DragHandle(frame, {
        label        = handleLabel(inst.unit),
        moveFrame    = frame,
        helpIcon     = NS.Icon and NS.Icon("help") or nil,
        canDrag      = function() return Castbar.DragAllowed(inst) end,
        onDragStop   = function() Castbar.SaveAnchor(inst, frame) end,
        -- The same open the launcher's left button and `/kcd config` reach
        -- (core/LauncherSetup.lua:131, core/KickCD.lua:200). It refuses itself
        -- in combat with options-ui-§2's gray line, so nothing is gated here.
        onRightClick = function() NS:OpenSettings() end,
        tooltip      = {
            title = L["KickCD castbar"],
            body  = { L["Drag to move. Right-click for settings."] },
        },
    })
    if not handle then return nil end
    handle:ApplyWidth(0)
    -- The hint's own place and the hint's own gap, except the 2 is now read off
    -- the widget (lib.DRAG_HANDLE.GAP) instead of typed here, so the strip and
    -- every sibling addon's strip keep the same standoff from what they move.
    -- ABOVE THE UNIT LABEL when one is parked on this bar, else above the bar itself. The
    -- strip's natural home is the frame's TOP edge and so is the label's, so the two drew on top
    -- of each other on the grid (owner, in the client, 2026-09-21) and would do the same here the
    -- moment a player set the label's attach to the cast bar. UnitLabel:FrameAbove resolves its
    -- own attach, show and anchor config and answers nil for every case that is not in the way --
    -- see there for why that is read off the config rather than off the frame's shown state.
    local lbl = NS:GetModule("UnitLabel", true)
    local above = lbl and lbl.FrameAbove and lbl:FrameAbove(inst.unit, "castbar") or nil
    handle:SetPoint("BOTTOM", above or frame, "TOP", 0, KW.DRAG_HANDLE.GAP)
    return handle
end

-- Published rather than local: Castbar.lua's EnsureFrame is the only caller and it
-- reaches this file through the module table, the same way it reaches Castbar_Skin.
Castbar.BuildHandle = buildHandle
