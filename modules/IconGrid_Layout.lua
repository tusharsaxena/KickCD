-- modules/IconGrid_Layout.lua — icon-grid geometry (peeled from IconGrid.lua, KCD-05)
--
-- Pure-ish layout math for the icon grid: anchor/grow token parsing and the
-- block-placement geometry. parseAnchor / parseGrow / placeBlock are pure
-- (numbers and strings in, numbers/strings out) and unit-tested headlessly;
-- layoutBlock is the frame-manipulating orchestrator that positions the
-- primary + secondary buttons against the grid frame using those helpers.
--
-- Published on the IconGrid module as IconGrid.LayoutMath so modules/IconGrid.lua
-- can call IconGrid.LayoutMath.layoutBlock(...) and the test harness can exercise
-- the pure parsers directly. (NOT IconGrid.Layout — that key is the OnEnable
-- orchestrator method; see the load-order note at the assignment below.)

local addonName, NS = ...
local IconGrid = NS:GetModule("IconGrid")

-- Published under a DISTINCT key from the IconGrid:Layout() orchestrator method
-- (modules/IconGrid.lua). Sharing the key would clobber the method — this file
-- loads after IconGrid.lua — and break every self:Layout() call (KCD-05).
local Layout = {}
IconGrid.LayoutMath = Layout

local floor = math.floor

-- Anchor parser. Returns (side, align). Accepts the modern "<SIDE>_MIDDLE"
-- dropdown tokens (normalized to "<SIDE>_CENTER"), the legacy "<SIDE>_CENTER"
-- tokens, and the whole-frame "CENTER" (13th option). Falls back to
-- ("RIGHT", "CENTER") for anything unrecognized.
function Layout.parseAnchor(value)
    if value == "CENTER" then return "CENTER", "CENTER" end

    local side, align = (value or ""):match("^(%a+)_(%a+)$")
    if align == "MIDDLE" then align = "CENTER" end

    if side == "TOP" or side == "BOTTOM" then
        if align == "CENTER" or align == "LEFT" or align == "RIGHT" then
            return side, align
        end
    elseif side == "LEFT" or side == "RIGHT" then
        if align == "CENTER" or align == "TOP" or align == "BOTTOM" then
            return side, align
        end
    end
    return "RIGHT", "CENTER"
end

-- Grow-direction parser. Returns (primaryAxis, secondaryAxis) where
-- primary is the in-line fill direction and secondary is the wrap.
function Layout.parseGrow(value)
    local primary, secondary = (value or ""):match("^(%a+)_(%a+)$")
    local horiz = { right = true, left = true }
    local vert  = { down  = true, up   = true }
    if not ((horiz[primary] and vert[secondary]) or
            (vert[primary]  and horiz[secondary])) then
        primary, secondary = "right", "down"
    end
    return primary, secondary
end

-- Compute the secondaries block's TOPLEFT relative to the grid frame's
-- TOPLEFT, plus the primary's TOPLEFT and the grid frame's full
-- bounding-box size — all in screen-pixel space (y grows downward; the
-- caller flips the sign when handing the value to SetPoint).
function Layout.placeBlock(side, align, primarySize, blockW, blockH, gap)
    local gridW, gridH, primaryX, primaryY, blockX, blockY

    if side == "CENTER" then
        -- Degenerate "stack on top of the primary" anchor: grid
        -- bounding box is whichever of the two is bigger on each axis,
        -- and both primary and the secondary block sit centered in
        -- it. The block visually overlaps the primary — niche, but
        -- it's the natural read of a 13th "CENTER" anchor option in a
        -- dropdown otherwise built around side+alignment edges.
        gridW    = math.max(primarySize, blockW)
        gridH    = math.max(primarySize, blockH)
        primaryX = floor((gridW - primarySize) / 2)
        primaryY = floor((gridH - primarySize) / 2)
        blockX   = floor((gridW - blockW) / 2)
        blockY   = floor((gridH - blockH) / 2)
    elseif side == "TOP" then
        gridW = math.max(primarySize, blockW)
        gridH = blockH + gap + primarySize
        blockY    = 0
        primaryY  = blockH + gap
        if align == "CENTER" then
            primaryX = floor((gridW - primarySize) / 2)
            blockX   = floor((gridW - blockW) / 2)
        elseif align == "LEFT" then
            primaryX, blockX = 0, 0
        else  -- RIGHT
            primaryX = gridW - primarySize
            blockX   = gridW - blockW
        end
    elseif side == "BOTTOM" then
        gridW = math.max(primarySize, blockW)
        gridH = primarySize + gap + blockH
        primaryY = 0
        blockY   = primarySize + gap
        if align == "CENTER" then
            primaryX = floor((gridW - primarySize) / 2)
            blockX   = floor((gridW - blockW) / 2)
        elseif align == "LEFT" then
            primaryX, blockX = 0, 0
        else  -- RIGHT
            primaryX = gridW - primarySize
            blockX   = gridW - blockW
        end
    elseif side == "LEFT" then
        gridW = blockW + gap + primarySize
        gridH = math.max(primarySize, blockH)
        blockX    = 0
        primaryX  = blockW + gap
        if align == "CENTER" then
            primaryY = floor((gridH - primarySize) / 2)
            blockY   = floor((gridH - blockH) / 2)
        elseif align == "TOP" then
            primaryY, blockY = 0, 0
        else  -- BOTTOM
            primaryY = gridH - primarySize
            blockY   = gridH - blockH
        end
    else  -- RIGHT
        gridW = primarySize + gap + blockW
        gridH = math.max(primarySize, blockH)
        primaryX = 0
        blockX   = primarySize + gap
        if align == "CENTER" then
            primaryY = floor((gridH - primarySize) / 2)
            blockY   = floor((gridH - blockH) / 2)
        elseif align == "TOP" then
            primaryY, blockY = 0, 0
        else  -- BOTTOM
            primaryY = gridH - primarySize
            blockY   = gridH - blockH
        end
    end

    return gridW, gridH, primaryX, primaryY, blockX, blockY
