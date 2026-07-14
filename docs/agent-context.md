# CLAUDE.md — working notes for future sessions

Guidance for Claude Code (and other LLM-assisted editors) working on **Ka0s KickCD**. Read this first before touching code.

## What this addon is

A WoW addon that tracks the player's interrupt and CC cooldowns and surfaces them on a movable, persistently-visible icon grid, with a sibling target cast bar driven from the same drag lock and the same addon-wide visibility mode (`always` / `in_combat` / `target_casting` / `target_casting_interruptible`). Designed as an interrupt rotation helper, not a generic raid-frame replacement. Target client: WoW 12.0.7 (Midnight). English only. Ace3 throughout.

The settings panel is a five-tab Blizzard subcategory (General / Icons / Cast bar / Spells / Profiles) with full slash-command parity (`/kcd list|get|set|reset|resetall|resetposition|spells|debug`). Every schema-driven option is automatically wired into UI widget, slash CLI, and Defaults reset — see [docs/settings-panel.md](settings-panel.md).

Display name in the addon list and Settings panel: `Ka0s KickCD` (the colored `## Title` field in `KickCD.toc`). The folder, addon ID, slash commands, saved-variable namespace (`KickCDDB`), and global frame names all stay unprefixed `KickCD` for ergonomics.

User-facing reference: [README.md](../README.md). Design overview + invariants: [ARCHITECTURE.md](ARCHITECTURE.md).

## Hard rules

- **Never auto-stage, auto-commit, or auto-push.** The user controls when changes get staged, committed, and pushed. After editing files, leave the changes in the working tree — don't run `git add` / `git stage` / `git restore --staged` / `git checkout -- <file>` to manipulate the index or discard working-tree edits. Only run `git add` / `git commit` / `git push` when the user explicitly asks ("stage this", "commit this", "commit all changes", "push", etc.). This holds even when working in auto mode. If you need to inspect what would change, use read-only commands (`git status`, `git diff`, `git diff --stat`) instead of staging as a probe.
  - **`/wow-addon:commit` is an explicit ask.** A user-issued `/wow-addon:commit` invocation is a manual assertion to stage and commit; the skill's own y/n/edit confirmation continues that authorization. No additional out-of-band "yes please commit" instruction is required for that flow. The carve-out is scoped to `/wow-addon:commit` only — every other skill (including `/wow-addon:diff`, `/wow-addon:sync-docs`, `/wow-addon:new-addon`) is read-only or edits the working tree, never the index, so the no-auto-commit rule still applies inside them. Slash commands the user types unprompted (or commit-adjacent skills they invoke) count; commit-adjacent reasoning Claude does on its own does not.
