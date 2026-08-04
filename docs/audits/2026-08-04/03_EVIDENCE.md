# KickCD — Evidence (2026-08-04)

Every claim in `01_CURRENT_STATE.md` and `02_DEVIATIONS.md` is sourced here. Mechanical checks were
**run**, not reasoned about; the commands and their real output are reproduced verbatim.

---

## 1. Standard provenance — fetched, then byte-verified

```
$ cd /tmp/.../scratchpad/std
$ RAW=https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master
$ curl -fsSL --max-time 15 -o AUDIT.md    "$RAW/AUDIT.md"    && echo AUDIT_OK
AUDIT_OK
$ curl -fsSL --max-time 15 -o STANDARDS.md "$RAW/standards/STANDARDS.md" && echo STD_OK
STD_OK
```

The index's Sections list (`STANDARDS.md:55-78`) names 24 section files; each was fetched from
`$RAW/standards/standards/<name>.md` with `--max-time 12`. No `FAIL` line was emitted and the
directory holds 24 files / 288K.

```
$ diff -r sec /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/standards && echo "SECTIONS_IDENTICAL"
SECTIONS_IDENTICAL
$ diff std/AUDIT.md      /mnt/.../WowAddonStandards/AUDIT.md               && echo AUDIT_IDENTICAL
AUDIT_IDENTICAL
$ diff std/STANDARDS.md  /mnt/.../WowAddonStandards/standards/STANDARDS.md && echo INDEX_IDENTICAL
INDEX_IDENTICAL
```

```
$ cd /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards && git status --porcelain && git log -1 --format='%H %s'
2141229 96c6c2db2e1c4a88a1f5d152dce2de928 v2.17.1 — finish the v2.17.0 rollout: no fourth slot, no drop-in imperative
```
(clean working tree; no porcelain lines)

Front matter read: `STANDARDS.md:1` — `# Ka0s WoW Addon Standard (v2.17.1, 2026-08-03)`.

**Conclusion:** the audit measured against the live standard; the local checkout only corroborated
it. No section was unassessed.

## 2. Vendored Ka0s-owned library sync (`diff -r`) — anti-patterns #45 / #48

The sibling source repo is present:

```
$ ls -d /mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s
/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s
$ ls /mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s
CHANGELOG.md  LICENSE  LibKa0s  README.md  docs  testkit  tests
$ cd /mnt/.../LibKa0s && git log -1 --format='%H %s'
ac5d0f576eddeb375b982515e0e49e9faba5d881 docs: act on the 2026-08-02 adoption report
```
(clean working tree)

Both mandated diffs, over the **whole** folders:

```
$ diff -r /mnt/.../LibKa0s/LibKa0s /mnt/.../KickCD/libs/LibKa0s
exit=0            # no output

$ diff -r /mnt/.../LibKa0s/testkit /mnt/.../KickCD/tests/_kit
exit=0            # no output
```

**Both empty.** The ship payload is whole and byte-identical (all eight module files plus
`LibKa0s.xml` and `LICENSE`), and the vendored harness matches `testkit/` exactly. **Anti-pattern
#45 is not triggered and #48 is not triggered.** The harness lives under `tests/`, never `libs/`
(testing-§1).

This is the check the 2026-08-03 review recorded as **unverified** because no LibKa0s checkout was
found (`docs/reviews/2026-08-03/01_FINDINGS.md:21-25`). It is now run and passing.

## 3. Lint

```
$ luacheck .
...
Checking settings/Spells.lua                      OK

Total: 0 warnings / 0 errors in 32 files
```

Config: `.luacheckrc` — `std = "lua51"`, `exclude_files = { "libs/", "docs/audits/", "_dev/",
"tests/", "docs/reviews/" }`, `debugprofilestop` in `read_globals` (lint, performance-§2), and both
SV globals in `globals` with justifying comments (`KickCDDB`, `KickCDPerfDB`).

## 4. Headless suite

```
$ lua tests/run.lua
...
-------------------
648 passed, 0 failed
```

43 suites. The generated inventory agrees:

