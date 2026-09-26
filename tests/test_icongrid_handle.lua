-- tests/test_icongrid_handle.lua — the unlocked drag strip over each unit's icon grid.
--
-- BEFORE THIS, THE GRID'S ONLY DRAG AFFORDANCE WAS THE GRID. IconGrid:ApplyLock flipped
-- EnableMouse and RegisterForDrag on the frame and nothing on screen said so: the grab target was
-- whatever icons happened to be laid out, which with a one-spell list is a single square and with
-- an EMPTY list is nothing at all — the wart IconGrid:Layout still works around by keeping an empty
-- grid at primary-icon size (modules/IconGrid.lua:454-457, "a small invisible square").
--
-- THE STRIP ITSELF IS NOT TESTED HERE. It is LibKa0s-Widgets-1.0's
-- (libs/LibKa0s/WidgetsDragHandle.lua) and its fill, edge, label face, help mark and tooltip bands
-- are covered by the library's own suite; re-asserting them in a consumer would be a second copy of
-- the same expectations, drifting on its own schedule. What is KickCD's, and what these cases pin,
-- is the WIRING:
--
--   * the strip is shown and hidden by the SAME ApplyLock that registers and unregisters the drag,
--     so the affordance can never outlive the ability it advertises;
--   * a drag on it moves the GRID and persists through the grid's own onDragStop path, not a
--     second copy of the save;
--   * it refuses to move anything while locked, so a path that leaves it shown cannot turn a locked
--     grid into a movable one;
--   * its label names the unit, because target and focus draw the same strip at the same time.
local T = _G.KICKCD_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local WIDGETS = "LibKa0s-Widgets-1.0"

--- A fresh enabled addon and its target instance. The enable cascade runs EnableUnit -> EnsureGrid,
--- so the strip is already built by the time a case sees it, and — the default profile being
--- unlocked — already shown. Fresh per case rather than shared: three of these write
--- db.profile.locked, and a shared instance would leak that into whatever ran next.
local function fresh()
    local loaded   = T.load(true, true)
    local NS       = loaded.NS
    local IconGrid = NS:GetModule("IconGrid")
    return NS, IconGrid, IconGrid:GetInstance("target"), loaded.mocks
end

--- Set the lock and re-run the ONE call that is allowed to act on it. Written as a helper so no
--- case can accidentally assert a strip's state against a lock nothing has applied yet.
local function setLocked(NS, IconGrid, inst, locked)
    NS.db.profile.locked = locked
    IconGrid:ApplyLock(inst)
end

test("the grid carries a drag strip once its frame exists", function()
    local _, _, inst = fresh()
    assertTrue(inst.handle ~= nil,
        "EnsureGrid must build the strip; without it the only grab target is the icons themselves")
end)

test("the strip's label names the addon and which grid it moves", function()
    local NS, _, inst = fresh()
    -- Both instances draw the same strip when Focus is enabled, so the unit has to be IN the text
    -- or the player is guessing which of two identical strips moves which grid. `__label` is what
    -- the widget was told, which is both what it draws and what it measures.
    assertEqual(inst.handle.__label, NS.L["Ka0s KickCD"] .. " — " .. NS.L["Target"])
end)

test("ApplyLock shows the strip when it registers the drag and hides it when it clears it", function()
    local NS, IconGrid, inst = fresh()
    setLocked(NS, IconGrid, inst, false)
    assertTrue(inst.handle:IsShown(), "an unlocked grid must say where to grab it")
    setLocked(NS, IconGrid, inst, true)
    assertFalse(inst.handle:IsShown(),
        "a locked grid takes no drag, so it must not advertise one")
    setLocked(NS, IconGrid, inst, false)
    assertTrue(inst.handle:IsShown(), "unlocking must bring it back")
end)

test("the strip is sized to its label plus the widget's reserve", function()
    local NS, IconGrid, inst, mocks = fresh()
    -- The widget measures on a detached font string of its own (`__DragHandleMeasurer`), never on
    -- the label. UNSTUBBED THIS CASE WOULD ASSERT THE FIXTURE: tests/wow_mock.lua:67 lists
    -- GetStringWidth among the NUMERIC_GETTERS, which answer an inert 0 so that arithmetic on a
    -- measurement can never raise — so the label measures 0 and this case would be asserting
    -- RESERVE * 2, the constant alone, rather than anything about the label. One lib table per
    -- loaded instance, so the replacement reaches no other suite.
    mocks.LibStub(WIDGETS, true).__DragHandleMeasurer = function()
        return { SetText = function() end, GetStringWidth = function() return 100 end }
    end
    setLocked(NS, IconGrid, inst, false)
    -- RESERVE is spent on BOTH sides of the label — on the right it pays for the mark's inset, its
    -- frame less the gutter its art is centered in and the clearance in front of that art; on the
    -- left it is the matching gap that keeps the label optically centered. Read off the widget
    -- rather than typed here, because a copy is a second number to keep in step.
    local RESERVE = mocks.LibStub(WIDGETS, true).DRAG_HANDLE.RESERVE
    assertEqual(inst.handle:GetWidth(), 100 + RESERVE * 2,
        "the strip is its label plus what it keeps clear on each side")
end)

