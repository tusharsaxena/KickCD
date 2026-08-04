# CCN elimination — KickCD

Branch `feat/fix-ccn`. Design: `LibKa0s/docs/superpowers/specs/2026-08-04-ccn-elimination-design.md`.

**20 functions** with `lizard` CCN > 15. Target: every one at CCN <= 15, behavior unchanged.

## Exit criteria

1. `luacheck . --quiet` — 0 warnings, 0 errors.
2. `lua5.1 tests/run.lua` — all pass, count >= baseline.
3. `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` — no CCN > 15.
4. No behavior change. No version bump, no CHANGELOG, no merge, no tag.

## Rules

- Preferred shapes, in order: table-driven dispatch; a named file-local helper for a
  self-contained block; a data table + loop replacing repeated defaulting; splitting a
  builder into N small builders.
- No dumping a body into one helper to game the metric. Every resulting function must be a
  unit a reader can name.
- Dispatch/defaults tables are **module-level**, built once at file load — never per call.
- `lizard` counts `and`/`or` as decisions. Prefer `== nil` over `or` wherever a stored
  `false` or `0` must survive.
- Hot paths must not gain a per-call allocation.
- Sixteen functions across the collection have no coverage; where this file says
  `Coverage: NONE`, write a characterization test pinning current behavior **before**
  refactoring.

## Functions

### `ReskinStructure` — CCN 36 → target 7

`modules/Castbar_Skin.lua:176-325` · pattern `multi-part-layout-builder` · risk **medium**

**What it does.** The geometry half of the cast bar re-skin — everything whose cost is a resize, re-anchor, texture reload or font load. Guarded by a structure signature so it is skipped when nothing geometric changed (F-015); `force` bypasses the guard after EnsureFrame builds fresh widgets.

**Where the branches come from.** By far the worst in the repo, and it is five unrelated jobs in one body. A signature gate; an orientation/reverse-fill decision pair; a 2x2 icon-position matrix (VERTICAL/HORIZONTAL x LEFT/RIGHT) with four fully-written SetPoint triples plus an OFF arm; a spark block with its own vertical/horizontal sizing, a rotation guard, and a second 2x2 anchor matrix; a font block with a NONE/nil flag normalization; two text-anchor calls with six `or` defaults between them; two show/hide ternaries; two border backdrops.

**Fix.** The textbook N-independent-sub-parts split, with the two matrices turned into module-level constant data. Add `local ICON_LAYOUT = { VERTICAL = { NEAR = {...}, FAR = {...} }, HORIZONTAL = { NEAR = {...}, FAR = {...} } }` where each entry holds the icon point and the two bar SetPoint specs with a sign for the iconSize inset — this replaces all four hand-written branches with one lookup and two data-driven SetPoint calls. Add `local SPARK_ANCHOR = { VERTICAL = { [true] = "BOTTOM", [false] = "TOP" }, HORIZONTAL = { [true] = "LEFT", [false] = "RIGHT" } }`. Then five file-locals: `applyBarGeometry(frame, isVertical, reverseFill, barLong, barThick)`, `applyIconLayout(frame, c, isVertical, barThick)` (icon size clamp, showIcon decision, the ICON_LAYOUT lookup, the hidden arm), `applySpark(frame, c, isVertical, reverseFill, barThick)`, `applyLabelFonts(frame, c)` (font resolution, flag normalization, the two anchorTextElement calls, the two show/hide), and the existing `applyBorderBackdrop` pair. ReskinStructure keeps only: resolve isVertical/sizes, the signature gate, the reverseFill decision, and five calls.

**Must not change.** The signature gate is a real performance contract — the early return on an unchanged signature, and `force` overriding it, must both survive, and inst.structureSig must still be stamped before any widget work. The two matrices are pure in-game visuals with no headless assertion behind them: the VERTICAL remap (LEFT reads as TOP, RIGHT as BOTTOM), the iconSize clamp to barThick, the reverse-fill polarity (HORIZONTAL/LEFT and VERTICAL/DOWN are the reversed cases), and the spark's 90-degree rotation in vertical mode with its size axes swapped. A transposed table entry here is invisible to every test and obvious to every user.

**Coverage.** tests/test_castbar_skin.lua covers Reskin's signature stamping, the skip-on-unchanged behavior, the force override, and safety before the frame exists — but NOT the icon-position or spark-anchor matrices. Add the four iconPosition x orientation cases and the four spark-anchor cases as characterization tests first; they are exactly what the new constant tables encode.

---

### `Castbar:DebugDump (lizard: Castbar@17-95)` — CCN 27 → target 7

`modules/Castbar_Debug.lua:17-95` · pattern `debug-dump-builder` · risk **low**

**What it does.** The /kcd debug castbar dump: prints the tracked unit, the tracked cast record's field types and secret-taint state, the per-state colours as read from the live profile, and the colours currently live on the StatusBar widgets — deliberately avoiding tostring/format on any possibly-secret field.

**Where the branches come from.** Highest CCN in the file and it is pure accumulation: a unit-exists guard, a no-cast guard with its own nested Compat probe, a header line built from three inline `and/or` ternaries, a three-way if/elseif/else on the notInterruptible type with a nested C_CurveUtil availability check, two closures (fmtColor, fmtStatusColor) each with their own guards and `or` defaults, and two four-line colour report blocks.

**Fix.** Split into four file-local printers, each taking `print` as its first argument, and hoist both formatter closures to file-locals (neither captures anything). `dumpUnitHeader(print, inst)` — exists guard plus the name/isUnit/canAttack line. `dumpCastRecord(print, inst)` — the isChannel line and the notInterruptible type report, with the three-way ladder replaced by a module-level `local NINT_REPORT = { boolean = ..., ["nil"] = ... }` lookup and a default 'secret-tainted' arm. `dumpConfiguredColors(print, inst)` — the NS.Units.Castbar reads through fmtColor. `dumpLiveBarColors(print, inst)` — the two fmtStatusColor lines. DebugDump becomes: resolve inst and print, the exists guard, the no-cast guard, then four calls.

