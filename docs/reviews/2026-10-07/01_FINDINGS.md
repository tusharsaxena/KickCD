# 01 — Findings (KickCD full-scope review, 2026-10-07)

**Verdict: minor issues.** The review found nothing Critical or High. Two Medium findings are real
functional defects on narrow paths. Seven Low findings follow.

**Resolved scope:** the whole repository (`all`), on branch `feat/2026-10-07-review-audit-remediation`
at `43aa263` with a clean tree. The review covered the authored source, which is the 127 tracked
`*.lua` files outside `libs/` and `tests/_kit/`, together with the TOC, `.luacheckrc`, `.gitattributes`
and the docs as evidence. Vendored `libs/` and `tests/_kit/` were checked only for sync (see below).
Profile: `wow`, kind `addon`.

**Standards cross-check:** the review used Ka0s WoW Addon Standard **v2.76.1 (2026-10-07)**. The index
and 21 section files came from `raw.githubusercontent.com/.../master`. The other six section files
(`savedvariables`, `slash-commands`, `standalone-windows`, `testing`, `toc-file`, `versioning-git`)
came from the sibling checkout's `master` with `git show master:standards/standards/<f>.md`, because
parallel review agents had slowed the GitHub raw fetch. Five of the GitHub-fetched files were sampled
(`anti-patterns`, `localization`, `events-frames-taint`, `options-ui`, `performance`), and each matched
the local `master` byte for byte.

## Measurement run (Step 0b — every suite re-run today, from scratch)

Every run used `~/.claude/dev-copilot/bin/ka0s-bounded`, written to a scratch path outside the repo.
Nothing in the repo was regenerated.

| Suite | Command (repo root) | Result |
|---|---|---|
| luacheck | `ka0s-bounded luacheck .` | **pass**: `0 warnings / 0 errors in 127 files` |
| Headless tests | `ka0s-bounded lua5.1 tests/run.lua` | **pass**: `1302 passed, 0 failed, 1 skipped, 1303 total`. The skip is the kit's diagnostics-contract opt-out case (`this addon keeps the default … the case above holds it`), so it is not applicable here rather than broken |
| `--list` inventory | `ka0s-bounded lua5.1 tests/run.lua --list` → scratch | **matches** `docs/test-cases.md` exactly after CR-normalization (`diff <(tr -d '\r' < docs/test-cases.md) <(tr -d '\r' < scratch)`, empty). Total 1303. The README badge `Tests-1302%2F1302_passing` leaves the skip out of both figures, as `testing-§5` requires |
| Offline perf | `ka0s-bounded lua5.1 tests/perf.lua` | **ran** (7 scenarios; v1.4.0): `spellPoll` 18.0 api / 581.9 B per iter; `spellState` 0.0 / 1.5; `iconApply` 0.0 / 0.0; `probeOverheadOff` 0.0 / 0.0; `probeOverheadOn` 0.0 / 0.1; `castStart` 0.0 / 208.0; `cdText` 2.0 / 800.0. All runner assertions held (exit 0) |
| Complexity (sighted) | `ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle` | **pass**: `0 warnings (fun rate 0.00), 25917 NLOC / 3580 funcs, avg CCN 2.1 (max 15)`. The kit is revision 37 (`tests/_kit/framework.lua:20`, `Kit.VERSION = 37`), so the run is sighted, and it reported no blind files |
| `make test` | — | **not applicable**: there is no root `Makefile` |
| Vendor sync | `diff -rq libs/LibKa0s ../LibKa0s/LibKa0s`; `diff -rq tests/_kit ../LibKa0s/testkit` | **identical**, both. `../LibKa0s` is at `353f286`, which has no `LibKa0s/` or `testkit/` diff from tag `v1.70.0` (`git diff --stat v1.70.0 HEAD -- LibKa0s testkit` is empty). `CLAUDE.md:42` states v1.70.0 |
| Cross-addon, class 1 (slash roots) | the overlay's two loops, TOC-derived load lists, 11 addons from `ADDONS.md` | **clean**: 22 roots, no collision (`cut -f1 roots.txt \| uniq -d` empty), no raw `SLASH_*` in loaded source. KickCD owns `kcd` and `kickcd` |
| Cross-addon, class 2 (minors) | the overlay's minor loop | **clean**, one line: `Bus:2 Compat:1 Core:10 DebugLog:19 Env:1 Item:2 Launcher:5 Lifecycle:3 Media:4 Options:28 Perf:14 Pool:3 Schema:2 Slash:19 Widgets:12` |
| Cross-addon, class 3 (payload bytes) | `diff -rq AbsorbTracker/libs/LibKa0s <a>/libs/LibKa0s`, AbsorbTracker as the reference | **clean**: exit 0 for all 11. 159 payload files |
| Cross-addon, class 4 (`## Interface:`) | the overlay's loop with `tr -d '\r'` | **clean**: `120100`, uniform |

