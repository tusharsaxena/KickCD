# 04 — Technical Design (Remediation)

**Addon:** Ka0s KickCD · **Date:** 2026-07-18 · **Standard:** v2.7.0 (2026-07-17)

How to close each gap in `02_DEVIATIONS.md`. Keyed to deviation IDs. This is design only — the audit changes no code. Every change lands behind the green gate (`lua tests/run.lua` + `luacheck .`).

---

## KCD-24 — Peel `settings/Panel.lua` (1641 → under 1500) · `layout-§1`, AP-16

**Shape.** `settings/Panel.lua` mixes three concerns: (a) category registration + landing page + header/skin, (b) the reusable widget-maker primitives that also register `refreshers`, and (c) `RenderUnitPanel` / per-group rendering + the Defaults reset helpers. Peel by concern into siblings in `settings/`:

- `settings/Panel.lua` — keep: constants (`PADDING_X`, `HEADER_TOP`, `DEFAULTS_W`, …), `NS.Panel:Register`, landing-page render, header (title + AceGUI Defaults button + divider), `OnShow` wiring, `RefreshAllPanels`, `RestoreDefaults`/`RestoreAllDefaults`.
- `settings/Panel_Widgets.lua` — the widget-maker helpers (slider/dropdown/checkbox/colour/button makers) and their `ctx.refreshers[#+1] = …` registrations.
- `settings/Panel_Render.lua` — `RenderUnitPanel`, group rendering, two-column pairing, the schema-error printer.

**Contract to preserve.** All helpers currently hang off one `Helpers`/`NS.Panel` table populated at file load; keep them on the same table so call order is irrelevant (architecture-§3 idempotent publish). Add the two new files to the TOC `# Settings` block **before** `settings/General.lua` (they must load before the per-tab files that call the makers). Update the load-order block per toc-file-§5.

**Risk.** Medium — this is layout-only motion of a live panel. Mitigate by moving whole functions verbatim (no signature changes) and running the existing panel/schema suites plus `luacheck` after each move. Any pure helper relocated gains/keeps a covering test (testing TDD gate).

**Ordering.** Independent of the other fixes; do it in its own sprint so the diff stays reviewable.

## KCD-25 — Strip trailing colons + align help header · `slash-commands-§4`

Three one-line edits in `core/KickCD.lua`:
- `:227` — remove the trailing `:` and the ` — `; render `<tag> v<version> slash commands (…alias…)` so the header matches the canonical form and the collection.
- `:243` — `"debug subcommands"` (no colon).
- `:860` — `"spells subcommands"` (no colon).

**Test.** Extend the slash/help suite (or add one) to assert no printed help/subheader line ends in `:` — a cheap regression guard so the rule can't silently regress. **Risk:** trivial.

## KCD-26 — Canonical CLAUDE.md standards heading · `documentation-§2`/`§6`, AP-34

In root `CLAUDE.md`: rename `## The standard is the source of truth` → `## Standards compliance (read first)`; keep the existing two-outcome body (accepted deviation vs change the standard); append the closing line "When in doubt, treat conformance as a hard requirement and ask." Order it right after the adherence line (documentation-§2 ordering). Docs-only; no test impact.

## KCD-27 — Standards rule as first Hard rule in agent-context · `documentation-§6`, AP-34

In `docs/agent-context.md`: insert as the **first** `## Hard rules` bullet the canonical conform-to-standard rule (documentation-§6 wording), linking `../CLAUDE.md` "Standards compliance". The existing no-auto-commit rule becomes the second bullet. Retitle H1 to an agent-context title (e.g. `# agent-context — Ka0s KickCD`). Docs-only.

> KCD-26 + KCD-27 together restore the four-places standards reference (TOC + README badge already satisfy places 1–2). Do them in one docs sprint.

## KCD-28 — Grey, canonical combat-refuse notice · `options-ui-§2`

- Change the `enUS.lua` value for the combat-refuse key to the canonical `cannot open settings during combat — Blizzard's category-switch is protected`.
- Wrap the body in a grey colour code before it reaches `Util.print` (which prepends the cyan tag) — e.g. a `|cff9d9d9d…|r` (or the project's existing grey constant) so the notice renders grey while the `[KCD]` tag stays cyan. Prefer a single grey constant in `core/Constants.lua` if one is added, to avoid a per-call literal.
- Keep the refusal semantics unchanged (already correct: refuse + return, no defer-replay). **Risk:** trivial; visual-only.

## KCD-19 — Castbar/IconGrid on-notice band · `layout-§1` (watch)

No change required now — both files are under the cap with documented justifications. When Castbar next needs a feature, peel the config-driven build path (widget construction vs. per-frame update) into a sibling to buy headroom before 1500. Tracked, not scheduled.

## KCD-29 — AceTimer dead weight · `library-stack-§3` (user decision)

Two clean options; surface to the user per the repo's deviation policy (this is a `library-stack-§1`-vs-`§3` tension):
1. **Prune** `libs/AceTimer-3.0/` — matches §3 "vendor what you use"; the addon uses `C_Timer.After`. Update `.pkgmeta`/`.luacheckrc` only if they name it (they don't). Smallest, cleanest.
2. **Adopt** AceTimer for the timer paths and add it to the TOC `# Libraries` block — matches §1's "mandatory" listing. Larger, and unnecessary given `C_Timer` suffices.

Recommended: option 1 (prune), with a one-line note that KickCD schedules via `C_Timer` by design. No functional risk either way.