**Must not change.** The no-tostring-on-secrets rule: notInterruptible, spellID, texture and name may only be reported via type() and the boolean-branch path, never through tostring or format. The early return when inst.current is nil must still first probe Compat.GetCastingInfo and print the 'missed event?' hint — that hint is the whole diagnostic value of that branch. Colours must keep rendering through NS.Util.Unpack (the keyed storage shape); a positional read here would report four zeroes and send the reader chasing a nonexistent bug.

**Coverage.** NONE — no test file references DebugDump. Needs a characterization test capturing the printed lines for the three notInterruptible states before refactoring.

---

### `IconGrid:RefreshAllGlows (lizard: IconGrid@957-1024)` — CCN 25 → target 8

`modules/IconGrid.lua:957-1024` · pattern `gate-cache-with-inline-resolution` · risk **medium**

**What it does.** Re-pushes the glow decision across every icon when the trigger condition could have moved (unit swap, cast start/stop, interruptibility flip), short-circuiting on a per-instance cache of the two booleans the trigger predicates branch on so a boss firing many short casts does not re-evaluate N icons per event.

**Where the branches come from.** A three-term `and/or` hostileCasting read; the interruptible tri-state resolution — nested UnitCastingInfo / UnitChannelInfo fallback, a secret probe, and a plain-value coercion, four levels deep; a four-term cache comparison; a per-change table allocation for lastGlowGate; a debug block containing a four-arm `and/or` label ladder plus its own dedup branch; and the final loop with a per-button method guard.

**Fix.** HOT — fires on every UNIT_SPELLCAST_* transition. Three extractions plus one allocation removal. `local function resolveInterruptible(unit, hostileCasting)` returns the tri-state (true/false/nil/"secret") and owns the whole nested API fallback and secret probe. Replace the `inst.lastGlowGate = { ... }` table with two scalar instance fields, `inst.lastGateCasting` and `inst.lastGateInterruptible` — this removes an allocation on every gate change, which is precisely the boss-cast case the cache exists for, and lets the comparison read as a plain `local function gateMoved(inst, casting, interruptible)`. Replace the debug label ladder with a module-level `local GATE_LABEL = { [true] = "on", [false] = "off", secret = "secret (combat-tainted)" }` and a `local function logGateChange(inst, unit, interruptible)` doing `local gate = GATE_LABEL[interruptible] or "none (no hostile cast)"` plus the dedup. RefreshAllGlows becomes: read hostileCasting, resolve, `if not gateMoved(...) then return end`, store the two scalars, logGateChange, loop.

**Must not change.** The "secret" sentinel must keep DEFEATING the short-circuit — while interruptibility is secret-tainted the gate is deliberately bypassed and iteration re-runs every time (correctness over efficiency for the rare flip). The debug dedup on the printed label is the only thing keeping that bypass from spamming a line per boss cast, so it must move with it. The tri-state distinction between false (hostile cast, not interruptible) and nil (no hostile cast) must not collapse — the labels are deliberately distinct. Note GATE_LABEL cannot be keyed on nil, hence the `or` fallback rather than a fourth entry.

**Coverage.** Effectively NONE. tests/test_perfsetup.lua reaches it indirectly by poking IconGrid.OnUnitCastEvent to fill the castEvent bucket, but asserts nothing about the gate cache; tests/test_icongrid_apply.lua and tests/test_icongrid_curve_link.lua cover UpdateGlow, not this caller. Needs a characterization test for the short-circuit, the secret bypass and the debug dedup before refactoring.

---

### `Icon:Apply (lizard: Icon@633-721)` — CCN 25 → target 8

`modules/IconGrid_Render.lua:633-721` · pattern `branch-render-dispatch` · risk **medium**

**What it does.** Applies a Ka0s_KickCD_SPELL_STATE payload to one icon — picks one of three render branches (full cooldown / charge recharge / idle), drives the swipe, countdown text, alpha, tint and GCD suppression from duration objects, then refreshes the glow and the charges badge.

**Where the branches come from.** A Perf bracket at both ends; a cfg fallback; a `force or plainStateMoved(...)` gate; a three-way branch whose first arm tests three terms (state, cdObject, curves.alpha) and second tests two; four separate `if stateWork` sub-gates scattered across the branches; nested `curves.tint` and `color and color.GetRGB` guards; a SetAlphaFromBoolean availability branch; and a two-term charges-badge gate.

**Fix.** HOT — one call per icon per SPELL_STATE message. Split the three render arms into file-locals taking explicit scalar arguments so no table is created: `renderFullCooldown(icon, state, curves, stateWork)` (the alpha evaluate with its SetAlphaFromBoolean fallback, the tint evaluate with its GetRGB guard, the swipe, the text, the GCD mask), `renderChargeRecharge(icon, state, cfg, stateWork)`, and `renderIdle(icon, cfg, stateWork)`. Add `renderChargesBadge(icon, cfg, state)` for the trailing badge. Apply then reads: open bracket, resolve cfg and stateWork, cache _lastState, resolve curves, a three-way `if ... elseif ... else` dispatch of one call each, `if stateWork then self:UpdateGlow(state) end`, renderChargesBadge, close bracket. Deliberately NOT table-driven — the branch predicate is 'which duration handle is non-nil', and an if/elseif states that far more clearly than a dispatch table would.

**Must not change.** Secret-value discipline throughout: the alpha from EvaluateRemainingDuration goes to SetAlphaFromBoolean(true, alpha, 0) rather than SetAlpha when available, the charges badge renders via SetFormattedText (the C-side path that accepts secrets), and the cooldown handle is passed to SetCooldownFromDurationObject rather than read from Lua. The stateWork gate is a real cost control — it exists so a cooldown-ticking icon does not pay four LibCustomGlow stop calls per apply — and each of its four sub-gates guards a different subset; folding them into one wrapper around a whole branch would change what runs. force=true must keep meaning 'config changed, re-render even though the state table is identical'. The charges badge gate is truthiness on `c`, deliberately not `c > 0`, so it works for plain numbers, secret numbers and nil alike.

**Coverage.** Strong: tests/test_icongrid_render.lua, tests/test_icongrid_apply.lua, tests/test_icongrid_curves.lua and tests/test_cooldowns.lua between them cover all three branches, the stateWork gate and the charges badge.

