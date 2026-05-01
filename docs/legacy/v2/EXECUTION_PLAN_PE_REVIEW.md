# Execution plan — KickCD PE review

Companion to [`PE_REVIEW.md`](PE_REVIEW.md) and
[`CHANGES_PE_REVIEW.md`](CHANGES_PE_REVIEW.md). This document
sequences the 39 change sets (CR-1 … CR-39) into parallelisable
**workstreams** that can be dispatched as independent sub-agents.

---

## 1. Approach

**Parallelism strategy: phased fan-out, file-domain-isolated workstreams.**

The 39 CRs touch ~16 source files. Naive per-CR parallelism would have
agents fight over `modules/IconGrid.lua` (17 CRs), `modules/Castbar.lua`
(13 CRs), and `core/KickCD.lua` (7 CRs). Instead, we group CRs into
workstreams by file ownership so each workstream owns a coherent
slice of the codebase end-to-end.

**Three phases:**

| Phase | Workstreams | Rationale |
|-------|-------------|-----------|
| **1. Foundations** | WS-A | Adds `core/State.lua`, `core/Constants.lua`, `Util.Throttle/Debounce/DeepCopy`, deletes dead `Compat.RegisterAddOnSetting`. Every other workstream depends on these symbols. **Must land first.** |
| **2. Feature streams** | WS-B + WS-C + WS-D (parallel) | Three independent file domains: spell pipeline + IconGrid (B), Castbar runtime + Compat helpers (C), Settings / slash / panel discipline (D). Run in parallel. |
| **3. Sweep** | WS-E | Cross-cutting cleanups (stale doc refs, FR/NFR tags, `_G.X` consistency, locale completeness). Must land **last** so it sees the final shape of every file. |

**Isolation strategy: worktrees per workstream.** Each agent runs in
an isolated git worktree branched from the latest merged commit. The
agent commits its changes locally on its own branch; the operator
(human) merges branches between phases. This matches the project
preference for human-controlled merges and gives each agent a clean
canvas without other streams' WIP pollution.

**Manual-only verification.** No Lua compiler is available in this
environment. Every workstream's acceptance gate is a structured
manual review: agent surfaces a unified diff and a checklist of
in-game smoke tests. Operator inspects diff and runs smoke tests
in WoW.

---

## 2. Phase summary

```
Phase 1 (sequential)
└── WS-A (foundations)             [5 CRs]   ~4h agent-time

Phase 2 (parallel — 3 agents)
├── WS-B (spell pipeline + IconGrid) [15 CRs]  ~10h agent-time
├── WS-C (Castbar runtime)            [6 CRs]   ~5h agent-time
└── WS-D (Settings/slash discipline)  [10 CRs]  ~6h agent-time

Phase 3 (sequential)
└── WS-E (sweep)                       [4 CRs]   ~3h agent-time
```

**Wall-clock estimate (parallel):** ~17h of agent-time, ~10h
wall-clock if Phase 2 agents run truly in parallel and operator
merges promptly.
**Wall-clock estimate (fully sequential):** ~28h.

---

## 3. Workstreams

Each workstream below specifies:
- **Scope** — files the agent owns exclusively for this run.
- **Ordered CRs** — the change-set sequence the agent works through
  (some CRs depend on earlier ones in the same stream).
- **Agent prompt** — self-contained brief the dispatcher passes to the
  Agent tool.
- **Acceptance gate** — what the operator inspects on completion.
- **Merge protocol** — how the operator integrates the work.

### 3.1 WS-A — Foundations

**Branch:** `pe-review/ws-a-foundations`
**Phase:** 1 (alone; must land before Phase 2 launches).
**Estimated agent-time:** ~4 hours.

**Scope (file ownership):**
- `core/Util.lua` (full)
- `core/Compat.lua` (CR-8 deletion only — leaves rest untouched)
- `core/State.lua` (new file)
- `core/Constants.lua` (new file; **optional** — see CR-30)
- `KickCD.toc` (load-order updates for new files)
- `core/Database.lua` (CR-14 DeepCopy adoption only)
- `settings/Panel.lua` (CR-14 DeepCopy adoption only)
- `settings/Spells.lua` (CR-14 DeepCopy adoption only)
- `modules/IconGrid.lua` (CR-5 read-only swap of `_inCombat` only)
- `modules/Castbar.lua` (CR-5 read-only swap of `_inCombat` only)

