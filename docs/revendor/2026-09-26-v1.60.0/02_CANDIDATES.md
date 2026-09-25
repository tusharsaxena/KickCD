# 02 — Candidates: LibKa0s v1.58.0 -> v1.60.0

Sources: `git -C ../LibKa0s log --oneline v1.58.0..v1.60.0` (18 commits), the library's
`CHANGELOG.md` v1.59.0 and v1.60.0 blocks, and the `Since` markers in
`docs/api/DebugLog/version-14.1-docs.md`, `docs/api/Slash/version-16-docs.md` and
`docs/api/Widgets/version-10.3-docs.md`. The two 3g blockers (the DebugLog stub members and the kit
suite's declaration) are not candidates; they land in the copy commit.

## A. Delivered on the re-vendor alone

- **`diagnostics` is live while disabled** (Slash 16, `LIVE_VERBS`). `settings/Slash.lua:428-433`
  builds the live set from `SlashLib.LIVE_VERBS`, so the verb reaches this addon's gate with no
  change. It does nothing until the verb is registered (DR-KC-03).
- **The 3000-line console** (DebugLog 14, `MAX_BUFFER` 1500 -> 3000, `BUFFER_SLACK` 64 -> 128). The
  console window, copy window and status line read the constant.
- **`lib.TIME_COPY`**, the hand-set copy-timing switch (DebugLog 14). Off by default.
- **Kit revision 27** and its `test_diagnostics_contract.lua`, declared in `tests/run.lua` and a
  declared skip until `Kit.diagnostics` is wired.

## B. Host change required

| # | Candidate | Evidence | Would touch | Blast radius | Plan's ruling |
|---|---|---|---|---|---|
| B1 | The diagnostics helper: `D:RunDiagnostics`, the `brandName` and `diagnostics` descriptor fields, `D:DebugVerb` | CHANGELOG v1.60.0 "DebugLogDiagnostics minor 1"; `DebugLog/version-14.1-docs.md:56-120`, `:525-526` | `core/DebugLogSetup.lua`, a new `modules/Diagnostics.lua`, `core/KickCD.lua` (`COMMANDS`, `DEBUG_COMMANDS`), the TOC, tests | Additive (a new report and verb) | Adopt in **DR-KC-03**, after DR-KC-02's emit seams |
| B2 | Slash 16's `diagnostics` reserved verb as a registered command | CHANGELOG v1.60.0 "Slash minor 16"; `Slash/version-16-docs.md` | `core/KickCD.lua` `COMMANDS` | Additive | Adopt in **DR-KC-03**, with B1 |
| B3 | `WidgetsDragHandle` close mark (`spec.onClose`, `closeIcon`, `closeTooltip`) | CHANGELOG v1.59.0 "WidgetsDragHandle minor 3"; `Widgets/version-10.3-docs.md` | `modules/Castbar_Handle.lua` | Additive | **Not adopted.** Owner ruling Q1 / DR-OW-03 (X-03): KickCD gets no X |

## C. Whole-module adoption

None. No major is new; `DebugLogDiagnostics.lua` is a second file of a major this addon already
consumes.
