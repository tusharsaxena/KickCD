# Candidates (KickCD, LibKa0s v1.71.0 -> v1.75.0)

Sources: `git -C ../LibKa0s log --oneline v1.71.0..v1.75.0` (56 commits), the CHANGELOG blocks
v1.72.0 to v1.75.0 (each with its *What a consumer owes*), and the API documents of the majors that
moved or arrived: `docs/api/Glow/version-1-docs.md`, `docs/api/Sim/version-1.1.1-docs.md`,
`docs/api/Widgets/version-13.1.4.3.2-docs.md`, `docs/api/Item/version-3-docs.md`,
`docs/api/Options/version-29.2.34.2.5.9.1.7.4.2.1-docs.md`, `docs/api/Media/version-5.1-docs.md`,
`docs/api/Perf/version-15.1.1.7-docs.md`, `docs/api/DebugLog/version-20.3.1-docs.md` and
`docs/api/testkit/version-41-docs.md`.

Every decision below was taken by the run's plan (`items.tsv` and `OWNER_SCOPE.md` of the
2026-10-22 bundle in Ka0sAddonsCommonTasks), not by an interview here. There is no
`03_DECISIONS.md` or `04_EXECUTION_PLAN.md`, and no GitHub issue is filed for a decline.

## A. Delivered on the re-vendor alone (not offered)

- **Options 29: a structural refresh keeps the page's scroll offset.** A Spells-page write that
  re-renders the page no longer drops the player back to the top.
- **DebugLogDiagnostics 3**: `/kcd diagnostics` names Glow and Sim (with SimTimeline, SimPanel) on
  the `LibKa0s running:` line when the client runs them.
- **Kit 41**: a crashed or bounded lizard run is a complexity fail, never a pass; the icon gate in
  `tests/test_vendor_sync.lua`.
- **Core 11, DebugLog 20, OptionsIdList 5, PerfPanel 7**: comment-only.

## B. Decided: adopt in this run

- **`LibKa0s-Glow-1.0`** (`Glow.Start`, `Glow.Stop`): the stateless LibCustomGlow driver for the
  icon grid's ready glow. **Decided adopt**, by item **KC-01** (M3), under OWNER_SCOPE A (#56), which
  names KickCD an adopter through a `core/GlowSetup.lua` seam publishing `NS.GlowLib`. Not done in
  this commit.

## C. Decided: not adopted in this run

- **`W.SearchBox`** (Widgets 13, #52). KickCD has no filter bar; the adopters are LootHistory,
  BankLedger and DropWatcher.
- **`W.TestStrip`** (Widgets 13, #48). KickCD has no test-mode window band; adopting it would also
  owe the `info` icon.
- **The step panel**. Not public (LK-11 outcome B): it is Sim-private, so there is nothing to adopt.
- **`LibKa0s-Sim-1.0`** (#54). KickCD has no simulator in this run. The candidate stays tracked by
  **KickCD#38**, which stays open (`state:triaged`), repointed at Sim-1.0 by OWNER_SCOPE A.
- **`Item.BonusIDsFromLink`** (Item 3, #51). KickCD does not look up `LibKa0s-Item-1.0` (the settled
  decline, issue #14).
- **`O.Drawer`** (OptionsDrawer 1). KickCD's pages have no collapsible subject; the stub carries it
  as an inert no-op (blocker 1 in `01_DELTA.md`).
- **`Perf.Note(..., false)`** (Perf 15). KickCD's `pollSpell` notes always name their parent or
  leave it unstated; no top-level-only observation exists to record.
