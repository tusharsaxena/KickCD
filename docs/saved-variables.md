# Saved variables

Two saved-variables are declared in `KickCD.toc`: **`KickCDDB`**, the AceDB-3.0 store described below, and **`KickCDPerfDB`**, which is owned entirely by `LibKa0s-Perf-1.0` (wired in `core/PerfSetup.lua`) and holds the `/kcd perf` A/B capture records. Nothing in this addon reads or writes `KickCDPerfDB` directly — the library owns its shape, and it is diagnostics data, not configuration: deleting it loses captures and nothing else.

`KickCDDB` is an AceDB-3.0 store. `Database:Init` calls `AceDB:New("KickCDDB", DEFAULTS, true)` — the `true` third argument expands to `"Default"` per AceDB-3.0, so every character on the account starts on the shared `"Default"` profile. (Omitting the third argument falls back to the per-character profile, which contradicts the docs and was the source of "every fresh character lands on its own profile" reports.) The user can opt into default / per-character / per-class / per-realm scope via the Profiles tab. See the rationale comment on the `AceDB:New` call in `core/Database.lua` for the in-tree note.

## `db.global` — account-wide scope

Alongside the profile store, AceDB carries a `db.global` scope (addon-wide, shared by every character on the account regardless of active profile):

```lua
db.global = {
    schemaVersion = <int>,       -- addon-wide schema version (CURRENT_DB_VERSION = 4).
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
                                 -- below). v2 -> v3 (migrations[2]) runs
                                 -- Database:MigrateSpecKeys then bumps to 3 (see the
                                 -- localized-spec-name migration below). v3 -> v4
                                 -- (migrations[3]) runs Database:MigrateColorShape
                                 -- then bumps to 4 (see the color-shape migration
                                 -- below).
}
```

Profile shape (see `core/Database.lua` `DEFAULT_PROFILE`):

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

## Spell list lifecycle

`spells` is seeded once on first profile creation by `Database:BuildSpells`, which deep-copies `NS.DefaultSpells` and appends the player's racial cast-stopper. Subsequent edits are user-owned; the seeder is idempotent on populated profiles.

`Database:ResetAllSpells` wipes `db.profile.spells` and re-runs `BuildSpells` so every spec — not just the active one — gets the current addon defaults back. It's the helper behind the General → "Reset all settings" popup, `/kcd spells resetall`, and `/kcd resetall`. The narrower per-spec reset (Spells panel's Defaults button + `KICKCD_RESET_SPELLS` popup, and `/kcd spells reset [CLASS SPEC]`) instead rebuilds only one `(class, spec)` slot.

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
                        justifyH, justifyV, rotation, font, size, flags } },
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

`icons` / `castbar` are structurally identical for `target` and `focus` (both seeded from the same `ICONS_DEFAULT` / `CASTBAR_DEFAULT` tables in `core/Database.lua`) — the only per-unit differences in `DEFAULT_PROFILE` are `enabled` (both default `true`), `link` (focus defaults `true`), `label.text`, and each unit's default screen offset in `anchors` (target seeds `y = 120`, focus seeds `y = 260` — Focus sits 140px above Target so the two grids don't overlap on first enable; this leaves roughly 10px of clearance between the Focus cast-timer bottom and the Target label top, a computed estimate from default element sizes that may need a small nudge once rendered).