test("dragging the strip moves the GRID and saves its anchor", function()
    local NS, IconGrid, inst = fresh()
    setLocked(NS, IconGrid, inst, false)
    local moves = { start = 0, stop = 0 }
    inst.grid.StartMoving        = function() moves.start = moves.start + 1 end
    inst.grid.StopMovingOrSizing = function() moves.stop  = moves.stop  + 1 end
    -- Wrapped rather than replaced, so the real save still runs and the `general` config message it
    -- fires goes round the live loop exactly as it does in the client.
    local saved
    local realSetAnchor = NS.Units.SetAnchor
    NS.Units.SetAnchor = function(unit, which, anchor)
        saved = { unit, which }
        return realSetAnchor(unit, which, anchor)
    end
    inst.handle:GetScript("OnDragStart")(inst.handle)
    inst.handle:GetScript("OnDragStop")(inst.handle)
    NS.Units.SetAnchor = realSetAnchor
    assertEqual(moves.start, 1, "the strip must move the grid, not itself")
    assertTrue(moves.stop > 0, "the move must be ended")
    -- `> 0` and not `== 1`: the widget stops the move itself and IconGrid's own onDragStop stops it
    -- again, which is a no-op on a frame that is no longer moving. Pinning the count would be
    -- pinning that redundancy rather than the behavior.
    assertTrue(saved ~= nil and saved[1] == "target" and saved[2] == "icons",
        "the drop must persist the grid's anchor through the path the frame already used")
end)

test("the strip refuses to move a LOCKED grid", function()
    local NS, IconGrid, inst = fresh()
    local started = 0
    inst.grid.StartMoving = function() started = started + 1 end
    setLocked(NS, IconGrid, inst, true)
    -- Fired directly rather than through a cursor, because ApplyLock has just hidden the strip and
    -- in the live client this is unreachable today. That is the point: the guard is what keeps it
    -- unreachable from a path nobody has written yet, and it is the same check the grid frame's own
    -- onDragStart makes (modules/IconGrid.lua:540).
    inst.handle:GetScript("OnDragStart")(inst.handle)
    assertEqual(started, 0, "a locked grid must not move, whoever asks")
end)

-- ── the strip clears the unit label (owner, in the client, 2026-09-21) ──────────────────────
--
-- The strip hangs off the grid's TOP and so does the unit label, by default, so the two drew on
-- top of each other -- "Ka0s KickCD — Target" and "Target" in the same place. The label is what a
-- player reads to tell two grids apart, so the strip is what moves.
--
-- The decision is UnitLabel's (FrameAbove), read off the CONFIG rather than off the label frame's
-- shown state, because both modules answer the same CONFIG_CHANGED and nothing orders them.
-- `__anchorTo` is what IconGrid recorded, for a fake frame that keeps no points.

--- Seed the label's APPEARANCE and its show flag where the resolvers actually read them:
--- `label.style.*` for Units.LabelStyle and `label.show` for Units.LabelShow (core/Units.lua).
--- Writing `label.attach` directly would set a key nothing reads, and every case here would
--- pass on the default rather than on what it asked for.
local function labelStyle(NS, unit, show, style)
    local u = NS.db.profile.units[unit]
    u.label = u.label or {}
    u.label.show = show
    u.label.style = u.label.style or {}
    for k, v in pairs(style) do u.label.style[k] = v end
end

test("the strip hangs above the unit LABEL when one is parked on the grid", function()
    local NS, IconGrid, inst = fresh()
    labelStyle(NS, "target", true, { attach = "icons", relPoint = "TOP" })
    local lbl = NS:GetModule("UnitLabel")
    lbl:Apply(lbl:GetInstance("target"))
    setLocked(NS, IconGrid, inst, false)
    local labelRegion = lbl:FrameAbove("target", "icons")
    assertTrue(labelRegion ~= nil, "the label reports itself as being above the grid")
    -- red under the old anchor, which was always the grid frame
    assertEqual(inst.handle.__anchorTo, labelRegion, "the strip clears the label")
    -- AND it is the FONTSTRING, not the 1x1 frame the text is centered on. Anchoring to that
    -- frame put the strip on the top half of the label -- the first attempt did exactly that and
    -- the overlap was still visible in the client.
    local li = lbl:GetInstance("target")
    assertEqual(labelRegion, li.text, "the region to clear is the text, which has real extents")
    assertTrue(labelRegion ~= li.frame, "not the 1x1 frame, whose TOP is the text's middle")
end)