The cross-addon baseline in the brief was recorded against LibKa0s v1.56.0. Today's tag is v1.70.0,
with 15 majors, 159 payload files and kit revision 37. That difference is a **stale brief, not drift**,
and these figures supersede it.

**Committed artifacts that disagree with today's run.** Both are stale, which is not the same as
non-compliant. Regeneration belongs to release.
- `docs/automated-tests/RESULTS.md`: its newest bundle is `20260927-030444` (`bcf9e51`, 1.3.0 → 1.4.0).
  The runner reports it as **81 commits behind HEAD**. It records 1201/0/1201 tests against 1302/1/1303
  today, 3089 functions against 3580, and 24073 NLOC against 25917. Its perf table has `spellState` at
  1696.6 B/iter against 1.5 today and `spellPoll` at 906.3 against 581.9, with 6 scenarios against 7
  (`cdText` is newer). The record's watch list held 0 CCN warnings, and today also has 0, so no
  complexity entry drifted.
- `docs/perf-analysis/`: the two committed captures (`20260807-131311`, `20260909-014035`) are both
  **v1.2.1**. Every bucket figure in them predates the KickCD#9 ticker split, so this review cites none
  of them as the current cost. The prior review already listed this as a known follow-up.
- `docs/performance.md` **agrees** with today on the one figure it pins (`castStart` "measured 208.0").

**Census (default scope).** `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'` lists 127 files.
`… | tr '\n' '\0' | xargs -0 wc -l | awk '$2!="total" && $1>1000'` lists **0** files in the
`layout-§1` notice band or over the cap. The largest is `modules/IconGrid.lua` at 996 lines.

## Conventions detected (checks applied only where present)

- The secret-safe printer is `NS.Util.print` (`core/CoreSetup.lua`), and no bare `print(` appears in
  the shipped files. The dispatch tables are `NS.COMMANDS`, `DEBUG_COMMANDS` and `SPELLS_COMMANDS`
  (`core/KickCD.lua`), on LibKa0s-Slash.
- The single write seam is `NS.Settings.Store.Set` (`settings/SchemaSetup.lua`). The spell-list writer
  is `NS.Database`, and anchors go through `NS.Units.SetAnchor`. The secret-value document is
  `docs/midnight-quirks.md`.
- `.gitattributes` carries `* text=auto eol=crlf`, `*.sh text eol=lf` and the binary set. `git ls-files
  --eol` shows `539 i/lf w/crlf`, `127 i/-text w/-text` and one `i/lf w/lf` (the `.sh` carve-out). The
  authoritative count belongs to the audit.
- LibKa0s v1.70.0 is vendored and 14 majors are wired, each through a setup file or an inline resolve
  (`docs/ARCHITECTURE.md` → External dependencies). The kit is vendored at `tests/_kit/` (rev 37).
- The evidence sets present are `tests/run.lua` with `docs/test-cases.md`, `tests/perf.lua` with
  `docs/performance.md`, two `docs/perf-analysis/` captures, and `docs/automated-tests/` (15 bundles
  plus `RESULTS.md`).
- Perf buckets cross-check clean. The 11 declared keys in `core/PerfSetup.lua:103-114` match the 11
  distinct `Perf.Note("<key>"` sites across the shipped files exactly
  (`git ls-files '*.lua' | grep -vE '^(libs/|tests/)' | xargs grep -ohE 'Perf\.Note\("[A-Za-z]+"' | sort | uniq -c`).

---

## Medium

### F-001: The cast bar keeps a stale primary-icon anchor after the icon grid empties `[correctness]` `[tests]`

- **Where:** `modules/Castbar_Events.lua:254`:
  `if payload.primaryIcon ~= nil then inst.lastGridLayout.primaryIcon = payload.primaryIcon end`.
  The producer is `modules/IconGrid.lua:495`, which an empty grid reaches:
  `announceLayout(inst, nil, geo.primarySize, geo.primarySize)`. The reader is
  `modules/Castbar.lua:220`: `if inst.lastGridLayout.primaryIcon then return inst.lastGridLayout.primaryIcon end`.
  It feeds `modules/Castbar_Frame.lua:152`:
  `local target = resolvePrimaryIcon(inst) or resolveGridFrame(inst)`.