```
$ lua tests/run.lua --list | tail -5
| test_slash.lua | 27 |
| test_perfsetup.lua | 25 |
| test_list_mode.lua | 5 |
| test_vendor_sync.lua | 2 |
| **Total** | **648** |
```

`docs/test-cases.md:3` — `_Generated — do not hand-edit. Regenerate with `lua tests/run.lua --list >
docs/test-cases.md`._` · `docs/test-cases.md:829` — `| **Total** | **648** |`.

---

# Evidence per deviation

## KCD-30 — the vendored kit is not consumed (`testing-§1`, `testing-§9`, AP-47)

The kit is present and correct (§2 above), and nothing loads it:

```
$ grep -rn '_kit' tests/*.lua | grep -v '^tests/_kit'
tests/run.lua:75:--- semantics as tests/_kit/framework.lua's, so adopting the kit replaces this
tests/test_vendor_sync.lua:4:  -- ... that `libs/LibKa0s/` and `tests/_kit/` in this repo are exactly
tests/test_vendor_sync.lua:144: test("tests/_kit is the test kit that shipped with that release", ...)
tests/wow_mock.lua:556:    -- Deliberately a VERBATIM port of tests/_kit/mock_base.lua's builder, so

$ grep -rn 'Kit\.' tests/*.lua
tests/test_vendor_sync.lua:14: -- ... LibKa0s gave `testkit/` a revision (`Kit.VERSION`) ...

$ grep -rn 'mock_base' tests/*.lua
tests/wow_mock.lua:556: -- Deliberately a VERBATIM port of tests/_kit/mock_base.lua's builder, so
```

Every hit is a comment or the sync suite. There is no `dofile` of `tests/_kit/framework.lua`,
`tests/_kit/loader.lua` or `tests/_kit/mock_base.lua`, and no `Kit.expose` / `Kit.run`.

What runs instead:

- `tests/run.lua:14-15` — `local mockmod = dofile(root .. "/tests/wow_mock.lua")` /
  `local loader = dofile(root .. "/tests/loader.lua")`.
- `tests/run.lua:19-33` — the private micro-framework header, `listMode`, `registry`,
  `currentSuite`.
- `tests/run.lua:40-56` — a hand-rolled `test()` with its own list-mode branch.
- `tests/run.lua:58-83` — the private assertion set; `:73-76` states outright that it duplicates the
  kit's: *"Same name, signature and semantics as `tests/_kit/framework.lua`'s, so adopting the kit
  replaces this with an identical function rather than changing any call site."*
- `tests/loader.lua:1-108` — a private sandboxed source loader with its own `readTOCOrder`.
- `tests/wow_mock.lua` — 1049 LOC, a replacement rather than a thin extender; `:556-558` —
  *"Deliberately a VERBATIM port of `tests/_kit/mock_base.lua`'s builder, so adopting the shared kit
  deletes this block rather than reconciling two divergent widget fakes."*

```
$ wc -l tests/run.lua tests/loader.lua tests/wow_mock.lua tests/_kit/*.lua
  253 tests/run.lua
  108 tests/loader.lua
 1049 tests/wow_mock.lua
  206 tests/_kit/framework.lua
   90 tests/_kit/loader.lua
  537 tests/_kit/mock_base.lua
```

