# Testing

A headless Lua unit harness lives under `tests/` — run `lua tests/run.lua` from the repo root (exits non-zero on any failure); `luacheck .` must stay at 0 errors. The suites load every source under a WoW-API mock and assert pure logic, the message bus, the full `OnInitialize → OnEnable` cascade that AceAddon fires on `PLAYER_LOGIN` (via `test_lifecycle`), and the per-frame coalescing of the chatty `SPELL_UPDATE_*` events (via `test_cooldowns`). The harness draws nothing and cannot model taint, so it complements rather than replaces the in-game checks.

## What the frame mock does and doesn't model

`tests/wow_mock.lua`'s frame stub carries **real state** for the properties the addon's correctness depends on — visibility (`Show`/`Hide`/`SetShown`/`IsShown`, with `IsVisible` walking the parent chain), geometry (`SetPoint`/`GetPoint` round trip, size, scale with `GetEffectiveScale` as the product down the parent chain), alpha, text, colour, and `StatusBar` min/max/value. Two C-side seams that accept 12.0 **secret values** are modelled deliberately, because they are the only correct way to branch on a secret: `Frame:SetAlphaFromBoolean` (which also records the raw flag, so a suite can prove the secret was passed through rather than read) and `C_CurveUtil.EvaluateColorValueFromBoolean`.

**Curve evaluation reads the control points.** `__makeDurationObject`'s `EvaluateRemainingDuration` walks the curve it is handed and returns the value of the last point at or below the queried remaining — it does not return a constant. This is load-bearing for the same reason `IsShown` is: the addon's curves are per unit and built from config, so a stub that ignores the points makes "this icon used ITS unit's curve" and "this icon used some other unit's curve" the same observation. A per-unit curve regression shipped green through exactly that hole (see `tests/test_icongrid_curve_link.lua`); the fix was to model the evaluation, not to add more assertions on the curve objects.

This fidelity is load-bearing, not convenience. Against a blanket no-op stub, `IsShown()` returns the frame — permanently truthy — so "the grid hid itself" and "the grid did nothing" are the same observation, and every visibility mode looks alike; `SetText`/`SetValue` go nowhere, so the cast bar's whole render path is unobservable. Anything **not** in that list keeps a self-returning no-op, so unmodelled chains stay inert. `CreateFrame` also records every frame it builds; `mocks.__findFrame(event)` reaches a bootstrap frame that has no published handle (the `PLAYER_REGEN_*` listener in `core/State.lua`), so a suite can fire its `OnEvent` without widening the addon's public surface.

Where a module's decision logic is a file-local, it is published on the module purely so the harness can reach it — the idiom `Castbar.AutoSizeLong` established. Current examples: `Castbar.{UnpackColor,TruncateName,StateConfig,ToSetPoint,Fetch*,StructureSignature,ResolveBarSize}`, `IconGrid.{VisibilityMode,ShouldBeVisible,InstanceCasting,MasterEnabled,SafeUnpackColor,UnpackGlowColor,TriggerSatisfied,PlainStateMoved,CurvesFor,CurveSignature}`, `Cooldowns.{MaterialChange,StateChanged,MasterEnabled}`, `Spells.{ValidateSpellInput,SpecOrder,SortedKeys,TitleCaseToken,ClassDisplayName}` and `Helpers.SnapToStep`. Internal call sites keep using the locals; nothing in the addon calls through these fields.

`Castbar.ResolveGridFrame` looks like it belongs in that list but does **not**: `modules/Castbar_Skin.lua` genuinely calls it to resolve the auto-size reference frame, so it is a real cross-file dependency rather than a harness hook. Its comment says so, to keep a future dead-export sweep from mistaking it for one.

The **authoritative test count and per-suite breakdown** live in the generated inventory at [test-cases.md](test-cases.md) — never a hand-typed number here. Regenerate it (and see the current total) with `lua tests/run.lua --list > docs/test-cases.md`. `lua tests/run.lua --list` is a non-executing listing mode: it loads every suite, prints the full inventory to stdout, and exits without running a single test.

## Testing against the vendored library

`tests/loader.lua` loads the eight `libs/LibKa0s/*.lua` files explicitly, in
`LibKa0s.xml`'s own order, before any addon file — the TOC pulls them in through
that one `.xml`, which the TOC-derived load list deliberately skips. The list is
pinned against the XML by `tests/test_coresetup.lua`, because a library file
omitted there makes the dependent major refuse to register, the host's setup file
fall back to its stub, and the suite happily measure **the stub** — green, and
testing nothing (testing-§9).