- **Problem:** `primaryIcon = nil` is the real "no primary icon" state, but the cache treats nil as
  "field absent" and keeps the previous button. That button has already gone back to the pool. It was
  `ClearAllPoints()`ed (`modules/IconGrid.lua:223`) and `Hide()`n (`libs/LibKa0s/Pool.lua:208`,
  `o:Hide()`), so `ApplyAnchor` keeps anchoring the cast bar to a parked button with no points. The
  `or resolveGridFrame(inst)` fallback is never reached.
- **Impact:** while the grid is empty, the cast bar is anchored to a frame with no position. It most
  likely does not render, or renders somewhere unrelated, until an icon comes back or the player runs
  `/reload`. Every re-anchor path (`OnConfigChanged`, `OnProfileChanged`, `OnGridLayout`) re-reads the
  same stale cache. **Unverified in client**: what the client draws for a frame anchored to a pointless
  frame needs a login to confirm.
- **Reachability:** any player on the default `anchorMode = "PRIMARY"` (`defaults/Profile.lua:180`)
  whose active spec's grid goes from at least one icon to zero during a session. That happens when they
  disable or remove every spell on the Spells page or with `/kcd spells disable|remove`, or when they
  swap to a spec whose list has no learned spell. It is a narrow path, but an ordinary one, and a player
  using KickCD only for its cast bar walks straight into it.
- **Coverage:** no case exercises `Castbar:OnGridLayout`. `grep -n 'OnGridLayout\|lastGridLayout'
  tests/*.lua` returns nothing. The IconGrid half is pinned:
  `tests/test_icongrid_layout_pass.lua:126` `assertNil(p.primaryIcon)`. The consumer's handling of
  that nil is not pinned.
- **Needs addressing? Yes.** The fix is one line. The defect makes a working cast bar disappear with no
  error, and there is no test over it.

### F-002: Cast-bar name truncation counts bytes, not characters, under a label that says characters `[locale]` `[ux]`

- **Where:** `modules/Castbar.lua:339-340`:
  `if #name <= maxChars then return name end` / `return string.sub(name, 1, maxChars) .. "…"`.
  The schema row is `settings/Castbar.lua:436`: `label = L["Truncate after (characters)"],`. The
  file's own comment admits the gap at `modules/Castbar.lua:332-333` ("Length is byte-counted;
  multi-byte UTF-8 names may truncate mid-character").
- **Problem:** the cap is applied in bytes. Any non-ASCII character in the spell name makes the visible
  cut shorter than the setting promises. If the cut lands inside a multi-byte sequence, the string
  handed to `FontString:SetText` is invalid UTF-8.
- **Impact:** on deDE, frFR, esES or ptBR clients, any accented name is cut early. On ruRU, the cut
  comes at about half the requested length. On koKR, zhCN and zhTW it comes at about a third. Both
  cases can leave a broken trailing glyph before the "…".
- **Reachability:** any player on a non-English client who sets *Truncate after (characters)* above 0
  (the default is `0`, off, `defaults/Profile.lua:216`), on a cast whose name is not secret. Secret
  names skip truncation at `modules/Castbar.lua:338`. This is opt-in, so it is not High.
- **Needs addressing? Yes, cheaply.** A UTF-8-aware prefix is a few lines. `../MultiMeters` already
  carries its own `utf8Truncate` (`modules/Row_NameCell.lua:280`), so a fix here would be the
  collection's second private copy. `02_PROPOSED_CHANGES.md` weighs that against an upstream member.

## Low

### F-003: An unknown `/kcd debug` word toggles the debug console window `[ux]`

- **Where:** `core/KickCD.lua:465-466`:
  `refuse(self, "Debug", "debug", nil, "unknown subcommand", …)` followed by `runDebug(self, "")`.
  The bare branch it re-enters is `core/KickCD.lua:458`:
  `if self.DebugLog then self.DebugLog:Toggle() end`.
- **Problem:** the reprint after a refusal goes back through the bare-verb branch, which toggles the
  console as well as listing the sub-verbs.
- **Impact:** a typo such as `/kcd debug spels` opens or closes the console as a side effect. The
  suite knows this and works around it rather than pinning it: `tests/test_slash.lua:198-199` runs
  `runVerb("debug NoSuch")` and then `runVerb("debug") -- the reprint toggled the console; toggle it back`.