---

### `add-spell StaticPopup OnAccept handler (lizard: OnAccept@360-423)` — CCN 25 → target 7

`settings/Spells.lua:360-423` · pattern `guard-stack` · risk **medium**

**What it does.** Handles the Add-spell dialog's accept: validates the typed input to a spellID, applies the Cooldown Manager gate only when the user is editing their own live class+spec, then either re-enables an existing list entry or appends a new one.

**Where the branches come from.** Written inline as a table field, so nothing could be extracted without moving it out. A validation failure arm with a nested `NS.Util and NS.Util.print` guard; a UnitClass availability branch; a five-term `editorIsActiveSpec` conjunction; a three-level nest for the cmSet gate (cmSet present, id absent from it, print available) with a `resolvedName or getSpellName(id) or tostring(id)` fallback chain; two separate `elseif NS.State and NS.State.debug` arms; and the list loop with its early return.

**Fix.** Hoist the entire body into named file-locals declared above the popup table, leaving OnAccept as a six-line orchestrator. `local function notify(msg)` collapses the thrice-repeated `if NS.Util and NS.Util.print then ... end`. `local function playerClassFile()` owns the UnitClass branch. `local function editorIsActiveSpec()` owns the five-term conjunction (CCN 6). `local function cooldownManagerRejects(id, resolvedName)` owns the cmSet gate, its name fallback chain, its rejection message and its debug-else arm, returning true to reject (CCN 6). `local function addOrEnable(id)` owns ensureActiveList, the re-enable loop and the append (CCN 5). OnAccept becomes: read text, validate, `if not id then notify(...) return end`, `if editorIsActiveSpec() and cooldownManagerRejects(id, resolvedName) then return end` with the non-active-spec debug line inside editorIsActiveSpec's else path, then addOrEnable(id).

**Must not change.** The class/spec scoping is the bug fix this code exists for and is easy to invert: C_CooldownViewer has no class/spec parameter — it answers for the LOGGED-IN player's ACTIVE spec — so the gate must be DROPPED entirely whenever the editor's selected pair differs from the player's live pair, or a Mage editing a Hunter list can add nothing. When cmSet is unavailable the code must fall through leniently (add the spell), never reject. The lazy-create-on-first-add path matters: a spec the user has never customized must gain a fresh list rather than failing silently on a nil GetSpellList. Re-adding an existing spell re-enables it in place rather than duplicating.

**Coverage.** NONE — tests/test_settings_spells.lua covers only the dropdown selection seeding. Needs a characterization test for the same-spec gate, the cross-spec bypass, the unavailable-API leniency and the re-enable-vs-append paths before refactoring.

---

### `UnitLabel:Apply (lizard: UnitLabel@70-123)` — CCN 24 → target 6

`modules/UnitLabel.lua:70-123` · pattern `field-defaulting` · risk **low**

**What it does.** Resolves and applies a unit's text label — per-unit text, link-resolved appearance and show flag, and position anchored to the chosen attach frame while the holder is reparented to the unit's icon grid so visibility follows the grid rather than the cast bar.

**Where the branches come from.** Almost the entire CCN is one long field-defaulting chain — roughly fifteen `x or default` reads across text, font, size, flags, justifyH, justifyV, rotation, attach, point, relPoint, offsetX and offsetY — plus an LSM availability guard, an LSM-result fallback, a colour presence check, a SetRotation capability guard, a `gridModule and ... or nil` chain, an anchorFrame branch, and a final three-term SetShown conjunction.

**Fix.** The canonical defaults-table case. Add a module-level `local STYLE_DEFAULTS = { font = "Friz Quadrata TT", size = 14, justifyH = "CENTER", justifyV = "MIDDLE", rotation = 0, attach = "castbar", point = "BOTTOM", relPoint = "TOP", offsetX = 0, offsetY = 0 }` and a file-local `local function sv(style, key) local v = style[key]; if v == nil then return STYLE_DEFAULTS[key] end; return v end` (CCN 2, no allocation) — every `style.x or default` in the body becomes `sv(style, "x")`, removing about ten branches in one move. Then three sub-builders: `applyLabelFont(fs, style)` (LSM fetch with its two guards, SetFont, the FLAG_MAP lookup which keeps its own `or "OUTLINE"`), `applyLabelColor(fs, style)` (the presence check and the Util.Unpack read), and `applyLabelPlacement(f, unit, style)` (attach frame, grid lookup, reparent, SetPoint). Apply becomes: EnsureFrame, SetText, three calls, the enabled read and the final SetShown.

**Must not change.** The parent/anchor split is the whole design and is easy to lose in an extraction: the frame is REPARENTED to the icon grid (so it inherits General visibility) but SetPoint'd against the attach frame (so position tracks the cast bar or whatever was chosen) — parenting to the anchor instead would make the label cast-gated. The grid is only a fallback-to-anchor when the grid module is not up yet. Colour must be read through NS.Util.Unpack, not by index — a positional read finds nil on every channel and renders the fallback gold silently, in game only. Visibility follows the link-resolved show (a linked focus mirrors target) while TEXT stays per-unit; the final three-term conjunction encodes that and must keep all three terms. Rotation is degrees-to-radians and only applied when SetRotation exists.

**Coverage.** tests/test_unitlabel.lua, tests/test_unitlabel_apply.lua and tests/test_color_shape.lua cover the defaults, the link resolution, the parenting and the keyed-colour read.

---

### `IconGrid:BuildActiveList (lizard: IconGrid@294-358)` — CCN 23 → target 8

`modules/IconGrid.lua:294-358` · pattern `filter-loop-with-duplicated-predicate` · risk **low**

**What it does.** Rebuilds a unit's icon list from the profile's spell list for the active class+spec — dropping disabled entries, duplicate spellIDs, and spells the player cannot actually see in their own spellbook — then acquires, textures and seeds a button for each survivor.

**Where the branches come from.** Four stacked guards before the loop (db/profile, spec key pair, GetSpellList). Then the eligibility predicate `entry and entry.enabled ~= false and entry.spellID` is written out TWICE — once in the duplicate-detection `if` and once in the `elseif` — costing six branches for one concept. Inside: a debug branch, a two-term name/available check, a three-term `tex ~= nil and issecretvalue and issecretvalue(tex)` secret probe, and a `tex and not texSecret` gate.