Rule text: `testing.md` §1 — *"The harness is a Ka0s-owned shared kit, not per-addon code. Addons
**MUST NOT** hand-roll their own registry, assertion set, source loader, or base mock (anti-patterns
#47)"*; *"`tests/run.lua` **MUST** keep only what is genuinely this addon's. It `dofile`s the kit's
`framework.lua` and `loader.lua` … and hands the ordered suite list to `Kit.run`"*;
*"`tests/wow_mock.lua` **MUST** be a **thin extender** over `mock_base.lua`, not a replacement"*.
§9 — *"**MUST** derive the runner's list of the addon's **own** files from the TOC, with the kit's
`Loader.tocFiles("<Addon>.toc")`"*.

Mitigating and worth recording: the addon's own loader **does** derive from the TOC and **does**
spell the library files out explicitly with a case pinning the list against the XML
(`tests/loader.lua:15-25`), so testing-§9's *intent* is met by private code. The deviation is the
duplication, not a missing behavior.

## KCD-31 — host copies of library Options members (`options-ui-§1`, AP-47)

Host side:

```
$ grep -n 'Helpers.LSMValues\|Helpers.AttachTooltip\|Helpers.EnsureScroll\|Helpers.AddSpacer' settings/Panel.lua
281:function Helpers.LSMValues(mediaType)
341:Helpers.AttachTooltip = attachTooltip
394:Helpers.EnsureScroll = ensureScroll
443:Helpers.AddSpacer = addSpacer
```

Implementations: `settings/Panel.lua:281-291` (`LSMValues`), `:315-341` (`attachTooltip`),
`:354-394` (`ensureScroll`), `:432-443` (`addSpacer`).

Library side — the same four members, published on the instance:

```
$ grep -n 'function O.AttachTooltip\|function O.AddSpacer\|function O.EnsureScroll\|function O.LSMValues' libs/LibKa0s/*.lua
libs/LibKa0s/Options.lua:305:  function O.EnsureScroll(ctx)
libs/LibKa0s/Options.lua:485:  function O.LSMValues(mediaType)
libs/LibKa0s/OptionsWidgets.lua:152:  function O.AttachTooltip(widget, label, tooltip)
libs/LibKa0s/OptionsWidgets.lua:181:  function O.AddSpacer(scroll, height)
```

The library's widget makers reach them **through the instance**, so the host copies are what
actually run inside library call paths — `libs/LibKa0s/OptionsWidgets.lua:193, 198, 210, 218, 241,
248, 255, 269, 276, 325, 333, 364, 375, 388, 395, 456, 498, 510` and
`libs/LibKa0s/Options.lua:291-292`.

The instance is the library's, decorated in place — `settings/OptionsSetup.lua:224`
(`NS.Settings.Helpers = lib:New(descriptor)`), as `settings/OptionsSetup.lua:12-17` intends. That is
correct; the decoration content is not.

Contract difference proving "they agree today" is not a defense: `settings/Panel.lua:281-291`
returns a **table**; `libs/LibKa0s/Options.lua:485` returns a **closure**. Call sites currently wrap
the host shape — `settings/Icons.lua:196,220`; `settings/Label.lua:147`;
`settings/Castbar.lua:280,401,438,463,500`.

Rule text: `options-ui.md` §1 — *"The host member **MUST *be*** the library instance, decorated in
place with the host's own **non-generalizable** pieces"*; AP-47 — *"forking the vendored copy … a
private options toolkit"*.

## KCD-32 — host copies of library layout constants (`options-ui-§8`)

```
$ grep -n 'PANEL_PADDING_X' core/Constants.lua
66:Const.PANEL_PADDING_X    = 16

$ grep -n 'PADDING_X\|ROW_VSPACER' settings/Panel.lua
300:-- Only PADDING_X survives, and only because this addon's own landing-page body
305:-- needs one, it reads it off the instance (Helpers.ROW_VSPACER,
306:-- Helpers.SECTION_HEADING_H, Helpers.BUTTON_PAIR_REL) rather than restating it.
307:local PADDING_X = NS.Const.PANEL_PADDING_X
363:    scroll.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      PADDING_X - 4, -8)
364:    scroll.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -(PADDING_X + 12), 8)
426:local ROW_VSPACER = 8
430:Helpers.ROW_VSPACER = ROW_VSPACER
```

Library side:

```
libs/LibKa0s/Options.lua:46    PADDING_X     = 16,
libs/LibKa0s/Options.lua:56    ROW_VSPACER           = 8,
libs/LibKa0s/Options.lua:159   O.ROW_VSPACER       = L.ROW_VSPACER
```

So `settings/Panel.lua:430` overwrites the library's published constant with a host restatement of
the same number. `settings/Panel_Render.lua:20` (`local ROW_VSPACER = Helpers.ROW_VSPACER`) reads
the instance correctly — and therefore reads the host's copy.

The library publishes `ROW_VSPACER`, `SECTION_HEADING_H` and `BUTTON_PAIR_REL` on the instance
(`Options.lua:159-161`) but **not** `PADDING_X`, which is why the `PADDING_X` half needs an additive
upstream publication rather than a local edit.

Rule text: `options-ui.md` §8 — *"Hosts **MUST NOT** copy these values into their own constants
file… Where a host needs one for its own bespoke widget… read it off the instance
(`Helpers.ROW_VSPACER`, `Helpers.SECTION_HEADING_H`, `Helpers.BUTTON_PAIR_REL`) rather than
restating the number."*

## KCD-33 — a second secret stringifier (`events-frames-taint-§8`, AP-47/#35)

```
$ grep -n 'safeRender\|issecretvalue' core/Compat.lua
366:--- `safeRender` first because in combat *any* string field
377:    local function safeRender(value)
378:        if _G.issecretvalue and _G.issecretvalue(value) then
397:        unit, safeRender(rawName), tostring(canAttack)))
401:        local secret = _G.issecretvalue and _G.issecretvalue(value) or false
403:            label, t, tostring(secret), safeRender(value)))
```

`core/Compat.lua:377-387` is the private stringifier; `:372` is the global-print fallback
(`local out = (NS.Util and NS.Util.print) or _G.print`).

The sanctioned copies already exist and are correct:

- `core/CoreSetup.lua:109-110` — `NS.IsConcatSafe = lib.IsConcatSafe` / `NS.SafeToString =
  lib.SafeToString`, i.e. the library's own function values.
- `core/CoreSetup.lua:81-92` — the library-absent branch, probing with
  `table.concat` (`local function probeConcat(v) return table.concat({ v }) end`), which is the
  **one** sanctioned second copy.

Rule text: `events-frames-taint.md` §8 — *"The stringifier and the printer are `LibKa0s-Core-1.0`'s,
not the addon's. An addon **MUST NOT** hand-roll either (anti-patterns #47)"*; *"Detection **MUST**
probe `table.concat`, not `..`"*; *"call sites **MUST NOT**: call the global `print()` directly"*;
*"A degraded build (library absent) falls back to the addon's own guarded implementations in the
same file — that branch is the **only** sanctioned place a second copy may exist."*

## KCD-34 — no offline scenario runner (`performance-§9`)

```
$ ls tests/perf.lua
ls: cannot access 'tests/perf.lua': No such file or directory
```

The claim the missing scenario is meant to substantiate is currently made in prose:
`core/PerfSetup.lua:19-31` identifies `iconApply` as the addon's one measurable hot path (~100
calls/s mid-fight) and explains why. The gated bracket idiom is correct everywhere and
`tests/test_perfsetup.lua:65` pins that every declared bucket is reached — but performance-§2's
*"the claim 'instrumentation is free when off' is not a comment; it is a measured, committed
number"* has no committed number.

