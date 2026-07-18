# 02 — Deviations

**Addon:** Ka0s KickCD · **Date:** 2026-07-18 · **Standard:** v2.7.0 (2026-07-17) · **Prefix:** `KCD-`

Severity: **MUST** = non-negotiable (bug); **SHOULD** = strongly preferred (deviation needs a code comment justifying it). IDs are stable across runs — a recurring deviation keeps its ID. Cross-references use the `filename-§N` scheme. Evidence for every row is in `03_EVIDENCE.md`; remediation is keyed to these IDs in `04`/`05`.

**Context.** The first audit (`docs/audits/2026-07-12/`, IDs `KCD-01`..`KCD-23`) was measured against v1.0.0 and fully remediated. This run measures against v2.7.0. All of `KCD-01`..`KCD-18`, `KCD-20`..`KCD-23` remain **closed** (spot-verified in `03_EVIDENCE.md`). The deviations below are new gaps (`KCD-24`..`KCD-29`) plus one recurring SHOULD (`KCD-19`).

## MUST failures

| ID | § | Severity | Deviation | Fix direction |
|----|----|----------|-----------|---------------|
| KCD-24 | `layout-§1`, AP-16 | MUST | `settings/Panel.lua` is **1641 LOC**, over the 1500 hard cap. (Was 1266/1270 and "on notice" at the prior audit; it has since grown over the cap.) | Peel into 2–3 siblings in `settings/` — e.g. `Panel.lua` (register + landing page + header/skin) + `Panel_Widgets.lua` (the widget-maker primitives + `refreshers`) + `Panel_Render.lua` (`RenderUnitPanel` / group rendering / Defaults). Keep the schema-driven contract intact; add covering tests for any pure helper moved. |
| KCD-25 | `slash-commands-§4` | MUST | Three chat lines end in a trailing `:` — the help header (`v… — slash commands (…):`), `"debug subcommands:"`, and `"spells subcommands:"`. The no-trailing-colon rule applies to **every** chat line; a list is introduced by its header text alone. | Strip the trailing `:` from all three. While there, align the help header to the canonical `<tag> v<version> slash commands (…)` shape (drop the ` — ` em-dash) so it reads identically to the rest of the collection. |
| KCD-26 | `documentation-§2`, `documentation-§6`, AP-34 | MUST | Root `CLAUDE.md`'s standards section is titled `## The standard is the source of truth`, not the canonical `## Standards compliance (read first)`, and omits the closing "when in doubt, treat conformance as a hard requirement and ask." line. The substance (flag deviations; user classifies as accepted-deviation vs change-the-standard) is present. | Rename the heading to `## Standards compliance (read first)`; add the closing line. Keep it the second section after the adherence line (documentation-§2 ordering). |
| KCD-27 | `documentation-§6`, AP-34 | MUST | `docs/agent-context.md` `## Hard rules` does **not** open with the "Conform to the Ka0s WoW Addon Standard" rule that points back to the root `CLAUDE.md` "Standards compliance" section (its first bullet is the no-auto-commit rule). The four-places standards-reference requirement (documentation-§6) is therefore unmet at place #4. (H1 also reads `# CLAUDE.md — working notes…` rather than an agent-context title.) | Insert the canonical conform-to-standard bullet as the **first** item under `## Hard rules`, linking `../CLAUDE.md` "Standards compliance". Retitle the H1 to `# agent-context — Ka0s KickCD` (or similar). |
| KCD-28 | `options-ui-§2` | MUST | The combat panel-open **refusal** is correct (it refuses, does not defer-and-replay), but the notice is neither a **grey** notice nor the canonical text: it prints `Cannot open settings during combat.` with only the cyan `NS.PREFIX` tag. Canonical: a grey-coded `cannot open settings during combat — Blizzard's category-switch is protected`. | Wrap the message body in the grey colour code and use the canonical wording; update the `enUS.lua` locale value. |

## SHOULD failures

| ID | § | Severity | Deviation | Fix direction |
|----|----|----------|-----------|---------------|
| KCD-19 | `layout-§1` | SHOULD | `modules/Castbar.lua` (1473) and `modules/IconGrid.lua` (1007) sit in the 1000–1500 "on notice" band. Both carry justifying header comments (the SHOULD deviation is documented), so this is a watch item, not a fresh gap — but Castbar has crept from 1426 toward the cap. | Keep watching; plan a Castbar peel (config-driven build vs. per-frame update) before it crosses 1500. No urgent action. |
| KCD-29 | `library-stack-§3` | SHOULD | `libs/AceTimer-3.0/` is vendored but **not** loaded in the TOC and **not** used — the addon schedules via `C_Timer.After` directly. library-stack-§3 says "vendor only libs the addon actually `LibStub` … prune dead weight." (Tension: library-stack-§1 lists AceTimer as a mandatory Ace3 lib — this is a standard-vs-addon call for the user.) | Either delete `libs/AceTimer-3.0/` (matches §3 "vendor what you use"), or adopt AceTimer for the timer paths and load it in the TOC. Flag to the user as a §1-vs-§3 decision per the repo's deviation policy. |

**Counts — MUST: 5 · SHOULD: 2** (of which KCD-19 recurs from the prior run and is already mitigated with comments).

**Anti-pattern coverage (this run):** AP-16 (KCD-24), AP-34 (KCD-26, KCD-27). Not triggered: AP-1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/17/18/19/20/21/22/23/24/25/26/27/28/29/30/31/32/33/35/36/37/38/39 — the corresponding rules are met (see `01_CURRENT_STATE.md` and `03_EVIDENCE.md`). Notably compliant: #38 (libs listed directly, no `embeds.xml`), #39 (in-place `refreshers` panel refresh; AceGUI Defaults button), #36 (printer via `NS.Util.print`), #32/#33 (per-target bus receivers + fidelity-modelling mock).