**Fix.** Four extractions, the first of which is the big win. `local function eligibleSpellID(entry)` returns `entry.spellID` when the entry is non-nil, not disabled and has an ID — called once at the top of the loop body, replacing both copies of the triple-conjunction and turning the if/elseif into a single `if not id then` / `elseif seen[id] then` / `else` ladder (removes 4 CCN). `local function isRenderable(spellID)` for the GetSpellInfo-and-IsSpellAvailable pair. `local function applySpellTexture(btn, spellID)` for the secret-texture probe and its skip. `local function seedIcon(self, inst, spellID)` for acquire, texture, ApplyTextConfig, the initial synthetic Apply and the ordered insert. BuildActiveList keeps the guards, the seen table and a flat loop.

**Must not change.** The duplicate rule is a correctness guard, not a nicety: pool.active must stay strictly 1:1 with spellID or the first widget is orphaned and silently stops receiving SPELL_STATE while remaining visible — so the SKIP (not overwrite) semantics and its debug line must survive. The secret-texture skip must leave the icon blank rather than let SetTexture reject and abort the rest of the rebuild. The synthetic `{ ready = true, start = 0, duration = 0 }` seed with force=true is what makes a pooled button repaint when its _lastState happens to match — keep it a per-icon literal rather than hoisting it to a shared constant, since Apply retains the table on _lastState.

**Coverage.** tests/test_icongrid_buildlist.lua covers the filtering, the duplicate skip and the availability gate.

---

### `Castbar:ApplyState (lizard: Castbar@726-780)` — CCN 22 → target 9

`modules/Castbar.lua:726-780` · pattern `options-builder` · risk **medium**

**What it does.** Applies the secret-bool-driven cast bar visuals — alpha-switches the stacked interruptible/uninterruptible bg, bar and border widgets and sets the spell-name colour, all via C_CurveUtil.EvaluateColorValueFromBoolean so the possibly-secret notInterruptible flag is never touched from Lua.

**Where the branches come from.** A frame guard; two `x and 1 or 0` border-show coercions; then two full render branches (preview/no-cast and active cast) that never interact; and inside them nine `or`-defaulted colour reads — `n[1] or 1` style, four channels per colour table, plus two `or { 1, 1, 1, 1 }` table-literal fallbacks that allocate on every call.

**Fix.** Hot-adjacent (fires on every cast start/stop and interruptibility flip, and once per Reskin), so keep it allocation-free. Add a module-level `local WHITE = { 1, 1, 1, 1 }` and a file-local `local function rgba(c) c = c or WHITE; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end` — four return values, no table, replaces every per-call `{ 1, 1, 1, 1 }` literal and every indexed `or 1`. Then split the two render branches into file-locals: `applyPreviewVisuals(frame, intCfg, intBorderShow)` and `applyLiveVisuals(frame, nint, intCfg, unintCfg, intBorderShow, unintBorderShow)`, the latter unpacking `local ur, ug, ub, ua = rgba(unintCfg.nameTextColor)` and `local ir, ig, ib, ia = rgba(intCfg.nameTextColor)` so the four EvaluateColorValueFromBoolean calls carry no `or`s at all. ApplyState becomes: frame guard, cfg + stateConfig resolution, the two border-show coercions, and a two-way dispatch on `inst.current`.

**Must not change.** Nothing may bind a curve result to a local or do arithmetic on it — every EvaluateColorValueFromBoolean call must feed straight into the Blizzard C method (SetAlpha / SetTextColor). The border-show toggle must stay FOLDED INTO the curve parameters (0 in the relevant slot) and never be multiplied against the result afterwards; multiplying a secret errors in combat. The argument order of each curve pair is the visual polarity — (nint, 0, 1) and (nint, 1, 0) are opposite sides and are trivially easy to transpose during a mechanical extraction. Only observable in game against a real uninterruptible cast.

**Coverage.** tests/test_castbar_frame.lua and tests/test_castbar.lua drive ApplyState through the mock curve evaluator.

---

### `Spells:RefreshRows (lizard: Spells@854-920)` — CCN 22 → target 7

`settings/Spells.lua:854-920` · pattern `panel-rebuild-builder` · risk **low**

**What it does.** Rebuilds the whole spell-editor panel: bails when hidden or already scheduled, degrades to a plain label when AceGUI is missing, releases the previous widget tree, defaults the class/spec selection, then builds the header, the scroll container and one row per list entry.

**Where the branches come from.** Three early guards; the AceGUI-missing arm with a nested lazy `if not fallbackLabel` construction and its own flag reset; a selection-defaulting cascade with an outer two-term condition, an inner if/else on the player's own class, and a following `if selectedClass and not selectedSpec`; the PanelHelpers two-term guard; and the empty-list versus row-loop branch with a per-row `if row` check.

**Fix.** Four extractions along the natural seams. `local function showAceGUIMissing()` owns the lazy fallback label and its display (CCN 2). `local function ensureSelection(classes)` owns the whole class/spec defaulting cascade (CCN 6) — this is the piece that already has test coverage, so isolating it is also a testability win. `local function buildScrollContainer(AceGUI)` owns the create, the four anchor calls and the always-show-scrollbar patch, returning the container (CCN 3). `local function fillRows(AceGUI, list)` owns the empty-list label versus the row loop (CCN 5). RefreshRows becomes: three guards, the AceGUI resolution with `if not AceGUI then rebuildScheduled = false; showAceGUIMissing(); return end`, releaseAceGUITree, ensureSelection, buildSpellsHeader, buildScrollContainer, fillRows, and the flag reset.

**Must not change.** The rebuildScheduled flag must be cleared on EVERY exit including the AceGUI-missing one, or the panel silently never refreshes again for the rest of the session. releaseAceGUITree must stay ahead of any new widget creation or the AceGUI pool leaks. The scrollbar patch is deliberately applied unconditionally so this panel's right gutter matches the schema-driven panels regardless of row count, and it is restored on widget release so other addons' pools stay clean — do not make it conditional on row count. The selection cascade must keep preferring the player's own class when the defaults contain it, falling back to the first sorted class otherwise.