Rule text: `performance.md` §9 — *"**MUST** live at `tests/perf.lua`, run as `lua tests/perf.lua`,
and stay outside the green gate"*; *"**MUST** ship a **zero-overhead scenario**"*.

## KCD-35 — two required docs absent (`documentation-§3`, `performance-§8`)

```
$ ls docs
ARCHITECTURE.md  audits  castbar.md  compat-layer.md  conventions.md  data-flow.md
icon-grid.md  message-bus.md  midnight-quirks.md  module-map.md  pending  reviews
saved-variables.md  scope.md  settings-panel.md  slash-dispatch.md  smoke-tests.md
superpowers  test-cases.md  testing.md
```

No `performance.md`, no `perf-runs/`. The canonical trio and `test-cases.md` are all present.

Rule text: `documentation.md` §3 — *"**Three** topic-detail docs are **required**, not optional:
`docs/test-cases.md` … **`docs/performance.md`** … **`docs/perf-runs/README.md`**"*.
`performance.md` §8 — *"**MUST** commit captures worth keeping under `docs/perf-runs/`… with a
`README.md` in that directory"*.

Independently corroborated by the prior review's deliberate hand-off:
`docs/reviews/2026-08-03/05_FINAL_SUMMARY.md:204-207` — *"`docs/performance.md` and
`docs/perf-runs/README.md` are required by `documentation-§3` and are absent. Deferred
deliberately: enumerating pre-existing standard deviations is `/wow-addon:standards-audit`'s job."*

