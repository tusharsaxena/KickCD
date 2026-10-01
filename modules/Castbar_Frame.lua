-- modules/Castbar_Frame.lua -- the cast bar's lock, drag and anchor code and its
-- frame build (peeled from Castbar.lua, #24)
--
-- dragAllowed, the bar's own drag scripts, saveAnchor, the 13-point anchor
-- translation (toSetPoint), Castbar:ApplyAnchor, Castbar:ApplyLock and
-- Castbar:EnsureFrame. A pure move: Castbar.lua had regrown to 1251 lines after
-- the Castbar_Events peel, still inside layout-§1's 1000-1500 band, and this is
-- the next seam #24 named.
--
-- The helpers come off the module table, the pattern Castbar_Skin.lua,
-- Castbar_Handle.lua and Castbar_Events.lua follow, bound to file-scope upvalues
-- once at load. onUpdate is Castbar.lua's per-frame loop, published as
-- Castbar._OnUpdate; by the time this file loads it is defined, so EnsureFrame
-- wraps the same function it wrapped before the move. Castbar.BuildHandle
-- (Castbar_Handle.lua, loaded after this file) is read when EnsureFrame runs, at
-- enable time.

local _, NS = ...
local Castbar = NS:GetModule("Castbar")   -- registered by modules/Castbar.lua, which loads first

local cfg                = Castbar.Cfg
local resolvePrimaryIcon = Castbar.ResolvePrimaryIcon
local resolveGridFrame   = Castbar.ResolveGridFrame
local isVisible          = Castbar.IsVisible
local onUpdate           = Castbar._OnUpdate

-- ---------------------------------------------------------------------------
-- Lock / drag persistence + anchoring
-- ---------------------------------------------------------------------------
--
-- Two anchor modes:
--   * FREE    — the bar floats free of the icon grid. The user drags it to
--               position; OnDragStop persists the anchor to anchors.castbar.
--   * PRIMARY — the bar is SetPoint'd to the icon grid's primary icon
--               button (or grid frame fallback when no spell is being
--               watched). Dragging is disabled in this mode because the bar
--               position is determined by the icon position and the user-
--               configured (anchorPoint, castbarPoint, offset) tuple.

--- May a drag move this bar at this moment?
---
--- ONE PREDICATE, TWO CONSUMERS, and that is the whole reason it was lifted out
--- of ApplyLock (which is its only caller before this change, below): the strip's
--- VISIBILITY and the widget's own `canDrag` GATE have to answer the same
--- question, or the bar grows a box that advertises a drag it then refuses.
---
--- They are not one mechanism wearing two names. Hiding the strip removes the
--- affordance; `canDrag` refuses the act (libs/LibKa0s/WidgetsDragHandle.lua,
--- dhSetDragScripts -- a false answer returns before StartMoving and before
--- __dragging is set, so the matching OnDragStop also returns and nothing is
--- persisted).
---
--- BOTH are wired because hiding alone does not cover the whole affordance.
--- dhBuildHelp copies the strip's drag scripts onto the "?" Button, so the mark is
--- a second thing that can start a move, and `canDrag` is the one gate that sits in
--- front of both. Hiding is what stops the bar ADVERTISING a drag it would refuse;
--- `canDrag` is what makes the refusal true wherever the drag is started from.
---
--- PRIMARY anchor mode forces drag-disabled -- the bar's position is determined
--- by the icon-grid anchor + offsets, not by dragging (defaults/Profile.lua's
--- `anchorMode` comment says the same thing from the schema's side, and PRIMARY
--- is the shipped default). `cfg(inst)` is indexed unguarded here because it was
--- indexed unguarded in ApplyLock before this: behavior is unchanged, not widened.
local function dragAllowed(inst)
    local profileLocked = NS.db and NS.db.profile and NS.db.profile.locked
    return (not profileLocked) and (cfg(inst).anchorMode ~= "PRIMARY")
end

local function onDragStart(_inst, self)
    if NS.db and NS.db.profile and NS.db.profile.locked then return end
    self:StartMoving()
end

--- Persist where the bar ended up, and say so on the bus.
---
--- SPLIT OUT OF onDragStop because there are now TWO ways a drag of this bar can
--- finish and only one of them owns the StopMovingOrSizing. The bar's own
--- OnDragStop (below) is handed the frame and stops the move itself; the strip's
--- stop is the widget's, which has already called StopMovingOrSizing on
--- `moveFrame` by the time it calls this back (libs/LibKa0s/WidgetsDragHandle.lua,
--- dhSetDragScripts). Handing the widget the old onDragStop would have stopped
--- one move twice.
local function saveAnchor(inst, frame)
    if NS.db and NS.db.profile then
        NS.Units.SetAnchor(inst.unit, "castbar", NS.Util.SaveAnchor(frame))
    end
    -- CR-34: complete the bus contract by announcing the anchor write.
    -- No subscriber listens for "castbar" anchor changes today (the bar
    -- has already moved itself), but firing it makes the bus self-
    -- consistent and defends against a future "anchor-aware" listener.
    -- Castbar's own OnConfigChanged handles { section = "castbar" }
    -- idempotently (Reskin + ApplyLock are no-ops for an already-correct
    -- frame), so the dispatch is safe to re-enter.
    local H = NS.Settings and NS.Settings.Helpers
    if H and H.FireConfigChanged then H.FireConfigChanged("castbar") end
end

local function onDragStop(inst, self)
    self:StopMovingOrSizing()
    saveAnchor(inst, self)
end


-- Translate a 13-point anchor token (the new `<SIDE>_<ALIGN>` /
-- `CENTER` set shared with the Icons grid dropdown) into a name
-- SetPoint accepts (TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT,
-- BOTTOMLEFT, BOTTOM, BOTTOMRIGHT). For 2D-point anchors `TOP_LEFT`
-- and `LEFT_TOP` collapse to the same corner — they're distinct
-- options in the dropdown for UI consistency with the Icons panel
-- (where the alignment axis is meaningful) but produce identical
-- visuals here.
--
-- Unrecognized values pass through unchanged so legacy 9-point
-- tokens saved by older profiles (`TOP`, `BOTTOMLEFT`, …) keep
-- working without an explicit migration. Falls back to `CENTER`
-- when nil.
local SETPOINT_MAP = {
    TOP_LEFT      = "TOPLEFT",
    TOP_MIDDLE    = "TOP",
    TOP_RIGHT     = "TOPRIGHT",
    BOTTOM_LEFT   = "BOTTOMLEFT",
    BOTTOM_MIDDLE = "BOTTOM",
    BOTTOM_RIGHT  = "BOTTOMRIGHT",
    LEFT_TOP      = "TOPLEFT",
    LEFT_MIDDLE   = "LEFT",
    LEFT_BOTTOM   = "BOTTOMLEFT",
    RIGHT_TOP     = "TOPRIGHT",
    RIGHT_MIDDLE  = "RIGHT",
    RIGHT_BOTTOM  = "BOTTOMRIGHT",
    CENTER        = "CENTER",
}

local function toSetPoint(value)
    if not value then return "CENTER" end
    return SETPOINT_MAP[value] or value
end

--- (Re)anchor the cast-bar frame based on the active anchor mode.
--- FREE   -> apply the saved anchor against UIParent.
--- PRIMARY -> SetPoint(castbarPoint, primaryIcon, anchorPoint, offX, offY).
---           Falls back to the grid frame, then to the saved free anchor.
function Castbar:ApplyAnchor(inst)
    local frame = inst.frame
    if not frame then return end
    local c = cfg(inst)
    local mode = c.anchorMode or "FREE"

    if mode == "PRIMARY" then
        -- Prefer the payload-cached references over the public accessors.
        -- Falls back to the grid frame when no spells are watched (no
        -- primary icon yet).
        local target = resolvePrimaryIcon(inst) or resolveGridFrame(inst)
        if target then
            frame:ClearAllPoints()
            frame:SetPoint(
                toSetPoint(c.castbarPoint  or "BOTTOM_MIDDLE"),
                target,
                toSetPoint(c.anchorPoint   or "TOP_MIDDLE"),
                c.anchorOffsetX or 0,
                c.anchorOffsetY or 0)
            return
        end
        -- Target not yet built — fall through to the saved free anchor so
        -- the bar at least has a position to render at while we wait.
    end

    local saved = NS.Units.Anchor(inst.unit, "castbar")
    NS.Util.ApplyAnchor(frame, saved or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 })
