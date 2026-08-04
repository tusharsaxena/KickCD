# KickCD — Current State (2026-08-04)

**Addon:** Ka0s KickCD · **Repo:** `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD` · **HEAD:** `249da4e` ("docs+i18n: adopt standard v2.17.1 — US English spelling throughout")
**Addon version:** 1.2.1 (`KickCD.toc:5`) · **Deviation prefix:** `KCD-`

---

## Standard resolved

**Audited against the Ka0s WoW Addon Standard v2.17.1 (2026-08-03)** — the version/date in the front
matter of `standards/STANDARDS.md`.

**Provenance — network fetch, byte-verified against the canonical checkout.** Unlike the previous
run in this environment, the raw endpoints responded. All 26 documents were fetched with
`curl -fsSL --max-time 12/15` from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master`:

- `AUDIT.md` (the playbook),
- `standards/STANDARDS.md` (the index),
- and **all 24 section files** discovered by following the index's Sections list —
  `layout`, `toc-file`, `library-stack`, `architecture`, `savedvariables`, `options-ui`,
  `standalone-windows`, `preview-mode`, `slash-commands`, `localization`, `events-frames-taint`,
  `public-api`, `compat`, `debug-logging`, `packaging`, `lint`, `testing`, `performance`,
  `documentation`, `audit-review-history`, `versioning-git`, `naming-cheatsheet`, `anti-patterns`,
  `open-evolutions`.

Every fetched file was then `diff`ed against the local canonical checkout at
`/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards` (clean tree, HEAD
`2141229 v2.17.1 — finish the v2.17.0 rollout`). **All three diffs were empty** — the fetched
playbook, index and section set are byte-identical to the checkout. No section was unassessed and no
rule was reconstructed from memory. Commands and output are in `03_EVIDENCE.md` §1.

**Prior runs:** `docs/audits/2026-07-12/` (v1.0.0, `KCD-01`..`KCD-23`, remediated) and
`docs/audits/2026-07-18/` (v2.7.0, `KCD-24`..`KCD-29`). This run continues the same prefix and
allocates `KCD-30`..`KCD-39`. Frozen prior folders were read, never edited.

---

## 1. Layout (`layout`)

The modular layout is in place: `core/`, `defaults/`, `settings/`, `locales/`, `modules/`, plus
`libs/`, `media/`, `tests/`, `docs/`. No source sits loose at the root; the root ships exactly
`README.md`, `CLAUDE.md`, `LICENSE`, `KickCD.toc` and the two config dotfiles.

Subfolders are lowercase; Lua files are PascalCase; suites are `test_<module>.lua`. Media uses typed
subfolders — `media/fonts/` (JetBrainsMono-Regular.ttf + OFL.txt), `media/logos/`
(`kickcd.logo.tga` runtime + `kickcd.logo.jpg` source), `media/screenshots/`. Nothing is loose in
`media/`.

No file exceeds the 1500 LOC hard cap. The largest are `modules/Castbar.lua` (1296),
`modules/IconGrid.lua` (1100) and `settings/Spells.lua` (1047) — all inside the 1000–1500 "on
notice" band; `modules/Castbar.lua:3-11` carries an explicit note recording the two peels that kept
it under the cap.

`docs/agent-context.md` **does not exist** (documentation-§3 / anti-pattern #49) and
`CLAUDE.md:19-34` states so and forbids its recreation.

## 2. TOC (`toc-file`)

`KickCD.toc:1-13` carries the required metadata block in the exact mandated field order —
`Interface: 120007`, `Title: Ka0s KickCD`, `Notes`, `Author: add1kted2ka0s`, `Version: 1.2.1`,
`IconTexture`, `SavedVariables: KickCDDB, KickCDPerfDB`, `OptionalDeps`, `DefaultState`,
`Category-enUS: Combat`, `X-License: MIT`, `X-Standard`, `X-Curse-Project-ID: 1530802`. No blank
lines inside the block; single Interface value; no `Dependencies`. `X-Wago-ID` is present only as a
commented-out placeholder (`KickCD.toc:14`), which the standard treats as omitted (`X-Wago-ID` is a
MAY).

Exactly two SavedVariables globals, in the mandated order. The file listing uses the required `#`
section comments in order — Libraries → Locales → Core → Defaults → Modules → Settings
(`KickCD.toc:16-71`) — every library is listed directly (no `embeds.xml`), and
`libs\LibKa0s\LibKa0s.xml` appears once, after Ace3 (`KickCD.toc:26`). The file ends with a single
trailing newline (CRLF, matching the repo `eol=crlf` policy).

`core/PerfSetup.lua` is last in the `# Core` block (`KickCD.toc:45`), before every `modules/` file —
i.e. before any consumer taking `NS.Perf` as a load-time upvalue. `core/PerfSetup.lua:9-17` records
why it sits there rather than higher (a higher position captured `nil` for `NS.VERSION` and stamped
every capture record `v?`).

