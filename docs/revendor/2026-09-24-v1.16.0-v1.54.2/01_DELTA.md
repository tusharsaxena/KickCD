Delta: LibKa0s v1.16.0 -> v1.54.2 (span: v1.16.0 v1.17.0 v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.35.0 v1.36.0 v1.36.1 v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.43.0 v1.44.0 v1.45.0 v1.46.1 v1.47.0 v1.50.0 v1.51.0 v1.52.0 v1.53.0 v1.54.2)

# 01 — Delta: the consolidated span bundle

Written 2026-09-24 for plan item KC-24 of the 2026-09-23 review and standards-audit remediation
(finding KICKCD-A-01), on branch `feat/2026-09-23-review-audit-remediation`. It is the sanctioned
record for a lapsed span (`audit-review-history`, standard v2.65.0): one folder named for the first
and last unrecorded tags, holding `01_DELTA.md` and `05_SUMMARY.md` only. Nothing is re-vendored
here and no code changes. The per-tag deliberation files (02 to 04) are absent on purpose, and no
per-tag folders are back-filled: these tags arrived through bulk collection sweeps, or folded into
feature commits, with no per-tag adoption run, so there is no deliberation to record.

## The true previous base

Line 1 names the first and last **unrecorded** tags, not a delta base. The last tag this store
recorded before the span is **v1.15.0** (`docs/revendor/2026-08-25/`, the store's first bundle and
the audit horizon), vendored at `9907d8d`. Read as a delta, the span runs **v1.15.0 -> v1.54.2**,
and the next recorded bundle, `docs/revendor/2026-09-23-v1.55.0/`, names v1.54.2 as its base
(vendored at `2cee93f`).

Seven tags inside that range already have their own bundles and are not in the span list: v1.25.0
(`2026-09-03/`), v1.30.0 (`2026-09-12/`), v1.31.0, v1.32.0, v1.33.0 (`2026-09-12-v1.3x.0/`) and
v1.34.0 (`2026-09-13-v1.34.0/`). Two of the bare-dated ones name a second tag on line 1 only as
their base (v1.24.0 in `2026-09-03/`, v1.29.0 in `2026-09-12/`). The audit check reads only the last
tag of a bare-dated line 1, so those two count as unrecorded and are listed here. Those frozen
bundles are not edited.

Tags the library cut that this addon never vendored are not in the span, because no commit here
carried them: v1.20.0, v1.21.0, v1.22.0, v1.40.0, v1.41.0, v1.46.0, v1.48.0, v1.48.1, v1.49.0,
v1.49.1, v1.54.0 and v1.54.1.

## How the list was derived

The `AUDIT.md` re-vendor comparison (WowAddonStandards v2.65.0), run before this bundle existed:

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)          # -> 2026-08-25
git log --since="$horizon 00:00" --format=%H -- libs/LibKa0s tests/_kit | while read -r c; do
  git show "$c:CLAUDE.md" 2>/dev/null |
    grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+' |
    grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
