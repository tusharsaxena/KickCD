# Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. `Database:Init` calls `AceDB:New("KickCDDB", DEFAULTS)` with no third argument, so every character on the account starts on the shared `"Default"` profile. The user can opt into default / per-character / per-class / per-realm scope via the Profiles tab. See `core/Database.lua:508-512` for the rationale comment.

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

```lua
{
    dbVersion  = 1,              -- profile schema version. Database:MigrateProfile
                                 -- runs at Init and on profile change; the v1
                                 -- migrator is a no-op, but the scaffold lets a
                                 -- future schema change ship a migrator next to it.
    enabled    = true,
    locked     = true,           -- shared drag lock (icon grid + cast bar)
    scale      = 1.0,            -- icon grid master scale
    alpha      = 1.0,            -- icon grid master alpha
    debugLog   = false,          -- mirrors /kcd debug log; toggles internal-message logging.
                                 -- Lives in section "debug" (no listener) so toggling it
                                 -- doesn't trigger Cooldowns:Rebuild / IconGrid relayout.
    visibility = "target_casting_interruptible",
                                 --   "always" | "in_combat" | "target_casting"
                                 -- | "target_casting_interruptible" (default)
                                 -- addon-wide visibility mode honored by both
                                 -- the icon grid AND the cast bar; master enable
                                 -- still wins, and unlocked frames bypass the
                                 -- mode so users can drag them. The "_interruptible"
                                 -- variant uses KickCD.State.IsHostileUnitCasting
                                 -- as the show gate and KickCD.State.ApplyInterruptibleAlpha
                                 -- (SetAlphaFromBoolean on the secret notInterruptible
                                 -- bool) as a C-side filter mask, since the flag
                                 -- can't be compared in Lua under 12.0. The
                                 -- "in_combat" branch reads KickCD.State.inCombat
                                 -- (event-driven), not InCombatLockdown() (lags
                                 -- the regen events by a frame).

    icons = {
        -- Sizing
        primarySize, secondarySize, gap, zoom,
        -- Tooltip
        showTooltip,                           -- per-icon hover tooltip; only active while locked
        -- Layout (13 anchor points + 8 grow directions; orthogonal)
        anchor,                                -- "TOP_LEFT" | "RIGHT_MIDDLE" | ...
                                               --   13 tokens: 12 <SIDE>_<ALIGN>
                                               --   pairs + plain CENTER. Legacy
                                               --   "_CENTER" alignment tokens
                                               --   accepted via parseAnchor.
        secondaryGrow,                         -- "right_down" | "up_left" | ...
        secondaryRows, secondaryCols,
        secondaryOffsetX, secondaryOffsetY,
        -- Visual states (drives the alpha/tint/GCD-suppress curves in IconGrid)
        readyAlpha, cooldownAlpha, cooldownTint, suppressGCDSwipe,
        -- Border
        borderShow, borderTexture, borderColor, borderSize,
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
        anchorMode,                             -- "FREE" | "PRIMARY" (default PRIMARY)
        anchorPoint, castbarPoint,              -- 13-point anchor tokens
                                                -- (TOP_LEFT, TOP_MIDDLE, TOP_RIGHT,
                                                --  BOTTOM_LEFT, …, RIGHT_BOTTOM,
                                                --  CENTER) shared with Icons →
                                                -- Layout → Anchor point. Defaults
                                                -- TOP_LEFT / BOTTOM_LEFT. Legacy
                                                -- 9-point tokens (TOPLEFT, TOP, …)
                                                -- still pass through unchanged
                                                -- via Castbar's SETPOINT_MAP.
        anchorOffsetX, anchorOffsetY,           -- defaults 0 / 1 (1 px above primary)
        -- Orientation + fill direction; both StatusBar:SetOrientation /
        -- SetReverseFill so per-frame math stays C-side.
        orientation,                            -- "HORIZONTAL" | "VERTICAL"
        growDirection,                          -- "RIGHT" | "LEFT" | "UP" | "DOWN"
        autoSize,                               -- pull dim from icon grid each KickCD_GRID_LAYOUT
        -- Per-element text anchor (INSIDE_LEFT / INSIDE_RIGHT / CENTER /
        -- OUTSIDE_LEFT / OUTSIDE_RIGHT) plus pixel offset.
        namePosition, nameOffsetX, nameOffsetY,
        nameTruncate,                           -- max visible chars in spell name
                                                -- (0 = unlimited); truncated at byte
                                                -- length, with "…" tail. Short-circuits
                                                -- on secret-tainted names (passes through
                                                -- raw to SetText, which is C-side safe).
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

## Spell list lifecycle

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `KickCD.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

`Database:ResetAllSpells` wipes `db.profile.spells` and re-runs `BuildSpells` so every spec — not just the active one — gets the current addon defaults back. It's the helper behind the General → "Reset all settings" popup, `/kcd reset spells`, and `/kcd resetall`. The narrower per-spec reset (Spells panel's Defaults button + `KICKCD_RESET_SPELLS` popup, and `/kcd spells reset [CLASS SPEC]`) instead rebuilds only one `(class, spec)` slot.

The full lifecycle / recovery flow is in [scope.md](scope.md#spell-list-lifecycle-and-recovery).