## 3. Library stack (`library-stack`)

`libs/` holds LibStub, CallbackHandler-1.0, AceAddon/AceEvent/AceDB/AceDBOptions/AceConsole/
AceConfig/AceGUI-3.0 (+ SharedMediaWidgets), LibSharedMedia-3.0, LibCustomGlow-1.0 and `LibKa0s/`.
All vendored and committed; `.pkgmeta` has no `externals:` block.

**`libs/LibKa0s/` is the whole ship folder** — `Core.lua`, `DebugLog.lua`, `Options.lua`,
`OptionsWidgets.lua`, `OptionsScroll.lua`, `Perf.lua`, `PerfPanel.lua`, `Slash.lua`, `LibKa0s.xml`,
`LICENSE`. `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` is **empty** and
`diff -r ../LibKa0s/testkit tests/_kit` is **empty** (evidence §2) — no #45 drift, no #48 partial
vendoring. The addon also carries `tests/test_vendor_sync.lua`, which pins the vendored payload
against the LibKa0s release tag the README names.

`libs/AceTimer-3.0/` was deleted since the previous audit (closing `KCD-29` by the "vendor what you
use" route); the addon schedules through `C_Timer.After`. This leaves the standard's own
library-stack-§1/§3 tension unresolved in the standard, not in the addon — see `02_DEVIATIONS.md`
advisory A-1.

## 4. The five LibKa0s adoptions — what the addon owns

The debug console, options toolkit, slash dispatcher, perf harness and test kit are **library**
code. What KickCD owns is one setup file per module, each a descriptor plus a degradation stub:

| Module | Setup file | LibStub lookup | Stub |
|---|---|---|---|
| `LibKa0s-Core-1.0` | `core/CoreSetup.lua` | `:64` | `:66-107` — working pre-library printer + `table.concat` probe, announces once |
| `LibKa0s-DebugLog-1.0` | `core/DebugLogSetup.lua` | `:45` | `:47-118` — 18 members, no formatter copied |
| `LibKa0s-Options-1.0` | `settings/OptionsSetup.lua` | `:35` | `:169-217` — deliberately **load-completing**, measured at zero load-time members |
| `LibKa0s-Slash-1.0` | `settings/Slash.lua` | `:55` | `:206-255` — `OnSlash`, `PrintHelp`, `LandingRows`, `SetRowAnnotator`, each `Cli*` verb |
| `LibKa0s-Perf-1.0` | `core/PerfSetup.lua` | `:33` | `:35-55` — `on`, `suspended`, `Note`, `OnCommand` |

There is **no** hand-rolled console window, widget maker set, flow engine, dispatcher or value
parser anywhere in `core/`, `modules/` or `settings/`. Every stub answers every member its call
sites reach; the shared cause clause `NS.LIBKA0S_MISSING` is defined once
(`core/CoreSetup.lua:61-62`) and each seam appends only its own consequence. The Options stub's
load-completing shape is documented and **measured** (`settings/OptionsSetup.lua:136-168`,
pinned by `tests/test_options_panel.lua`) — the documented exception, not an inconsistency.

Two places nevertheless carry pre-library host code that the library now provides: the Options
instance is decorated with host copies of `AttachTooltip`, `EnsureScroll`, `AddSpacer`, `LSMValues`
and the `ROW_VSPACER` constant (`settings/Panel.lua:281,341,394,430,443`), and the headless harness
hand-rolls the framework/loader/mock the vendored `tests/_kit/` supplies. Both are recorded as
deviations (`KCD-30`, `KCD-31`, `KCD-32`).

## 5. Architecture (`architecture`)

Every file opens `local addonName, NS = ...`; there is no `_G.KickCD` (`CLAUDE.md:54`).
`core/KickCD.lua` promotes `NS` through `AceAddon:NewAddon`. The printer is published at
`NS.Util.print`, never `NS.Print` (`core/CoreSetup.lua:35-41,122`), so AceConsole's `:Print` mixin
has nothing to clobber — anti-pattern #36 avoided by the first of the two sanctioned routes.

The closed bus carries five `Ka0s_KickCD_*` messages, documented in `docs/message-bus.md` with
sender/payload/consumers. Receivers register on their own AceEvent targets. The bus mock keys by
`(message, target)` and fans out (`tests/wow_mock.lua:1-9`), so the
same-target clobber is catchable. One message, `Ka0s_KickCD_CONFIG_CHANGED`, has **six** senders —
see `KCD-38`.

`NS.Settings.Schema` is the single source of truth and every mutation funnels through
`Helpers.SetAndRefresh` (`settings/Panel_Render.lua:152`), which is the same seam `/kcd set` and the
panel widgets both use.

## 6. SavedVariables (`savedvariables`)

`KickCDDB` is the AceDB tree; `KickCDPerfDB` is the sanctioned second global, outside the tree,
declared in `.luacheckrc` `globals` with a comment. `core/Database.lua` (835 LOC) ships the
migration runner with a `schemaVersion` in globals; the v3→v4 step moved stored colors onto the
library's keyed `{r,g,b,a}` shape so no color codec is needed at any seam.

## 7. Options UI (`options-ui`)

Six subcategories (General, Icons, Cast bar, Text Label, Spells, Profiles) built by
`LibKa0s-Options-1.0` from the descriptor in `settings/OptionsSetup.lua:47-134`.
`NS.Settings.Helpers` **is** the library instance, decorated in place (`:224`) — not a copy-across
table. The panel-open refuses in combat with a gray canonical notice
(`core/KickCD.lua:736-747`), closing `KCD-28`. Panel refresh is in-place through per-widget
`refreshers` with structural rebuilds scoped to the on-screen subcategory (anti-pattern #39 not
triggered). The Defaults button, the always-shown scrollbar and the two-column flow are the
library's.

Host copies of library-owned members and layout constants remain — `KCD-31`, `KCD-32`.

## 8. Standalone windows / preview mode

KickCD ships no standalone data browser. The only Ka0s-edged windows it puts on screen are the
library's: the debug console, its copy window and the perf step panel. `core/DebugLogSetup.lua`
passes **no** `skin`, `applySkin` or `makeCloseButton` override, so the console draws the standard
two-line Ka0s edge from `Core.SKIN`/`Core.ApplySkin` (standalone-windows-§2). `core/PerfSetup.lua:208-217`
decorates the perf panel through the console's **own** `MakeCloseButton` factory rather than a
lookalike (debug-logging-§12).

Preview mode is present: `modules/Castbar.lua:426-431,817-821` shows placeholder cast content while
the UI is unlocked, through the same render path as live data (preview-mode).

## 9. Slash commands (`slash-commands`)

`/kcd` with the `/kickcd` alias, registered through AceConsole; dispatch through
`LibKa0s-Slash-1.0` over the addon's own ordered `NS.COMMANDS` (`core/KickCD.lua:188`), positional
triples. All ten reserved verbs are present and mean the standard thing, including `perf`
(registered by the addon, not the library) and the path-shaped `reset` — with retired page names
answered by a "where it went" message rather than a bare not-found (`settings/Slash.lua:169-190`).
The cyan `|cff00ffff[KCD]|r` tag is a single shared constant. Two host adapters are documented and
justified: `groupKey` (rows carry `panel`, not `page`) and a `parse` override carrying the
`valueGate` hint. No trailing-colon chat lines remain, closing `KCD-25`.

## 10. Localization (`localization`)

`locales/enUS.lua` builds `NS.L` with the mandated `__index`-returns-the-key metatable
(`locales/enUS.lua:14-17`); keys are the English source strings. Only `enUS` ships, so no gating is
needed. Spell/spec matching keys on Blizzard spec IDs rather than translated names (the 1.2.1 fix),
so anti-pattern #37 is not triggered. A sweep for British spellings across `core/`, `modules/`,
`settings/`, `locales/`, `README.md`, `CLAUDE.md` and the canonical `docs/` trio returns **nothing**
— US English throughout (localization-§5).

## 11. Events / frames / taint (`events-frames-taint`)

`core/State.lua:133-159` drives the combat flag from `PLAYER_REGEN_*` rather than polling. Secret
values are handled correctly on the hot paths — `Compat.GetSpellCooldown` discards the secret
timings, the cast bar hands `d:Get*Duration()` straight into `SetValue`/`SetFormattedText`. The
shared printer routes every argument through `NS.SafeToString`, which is the library's
(`core/CoreSetup.lua:109-110`). One private second stringifier survives in
`core/Compat.lua:377-387` — `KCD-33`.

## 12. Compat (`compat`)

`core/Compat.lua` (472 LOC) owns every deprecated / cross-patch call — spell info, specialization,
cooldown, metadata. No `WOW_PROJECT_ID` branch anywhere. `docs/compat-layer.md` and
`docs/midnight-quirks.md` document the 12.0 secret-value rules.

## 13. Debug logging (`debug-logging`)

The console is the library's, wired at `core/DebugLogSetup.lua:120-164` with the addon's frame
prefix, title, mono font, the session-only `NS.State.debug` flag (never in SavedVariables) and the
`[Init]` summary. JetBrains Mono is registered to LSM above the library guard
(`core/DebugLogSetup.lua:37-43`) — the sanctioned styling exception, not a deviation. Debug output
goes to the console, never the chat frame; the gated sink is bound bare as `NS.Debug`
(`core/DebugLogSetup.lua:170`). The scrollbar, line counter and 500-line buffer are the library's.

## 14. Packaging / lint (`packaging`, `lint`)

`.pkgmeta` sets `package-as: KickCD`, has no `externals:`, and ignores `.luacheckrc`, `.gitignore`,
`.gitattributes`, `docs`, `tests`, `_dev`, `*.bak`. `.luacheckrc` follows the template, excludes
`libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/`, carries `debugprofilestop` in
`read_globals`, and declares both SV globals in `globals` with comments. **`luacheck .` → 0
warnings / 0 errors across 32 files.**

## 15. Testing (`testing`)

**`lua tests/run.lua` → 648 passed, 0 failed** across 43 suites. `docs/test-cases.md` is generated
by `--list` and totals 648. `tests/_kit/` is vendored and byte-identical to the LibKa0s
`testkit/`.

However, the kit is **vendored but not consumed**: `tests/run.lua` carries its own registry,
assertion set and `--list` renderer (`:19-83`), `tests/loader.lua` is a private source loader, and
`tests/wow_mock.lua` (1049 LOC) is a full replacement carrying a self-described "VERBATIM port of
`tests/_kit/mock_base.lua`'s builder" (`:556-558`) rather than a thin extender. This is `KCD-30`.
The runner does derive the addon's own file list from the TOC and spells the library files out
explicitly, and pins both — but through its own code rather than the kit's `Loader.tocFiles`.

`tests/perf.lua` — the offline scenario runner — is **absent** (`KCD-34`).

## 16. Performance (`performance`)

Wiring is complete and unusually well-reasoned. `core/PerfSetup.lua` creates one instance from a
descriptor with eight declared buckets and their `within` nesting (`:93-102`), a `suspend`/`resume`
pair that releases the modules' own per-unit dispatch frames and restores from current state
(`:138-161`), `sv = "KickCDPerfDB"`, a `log`/`print`/`showLog` trio and a `decorate` hook built from
the console's own close-button factory. Every bracket uses the mandated gated form and
`tests/test_perfsetup.lua:65` pins that **every declared bucket is reached by a real bracket**. The
`perf` verb is registered by the addon through `NS.COMMANDS`.

What is missing is the evidence and documentation half: no `tests/perf.lua` (`KCD-34`), no
`docs/performance.md` or `docs/perf-runs/README.md` (`KCD-35`), no `docs/complexity.md` (`KCD-39`).

## 17. Documentation (`documentation`)

Root ships `README.md`, `CLAUDE.md`, `LICENSE`. The README follows the canonical section order (H1 →
badges → logo → description → `## What's new in 1.2.1` → Screenshots → Usage → How interrupt
tracking works → FAQ → Troubleshooting → Libraries and credits → Issues → Version History); the
`What's new` section matches the top Version History row. `CLAUDE.md` is a stub carrying the
adherence line, `## Standards compliance (read first)` closing with the canonical sentence
(closing `KCD-26`), a pointer list into `docs/`, and the green-gate line.

`docs/` carries the canonical trio (`ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`), the
generated `test-cases.md`, and fourteen topic-detail docs. `ARCHITECTURE.md` carries every required
heading. The three-place standards reference is satisfied — TOC `X-Standard`, README badge,
`CLAUDE.md` section — with no fourth place (documentation-§6), so `KCD-27` is closed by the
standard's own v2.17.0 deletion.

Two README defects remain: a stale `[tests]` badge (`KCD-36`) and an angle-bracket placeholder
(`KCD-37`).

## 18. Audit / review history, versioning, git

`docs/audits/2026-07-12/`, `docs/audits/2026-07-18/` and `docs/reviews/2026-05-02/`,
`docs/reviews/2026-08-03/` are retained and unedited. Semver in TOC and `NS.VERSION` agree (1.2.1).
Working tree is clean apart from the untracked 2026-08-03 review bundle; branch is `master`
(trunk-based).

---

## Anti-pattern sweep

**Triggered:** #17 (`KCD-38`), #47 (`KCD-30`, `KCD-31`, `KCD-33`), #35 (`KCD-33`, in its detection
half).

**Not triggered — verified, not assumed:** #1, #2, #3, #4, #5, #6, #7, #8, #9, #10, #11, #12, #13,
#14, #15, #16, #18, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #31, #32, #33, #34,
#36, #37, #38, #39, #40, #41, #42, #43, #44, #45, #46, #48, #49. Notable positives: #45/#48 both
cleared by two empty `diff -r` runs; #49 cleared by the deletion commit `c4522b4` and the standing
prohibition in `CLAUDE.md:19-34`; #46 cleared by a spelling sweep that returns nothing.
