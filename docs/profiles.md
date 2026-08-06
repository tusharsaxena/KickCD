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
- **Opened lazily on every `OnShow`, not once.** Re-opening is cheap — AceConfigDialog reuses an
  existing widget tree — and it is what makes the page reflect the **current** profile after a
  switch. Opening once would leave the page describing whichever profile was active the first time it
  was shown.

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

`Database:OnProfileChanged` handles all three because the required response is identical. One
signature detail matters: AceDB hands `(event, db, newProfileKey)` for *Changed* and *Copied*, but
the third argument is **`nil`** for *Reset* — so the handler substitutes the active key rather than
trusting the parameter. A handler that reads it blindly logs a `nil` profile name on every reset.

## Profiles and per-unit appearance

Per-unit appearance (`icons` / `castbar`) is read through `NS.Units.Icons(unit)` /
`NS.Units.Castbar(unit)` rather than off `db.profile` directly, so that a **linked focus** reading
target's tables resolves in one place (`core/Units.lua`). A profile switch changes what those
accessors resolve to; nothing caches the resolved table across a switch.
