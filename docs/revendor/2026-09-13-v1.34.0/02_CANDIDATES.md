# 02 — Candidates: LibKa0s v1.34.0

Sources: the v1.34.0 block of `CHANGELOG.md` at the tag; `docs/api/Options/version-18.15.5.3-docs.md`,
`docs/api/Slash/version-10-docs.md` and `docs/api/testkit/version-19-docs.md` at the tag.

## Class A: delivered on the copy alone

| Item | What it does here |
|---|---|
| Slash 10: a `string` row takes the whole value after the path, trimmed | `units.<unit>.label.text` (`settings/Label.lua:105`), the one free-text row, now keeps every word: `/kcd set units.target.label.text Kick Now` stores `"Kick Now"`, not `"Kick"`. The LSM font and texture rows with spaces in their names start working too. `parseForHost` is unaffected (01_DELTA). |
| Options 18 / OptionsCompose 5, without the new field | The descriptor supplies `resetProfile` (`settings/OptionsSetup.lua:129`), so on the copy alone the Reset-all tooltip moves to *"Reset the current profile to its defaults. Your other profiles are not affected."* |
| Kit 19: the AceDB fake's `OnProfileReset` carries no key | Unreachable: this harness replaces the kit's AceDB (01_DELTA). |

## Class B: host change required

### B1. `profilesPage = true` on the Options descriptor (O18)

This addon ships an AceDBOptions Profiles sub-page and supplies `resetProfile`, which is the case
`version-18.15.5.3-docs.md` ("What the host does") names. With the field the General page's
Reset-all tooltip reads *"Reset the current profile to its defaults — the same thing Profiles →
Reset Profile does. Your other profiles are not affected."*, which is `options-ui-§12`'s SHOULD.

## Class C: whole-module adoption

None.