**Ordered CR sequence:**
1. CR-8 (delete dead `Compat.RegisterAddOnSetting`).
2. CR-30 (new `core/Constants.lua` — optional, but blocks no one).
3. CR-11 (`Util.Throttle` rename + new true `Util.Debounce`).
4. CR-14 (`Util.DeepCopy` promotion + adopt at three call sites).
5. CR-5 (`KickCD.State.inCombat`; both modules' `_inCombat` reads
   redirected; bootstrap event listener wired).

**Agent prompt:**
```
You are working on the WoW addon KickCD in branch ws-a-foundations.
Read docs/legacy/v2/PE_REVIEW.md (sections 3.1, 3.4, 3.7, 3.10, 5.6),
docs/legacy/v2/CHANGES_PE_REVIEW.md (CRs 5, 8, 11, 14, 30), and the
file headers of every file in your scope.

Implement the five CRs in the order listed under WS-A in
docs/legacy/v2/EXECUTION_PLAN_PE_REVIEW.md §3.1. For each CR, follow
the description and acceptance criteria verbatim from
CHANGES_PE_REVIEW.md.

Constraints:
- Do not touch any file outside the WS-A scope list.
- CR-30 (core/Constants.lua) is optional. If skipped, leave the magic
  constants in place and call it out explicitly.
- Match the surrounding code style (CRLF line endings, comment
  density, naming).
- Update KickCD.toc to load core/State.lua and core/Constants.lua
  AFTER core/Compat.lua and BEFORE core/Util.lua so Util can use
  Constants if desired (and State's bootstrap event listener
  registers cleanly).
- Do NOT run tests (none exist) or attempt to launch WoW.
- Commit each CR as a separate git commit on the ws-a-foundations
  branch with a clear subject line ("CR-8: Delete dead
  Compat.RegisterAddOnSetting", etc.).

Report back with: branch name, file diff summary (one line per file),
and a checklist of the 5 CRs marked complete or deferred (with
reasons).
```

**Acceptance gate (operator runs):**
- `git log ws-a-foundations --oneline` shows 5 commits (or fewer if
  CR-30 skipped), each with a CR-N subject prefix.
- `grep -nR "RegisterAddOnSetting\|_inCombat\|function deepCopy\|local deepCopy" --include='*.lua'` returns expected zeros / single-source results.
- Addon loads in WoW (cold reload). General settings tab opens. No
  Lua errors in BugSack / Lua-error popup.

**Merge protocol:** operator merges `ws-a-foundations` → `master`
locally. No cherry-picking; standard `git merge --no-ff`.

---

### 3.2 WS-B — Spell pipeline + IconGrid runtime + spells bus discipline

**Branch:** `pe-review/ws-b-spells-icongrid`
**Phase:** 2 (parallel with WS-C, WS-D after WS-A merges).
**Estimated agent-time:** ~10 hours.

**Scope:**
- `core/Util.lua` (CR-1 add `NormalizeSpecToken` /
  `NormalizeClassToken`)
- `core/Database.lua` (CR-6 helpers, CR-37 doc, CR-39 dbVersion)
- `core/KickCD.lua` (CR-1 normaliser usage in `resolvePlayerClassSpec`,
  CR-6 spell-list helpers in `runSpells*`, CR-7 drop direct
  `RefreshRows` call in `commitSpellsChange`)
- `modules/Cooldowns.lua` (CR-1, CR-2, CR-6)
- `modules/IconGrid.lua` (CR-1, CR-6, CR-9, CR-12, CR-16, CR-19,
  CR-23, CR-29 sender side, CR-32 doc, CR-34 IconGrid drag-stop half)
- `settings/Spells.lua` (CR-1, CR-6, CR-7 listener wire-up, CR-22)
- `docs/CLAUDE_MESSAGE_BUS.md` (CR-2 sentinel doc, CR-29 payload doc)
- `docs/ARCHITECTURE_MESSAGE_CONTRACT.md` (CR-29 payload doc)