end

-- Position the primary + secondary buttons against `gridFrame` and return the
-- grid's bounding-box (width, height, truncatedCount). `gridFrame` was a file-
-- local in the pre-peel module; it's now an explicit parameter so this stays a
-- sibling file with no shared upvalue.
function Layout.layoutBlock(gridFrame, primary, secondaries, primarySize, secondarySize, gap,
                            anchor, grow, rows, cols, offX, offY)
    primary:ClearAllPoints()
    primary:SetSize(primarySize, primarySize)

    -- Visible-count short-circuit: a primary-only grid has no
    -- secondary block, so collapse to a primarySize × primarySize
    -- frame (no gap, no empty block padding). Without this, the
    -- placeBlock math below would add `gap + 0` to each side
    -- creating a phantom strip the user can drag but can't see.
    local visibleCount = #secondaries
    if visibleCount == 0 then
        primary:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, 0)
        return primarySize, primarySize
    end

    local side, align         = Layout.parseAnchor(anchor)
    local primaryAxis, secAxis = Layout.parseGrow(grow)

    -- Fill order: row-major if grow's primary axis is horizontal,
    -- column-major if vertical.
    local rowMajor = (primaryAxis == "right" or primaryAxis == "left")
    -- `c=0` lives at the right edge if either axis is "left"; `r=0` at
    -- the bottom edge if either axis is "up".
    local invertX = (primaryAxis == "left") or (secAxis == "left")
    local invertY = (primaryAxis == "up")   or (secAxis == "up")

    -- "Used" extent — the actual rectangular area the visible icons
    -- occupy, regardless of how much capacity (rows * cols) was
    -- configured. Lets the grid frame's bounding box hug the live
    -- icons so:
    --   * The cast bar's "Auto-size to icon grid" tracks the visible
    --     extent, not the configured capacity.
    --   * The drag handle doesn't include phantom empty slots beyond
    --     the rendered icons.
    -- Wrap math in the per-icon loop below still uses the configured
    -- `cols` / `rows` so multi-row layouts wrap at the user's chosen
    -- column count; only the bounding box and the inverted-axis
    -- mirror collapse onto `usedCols` / `usedRows`.
    local usedCols, usedRows
    if rowMajor then
        usedCols = math.min(visibleCount, cols)
        usedRows = math.ceil(visibleCount / cols)
    else
        usedRows = math.min(visibleCount, rows)
        usedCols = math.ceil(visibleCount / rows)
    end

    local step = secondarySize + gap
    -- Block bounding box is the icons' rectangular extent — not cols*step,
    -- since the trailing gap doesn't belong to the block. (usedCols-1)*step
    -- gives the offset of the last icon's left edge; + secondarySize
    -- closes the right edge.
    local blockW = (usedCols - 1) * step + secondarySize
    local blockH = (usedRows - 1) * step + secondarySize

    local gridW, gridH, primaryX, primaryY, blockX, blockY =
        Layout.placeBlock(side, align, primarySize, blockW, blockH, gap)

    primary:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", floor(primaryX), floor(-primaryY))

    local cap = rows * cols
    for i = 1, math.min(visibleCount, cap) do
        local r, c
        if rowMajor then
            r = floor((i - 1) / cols)
            c = (i - 1) - r * cols
        else
            c = floor((i - 1) / rows)
            r = (i - 1) - c * rows
        end
        -- Visual position uses usedCols / usedRows for inverted axes
        -- so the mirror lands inside the shrunk block (icons cluster
        -- against the primary instead of against a phantom far edge).
        -- Non-inverted axes don't need to mirror — `c` and `r` are
        -- already 0-based indices that fit naturally.
        local cVis = invertX and (usedCols - 1 - c) or c
        local rVis = invertY and (usedRows - 1 - r) or r

        local btn = secondaries[i]
        btn:SetSize(secondarySize, secondarySize)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", gridFrame, "TOPLEFT",
            floor(blockX + cVis * step + offX),
            floor(-(blockY + rVis * step + offY)))
    end

    -- Hide overflow secondaries — pool keeps them around for next rebuild.
    -- Track the truncation count so the caller can warn the user once
    -- per (class/spec/cap) tuple — silently dropping icons past the
    -- configured grid size used to be an invisible failure mode.
    local truncated = 0
    for i = cap + 1, #secondaries do
        secondaries[i]:Hide()
        truncated = truncated + 1
    end

    -- Add abs(offset) to the grid bounding box so dragging stays sane
    -- when the user has shifted the block off the primary's footprint.
    local width  = gridW + math.abs(offX)
    local height = gridH + math.abs(offY)
    if width  <= 0 then width  = primarySize end
    if height <= 0 then height = primarySize end
    return floor(width), floor(height), truncated
end
