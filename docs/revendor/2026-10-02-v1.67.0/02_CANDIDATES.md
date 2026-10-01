# Candidates (KickCD)

Listed, not interviewed: the 2026-10-02 census adoption bundle
(`Ka0sAddonsCommonTasks/docs/2026-10-02-LIBKA0S_CENSUS_ADOPTION/`, `01_DESIGN.md` D1-D3) decided every
adoption in advance and assigns each to an item.

- **Options descriptor `addonName`** (Options minor 28 / OptionsIdList minor 3, LibKa0s#42). Taken by
  **CA-KC-NM**: `settings/OptionsSetup.lua` keeps its first vararg (`local addonName, NS = ...`) and passes
  `addonName = addonName`. Latent here: KickCD builds no `O.IdList`, so no help mark draws either way.
- **`MakeResizable`'s `canResize`, `onResizeStop` and `gripParent`** (Core minor 10, LibKa0s#41). Taken by
  **none**: KickCD owns no resize grip (its only grips are the library's debug console, copy window and
  perf panel), and the design's grip hosts are BankLedger, LootHistory and MultiMeters.
- **KickCD#36** (the census's slash vocabulary and `Core.SECRET` adoption) moves no surface in this tag; it
  is CA-KC-01 and CA-KC-02 of the same bundle, on surfaces already vendored at v1.66.0.
