-- modules/Castbar_Skin.lua — config-driven re-skin of the cast bar (peeled from
-- Castbar.lua, KCD-19)
--
-- Everything that turns the `castbar` config table into widget geometry and
-- color: frame sizing (including auto-size against the icon grid), orientation
-- and reverse fill, the icon/bar inset split, the spark, fonts and text
-- anchoring, per-state backgrounds, status-bar textures and colors, and the
-- per-state border backdrops. Castbar.lua keeps the instances, the frame build
-- (EnsureFrame), the per-cast paint (RenderCast), the OnUpdate loop, the
-- lifecycle, and every event/message handler.
--
-- Peeled because Castbar.lua reached 1489 LOC against the standard's 1500 hard
-- cap (layout-§1) with no room left for the next change. The seam is the one
-- the file's own header comment nominated: "a further split of the config-driven
-- build (Reskin / sizing / anchors) from the per-cast update path".
--
-- Shared helpers come off the module table (Castbar.UnpackColor, .StateConfig,
-- .FetchFont, …) rather than being duplicated — they are already published
-- there for the headless suites, and Castbar.lua loads first so they exist by
-- the time anything here runs. Same pattern as IconGrid_Render.lua.
--
-- ---------------------------------------------------------------------------
-- The structural / color split (F-015)
-- ---------------------------------------------------------------------------
--
-- Reskin used to be one ~40-widget-call pass that ran on EVERY
-- Ka0s_KickCD_CONFIG_CHANGED for section "castbar". Dragging a color picker
-- commits at 50 ms intervals, so a two-second drag re-ran frame sizing, icon
-- insets, spark rotation, font loading and text anchoring ~40 times over — none
-- of which a color can change.
--
-- It is now two halves behind the same public entry point:
--
--   * ReskinStructure — geometry: size, orientation, insets, spark, fonts, text
--     anchors, border backdrops (edgeFile / edgeSize). Guarded by a signature
--     over exactly the config fields it reads, so it is skipped outright when
--     none of them moved.
--   * ReskinColors — the cheap half: background colors, status-bar textures and
--     colors, border colors, the shared time-text color. Always runs.
--
-- The guard is a signature rather than a bus payload change on purpose. The
-- alternative — adding the written path to Ka0s_KickCD_CONFIG_CHANGED so
-- subscribers could tell a color edit from a layout edit — would widen the
-- closed five-message bus for one subscriber's benefit. The signature keeps the
-- knowledge of "which fields are structural" in the one file that reads them.
--
-- The resolved bar dimensions are folded INTO the signature, not just the raw
-- config: with castbar.autoSize on, the bar's long axis tracks the icon grid's
-- footprint, which moves on Ka0s_KickCD_GRID_LAYOUT while the config table sits
-- perfectly still. Signing the resolved size is what keeps auto-size working.

local addonName, NS = ...
local Castbar = NS:GetModule("Castbar")

-- A 4px inset on the inside positions keeps text from touching the bar
-- border. The user's offsetX is added on top so they can pull the text
-- further out or push it back in. Sourced from KickCD.Const so the
-- value lives in exactly one place across the addon.
local INSIDE_INSET  = NS.Const.CASTBAR_INSIDE_INSET
local OUTSIDE_INSET = NS.Const.CASTBAR_OUTSIDE_INSET

