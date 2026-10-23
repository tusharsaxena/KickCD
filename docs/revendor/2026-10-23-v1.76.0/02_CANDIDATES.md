# Candidates (KickCD, LibKa0s v1.75.2 -> v1.76.0)

Sources: `git -C ../LibKa0s log --oneline v1.75.2..v1.76.0` (8 commits), the tag's `CHANGELOG.md`
v1.76.0 block (`CHANGELOG.md:13-101`, with *What a consumer owes* at `:84`), and the API documents
of the two majors that moved: `docs/api/Sim/version-2.3.5-docs.md` and
`docs/api/Widgets/version-14.1.4.3.2-docs.md`.

Every decision below was taken by the run's plan (`items.json` and `inputs/OWNER_SCOPE.md` of the
2026-10-23 bundle in Ka0sAddonsCommonTasks), not by an interview here. There is no
`03_DECISIONS.md` or `04_EXECUTION_PLAN.md`, and no GitHub issue is filed.

## A. Delivered on the re-vendor alone (not offered)

Nothing KickCD uses changes on screen: it hosts no Sim session and draws no strip, and `W.ReorderList`
is untouched.

## B. Decided: adopt in this run (not in this commit)

- **`LibKa0s-Sim-1.0` at 2.3.5** (class C, whole module): `/kcd sim` with KickCD#38's scenarios.
  Evidence: `CHANGELOG.md:26` (the auto-run) and `docs/api/Sim/version-2.3.5-docs.md:22`. Additive:
  new files (`core/SimSetup.lua`, `modules/SimWorld.lua`, `modules/Sim.lua`, `modules/SimDrivers.lua`,
  `modules/SimScenario.lua`) behind prerequisites in `NS.Compat` and the event dispatch. **Decided
  adopt** by KC-01 to KC-08 and KC-10 (OWNER_SCOPE A and B.4). KickCD#38 closes on merge.
- **`W.TestStrip(parent, { kind = "sim" })`** (Widgets 14, class B): the sim strip on top of the
  party icon grid while a simulation runs. Evidence: `CHANGELOG.md:49`,
  `docs/api/Widgets/version-14.1.4.3.2-docs.md:27`. Additive. **Decided adopt** by KC-09
  (OWNER_SCOPE B.2).

## C. Decided: not adopted

- **The amber `TestStrip`** (`kind = "test"`). KickCD has no test mode (OWNER_SCOPE B.2).
