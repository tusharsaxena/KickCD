# 03 — Decisions: LibKa0s v1.29.0 → v1.30.0

This run was non-interactive. The owner's standing answers for the v1.30.0 rollout (2026-09-12)
were:

- **adopt** = delete a local shim only where the kit now gives the same contract and the suite
  stays green;
- **decline** = anything that needs a harness migration, such as a `wow_mock` that replaces the
  kit's `NewAddon` / AceEvent / LibStub wholesale so a kit fix cannot reach it.

Declines are **not filed by this run**. The owner asked for them to be returned to the
orchestrating session as proposed issues. No GitHub issue was created and nothing was pushed.

| Candidate | Decision | Reason |
|---|---|---|
| #28 runner-mode case | delivered (class A) | Arrived with the copy; 870 → 871, all green. |
| #27 `AceGUI:Release` | **declined: harness migration** | The local AceGUI fake (`tests/wow_mock.lua:782`) replaces the kit's, so the kit's `Release` never reaches this suite. No shim to delete. |
| #29 AceEvent event half | **declined: harness migration** | The local `embedAceEvent` (`tests/wow_mock.lua:493`, event no-ops at `:510-513`) replaces the kit's Embed. No shim to delete. |
| #30 `Printf` | **declined: harness migration** | The local `embedAceConsole` (`tests/wow_mock.lua:526`) replaces the kit's. The addon uses no `Printf`. No shim to delete. |

The three declines are one proposed issue: *adopt the kit's Ace fakes in `tests/wow_mock.lua`*.
Severity low: nothing is broken today, but the suite does not see these four client behaviors and
future kit fixes to the Ace fakes will not reach it either.
