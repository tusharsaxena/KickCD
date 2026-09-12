# 02 — Candidates: LibKa0s v1.31.0 → v1.32.0

Sources, in the order the procedure requires:

```
git -C ../LibKa0s log --oneline v1.31.0..v1.32.0
```

```
e18dd12 The v1.32.0 release record, re-taken on the final tree
c6314d6 CLAUDE.md: the luacheck scope is fifty-four files at v1.32.0
4083889 v1.32.0 review: bulkEnd's info names a profile reset (debug-logging-§10 final ruling)
4353908 The v1.32.0 release record
f7d78cd v1.32.0: Options 16 and Slash 8 bracket their reset walks (debug-logging-§10)
807925a v1.31.0 post-tag docs and test: the verifier's findings
```

The `CHANGELOG.md` block `## v1.32.0 — 2026-09-12` at the tag, and the two API documents for the
majors that moved: `docs/api/Options/version-16.15.4.3-docs.md` and `docs/api/Slash/version-8-docs.md`.

## Class A — reached this addon on the re-vendor alone

| Item | Evidence | Why nothing had to change here |
|---|---|---|
| `Options.lua` minor 16 and `Slash.lua` minor 8, unbracketed | CHANGELOG v1.32.0: "A host that supplies neither new field runs the exact walk it ran at v1.31.0, with no `pcall` on the path" | Until a descriptor supplies `bulkBegin` / `bulkEnd`, both walks are minor 15's and minor 7's. Measured: 913 passed before the copy and 913 after it (`2bf885c`). |

## Class B — host change required

**B1. The bulk bracket on both descriptors (`debug-logging-§10`).** CHANGELOG v1.32.0, "`Options.lua`
minor 16" and "`Slash.lua` minor 8"; `docs/api/Options/version-16.15.4.3-docs.md`, "What the host
logs — the contract".

- Before it, every page Defaults logged one `[Set]` per row walked (castbar 110, icons 78,
  label 32, general 9). Reset all logged the `sessionOnly` row's `[Set]` line, and the handler logged
  `[Profile] switched to '<name>'` for a reset and a copy alike.
- Touches `settings/Panel.lua` (the record and the one line), `settings/OptionsSetup.lua` (descriptor
  fields, and the degraded Reset all under the mute), `settings/Slash.lua` (descriptor fields),
  `settings/Panel_Render.lua` (`SetRows` logs the changed-row count), `core/Database.lua` (the handler
  worded by event).
- Blast radius: the debug log only, plus one message payload. A profile copy's
  `PROFILE_CHANGED` now carries the active key rather than AceDB's third argument, which for
  `OnProfileCopied` is the source profile.
- Recommendation: adopt. It is the owner's ruling in `debug-logging-§10` (standard v2.44.0).

**The review correction, binding on B1.** `bulkEnd`'s `count` is every row `applyDefault` returned,
rows already at their default included, so it is not the §10 N. The host tallies the rows whose
value changed, nested acts log once from the outermost level with the summed rows, and a level that
reset the profile silences the act. The same rule applies to the host's own bulk act, Copy styling.

## Class C — whole-module adoption

**`LibKa0s-Item-1.0`.** Unchanged in this release (Item minor 1), premise unchanged: KickCD tracks
spells, not items. Not re-offered.
