Delta: LibKa0s v1.106.0 -> v1.106.0 (span: v1.106.0)

Written by the v1.107.0 re-vendor (AF-RV-KC of Ka0sAddonsCommonTasks `docs/2026-11-19-ADOPTION_FEEDBACK/`), whose 3h walk found one tag this addon vendored with no bundle:

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)   # 2026-08-25
# the audit's walk over libs/LibKa0s and tests/_kit, plus CLAUDE.md commits that roll the line,
# minus the tags named by existing bundles (wow-revendor-libka0s 3h)
```

Output: `v1.106.0`, vendored in `bb5a668` ("Re-vendor LibKa0s v1.106.0 (Widgets minor 28: the HUD dock guards its measurements, RangeMaster#17)").