**Coverage.** tests/test_settings_spells.lua covers the selection cascade in four tests (own class+spec seeding, spec-change tracking, class fallback, Blizzard spec ordering); tests/test_options_panel.lua touches the panel's footer wiring. The container and row-fill paths are uncovered.

---

### `Database:MigrateSpecKeys (lizard: Database@583-625)` — CCN 20 → target 8

`core/Database.lua:583-625` · pattern `schema-migration-chain` · risk **low**

**What it does.** Rekeys profile.spells[CLASS] from localized spec-name tokens to numeric spec IDs (issue #8 — non-English clients never matched the shipped English keys). Shape-driven on the key type, collects before mutating, and leaves unresolvable or colliding keys in place rather than dropping user data.

**Where the branches come from.** Three stacked guards (`db and db.profile`, `type(spells) ~= "table"`, `Util and Util.ResolveSpecID`); three levels of nesting (pairs over classes, pairs to collect, ipairs to apply); a three-way if/elseif/else on resolve-failure / collision / success; and the same `if NS.State and NS.State.debug then NS.Debug(...) end` guard repeated three times, once per branch.

**Fix.** Three extractions. (a) `local function migrateDebug(fmt, ...)` collapsing the thrice-repeated debug guard to one place — this alone removes 3 CCN. (b) `local function collectStringKeys(bySpec)` returning the { key, list } array (the mutate-while-walking guard), CCN 3. (c) `local function rekeyOne(bySpec, entry, classFile)` holding the resolve call and the whole three-way outcome with its debug lines, CCN 4. MigrateSpecKeys becomes: three guards, `for classFile, bySpec in pairs(spells) do if type(bySpec) == "table" then for _, e in ipairs(collectStringKeys(bySpec)) do rekeyOne(bySpec, e, classFile) end end end`.

**Must not change.** The collect-then-mutate split must survive — mutating a table while pairs() walks it is undefined in Lua 5.1 and this is the function that documents that. The data-safety rules are load-bearing: an unresolvable key is LEFT IN PLACE, and an incoming key never overwrites an existing numeric one. Idempotence on re-run, and the fact that it runs unconditionally on every profile swap (spells are per-profile, the schema version is per-account) must not become version-gated.

**Coverage.** tests/test_database.lua and tests/test_schema.lua.

---

### `Compat.DebugInterrupt (lizard: Compat.DebugInterrupt@371-455)` — CCN 19 → target 6

`core/Compat.lua:371-455` · pattern `debug-dump-builder` · risk **low**

**What it does.** Slash-driven diagnostic that dumps a unit's cast/channel API return positions with type + secret-taint annotations, then reports what the addon's visibility and glow logic decided. Every value is funnelled through a local safeRender so that secret-tainted strings never reach tostring/format.

**Where the branches come from.** Two nested closures (safeRender with a six-branch type ladder plus two issecretvalue guards, describe with an and/or secret probe); two near-identical UnitCastingInfo / UnitChannelInfo blocks each with an if/else on whether a cast is in progress; a trailing five-term `or` defaulting chain for profile/visibility/icons.

**Fix.** Hoist both closures to file-locals (neither captures anything but `out`, which becomes a parameter). Replace safeRender's type ladder with a module-level constant `local RENDER_BY_TYPE = { string = function(v) return ("%q"):format(v) end, number = tostring, boolean = tostring, ["nil"] = function() return "nil" end }` and a single lookup with a `"<"..t..">"` fallback. Collapse the two API dump blocks into one `dumpPositions(out, title, fieldNames, ...)` driven by two module-level constant lists `CASTING_FIELDS` and `CHANNEL_FIELDS` (the field names are the only difference). Extract `dumpVisibilityGate(out, unit)` for the trailing profile/icons block. DebugInterrupt itself becomes: existence guard, header line, two dumpPositions calls, the IsHostileUnitCasting line, dumpVisibilityGate.

**Must not change.** The secret-taint discipline is the entire point of this function: no value from a Unit* API may reach tostring/format/concat before passing the issecretvalue check, and the vararg path in dumpPositions must not concatenate its arguments. The exact printed line format (column widths in the %-20s/%-8s/%-5s describe line, and the 1..9 / 1..8 position numbering) is what makes the dump diffable against a user's paste — preserve it verbatim. Only verifiable in game, in combat, against a guarded cast.

**Coverage.** NONE — tests/test_slash_style.lua matches the string only to pin the slash verb wiring, and never invokes the function. Needs a characterization test (a fake unit with a planted secret value) before refactoring.

---

### `NS:OpenSettings (lizard: NS@733-771)` — CCN 19 → target 6

`core/KickCD.lua:733-771` · pattern `guard-stack` · risk **medium**

**What it does.** Opens the addon's Settings category, refusing in combat (Blizzard's category switch is protected and would taint the dropdown) and deferring with a bounded retry when the Settings layer has not registered yet — a /kcd config immediately after login can race the PLAYER_LOGIN-deferred RegisterPanel.

**Where the branches come from.** An `or` chain for combat detection across two sources; an `or` chain for the localized notice string plus a `NS.GRAY or ""` colour default; then three nesting levels — `if Settings and Settings.OpenToCategory` wrapping `if main and main.GetID` wrapping a debug branch, followed by the retry arm with a three-term `and` condition of its own.

**Fix.** Four file-locals, each a genuine unit. `local function inCombat(self)` — the two-source check. `local function combatNotice(self)` — the localized-string `or` chain plus the GRAY wrap, returning the finished message. `local function openRegisteredPanel(self)` — resolves main, clears _openRetries, logs, calls Settings.OpenToCategory and expandMainCategory, returns true when it opened. `local function scheduleOpenRetry(self, input)` — bumps and bounds _openRetries, prints the loading notice, arms C_Timer.After, returns true when a retry was armed. OpenSettings reads: `if inCombat(self) then self._openRetries = nil; p(self, combatNotice(self)); return end`, then `if Settings and Settings.OpenToCategory then if openRegisteredPanel(self) then return end; if scheduleOpenRetry(self, input) then return end; self._openRetries = nil end`, then the final fallback print.