## KCD-36 — stale `[tests]` badge (`documentation-§1` #2, `testing-§5`)

```
README.md:7        ![Tests](https://img.shields.io/badge/Tests-646%2F646_passing-green)
docs/test-cases.md:829   | **Total** | **648** |
$ lua tests/run.lua  ->  648 passed, 0 failed
```

Rule text: `testing.md` §5 — *"**MUST** keep both in lockstep with the suite: whenever a case is
added, removed, or renamed, or the pass count moves … regenerate `docs/test-cases.md` and update the
README badge **as part of the same change**, never as a deferred follow-up."* `documentation.md`
§1 #2 keep-in-sync rule says the same for badge #5.

The addon already knows the rule — `CLAUDE.md:56` states it verbatim — which makes this a lapse in
execution rather than a missing convention.

## KCD-37 — angle-bracket placeholder in the README (`documentation-§1`)

```
$ grep -n '<[a-zA-Z_][a-zA-Z0-9_ ]*>' README.md
191:| I want a clean slate. | ... One setting: `/kcd reset <setting>`. ...
210:| 1.2.1 | 2026-07-26 | ...<br>The Spells tab's spec dropdown ...
```

`:191` is the deviation. `:210` (and `:211`) are `<br>` in a table cell — deliberate HTML that
documentation-§1 protects by name from exactly this sweep.

The correct form is already used three lines apart in the same file: `README.md:73`
(`/kcd get setting`), `:74` (`/kcd set setting value`), `:75` (`/kcd reset setting`).

Rule text: `documentation.md` §1 — *"**Angle-bracket placeholders MUST NOT appear in shipped README
content.** CurseForge strips `<setting>`, `<name>`, `<value>` and the like as unknown HTML tags —
**including inside backticks**"*.

## KCD-38 — six senders for one bus message (`architecture-§4`, AP-17)

```
$ grep -rn 'SendMessage' core/ modules/ settings/ | grep -i config_changed
core/KickCD.lua:128:        self:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })
core/KickCD.lua:457:        NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "spells" })
modules/IconGrid.lua:522:    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "general" })
modules/Castbar.lua:333:    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "castbar" })
settings/Spells.lua:325:    NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = "spells" })
settings/Panel.lua:77:       NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", { section = section })
```

Six call sites across five files. The in-repo record acknowledges it:
`docs/message-bus.md:61` — *"Default to a single emitter per message; a second one needs a recorded
justification and **must live in the same file as the first**, so the message still has one owning
module. Today only `Ka0s_KickCD_CONFIG_CHANGED` (multi-module by design) and
`Ka0s_KickCD_PROFILE_CHANGED` (two call sites, both in `core/Database.lua`) have more than one."* —
so even the addon's own relaxed rule ("same file as the first") is not met by the five-file spread.

Rule text: `architecture.md` §4 — *"**MUST NOT** have two senders for the same message"*; and the
documentation MUST names *"sender (one)"*. AP-17.

## KCD-39 — no complexity report (`performance-§10`)

`docs/` listing above shows no `complexity.md`. Rule text: `performance.md` §10 — *"**SHOULD** run
`lizard` over the addon's own source, excluding `libs/`, and commit the report as
`docs/complexity.md`"*, with *"**MUST NOT** gate commits on it"*.

---

# Compliance evidence (claims made in `01_CURRENT_STATE.md`)

Recorded because the playbook requires compliance claims to be sourced too, and because "we looked
and it was fine" is worth as much as a finding on the next run.

