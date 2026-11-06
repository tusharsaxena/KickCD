# Candidates

Range `v1.89.0..v1.90.0`, from the v1.90.0 CHANGELOG block and the moved majors' API documents (Core 16, Widgets 24.5.12.6.8.5, Skin 17.1.27.8.19.18.17.4.9, Options 37.4.44.2.7.2.9.15.2.4.19.13.5.5.7.7.11.1.1.4). Decisions come from Ka0sAddonsCommonTasks `docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/SF1_SMOKE_FEEDBACK.md`, not from an interview.

## Class A, delivered on the copy

- **One physical pixel** (`SF1-L1`, Core 16, Widgets 24, WidgetsAutocomplete 8, SkinPaint 19, SkinPaintExtras 18): every library Widgets edge of one UI unit (`W.Dropdown`'s box, `W.SearchBox`, the shared menu and its cascade levels, the autocomplete list) is one physical pixel at any UI scale and sub-pixel position, with no skin and under every skin. This addon draws none of those controls itself (`grep -rn 'W\.Dropdown\|W\.SearchBox\|Autocomplete'` outside the payloads is empty), but any library-drawn menu it shows, such as the Sim scenario picker, takes the fix on the copy. No member or option moves.
- **`lib.__copySkinTo` and `keepScope`** (`SF1-L2`, Skin 17, OptionsAppearance 7): an Apply to all or Skin-tab copy from this addon now leaves a `keepScope` target's Scope alone (the Skin Tester's, at `SF1-ST`). Delivered with no host change.

## Class B, host change

- **`RegisterOwner(owner, { keepScope = true })`** (`docs/api/Skin/version-17.1.27.8.19.18.17.4.9-docs.md`, CHANGELOG v1.90.0 *A copy leaves a host's Scope alone*): not applicable. The opt-out is for a host whose documented Scope differs from the others' (the Skin Tester's `ignorePanel = false`). KickCD has no such deviation, so its registration at `core/SkinSetup.lua:641` takes copies as before. Additive if ever wanted.

## Class C, whole-module

None. No major is new at v1.90.0. `LibKa0s-IconBrowser-1.0` and `LibKa0s-Toast-1.0` stay unadopted, as the v1.89.0 bundle settled (no icon chooser, no toast).
