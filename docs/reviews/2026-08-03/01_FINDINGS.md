# KickCD — Review Findings (2026-08-03)

**Verdict: minor issues.** The addon is well-architected, fully green on its own gates
(`luacheck .` → 0 warnings / 0 errors across 32 files; `lua tests/run.lua` → **648 passed, 0 failed**),
and its LibKa0s adoption is unusually careful. Nothing here blocks a release. The substantive theme is
**incomplete de-duplication after the LibKa0s-Options extraction**: `settings/Panel.lua` still carries
pre-extraction copies of five members the vendored library now provides, and it installs them *onto the
library instance*, so the library's own widget makers run KickCD's copies. Two smaller correctness
issues (a hand-rolled second secret-stringifier, an unguarded transient settings write) and a set of
hygiene items round it out.

**Standards cross-check: performed.** Resolved against the Ka0s WoW Addon Standard **v2.17.1
(2026-08-03)**. The published raw endpoints timed out from this environment, so the standard was read
from the local clone of `tusharsaxena/WowAddonStandards` at `master` (HEAD `2141229`, clean working
tree, front matter `v2.17.1, 2026-08-03`) — byte-identical to what `curl` would have returned. Every
fix direction below was checked against it; where a rule shaped or vetoed a fix, it is cited as
`filename-§N`.

**Upstream findings: none.** Nothing under `libs/` or `tests/_kit/` produced a defect in this pass.
`libs/LibKa0s/` reads consistently (Core minor 3, DebugLog 7, Options 5 + Widgets 5 + Scroll 2,
Perf 5 + Panel 3, Slash 5) and `tests/test_vendor_sync.lua` already pins the vendored payload against
the tag the README names. The byte-level `diff -r` against the LibKa0s source repo required by
`library-stack-§7` / anti-pattern #45 could **not** be run — no `LibKa0s` checkout exists under
`/mnt/d/Profile/Users/Tushar/Documents/GIT/` — so that check is unverified rather than passed.

**Scope note.** This is a review, not a compliance audit. Pre-existing standard deviations unrelated to
the findings below (e.g. the absence of `docs/performance.md` and `docs/perf-runs/`) are deliberately
not enumerated here — that is `/wow-addon:standards-audit`'s job.

---

## Areas checked and found clean

Stated explicitly so the absence of findings is not read as absence of review:

- **Deprecated APIs.** No call to `GetSpellInfo`, `UnitAura*`, `GetContainerItemInfo`, `IsAddOnLoaded`,
  `LoadAddOn`, `InterfaceOptions_AddCategory` or bare `GetAddOnMetadata` outside `core/Compat.lua`,
  which owns every one of them behind a shim (`compat`). `SetBackdrop` call sites all use
  `"BackdropTemplate"` (`modules/IconGrid_Render.lua:218`, `modules/Castbar.lua:532-533`).
- **Taint / combat lockdown.** `NS:OpenSettings` gates *inside the open function* on
  `State.inCombat or InCombatLockdown()` and refuses with a gray notice rather than deferring
  (`core/KickCD.lua:736-747`) — exactly `options-ui-§2`. No protected-API call sits on a
  combat-reachable path. `core/State.lua:133-159` drives the combat flag off `PLAYER_REGEN_*` rather
  than polling, as `events-frames-taint-§2` requires.
- **Secret values on the hot paths.** `Compat.GetSpellCooldown` discards the secret start/duration and
  returns the plain `isActive`; `modules/Castbar.lua:690-716` passes `d:Get*Duration()` straight into
  `SetValue`/`SetFormattedText` without binding a local; `State.ApplyInterruptibleAlpha` feeds
  `notInterruptible` to `SetAlphaFromBoolean`. The chat printer routes every argument through
  `NS.SafeToString` (`core/CoreSetup.lua:109-122`). One exception — see F-002.
- **Printer collision.** The printer is published at `NS.Util.print`, never `NS.Print`, so
  AceConsole's `:Print` mixin has nothing to clobber (`architecture-§2`, anti-pattern #36).