- **Never bump the version without explicit instruction.** Don't edit `KickCD.toc`'s `## Version`, `NS.VERSION` in `core/KickCD.lua`, the README badge, or the README "Version History" section as part of any other task. Version bumps are a release-time decision the user makes deliberately. If a task seems to imply a bump (new feature, breaking change), call it out in the reply and let the user decide. Synchronising version strings *to a value the user already chose* (e.g. "make all the version strings say 1.0.1") is fine — that's not a bump.
- **12.0 secret values.** Never compare, do arithmetic on, format, or `tostring` a value that might be secret. `C_Spell.GetSpellCooldown`'s timing returns and `UnitCastingInfo`'s `name` / `texture` / `notInterruptible` / `spellID` all come back secret in combat for protected interrupts. Pass them straight to Blizzard C methods (`Cooldown:SetCooldownFromDurationObject`, `FontString:SetFormattedText`, `Texture:SetTexture`, `Frame:SetAlphaFromBoolean`, `C_CurveUtil.EvaluateColorValueFromBoolean`); never bind to a Lua local. Full pattern catalogue and the anti-patterns we've already burned on are in [docs/midnight-quirks.md](midnight-quirks.md).
- **Visibility / glow / interruptibility decisions** that depend on `notInterruptible` MUST go through the two-step gate: `NS.State.IsHostileUnitCasting` for show + `NS.State.ApplyInterruptibleAlpha` for filter. Both live in `core/State.lua`, **not** `core/Compat.lua` — these are addon visibility decisions, not API normalisation. Lua-side comparison of the secret bool errors in combat. See [docs/midnight-quirks.md](midnight-quirks.md#cast-interruptibility-unitcastinginfo--unitchannelinfo).
- **Closed message bus.** The five AceEvent messages (`Ka0s_KickCD_SPELL_STATE`, `Ka0s_KickCD_CONFIG_CHANGED`, `Ka0s_KickCD_PROFILE_CHANGED`, `Ka0s_KickCD_GRID_LAYOUT`, `Ka0s_KickCD_COMBAT_STATE`) are the only inter-module communication channel. Each receiver registers on its own AceEvent target (the Spells panel gets one via `NS.NewBusTarget()`). Modules don't call each other directly across boundaries. Adding a new message requires updating the source emitter, every consumer, and [docs/message-bus.md](message-bus.md). Don't invent new messages without a reason.
- **Compat / State / Constants split.** `core/Compat.lua` is API normalisation only (spell-info shims, cast-info record building). `core/State.lua` owns shared mutable state and visibility helpers. `core/Constants.lua` owns shared magic numbers under `NS.Const`. Don't add visibility decisions or shared state to Compat. See [docs/conventions.md](conventions.md#compat--state--constants-split).
- **`NS.Settings.Schema` is the single source of truth for every option.** Adding a setting = one row in the schema; UI widget, `/kcd get|set|list` coverage, the per-panel Defaults reset, and the General → "Reset all settings" reset are wired automatically. Don't add a parallel mutator for a field that already has a schema row. See [docs/settings-panel.md](settings-panel.md).
- **Never `setmetatable(frame, t)` on a Blizzard widget.** Frame methods live on the C-side metatable; replacing it nils them. Use `Mixin(frame, t)` instead. See [docs/midnight-quirks.md](midnight-quirks.md#frame-mixin-pattern).
- **Chat output goes through `Util.print`.** Never call the global `print` directly and never write your own `|cff…KickCD|r:` prefix. `Util.print` prepends the single shared `NS.PREFIX` chat tag (a cyan `[KCD]` banner, defined once in `core/Constants.lua`); passing your own prefix produces a double banner. The help printers in `core/KickCD.lua` are the only callers that color anything else.
- **Debug logging is not chat.** Debug is a session-only flag `NS.State.debug` (never persisted); the `NS.Debug(tag, …)` sink routes to the on-screen console in `modules/DebugLog.lua`, not to chat via `Util.print`.

## Module publishing pattern

Every module in this addon uses the same idiom, built on the private addon namespace (the WoW addon vararg — there is no `_G.KickCD` global table):

```lua
local addonName, NS = ...
NS.Foo = NS.Foo or {}
local F = NS.Foo
```

- Every source file starts with `local addonName, NS = ...`; `NS` is the shared private table WoW passes to every file in the addon.
- Never overwrite an existing `NS.Foo` without `or {}` — another file may have reached it first.
- Expose the public API on `F` (or `NS.Foo` directly). Keep helpers `local` to the file.

There is no `_G.KickCD` and no `KickCD = KickCD or {}` bootstrap. `core/KickCD.lua` calls `LibStub("AceAddon-3.0"):NewAddon(NS, "KickCD", …)` and sets `NS.addon = addon` — no `_G.KickCD = addon` rebind; later files get `NS` from their own `local addonName, NS = ...` header, not `GetAddon`. `core/Compat.lua` just hangs `NS.Compat` on the shared `NS` at TOC load time. The addon id `"KickCD"`, `KickCDDB`, and the global frame names (`KickCDIconGrid`, `KickCDCastbar`, `KickCDDebugWindow`) intentionally stay literally `KickCD`.

## Working environment

- **Dual-path WSL.** `/home/tushar/GIT/KickCD/` and `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD/` are the same repo via symlink. Either path works for git and file tools.
- **`.gitattributes`** enforces `* text=auto eol=crlf` — every text file lives as CRLF in the working tree and the stored blob, no `core.autocrlf` flip-flopping per developer. New files added by an agent should match.
- **Tests.** A headless Lua unit harness (`lua tests/run.lua`, exits non-zero on failure) plus `luacheck .` cover pure logic, the message bus, and the `OnInitialize → OnEnable` lifecycle — see [docs/testing.md](testing.md). The harness can't render frames or model taint, so end-to-end scenarios (cold install, visibility modes, lock/drag, cast bar auto-size, spec/talent/pet rebuilds, secret-value safety, profiles) stay manual and in-game in [docs/smoke-tests.md](smoke-tests.md).
- **Default-spell coverage source.** `defaults/Spells.lua` is synced from Baratus's "Class Info - Wow" Google Sheet, Midnight tab. Column reference and refresh procedure live in [docs/scope.md](scope.md#default-spell-coverage).

## Response style for this repo

- **Terse.** State the change, not the deliberation.
- **Use `file_path:line_number` references** when pointing at code.
- **Don't write summaries** the user can read from the diff.
- **Ship functional, defer polish.** When core functionality lands, move on — don't stop to polish UX mid-milestone. Revisit polish later as a dedicated pass.
- **No comments explaining *what* well-named code does.** Only add a comment when the *why* is non-obvious (subtle invariant, workaround for a specific Blizzard quirk, hidden constraint).
- **Don't create docs or planning files unless asked.**

## Doc index

Topic-specific detail lives in `docs/`. Read on demand — these are not auto-loaded.

| Topic | File | When to read |
|-------|------|--------------|
| Scope, defaults source, spell-list lifecycle | [docs/scope.md](scope.md) | Evaluating a feature request; understanding the seed/recovery flow. |
| Per-file responsibility map + TOC load order + AceAddon lifecycle | [docs/module-map.md](module-map.md) | "Which file owns X?" / "When does Y run?" |
| Game event → state → message → render pipeline; visibility gate; lock + anchor | [docs/data-flow.md](data-flow.md) | Touching event handling, settings writes, or drag/anchor logic. |
| Closed message bus (the five `KickCD_*` messages with sender/listener/payload) | [docs/message-bus.md](message-bus.md) | Adding or modifying anything that sends or listens to a message. |
| `KickCDDB` shape, `DEFAULT_PROFILE`, profile lifecycle | [docs/saved-variables.md](saved-variables.md) | Adding persistent state. |
| `Compat.*` API shim catalogue + `State.*` visibility helpers | [docs/compat-layer.md](compat-layer.md) | Adding or wrapping a Blizzard spell/cast API; reasoning about taint. |
| 12.0 secret values, plain-after-flip invariant, frame mixin, other Midnight gotchas | [docs/midnight-quirks.md](midnight-quirks.md) | **Required reading** before touching cooldown, cast, or visibility code. |
| Icon grid layout model (anchor + grow + dimensions) | [docs/icon-grid.md](icon-grid.md) | Touching `modules/IconGrid.lua` layout. |
| Cast bar — secret-value-gated, dual stacked widgets, anti-patterns | [docs/castbar.md](castbar.md) | Touching `modules/Castbar.lua`. |
| Schema-driven canvas-layout settings panel; widget primitives; validation | [docs/settings-panel.md](settings-panel.md) | Adding an option, a tab, or a custom-body widget. |
| Slash dispatch tables (`COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS`) | [docs/slash-dispatch.md](slash-dispatch.md) | Adding or modifying a slash subcommand. |
| End-to-end smoke tests (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet, profiles, secret values) | [docs/smoke-tests.md](smoke-tests.md) | Before claiming a non-trivial change works; before tagging a release. |
| Slash-command + debug coverage matrices (what each command produces) | [docs/testing.md](testing.md) | Looking up the exact behavior of a `/kcd …` invocation. |
| Code style, saved-variable boundary, anchor format, `_G.X` vs bare X | [docs/conventions.md](conventions.md) | Style / boundary questions. |
