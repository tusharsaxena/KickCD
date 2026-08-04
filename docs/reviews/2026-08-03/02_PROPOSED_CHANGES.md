# KickCD — Proposed Changes (HLD + LLD), 2026-08-03

**Standard resolved:** Ka0s WoW Addon Standard **v2.17.1 (2026-08-03)**, read from the local
`WowAddonStandards` clone at `master` HEAD `2141229` (clean tree) after the raw GitHub endpoints timed
out from this environment. Every change below was checked against it; rules that shaped or vetoed a
change are cited as `filename-§N`.

**No entry in this document targets a path under `libs/` or `tests/_kit/`.** There is no upstream
change-set in this pass — see `01_FINDINGS.md`.

---

## HLD — themes

### Theme A — Finish the LibKa0s-Options de-duplication (F-001, F-004, F-007)

*Rationale.* `settings/OptionsSetup.lua` correctly makes `NS.Settings.Helpers` **be** the library
instance rather than a copy-across table, which is what `options-ui-§1` asks for. What was not
finished is the other half: `settings/Panel.lua` still ships the pre-extraction implementations of
`AttachTooltip`, `EnsureScroll`, `AddSpacer`, `LSMValues` and the `ROW_VSPACER` constant, and assigns
them onto that same instance. Because the library's widget makers reach those members *through the
instance*, KickCD is running host code inside library call paths. That is anti-pattern #47 with the
blast radius pointed inward, and `options-ui-§8`'s host-copy prohibition on top.

*Alternatives considered.*

