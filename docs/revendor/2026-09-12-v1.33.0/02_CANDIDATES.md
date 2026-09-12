# 02 — Candidates: LibKa0s v1.33.0

Sources: the v1.33.0 block of `CHANGELOG.md` at the tag; `docs/api/Options/version-17.15.4.3-docs.md`,
`docs/api/Slash/version-9-docs.md` and `docs/api/testkit/version-18-docs.md` at the tag.

## Class A: delivered on the copy alone

| Item | What it does here |
|---|---|
| Options 17: every LSM font loaded on the first panel show | The descriptor already hands the library `getLSM` (`settings/OptionsSetup.lua:153`). The Cast bar and Text Label pages build their font rows with `H.FontGroup` (`settings/Castbar.lua:346`, `settings/Label.lua:184`), which writes `LSM30_Font`. So the first open of those dropdowns now draws every row. Nothing to wire. |
| Slash 9 | Docstrings only. Nothing. |
| Kit 18: the AceDB fake's `OnProfileCopied` carries the source key | Unreachable here. `tests/wow_mock.lua` replaces the kit's AceDB with this addon's own, whose `CopyProfile` is a no-op. The test that pins the copy line (`tests/test_settings_log.lua:377`) calls the handler directly. |

## Class B: host change required

None. v1.33.0 adds no descriptor field and no member.

## Class C: whole-module adoption

None.