- **Reachability:** anyone who mistypes a `/kcd debug` sub-verb. The verb is listed in `/kcd help`, but
  in practice it is a diagnostic surface. Nothing is stored or lost.
- **Needs addressing? Yes, cheaply.** The output contract is otherwise good (refusal, then the list).
  Only the side effect is wrong.

### F-004: `/kcd debug castbar` and `/kcd debug interrupt` can only show the target `[ux]`

- **Where:** `core/KickCD.lua:390` `{"castbar", "Print the current target cast bar state",`, then
  `:393` `if m and m.DebugDump then m:DebugDump()`, which passes no unit. `:399` is
  `NS.Compat.DebugInterrupt("target")`. Both callees take a unit: `modules/Castbar_Debug.lua:138`
  `function Castbar:DebugDump(unit, emit)`, and `core/Compat.lua:448`.
- **Problem:** focus has been a first-class tracked unit since dual tracking shipped, but the two
  topic verbs cannot reach it.
- **Impact:** a focus-only cast-bar problem cannot be inspected through the topic verbs. `/kcd
  diagnostics` covers both units (`modules/Diagnostics.lua:207`, `:228-230`), so a workaround exists.
- **Reachability:** only a player or developer debugging the focus bar who types the debug verbs.
- **Needs addressing? Optional.** It is cheap, and it shares a function with F-003. With diagnostics
  covering focus, a won't-fix is defensible.

### F-005: The glow gate ignores casts by a target the player cannot attack, but the `target_casting` trigger counts them `[correctness]`

- **Where:** `modules/IconGrid_Visibility.lua:263-268`. The gate is keyed on `IsHostileUnitCasting`
  (false whenever `UnitCanAttack` is false) and on `resolveInterruptible`, and it returns early when
  neither moved. The trigger it serves is `modules/IconGrid_Render.lua:451`
  (`target_casting` → `inst.isCasting()`, which is any cast, friendly included).
- **Problem:** for a target the player cannot attack, cast start and stop leave the gate tuple at
  `(false, nil)`, so `RefreshAllGlows` never calls `UpdateGlow`. The glow then changes only when an
  unrelated cooldown-state change happens to repaint the icon.
- **Impact:** the *When target is casting* glow is inconsistent for a friendly or non-attackable
  caster. It is off at cast start and stale at cast end.
- **Reachability:** a player who sets a glow trigger to *When target is casting* (the default is
  `"never"`, `defaults/Profile.lua:131`) and targets a non-attackable caster. Nobody on defaults hits
  it, and few players want an interrupt glow for a friendly cast.
- **Needs addressing? Optional.** The owner should first decide what `target_casting` means: any cast,
  as the grid's visibility mode reads it, or a hostile cast. If the answer is "hostile", the fix is in
  the trigger, not the gate.

### F-006: `CONFIG_CHANGED{general}` rebuilds Cooldowns on scale/alpha slider ticks and on every grid drag `[perf]` `[design]`

- **Where:** `modules/Cooldowns.lua:708` `if section == "spells" or section == "general" then` →
  `:713` `self:Rebuild()`. The section is fired by the whole Master-controls block
  (`settings/General.lua:92` `H.AddComposed(masterRows, { panel = "general", section = "general" })`,
  which covers scale, alpha, lock, visibility, debug console and minimap) and by the icon grid's
  drag-stop (`modules/IconGrid.lua:549` `H.FireConfigChanged("general")`).
- **Problem:** the file says this is deliberate (`modules/Cooldowns.lua:709-712`: `"general" still rebuilds for the section's other writes, which is cheap and keeps the watched list current`), but no `general` row changes what Cooldowns polls. The one row that does, `enabled`, already
  reaches Cooldowns through the stand-down latch, and `Cooldowns:Resume` rebuilds. Every throttled
  scale or alpha tick and every drag-stop still pays a full re-poll and a `SPELL_STATE` fan-out to
  every icon of every unit.
- **Impact:** wasted work, at configuration time only. **Unmeasured**: no offline scenario covers the
  config path, so this review claims no cost figure.
- **Reachability:** any player who drags the grid or moves the Scale or Alpha sliders. They see nothing
  wrong.
- **Needs addressing? Optional, low value.** Narrowing the condition is a one-token change, but it
  needs a characterization case proving that `enabled` still rebuilds through Resume.

### F-007: New default spell lists never reach existing profiles `[design]`