**Ordered CR sequence:**
1. CR-1 (spec/class normaliser; introduces `Util.NormalizeSpecToken`).
2. CR-6 (`Database:GetSpellList` / `EnsureSpellList`; replace 5 call sites).
3. CR-22 (read-only `getActiveList`; build on CR-6).
4. CR-37 (doc the no-reseed intent in `BuildSpells`; light edit).
5. CR-2 (stale-watched cleanup in `Cooldowns:Refresh`).
6. CR-7 (drop direct `KickCD.SettingsSpells.RefreshRows` call;
   register bus listener in `settings/Spells.lua`).
7. CR-39 (`db.profile.dbVersion` + migrator scaffold).
8. CR-9 (single shared cooldown-text ticker in `modules/IconGrid.lua`).
9. CR-16 (dedupe spellID in `BuildActiveList`).
10. CR-12 (warn on layout truncation).
11. CR-19 (GameTooltip ownership check on icon `OnLeave`).
12. CR-23 (`RefreshAllGlows` short-circuit on unchanged gate).
13. CR-29 (enrich `KickCD_GRID_LAYOUT` payload — sender side; receiver
    side falls to WS-C and is gated by WS-C reading the payload).
14. CR-32 (`LCG_KEY` scoping comment).
15. CR-34 (IconGrid drag-stop fires `KickCD_CONFIG_CHANGED`).

**Agent prompt:**
```
You are working on the WoW addon KickCD in branch
pe-review/ws-b-spells-icongrid. Phase 1 (WS-A) has already landed,
so KickCD.State, Util.Throttle, Util.Debounce, Util.DeepCopy, and
the deletion of Compat.RegisterAddOnSetting are all in place — verify
by reading core/Util.lua and core/Compat.lua before you start.

Read docs/legacy/v2/PE_REVIEW.md (sections 2.1, 2.2, 3.2, 3.3, 3.5,
3.8, 4.2, 4.5, 4.8, 4.9, 5.5, 5.8, 5.11, 5.15, 5.17), then
docs/legacy/v2/CHANGES_PE_REVIEW.md for CRs 1, 2, 6, 7, 9, 12, 16, 19,
22, 23, 29, 32, 34 (IconGrid half), 37, 39. Implement them in the
order listed under WS-B in docs/legacy/v2/EXECUTION_PLAN_PE_REVIEW.md
§3.2.

For CR-1: the bug is that GetSpecializationInfo's localised "Beast
Mastery" (with whitespace) does not match the no-whitespace key
"BEASTMASTERY" used in defaults/Spells.lua. Routing every spec-key
build through Util.NormalizeSpecToken fixes this AND any analogous
multi-word spec name in non-English locales. Don't just patch the
two known sites — grep for every uppercase-on-spec-name pattern.

For CR-6 / CR-22: introduce the helpers in core/Database.lua, then
do a sweep replacing every direct profile.spells[class][spec] walk.
The five known sites are listed in CHANGES_PE_REVIEW.md §CR-6;
verify by grep'ing for "profile.spells[" after.

For CR-29: KickCD_GRID_LAYOUT goes from { } to { gridFrame,
primaryIcon, width, height }. The receiver in modules/Castbar.lua
will be updated by WS-C. To avoid breaking Castbar mid-flight,
keep the public accessors KickCD.IconGrid:GetGridFrame() and
:GetPrimaryIcon() so Castbar's existing OnGridLayout code keeps
working. WS-C will switch to the payload form.

For CR-34 (IconGrid half only): in onDragStop, after persisting the
anchor, fire KickCD:SendMessage("KickCD_CONFIG_CHANGED",
{ section = "general" }). Do NOT touch modules/Castbar.lua —
that's WS-C's half.

Constraints:
- Do not touch any file outside the WS-B scope list.
- Match surrounding code style (CRLF, comment density, naming).
- Commit each CR as a separate git commit with a clear "CR-N:
  <subject>" subject line.
- After each CR, run a grep-based self-check from the acceptance
  criteria in CHANGES_PE_REVIEW.md and report results.

Report back with: branch name, per-file diff summary (one line each),
and a 15-row checklist of CRs marked complete with the relevant
acceptance-grep output verbatim.
```

**Acceptance gate:**
- `git log` shows 15 commits (one per CR; or merged if explicitly
  flagged).
- `grep -nR "specName:upper()\|string.upper(specName)" --include='*.lua' .`
  returns 0.
- `grep -nR "profile.spells\[" --include='*.lua' .` returns only the
  Database helpers.