| Claim | Source |
|---|---|
| No hand-rolled debug console, widget makers, dispatcher or parser | `core/DebugLogSetup.lua:45,120`; `settings/OptionsSetup.lua:35,224`; `settings/Slash.lua:55,286` — all `LibStub(major, true)` + `:New(descriptor)`; no `modules/DebugLog.lua`, no host widget-maker file, no host dispatcher exists in the tree |
| Core stub covers its call sites | `core/CoreSetup.lua:66-107` — `IsConcatSafe`, `SafeToString`, `Util.print`, announcing once at `:97-101` |
| DebugLog stub covers its call sites | `core/DebugLogSetup.lua:74-116` — 18 members incl. `Add`, `Debug`, `Clear`, `Show`, `Hide`, `Toggle`, `IsShown`, `IsEnabled`, `RefreshHeader`, `ShowCopy`, `UpdateScrollBar`, `UpdateStatus`, `BufferSize`, `LastLine`, `FindLine`, `MakeCloseButton`, `FormatPlain`/`FormatColored`, `SetEnabled`, `ConsoleCheckbox`; `:58-62` records that no formatter is copied, and `:19-21` notes a suite greps for the hex codes to prove it |
| Perf stub covers its call sites | `core/PerfSetup.lua:42-53` — `on`, `suspended`, `Note`, `OnCommand`; `:36-41` names each and why |
| Slash stub covers its call sites | `settings/Slash.lua:216-254` — `SetRowAnnotator`, `CliList/Get/Set/Reset/ResetAll`, `CliVersion`, `LandingRows`, `HelpRows`, `PrintHelp`, `OnSlash`; `:202-205` records that no formatter or parser is copied |
| Options stub is load-completing **by measurement**, not by assertion — the documented exception | `settings/OptionsSetup.lua:136-168`; `:155-157` records the measured result (zero load-time members needed here, unlike the reference consumer) and `:159-163` names the suite that gates it (`tests/test_options_panel.lua`, loading the addon with the library absent and pinning `#NS.Settings.Schema`) |
| Degraded path exercised by a **real load**, not a hand-stub (testing-§8) | `tests/run.lua:96-99` — `{ libFiles = {} }` loads the addon with LibKa0s absent |
| Every declared perf bucket is reached | `tests/test_perfsetup.lua:63-101`, driving each bucket's genuine entry point; `core/PerfSetup.lua:104-118` records the capture that *changed* the bucket set (`pollSpell` added after 73.9 ms went unattributed; `visibility`'s `within` dropped after six calls against zero for the declared parent) |
| Perf verb registered by the addon, not the library | `core/KickCD.lua:188` (`NS.COMMANDS`), routed at `settings/Slash.lua:289` |
| Suspend is enforced at the source, not by hiding frames | `core/PerfSetup.lua:131-146` — `IconGrid.shouldBeVisible` / `Castbar.isVisible` check `NS.Perf.suspended` as step 0; resume rebuilds from current state at `:155-161` |
| Printer cannot be clobbered by AceConsole (AP-36) | `core/CoreSetup.lua:35-41` (the reasoning) and `:122` (`Util.print = printer.Print`) — published at `NS.Util.print`, never `NS.Print` |
| Combat refusal for the panel is gray + canonical (closes `KCD-28`) | `core/KickCD.lua:736-747` |
| No trailing-colon chat lines (closes `KCD-25`) | Sweep of `core/`, `modules/`, `settings/` for line-terminal `:` in printed strings returns nothing |
| `CLAUDE.md` standards section is canonical (closes `KCD-26`) | `CLAUDE.md:7-17`, heading `## Standards compliance (read first)`, closing *"When in doubt, treat conformance as a hard requirement and ask."* |
| Three-place standards reference, no fourth (closes `KCD-27` via v2.17.0) | `KickCD.toc:12`; `README.md:6`; `CLAUDE.md:7` |
| `docs/agent-context.md` absent and prohibited (AP-49) | Not in the tree; deleted in commit `c4522b4`; `CLAUDE.md:19-34` forbids recreation and marks older bundles that name it as frozen history |
| US English throughout (localization-§5, AP-46) | `grep -rniE '(colour\|grey\|behaviour\|centre\|cancelled\|initialise\|organis\|analyse\|catalogue\|defence\|licence\|favour\|labelled\|customis\|normalis)'` over `core/ modules/ settings/ locales/ README.md CLAUDE.md docs/{ARCHITECTURE,testing,smoke-tests}.md` → no matches |
| Locale fallback metatable (AP-2) | `locales/enUS.lua:14-17` |
| Game data matched on IDs, not localized strings (AP-37) | The 1.2.1 fix keys spec lists on Blizzard spec IDs — `README.md:22`, `docs/`; no English-literal name comparisons in `modules/` |
| Preview mode (preview-mode) | `modules/Castbar.lua:426-431` (show while unlocked), `:817-821` (kept visible while unlocked), through the live render path |
| Console draws the standard Ka0s edge; no host override (standalone-windows-§2) | `core/DebugLogSetup.lua:120-164` — descriptor passes `name`, `title`, `font`, `slash`, `isEnabled`, `setEnabled`, `print`, `safeToString`, `initSummary`, `onVisibilityChanged`; **no** `skin`, `applySkin` or `makeCloseButton` |
| Perf panel close button from the console's own factory (debug-logging-§12) | `core/PerfSetup.lua:208-217` — `NS.DebugLog.MakeCloseButton(frame, api.Hide)`, not a lookalike |
| Single write seam shared by panel and CLI | `settings/Panel_Render.lua:152` (`Helpers.SetAndRefresh`), referenced by `settings/OptionsSetup.lua:65` and `settings/Slash.lua:306-309` |
| Two SV globals, diagnostics ring outside AceDB | `KickCD.toc:7`; `.luacheckrc` `globals` block with the comment; `core/PerfSetup.lua:86` (`sv = "KickCDPerfDB"`) |
| No `embeds.xml`, libs listed directly (AP-38) | `KickCD.toc:16-29` |
| `.pkgmeta` has no `externals:` (AP-7) | `.pkgmeta` — `package-as: KickCD`, comment, `ignore:` list only |
| Frozen prior runs untouched | `docs/audits/2026-07-12/`, `docs/audits/2026-07-18/` unmodified; `git status --porcelain` shows only the untracked `docs/reviews/2026-08-03/` |