- **Where:** `core/Database.lua:265`, `if not isEmpty(profile.spells) then`, followed by `return`. This
  is the all-or-nothing seed, and `:234-254` documents it as deliberate.
- **Problem:** the "don't re-seed customized work" policy is applied to the whole `spells` table, not
  per `(class, spec)` pair. A pair can only be `nil` if it was never seeded: no writer sets a list to
  nil, `RemoveSpell` leaves an empty table, and `ResetAllSpells` re-seeds everything. Seeding missing
  pairs therefore could not overwrite intent, yet it is not done.
- **Impact:** a spec added to `defaults/Spells.lua` later (a new class spec, for example) would give
  every existing profile an empty grid on that spec, with no message.
- **Reachability:** **nobody today.** Every shipped spec, including Devourer (added in `cc6b833`,
  before `1.0.0-release`), has been in the defaults since the first release. The first player affected
  would be one on the next spec Blizzard adds.
- **Needs addressing? Defer.** The re-check trigger is the first spec added to `defaults/Spells.lua`
  after 1.4.0.

### F-008: `.luacheckrc` whitelists read-globals that no shipped file reads `[lint]`

- **Where:** `.luacheckrc:48-79` (`read_globals = {` … `}`). Census command, default scope minus `tests/`:
  `for g in <read_globals>; do git ls-files '*.lua' | grep -vE '^(libs/|tests/)' | xargs grep -lwE "$g"; done`.
  **22 of the names have zero readers among the 50 shipped files.** Two of them, `GameFontDisable` and
  `UIDropDownMenu_AddButton`, have zero readers in any authored file, tests included. The rest are read
  only under `tests/`.
- **Problem:** a whitelist entry with no reader means a new bare call to that global lints clean.
  `UIDropDownMenu_AddButton` is the legacy dropdown API. This continues F-016 from the 2026-09-23
  review, whose deprecated-name half was fixed.
- **Impact:** lint slack only. No runtime effect.
- **Reachability:** development only.
- **Needs addressing? Yes, cheaply.** Drop the two dead names and move the test-only names under
  `files["tests/"]`.

### F-009: `Util.Throttle` allocates an args table on every call, including every `SPELL_UPDATE_COOLDOWN` `[perf]`

- **Where:** `core/Util.lua:190` `pendingArgs = { n = select("#", ...), ... }`, reached from
  `modules/Cooldowns.lua:688` `if self._refreshCoalesced then self._refreshCoalesced() end` for each
  cooldown event.
- **Problem:** the coalescer builds a fresh table even when the call carries no arguments, which is
  always the case for Cooldowns.
- **Impact:** one small table per cooldown event in combat. **Unmeasured**: `tests/perf.lua` has no
  `OnCooldownEvent` scenario, and the committed captures predate the current code.
- **Reachability:** every player in combat. The garbage is real but small.
- **Needs addressing? No change without a measurement.** Add the scenario first. Act only if it shows a
  per-event allocation worth removing.

---

## Not filed (and why)

- **Mixed `NS.L` / literal strings in `COMMANDS`** (3 of 19 rows routed, `core/KickCD.lua:284`, `:298`,
  and `:382` in `DEBUG_COMMANDS`). This is `localization-§3`'s terminal-state question (routed, or an
  English-only register row). That makes it compliance, which belongs to `/dev-copilot:wow-standards-audit`
  under the guardrail, not to this review.
- **Prior review F-001 to F-018** (2026-09-23): re-checked where this pass touched the code. The
  per-profile migrators run on every profile change (`core/Database.lua:662-671`). The cast filters are
  re-armed, not rebuilt (`core/Util.lua:503-530`). `ScheduleTimer` returns a handle. Empowered casts are
  routed (`modules/Castbar.lua:130-132`). The Spells page re-throws render errors after clearing its
  guard (`settings/Spells.lua:706-712`). No regression was found.
- **Cooldown-reduction mid-cooldown.** `Cooldowns.MaterialChange` ignores a new duration object while
  `isActive` stays true. The 0.1 s ticker re-reads the live handle for the text and the curves
  (`modules/IconGrid_Ticker.lua`), so only the swipe could lag. Not filed: unverified, and the
  user-visible effect is speculative.

## Upstream findings

**None.** Vendor sync and the four cross-addon classes are clean. F-002's fix direction may become an
additive LibKa0s member (see `02_PROPOSED_CHANGES.md`). That would be a feature request upstream, not
a defect in the vendored copy.