- Manual smoke (in-game): Beast Mastery hunter logs in → grid
  populates with seeded BM defaults; Marksmanship hunter same;
  Mage editing HUNTER/BEASTMASTERY in the Spells tab can add a
  Hunter spell; dismissing pet drops Counter Shot off the grid
  within ~1s without `/reload`.
- Visual: dragging the icon grid still saves position correctly.

**Merge protocol:** operator merges `ws-b-spells-icongrid` → `master`.
Resolve any conflicts from WS-D's parallel work in `core/KickCD.lua`
or `settings/Spells.lua` (rare; non-overlapping line ranges) by
keeping both halves.

---

### 3.3 WS-C — Castbar runtime + Compat helpers

**Branch:** `pe-review/ws-c-castbar`
**Phase:** 2 (parallel with WS-B, WS-D).
**Estimated agent-time:** ~5 hours.

**Scope:**
- `modules/Castbar.lua` (CR-10, CR-17, CR-27 caller side, CR-29
  receiver side, CR-34 Castbar drag-stop half, CR-36)
- `core/Compat.lua` (CR-27 hoist `IsHostileUnitCasting` /
  `ApplyInterruptibleAlpha` out, CR-35 `_firstReturn` helper)
- `docs/CLAUDE_CASTBAR.md` (CR-36)
- `docs/CLAUDE_SECRET_VALUES.md` (CR-36)

**Ordered CR sequence:**
1. CR-35 (`Compat._firstReturn` helper; replace `(unit_call())` patterns).
2. CR-27 (move `IsHostileUnitCasting` / `ApplyInterruptibleAlpha`
   from `core/Compat.lua` to `core/State.lua` (or new
   `core/Visibility.lua`); update Castbar callers).
3. CR-36 (one-paragraph doc + code comment about
   `notInterruptible` plain-after-flip invariant).