---

## 9. Prior-run closure spot-checks

| ID | Was | Now |
|---|---|---|
| `KCD-24` | `settings/Panel.lua` 1641 LOC, over the cap | Peeled to `Panel.lua` (622), `Panel_Widgets.lua` (65), `Panel_Render.lua` (271) — **closed** |
| `KCD-25` | Three chat lines ending in `:` | Sweep returns none — **closed** |
| `KCD-26` | `CLAUDE.md` heading non-canonical | `CLAUDE.md:7-17` — **closed** |
| `KCD-27` | Standards ref missing at place #4 | Place #4 deleted by standard v2.17.0 — **closed by the standard** |
| `KCD-28` | Combat notice not gray / non-canonical | `core/KickCD.lua:736-747` — **closed** |
| `KCD-29` | `libs/AceTimer-3.0/` vendored but unused | Folder deleted — **closed**; the §1/§3 tension is recorded as advisory A-1 |
| `KCD-19` | Files in the on-notice band | Still true; reclassified to advisory A-2 with the reasoning recorded |

## 10. Note on the 2026-08-03 review

`docs/reviews/2026-08-03/05_FINAL_SUMMARY.md:27` reports *"High fixed: 2 — F-001, F-002"*. That
remediation is **not present in the working tree**: `git status --porcelain` shows only the untracked
review folder, the last code commit is `44ac28d` (2026-08-02, a re-vendor), and the code still sits
at the exact line numbers `02_PROPOSED_CHANGES.md` cites for deletion
(`settings/Panel.lua:281,315-341,354-394,432-443`). `KCD-31`, `KCD-32` and `KCD-33` are therefore
live findings, verified independently against the standard's text rather than inherited from the
review. The review's own scope note (`01_FINDINGS.md:26-28`) makes the same hand-off explicit for
`KCD-35`.
