# Saved variables

Single saved-variable: `KickCDDB`, an AceDB-3.0 store. `Database:Init` calls `AceDB:New("KickCDDB", DEFAULTS, true)` — the `true` third argument expands to `"Default"` per AceDB-3.0, so every character on the account starts on the shared `"Default"` profile. (Omitting the third argument falls back to the per-character profile, which contradicts the docs and was the source of "every fresh character lands on its own profile" reports.) The user can opt into default / per-character / per-class / per-realm scope via the Profiles tab. See the rationale comment on the `AceDB:New` call in `core/Database.lua` for the in-tree note.

## `db.global` — account-wide scope

Alongside the profile store, AceDB carries a `db.global` scope (addon-wide, shared by every character on the account regardless of active profile):

```lua
db.global = {
    schemaVersion = <int>,       -- addon-wide schema version (CURRENT_DB_VERSION = 2).
                                 -- Database:MigrateProfile reads and writes
                                 -- db.global.schemaVersion, looping migrations[v]
                                 -- forward one step at a time until it reaches
                                 -- CURRENT_DB_VERSION. A legacy account that still
                                 -- carries a per-profile dbVersion field is adopted
                                 -- once — detection keys on the presence of that old
                                 -- per-profile field, because AceDB's defaults merge
                                 -- backfills db.global.schemaVersion on first access.
                                 -- v1 -> v2 (migrations[1]) runs Database:FoldLegacyUnits
                                 -- then bumps schemaVersion to 2 (see "units.* migration"
                                 -- below).
}
```

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

```lua
{
    enabled    = true,
    locked     = true,           -- shared drag lock (icon grid + cast bar)
    scale      = 1.0,            -- icon grid master scale
    alpha      = 1.0,            -- icon grid master alpha
    visibility = "target_casting_interruptible",
                                 --   "always" | "in_combat" | "target_casting"
                                 -- | "target_casting_interruptible" (default)
                                 -- addon-wide visibility mode honored by both
                                 -- the icon grid AND the cast bar; master enable
                                 -- still wins, and unlocked frames bypass the
                                 -- mode so users can drag them. The "_interruptible"
                                 -- variant uses NS.State.IsHostileUnitCasting
                                 -- as the show gate and NS.State.ApplyInterruptibleAlpha
                                 -- (SetAlphaFromBoolean on the secret notInterruptible
                                 -- bool) as a C-side filter mask, since the flag
                                 -- can't be compared in Lua under 12.0. The
                                 -- "in_combat" branch reads NS.State.inCombat
                                 -- (event-driven), not InCombatLockdown() (lags
                                 -- the regen events by a frame).

    -- Per-unit widgets (target/focus dual tracking). Appearance (icons/
    -- castbar) is duplicated per unit; NS.Units is the single place that
    -- resolves "focus.link" into "read target's appearance instead" — see
    -- core/Units.lua and the "units.*" section below. enabled/anchors/
    -- label.text stay per-unit even while linked.
    units = {
        target = { enabled, link = false, label = { show, text },
                   anchors = { icons = {...}, castbar = {...} },
                   icons = { ... }, castbar = { ... } },  -- shapes below
        focus  = { enabled, link,          label = { show, text },
                   anchors = { icons = {...}, castbar = {...} },
                   icons = { ... }, castbar = { ... } },
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

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `NS.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

`Database:ResetAllSpells` wipes `db.profile.spells` and re-runs `BuildSpells` so every spec — not just the active one — gets the current addon defaults back. It's the helper behind the General → "Reset all settings" popup, `/kcd reset spells`, and `/kcd resetall`. The narrower per-spec reset (Spells panel's Defaults button + `KICKCD_RESET_SPELLS` popup, and `/kcd spells reset [CLASS SPEC]`) instead rebuilds only one `(class, spec)` slot.