- **Perf harness.** All eight declared buckets are reached by a real bracket, and every bracket uses
  the mandated gated form `local t0 = Perf.on and debugprofilestop()` (`performance-§2`,
  anti-pattern #43). One bracket leaks an exit — see F-008.
- **Degradation stubs.** `core/DebugLogSetup.lua`, `core/PerfSetup.lua`, `settings/Slash.lua` and
  `settings/OptionsSetup.lua` each answer every member their call sites reach; the Options stub is
  correctly load-completing rather than member-answering (`options-ui-§1`).
- **Dead code.** A cross-file scan of exported `NS.*` / module-table functions found **no** zero-caller
  exports.
- **TOC.** `## Interface: 120007` matches every sibling Ka0s addon in the collection; single Interface
  line; two SavedVariables globals in order (`KickCDDB, KickCDPerfDB`); libraries listed individually
  with `libs\LibKa0s\LibKa0s.xml` after Ace3 and `core\PerfSetup.lua` after `core\KickCD.lua`.
- **Localization.** No game data matched against a localized display string; spec resolution keys on
  the numeric spec ID with a v2→v3 migration behind it (`localization-§4`, anti-pattern #37).

---

## High

### F-001 — `settings/Panel.lua` overwrites five members the LibKa0s-Options instance already provides, on the instance the library's own code calls `[design]`

**Where:** `settings/Panel.lua:281` (`Helpers.LSMValues`), `:315-341` (`attachTooltip` →
`Helpers.AttachTooltip`), `:354-394` (`ensureScroll` → `Helpers.EnsureScroll`), `:432-443`
(`addSpacer` → `Helpers.AddSpacer`), `:426-430` (`Helpers.ROW_VSPACER`).

**Problem:** `NS.Settings.Helpers` *is* the `LibKa0s-Options-1.0` instance
(`settings/OptionsSetup.lua:224`), and the library defines `O.LSMValues`, `O.AttachTooltip`,
`O.EnsureScroll`, `O.AddSpacer` and `O.ROW_VSPACER` on it (`libs/LibKa0s/Options.lua:159,305,485`,
`libs/LibKa0s/OptionsWidgets.lua:152,181`). `settings/Panel.lua` loads immediately after `:New` and
assigns its own pre-extraction copies over four of the five, plus the constant.

**Impact:** three-fold, and only the third is theoretical. (1) The library's five widget makers call
`O.EnsureScroll` / `O.AddSpacer` / `O.AttachTooltip` **through the instance**
(`libs/LibKa0s/OptionsWidgets.lua:193,198,210,218,241,248,255,269,276,325,333,364,375,388,395,456,498,510,551,564,591,604,617`),
so in KickCD every one of them runs the host's copy instead of the library's — the drift the
extraction exists to end, reinstated silently. (2) A live contract already differs:
`O.AddSpacer` returns the created `SimpleGroup`; the host's `addSpacer` (`Panel.lua:432-438`) returns
nothing, so the first library minor that uses that return breaks here and nowhere else. (3)
`Helpers.LSMValues` diverges in shape and sentinel — host returns a **table** built from `LSM:List`
with a `"Default"` fallback key, library returns a **deferred closure** built from `LSM:HashTable`
with `lib.STRINGS.LSM_NONE`. (KickCD's page files wrap the call in `function() ... end`, so deferral
is preserved and no user-visible bug exists *today*.)

**Fix direction:** delete the host copies and let the instance's own members stand
(`options-ui-§1`: the host member is the library instance decorated only with *pieces that did not
generalize*; anti-pattern #47). If the fallback-key or `List`-vs-`HashTable` behavior is genuinely
wanted, push it upstream as an additive descriptor field — **not** an edit under `libs/`, and **not**
a local re-implementation.

### F-002 — `Compat.DebugInterrupt` hand-rolls a second secret-safe stringifier with a different detection mechanism `[taint]`

**Where:** `core/Compat.lua:377-387` (`safeRender`), used at `:396-397`, `:402-403`.

**Problem:** the addon already publishes the standard's mandated stringifier
(`NS.SafeToString = lib.SafeToString`, `core/CoreSetup.lua:110`), whose detection is a `pcall` probe
of **`table.concat`**. `safeRender` is a private second copy whose detection is
`_G.issecretvalue(value)`, and whose fallthrough for a string is `("%q"):format(value)`.

**Impact:** `events-frames-taint-§8` requires detection to probe `table.concat` precisely because any
other probe can under-report. If `issecretvalue` is absent, renamed, or does not cover a given value,
`safeRender` returns `false` and line 382 hands a secret string to `string.format` — which raises,
inside the one command (`/kcd debug interrupt`) whose entire purpose is diagnosing secret values in
combat. The same one-off pattern recurs at `modules/Castbar_Debug.lua:45`.

**Fix direction:** route `safeRender`'s callers through `NS.SafeToString`, keeping only the
`issecretvalue`-derived `isSecret=` **column** (which is diagnostic reporting, not stringification).
`events-frames-taint-§8` and anti-pattern #47 forbid the addon carrying its own stringifier; the
sanctioned second copy is the `core/CoreSetup.lua` library-absent branch alone.

---

## Medium

### F-003 — Three settings files hard-resolve AceGUI at file load, so a missing AceGUI takes the whole settings layer down `[design]`

**Where:** `settings/Panel.lua:30`, `settings/Panel_Widgets.lua:30`, `settings/Panel_Render.lua:13` —
all `LibStub("AceGUI-3.0")` with no silent flag.

**Problem:** `options-ui-§1` states plainly that *"AceGUI-3.0 is **survivable, not a dependency**"* —
the library resolves it silently, prints one honest line and returns. These three call sites raise at
load instead. A raise in `Panel.lua` also loses `Helpers.Get` / `Set` / `SetAndRefresh` / `FindSchema` /
`ValidateSchema` / `LSMValues` / `AnchorValues`, which the page files then evaluate at load — the exact
silent half-load that `settings/OptionsSetup.lua`'s load-completing stub exists to prevent, arriving
through a different door. Secondarily, these are three redundant LibStub resolutions when the
descriptor's `onAceGUI` seam (`settings/OptionsSetup.lua:113`) and the instance's `O.AceGUI` already
hold one.

**Impact:** only reachable on a corrupted/partial install (AceGUI is vendored and TOC-listed), but the
failure mode is a settings layer that half-loads with no error naming the cause.

**Fix direction:** resolve silently and read the instance's `O.AceGUI` where possible; degrade the
three files' render paths rather than raising.

### F-004 — Host copies of library layout constants `[design]`

**Where:** `core/Constants.lua:66` (`Const.PANEL_PADDING_X = 16`), `settings/Panel.lua:426`
(`local ROW_VSPACER = 8`) and `:430` (`Helpers.ROW_VSPACER = ROW_VSPACER`).

**Problem:** both restate values the library owns (`libs/LibKa0s/Options.lua:46` `PADDING_X = 16`,
`:56` `ROW_VSPACER = 8`). Line 430 additionally **clobbers** `O.ROW_VSPACER`, which the library set at
`Options.lua:159`, on the shared instance. `settings/Panel.lua:300-306`'s own comment asserts the
opposite — *"Where host code needs one, it reads it off the instance (`Helpers.ROW_VSPACER`, …) rather
than restating it"* — twenty lines above the restatement.

**Impact:** the values agree today, so nothing is visibly wrong; the point of the rule is that they
cannot be *made* to disagree. `options-ui-§8` is a MUST NOT here, and `tests/test_options_panel.lua:355`
already asserts the *stub* carries no such copy while `Panel.lua` carries two.

**Fix direction:** delete both host copies; read `Helpers.ROW_VSPACER` and add a `PADDING_X` read off
the instance for the landing-page body.

### F-005 — `NS.Slash.GateHint` writes the profile directly and restores without a `pcall` `[bug]` `[data]`

**Where:** `settings/Slash.lua:118-129`.

**Problem:** the probe swaps a sibling setting's stored value (`parent[key] = candidate`), calls
`allowedKeys(row)` — which invokes an arbitrary schema row's `values()` function — then restores
(`parent[key] = gateVal`). The restore is not protected. It is also a raw `db.profile` write that
bypasses the addon's declared single write seam, `Helpers.SetAndRefresh`.

**Impact:** if any row's `values()` raises (a media list from a third-party addon, a nil profile
mid-switch), the loop unwinds with the gating setting left at a probe candidate. That value is now in
`KickCDDB` and persists across `/reload` — the user's `castbar.orientation` silently flipped because
they typed an invalid `/kcd set castbar.growDirection`.

**Fix direction:** wrap the swap/probe/restore in a `pcall` so the restore always runs. The direct
write itself stays justified (it must not fire `onChange` or the bus), but the invariant that makes it
safe must be enforced, not asserted — the standard's single-write-seam rule (`options-ui-§1`,
`architecture-§5`) tolerates a transient probe only while it is genuinely transient.

### F-006 — `.pkgmeta` ships the development scratch directories to end users `[packaging]`

**Where:** `.pkgmeta` `ignore:` list; `.superpowers/sdd/` (68 files: 25 review diffs, task briefs,
reports, specs), `.claude/settings.local.json`.

**Problem:** the ignore list covers `docs`, `tests`, `_dev`, `.luacheckrc`, `.gitignore`,
`.gitattributes`, `*.bak` — but not `.superpowers/` or `.claude/`.

**Impact:** the packaged CurseForge zip carries the addon's internal planning history and raw commit
diffs. Harmless functionally; it is dead weight in every user's `AddOns` folder and leaks in-progress
design notes. (`packaging`.)

**Fix direction:** add `.superpowers` and `.claude` to the `ignore:` list.

### F-007 — The Options stub's justification comments describe code that does not exist `[naming]`

**Where:** `settings/OptionsSetup.lua:144-145` and `:180-182`.

**Problem:** two load-bearing comments are factually wrong about the files they cite.
(a) Lines 144-145 state that *"settings/Icons.lua and settings/Castbar.lua evaluate `H.LSMValues("border")`
and `H.AnchorValues()` inside schema-row literals, at FILE LOAD"*. Every `LSMValues` call site is in
fact wrapped in a closure (`settings/Icons.lua:196,220`, `settings/Label.lua:147`,
`settings/Castbar.lua:280,401,438,463,500` — all `values = function() return H.LSMValues(...) end`);
only `AnchorValues` is evaluated at load (`settings/Icons.lua:39`, `settings/Castbar.lua:52`).
(b) Lines 180-182 say the stub *"answers until then"* for `AnchorValues`/`AnchorOrder` — the stub
publishes neither; `settings/Panel.lua:244,266` does, unconditionally, and loads before the page files.

**Impact:** the comments are the argument for the stub's exact member set. A future maintainer
reasoning from them will publish the wrong members, or delete the right ones. The measurement gate
(`tests/test_options_panel.lua`) is correct; only the prose is not.

**Fix direction:** correct both comments to name `AnchorValues`/`AnchorOrder` (the real load-time
evaluators) and `settings/Panel.lua` (their real provider).

---

## Low

### F-008 — The `castTick` perf bracket is not closed on its early exit `[perf]`

**Where:** `modules/Castbar.lua:690-697` — `local __t0 = Perf.on and debugprofilestop()` at 690;
`if not d then frame:SetScript("OnUpdate", nil); return end` at 694-697 returns without
`Perf.Note("castTick", ...)`.

**Impact:** the sample is taken and discarded, so `castTick`'s `calls` count is short by one per cast
teardown. `performance-§3` treats an under-counted bucket as a report that misleads. The same module's
sibling (`modules/Cooldowns.lua:93-198`) instruments all four of `PollSpell`'s exits precisely because
of this, and documents why — so this is an inconsistency within the addon's own established idiom.

**Fix direction:** close the bracket on the early-return path, mirroring `PollSpell`.

### F-009 — `/kcd debug castbar` prints nothing for a secret `notInterruptible` when `C_CurveUtil` is absent `[ux]`

**Where:** `modules/Castbar_Debug.lua:51-58`.

**Impact:** the `else` branch's only statement is guarded by
`if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then`. On a client without that
namespace the dump silently omits the line the command exists to produce, and the user sees a gap
rather than a diagnosis.

**Fix direction:** print an unconditional line for the non-boolean/non-nil case; mention the curve
evaluator only when it is present.

### F-010 — Eight orphaned locale keys `[locale]`

**Where:** `locales/enUS.lua`. Keys with zero call sites anywhere in `core/`, `modules/`, `settings/`:
`Show Target label`, `Target label text`, `Focus label text`, `Debug`,
`Print every internal message to chat. Useful for diagnosing module wiring.`, `Allowed values: %s`,
`Setting not found: %s`, `Invalid value for %s`, `Usage: /kcd get <path>`,
`Usage: /kcd set <path> <value>`.

**Impact:** the first five are residue of the Text Label page rewrite and the debug-console checkbox
moving into `LibKa0s-DebugLog-1.0`; the last five were superseded by `LibKa0s-Slash-1.0`'s own
`STRINGS`. A translator copying `enUS.lua` (which is exactly the workflow the file's header describes)
spends effort on strings that render nowhere. No runtime effect — the metatable fallback means an
unused key is inert.

**Fix direction:** delete the ten keys. Note that under `localization-§2` a key *is* its English
string, so deletion is safe only because no call site references them — verified by grep.

### F-011 — `docs/message-bus.md`'s stated rule contradicts its own sender table `[doc]`

**Where:** `docs/message-bus.md:61` vs `:10`.

**Impact:** line 61 requires a second emitter to *"live in the same file as the first, so the message
still has one owning module"*. `Ka0s_KickCD_CONFIG_CHANGED` is emitted from five files —
`core/KickCD.lua:128,457`, `modules/IconGrid.lua:522`, `modules/Castbar.lua:333`,
`settings/Spells.lua`, `settings/Panel.lua` — and line 10's table lists all of them as intended.
`core/PerfSetup.lua:152-154` reasons about *"a sixth sender"*, so the count is live knowledge. The
divergence is between the doc's rule and the doc's table, not (per `architecture-§4`'s allowance for a
recorded justification) necessarily between the doc and the code. A reader cannot tell which half is
authoritative.

**Fix direction:** amend line 61 to state the actual, recorded policy for this message (multi-module by
design, one section value per emitter), rather than a rule the table immediately breaks.
