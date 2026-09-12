# Profiles

KickCD stores its settings **per profile**, and surfaces AceDB's own profile management as a settings
page. That makes profiles part of the addon's user-visible behavior rather than an AceDB
implementation detail, which is why they have a page here.

The stored shape inside a profile is [schema.md](schema.md); the pages around this one are
[settings-panel.md](settings-panel.md).

## Where profiles sit

`core/Database.lua` opens the store with `AceDB:New("KickCDDB", aceDBDefaults(), true)` — the `true`
naming a shared **Default** profile, so a fresh character inherits a working setup rather than an
empty one. Every setting path resolves against `NS.db.profile`.

`defaults/Profile.lua`'s `DEFAULT_PROFILE` is the **only** place a profile default is hardcoded
(`savedvariables-§2`). `defaults/Spells.lua` is the separate per-class-and-spec seed, applied by
`Database:BuildSpells()` when a profile is first created — which is why a *new* spell added to that
file does not appear in an existing profile until `/kcd resetall` re-seeds it.

## The Profiles page

`settings/Profiles.lua` registers a canvas subcategory whose body hosts an AceGUI `SimpleGroup`, into
which `AceConfigDialog` renders **AceDBOptions'** own options table — create, switch, copy, reset,
delete, plus the per-character / per-class / per-realm / per-faction / default scope dropdowns.

Three decisions in that file are deliberate:

- **No Defaults button** (`defaultsButton = false`, stated explicitly rather than defaulted). Profile
  management already carries its own destructive controls; a second reset control beside them, with
  different semantics, is a trap.
- **Rendered into our container, not its own window.** `AceConfigDialog:Open` accepts any AceGUI
  container as its target, so the AceDBOptions widgets land inside the canvas frame instead of
  popping a separate dialog.
- **Opened lazily on every show, not once.** Re-opening is cheap — AceConfigDialog reuses an
  existing widget tree — and it is what makes the page reflect the **current** profile after a
  switch. Opening once would leave the page describing whichever profile was active the first time it
  was shown. The open is the page's `Helpers.SetRenderer` body rather than a parked `OnShow`
  (`CX03`), so the Blizzard AddOns sidebar cannot reach it in combat; the library re-runs a renderer
  on first show and on the next show after the page was marked dirty, and the page's `OnHide` marks
  it with `Helpers.RefreshPanel(ctx, true)` to keep "every show" true.

This is the one place `AceConfigDialog` is used. Every other page is raw AceGUI on a Blizzard canvas
(`options-ui`); AceDBOptions is the exception because the options table is Ace's, not the addon's.

## Reacting to a profile change

A profile switch is not a settings change — the whole settings tree is different afterwards, and
every rendered surface has to be rebuilt rather than nudged. `core/Database.lua` registers **one**
handler for three AceDB callbacks:

```lua
db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
```

`Database:OnProfileChanged` handles all three because the required response is identical. The
signatures are not: AceDB hands `(event, db, newProfileKey)` for *Changed*,
`(event, db, sourceProfileKey)` for *Copied* and `(event, db)` for *Reset*. Only a switch names the
profile that is now active. A copy and a reset leave the active profile where it was, so for both
the handler announces the active key (`db.keys.profile`). Reading the third argument blindly
would announce the copy's *source* as the new profile, and a `nil` on every reset.

**The debug line is worded by the event** (`debug-logging-§10`). A reset and a copy replace the
profile's rows wholesale, so each logs one `[Set]` line; a switch rewrites no row and keeps its
`[Profile]` trace:

| Event | Line |
|---|---|
| *Reset* | `[Set] reset profile '<name>' to defaults (N rows)`, N being every row the profile stores (the schema less its `sessionOnly` rows) |
| *Copied* | `[Set] copied profile '<source>' → '<active>'` |
| *Changed* | `[Profile] switched to '<name>'` |

That handler line is the only line a Reset all logs. The library's bulk bracket reports that the act
reset the profile, so `Helpers.BulkEnd` adds nothing, and the `sessionOnly` row the library writes
first is muted ([settings-panel.md](settings-panel.md#bulk-resets-log-one-line)).

## Profiles and per-unit appearance

Per-unit appearance (`icons` / `castbar`) is read through `NS.Units.Icons(unit)` /
`NS.Units.Castbar(unit)` rather than off `db.profile` directly, so that a **linked focus** reading
target's tables resolves in one place (`core/Units.lua`). A profile switch changes what those
accessors resolve to; nothing caches the resolved table across a switch.