**Must not change.** The _openRetries lifecycle is subtle and entirely in-game: it is cleared on the combat refusal, cleared on a successful open, incremented per deferral, and cleared once when the bound is exhausted — so a later successful open starts from zero again. Getting the clear points wrong produces an addon that permanently refuses to open its own panel after a few racy logins. The combat gate must stay ahead of everything else (it is the taint guard), and the retry must remain bounded by OPEN_SETTINGS_MAX_RETRIES.

**Coverage.** NONE — no test file references OpenSettings; tests/test_slash.lua covers verb dispatch only. Needs a characterization test for the combat refusal, the retry counter lifecycle, and the exhausted-retries fallback before refactoring.

---

### `Cooldowns:PollSpell (lizard: Cooldowns@93-199)` — CCN 19 → target 7

`modules/Cooldowns.lua:93-199` · pattern `guard-stack` · risk **medium**

**What it does.** Polls one spellID and returns its freshly-computed state record (ready, isActive, cdObject, chargeCdObject, charges), or nil when the spell is not actually in the player's spellbook so the grid can hide it. Fully instrumented — the Perf bracket opens above the guards and closes on every one of its four exits.

**Where the branches come from.** Roughly half the CCN is instrumentation: `Perf.on and debugprofilestop()` plus four separate `if __t0 then Perf.Note(...) end` exit closures, eight branches before any logic. The rest: two rejection guards on spellID type and GetSpellInfo, one on IsSpellAvailable, a three-way hasCharges resolution (nil / secret / compare), a two-term chargeCdObject condition, and a three-term `ready` conjunction.

**Fix.** HOT PATH — runs per watched spell per refresh; the proposal adds no allocation (the single state table is unchanged). Two extractions collapse the instrumentation cost. `local function isPollable(spellID)` holds all three rejection guards (type check, GetSpellInfo, IsSpellAvailable) and returns a boolean. `local function buildSpellState(spellID)` holds everything from GetSpellCooldown down to the returned table, itself using two tiny file-locals: `local function chargesAvailable(cur)` for the nil/secret/compare three-way, and `local function rechargeHandle(cur, isActive)` for the charge-recharge condition. PollSpell becomes exactly two exits — `local __t0 = Perf.on and debugprofilestop(); if not isPollable(spellID) then if __t0 then Perf.Note("pollSpell", debugprofilestop() - __t0) end; return nil end; local state = buildSpellState(spellID); if __t0 then Perf.Note("pollSpell", debugprofilestop() - __t0) end; return state` — which removes 6 CCN outright while keeping the bracket open above the guards and closed on every exit.

