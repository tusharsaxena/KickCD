Delta: LibKa0s v1.80.0 -> v1.83.0 (span: v1.80.0 v1.81.0 v1.82.0 v1.83.0)

Back-filled by item `FX-KC-DOCS` of the 2026-10-31 findings remediation. KickCD took all four tags
inside the skinning rollout, the skin library follow-ups, the skin fonts run and the font pickers
run, and none of them wrote a bundle. The delta base of the first is v1.77.0, the last recorded
tag (`../2026-10-24-v1.77.0/`). KickCD never vendored v1.78.0 or v1.79.0: their changes arrived
with v1.80.0.

## The listing (3h of `/dev-copilot:wow-revendor-libka0s`)

```sh
# vendored: tags named by the CLAUDE.md provenance line at every payload commit
# recorded: the tag each docs/revendor/ folder names, plus line 1 of 01_DELTA.md for a span
grep -vxF -f recorded.txt vendored.txt
# v1.80.0
# v1.81.0
# v1.82.0
# v1.83.0
```

The listing also prints v1.8.1, v1.8.2, v1.10.2 and v1.15.0, plus v1.25.0 and v1.30.0, which the
span `../2026-09-24-v1.16.0-v1.54.2/` covers without naming them on its line 1. None of those is
this span's concern.

## The commits that carried them

```sh
git log --format='%h %s' -- libs/LibKa0s tests/_kit | head -7
# f97114c KC-RV3: Take the re-cut LibKa0s v1.83.0 (LK-A3, the skin picker's rows)
# 789865a KC-RV2: Take the re-cut LibKa0s v1.83.0 (LK-A1, LK-A2)
# 1cd723a KC-F01: Re-vendor LibKa0s v1.83.0 and move to its outline default and faces
# 38de9ae KC-02: Remove the floating simulation strip and keep the step panel up as the session's sign
# b761254 KC-01: Re-vendor LibKa0s v1.82.0 with the Font outline, /kcd skin, From skin flags and the HUD size scale
# a383f30 KC-RV: Re-vendor LibKa0s v1.81.0 from the local tag
# eb98c7d KC-RV: Re-vendor LibKa0s v1.80.0 from the local tag
```

Each provenance roll is in its re-vendor commit. `f97114c` and `789865a` took the re-cuts of the
same tag, so the line stays at v1.83.0. Library files new in the span:

- v1.80.0: `DebugLogWindow`, `OptionsAppearance`, `OptionsSkinPicker`, `Skin`, `SkinAce`, `SkinDefs`,
  `SkinEUI`, `SkinPaint`, `SkinPaintControls`, `SkinPaintExtras`, `Toast`, `WidgetsCopyWindow`, plus
  the skins' fonts and textures. The `LibKa0s icons:` line gains `settings`.
- v1.81.0: none; twenty-four library files move and the kit stays at revision 44.
- v1.82.0: `OptionsSwitch`, plus Prototype, Expressway and a third Fira Sans weight. Kit revision 45.
- v1.83.0: `OptionsMedia`, plus the new skin faces. Kit revision 46.

All four tags are pushed (`git -C ../LibKa0s ls-remote --tags origin v1.80.0 v1.81.0 v1.82.0 v1.83.0`
answers all four).
