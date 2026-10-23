Delta: LibKa0s v1.75.1 -> v1.75.2 (span: v1.75.1 v1.75.2)

Back-filled by item `KC-RV` of the 2026-10-23 run "sim auto-run, QC preview selector, mode strips,
MM/KCD simulators", before its own re-vendor of v1.76.0 (`../2026-10-23-v1.76.0/`). KickCD carried
both tags through the post-run sweeps of the 2026-10-22 run, and neither got a bundle.

## The listing (3h of `/dev-copilot:wow-revendor-libka0s`)

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)        # 2026-08-25
# vendored: tags named by the CLAUDE.md provenance line at every payload commit since the horizon,
# plus every CLAUDE.md commit that rolled the line
# recorded: the tag each docs/revendor/ folder names (line 1 of 01_DELTA.md for a span)
grep -vxF -f recorded.txt vendored.txt
# v1.75.1
# v1.75.2
```

The two commits that carried them, each a provenance roll plus `libs/LibKa0s/SimPanel.lua` alone:

```sh
git log --format='%h %s' -- libs/LibKa0s tests/_kit | head -2
# 6c70977 Re-vendor LibKa0s v1.75.2 (SimPanel minor 4)
# 5ce5308 Re-vendor LibKa0s v1.75.1 (SimPanel minor 3)
```

Both tags are pushed (`git -C ../LibKa0s ls-remote --tags origin v1.75.1 v1.75.2` answers both).
