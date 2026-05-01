# Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. Default scope is per-character (the `true` arg in `AceDB:New`); the user can switch to default / per-class / per-realm via the Profiles tab.

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

```lua
{
    enabled    = true,
    locked     = true,           -- shared drag lock (icon grid + cast bar)
    scale      = 1.0,            -- icon grid master scale
    alpha      = 1.0,            -- icon grid master alpha
    debugLog   = false,          -- mirrors /kcd debug log; toggles internal-message logging
    visibility = "always",       -- "always" | "in_combat" | "target_casting"
                                 --   | "target_casting_interruptible"
                                 -- addon-wide visibility mode honored by both
                                 -- the icon grid AND the cast bar; master enable
                                 -- still wins, and unlocked frames bypass the
                                 -- mode so users can drag them.

    icons = {
        -- Sizing
        primarySize, secondarySize, gap, zoom,
        -- Tooltip
        showTooltip,                           -- per-icon hover tooltip; only active while locked
        -- Layout (12 anchor points + 8 grow directions; orthogonal)
        anchor,                                -- "TOP_LEFT" | "RIGHT_CENTER" | ...
        secondaryGrow,                         -- "right_down" | "up_left" | ...
        secondaryRows, secondaryCols,
        secondaryOffsetX, secondaryOffsetY,
        -- Visual states (drives the alpha/tint/GCD-suppress curves in IconGrid)
        readyAlpha, cooldownAlpha, cooldownTint, suppressGCDSwipe,
        -- Border
        borderShow, borderColor, borderSize,
        -- Annotations
        showCooldownText, cooldownTextFont, cooldownTextSize, cooldownTextFlags,
        showCharges,
        -- Per-slot ready glow (LibCustomGlow). Trigger ∈
        --   { never, always, target_casting, target_casting_interruptible }
        -- Type ∈ { button, proc, pixel, autocast }.
        primaryGlowTrigger,   primaryGlowType,   primaryGlowColor,
        secondaryGlowTrigger, secondaryGlowType, secondaryGlowColor,
    },

    castbar = {
        enabled,                                -- sub-module enable (master enable still wins)
        width, height, iconSize, iconPosition,  -- "LEFT" | "RIGHT" | "OFF"
        showSpark, showName, showTime,
        font, fontSize, fontFlags,
        -- Anchor: FREE = drag-positioned (saved to anchors.castbar);
        -- PRIMARY = SetPoint to the icon grid's primary icon button at
        -- (anchorPoint, castbarPoint, anchorOffsetX, anchorOffsetY).
        anchorMode,                             -- "FREE" | "PRIMARY"
        anchorPoint, castbarPoint,              -- 9-point anchors (TOPLEFT, TOP, …)
        anchorOffsetX, anchorOffsetY,
        -- Orientation + fill direction; both StatusBar:SetOrientation /
        -- SetReverseFill so per-frame math stays C-side.
        orientation,                            -- "HORIZONTAL" | "VERTICAL"
        growDirection,                          -- "RIGHT" | "LEFT" | "UP" | "DOWN"
        autoSize,                               -- pull dim from icon grid each KickCD_GRID_LAYOUT
        -- Per-element text anchor (INSIDE_LEFT / INSIDE_RIGHT / CENTER /
        -- OUTSIDE_LEFT / OUTSIDE_RIGHT) plus pixel offset.
        namePosition, nameOffsetX, nameOffsetY,
        timePosition, timeOffsetX, timeOffsetY,
        -- Per-state appearance (curve-switched on the cast's secret
        -- notInterruptible bool via C_CurveUtil.EvaluateColorValueFromBoolean).
        interruptible   = { statusBarTexture, barColor, bgColor,
                            nameTextColor, borderShow, borderTexture,
                            borderColor, borderSize },
        uninterruptible = { statusBarTexture, barColor, bgColor,
                            nameTextColor, borderShow, borderTexture,
                            borderColor, borderSize },
    },

    anchors = {
        icons   = { point, relativePoint, x, y },  -- icon grid (always vs UIParent)
        castbar = { point, relativePoint, x, y },  -- cast bar in FREE anchor mode
    },
    spells = {
        [CLASS] = {
            [SPEC] = {
                { spellID, category, enabled }, ...
            },
        },
    },
}
```

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `KickCD.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.