done | sort -uV > vendored.txt                                        # 38 tags, 39 commits
# recorded.txt: the recorded-side loop over docs/revendor/*/           # 9 tags
grep -vxF -f recorded.txt vendored.txt                                 # 29 tags, the span above
```

Every in-scope commit resolved a tag from its `CLAUDE.md` provenance line. After this bundle, the
same comparison prints nothing.

**Correction to the item text.** KC-24 and the audit named 25 tags, v1.18.0 to v1.53.0. That count
used a bare-date `--since`, which drops the horizon day's own commits (v1.16.0 and v1.17.0 on
2026-08-25), and walked `libs/LibKa0s` alone, which misses the kit-only v1.43.0 and v1.54.2
re-vendors. The v2.65.0 comparison finds 29 tags in 29 commits. The folder is named for the span it
actually covers, `2026-09-24-v1.16.0-v1.54.2`, not the item's `v1.18.0-v1.53.0`.

## The 29 vendoring commits

One commit per tag, from `git log --format='%h %ad %s' --date=short -- libs/LibKa0s tests/_kit`,
each joined to the tag its `git show <sha>:CLAUDE.md` provenance line (`Bundles [LibKa0s] vX.Y.Z`)
names. "Folded" marks a copy that rode inside a feature commit rather than standing alone
(`versioning-git` makes that a SHOULD, not a MUST).

| Tag | Commit | Date | Subject |
|---|---|---|---|
| v1.16.0 | `39e2595` | 2026-08-25 | Re-vendor LibKa0s v1.16.0 |
| v1.17.0 | `fc3be83` | 2026-08-25 | Re-vendor LibKa0s v1.17.0 |
| v1.18.0 | `55014e0` | 2026-08-26 | Re-vendor LibKa0s v1.18.0 and take the library's resetProfile field |
| v1.18.1 | `f952fc6` | 2026-08-26 | Re-vendor LibKa0s v1.18.1: the landing logo stops pooling its texture |
| v1.19.0 | `2cb5661` | 2026-08-27 | Carry LibKa0s v1.19.0 |
| v1.23.0 | `8f30146` | 2026-09-01 | Carry LibKa0s v1.23.0 |
| v1.24.0 | `c5682dd` | 2026-09-02 | feat(settings): annotations re-laid out, cast bar split, spells by drag |
| v1.26.0 | `e3274f6` | 2026-09-08 | M3-01: re-vendor LibKa0s v1.26.0, and keep the media rows deferred |
| v1.27.0 | `a606707` | 2026-09-08 | M4-01: adopt LibKa0s v1.27.0, and wire the gate that came with it |
| v1.28.0 | `fca318f` | 2026-09-09 | re-vendor LibKa0s v1.28.0 - the perf usage block renders correctly |
| v1.29.0 | `d81d2a5` | 2026-09-09 | re-vendor LibKa0s v1.29.0 - the JSON dump folds into the report step |
| v1.35.0 | `b4c6eaf` | 2026-09-14 | Re-vendor LibKa0s v1.35.0 (Options 18.16.5.3, kit 20) |
| v1.36.0 | `0eb71b5` | 2026-09-15 | Re-vendor LibKa0s v1.36.0 |
| v1.36.1 | `eddb3d9` | 2026-09-15 | Re-vendor LibKa0s v1.36.1: fix pooled CheckBox gold-fill leak |
| v1.36.2 | `2110c4a` | 2026-09-15 | Re-vendor LibKa0s v1.36.2: drop grid-cell yellow fill, ASCII-only strings |
| v1.37.0 | `233a5d8` | 2026-09-16 | Re-vendor LibKa0s v1.37.0 |
| v1.38.0 | `880c80b` | 2026-09-16 | Re-vendor LibKa0s v1.38.0: a bare /kcd opens the settings panel |
| v1.39.0 | `9344017` | 2026-09-16 | Re-vendor LibKa0s v1.39.0: the launcher major and the minimap seam |
| v1.42.0 | `2c6733b` | 2026-09-17 | Disabling the addon stands it down, and a perf run takes the same latch |
| v1.43.0 | `b70f13a` | 2026-09-17 | Re-vendor LibKa0s v1.43.0: kit revision 23 bounds every run and stops holding built instances |
| v1.44.0 | `95ad2c3` | 2026-09-19 | Re-vendor LibKa0s v1.44.0 |
| v1.45.0 | `9f433db` | 2026-09-19 | Re-vendor LibKa0s v1.45.0 |
| v1.46.1 | `fecabd4` | 2026-09-19 | Re-vendor LibKa0s v1.46.1 |
| v1.47.0 | `af67af1` | 2026-09-20 | Re-vendor LibKa0s v1.47.0 |
| v1.50.0 | `9fe9f42` | 2026-09-21 | Re-vendor LibKa0s v1.50.0 |
| v1.51.0 | `0e13ed3` | 2026-09-22 | Re-vendor LibKa0s v1.51.0 |
| v1.52.0 | `1706cbd` | 2026-09-22 | Re-vendor LibKa0s v1.52.0 |
| v1.53.0 | `3b2832b` | 2026-09-22 | Re-vendor LibKa0s v1.53.0 |
| v1.54.2 | `2cee93f` | 2026-09-22 | Adopt the kit's US-English gate, and delete the copy this repo was keeping |

Folded copies: v1.24.0 (`c5682dd`, the settings revamp), v1.42.0 (`2c6733b`, the stand-down
latch) and v1.54.2 (`2cee93f`, kit revision 24's US-English gate; the library bytes are identical
to v1.53.0). v1.43.0 (`b70f13a`) is kit-only as well. Each commit rolled the provenance line in the
same commit as the copy, the pairing `tests/test_vendor_sync.lua` now enforces.