The full lifecycle / recovery flow is in [scope.md](scope.md#spell-list-lifecycle-and-recovery).

## `units.<unit>` shape

`units.target` and `units.focus` (`NS.Units.LIST`) each carry the full per-widget config that used to live at the profile's top level:

```lua
units[unit] = {
    enabled = true|false,    -- per-unit sub-enable; master `enabled` still wins (NS.Units.IsEnabled)
    link    = false|true,    -- target is always false (never linked); focus defaults true
                              -- (mirror target's icons/castbar live — see core/Units.lua)
    label = { show = false, text = "Target"|"Focus" },  -- identity FontString above the
                              -- grid + cast bar; per-unit even while linked
    anchors = {
        icons   = { point, relativePoint, x, y },  -- vs UIParent
        castbar = { point, relativePoint, x, y },  -- cast bar in FREE anchor mode
    },
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
        enabled,                                -- sub-module enable (master + unit enable still win)
        width, height, iconSize, iconPosition,  -- "LEFT" | "RIGHT" | "OFF"
        showSpark, showName, showTime,
        font, fontSize, fontFlags,
        -- Anchor: FREE = drag-positioned (saved to anchors.castbar);
        -- PRIMARY = SetPoint to this unit's icon grid primary icon button at
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
        autoSize,                               -- pull dim from this unit's icon grid each
                                                -- Ka0s_KickCD_GRID_LAYOUT (filtered on payload.unit)
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
}
```

`icons` / `castbar` are structurally identical for `target` and `focus` (both seeded from the same `ICONS_DEFAULT` / `CASTBAR_DEFAULT` tables in `core/Database.lua`) — the only per-unit differences in `DEFAULT_PROFILE` are `enabled` (focus defaults `false`), `link` (focus defaults `true`), `label.text`, and each unit's default screen offset in `anchors` (focus is seeded 80px below target so the two grids don't overlap on first enable).

**Link resolution lives in `core/Units.lua` (`NS.Units`), not scattered across the widget modules.** `IconGrid` and `Castbar` never read `db.profile.units.<unit>.icons` / `.castbar` directly for appearance — they call `NS.Units.Icons(unit)` / `NS.Units.Castbar(unit)`, which resolve to `units.target.icons` / `.castbar` whenever `units.focus.link == true` (target is never linked). Position (`anchors`) and `label.text` are read straight off the unit's own config via `NS.Units.Anchor` / `.Label` — they are NOT link-resolved, so a linked focus grid still drags independently of target and keeps showing "Focus" if its label is on. `NS.Units.CopyStyling(from, to)` deep-copies `icons`/`castbar` one-time and flips `link = false`, backing the settings panel's "Copy styling from Target" button.

## Migration: folding legacy `icons`/`castbar`/`anchors` into `units.target`

Pre-dual-tracking profiles stored `db.profile.icons`, `db.profile.castbar`, and `db.profile.anchors` at the top level (no `units` table at all). `Database:FoldLegacyUnits(db)` — run unconditionally at the start of both `Database:Init` and `Database:OnProfileChanged` (before `MigrateProfile`) — moves those three tables into `db.profile.units.target.{icons,castbar,anchors}` and clears the old top-level keys.

It is **shape-driven, not version-gated**: it checks `p.icons == nil and p.castbar == nil and p.anchors == nil` and returns immediately (no-op) when all three are already absent — which is true for both a fresh v2 install and an already-migrated account. Version-gating on `db.global.schemaVersion` was considered and rejected for the same reason the account-adoption code above avoids trusting a bare `schemaVersion == nil` check: AceDB's `copyDefaults` rawsets `db.global.schemaVersion` to `CURRENT_DB_VERSION` the moment `db.global` is first touched, which would make a legacy account that never had a chance to run the migrator look "already current" and silently strand its customised icons/castbar/anchors data under the old top-level keys forever. Keying on the presence of the old tables instead detects exactly (and only) the accounts that carry legacy data, regardless of what `schemaVersion` claims.

The `migrations[1]` step (`Database:MigrateProfile`'s registered v1→v2 migrator) also calls `FoldLegacyUnits` and bumps `db.global.schemaVersion` to 2, so the fold happens exactly once from the schema-version path too — `FoldLegacyUnits`'s own idempotency means running it from both call sites is safe, not redundant-in-a-bad-way. `CURRENT_DB_VERSION = 2` in `core/Database.lua` marks the `units.*` restructure as the addon's second schema generation (v1 was the pre-migration baseline; the v1→v2 migrator was a no-op).

**Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): restructuring `DEFAULT_PROFILE` (a rename/nest, not a pure addition) departs from a "profile shape never changes shape, only grows" expectation some Ace3-based addons hold — it was necessary because target/focus each need independently-customisable `icons`/`castbar`, and the alternative (flat `icons`, `focusIcons`, `castbar`, `focusCastbar`, …) doesn't scale to a third unit later and duplicates the anchor/label bookkeeping. The shape-driven (not version-gated) migration is the mitigation that makes the restructure safe for existing installs.
