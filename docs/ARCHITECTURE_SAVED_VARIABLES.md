# Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. Default scope is per-character (the `true` arg in `AceDB:New`); the user can switch to default / per-class / per-realm via the Profiles tab.

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

```lua
{
    enabled  = true,
    locked   = true,           -- icon grid drag lock
    scale    = 1.0,            -- master scale
    alpha    = 1.0,            -- master alpha
    debugLog = false,          -- mirrors /kcd debug log; toggles internal-message logging

    icons = {
        -- Sizing
        primarySize, secondarySize, gap, zoom,
        -- Layout (12 anchor points + 8 grow directions; orthogonal)
        anchor,                                -- "TOP_LEFT" | "RIGHT_CENTER" | ...
        secondaryGrow,                         -- "right_down" | "up_left" | ...
        secondaryRows, secondaryCols,
        secondaryOffsetX, secondaryOffsetY,
        -- Visual states (drives the alpha/tint curves in IconGrid)
        readyAlpha, cooldownAlpha, cooldownTint, suppressGCDSwipe,
        -- Border
        borderShow, borderColor, borderSize,
        -- Annotations
        showCooldownText, cooldownTextFont, cooldownTextSize, cooldownTextFlags,
        showCharges,
    },
    anchors = {
        icons = { point, relativePoint, x, y },   -- always relative to UIParent
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