end

function Castbar:ApplyLock(inst)
    local frame = inst.frame
    if not frame then return end
    local profileLocked  = NS.db and NS.db.profile and NS.db.profile.locked
    -- The lock question and the PRIMARY question now live in one place
    -- (dragAllowed, up beside the drag scripts), because the strip's `canDrag`
    -- has to ask the same one -- see that function's comment for why both the
    -- hiding and the gate are wired rather than either alone. The local is
    -- renamed only because the predicate took the old name.
    local allowed        = dragAllowed(inst)

    -- THE BAR BODY KEEPS ITS OWN DRAG. The strip is an ADDITIONAL grip, not a
    -- replacement: every player who has ever moved this bar did it by grabbing
    -- the bar, and nothing about adopting the widget requires taking that away.
    -- What is swapped here is only which thing is shown alongside it -- the
    -- library's strip where a one-line FontString hint used to be.
    if allowed then
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if frame.dragHandle then frame.dragHandle:Show() end
    else
        frame:EnableMouse(false)
        frame:RegisterForDrag()
        if frame.dragHandle then frame.dragHandle:Hide() end
    end

    -- Visibility for the empty (no-cast) state:
    --   * UI unlocked + sub-module visible → show preview (so the user can
    --     see where the bar will appear, even in PRIMARY anchor mode).
    --   * UI locked → hide the empty bar; only show during real casts.
    if not inst.current then
        if (not profileLocked) and isVisible(inst) then
            self:ShowPreview(inst)
        else
            frame:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