local function anchorTextElement(fs, bar, position, ox, oy)
    fs:ClearAllPoints()
    if position == "INSIDE_RIGHT" then
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", bar, "RIGHT", -INSIDE_INSET + ox, oy)
    elseif position == "CENTER" then
        fs:SetJustifyH("CENTER")
        fs:SetPoint("CENTER", bar, "CENTER", ox, oy)
    elseif position == "OUTSIDE_LEFT" then
        -- Text floats just to the left of the bar (right-justified so the
        -- text grows outward from the bar's left edge).
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", bar, "LEFT", -OUTSIDE_INSET + ox, oy)
    elseif position == "OUTSIDE_RIGHT" then
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", bar, "RIGHT", OUTSIDE_INSET + ox, oy)
    else
        -- INSIDE_LEFT (default).
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", bar, "LEFT", INSIDE_INSET + ox, oy)
    end
end

--- Border backdrop — the STRUCTURAL half of a per-state border. edgeFile is an
--- LSM border texture; edgeSize is the thickness of that texture's edge slices.
--- BackdropTemplate's SetBackdrop wants the table verbatim each call, which is
--- exactly why this belongs on the guarded side: it allocates a fresh table per
--- call and reloads a texture.
local function applyBorderBackdrop(borderFrame, sc)
    borderFrame:SetBackdrop({
        edgeFile = Castbar.FetchBorderTexture(sc.borderTexture),
        edgeSize = math.max(1, sc.borderSize or 1),
    })
end

--- Border tint — the COLOR half. Colors the already-configured backdrop
--- texture, so it is safe to run without a preceding SetBackdrop.
local function applyBorderColor(borderFrame, sc)
    borderFrame:SetBackdropBorderColor(Castbar.UnpackColor(sc.borderColor, 0, 0, 0, 1))
end

--- Resolve the bar's long / thick axes from config, applying the auto-size
--- override against the unit's own icon grid.
---
--- "Cast bar width" / "Cast bar height" in the settings UI are semantic, NOT
--- physical: width = the bar's long axis (the direction that fills during a
--- cast), height = its thickness perpendicular to fill. WoW Frames have no
--- native rotation, so we fake the user's "rotate 90° in vertical mode" mental
--- model by swapping which physical axis each maps to. With defaults
--- (width=250, height=24):
---   * Horizontal → frame is 250×24 (wide, short).
---   * Vertical   → frame is 24×250 (narrow, tall).
--- Everything downstream — bar sub-frame insets, spark rotation, the iconPos
--- LEFT→TOP / RIGHT→BOTTOM remap — already works once the physical dimensions
--- reflect the rotated geometry.
---
--- Auto-size matches the bar's long axis to the icon grid's corresponding
--- screen-axis extent; thickness stays user-configured. Re-runs on every
--- Ka0s_KickCD_GRID_LAYOUT so the bar tracks the grid as icons are added /
--- removed / resized.
---
--- @return number barLong, number barThick
local function resolveBarSize(inst, c, isVertical)
    local barLong  = math.max(40, c.width  or 250)
    local barThick = math.max(8,  c.height or 24)

    if c.autoSize then
        local gridFrame = Castbar.ResolveGridFrame(inst)
        local frame = inst.frame
        if gridFrame and frame then
            local gs = gridFrame:GetEffectiveScale()
            local bs = frame:GetEffectiveScale()
            if isVertical then
                barLong = Castbar.AutoSizeLong(gridFrame:GetHeight(), gs, bs, barLong)
            else
                barLong = Castbar.AutoSizeLong(gridFrame:GetWidth(), gs, bs, barLong)
            end
        end
    end

    return barLong, barThick
end

--- Flatten every input ReskinStructure reads into one comparison key.
---
--- Anything absent from this list is, by construction, something the structural
--- half does not look at — so if you add a config read to ReskinStructure, add
--- it here in the same edit or the new field will silently fail to take effect
--- until some other structural field happens to move.
---
--- All plain values out of SavedVariables plus the resolved dimensions; nothing
--- here is ever secret.
local function structureSignature(c, intCfg, unintCfg, barLong, barThick)
    return table.concat({
        barLong, barThick,
        tostring(c.orientation), tostring(c.growDirection),
        tostring(c.iconPosition), tostring(c.iconSize),
        tostring(c.showSpark),
        tostring(c.font), tostring(c.fontSize), tostring(c.fontFlags),
        tostring(c.namePosition), tostring(c.nameOffsetX), tostring(c.nameOffsetY),
        tostring(c.timePosition), tostring(c.timeOffsetX), tostring(c.timeOffsetY),
        tostring(c.showName), tostring(c.showTime),
        tostring(intCfg.borderTexture),   tostring(intCfg.borderSize),
        tostring(unintCfg.borderTexture), tostring(unintCfg.borderSize),
    }, "|")