4. CR-29 (Castbar reads `KickCD_GRID_LAYOUT` payload's `gridFrame` /
   `primaryIcon` — only after WS-B's sender side is observable; if
   WS-B isn't merged yet, defer this CR to a follow-up commit).
5. CR-10 (Castbar `onUpdate` redundancy elimination).
6. CR-17 (split `Castbar:Reskin` / `Castbar:RenderCast`).
7. CR-34 (Castbar drag-stop fires `KickCD_CONFIG_CHANGED { castbar }`).

**Agent prompt:**
```
You are working on the WoW addon KickCD in branch
pe-review/ws-c-castbar. Phase 1 (WS-A) has landed: KickCD.State exists,
Util.Throttle / Debounce / DeepCopy exist, Compat.RegisterAddOnSetting
is gone. WS-B is running in parallel — do NOT depend on its changes
unless explicitly noted in your CR sequence.

Read docs/legacy/v2/PE_REVIEW.md (sections 3.6, 4.3, 5.3, 5.5, 5.11,
5.12, 5.13), then docs/legacy/v2/CHANGES_PE_REVIEW.md for CRs 10, 17,
27, 29 (receiver), 34 (Castbar half), 35, 36. Implement in the
order listed under WS-C in docs/legacy/v2/EXECUTION_PLAN_PE_REVIEW.md §3.3.

For CR-27: this is a refactor with semantic-preserving moves only.
The two functions move from core/Compat.lua to a new home (your
choice between extending core/State.lua or creating
core/Visibility.lua — pick the one that reads more naturally; State
already exists from WS-A so extending it is one less file). Update
KickCD.toc only if you create a new file. Update every caller (one
in IconGrid, one in Castbar, one in core/KickCD.lua's debug surface)
to call from the new namespace. The OLD function names should NOT
remain in Compat (no shim) — this is a clean break.

For CR-29 (receiver): Castbar:OnGridLayout currently reaches back
through KickCD.IconGrid:GetGridFrame() / :GetPrimaryIcon(). Switch
to reading the payload's `gridFrame` / `primaryIcon` fields. Keep a
fallback to the public accessors for the FIRST tick after enable
when no KickCD_GRID_LAYOUT has fired yet.

For CR-17: this is the heaviest CR in this stream. Castbar:ApplyConfig
becomes Castbar:Reskin (config-driven, called from OnConfigChanged /
OnGridLayout / OnProfileChanged). A new Castbar:RenderCast(rec)
handles cast-record-driven work (set texture, set name, seed bar
values, ApplyState). Castbar:Start calls only RenderCast — not Reskin.
Verify that an open castbar reskins correctly on color-picker writes
and that cast start is fast.

For CR-34 (Castbar half): in onDragStop, after persisting the anchor,
fire KickCD:SendMessage("KickCD_CONFIG_CHANGED", { section = "castbar" }).

Constraints:
- Do not touch any file outside the WS-C scope list.
- If WS-B has not yet merged when you reach CR-29, write a TODO
  comment marking the receiver side and skip — operator will land
  it after the merge.
- Match surrounding code style. Commit each CR separately.

Report back with: branch name, per-file diff summary, CR checklist.
```

**Acceptance gate:**
- `grep -nR "Compat.IsHostileUnitCasting\|Compat.ApplyInterruptibleAlpha" --include='*.lua' .`
  returns 0 outside the new home file (and tests for the new
  `KickCD.State.IsHostileUnitCasting` or `KickCD.Visibility.*` form).
- Manual: cast bar still updates per-frame on a target's cast.
  Cast-start latency is visibly snappier (config no longer
  re-applied on every Start).
- Manual: dragging the cast bar fires `general` config-changed (test
  by toggling a side-effect, e.g., a debug-log).

**Merge protocol:** operator merges `ws-c-castbar` → `master`. If
WS-B's CR-29 sender-side hasn't merged yet, the Castbar receiver-side
(CR-29 in WS-C) reads from the public accessor fallback and works
unchanged.

---

### 3.4 WS-D — Settings + slash + bus discipline

**Branch:** `pe-review/ws-d-settings`
**Phase:** 2 (parallel with WS-B, WS-C).
**Estimated agent-time:** ~6 hours.

**Scope:**
- `settings/Panel.lua` (CR-15, CR-18, CR-24)
- `settings/Castbar.lua` (CR-3)
- `settings/Spells.lua` (CR-4, CR-13, CR-20)
- `settings/Profiles.lua` (CR-20, CR-33)
- `core/KickCD.lua` (CR-21, CR-38)

**Ordered CR sequence:**
1. CR-3 (drop double-dispatch in schema `onChange` —
   `settings/Castbar.lua` reskin and orientation row cleanup).
2. CR-15 (drop redundant `icons` fire on `/kcd resetposition`).
3. CR-24 (schema-shape validation at file load).
4. CR-18 (throttle ColorPicker writes via `Util.Throttle`).
5. CR-21 (`OpenSettings` defers when subcategory not yet built).
6. CR-38 (improve `valueGate` error message).
7. CR-20 (drop `_G.KickCD` fallback in `settings/Spells.lua` and
   `settings/Profiles.lua`).
8. CR-33 (drop dead `Profiles._registered` / `_panel`).
9. CR-4 (scope `Add spell` cooldown-manager validation correctly).
10. CR-13 (cache cooldown-manager set; invalidate on `TRAIT_CONFIG_UPDATED`).

**Agent prompt:**
```
You are working on the WoW addon KickCD in branch
pe-review/ws-d-settings. Phase 1 (WS-A) has landed: Util.Throttle,
Util.Debounce, Util.DeepCopy exist, KickCD.State exists, dead Compat
shim is gone. WS-B and WS-C are running in parallel — do NOT touch
their files (modules/IconGrid.lua, modules/Cooldowns.lua,
modules/Castbar.lua, core/Database.lua, settings/Spells.lua sections
owned by WS-B's CR-1/CR-6/CR-7/CR-22).

Read docs/legacy/v2/PE_REVIEW.md (sections 2.3, 2.4, 3.9, 4.1, 4.4, 4.6,
4.7, 4.10, 5.9, 5.16), then docs/legacy/v2/CHANGES_PE_REVIEW.md for
CRs 3, 4, 13, 15, 18, 20, 21, 24, 33, 38. Implement in the order
listed under WS-D in docs/legacy/v2/EXECUTION_PLAN_PE_REVIEW.md §3.4.

For CR-3: the schema's onChange is duplicating the bus dispatch.
Remove every `onChange = reskin` line in settings/Castbar.lua AND
remove the explicit Castbar:OnConfigChanged call in the
castbar.enabled row's onChange. The bus already fires
KickCD_CONFIG_CHANGED on Helpers.Set; let it dispatch. The ONLY
exception is the orientation row, which has to write through to
growDirection AND refresh panels — keep H.Set("castbar.growDirection",
...) and H.RefreshAllPanels(), but DROP the trailing reskin().

For CR-7 boundary: WS-B owns settings/Spells.lua's bus listener
wiring. Your CR-20 (drop _G.KickCD fallback) and CR-4 (Add-spell
scope) and CR-13 (cm cache) all touch settings/Spells.lua but in
different sections. After WS-B and WS-D both merge, expect
non-overlapping diffs. If you see a merge-conflict-prone edit,
flag it in your report and skip that line range.

For CR-24: the schema validator should print but not refuse to load.
Use |cffff0000KickCD schema error|r: as the prefix.

Constraints:
- Do not touch any file outside the WS-D scope list.
- For settings/Spells.lua specifically, ONLY edit:
    - validateSpellInput / KICKCD_ADD_SPELL OnAccept (CR-4)
    - getCooldownManagerSpellSet (CR-13)
    - The header `local KickCD = …` block (CR-20)
  Do NOT touch getActiveList, RefreshRows, the bus listener wiring,
  buildRow, or the static popup definitions — those are WS-B's.
- Match surrounding code style. Commit each CR separately.

Report back with: branch name, per-file diff summary, CR checklist.
```

**Acceptance gate:**
- `grep -nR "or _G.KickCD" --include='*.lua' .` returns 0.
- `grep -n "_registered\|_panel" settings/Profiles.lua` returns
  no module-level state references.
- Manual: toggling `Enable cast bar` in the panel triggers the bus
  exactly once (verify via `/kcd debug log` — expect one
  CONFIG_CHANGED line, not two).
- Manual: dragging a color slider in Castbar settings doesn't lag
  the bar (the throttle is engaged).
- Manual: a Mage editing `HUNTER / BEASTMASTERY` can add Counter
  Shot.
- Manual: `/kcd config` immediately on login lands on the General
  page (not the empty parent).

**Merge protocol:** operator merges `ws-d-settings` → `master` AFTER
WS-B (so the settings/Spells.lua sections from both don't collide).
If WS-D lands first, no harm — they're non-overlapping by
construction; the Git merge is clean.

---

### 3.5 WS-E — Sweep (cross-cutting cleanup)

**Branch:** `pe-review/ws-e-sweep`
**Phase:** 3 (alone; runs after all of Phase 2 has merged).
**Estimated agent-time:** ~3 hours.

**Scope:** every source file (read-modify-write at low density;
purely cosmetic).

**Ordered CR sequence:**
1. CR-25 (rewrite stale doc references).
2. CR-26 (drop FR/NFR tags from comments).
3. CR-28 (standardise `_G.X` vs bare `X` lookups).
4. CR-31 (add missing locale keys to `locales/enUS.lua`).

**Agent prompt:**
```
You are working on the WoW addon KickCD in branch
pe-review/ws-e-sweep. All previous workstreams (WS-A, WS-B, WS-C,
WS-D) have landed; this is the final sweep.

Read docs/legacy/v2/PE_REVIEW.md sections 5.1, 5.2, 5.4, 5.7, then
docs/legacy/v2/CHANGES_PE_REVIEW.md for CRs 25, 26, 28, 31.

Implement in this order:
1. CR-25 — replace stale doc references. Run:
       grep -nRl "TECHNICAL_DESIGN\|RESEARCH.md\|REQUIREMENTS.md\|EXECUTION_PLAN.md" --include='*.lua' .
   For each file, replace the reference with the correct
   ARCHITECTURE_*.md or CLAUDE_*.md per the index in
   docs/CLAUDE.md / docs/ARCHITECTURE.md. Use prose where no direct
   mapping exists.

2. CR-26 — drop FR/NFR tags. Run:
       grep -nR "FR-[0-9]\|NFR-[0-9]" --include='*.lua' .
   For each match, replace with prose where the comment is still
   useful, or delete the citation entirely.

3. CR-28 — standardise _G.X vs bare X. Document the rule in
   docs/CLAUDE_CONVENTIONS.md (recommended: bare for known-existing
   globals like UnitClass, _G. for runtime-checked globals like
   issecretvalue). Apply uniformly across the three files.

4. CR-31 — extract every L["..."] key from settings/* and
   modules/* via grep, diff against locales/enUS.lua, add explicit
   entries for every missing key. Don't change keys that already
   exist; only add new identity entries (key == English).

Constraints:
- This is a cleanup pass. Do not refactor logic or change behaviour.
- Each CR is a separate commit ("CR-25: Rewrite stale doc refs",
  etc.).
- After each CR, re-run the grep from its acceptance criteria and
  paste the (zero-result) output into the commit message body.

Report back with: branch name, per-file diff summary, the four
acceptance greps' output.
```

**Acceptance gate:**
- All four acceptance greps return 0 hits.
- Diff is purely additive in `locales/enUS.lua` (no key renamed or
  removed).
- Addon still loads (cold reload).

**Merge protocol:** operator merges `ws-e-sweep` → `master`. Ship.

---

## 4. Cross-stream coordination

### 4.1 Inter-phase synchronization

The three phases are **gated**: Phase 2 cannot launch until WS-A is
merged; Phase 3 cannot launch until all of WS-B / WS-C / WS-D are
merged. The dispatcher (the agent or operator launching workstreams)
enforces this:

```
phase 1 ──► WS-A done ──► operator merges ──┐
                                            ▼
                                  phase 2 fan-out (3 agents)
                                            │
                                            ▼
                                  all 3 done + merged
                                            │
                                            ▼
                                  phase 3 ──► WS-E done ──► merge
```

### 4.2 Intra-Phase-2 file overlap matrix

| File | WS-B | WS-C | WS-D | Conflict risk |
|------|------|------|------|---------------|
| `core/Util.lua` | CR-1 add fns | — | — | none |
| `core/Compat.lua` | — | CR-27, CR-35 | — | none |
| `core/Database.lua` | CR-6, CR-37, CR-39 | — | — | none |
| `core/KickCD.lua` | CR-1, CR-6, CR-7 | — | CR-21, CR-38 | low — different functions |
| `modules/Cooldowns.lua` | CR-1, CR-2, CR-6 | — | — | none |
| `modules/IconGrid.lua` | many | — | — | none |
| `modules/Castbar.lua` | — | many | — | none |
| `settings/Panel.lua` | — | — | CR-15, CR-18, CR-24 | none |
| `settings/Castbar.lua` | — | — | CR-3 | none |
| `settings/Spells.lua` | CR-1, CR-6, CR-7, CR-22 | — | CR-4, CR-13, CR-20 | low — non-overlapping line ranges; agent prompts explicitly partition |
| `settings/Profiles.lua` | — | — | CR-20, CR-33 | none |
| `docs/CLAUDE_*.md` | CR-2, CR-29 | CR-36 | — | low — different docs |

**`core/KickCD.lua`** has WS-B (lines ~471-794: spells subcommand
helpers + `commitSpellsChange`) and WS-D (lines ~810-826:
`OpenSettings`; lines ~278-350: `applyFromText` valueGate error). The
two regions are ~150 lines apart; merge is a clean
fast-forward-or-merge.

**`settings/Spells.lua`** is the trickiest. WS-B owns the row layout
+ helper plumbing (the bottom 2/3 of the file). WS-D owns the `Add
spell` validation + cm-cache + the file-header `local KickCD = …`
block (the top 1/3 + the `KICKCD_ADD_SPELL` popup). The agent prompt
explicitly tells WS-D not to touch WS-B's regions. If a real
conflict surfaces at merge time, operator picks WS-B's version (the
heavier refactor) and reapplies WS-D's small change manually.

### 4.3 Operator merge sequence (recommended)

After Phase 2 returns:

1. Merge `ws-b-spells-icongrid` first (largest changeset).
2. Merge `ws-c-castbar` second (no expected conflicts).
3. Merge `ws-d-settings` last (smallest changeset; resolves any
   `settings/Spells.lua` line collisions in WS-D's favour).

After each merge:
- Run `grep -nR "FIXME-merge\|TODO-merge"` to catch unresolved
  conflict markers.
- Reload the addon in WoW; verify no Lua errors.
- Run `/kcd debug spells` and `/kcd debug castbar` to confirm
  modules report sane state.

---

## 5. Verification (manual smoke tests)

The acceptance gates above name the per-workstream smoke tests.
After Phase 3 (WS-E merged), run the **full smoke battery** against
the merged tree:

1. **Cold reload + login** — addon loads cleanly, no Lua errors.
2. **Spec coverage** — log in on Beast Mastery hunter, verify icons
   render. Repeat for Marksmanship and Survival. Repeat for Frost
   DK (no whitespace) and Blood DK (one of the longer default lists).
3. **Spell editor cross-class** — open Spells tab, switch dropdown
   to a class other than the player's. Add Counter Shot (#147362)
   to BM. Verify it's persisted on `/reload`.
4. **Pet dismiss** — on Hunter, summon a pet, see Counter Shot
   render. Dismiss the pet. Counter Shot disappears within ~1s.
   Re-summon: returns.
5. **Visibility modes** — cycle through `always`, `in_combat`,
   `target_casting`, `target_casting_interruptible` while
   targeting a hostile caster. Both grid and cast bar follow.
6. **Drag** — `/kcd unlock`, drag grid + cast bar, `/kcd lock`,
   `/reload`, positions persist.
7. **Reset commands** — `/kcd resetposition` recenters the grid.
   `/kcd reset icons` returns the Icons panel to defaults.
   `/kcd resetall` wipes everything.
8. **Color picker** — drag a slider on a castbar color; the bar
   updates smoothly without UI hitching.
9. **Cast bar** — target a cast-heavy mob; the bar tracks every
   cast with no errors. Boss with toggling immunity (e.g., a dummy
   trainer that gains/loses interruptibility) doesn't error.
10. **Slash commands** — every command in `docs/CLAUDE_TESTING.md`
    runs without error and produces sane output.

---

## 6. Risk register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Phase 2 file conflicts | medium | low | Agent prompts explicitly partition `settings/Spells.lua` and `core/KickCD.lua`. Operator merge order specified. |
| WS-B or WS-D agent times out (long stream) | medium | medium | Each CR commits separately — partial progress is mergeable. Operator can resume by re-launching with "complete remaining CRs from N onward". |
| WS-A's `KickCD.State` design rejected | low | high | Discuss in Phase 1 review before launching Phase 2. Easy to roll back (single commit). |
| In-game smoke test surfaces a regression | medium | medium | The 10-step smoke battery catches the common ones. CR-by-CR commits make `git bisect` viable for the rest. |
| `Cooldowns:Refresh` "send sentinel SPELL_STATE on disappearance" causes IconGrid to render a weird intermediate state | low | low | The IconGrid's no-cdObject branch (already in `Apply`) renders ready visuals; the next `Rebuild` (within seconds) drops the icon. |
| Castbar split (CR-17) breaks an in-progress cast on tab open | low | medium | Manual smoke test #9. Easy to revert just that CR. |
| Locale sweep (CR-31) accidentally renames a key in use | low | medium | Diff is additive-only by construction; CI-equivalent grep validates this. |
| Operator merges Phase 2 in wrong order | low | low | Documented order; Git merges are non-destructive. |

---

## 7. Operator runbook (you, not the agents)

You'll drive this in three sessions, with a confirmation gate
between each:

**Session 1 — Phase 1:**
1. Confirm this execution plan is acceptable (you said "go ahead").
2. Dispatcher launches WS-A in a worktree. Wait for completion.
3. Inspect WS-A's diff. Confirm acceptance gate.
4. Merge `pe-review/ws-a-foundations` to `master`.
5. Smoke-test addon loads cleanly.

**Session 2 — Phase 2:**
6. Dispatcher launches WS-B, WS-C, WS-D in parallel worktrees.
7. Wait for all three to complete (notification per agent).
8. Inspect each diff. Confirm each acceptance gate.
9. Merge in the recommended order: WS-B → WS-C → WS-D.
10. Smoke-test addon loads + 10-step battery.

**Session 3 — Phase 3:**
11. Dispatcher launches WS-E in a worktree.
12. Wait for completion.
13. Inspect diff. Confirm acceptance gate.
14. Merge `pe-review/ws-e-sweep` to `master`.
15. Run the full 10-step smoke battery one more time.
16. Tag `v0.1.1` (optional).

---

## 8. Done-criteria

The PE review is "executed" when:
- All 36 actioned CRs have landed (3 are deferred per §1).
- Manual 10-step smoke battery passes.
- `git log master --since="<start>"` shows the 36 CR commits with
  clear subject lines.
- `PE_REVIEW.md`'s critical & high findings are all resolved
  (verifiable by re-grepping the criteria in CHANGES_PE_REVIEW.md).
