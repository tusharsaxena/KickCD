# Saved variables

Two saved-variables are declared in `KickCD.toc`: **`KickCDDB`**, the AceDB-3.0 store described below, and **`KickCDPerfDB`**, which is owned entirely by `LibKa0s-Perf-1.0` (wired in `core/PerfSetup.lua`) and holds the `/kcd perf` A/B capture records. Nothing in this addon reads or writes `KickCDPerfDB` directly — the library owns its shape, and it is diagnostics data, not configuration: deleting it loses captures and nothing else. It is named non-setting state under `architecture-§5`, with its owner and writer in [ARCHITECTURE.md → Settings schema](ARCHITECTURE.md#settings-schema).

`KickCDDB` is an AceDB-3.0 store. `Database:Init` calls `AceDB:New("KickCDDB", DEFAULTS, true)` — the `true` third argument expands to `"Default"` per AceDB-3.0, so every character on the account starts on the shared `"Default"` profile. (Omitting the third argument falls back to the per-character profile, which contradicts the docs and was the source of "every fresh character lands on its own profile" reports.) The user can opt into default / per-character / per-class / per-realm scope via the Profiles tab. See the rationale comment on the `AceDB:New` call in `core/Database.lua` for the in-tree note.

## `db.global` — account-wide scope

Alongside the profile store, AceDB carries a `db.global` scope (addon-wide, shared by every character on the account regardless of active profile):

```lua
db.global = {
    schemaVersion = <int>,       -- addon-wide schema version (NS.SCHEMA_VERSION = 8).
                                 -- DECLARED DEFAULT 0 (savedvariables-§1): AceDB's
                                 -- removeDefaults strips a stored value equal to its
                                 -- default, and backfills a default onto a legacy
                                 -- account, so a current-version default would never
                                 -- persist and would mask a legacy account as current.
                                 -- Database:MigrateProfile owns the stamp: a stored 0
                                 -- starts at v1 (every step is idempotent against a
                                 -- default profile), each migrations[v] step is a pure
                                 -- function run under pcall, and the stamp advances to
                                 -- v + 1 only past a step that returned. A step that
                                 -- raises prints one "settings migration vN -> vN+1
                                 -- failed" line and stops the walk at the last
                                 -- completed step. A legacy account that still carries
                                 -- a per-profile dbVersion field is adopted once.
                                 -- v1 -> v2 (migrations[1]) runs Database:FoldLegacyUnits
                                 -- (see "units.* migration" below). v2 -> v3
                                 -- (migrations[2]) runs Database:MigrateSpecKeys (see
                                 -- the localized-spec-name migration below). v3 -> v4
                                 -- (migrations[3]) runs Database:MigrateColorShape (see
                                 -- the color-shape migration below). v4 -> v5
                                 -- (migrations[4]) runs Database:MigrateFontFlags (see
                                 -- the font-flag migration below). v5 -> v6
                                 -- (migrations[5]) runs Database:MigrateHudSkin (see
                                 -- the one-time HUD style reset below). v6 -> v7
                                 -- (migrations[6]) runs Database:MigrateFlagsFromSkin,
                                 -- v7 -> v8 (migrations[7]) Database:MigrateSkinFontPicks
                                 -- (see the two steps after the HUD style reset).
    minimap = {                  -- LibDBIcon-1.0's OWN table (launcher-§3). The
        hide = false,            -- `hide` boolean is the `Minimap button` row's;
    },                           -- `minimapPos` is the library's, written when the
                                 -- player drags the button, and carries no row.
                                 -- GLOBAL rather than profile so a profile switch
                                 -- does not move a player's buttons and
                                 -- `Reset all settings` -- a profile reset by
                                 -- definition -- cannot un-hide one they hid.
}
```

**`minimap` moved no stored path and bumped no `schemaVersion`.** This addon has never stored a
minimap table, so the declared default above is simply what materializes it (`architecture-§5`) --
nothing seeds or backfills it by hand. (The collection's one `profile` -> `global` move is Multi
Meters'.) The row's label says *shown* while the stored boolean says *hidden*, so the inversion
lives on the row's own `get`/`set` (wired in `settings/General.lua`), which the addon's single write seam calls; see
[settings-panel.md](settings-panel.md).

Profile shape (see `defaults/Profile.lua` `DEFAULT_PROFILE`, published as `NS.C` / `NS.DEFAULT_PROFILE`):

```lua
{
    enabled    = true,
    locked     = false,          -- shared drag lock (icon grid + cast bar)
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

    -- The skin this addon wears (skinning-§2: per addon, per profile;
    -- core/SkinSetup.lua). See "skin.*" below.
    skin = {
        source      = "ka0s",        -- "ka0s" | "eui" (EllesmereUI)
        skin        = "ka0s",        -- a registered skin key; "ka0s" is Ka0s Default
        ignorePanel = true,          -- the Scope: the settings pages stay the client's
        ignoreFonts = false,         -- the Scope: every string keeps its own face, HUD too
        font        = "",            -- an LSM font key over the skin's, "" = the skin's own
        texture     = "",            -- an LSM statusbar key over the skin's, "" = the skin's own
        outline     = "hud",         -- the Font outline: "hud" text only | "all" text | "off"
        pickerSeen  = false,         -- the first-run skin picker was closed on this profile
        hudReset    = false,         -- the one-time HUD style reset's record (no schema row)
        flagsReset  = false,         -- the one-time Font flags step's record (no schema row)
        fontPicksKept = false,       -- the one-time picked-face step's record (no schema row)
    },

    -- Per-unit widgets (target/focus dual tracking). Appearance (icons/
    -- castbar) is duplicated per unit; NS.Units is the single place that
    -- resolves "focus.link" into "read target's appearance instead" — see
    -- core/Units.lua and the "units.*" section below. enabled/anchors/
    -- label.text are read per-unit even while linked; label.show and
    -- label.style follow the link like icons/castbar do.
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
            [specID] = {
                { spellID, category, enabled }, ...
            },
        },
    },
}
```

## `skin.*` — the skin this addon wears

Eight of the eleven keys are schema rows on the General page's Skin tab (`settings/General.lua`), every
one `skipRender` and drawn by the library's `O.AppearanceTab`, so `/kcd get|set skin.<key>` validates
them (`skin.skin` refuses a key no skin registered) and Reset all settings, a profile reset, takes them
back to the defaults above. The General page's own Defaults leaves them alone (the schema seam's
`resetExempt`): it restores Master controls. `skin.font` and `skin.texture` are free text rather than a
dropdown, because a media pack may register its keys after the settings files load. `skin.outline`
(LibKa0s v1.82.0, Skin minor 9, ruling D-06) is the Skin tab's Font outline, one of the library's
three modes, `hud` by default (`all` before LibKa0s v1.83.0, ruling D-10: a stored mode stays, nothing migrates); every Font flags row left at From skin follows it, and the write
seam stores it from `media.outline` (the tab's dropdown and another addon's copy). Each row's
`onChange` moves only its own half of the applied skin through `LibKa0s-Skin-1.0`
([ARCHITECTURE.md → Skins](ARCHITECTURE.md#skins)). The defaults are Ka0s Default from both halves,
so a profile that never opened the Skin tab wears Ka0s Default; `pickerSeen` is false on every profile,
old and new (owner ruling O3), so the first-run skin picker shows once on each. `skin.hudReset` is the
one-time HUD style reset's record, `skin.flagsReset` the Font flags step's and `skin.fontPicksKept`
the picked-face step's, none with a row (see the v5 → v6, v6 → v7 and v7 → v8 migrations below). Adding the block
moved no stored path and needed no step of its own: AceDB merges the declared defaults into every
profile.

## Spell list lifecycle

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `NS.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

`Database:ResetAllSpells` wipes `db.profile.spells` and re-runs `BuildSpells` so every spec — not just the active one — gets the current addon defaults back. It backs `/kcd spells resetall`. It is **no longer on the global reset's path**: `/kcd resetall` and the General → "Reset all settings" popup are a **profile reset** now (`options-ui-§12`), and `db.profile.spells` goes with the profile — `Database:OnProfileChanged` re-seeds it through `BuildSpells` on the way back, which is the same path a profile switch takes. The narrower per-spec reset (Spells panel's Defaults button + `KICKCD_RESET_SPELLS` popup, and `/kcd spells reset [CLASS SPEC]`) instead rebuilds only one `(class, spec)` slot, through `Database:ResetSpellList`. It shares `BuildSpells`' seed routine, so resetting a spec of the player's own class re-appends their racial just as `resetall` does. Before the two resets shared that routine, both dropped it.

The full lifecycle / recovery flow is in [scope.md](scope.md#spell-list-lifecycle-and-recovery).

## `units.<unit>` shape

`units.target` and `units.focus` (`NS.Units.LIST`) each carry the full per-widget config that used to live at the profile's top level:

```lua
units[unit] = {
    enabled = true|false,    -- per-unit sub-enable; master `enabled` still wins (NS.Units.IsEnabled)
    link    = false|true,    -- target is always false (never linked); focus defaults true
                              -- (mirror target's icons/castbar live — see core/Units.lua)
    label = { show = true, text = "Target"|"Focus",    -- identity FontString rendered by
                              -- modules/UnitLabel.lua. Both are stored per-unit, but
                              -- only `text` is READ per-unit (NS.Units.Label(unit));
                              -- `show` follows the link (NS.Units.LabelShow(unit))
              style = { attach, point, relPoint, offsetX, offsetY,
                        justifyH, justifyV, rotation, font, size, flags,
                        shadow, color, useClassColor } },
                              -- style is link-resolved (NS.Units.LabelStyle(unit) —
                              -- a linked focus reads target's style); see the
                              -- "units.<unit>.label.style" section below
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
        -- Visual states (drives the alpha/tint/GCD-suppress curves in IconGrid).
        -- useClassColorCooldownTint is the tint's class-color companion and it
        -- feeds the CURVE, so it is part of curveSignature -- see options-ui-§17.
        readyAlpha, cooldownAlpha, cooldownTint, useClassColorCooldownTint,
        suppressGCDSwipe,
        -- Border. The composed block (options-ui-§16); borderTexture keeps its
        -- shipped name while the composer calls that leaf `borderStyle`.
        borderShow, borderTexture, borderColor, useClassColorBorder, borderSize,
        borderTextureFromSkin,   -- "Use the skin's border": style AND thickness
                                 -- follow the skin's icon family (see the v5 -> v6
                                 -- migration below); default true
        -- Annotations. chargesOffsetX/Y are the charges badge's inset from the
        -- icon's bottom-right corner, in pixels (positive X = right, positive
        -- Y = up). They WERE the hardcoded `-2, 2` in modules/IconGrid_Render's
        -- SetPoint call; the defaults are those exact numbers, so an untouched
        -- profile draws the badge exactly where it always did, and the render
        -- path clamps to +/-32 because a SavedVariable can hold anything.
        -- The countdown's typography is the composed font block (options-ui-§16),
        -- so cooldownTextColor / useClassColorCooldownText / cooldownTextShadow
        -- arrived with it; every one of them keeps this addon's shipped leaf name
        -- through the composer's `keys` map.
        showCooldownText, cooldownTextFont, cooldownTextSize, cooldownTextFlags,
        cooldownTextColor, useClassColorCooldownText, cooldownTextShadow,
        cooldownTextFontFromSkin,  -- "Use the skin's font" (hud.font); default true
        showCharges, chargesOffsetX, chargesOffsetY,
        -- Per-slot ready glow (LibCustomGlow). Trigger ∈
        --   { never, always, target_casting, target_casting_interruptible }
        -- Type ∈ { button, proc, pixel, autocast }.
        -- Each glow color is an H.ColorPair, so each carries its own
        -- useClassColor* companion immediately after it (options-ui-§17).
        primaryGlowTrigger,   primaryGlowType,   primaryGlowColor,
        useClassColorPrimaryGlowColor,
        secondaryGlowTrigger, secondaryGlowType, secondaryGlowColor,
        useClassColorSecondaryGlowColor,
        -- Each slot's per-style knobs, <slot> = primary | secondary
        -- (core/Constants.lua's Const.GLOW_KNOBS: range / step, default).
        -- Only the slot's chosen style's knobs are read; the render clamps
        -- each into its range and reads a wrong-typed value as the default.
        --   button:   <slot>GlowButtonFrequency    0.05-2 / 0.05,  0.25
        --   proc:     <slot>GlowProcDuration       0.25-3 / 0.25,  1
        --             <slot>GlowProcStartAnim      bool,           true
        --   pixel:    <slot>GlowPixelLines         1-20 / 1,       8
        --             <slot>GlowPixelFrequency     0.05-2 / 0.05,  0.25
        --             <slot>GlowPixelLength        0-20 / 1,       0 (automatic)
        --             <slot>GlowPixelThickness     1-6 / 1,        1
        --             <slot>GlowPixelBorder        bool,           true
        --   autocast: <slot>GlowAutocastParticles  1-12 / 1,       4
        --             <slot>GlowAutocastFrequency  0.05-2 / 0.05,  0.125
        --             <slot>GlowAutocastScale      0.5-3 / 0.1,    1
        --   pixel, autocast, proc:
        --             <slot>GlowXOffset, <slot>GlowYOffset  -10-10 / 1, 0
    },
    castbar = {
        enabled,                                -- sub-module enable (master + unit enable still win)
        width, height, iconSize, iconPosition,  -- "LEFT" | "RIGHT" | "OFF"
        showSpark, showName, showTime,
        -- The composed font block (options-ui-§16). fontShadow, textColor and
        -- useClassColorText arrived with it; textColor governs the CAST TIME
        -- text (the spell name's color is per-state, below) and is labeled
        -- "Cast time color" in the panel for that reason.
        font, fontSize, fontFlags, fontShadow,
        textColor, useClassColorText,
        fontFromSkin,                           -- "Use the skin's font" for both texts
                                                -- (hud.font); default true
        -- Anchor: FREE = drag-positioned (saved to anchors.castbar);
        -- PRIMARY = SetPoint to this unit's icon grid primary icon button at
        -- (anchorPoint, castbarPoint, anchorOffsetX, anchorOffsetY).
        anchorMode,                             -- "FREE" | "PRIMARY" (default PRIMARY)
        anchorPoint, castbarPoint,              -- 13-point anchor tokens
                                                -- (TOP_LEFT, TOP_MIDDLE, TOP_RIGHT,
                                                --  BOTTOM_LEFT, …, RIGHT_BOTTOM,
                                                --  CENTER) shared with Units > Icons
                                                -- > Size and layout > Primary icon
                                                -- anchor point. Defaults
                                                -- BOTTOM_LEFT / TOP_LEFT. Legacy
                                                -- 9-point tokens (TOPLEFT, TOP, …)
                                                -- still pass through unchanged
                                                -- via Castbar's SETPOINT_MAP.
        anchorOffsetX, anchorOffsetY,           -- defaults 0 / -1 (1 px below primary)
        -- Orientation + fill direction; both StatusBar:SetOrientation /
        -- SetReverseFill so per-frame math stays C-side.
        orientation,                            -- "HORIZONTAL" | "VERTICAL"
        growDirection,                          -- "RIGHT" | "LEFT" | "UP" | "DOWN"
        autoSize,                               -- pull dim from this unit's icon grid each
                                                -- Ka0s_KickCD_GridLayout (filtered on payload.unit)
        -- Per-element text anchor (INSIDE_LEFT / INSIDE_RIGHT / CENTER /
        -- OUTSIDE_LEFT / OUTSIDE_RIGHT) plus pixel offset.
        namePosition, nameOffsetX, nameOffsetY,
        nameTruncate,                           -- max visible chars in spell name
                                                -- (0 = unlimited); counted in UTF-8
                                                -- characters, with "…" tail. Short-circuits
                                                -- on secret-tainted names (passes through
                                                -- raw to SetText, which is C-side safe).
        timePosition, timeOffsetX, timeOffsetY,
        -- Per-state appearance (curve-switched on the cast's secret
        -- notInterruptible bool via C_CurveUtil.EvaluateColorValueFromBoolean).
        -- Each per-state table is one composed bar group plus two composed
        -- swatch pairs plus one composed border group (options-ui-§16/§17), so
        -- every color carries a useClassColor* companion and the bar carries
        -- barAlpha -- which folds into the per-state alpha CURVE in
        -- modules/Castbar.lua's ApplyState, never a SetAlpha of its own.
        -- Each state's statusBarTextureFromSkin ("Use the skin's texture",
        -- bar.texture) and borderTextureFromSkin ("Use the skin's border", the
        -- icon family: icon.borderStyle and icon.borderSize, KC-A1) default true.
        interruptible   = { statusBarTexture, barColor, useClassColorBar,
                            barAlpha, statusBarTextureFromSkin,
                            bgColor, useClassColorBgColor,
                            nameTextColor, useClassColorNameTextColor,
                            borderShow, borderTexture,
                            borderColor, useClassColorBorder, borderSize,
                            borderTextureFromSkin },
        uninterruptible = { statusBarTexture, barColor, useClassColorBar,
                            barAlpha, statusBarTextureFromSkin,
                            bgColor, useClassColorBgColor,
                            nameTextColor, useClassColorNameTextColor,
                            borderShow, borderTexture,
                            borderColor, useClassColorBorder, borderSize,
                            borderTextureFromSkin },
    },
}
```

`icons` / `castbar` are structurally identical for `target` and `focus` (both seeded from the same `ICONS_DEFAULT` / `CASTBAR_DEFAULT` tables in `defaults/Profile.lua`) — the only per-unit differences in `DEFAULT_PROFILE` are `enabled` (both default `true`), `link` (focus defaults `true`), `label.text`, and each unit's default screen offset in `anchors` (target seeds `y = 120`, focus seeds `y = 260` — Focus sits 140px above Target so the two grids don't overlap on first enable; this leaves roughly 10px of clearance between the Focus cast-timer bottom and the Target label top, a computed estimate from default element sizes that may need a small nudge once rendered).

**Link resolution lives in `core/Units.lua` (`NS.Units`), not scattered across the widget modules.** `IconGrid` and `Castbar` never read `db.profile.units.<unit>.icons` / `.castbar` directly for appearance — they call `NS.Units.Icons(unit)` / `NS.Units.Castbar(unit)`, which resolve to `units.target.icons` / `.castbar` whenever `units.focus.link == true` (target is never linked). Position (`anchors`) and `label.text` are read straight off the unit's own config via `NS.Units.Anchor` / `.Label` — they are NOT link-resolved, so a linked focus grid still drags independently of target and keeps showing its own "Focus" identity text. `label.show` is the exception among the label fields: it resolves through `NS.Units.LabelShow`, so turning target's label off also hides a linked focus's. `NS.Units.CopyStyling(from, to)` copies every schema row under `icons`/`castbar`/`label.style` plus `label.show` (it has to, or unlinking would revive focus's stale independent `show`), then `link = false`, as one all-or-nothing `Store.SetMany` batch through the schema seam (`LibKa0s-Schema-1.0`). `label.text` is deliberately not copied. It backs the Units page band's "Copy from Target" button. `units.focus.link` is itself a schema row (stamped to General, `skipRender`, drawn as *Link to Target* in the Units page's band; default `true`), so `/kcd get|set|list|reset` reach it. `units.target.link` has no row and stays `false`.

### `units.<unit>.label.style` shape

```lua
units[unit].label.style = {
    attach   = "castbar"|"icons",    -- which widget frame the label anchors to
    point    = "BOTTOM",             -- the label's own SetPoint anchor point
    relPoint = "TOP",                -- the attach frame's point it anchors to
    offsetX  = 0, offsetY  = 12,     -- pixel offset from that point
    justifyH = "CENTER", justifyV = "MIDDLE",
    rotation = 0,                     -- degrees; FontString:SetRotation (radians internally)
    font     = "Friz Quadrata TT",   -- LSM font name
    size     = 14,
    flags    = "@skin",               -- "@skin" (From skin, the default since LibKa0s
                                      --    v1.82.0: the Font outline decides) | "" |
                                      --    "OUTLINE" | "THICKOUTLINE" | "MONOCHROME"
                                      --    | "OUTLINE, MONOCHROME". The EMPTY STRING
                                      --    is "None" and is a real stored value; the
                                      --    pre-v5 token for it was "NONE"
    shadow   = false,                 -- drop shadow behind the text
    fontFromSkin = true,              -- "Use the skin's font" (hud.font): while true the
                                      --    label draws the skin's face, `font` is kept
    color    = { r = 1, g = 0.82, b = 0, a = 1 },  -- label text color (Blizzard gold)
    useClassColor = false,            -- the color's class-color companion. UNIT-scoped:
                                      --    a label names the unit it is drawn beside, and
                                      --    a linked focus still resolves on FOCUS
}
```

`label.style` is **single-sourced** from one `LABELSTYLE_DEFAULT` table in `defaults/Profile.lua`, deep-copied into both `units.target.label.style` and `units.focus.label.style` — Target and Focus ship with an IDENTICAL label appearance out of the box (unlike `icons`/`castbar`, which are also structurally identical but seeded from their own `ICONS_DEFAULT`/`CASTBAR_DEFAULT`, this is the same pattern applied to label styling). `label.style` **is** link-resolved (`NS.Units.LabelStyle(unit)`, resolving to `units.target.label.style` for a linked focus), and so is `label.show` (`NS.Units.LabelShow(unit)`) — only `text` stays per-unit (`NS.Units.Label(unit)`, never link-resolved), so a linked Focus mirrors Target's font/position/rotation/color *and* its on/off state while still showing its own "Focus" text.

**Visibility:** the label's holder frame is created on `UIParent` but `SetParent`'d onto the unit's **icon grid** (`IconGrid:GetGridFrame(unit)`, falling back to the attach frame only if the grid isn't up yet) on every `Apply`, while `SetPoint`-anchoring to the resolved attach frame for position alone. Parenting to the grid — not the attach frame — means the label inherits the grid's shown state + effective alpha, so it follows the addon's General visibility (`db.profile.visibility`) without being cast-gated by a cast bar that hides itself between casts. See [common-tasks.md](common-tasks.md#frame-names).

**Migration:** `Database:BackfillLabelStyle(db)` fills in `units.<unit>.label.style` on a profile saved before this feature shipped, AND key-fills any individual fields added to `LABELSTYLE_DEFAULT` since (e.g. `color`) that are missing from an existing style table. Like `FoldLegacyUnits`, it is **shape-driven, not version-gated** — for each of `target`/`focus`, if that unit's config exists it sets `u.label = u.label or {}`; if `u.label.style == nil` it fills the whole `u.label.style = copy(LABELSTYLE_DEFAULT)`, otherwise it walks `LABELSTYLE_DEFAULT` and copies in only the keys ABSENT from the existing style (never overwriting a key the user already has, even a customized one) — `show`/`text` are left exactly as saved. A fresh install (or an already-migrated profile with every current key) already has `style` fully populated by `DEFAULT_PROFILE`, so the check is a no-op. It runs against the currently-active profile at both `Database:Init` and `Database:OnProfileChanged` (right after `FoldLegacyUnits` in both call sites), so any profile — including one switched to or copied in later — picks up any new sub-fields the moment it becomes active, with no visual change since the backfilled values equal the shipped defaults.

**Deviation recorded as intentional** — ratified in [ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations) against `savedvariables-§1`; this paragraph is the reasoning, that row is the record. Adding a new `label.style` sub-table under an existing `units.<unit>.label` field (previously just `{ show, text }`) is a shape addition under a field that predates it, backfilled by a dedicated shape-driven migrator rather than folded into `FoldLegacyUnits` or gated on `db.global.schemaVersion` — necessary because a bare `schemaVersion` bump can't be trusted to distinguish "pre-label-style" from "current" (the same AceDB `copyDefaults`-masking trap `FoldLegacyUnits` already works around), and the field is narrow enough (one sub-table on one existing field) that a second general-purpose migrator was clearer than overloading `FoldLegacyUnits`'s unrelated top-level-table check.

## Migration: folding legacy `icons`/`castbar`/`anchors` into `units.target`

Pre-dual-tracking profiles stored `db.profile.icons`, `db.profile.castbar`, and `db.profile.anchors` at the top level (no `units` table at all). `Database:FoldLegacyUnits(db)` — run unconditionally at the start of both `Database:Init` and `Database:OnProfileChanged` (before `MigrateProfile`) — moves those three tables into `db.profile.units.target.{icons,castbar,anchors}` and clears the old top-level keys.

It is **shape-driven, not version-gated**: it checks `p.icons == nil and p.castbar == nil and p.anchors == nil` and returns immediately (no-op) when all three are already absent — which is true for both a fresh v2 install and an already-migrated account. Version-gating on `db.global.schemaVersion` was considered and rejected for the same reason the account-adoption code above avoids trusting a bare `schemaVersion == nil` check: AceDB's `copyDefaults` rawsets `db.global.schemaVersion` to `NS.SCHEMA_VERSION` the moment `db.global` is first touched, which would make a legacy account that never had a chance to run the migrator look "already current" and silently strand its customized icons/castbar/anchors data under the old top-level keys forever. Keying on the presence of the old tables instead detects exactly (and only) the accounts that carry legacy data, regardless of what `schemaVersion` claims.

The `migrations[1]` step (`Database:MigrateProfile`'s registered v1→v2 migrator) also calls `FoldLegacyUnits`, and the runner then stamps `db.global.schemaVersion` to 2, so the fold happens exactly once from the schema-version path too — `FoldLegacyUnits`'s own idempotency means running it from both call sites is safe, not redundant-in-a-bad-way. Schema generation 2 is the `units.*` restructure (v1 was the pre-migration baseline). The current constant is `NS.SCHEMA_VERSION = 8` — see the spec-key rekey, the color-shape migration, the font-flag migration, the one-time HUD style reset, the flags-onto-From-skin step and the font-picks step below.

**Deviation recorded as intentional** — ratified in [ARCHITECTURE.md § Documented deviations](ARCHITECTURE.md#documented-deviations) against `savedvariables-§1`; this paragraph is the reasoning, that row is the record. Restructuring `DEFAULT_PROFILE` (a rename/nest, not a pure addition) departs from a "profile shape never changes shape, only grows" expectation some Ace3-based addons hold — it was necessary because target/focus each need independently-customizable `icons`/`castbar`, and the alternative (flat `icons`, `focusIcons`, `castbar`, `focusCastbar`, …) doesn't scale to a third unit later and duplicates the anchor/label bookkeeping. The shape-driven (not version-gated) migration is the mitigation that makes the restructure safe for existing installs.

## Migration: localized spec names → numeric spec IDs

Up to schema **v2** the per-spec spell-list key was the player's spec name, uppercased with whitespace stripped (`ELEMENTAL`, `BEASTMASTERY`). That name comes from `GetSpecializationInfo`'s **second** return, which is the *localized display name* — so the key the addon derived at runtime depended on the client's language, while `defaults/Spells.lua` shipped English keys.

On any non-English client the two never met. A frFR Elemental Shaman derived `ELEMENTAIRE`, looked up `spells.SHAMAN.ELEMENTAIRE`, got `nil`, and tracked nothing at all — with no error, because an absent spec list is indistinguishable from a deliberately emptied one. Reported as [issue #8](https://github.com/tusharsaxena/kickcd/issues/8). Only specs whose localized name happens to be spelled exactly like the English one (frFR Warlock `Affliction` / `Destruction`) worked by accident, which is why the bug looked class-specific.

Schema **v3** keys on Blizzard's **numeric specialization ID** instead — `GetSpecializationInfo`'s *first* return, invariant across every locale:

```lua
spells = {
    SHAMAN = {
        [262] = { ... },   — Elemental
    },
}
```

`Const.SPEC` in `core/Constants.lua` holds the ID table (verified against the live `ChrSpecialization` DB2 export) and `defaults/Spells.lua` writes its keys as `[SPEC.ELEMENTAL]` so the file stays greppable. Localized names remain in use for **display only**: `Util.SpecDisplayName` labels the Spells dropdown in the player's own language, and `Util.ResolveSpecID` accepts a localized name typed at the slash command.

### The migrator

`Database:MigrateSpecKeys` walks `profile.spells[CLASS]` and rewrites every **string** key to its numeric specID, resolving through `Util.ResolveSpecID`. That resolver tries, in order: the class-scoped localized name map built from `GetSpecializationInfoForClassID` (which is what recovers a French user's own `/kcd spells add` data), the English token from `Const.SPEC`, then an accent-folded ASCII alias — the last tier existing because WoW's locale-aware `strupper` uppercases accented letters (`Elementaire` → `ELEMENTAIRE`) while stock Lua's does not, so a saved key and a freshly-derived one can differ in case on the accented bytes alone.

It is **shape-driven, not version-gated** — keyed on `type(specKey) == "string"`, so it is a no-op once the profile is numeric. Beyond the AceDB `copyDefaults`-masking trap that `FoldLegacyUnits` documents above, spells have a second, independent reason to avoid version-gating: `db.global.schemaVersion` is **per-account** but `profile.spells` is **per-profile**. A version-gated step would migrate only whichever profile happened to be active at upgrade time, bump the account to v3, and leave every other profile stranded on string keys forever. Running unconditionally from both `Database:Init` and `OnProfileChanged` catches each profile as it loads.

Two data-safety rules, both covered by tests:

- A key that resolves to nothing (hand-edited SavedVariables, a spec removed by a patch) is **left in place**, not deleted. A stale key is inert; losing a customized list is not.
- A string key never overwrites an existing numeric one. On collision the already-migrated numeric list wins and the string key is left alone.

`migrations[2]` calls the same method and the runner stamps `db.global.schemaVersion` to 3, so the rekey also happens once from the version-gated path — safe rather than redundant, given the idempotency above.

## Migration: positional colors → the keyed shape

Up to schema **v3** a color was stored as a positional array, `{ r, g, b, a }`. Schema **v4** stores it keyed:

```lua
borderColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 },
```

That is the collection's shape, not a preference: `LibKa0s-Slash-1.0` parses into it and renders from it, and `LibKa0s-Options-1.0`'s color picker decodes and encodes it. Keeping the positional array would have meant a host-side codec translating at every seam, in both libraries, forever — `settings/Slash.lua` carried exactly that for one release and now doesn't.

`Database:MigrateColorShape(db)` is the v3→v4 step (`migrations[3]`), and it **also runs from `Database:Init` and every `OnProfileChanged`**, after `MigrateSpecKeys`. The stamp is per-account and colors are per-profile: gated on the stamp alone, the step converted only the profile that was active the day the account reached v4, and every other profile kept its positional colors and read them back as the defaults (KICKCD-R-01). Running it on every load and every swap converts each profile the first time it is active, and every rule below is idempotent. It **walks the whole profile** rather than a hardcoded path list — a list would have to be kept in step with every color row ever added, and a row missed there reads `nil` on every channel and renders as the fallback, which is the failure this migration exists to prevent. The shape test is deliberately narrow: a table with a numeric `[1]`, length 3 or 4, whose entries are all numbers in `0..1`. That can't match an anchor table (`{ point =, x =, y = }`), a spell list (array of tables), or a curve. Recursion is depth-bounded at 12, because an unbounded walk over user data is a hang rather than an error.

**The AceDB hybrid trap.** By the time this runs, AceDB has already merged the new *keyed* defaults into the saved table — `copyDefaults` fills any key the saved table lacks, and a saved positional array lacks `r`/`g`/`b`/`a`. So a pre-migration color arrives as a hybrid, `{ 0.25, 0.5, 0.75, 0.5, r = 1, g = 0.4, … }`: the user's values in the array part, the *defaults* in the keys. Detecting "already keyed" by the presence of `.r` would therefore skip every row the migration was written to convert, and each would silently read back as its default. The array part is the tell: if `[1]` is a number there is an array to resolve, and the keys decide which half is the user's. The walk carries `NS.DEFAULT_PROFILE`'s subtree at the same path beside the stored one:

- **The keyed part equals the declared default** at that path (channel by channel, SameValue on the numbers), **or the path has no declared default**, **or there is no keyed part at all**: the keys are AceDB's backfill and the array is the user's color. Convert the array to keys.
- **The keyed part differs from the default**: the keys are a post-upgrade edit. The profile was converted once, the player then changed the color, and an array part lingered. Keep the keys and drop `[1]`..`[4]`; converting would roll the player's newer choice back to an older one.

## Migration: the `"NONE"` font-flag token → the empty string

Up to schema **v4** this addon spelled "no outline, no monochrome" as the literal `"NONE"`, in three places per unit:

| Path | Surface |
|---|---|
| `units.<unit>.icons.cooldownTextFlags` | the countdown drawn on each icon |
| `units.<unit>.castbar.fontFlags` | the cast bar's spell name and cast time |
| `units.<unit>.label.style.flags` | the unit's identity label |

Schema **v5** stores `""` instead, which is what `FontString:SetFont` actually spells it as and what `LibKa0s-Options-1.0`'s canonical `FONT_FLAGS` list is keyed on (`options-ui-§16`).

**The rendering never changed.** `SetFont` did not recognize `"NONE"` and ignored it, which is the same result as `""` — every call site mapped the token to `""` on the way out anyway. What the migration saves is the **control**: a stored `"NONE"` matches no key in the new value list, so the dropdown would have come up showing nothing, in game only.

`Database:MigrateFontFlags(db)` is the v4→v5 step (`migrations[4]`), and like `MigrateColorShape` it also runs from `Database:Init` and every `OnProfileChanged`, for the same per-profile reason. Unlike `MigrateColorShape` it walks an **explicit path list** rather than the whole profile: a bare `"NONE"` string is not distinguishable from a legitimate user value anywhere else in the tree, and three known leaves per unit is not a list that needs deriving. It is idempotent, and it survives a half-built profile (a unit mid-backfill with no `label` table yet).

This is the one **stored-value type change** in the settings-revamp-v2 pass, and it takes the full treatment `options-ui-§15` describes for one: a bumped `NS.SCHEMA_VERSION` and a registered step in the migration runner, in the same change as the row's new value list. The `Master controls` tab RENAME beside it needed neither — a `group` is not a stored path.

## Migration: the one-time HUD style reset (v5 → v6)

KickCD adopted skins in the 2026-10-29 skinning rollout (Ka0sAddonsCommonTasks `docs/2026-10-29-SKINNING_ROLLOUT/`, item KC-03). Each HUD media pick gained a **"Use the skin's ..."** companion bool beside it, emitted by the composer's `fromSkin` (LibKa0s-Options-1.0, OptionsCompose minors 12 and 13), eight per unit:

| Companion (under `units.<unit>.`) | Governs | Skin token (Ka0s Default) |
|---|---|---|
| `icons.borderTextureFromSkin` | the icon border's style **and thickness** (the icon family, `fromSkin = "icon"`) | `icon.borderStyle` `"Solid"`, `icon.borderSize` 2 |
| `icons.cooldownTextFontFromSkin` | the countdown's face | `hud.font` `"Ka0s Prototype"` |
| `castbar.fontFromSkin` | the face of both cast-bar texts | `hud.font` |
| `castbar.interruptible.statusBarTextureFromSkin`, `castbar.uninterruptible.statusBarTextureFromSkin` | each state's bar texture | `bar.texture` `"Ka0s Default"` |
| `castbar.interruptible.borderTextureFromSkin`, `castbar.uninterruptible.borderTextureFromSkin` | each state's border style **and thickness** (the icon family, `fromSkin = "icon"`, KC-A1) | `icon.borderStyle` `"Solid"`, `icon.borderSize` 2 |
| `label.style.fontFromSkin` | the label's face | `hud.font` |

Every one **defaults true** (rollout decision X3), in `defaults/Profile.lua` and in the composer row alike. While one is set its picker is disabled and shows the skin's value, and the HUD draws `NS.SkinResolve(token, pick, companion)` (`core/SkinSetup.lua`), except that while the Scope's `ignoreFonts` is on the stored pick wins for `hud.font` whatever the companion says (LibKa0s v1.81.0, R-1); the stored pick is never overwritten, so turning the companion off draws exactly what the player had. Only the face, the texture and the border follow (X4): every color, size (but the borders' thickness, which the icon family sets), flag and shadow stays the player's. The charges badge, which has no setting, takes the skin's `hud.font` face with `NumberFontNormal`'s size and flags, and `NumberFontNormal`'s own face while `ignoreFonts` is on.

`Database:MigrateHudSkin(db)` is the v5→v6 step (`migrations[5]`), the owner's ruling O2: adopting skins puts every companion on the skin **once, for every player**, through `LibKa0s-Skin-1.0`'s `Skin.ResetToSkin` (set directly when the library is absent). It runs from `Database:Init` and every `OnProfileChanged`, like the shape-driven steps, because the stamp is per account and the data per profile. It cannot be shape-driven, though: "follows the skin" is not a shape a later run could tell from the player's own choice. So each profile carries its own record, `skin.hudReset` (default false, no schema row): false, the step sets the sixteen companions and the record; true, it does nothing, so a companion the player turns off afterwards stays off for good. A profile reset puts the record back to false, and the step then re-runs against defaults that already follow the skin, which changes nothing a player can see. Only a companion that reads a boolean is named. The reason was `ResetToSkin` writing the `FROM_SKIN` sentinel into a key it found neither a table nor a bool; LibKa0s v1.81.0 (Skin minor 8) sets a listed `FromSkin` key true stored or not, but the shipped step keeps its filter so a profile that migrates late gets what an early one got (decision D-19), and an absent companion already reads AceDB's default, true.

## Migration: Font flags onto From skin (v6 → v7)

LibKa0s v1.82.0 (Ka0sAddonsCommonTasks `docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK/`, item KC-01, ruling D-07) gave every Font flags row a **From skin** value, `"@skin"`, and made it the default where `OUTLINE` was: `units.<unit>.icons.cooldownTextFlags`, `units.<unit>.castbar.fontFlags` and `units.<unit>.label.style.flags` (the composer's `flagsFromSkin`). The HUD draws From skin through the facade's `S.FontFlags`, which follows the Skin tab's Font outline (`skin.outline`: All text and HUD text only draw `OUTLINE`, Off draws none); any other flag is drawn as picked (`NS.SkinFontFlags`, `core/SkinSetup.lua`, which also keeps reading the pre-v5 `"NONE"` as none).

`Database:MigrateFlagsFromSkin(db)` is the v6→v7 step (`migrations[6]`): a flag still at the old default, `OUTLINE`, moves onto From skin **once**, so the Font outline reaches it; any other flag stays (Addendum 01 of that bundle: only a flag the player changed counts as picked). An `OUTLINE` picked on purpose cannot be told from the old default, because AceDB never stored a value equal to its default; All text, the Font outline's default, draws it the same. Like the HUD style reset it runs from `Database:Init` and every `OnProfileChanged` and is recorded per profile in `skin.flagsReset` (default false, no schema row), so an `OUTLINE` picked afterwards is never moved; a profile reset puts the record back, and the step then finds defaults already on From skin.

While a HUD text uses the skin's face, its stored size is drawn through `S.HudFontSize` (`NS.SkinHudSize`, ruling D-09), scaled by the skin's `hud.fontSize` over Ka0s Default's so the text is as wide in every skin; a text on its own face, and every text while Ignore fonts is on, draws its stored size. No stored size is ever rewritten, so this needs no step.

## Migration: a picked face kept off the skin's font (v7 → v8)

The v5 → v6 HUD style reset put every "Use the skin's font" box on the skin and kept the stored face, so a face the player had picked (the owner's Ka0s Kait on the target label, Ka0sAddonsCommonTasks `docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK/inputs/inventory/Z_CRITIC.md` R5) has drawn the skin's face since. `Database:MigrateSkinFontPicks(db)` is the v7→v8 step (`migrations[7]`, item KC-03, the owner's ruling D-15; AuraMaster's AM-03 is the same rule over its own texts, except that AM-03 does not exempt the pre-v1.82.0 skin faces named below; KickCD keeps that exemption): on each unit's countdown (`icons.cooldownTextFont`), cast bar (`castbar.font`) and label (`label.style.font`), a box that is on goes off when the stored face is the player's pick, so the face comes back. Not a pick: the stored default, Friz Quadrata TT (AceDB never told it apart from an unchanged row); the HUD face of the skin the profile wears (`Skin:ResolveSkin(skin.skin)["hud.font"]`, Ka0s Default's Prototype without the library); and a face a Ka0s skin drew before LibKa0s v1.82.0 (Oxanium, Inter, Fira Sans Regular), which a skin stored and the player never picked. v1.82.0 dropped those faces and v1.83.0 ships them again, so the exemption is no longer what keeps them drawing, and it stays because such a face is still no pick. The stored face is never written. Like the steps above it runs from `Database:Init` and every `OnProfileChanged`, after `MigrateHudSkin`, and is recorded per profile in `skin.fontPicksKept`, so a box the player ticks again afterwards stays ticked. A text kept on its own face draws its stored size, unscaled (`S.HudFontSize`).