test("the strip keeps its old place when no label is above the grid", function()
    local NS, IconGrid, inst = fresh()
    labelStyle(NS, "target", false, { attach = "icons", relPoint = "TOP" })
    local lbl = NS:GetModule("UnitLabel")
    lbl:Apply(lbl:GetInstance("target"))
    setLocked(NS, IconGrid, inst, false)
    assertEqual(inst.handle.__anchorTo, inst.grid, "with the label off, the grid is the anchor")
end)

test("a label parked on the CAST BAR is not in the grid strip's way", function()
    local NS, IconGrid, inst = fresh()
    labelStyle(NS, "target", true, { attach = "castbar", relPoint = "TOP" })
    local lbl = NS:GetModule("UnitLabel")
    lbl:Apply(lbl:GetInstance("target"))
    setLocked(NS, IconGrid, inst, false)
    assertTrue(lbl:FrameAbove("target", "icons") == nil, "it is above the cast bar, not the grid")
    assertEqual(inst.handle.__anchorTo, inst.grid, "so the strip stays on the grid")
end)

test("a label anchored UNDER the grid is not in the strip's way either", function()
    local NS, IconGrid, inst = fresh()
    labelStyle(NS, "target", true, { attach = "icons", relPoint = "BOTTOM" })
    local lbl = NS:GetModule("UnitLabel")
    lbl:Apply(lbl:GetInstance("target"))
    setLocked(NS, IconGrid, inst, false)
    assertTrue(lbl:FrameAbove("target", "icons") == nil, "the point is configurable; BOTTOM is not above")
    assertEqual(inst.handle.__anchorTo, inst.grid)
end)

-- ── the strip clears the label with NO manual re-apply (owner, in the client, 2026-09-26) ────
--
-- Every case above builds the label and then calls ApplyLock by hand, and that hid the bug the
-- owner still saw after the 2026-09-21 fix. In the client nothing makes that second call:
-- core/LifecycleSetup.lua stands IconGrid up BEFORE UnitLabel, so EnsureGrid anchors the strip
-- while the label has no frame yet (FrameAbove answered nil and the strip went to the grid), and
-- a later label toggle fires CONFIG_CHANGED { section = "label" }, which IconGrid did not handle
-- at all. These cases go through the real stand-up and the real bus and make no ApplyLock call
-- of their own.

--- What a settings write under the Label page fires.
local function fireLabelChanged(NS, unit)
    NS:SendMessage(T.NS.MSG.CONFIG_CHANGED, { section = "label", unit = unit })
end

test("after a plain load both units' strips already clear the default label", function()
    local loaded   = T.load(true, true)
    local NS       = loaded.NS
    local IconGrid = NS:GetModule("IconGrid")
    local lbl      = NS:GetModule("UnitLabel")
    for _, u in ipairs({ "target", "focus" }) do
        local inst = IconGrid:GetInstance(u)
        assertTrue(inst.handle ~= nil and inst.handle:IsShown(), u .. ": the unlocked strip is up")
        local region = lbl:FrameAbove(u, "icons")
        assertTrue(region ~= nil, u .. ": the default label sits above the grid")
        assertEqual(inst.handle.__anchorTo, region,
            u .. ": the strip hangs off the label's text, not the grid it shares a top edge with")
    end
end)

test("toggling the label re-places both units' strips through the bus", function()
    local loaded   = T.load(true, true)
    local NS       = loaded.NS
    local IconGrid = NS:GetModule("IconGrid")
    local lbl      = NS:GetModule("UnitLabel")
    local units    = NS.db.profile.units
    for _, u in ipairs({ "target", "focus" }) do
        local inst = IconGrid:GetInstance(u)
        -- Focus is linked by default and reads target's show; unlink it so each unit's own
        -- flag is what is being toggled.
        units.focus.link = false
        units[u].label.show = false
        fireLabelChanged(NS, u)
        assertEqual(inst.handle.__anchorTo, inst.grid, u .. ": label off, the strip sits on the grid")
        units[u].label.show = true
        fireLabelChanged(NS, u)
        assertEqual(inst.handle.__anchorTo, lbl:FrameAbove(u, "icons"),
            u .. ": label back on, the strip moves above it")
        units[u].label.style.attach = "castbar"
        fireLabelChanged(NS, u)
        assertEqual(inst.handle.__anchorTo, inst.grid,
            u .. ": label moved to the cast bar, the grid's strip returns to the grid")
        units[u].label.style.attach = "icons"
        fireLabelChanged(NS, u)
    end
end)
