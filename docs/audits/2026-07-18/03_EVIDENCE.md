# 03 — Evidence

**Addon:** Ka0s KickCD · **Date:** 2026-07-18 · **Standard:** v2.7.0 (2026-07-17)

`file:line` citations backing every deviation in `02_DEVIATIONS.md`, plus evidence for the key compliance claims (including that the prior run's deviations stay closed). Line numbers are from the working tree at audit time.

---

## Deviation evidence

### KCD-24 — `settings/Panel.lua` over the 1500 LOC cap (`layout-§1`, AP-16)
```
$ wc -l settings/Panel.lua
1641 settings/Panel.lua
```
- The file is the single largest source in the addon (next: `modules/Castbar.lua` 1473, `settings/Spells.lua` 976, `core/KickCD.lua` 949).
- Prior run recorded it at 1266 LOC and "on notice" (KCD-19 in `docs/audits/2026-07-12/02_DEVIATIONS.md`); it has grown past the hard cap since.

### KCD-25 — Trailing-colon chat lines (`slash-commands-§4`)
- `core/KickCD.lua:227` — help header:
  ```lua
  p(self, "v" .. addonVersion() .. " — slash commands (|cffffff00/kickcd|r is an alias for |cffffff00/kcd|r):")
  ```
  Ends with `):` and uses ` — ` where the canonical header is `<tag> v<version> slash commands (…)`.
- `core/KickCD.lua:243` — `p(self, "debug subcommands:")` — trailing `:` before the debug command rows.
- `core/KickCD.lua:860` — `p(self, "spells subcommands:")` — trailing `:` before the spells command rows.
- Rule: "**No** chat line the addon prints … **MUST** end in a trailing `:`. Introduce a list with the header text alone." (slash-commands-§4)

### KCD-26 — Root `CLAUDE.md` standards-section heading (`documentation-§2`/`§6`, AP-34)
- `CLAUDE.md:7` — `## The standard is the source of truth` (should be `## Standards compliance (read first)` per documentation-§2 #3).
- `CLAUDE.md:9-15` — substance is present (flag deviations; user decides "intentional deviation" vs "standard should change"); the closing canonical line "when in doubt, treat conformance as a hard requirement and ask." is absent.
- AP-34: "a `CLAUDE.md` with no `## Standards compliance (read first)` section" is non-compliant.

### KCD-27 — `docs/agent-context.md` Hard rules do not open with the standard rule (`documentation-§6`, AP-34)
- `docs/agent-context.md:15` — `## Hard rules`.
- `docs/agent-context.md:17` — first bullet is "**Never auto-stage, auto-commit, or auto-push.**" — not the conform-to-the-standard rule.
- documentation-§6 #4 requires the standards rule as the **first** `## Hard rules` bullet, pointing back to the root `CLAUDE.md` "Standards compliance" section. No such bullet exists in the file.
- `docs/agent-context.md:1` — H1 `# CLAUDE.md — working notes for future sessions` (mislabeled for the agent-context brief).

### KCD-28 — Combat-refuse notice not grey / not canonical (`options-ui-§2`)
- `core/KickCD.lua:917-924` — `NS:OpenSettings` gates and refuses:
  ```lua
  local inCombat = (self.State and self.State.inCombat)
      or (_G.InCombatLockdown and _G.InCombatLockdown())
  if inCombat then
      self._openRetries = nil
      p(self, (self.L and self.L["Cannot open settings during combat."])
          or "Cannot open settings during combat.")
      return
  end
  ```
- `locales/enUS.lua:165` — `L["Cannot open settings during combat."] = "Cannot open settings during combat."` — no grey colour code, and not the canonical `cannot open settings during combat — Blizzard's category-switch is protected`.
- Compliant part: it **refuses and returns** (no defer-and-replay, no protected `OpenToCategory` call under lockdown) — options-ui-§2's core MUST is met; only the notice styling/wording deviates.

### KCD-19 — On-notice LOC band (`layout-§1`, recurring/mitigated)
- `modules/Castbar.lua` = 1473 LOC; header comment at `modules/Castbar.lua:3-5` documents the on-notice status and the `Castbar_Debug.lua` peel.
- `modules/IconGrid.lua` = 1007 LOC; header comment at `modules/IconGrid.lua:105-106` documents the `IconGrid_Render.lua`/`IconGrid_Layout.lua` peel.

### KCD-29 — AceTimer vendored but unused (`library-stack-§3`)
- `libs/AceTimer-3.0/AceTimer-3.0.lua` and `.xml` exist in the tree.
- `KickCD.toc` `# Libraries` block does **not** list AceTimer (grep: no match).
- No source references AceTimer / `ScheduleTimer` / `ScheduleRepeatingTimer` (grep over `core/ modules/ settings/`: no match). Scheduling is done with `C_Timer.After` (e.g. `core/KickCD.lua:939-941`).

---

## Compliance evidence (key claims + prior-run closures)

### TOC (`toc-file`)
- `KickCD.toc:1-14` — field order per toc-file-§1; single `## Interface: 120007`; `Author: add1kted2ka0s`; `X-Standard`, `X-Curse-Project-ID: 1530802`; `X-Wago-ID` a commented TODO (KCD-11/12/18 closed).
- `KickCD.toc:16-58` — `#`-sectioned listing, Libraries→Locales→Core→Defaults→Modules→Settings; libs listed **directly**, no `embeds.xml` (anti-pattern #38 clear; KCD confirmed compliant with the v2.5.0 rule).

### Namespace / bus (`architecture`, KCD-01/08/09 closed)
- `core/KickCD.lua:28` — `NewAddon(NS, "KickCD", …)`; no `_G.KickCD` table (module pattern documented `docs/agent-context.md:32-46`).
- Five `Ka0s_KickCD_*` messages; Spells panel uses a private `NS.NewBusTarget()` receiver (design noted `CLAUDE.md:30`, `docs/agent-context.md:22`).

### Compat (`compat`, KCD-10 closed)
- `core/KickCD.lua:100-107` — version read via `C_AddOns.GetAddOnMetadata` with in-code fallback (slash-commands-§3 `version` verb).
- `core/Compat.lua` (461 LOC) owns spell/spec/cast shims.

### Slash colour scheme (`slash-commands-§5`)
- `core/KickCD.lua:315-316` — shared `FormatKV` (gold key `ffff00`, white value `ffffff`).
- `core/KickCD.lua:448` — `Available settings` header green `33ff99`; `:459` — `[page]` group header azure `3399ff`; `:461`/`:480` — rows/echo via `FormatKV`.

### Debug console (`debug-logging`, KCD-06/07 closed)
- `modules/DebugLog.lua:353-388` — single `SetEnabled` seam; `:358` colour-coded ack (`40ff40` ON / `ff4040` OFF); `:363` `[Debug] logging enabled/disabled` via raw `Add`; `:372` `[Init] KickCD v%s, schema v%s, profile '%s'` summary on enable.
- Settings-change logged once at the schema write seam: `settings/Panel.lua:70` (comment referencing §10) and `settings/Panel.lua:100` — `NS.Debug("Set", "%s = %s", …)`.

### Options UI (`options-ui`, incl. v2.7.0 rules)
- `settings/Panel.lua:346-348` — Defaults button = `AceGUI:Create("Button")` (options-ui-§5 / anti-pattern #39 button clause: compliant).
- `settings/Panel.lua:388` — `refreshers = {}`; `:1300-1302` — `RefreshAllPanels` runs per-widget updater closures in place (options-ui-§11 in-place path; anti-pattern #39 clear).
- `settings/Panel.lua:1607` — lazy body build in `OnShow`.
- `core/KickCD.lua:917-924` — combat gate lives inside the open function (options-ui-§2 gate present; see KCD-28 for the notice).

### Testing / docs (`testing`, `documentation`)
- `lua tests/run.lua` → `108 passed, 0 failed`.
- `docs/test-cases.md` — generated inventory, `**Total** 108`; README badge `Tests-108%2F108_passing-green` (`README.md:7`) in lockstep.
- README badge row `README.md:3-7` — order WoW → CurseForge version → License → Standard → Tests (documentation-§1 canonical order).
- README section order (`README.md`): H1 → badges → logo → description → Screenshots → Usage (Slash commands + Settings panel) → How interrupt tracking works → FAQ → Troubleshooting → Issues and feature requests → Version History (documentation-§1 canonical; KCD-21 closed).
- `docs/` quartet present: `agent-context.md`, `ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`; plus generated `test-cases.md`. No `TODO.md` in the tree.

### Sanctioned media (not flagged, per v2.6.0)
- `media/fonts/JetBrainsMono-Regular.ttf` + `JetBrainsMono-OFL.txt` (debug console font) and `media/logos/kickcd.logo.tga`/`.jpg` (logo) are the two sanctioned shipped-media exceptions (debug-logging-§2, options-ui-§6 / layout-§3) — **not** deviations.
