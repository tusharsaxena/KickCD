Delta: LibKa0s v1.64.0 -> v1.65.0 (span: v1.64.0 v1.65.0)

Back-filled on 2026-10-01 by GI-KC-RV, beside `2026-10-01-v1.66.0/`. Two tags this addon vendored went
without a bundle of their own.

Listing (the skill's Step 3h, run before the v1.66.0 copy, from the repo root):

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)
# payload commits since the horizon, plus CLAUDE.md commits that roll the provenance line,
# mapped to the tag each one's CLAUDE.md names        -> vendored.txt
# the tags the existing bundles record                -> recorded.txt
grep -vxF -f recorded.txt vendored.txt
```

Output:

```
v1.64.0
v1.65.0
```

The commits that carried them: `ffe7a1a` (DL-KC-01, v1.64.0, kit 33), `a5989be` (DL-KC-03, the final
v1.64.0, kit 34) and `fa8aead` (DG-KC-01, v1.65.0, kit 34).