end

--- Geometry half of the re-skin: everything whose cost is a frame resize, a
--- re-anchor, a texture reload or a font load. Skipped when its signature is
--- unchanged (F-015).
---
--- @param force boolean pass true to rebuild regardless of the signature —
---        used after EnsureFrame builds fresh widgets, which start with no
---        geometry at all while the cached signature may still match.
local function ReskinStructure(inst, c, intCfg, unintCfg, force)
    local frame = inst.frame
    local isVertical = (c.orientation == "VERTICAL")
    local barLong, barThick = resolveBarSize(inst, c, isVertical)

    local sig = structureSignature(c, intCfg, unintCfg, barLong, barThick)
    if not force and inst.structureSig == sig then return end
    inst.structureSig = sig

    -- For HORIZONTAL: grow="LEFT" reverses fill (right-anchored texture grows
    -- right→left). For VERTICAL: grow="DOWN" reverses fill (top-anchored
    -- texture grows top→bottom). The default non-reverse case is
    -- HORIZONTAL/RIGHT (left→right) and VERTICAL/UP (bottom→top), which is
    -- what most cast bars use.
    local reverseFill
    if isVertical then
        reverseFill = (c.growDirection == "DOWN")
    else
        reverseFill = (c.growDirection == "LEFT")
    end

    if isVertical then
        frame:SetSize(barThick, barLong)
    else
        frame:SetSize(barLong, barThick)
    end

    -- Apply orientation + reverse-fill on both stacked StatusBars. Blizzard
    -- handles all the C-side texture growth math, so we never have to do
    -- per-frame arithmetic ourselves (which would error on secret
    -- CastingDuration values in combat).
    local barOrient = isVertical and "VERTICAL" or "HORIZONTAL"
    frame.bar.interruptible:SetOrientation(barOrient)
    frame.bar.uninterruptible:SetOrientation(barOrient)
    frame.bar.interruptible:SetReverseFill(reverseFill)
    frame.bar.uninterruptible:SetReverseFill(reverseFill)

    -- Icon position decides bar inset. "OFF" hides the icon entirely and
    -- gives the bar the full frame; "LEFT" / "RIGHT" inset the bar on the
    -- corresponding side. In VERTICAL orientation, LEFT is remapped to TOP
    -- and RIGHT to BOTTOM since literal left/right doesn't make sense for
    -- a tall bar.
    local iconPos  = c.iconPosition or "LEFT"
    local iconSize = math.max(0, c.iconSize or barThick)
    -- Cap iconSize at the bar's thickness (the perpendicular-to-fill
    -- dimension) so the icon never overflows the bar's short axis.
    if iconSize > barThick then iconSize = barThick end
    local showIcon = (iconPos ~= "OFF") and (iconSize > 0)

    frame.icon:ClearAllPoints()
    frame.bar:ClearAllPoints()
    if showIcon then
        frame.icon:Show()
        frame.icon:SetSize(iconSize, iconSize)
        if isVertical then
            if iconPos == "RIGHT" then
                -- BOTTOM in vertical mode.
                frame.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, iconSize)
            else
                -- TOP in vertical mode (default).
                frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, -iconSize)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, 0)
            end
        else
            if iconPos == "RIGHT" then
                frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      0, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -iconSize, 0)
            else
                frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
                frame.bar:SetPoint("TOPLEFT",     frame, "TOPLEFT",      iconSize, 0)
                frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  0, 0)
            end
        end
    else
        frame.icon:Hide()
        frame.bar:SetAllPoints(frame)
    end

    -- Spark — anchor to the fill edge of the interruptible bar's inner
    -- status texture. Both stacked bars receive identical
    -- SetMinMaxValues / SetValue calls every frame, so their textures are
    -- the same size; anchoring to either gives the same fill-edge position.
    -- The fill edge depends on orientation + reverseFill:
    --   * HORIZONTAL non-reverse  → texture grows L→R, fill edge = RIGHT
    --   * HORIZONTAL reverse      → texture grows R→L, fill edge = LEFT
    --   * VERTICAL   non-reverse  → texture grows B→T, fill edge = TOP
    --   * VERTICAL   reverse      → texture grows T→B, fill edge = BOTTOM
    -- The natural Blizzard spark is a tall vertical line; for VERTICAL
    -- orientation we rotate it 90° so it reads as a horizontal slash
    -- across the bar's fill edge.
    if c.showSpark ~= false then
        frame.spark:Show()
        frame.spark:ClearAllPoints()
        if isVertical then
            -- Spark sized to span the bar's thickness (now the
            -- horizontal axis); 90° rotation turns the texture's
            -- tall line into a horizontal slash across the fill edge.
            frame.spark:SetSize(barThick + 6, 20)
            if frame.spark.SetRotation then frame.spark:SetRotation(math.pi / 2) end
        else
            frame.spark:SetSize(20, barThick + 6)
            if frame.spark.SetRotation then frame.spark:SetRotation(0) end
        end
        local fill = frame.bar.interruptible:GetStatusBarTexture()
        if fill then
            local sparkAnchor
            if isVertical then
                sparkAnchor = reverseFill and "BOTTOM" or "TOP"
            else
                sparkAnchor = reverseFill and "LEFT"   or "RIGHT"
            end
            frame.spark:SetPoint("CENTER", fill, sparkAnchor, 0, 0)
        end
    else
        frame.spark:Hide()
    end

    -- Font for both labels (shared across states).
    local fontPath = Castbar.FetchFont(c.font)
    local fontSize = c.fontSize or 12
    local fontFlags = c.fontFlags
    if fontFlags == "NONE" or fontFlags == nil then fontFlags = "" end

    frame.nameText:SetFont(fontPath, fontSize, fontFlags)
    frame.timeText:SetFont(fontPath, fontSize, fontFlags)

    -- Position labels per their independent anchor settings. INSIDE_*
    -- variants pin the text to a bar edge (with a 4px breathing-room
    -- inset that the user's offsetX adds to). OUTSIDE_* variants float
    -- the text just past the bar edge so multi-line layouts can put
    -- name above and time below the bar by combining OUTSIDE positions
    -- with appropriate Y offsets. CENTER pins to bar center.
    anchorTextElement(frame.nameText, frame.bar,
        c.namePosition or "INSIDE_LEFT",  c.nameOffsetX or 0, c.nameOffsetY or 0)
    anchorTextElement(frame.timeText, frame.bar,
        c.timePosition or "INSIDE_RIGHT", c.timeOffsetX or 0, c.timeOffsetY or 0)

    if c.showName == false then frame.nameText:Hide() else frame.nameText:Show() end
    if c.showTime == false then frame.timeText:Hide() else frame.timeText:Show() end

    -- Per-state border backdrops. Visibility is folded into alpha switching in
    -- ApplyState; here we just configure the backdrop on each frame so it's
    -- ready when the curve unhides it. The tint is ReskinColors' job.
    applyBorderBackdrop(frame.borderInterruptible,   intCfg)
    applyBorderBackdrop(frame.borderUninterruptible, unintCfg)
end

--- Color half of the re-skin: per-state backgrounds, status-bar textures and
--- colors, border tints, and the shared time-text color. Always runs — this
--- is the half a color-picker drag legitimately needs at 50 ms intervals, and
--- it is a handful of widget calls.
---
--- nameText color is deliberately absent: it is per-state and applied in
--- ApplyState via curve-evaluated channels, because the interruptible flag
--- driving the choice can be secret in combat.
local function ReskinColors(inst, intCfg, unintCfg)
    local frame = inst.frame
    local unpack_ = Castbar.UnpackColor

    -- Per-state backgrounds (alpha-switched in ApplyState).
    frame.bgInterruptible:SetColorTexture(unpack_(intCfg.bgColor, 0, 0, 0, 0.5))
    frame.bgUninterruptible:SetColorTexture(unpack_(unintCfg.bgColor, 0, 0, 0, 0.5))

    -- Per-state bar textures + colors. Both bars share size/anchors so
    -- the spark anchor (to the interruptible inner status texture) is
    -- always at the correct fill edge regardless of which one is visible.
    frame.bar.interruptible:SetStatusBarTexture(
        Castbar.FetchStatusBarTexture(intCfg.statusBarTexture))
    frame.bar.interruptible:SetStatusBarColor(unpack_(intCfg.barColor, 1, 0.85, 0.05, 1))
    frame.bar.uninterruptible:SetStatusBarTexture(
        Castbar.FetchStatusBarTexture(unintCfg.statusBarTexture))
    frame.bar.uninterruptible:SetStatusBarColor(unpack_(unintCfg.barColor, 0.85, 0.1, 0.1, 1))

    -- timeText color stays shared (white).
    frame.timeText:SetTextColor(1, 1, 1, 1)

    applyBorderColor(frame.borderInterruptible,   intCfg)
    applyBorderColor(frame.borderUninterruptible, unintCfg)
end

--- Config-driven re-skin of the cast bar widgets. Recomputes orientation,
--- size, child anchors, fonts, backdrops, status-bar textures + colors,
--- spark rotation, and per-state border backdrops. Does NOT touch the
--- per-cast texture, spell name, or bar fill values — those are
--- Castbar:RenderCast's job.
---
--- Called from:
---   * OnConfigChanged (section == "castbar") — config flip
---   * OnGridLayout — auto-size needs to re-track the grid frame
---   * OnProfileChanged — profile swap
---   * ShowPreview — the placeholder bar still depends on config
---   * EnsureFrame — first skin of a freshly built frame (force = true)
---
--- This used to be Castbar:ApplyConfig and was called on every cast
--- start, recomputing ~40 widget calls per cast. CR-17 split it: cast
--- start now goes through Castbar:RenderCast (~6 widget calls) and
--- only re-skins on actual config changes. F-015 then split THIS into the
--- guarded structural half and the always-run color half above.
---
--- @param force boolean rebuild geometry even if its signature is unchanged.
---        EnsureFrame passes true: a fresh frame has no geometry yet, but the
---        instance may still carry a matching signature from a previous frame.
function Castbar:Reskin(inst, force)
    local frame = inst.frame
    if not frame then return end
    local c = NS.Units.Castbar(inst.unit)

    local intCfg   = self.StateConfig(c, "interruptible",   self.INT_FALLBACK)
    local unintCfg = self.StateConfig(c, "uninterruptible", self.UNINT_FALLBACK)

    ReskinStructure(inst, c, intCfg, unintCfg, force)
    ReskinColors(inst, intCfg, unintCfg)

    -- Apply the secret-bool-driven alpha + name color now so a config
    -- change that arrives mid-cast picks up the new per-state values.
    self:ApplyState(inst)

    -- Per-cast texture / name re-paint is the responsibility of
    -- Castbar:RenderCast. OnConfigChanged calls RenderCast(current)
    -- after Reskin when a cast is active so the texture / name pick
    -- up any structural change (iconSize toggling on / off,
    -- nameTruncate change, ...). See CR-17 for the split.
end

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- Pure functions with no frame dependency, published on the module the same way
-- Castbar.lua publishes its own helpers. Nothing inside the addon calls them
-- through these fields.
Castbar.StructureSignature = structureSignature
Castbar.ResolveBarSize     = resolveBarSize