The degraded path is exercised by a **real load**, never by hand-stubbing:

```lua
local inst = T.load(true, false, nil, { libFiles = {} })   -- LibKa0s absent
```

Each adopted module has a case proving its stub answers every member the addon
calls, and `tests/test_options_panel.lua` additionally pins `#NS.Settings.Schema`
against the fully-loaded environment — the only thing standing between the
options stub and a silent half-load.

## Verifying the vendored copies

```
diff -r ../LibKa0s/LibKa0s libs/LibKa0s      # must be empty
diff -r ../LibKa0s/testkit tests/_kit        # must be empty
```

Both must be empty before every commit. Nothing about "the tests are green" will
tell you the copies have diverged: the library's suite passes against the
library, and this addon's passes against a stale copy that still works.

## The source-scan guard

Most suites here assert on *behaviour* — drive the real code, inspect what it produced. `tests/test_slash_style.lua` also does something different, and it's worth knowing why before writing another guard like it.

It enforces the no-trailing-colon chat rule (slash-commands-§4, see [conventions.md](conventions.md#chat-output)) two ways:

1. **Behaviourally** — drive `/kcd help`, `debug`, `spells`, and the three diagnostic dumps, then inspect every line that reached `DEFAULT_CHAT_FRAME`. New sub-headers under those paths are covered without anyone adding a case.
2. **By reading the sources** — scan every `.lua` under `core/`, `modules/`, `settings/`, `defaults/`, `locales/` for a string literal ending in `:` that closes a call.

The second exists because the first has a hole that is not fixable by adding more cases: **the mock's `UnitExists` returns false**, so both `Castbar:DebugDump` and `Compat.DebugInterrupt` take their early-return branch and their deep section headers are unreachable headlessly. Five real violations lived in exactly those branches. A behaviour-only guard would have passed on all five, and the 2026-07-18 audit's grep missed them too because it only inspected the help printers.

The scan needs no exemption list. The one legitimate `:`-terminated literal closing a call is a **separator** argument (`table.concat(parts, ":")`), and it is distinguishable structurally: a separator is *exactly* `":"` with nothing before the colon, while a chat header always carries text. Flag a non-empty prefix and `curveSignature`'s concat stays legal on its own merits — no filename or function-name whitelist to rot.

Reach for this shape when a rule must hold in code the harness cannot enter — combat-only paths, branches gated on live game state, anything behind an API the mock stubs to a constant. It is not a substitute for behavioural coverage; it is what you add when you can prove coverage is structurally impossible.

## Keeping the inventory & badge in sync

`docs/test-cases.md` and the README `Tests` badge are hand-maintained-in-lockstep coverage artifacts (Ka0s WoW Addon Standard, testing-§5). Whenever the suite changes — a case is added, removed, or renamed, or the pass count moves (i.e. whenever a failing test is resolved) — regenerate the inventory via `lua tests/run.lua --list > docs/test-cases.md` **and** update the README `Tests-X/Y_passing` badge count in the **same change**, never as a deferred follow-up. Verify the inventory is in sync with `diff <(lua tests/run.lua --list) docs/test-cases.md` (no output = clean).

For end-to-end test scenarios — fresh install, visibility modes, lock/drag, cast bar auto-size, spec/talent/pet rebuilds, profile lifecycle, secret-value safety, etc. — see [smoke-tests.md](smoke-tests.md). The matrices below catalogue what each slash and debug command produces; they're the reference the smoke tests lean on.

## Slash command coverage

- `/kcd` — print the slash command help. `/kickcd` is a long-form alias that routes to the same handler. Every printed line should carry a cyan `[KCD]` prefix (added by `Util.print`); each help row should show the slash invocation in yellow and the description in white.
- `/kcd version` — print the addon version on its own line (`v<X.Y.Z>`), read from the TOC manifest with the in-code `NS.VERSION` stamp as fallback. Covered headlessly by `test_version`.
- `/kcd config` — open the settings panel. Refuses during combat (the Blizzard category-switch is protected); user gets a one-line print instead. `/kcd options` is an alias.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the shared icon grid + cast bar lock state. Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes.
- `/kcd list` — dump every schema-driven setting grouped by panel, with current values. Useful for "did the panel/slash share state?" spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every schema row. `path` is the dotted `db.profile` path (`enabled`, `units.target.icons.primarySize`, `units.target.icons.cooldownTint` …). `set` parses by `def.type`: bool accepts `true/false/on/off/1/0`; number is clamped to `[min, max]`; string must match a `values[i].value` (rejection prints the option list, plus `(depends on <gate> = ...)` when the row carries a `valueGate`); color takes 3–4 floats (`r g b [a]`, each clamped to `[0, 1]`). On success, any open panel refreshes its widgets via `Helpers.RefreshAllPanels()`.
- `/kcd reset <path>` — reset **one setting** to its default, through the same `Helpers.SetAndRefresh` write seam `set` uses (a table default is `DeepCopy`'d, so two profiles resetting to the same RGBA don't share a table). Page-scoped reset lives only on each panel's **Defaults** button now; the five retired page names (`general` / `icons` / `castbar` / `label` / `spells`) each answer with a line naming where their capability went rather than a bare "Setting not found".
- `/kcd resetall` — reset every schema-driven panel **and** every spec's spell list to addon defaults. Mirrors the General → "Reset all settings" popup but with no CLI confirmation prompt.
- `/kcd resetposition` — restore the icon grid to its default screen position. Mirrors the General → "Reset position" button.
- `/kcd spells <subcmd>` — per-class+spec spell-list editor (CLI parity for the Spells panel). Subcommands: `list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`, `resetall`. Every subcommand accepts an optional trailing `[CLASS SPEC]`; both default to the player's current spec when omitted. Note: `/kcd spells reset` rebuilds **one** spec's list, while `/kcd spells resetall` (the new home of the old `/kcd reset spells`) calls `Database:ResetAllSpells` and rebuilds every spec's.
- `/kcd perf` — the guided A/B performance capture (`LibKa0s-Perf-1.0`, wired in `core/PerfSetup.lua`), driven from a clickable step panel. `perf` is a **reserved verb across the collection** and is registered by the addon, never by the library: the lib returns lines and `core/KickCD.lua` prints them through the tagged printer. Records land in the `KickCDPerfDB` saved variable, stamped with the TOC version so a capture is attributable once it leaves the session. The instrumented path is `iconApply`; `NS.Perf.suspended` is consulted by the two show decisions so a capture doesn't measure itself.

## Debug subcommands

Continuous debug output does **not** go to the chat frame. It routes through the `NS.Debug(tag, fmt, ...)` sink (gated on the session flag `NS.State.debug`) into the on-screen debug console — the DIALOG-strata "Ka0s KickCD — Debug" window `LibKa0s-DebugLog-1.0` builds from the descriptor in `core/DebugLogSetup.lua`. The enabled flag is session-only: default off, never persisted to SavedVariables (there is no `db.profile.debugLog` field and no General → "Debug" checkbox), and it resets each `/reload`. The structured `spells|castbar|interrupt` dumps below are still printed to chat.

- `/kcd debug window` — toggle the on-screen debug console window (ScrollingMessageFrame, Copy/Clear buttons, header Debug:ON/OFF toggle, shipped JetBrains Mono font). This is where `NS.Debug` output lands.
- `/kcd debug on` / `/kcd debug off` / `/kcd debug toggle` — set / clear / flip the session-only debug flag `NS.State.debug` via the single write seam `DebugLog:SetEnabled(on)`. Off by default; not persisted; resets each `/reload`.
- `/kcd debug spells` — dump (to chat) the watched cooldown list with `ready / active / cdObj / chargeCdObj / charges` per spell. `cdObj=yes` means a full-cooldown duration object is held; `chargeCdObj=yes` means a charge-recharge timer is ticking while the spell is still castable. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope; charges are also secret-safed via a `safeStr` placeholder.
- `/kcd debug castbar` — print (to chat) one unit's cast state plus the configured/live per-state colors and `notInterruptible`'s type/secret-status (`Castbar:DebugDump(unit)`, defaulting to `target`). Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump.
- `/kcd debug interrupt` — dump (to chat) every `UnitCastingInfo` / `UnitChannelInfo` position with `type()` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting("target")` and the addon-wide visibility / glow-trigger logic decided. The reference for diagnosing 12.0 secret-value handling drift (especially regressions in the `target_casting_interruptible` mode where `notInterruptible` cannot be inspected from Lua). Reads safely via the `safeRender` helper that short-circuits secret values to `<secret>`.

## In-game spot checks

The end-to-end scenarios that used to live here — interrupt-on-hostile, visibility-mode matrix, drag/reload persistence, spec / talent / pet rebuilds, cast bar auto-size — are now part of the comprehensive suite in [smoke-tests.md](smoke-tests.md). Run that file before claiming a non-trivial change works.
