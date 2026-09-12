# 02 — Candidates: LibKa0s v1.30.0 → v1.31.0

Sources, in the order the procedure requires:

```
git -C ../LibKa0s log --oneline v1.30.0..v1.31.0
```

```
30db4ed The v1.31.0 release record
2b312db v1.31.0: release pointers, standards v2.44.0, the case list
f355fdc Kit 17: the Ace surfaces six consumer harnesses migrate onto
3162e53 Options 15.15.4.3: a record-backed bind arm for the composers (PanelMaster#48)
09099b1 docs(releasing): v1.30.0 is merged in all ten consumers
853c62e Merge branch 'fix/kit-27-30'
5193ebe Post-tag v1.30.0: consumers table sweep; AuraMaster is the tenth consumer
```

The `CHANGELOG.md` block `## v1.31.0 — 2026-09-12` at the tag, and the two API documents for the
majors that moved: `docs/api/Options/version-15.15.4.3-docs.md` and
`docs/api/testkit/version-17-docs.md`.

## Class A — reached this addon on the re-vendor alone

| Item | Evidence | Why nothing had to change here |
|---|---|---|
| `OptionsWidgets.lua` minor 15: a row with no `path` reads and writes through its own `get` / `set` | CHANGELOG v1.31.0, "`OptionsWidgets.lua` minor 15" | The gate is `path == nil`. Every KickCD schema row carries a `path`, so every maker reads and writes through the descriptor exactly as before. |
| `OptionsCompose.lua` minor 4: path-keyed composer output | CHANGELOG v1.31.0, "`OptionsCompose.lua` minor 4" | "Path-keyed callers are byte-for-byte unaffected", pinned upstream by `tests/fixture_compose_golden.lua`. KickCD's font, border, bar and color blocks are all path-keyed. |
| Kit revision 17 on the copy | CHANGELOG v1.31.0, "Adoption: nothing moves"; `docs/api/testkit/version-17-docs.md` "For consumers: nothing moves" | Measured upstream at 888 for KickCD with rev 16, rev 17 and rev 17 plus the v1.31.0 `libs/`. Measured here too: 894 before the copy and 894 after it. The harness still replaced the kit's Ace layer, so nothing else could reach it on the copy alone. |

## Class B — host change required

**B1. Kit revision 17's Ace surfaces, adopted by migrating the harness (#21).**
`docs/api/testkit/version-17-docs.md`, "For the six migrations: what stays local", KickCD paragraph.
It lists what KickCD takes from the kit (`NewModule`, `GetModule`, the module lifecycle,
string-method message dispatch, the event half, `AceGUI:Release`, AceConsole, `GetAddon`) and what
stays local (`__enableAll` as a one-line layer, its AceDB, its frame model, its `C_Timer` queue, the
`SetHighlight` recorder).

- Touches `tests/wow_mock.lua`, `tests/test_state.lua` and `tests/test_lifecycle.lua` (ports), plus
  three new cases in `tests/test_lifecycle.lua` and `tests/test_settings_spells_editor.lua`.
- Blast radius: **replaces** harness code the addon owned (its local LibStub, AceAddon, AceEvent,
  AceConsole, AceTimer and AceGUI fakes). No production file moves.
- Recommendation: adopt. It is owner decision 3 of the 2026-09-12 triage, and without it every
  future kit revision to the Ace fakes bypasses this suite.

**B2. `spec.bind`, the record-backed composer arm.** CHANGELOG v1.31.0, "`OptionsCompose.lua` minor
4 — `spec.bind`"; `docs/api/Options/version-15.15.4.3-docs.md`.

- It lets a page that edits **registry records** compose the canonical font, border and bar groups.
  KickCD's one registry is the spell lists, and its per-entry fields (`enabled`, `category`) are a
  checkbox and a dropdown, not a composed group. No KickCD page composes a group over a record.
- Blast radius: additive; nothing would be replaced.
- Recommendation: do not adopt. There is no call site it fits. The `architecture-§5` register row
  for the spell-entry fields (#17) has its own re-check trigger, which this arm does not fire.

## Class C — whole-module adoption

**`LibKa0s-Item-1.0`.** It ships in the payload with no lookup in this addon, as it did at v1.29.0
and v1.30.0, and it did not move in this release (Item minor 1). Its premise is unchanged: KickCD
tracks spells, not items. Not re-offered.