function Castbar:EnsureFrame(inst)
    if inst.frame then return inst.frame end

    -- Target keeps the exact legacy global name KickCDCastbar (macros / other
    -- addons may reference it); Focus is KickCDCastbarFocus.
    local frame = CreateFrame("Frame",
        inst.unit == "target" and "KickCDCastbar" or "KickCDCastbarFocus", UIParent)
    inst.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Initial anchor — ApplyAnchor() handles both FREE and PRIMARY modes.
    -- Called again at OnEnable / OnConfigChanged / OnGridLayout time.
    self:ApplyAnchor(inst)

    frame:SetScript("OnDragStart", function(f) onDragStart(inst, f) end)
    frame:SetScript("OnDragStop",  function(f) onDragStop(inst, f) end)

    -- ----------------------------------------------------------------
    -- Two backgrounds (interruptible / uninterruptible), stacked. Each
    -- has its own color; alphas are curve-switched against the cast's
    -- secret notInterruptible bool in ApplyState() so only one shows.
    -- ----------------------------------------------------------------
    frame.bgInterruptible   = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgUninterruptible = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgInterruptible:SetAllPoints(frame)
    frame.bgUninterruptible:SetAllPoints(frame)

    -- ----------------------------------------------------------------
    -- Bar area is a non-StatusBar Frame container; the two state bars
    -- live inside it side-by-side (same anchors, alpha-switched).
    -- ----------------------------------------------------------------
    frame.bar = CreateFrame("Frame", nil, frame)

    frame.bar.interruptible   = CreateFrame("StatusBar", nil, frame.bar)
    frame.bar.uninterruptible = CreateFrame("StatusBar", nil, frame.bar)
    for _, sb in ipairs({ frame.bar.interruptible, frame.bar.uninterruptible }) do
        sb:SetAllPoints(frame.bar)
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0)
    end

    -- Overlay frame above the bars. Spark and the name/time text live
    -- here so they draw on TOP of the bar's filled status texture —
    -- otherwise the StatusBar children of frame.bar would render on top
    -- of any FontString/Texture parented to frame.bar at OVERLAY layer
    -- (child frames always draw above their parent's draw layers,
    -- regardless of layer name). frame.overlay sits at a higher
    -- FrameLevel than the bars, so its OVERLAY-layer children win.
    frame.overlay = CreateFrame("Frame", nil, frame.bar)
    frame.overlay:SetAllPoints(frame.bar)
    frame.overlay:SetFrameLevel(frame.bar.interruptible:GetFrameLevel() + 1)

    -- Spark texture (overlay at the right edge of the inner status texture).
    -- We anchor it to the interruptible bar's status texture: both bars
    -- share the same SetMinMaxValues / SetValue calls each frame, so their
    -- inner textures are the same width — anchoring to either is fine.
    frame.spark = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetSize(20, 30)

    -- Icon texture (square; height matches the bar).
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop the Blizzard border

    -- Spell name + remaining time on the overlay frame (above the bars).
    -- Color is per-state and curve-evaluated on a single FontString —
    -- no need to stack two FontStrings.
    frame.nameText = frame.overlay:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetWordWrap(false)

    frame.timeText = frame.overlay:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetJustifyH("RIGHT")

    -- ----------------------------------------------------------------
    -- Two LSM-textured border frames (BackdropTemplate). Each owns its
    -- own edgeFile / edgeSize / color via SetBackdrop+SetBackdropBorderColor;
    -- alphas are curve-switched in ApplyState. Border show toggles fold
    -- into the curve directly so disabled-side stays alpha=0.
    --
    -- Frame level must be HIGHER than the stacked StatusBars; otherwise
    -- the bar's filled status texture (which sits at level +2 because
    -- it's a grandchild of frame) renders ON TOP of the border's edge
    -- and makes the border look like it's tinted by the bar color.
    -- Bumping borders to bar level + 2 puts them above both the bars
    -- (level +2) and the overlay text/spark layer (level +3).
    -- ----------------------------------------------------------------
    frame.borderInterruptible   = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.borderUninterruptible = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.borderInterruptible:SetAllPoints(frame)
    frame.borderUninterruptible:SetAllPoints(frame)
    local barLevel = frame.bar.interruptible:GetFrameLevel()
    frame.borderInterruptible:SetFrameLevel(barLevel + 2)
    frame.borderUninterruptible:SetFrameLevel(barLevel + 2)

    -- The drag strip, shown only where a drag would actually move the bar
    -- (ApplyLock). It REPLACES the plain "KickCD castbar — drag to move"
    -- FontString this file drew here: the same place (BOTTOM to the bar's TOP),
    -- the same 2px gap -- which is the widget's own lib.DRAG_HANDLE.GAP now,
    -- read rather than re-typed -- and the same hidden-at-birth state, which the
    -- widget does itself (libs/LibKa0s/WidgetsDragHandle.lua closes lib.DragHandle
    -- on handle:Hide(), because a strip born visible would flash at zero width).
    --
    -- What the strip adds over the hint is a hit target, a tooltip and a
    -- right-click into the settings panel. What it costs is a box of chrome above
    -- an unlocked bar where there used to be one line of gray text: a UX change,
    -- accepted as one.
    frame.dragHandle = Castbar.BuildHandle(inst, frame)

    -- Built ONCE per instance, here, because this is the only code that runs
    -- once per unit for the life of the session: inst.frame is never cleared,
    -- so the early return at the top of this function is the guard. Start used
    -- to close over `inst` afresh on every cast start (M4-22). A cached handler
    -- also makes SetScript idempotent — installing the SAME function twice is a
    -- no-op, where installing two equal-but-distinct ones is not.
    inst.onUpdateScript = function() onUpdate(inst) end

    frame:Hide()
    return frame
end

-- ---------------------------------------------------------------------------
-- Exposed for modules/Castbar_Handle.lua and the suites
-- ---------------------------------------------------------------------------
-- The drag strip needs the two answers that live here: whether this bar may be
-- dragged at all (the PRIMARY anchor mode says no) and where to write the anchor
-- once a drag stops. ToSetPoint is a pure decider the headless suites pin.
Castbar.DragAllowed   = dragAllowed
Castbar.SaveAnchor    = saveAnchor
Castbar.ToSetPoint    = toSetPoint