**Must not change.** The Perf bracket contract, which is documented at length in the function and pinned by tests: the bracket must OPEN ABOVE the guards (GetSpellInfo and IsSpellAvailable are themselves API calls and part of the poll's real cost) and every exit must close it, or the bucket under-counts exactly the way it did before this was fixed (spellPoll totalled 125.02 ms with 73.9 ms attributed to nothing). Re-run tests/test_perfsetup.lua and confirm the measured total is unchanged, not merely that it passes. Also secret-critical: the secret-tainted charge count must keep failing OPEN (assume charges available) rather than erroring, and start/duration from GetSpellCooldown must stay discarded.

**Coverage.** tests/test_cooldowns.lua covers the poll outcomes and the rejection paths; tests/test_perfsetup.lua pins the bracket contract.

---

### `buildRow` — CCN 19 → target 5

`settings/Spells.lua:506-673` · pattern `options-builder` · risk **low**

**What it does.** Builds one AceGUI row for the spell editor: spell icon with tooltip, name label with a hooked tooltip, enable checkbox, known/not-known status glyph, a fixed-width spacer, a category dropdown, and the move-up / move-down / remove buttons.

**Where the branches come from.** Eight independent widgets in one body, each contributing its own guard: `if icon.image and icon.image.SetDesaturated` (twice — once at build, once in the checkbox callback), `if label.frame and label.frame.HookScript`, `if dd.frame and dd.frame.HookScript`, a `known and ... or false` coercion plus two `known and A or B` selections, index-bound checks inside all three button callbacks, and two debug-guarded log lines. Note lizard reports the span as 506-797 because it folds the following file-local helpers in through the nested closures; the real function ends at 673.

**Fix.** The N-independent-sub-parts split, one file-local per widget, each returning its widget. `rowSpellIcon(AceGUI, entry)` (returns the icon plus the two shared tooltip closures so the label can reuse them), `rowNameLabel(AceGUI, entry, showTooltip, hideTooltip)`, `rowEnableCheck(AceGUI, entry, icon)`, `rowKnownGlyph(AceGUI, entry)`, `rowSpacer(AceGUI, width)`, `rowCategoryDropdown(AceGUI, entry)`, `rowMoveButtons(AceGUI, list, index)` — the up and down buttons are symmetric, so drive both from a module-level `local MOVE_SPECS = { { image = ..., tooltip = ..., delta = -1, atEdge = function(i) return i <= 1 end }, { image = ..., tooltip = ..., delta = 1, atEdge = function(i, n) return i >= n end } }` and one loop — and `rowRemoveButton(AceGUI, list, index)`. Also hoist the per-row CATEGORIES items/order construction to a file-level memo built once, which removes two table allocations per row per refresh. buildRow then creates the SimpleGroup and issues eight AddChild calls.

**Must not change.** AddChild ORDER is the visual column order and must be preserved exactly, spacer included — the spacer is a deliberate layout device because AceGUI's Flow layout has no inter-widget gap. The specific widths are tuned and commented (238 for the label, 22 for the status glyph so its box hugs the 20 px image, 14 for the spacer) and are not arbitrary. The checkbox callback must keep desaturating the icon it captured. The move/remove callbacks close over `index`, which is only valid until the next rebuild — the bounds checks inside them are the guard against a stale click and must survive the loop-driven rewrite. The status glyph is informational and must stay non-gating on enable/disable.

**Coverage.** NONE — no test constructs a row. Needs a characterization test asserting the child order, the widths and the move/remove bounds behavior before refactoring; this is the least-covered function in the set relative to its surface area.

---

### `test body: "every declared bucket is reached by a real bracket" (lizard: (anonymous)@65-111)` — CCN 18 → target 6

`tests/test_perfsetup.lua:65-111` · pattern `guard-stack` · risk **low**

**What it does.** The performance-§3 test: drives each declared Perf bucket through its genuine entry point (a Cooldowns refresh, a real SPELL_STATE message, a cast event, a visibility refresh) rather than calling Perf.Note directly, then asserts every bucket the harness can drive was actually reached.

**Where the branches come from.** A stack of seven near-identical `if obj and obj.Method then pcall(obj.Method, obj, ...) end` availability guards, each worth two branches; a `Cooldowns and Cooldowns.watched or {}` chain with a break-on-first loop; a `P.__buckets and P.__buckets() or {}` chain; a units loop; and the final assertion loop with a two-term condition.

**Fix.** One helper removes most of it: `local function tryCall(obj, method, ...) if obj and obj[method] then return pcall(obj[method], obj, ...) end end` (CCN 3), declared at file scope, replaces all seven guarded pokes with flat one-liners and strips roughly eight branches. Then extract `local function firstWatchedSpell(Cooldowns)` for the break-on-first lookup (CCN 3) and `local function assertBucketsReached(buckets, keys)` for the final loop (CCN 3). The test body becomes a readable script: load, enable the probe, resolve the three modules, six tryCall lines, the SPELL_STATE send, flush timers, read buckets, disable, assert.

**Must not change.** The test's value is that it drives buckets through REAL entry points — replacing any tryCall with a direct Perf.Note call would prove only that Note appends, which is the exact failure mode the comment warns about. The pcall wrapping must survive (several of these entry points legitimately throw headlessly). P.on must be set before and cleared after, and the timer flush must stay ahead of the bucket read. The assertion list must keep naming only the four headlessly-drivable buckets and must not quietly grow to include castTick or cdText, which need a live cast and the ticker.

**Coverage.** This IS a test — it is the coverage for the Perf bracket contract, including Cooldowns:PollSpell's four exits. Refactor it before, and re-run it after, the PollSpell change.

---

### `Database:FoldLegacyUnits (lizard: Database@516-533)` — CCN 16 → target 7

`core/Database.lua:516-533` · pattern `schema-migration-chain` · risk **low**

**What it does.** Shape-driven, idempotent migration that folds a legacy pre-units profile's top-level icons/castbar/anchors tables down into units.target, then defaults units.target.enabled to true.

**Where the branches come from.** A guard stack (`db and db.profile`, then a three-way `p.icons == nil and p.castbar == nil and p.anchors == nil` bail); four `x = x or {}` lazy-create defaults; three `if field ~= nil then move end` blocks; a nested anchors block with two more `~= nil` moves; a final `if t.enabled == nil` default.

**Fix.** Two data tables plus one extracted helper. `local LEGACY_TOPLEVEL = { "icons", "castbar" }` drives a loop replacing the two identical move blocks: `for _, k in ipairs(LEGACY_TOPLEVEL) do if p[k] ~= nil then t[k] = p[k]; p[k] = nil end end`. `local LEGACY_ANCHOR_KEYS = { "icons", "castbar" }` drives an extracted `local function foldAnchors(p, t)` holding the nested anchors sub-merge and its own nil-clear. FoldLegacyUnits then reads: guards, lazy-create units.target, the top-level loop, `if p.anchors ~= nil then foldAnchors(p, t) end`, the enabled default.

**Must not change.** Idempotence and the shape-driven trigger. The function must stay keyed on the PRESENCE of the old top-level tables and never on schemaVersion — AceDB's defaults merge backfills the version and would mask a legacy account as already-current (the KCD-20 backfill trap). The anchors sub-merge must keep copying INTO an existing t.anchors rather than replacing it, and p.anchors must still be cleared exactly once. A second run on an already-folded profile must be a no-op.

**Coverage.** tests/test_database.lua exercises it by name.

---

### `Util.ResolveSpecID` — CCN 16 → target 8

`core/Util.lua:290-322` · pattern `lookup-tier-chain` · risk **low**

**What it does.** Resolves a spec identifier from a number, a numeric string, a localized spec name in the client's language, or the English Const.SPEC token — returning nil rather than guessing. The optional classFile disambiguates the four names shared across classes (Frost, Holy, Protection, Restoration).

**Where the branches come from.** Four early-return guards (number passthrough, non-string/empty reject, tonumber passthrough), then three lookup tiers, each a separate `or` chain: the class-scoped tier tries token/input/folded (2 ors), the Const.SPEC tier one lookup, the global localized tier another token/input/folded chain (2 ors), each followed by its own `if hit then return hit end`.

**Fix.** Keep the guards, extract the three tiers as file-locals so each `or` chain is isolated: `local function resolveByClass(classFile, token, input, folded)` (returns nil when classFile is nil or unknown), `local function resolveByConstToken(token)`, `local function resolveByLocalizedName(token, input, folded)`. The body then ends `return resolveByClass(classFile, token, input, folded) or resolveByConstToken(token) or resolveByLocalizedName(token, input, folded) or nil`. Tier ORDER is the behavior and must be preserved exactly by the order of that expression.

**Must not change.** Tier precedence is the contract: class-scoped first (only tier that can resolve a shared name), then the English Const.SPEC token so an English speaker's input resolves identically on any locale client, then the global localized map. The `false` sentinel in specNameMap marks an ambiguous name with no class hint and must keep being refused (a naive `or` chain that treats false as 'keep looking' would change this — the helper must return nil for a false hit, not fall through to a different answer). ensureSpecNameMaps() must still run before any map read.

**Coverage.** tests/test_util.lua and tests/test_locale.lua both exercise it, including the localized and ambiguous cases.

---

### `Icon:UpdateGlow (lizard: Icon@532-560)` — CCN 16 → target 8

`modules/IconGrid_Render.lua:532-560` · pattern `guard-stack` · risk **low**

**What it does.** Decides glow visibility from the icon's state, its per-slot config and the trigger condition, then starts or stops the glow — and for the target_casting_interruptible trigger hands the glow frame to the C-side alpha mask so uninterruptible casts run the animation invisibly.

**Where the branches come from.** A cfg fallback `or`; a primary/secondary branch selecting three config fields; a `state and state.ready and true or false` coercion; a two-term stop condition; the four-term interruptible-filter conjunction (trigger equality, self.glow, the State method's existence, and its return value); and a final `if self.glow` guard.

**Fix.** HOT — called from Apply on every state change and from RefreshAllGlows once per icon per cast event; both helpers below are allocation-free (multiple returns, no tables). `local function glowConfig(cfg, isPrimary)` returns trigger, kind, color and owns the primary/secondary branch, CCN 2. `local function applyInterruptibleMask(icon, trigger)` owns the four-term conjunction and returns true when the mask took over, CCN 5. UpdateGlow becomes: cfg guard, `local trigger, kind, color = glowConfig(cfg, self._isPrimary)`, the ready coercion, the stop guard, StartGlow, `if applyInterruptibleMask(self, trigger) then return end`, and the final `if self.glow then self.glow:SetAlpha(1) end`.

**Must not change.** The ordering is the behavior: the glow must START for any hostile cast and only then have its alpha masked — the mask is an overlay on a running animation, not an alternative to starting it. So StartGlow must stay ahead of applyInterruptibleMask, and the early return when the mask takes over must not also skip StopGlow semantics. The `state and state.ready and true or false` normalization matters because state.ready can be nil and the trigger predicates compare against a real boolean.

**Coverage.** tests/test_icongrid_apply.lua, tests/test_icongrid_curve_link.lua and tests/test_icongrid_visibility.lua all drive UpdateGlow, including the primary/secondary split.

---

### `getCooldownManagerSpellSet` — CCN 16 → target 7

`settings/Spells.lua:254-290` · pattern `guard-stack` · risk **low**

**What it does.** Builds and memoizes the set of spellIDs the Blizzard Cooldown Manager tracks for the logged-in player's active spec, walking every C_CooldownViewer category. Uses a sentinel table so an API that returned nothing is not re-walked on every call.

**Where the branches come from.** Two cache guards (sentinel then hit); a C_CooldownViewer presence guard; a four-term availability conjunction over getCategorySet, getInfo, Enum and Enum.CooldownViewerCategory; then a double loop where each level carries a pcall plus a type check plus a field check; then the seenAny sentinel decision.

**Fix.** Two extractions. `local function cooldownViewerApi()` returns `getCategorySet, getInfo` or nil, owning the C_CooldownViewer guard and the four-term availability conjunction (CCN 4). `local function collectCategorySpells(getCategorySet, getInfo, category, set)` owns the inner double loop with both pcalls and type checks and returns whether it added anything (CCN 6). getCooldownManagerSpellSet keeps: the two cache guards, `local getCategorySet, getInfo = cooldownViewerApi(); if not getCategorySet then _cmCache = _CM_EMPTY; return nil end`, the category loop ORing the collector's result into seenAny, and the sentinel decision.

**Must not change.** The three-state cache must be preserved exactly: nil means not yet computed, _CM_EMPTY means computed-and-empty (do not recompute), a table means a real set. Collapsing empty-to-nil would re-walk every category on every call. Both pcalls are load-bearing — C_CooldownViewer throws on some category values in some client builds — and the invalidation on TRAIT_CONFIG_UPDATED / PLAYER_SPECIALIZATION_CHANGED must keep resetting to nil rather than to the sentinel.

**Coverage.** NONE — no test references it, and the surrounding tests/test_settings_spells.lua covers only selection seeding. Needs a characterization test (a stub C_CooldownViewer, an absent one, and an empty-result one) before refactoring.

---

### `AceDB.New mock (lizard: New@510-530)` — CCN 16 → target 5

`tests/wow_mock.lua:510-530` · pattern `field-defaulting` · risk **medium**

**What it does.** The LibStub AceDB-3.0 mock's New: reads the named SavedVariables global out of the sandbox when a suite has staged one, merges the declared defaults into it in place for the profile/global/char sections, and attaches the profile-management no-ops the addon calls.

**Where the branches come from.** A `name and mocks[name] or nil` chain; a type check; then six `or` defaults in three symmetric pairs — `saved and saved.profile or {}` against `defaults and defaults.profile or {}`, repeated identically for global and char — which alone is twelve branches for one idea; then seven attached function definitions.

**Fix.** Data-driven, two moves. Add a file-local `local function section(t, key) return t and t[key] or {} end` (CCN 3) and a module-level `local DB_SECTIONS = { "profile", "global", "char" }`, then build with one loop: `for _, k in ipairs(DB_SECTIONS) do db[k] = copyDefaults(section(saved, k), section(defaults, k)) end` — this removes all twelve `or` branches. Second, hoist the attached methods into a module-level `local DB_STUBS = { RegisterCallback = function() end, GetCurrentProfile = function() return "Default" end, GetProfiles = function(_, t) t = t or {}; t[1] = "Default"; return t end, SetProfile = function() end, ResetProfile = function() end, CopyProfile = function() end, DeleteProfile = function() end }` copied in with a second short loop. New becomes: resolve saved, the type check, the keys table, the section loop, the stub loop, return.

**Must not change.** Argument order into copyDefaults is the contract and must not flip: the STAGED saved section is `dst` and the declared defaults are `src`, so defaults merge into the staged account in place and only fill absent keys. Reverse it and the pre-migration account staging that tests/test_database.lua and tests/test_schema.lua depend on stops working — silently, because the tests would then be migrating a defaults-shaped table and passing for the wrong reason. `section()` must keep returning a fresh `{}` for a missing section (matching today's `saved and saved.profile or {}`), never a shared table, or two sections would alias. GetProfiles must stay a real implementation, not a no-op, since it fills the caller's table.

**Coverage.** Indirect but real: tests/test_database.lua and tests/test_schema.lua stage pre-migration SavedVariables through this path and are the regression net for it. tests/test_vendor_sync.lua and tests/test_coresetup.lua also construct the db.

---