- **Keep the host copies but rename them off the library's keys** (`Helpers.KcdEnsureScroll`, …).
  Rejected: it preserves two implementations of one thing, which is the drift the extraction exists to
  end (anti-pattern #47). It also silently changes panel geometry, since the library's makers would
  then use the library's scroll while host page code used the host's.
- **Patch `libs/LibKa0s/Options.lua` to accept host overrides as a documented seam.** Rejected
  outright: a local edit under `libs/` is reverted by the next re-vendor with no trace in this repo's
  history (`library-stack-§7`, anti-pattern #45). If a seam is genuinely wanted it is an **additive**
  descriptor field pushed upstream first, then re-vendored — and nothing here needs one.
- **Do nothing, since the values agree today.** Rejected: `O.AddSpacer`'s return value is already a
  live contract difference, and the rule exists precisely so that agreement cannot silently lapse.

*Trade-off.* Deleting `ensureScroll` means the addon's scroll geometry becomes the library's. The two
are byte-equivalent today (`PADDING_X - 4, -8` / `-(PADDING_X + 12), 8`, both with 16), so this is a
no-op visually — but it is worth an explicit smoke test, which `03_SMOKE_TESTS.md` provides.

### Theme B — One secret-safe stringifier, one detection mechanism (F-002)

*Rationale.* `events-frames-taint-§8` makes the shared stringifier a MUST and names exactly one
sanctioned second copy: the library-absent branch of `core/CoreSetup.lua`. `Compat.DebugInterrupt`'s
private `safeRender` is a third, and its detection (`issecretvalue`) is not the mandated one
(a `table.concat` probe). The failure it invites lands inside the command whose whole purpose is
diagnosing secrets.

*Alternative considered.* **Harden `safeRender` in place** by adding a `pcall`-of-`table.concat`
fallback. Rejected: it makes the duplicate *correct* rather than *absent*, which the standard treats as
the wrong direction — the addon must not carry its own stringifier at all.

### Theme C — Survivable library resolution in the settings layer (F-003)

*Rationale.* `options-ui-§1` names AceGUI survivable, not a dependency, and the whole
`settings/OptionsSetup.lua` stub design is built on the principle that a missing library degrades
rather than half-loads. Three hard `LibStub` calls contradict it from inside the same folder.

*Alternative considered.* **Move the resolution into the descriptor and pass it around.** Rejected as
over-engineering: the instance already exposes `O.AceGUI`, resolved once at `:New`, which is exactly
the "resolve once, read the upvalue" rule the descriptor's `onAceGUI` comment cites.

### Theme D — Correctness and hygiene (F-005, F-006, F-008, F-009, F-010, F-011)

*Rationale.* Six independent, low-coupling fixes with no shared design story: a missing `pcall` around
a transient settings write, two packaging ignores, an unclosed perf bracket, a dead-end diagnostic
branch, ten orphaned locale keys, one self-contradicting doc line. Grouped only so they can be
sequenced together.

---

## LLD — change-set

### C-01 — Delete the host copies of library-provided Options members
**Covers:** F-001. **Files:** `settings/Panel.lua`, `settings/Panel_Render.lua`,
`settings/Panel_Widgets.lua`.

Remove from `settings/Panel.lua`:

- `attachTooltip` (:315-340) and `Helpers.AttachTooltip = attachTooltip` (:341) — byte-identical to
  `libs/LibKa0s/OptionsWidgets.lua:152-176`.
- `ensureScroll` (:354-388) and `Helpers.EnsureScroll = ensureScroll` (:394) — equivalent to
  `libs/LibKa0s/Options.lua:305-333`.
- `addSpacer` (:432-438) and `Helpers.AddSpacer = addSpacer` (:443) — equivalent to
  `libs/LibKa0s/OptionsWidgets.lua:181-188`, **except** the library's returns the widget.
- `Helpers.LSMValues` (:281-291) — the library's `O.LSMValues` (`Options.lua:485-497`) is a deferred
  closure factory fed by the descriptor's existing `getLSM` seam (`OptionsSetup.lua:104`).

Then update the internal callers that used the file-locals:

```lua
-- settings/Panel.lua — BuildMainContent and friends
-  local scroll = ensureScroll(ctx)
+  local scroll = Helpers.EnsureScroll(ctx)
```

```lua
-- settings/Panel_Render.lua:20 — the load-time upvalue now reads the library's constant
-  local ROW_VSPACER = Helpers.ROW_VSPACER      -- (unchanged line, but now library-sourced)
```

**Call-site sweep required.** `H.LSMValues(...)` currently returns a *table*; the library's returns a
*function*. Every call site is already `values = function() return H.LSMValues(m) end`
(`settings/Icons.lua:196,220`; `settings/Label.lua:147`; `settings/Castbar.lua:280,401,438,463,500`),
so each becomes `values = H.LSMValues(m)` — the closure the library hands back **is** the `values`
function the schema row wants. This is the one non-mechanical part of C-01.

**Risk:** medium. Touches the render path of every settings page. The empty-media fallback key changes
from `"Default"` to the library's `LSM_NONE`, which is user-visible in a dropdown when no media library
is loaded. Mitigated by the per-page smoke tests in `03_SMOKE_TESTS.md`.

**Standards conformance:** required by `options-ui-§1` (instance decorated only with pieces that did
not generalize) and anti-pattern #47. The rejected alternative — renaming the host copies onto private
keys — would have left two implementations, which #47 forbids by name.

### C-02 — Delete the host copies of library layout constants
**Covers:** F-004. **Files:** `core/Constants.lua`, `settings/Panel.lua`.

```lua
-- core/Constants.lua:66
- Const.PANEL_PADDING_X    = 16
```
```lua
-- settings/Panel.lua:307
- local PADDING_X = NS.Const.PANEL_PADDING_X
+ -- PADDING_X is the library's (options-ui-§8); read it off the instance where the
+ -- landing-page body needs it: Helpers.PADDING_X.
```
```lua
-- settings/Panel.lua:426-430
- local ROW_VSPACER = 8
- Helpers.ROW_VSPACER = ROW_VSPACER
```

`Helpers.ROW_VSPACER` then keeps the value the library set at `Options.lua:159`. Correct the stale
comment at `Panel.lua:300-306` so it describes what the file now does.

**Dependency:** `PADDING_X` is only still needed by `BuildMainContent`'s own blocks once C-01 removes
`ensureScroll`. The library does **not** currently publish `PADDING_X` on the instance (only
`ROW_VSPACER`, `SECTION_HEADING_H`, `BUTTON_PAIR_REL` — `Options.lua:159-161`). Two compliant options:
(a) keep the landing-page body's horizontal inset as a **host** constant, which `options-ui-§8`
explicitly sanctions ("*Landing page … these are the host's own constants, since the body is*") and
name it so — `MAIN_PADDING_X`, in `settings/Panel.lua` beside the other `MAIN_*` values at :455-458;
or (b) push `PADDING_X` onto the instance upstream as an additive field. **(a) is chosen** — it needs
no cross-repo work and is the reading `options-ui-§8` already gives for landing-page geometry.

**Risk:** low. Values are identical; only ownership moves.

**Standards conformance:** `options-ui-§8` MUST NOT on host copies of the header/body constants, with
its own landing-page carve-out used for the one value that stays.

### C-03 — Correct the Options stub's justification comments
**Covers:** F-007. **File:** `settings/OptionsSetup.lua:144-145, 180-182`.

Replace "*settings/Icons.lua and settings/Castbar.lua evaluate `H.LSMValues("border")` and
`H.AnchorValues()` inside schema-row literals, at FILE LOAD*" with the measured truth: `LSMValues` is
reached through a closure and is therefore **not** a load-time member; `AnchorValues`/`AnchorOrder`
**are** (`settings/Icons.lua:39`, `settings/Castbar.lua:52`) and are published unconditionally by
`settings/Panel.lua:244,266`, which loads before every page file. Delete the "*the stub answers until
then*" clause at :180-182, which describes members the stub does not define.

**Note:** C-01 changes this analysis — after C-01, `LSMValues` comes from the library and its absence
*is* a load-time hole. Re-run the measurement (`tests/test_options_panel.lua`'s library-absent load)
and let the result, not this document, decide the stub's member set. `options-ui-§1` requires exactly
that: *"MUST determine that set by measurement, not by reading."*

**Risk:** low (comments), but sequencing matters — see `04_EXECUTION_PLAN.md`, C-03 runs after C-01.

### C-04 — Route `Compat.DebugInterrupt` through the shared stringifier
**Covers:** F-002. **File:** `core/Compat.lua:377-403`.

```lua
-  local function safeRender(value)
-      if _G.issecretvalue and _G.issecretvalue(value) then return "<secret>" end
-      local t = type(value)
-      if t == "string"  then return ("%q"):format(value) end
-      ...
-  end
+  -- The stringifier is LibKa0s-Core-1.0's, published by core/CoreSetup.lua
+  -- (events-frames-taint-§8: detection MUST probe table.concat, not `..` and not
+  -- issecretvalue alone). The isSecret= column below stays issecretvalue-driven —
+  -- that is diagnostic REPORTING, which is this command's whole point, not
+  -- stringification.
+  local function safeRender(value)
+      return NS.SafeToString and NS.SafeToString(value) or "<unavailable>"
+  end
```

`describe()` (:399-404) keeps its `issecretvalue`-derived `isSecret=` column unchanged. The `("%q")`
quoting of plain strings is lost; if the quoting is wanted, apply it *after* `SafeToString` has
returned a string known safe.

Apply the same substitution at `modules/Castbar_Debug.lua:45`'s stringification (the
`issecretvalue` probe there is likewise a legitimate *report*, so only the surrounding `tostring` moves).

**Risk:** low. Output text for plain strings loses surrounding quotes unless re-added.

**Standards conformance:** `events-frames-taint-§8` (single shared secret-safe printer/stringifier;
concat-probe detection) and anti-pattern #47. Rejected alternative: hardening `safeRender` in place —
it keeps a forbidden duplicate.

### C-05 — Resolve AceGUI survivably in the settings layer
**Covers:** F-003. **Files:** `settings/Panel.lua:30`, `settings/Panel_Widgets.lua:30`,
`settings/Panel_Render.lua:13`.

```lua
- local AceGUI = LibStub("AceGUI-3.0")
+ -- Survivable, not a dependency (options-ui-§1). The library resolves it once at
+ -- :New and holds it on the instance; read that, and fall back to a silent LibStub
+ -- for the library-absent path. Every use site below is already reached only from a
+ -- builder, so a nil AceGUI degrades to "no panel" rather than a load-time raise.
+ local AceGUI = (NS.Settings and NS.Settings.Helpers and NS.Settings.Helpers.AceGUI)
+     or (LibStub and LibStub("AceGUI-3.0", true))
```

Each file's widget-creating helpers gain a leading `if not AceGUI then return end`.

**Risk:** low-medium — the guard must be added to every creator or a nil AceGUI merely relocates the
raise. `luacheck` will not catch a missed one; the smoke test for C-05 exercises the panel end to end.

**Standards conformance:** `options-ui-§1` ("survivable, not a dependency") and the resolve-once rule
the descriptor's `onAceGUI` comment already cites.

### C-06 — Make `GateHint`'s probe restore unconditionally
**Covers:** F-005. **File:** `settings/Slash.lua:118-129`.

```lua
      for candidate in pairs(gateValues) do
          if candidate ~= gateVal then
-             parent[key] = candidate
-             local alt = allowedKeys(row)
-             parent[key] = gateVal
+             -- The restore MUST run even if a row's values() raises: this is a raw
+             -- profile write (deliberately, so it fires no onChange and no bus
+             -- message), and an unwound loop would persist a probe candidate into
+             -- KickCDDB. pcall is what keeps "transient" true rather than merely
+             -- intended (architecture-§5, options-ui-§1 single write seam).
+             parent[key] = candidate
+             local ok, alt = pcall(allowedKeys, row)
+             parent[key] = gateVal
+             if not ok then alt = {} end
              if #alt > 0 then ... end
          end
      end
```

**Risk:** very low.

**Standards conformance:** keeps the single-write-seam exception narrow and provably transient rather
than widening it. Rejected alternative — routing the probe through `Helpers.SetAndRefresh` — would fire
`onChange` and `Ka0s_KickCD_CONFIG_CHANGED` twice per candidate, which `architecture-§4` and
`options-ui-§11` both make expensive and wrong.

### C-07 — Close the `castTick` bracket on its early exit
**Covers:** F-008. **File:** `modules/Castbar.lua:694-697`.

```lua
      if not d then
          frame:SetScript("OnUpdate", nil)
+         if __t0 then Perf.Note("castTick", debugprofilestop() - __t0) end
          return
      end
```

**Risk:** none. **Standards conformance:** `performance-§3`. Add a case to `tests/test_perfsetup.lua`
alongside the existing `PollSpell` exit case so the invariant is pinned for both.

### C-08 — Give the secret `notInterruptible` branch an unconditional line
**Covers:** F-009. **File:** `modules/Castbar_Debug.lua:51-58`.

```lua
      else
-         if _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean then
-             print("    secret-tainted; visual state determined via "
-                 .. "C_CurveUtil.EvaluateColorValueFromBoolean")
-         end
+         local via = (_G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean)
+             and "C_CurveUtil.EvaluateColorValueFromBoolean"
+             or "no curve evaluator on this client — visuals fall back to interruptible"
+         print("    secret-tainted; visual state determined via " .. via)
      end
```

**Risk:** none.

### C-09 — Add the scratch directories to `.pkgmeta`
**Covers:** F-006. **File:** `.pkgmeta`.

```yaml
 ignore:
   - .luacheckrc
   - .gitignore
   - .gitattributes
+  - .superpowers
+  - .claude
   - docs
   - tests
   - _dev
   - "*.bak"
```

**Risk:** none. **Standards conformance:** `packaging`.

### C-10 — Remove the orphaned locale keys
**Covers:** F-010. **File:** `locales/enUS.lua`.

Delete the ten keys listed in F-010. Because a key *is* its English string (`localization-§2`), a
deletion is only safe with zero call sites — verified by grep across `core/`, `modules/`, `settings/`.
`enUS.lua` is currently the only locale file, so there is no sibling to keep in step; if that changes,
the same deletion must land in every locale file in the same commit (`localization-§5`,
anti-pattern #46).

**Risk:** low — a missed call site renders the raw key rather than erroring, so `tests/test_locale.lua`
should be extended to assert the key set matches the used set in both directions.

### C-11 — Fix the message-bus doc's self-contradiction
**Covers:** F-011. **File:** `docs/message-bus.md:61`.

Rewrite the sentence so it states the policy the table records: one owning emitter per message by
default; `Ka0s_KickCD_CONFIG_CHANGED` is multi-module **by design**, with each emitter owning exactly
one `section` value, and `Ka0s_KickCD_PROFILE_CHANGED`'s two call sites both in `core/Database.lua`.
Drop the "*must live in the same file as the first*" clause, which the table has never satisfied.

**Risk:** none. **Standards conformance:** `architecture-§4` permits a recorded justification for a
second sender and requires each message documented with sender, payload and consumers — the table
already does that; only the rule sentence is wrong.

---

## Standards conformance summary

| Change | Rules that shaped it | New deviation introduced? |
|---|---|---|
| C-01 | `options-ui-§1`, `options-ui-§8`, anti-pattern #47 | No — removes one |
| C-02 | `options-ui-§8` (incl. its landing-page carve-out) | No |
| C-03 | `options-ui-§1` (measurement, not reading) | No |
| C-04 | `events-frames-taint-§8`, anti-pattern #47 | No — removes one |
| C-05 | `options-ui-§1` (AceGUI survivable) | No |
| C-06 | `architecture-§5`, `options-ui-§1`, `options-ui-§11` | No |
| C-07 | `performance-§3`, `testing` | No |
| C-08 | — (UX) | No |
| C-09 | `packaging` | No |
| C-10 | `localization-§2`, `localization-§5`, anti-pattern #46 | No |
| C-11 | `architecture-§4` | No |

No proposed change edits, forks or works around anything under `libs/` or `tests/_kit/`, and none
re-implements a subsystem a LibKa0s module provides.