**Link resolution lives in `core/Units.lua` (`NS.Units`), not scattered across the widget modules.** `IconGrid` and `Castbar` never read `db.profile.units.<unit>.icons` / `.castbar` directly for appearance — they call `NS.Units.Icons(unit)` / `NS.Units.Castbar(unit)`, which resolve to `units.target.icons` / `.castbar` whenever `units.focus.link == true` (target is never linked). Position (`anchors`) and `label.text` are read straight off the unit's own config via `NS.Units.Anchor` / `.Label` — they are NOT link-resolved, so a linked focus grid still drags independently of target and keeps showing its own "Focus" identity text. `label.show` is the exception among the label fields: it resolves through `NS.Units.LabelShow`, so turning target's label off also hides a linked focus's. `NS.Units.CopyStyling(from, to)` deep-copies `icons`/`castbar`/`label.style` and snapshots `label.show` (it has to — otherwise unlinking would revive focus's stale independent `show`), then flips `link = false`; `label.text` is deliberately not copied. It backs the settings panel's "Copy styling from Target" button.

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
    flags    = "OUTLINE",             -- "NONE" | "OUTLINE" | "THICKOUTLINE" | "MONOCHROME"
    color    = { 1, 0.82, 0, 1 },     -- RGBA label text color (Blizzard gold)
}
```

`label.style` is **single-sourced** from one `LABELSTYLE_DEFAULT` table in `core/Database.lua`, deep-copied into both `units.target.label.style` and `units.focus.label.style` — Target and Focus ship with an IDENTICAL label appearance out of the box (unlike `icons`/`castbar`, which are also structurally identical but seeded from their own `ICONS_DEFAULT`/`CASTBAR_DEFAULT`, this is the same pattern applied to label styling). `label.style` **is** link-resolved (`NS.Units.LabelStyle(unit)`, resolving to `units.target.label.style` for a linked focus), and so is `label.show` (`NS.Units.LabelShow(unit)`) — only `text` stays per-unit (`NS.Units.Label(unit)`, never link-resolved), so a linked Focus mirrors Target's font/position/rotation/color *and* its on/off state while still showing its own "Focus" text.

**Visibility:** the label's holder frame is created on `UIParent` but `SetParent`'d onto the unit's **icon grid** (`IconGrid:GetGridFrame(unit)`, falling back to the attach frame only if the grid isn't up yet) on every `Apply`, while `SetPoint`-anchoring to the resolved attach frame for position alone. Parenting to the grid — not the attach frame — means the label inherits the grid's shown state + effective alpha, so it follows the addon's General visibility (`db.profile.visibility`) without being cast-gated by a cast bar that hides itself between casts. See [conventions.md](conventions.md#frame-names).

**Migration:** `Database:BackfillLabelStyle(db)` fills in `units.<unit>.label.style` on a profile saved before this feature shipped, AND key-fills any individual fields added to `LABELSTYLE_DEFAULT` since (e.g. `color`) that are missing from an existing style table. Like `FoldLegacyUnits`, it is **shape-driven, not version-gated** — for each of `target`/`focus`, if that unit's config exists it sets `u.label = u.label or {}`; if `u.label.style == nil` it fills the whole `u.label.style = copy(LABELSTYLE_DEFAULT)`, otherwise it walks `LABELSTYLE_DEFAULT` and copies in only the keys ABSENT from the existing style (never overwriting a key the user already has, even a customized one) — `show`/`text` are left exactly as saved. A fresh install (or an already-migrated profile with every current key) already has `style` fully populated by `DEFAULT_PROFILE`, so the check is a no-op. It runs against the currently-active profile at both `Database:Init` and `Database:OnProfileChanged` (right after `FoldLegacyUnits` in both call sites), so any profile — including one switched to or copied in later — picks up any new sub-fields the moment it becomes active, with no visual change since the backfilled values equal the shipped defaults.

**Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): adding a new `label.style` sub-table under an existing `units.<unit>.label` field (previously just `{ show, text }`) is a shape addition under a field that predates it, backfilled by a dedicated shape-driven migrator rather than folded into `FoldLegacyUnits` or gated on `db.global.schemaVersion` — necessary because a bare `schemaVersion` bump can't be trusted to distinguish "pre-label-style" from "current" (the same AceDB `copyDefaults`-masking trap `FoldLegacyUnits` already works around), and the field is narrow enough (one sub-table on one existing field) that a second general-purpose migrator was clearer than overloading `FoldLegacyUnits`'s unrelated top-level-table check.

## Migration: folding legacy `icons`/`castbar`/`anchors` into `units.target`

Pre-dual-tracking profiles stored `db.profile.icons`, `db.profile.castbar`, and `db.profile.anchors` at the top level (no `units` table at all). `Database:FoldLegacyUnits(db)` — run unconditionally at the start of both `Database:Init` and `Database:OnProfileChanged` (before `MigrateProfile`) — moves those three tables into `db.profile.units.target.{icons,castbar,anchors}` and clears the old top-level keys.

It is **shape-driven, not version-gated**: it checks `p.icons == nil and p.castbar == nil and p.anchors == nil` and returns immediately (no-op) when all three are already absent — which is true for both a fresh v2 install and an already-migrated account. Version-gating on `db.global.schemaVersion` was considered and rejected for the same reason the account-adoption code above avoids trusting a bare `schemaVersion == nil` check: AceDB's `copyDefaults` rawsets `db.global.schemaVersion` to `CURRENT_DB_VERSION` the moment `db.global` is first touched, which would make a legacy account that never had a chance to run the migrator look "already current" and silently strand its customized icons/castbar/anchors data under the old top-level keys forever. Keying on the presence of the old tables instead detects exactly (and only) the accounts that carry legacy data, regardless of what `schemaVersion` claims.

The `migrations[1]` step (`Database:MigrateProfile`'s registered v1→v2 migrator) also calls `FoldLegacyUnits` and bumps `db.global.schemaVersion` to 2, so the fold happens exactly once from the schema-version path too — `FoldLegacyUnits`'s own idempotency means running it from both call sites is safe, not redundant-in-a-bad-way. Schema generation 2 is the `units.*` restructure (v1 was the pre-migration baseline). The current constant is `CURRENT_DB_VERSION = 4` — see the spec-key rekey and the color-shape migration below.

**Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): restructuring `DEFAULT_PROFILE` (a rename/nest, not a pure addition) departs from a "profile shape never changes shape, only grows" expectation some Ace3-based addons hold — it was necessary because target/focus each need independently-customizable `icons`/`castbar`, and the alternative (flat `icons`, `focusIcons`, `castbar`, `focusCastbar`, …) doesn't scale to a third unit later and duplicates the anchor/label bookkeeping. The shape-driven (not version-gated) migration is the mitigation that makes the restructure safe for existing installs.

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

`migrations[2]` calls the same method and bumps `db.global.schemaVersion` to 3, so the rekey also happens once from the version-gated path — safe rather than redundant, given the idempotency above.

## Migration: positional colors → the keyed shape

Up to schema **v3** a color was stored as a positional array, `{ r, g, b, a }`. Schema **v4** stores it keyed:

```lua
borderColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 },
```

That is the collection's shape, not a preference: `LibKa0s-Slash-1.0` parses into it and renders from it, and `LibKa0s-Options-1.0`'s color picker decodes and encodes it. Keeping the positional array would have meant a host-side codec translating at every seam, in both libraries, forever — `settings/Slash.lua` carried exactly that for one release and now doesn't.

`Database:MigrateColorShape(db)` is the v3→v4 step (`migrations[3]`). It **walks the whole profile** rather than a hardcoded path list — a list would have to be kept in step with every color row ever added, and a row missed there reads `nil` on every channel and renders as the fallback, which is the failure this migration exists to prevent. The shape test is deliberately narrow: a table with a numeric `[1]`, length 3 or 4, whose entries are all numbers in `0..1`. That can't match an anchor table (`{ point =, x =, y = }`), a spell list (array of tables), or a curve. Recursion is depth-bounded at 12, because an unbounded walk over user data is a hang rather than an error.

**The AceDB hybrid trap.** By the time this runs, AceDB has already merged the new *keyed* defaults into the saved table — `copyDefaults` fills any key the saved table lacks, and a saved positional array lacks `r`/`g`/`b`/`a`. So a pre-migration color arrives as a hybrid, `{ 0.25, 0.5, 0.75, 0.5, r = 1, g = 0.4, … }`: the user's values in the array part, the *defaults* in the keys. Detecting "already keyed" by the presence of `.r` would therefore skip every row the migration was written to convert, and each would silently read back as its default. The array part is the tell — if `[1]` is a number, the user's real color is there and the keys are contamination.
