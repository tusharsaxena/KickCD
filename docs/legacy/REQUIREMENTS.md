# Ka0s KickCD — Requirements

**Version:** 0.1 (draft, awaiting sign-off)
**Author:** Ka0s
**Target client:** WoW: Midnight 12.0.5 (Interface **120005**) — primary and only supported baseline for v0.1
**Scope:** v0.1.0 — first public release

---

## 1. Vision

KickCD is a lightweight, single-folder addon that helps the player make informed interrupt decisions in real time. When the current target is a hostile unit casting an interruptible spell, KickCD shows:

1. A movable **icon grid** of the player's interrupt + cast-stopping CC abilities, with cooldown swipes and a clear "ready vs not ready" visual state.
2. A movable **minimal target castbar** showing cast name, time remaining, and an interruptibility border color.

Defaults are sensible per class and spec; the user can fully customize which spells are tracked, their order, look, and position. All UI is configured through the **Blizzard default Settings panel** (post-10.0 `Settings` API).

---

## 2. Personas

- **PvE-MD** — runs Mythic+ keys, needs to know at a glance which kicks/CCs are off-cooldown for interrupting boss/trash casts.
- **PvP-AR** — plays arena/BGs, uses the same single tracked list (no PvE/PvP split). DR awareness is deferred to a later release — see §10.
- **Alt-RA** — has many alts across classes; expects sane defaults the moment they log in on a new character.

---

## 3. Functional Requirements

### FR-1 — Trigger conditions

KickCD's UI **must show** when **all** of the following are true for the player's current target:

1. `UnitExists("target")` is true.
2. `UnitCanAttack("player","target")` is true (target is hostile).
3. `UnitIsDead("target")` is false.
4. The target is currently casting (`UnitCastingInfo("target")`) **or** channeling (`UnitChannelInfo("target")`) a spell.
5. The cast's `notInterruptible` field is **false** (i.e., the cast can be kicked).

If any condition becomes false, the UI must hide within 100 ms.

### FR-2 — Icon grid

- **FR-2.1** — Layout: one **primary** icon (player's main interrupt) plus N **secondary** icons (player's tracked CCs), arranged horizontally to the right of the primary by default. Layout direction (horizontal/vertical) and primary-icon-position (left/right/top/bottom) are user-configurable.
- **FR-2.2** — Primary icon size is configurable (default 48 px). Secondary icon size is configurable as a percentage of primary (default 70%).
- **FR-2.3** — Each icon shows the spell texture (`C_Spell.GetSpellTexture(spellID)`).
- **FR-2.4** — Each icon has a cooldown swipe (`CooldownFrameTemplate`) tied to `C_Spell.GetSpellCooldown(spellID)`.
- **FR-2.5** — Visual states:
  - **Ready** — full color, full alpha (default 1.0), no swipe.
  - **On cooldown** — red tint (configurable color), reduced alpha (default 0.4), animated cooldown swipe.
  - **Unusable** (out of resource / wrong stance / no target line-of-sight via `C_Spell.IsSpellUsable`) — same as "on cooldown" by default; user can disable this state if they only care about cooldown.
- **FR-2.6** — Optional cooldown text (numeric seconds remaining) rendered on the icon, font and font size configurable. Disabled by default to avoid duplicating OmniCC if the user has it.
- **FR-2.7** — Charges (where applicable, e.g. Mage Counterspell talents): show charge count in a corner badge using `C_Spell.GetSpellCharges(spellID)`.
- **FR-2.8** — When a tracked spell is not in the player's spellbook (e.g., spec-locked), it must be hidden — never grayed out forever.

### FR-3 — Target castbar

- **FR-3.1** — Single horizontal bar showing the spell name, cast icon, and remaining time.
- **FR-3.2** — Bar color reflects interruptibility: configurable "interruptible" color (default Blizzard yellow) and "not interruptible" color (default gray) — though per FR-1, the bar only appears for interruptible casts in v0.1.
- **FR-3.3** — Width, height, font, font size, texture (LibSharedMedia), and border are configurable.
- **FR-3.4** — Channeled casts fill **right-to-left** (counting down), regular casts fill **left-to-right** (filling up). This matches Blizzard convention.
- **FR-3.5** — A spark/marker indicates current cast progress.

### FR-4 — Cooldown + usability tracking

- **FR-4.1** — Cooldown state for every tracked spell must be accurate within 100 ms of the underlying API event (`SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_USABLE`, `SPELL_UPDATE_CHARGES`).
- **FR-4.2** — On `PLAYER_ENTERING_WORLD` and `PLAYER_SPECIALIZATION_CHANGED`, the tracked spell list must refresh and re-bind cooldown handlers.

### FR-5 — Default spell sets per class + spec

- **FR-5.1** — KickCD ships with **one** default interrupt + CC list per class+spec (no separate PvE/PvP variants). Where a spell is useful in only one mode, the default biases toward **PvE** utility (e.g., a stun that works on dungeon mobs but is on DR in arena is included; a PvP-only talent that does nothing in PvE is excluded). Defaults include the primary interrupt plus 3–6 CCs per RESEARCH.md §6.
- **FR-5.2** — Defaults include the player's race-specific cast-stopping ability where applicable (War Stomp for Tauren, Quaking Palm for Pandaren, Bull Rush for Highmountain Tauren, Haymaker for Kul Tiran, Arcane Pulse for Nightborne).
- **FR-5.3** — Defaults are versioned. When a new addon version ships with revised defaults, existing user customizations are preserved; only un-customized profiles auto-upgrade.
- **FR-5.4** — Users who want PvP-specific tracking (or any other variant) achieve it via Ace3 profiles (FR-6.2.5, FR-10.4) — e.g., a "PvP" profile they switch to for arenas. The addon does not automatically swap profiles based on instance type in v0.1.

### FR-6 — Settings panel (Blizzard default UI)

Implemented via the post-10.0 `Settings` API (no AceConfig dropped into a separate window — must live inside Blizzard's settings panel as the user requested).

- **FR-6.1** — Panel registers under `Settings.RegisterAddOnCategory` with the title **"Ka0s KickCD"**.
- **FR-6.2** — Subcategories:
  1. **General** — enable/disable, lock/unlock frame for dragging, reset position, scale slider, global alpha, test-mode toggle (force-show UI for previewing without a target).
  2. **Icons** — primary size, secondary size %, layout direction, gap, cooldown text on/off + font + size, ready/on-cooldown alpha and tint, charges display on/off.
  3. **Castbar** — width, height, font, texture (LibSharedMedia dropdown), border, interruptible/not-interruptible colors, spark on/off.
  4. **Spells** — per-class-spec spell list editor (see FR-7).
  5. **Profiles** — full Ace3 AceDBOptions-3.0 profile management UI: list profiles, **create new** (named), **switch active**, **copy from** another profile, **reset** current, **delete** non-active. Scope toggles: per-character, per-class, per-realm, per-faction, default. Per-character is the initial default.
- **FR-6.3** — `/kickcd` and `/kcd` slash commands open the settings panel.
- **FR-6.4** — All controls update the live UI immediately (no reload-UI required) using `Setting:SetValueChangedCallback`.

### FR-7 — Spell-list editor

The "Spells" subcategory must allow the user to:

- **FR-7.1** — View the current spell list for their **active spec** in priority order (top = primary, rest = secondary).
- **FR-7.2** — **Add** a spell by ID or name (with validation against `C_Spell.GetSpellInfo`).
- **FR-7.3** — **Remove** a spell.
- **FR-7.4** — **Reorder** spells via up/down arrows (drag-and-drop is a stretch goal for v0.2).
- **FR-7.5** — **Toggle** any spell on/off without removing it.
- **FR-7.6** — Set a category per spell — `interrupt`, `stun`, `knockback`, `incapacitate`, `silence`, `racial`, `other` — used for icon grouping/coloring (visual hint only).
- **FR-7.7** — **Reset to defaults** for the active spec (one click, with confirmation prompt).
- **FR-7.8** — Switch the editor to view the list for any other class/spec the user wants to pre-configure (alts).

### FR-8 — Anchoring and positioning

- **FR-8.1** — Default anchor: `CENTER, UIParent, CENTER, 0, -150` (slightly below screen center).
- **FR-8.2** — When the user enables "Unlock frame" in General, the icon grid and castbar each become draggable; positions persist on lock.
- **FR-8.3** — Reset Position button restores defaults.
- **FR-8.4** — The icon grid and castbar can be unlocked together (single anchor) or independently (two anchors). Independent is the default.

### FR-9 — Test mode

- **FR-9.1** — When enabled, KickCD displays a fake castbar and icon grid with a simulated 5-second cast on loop, ignoring target conditions. Allows the user to preview look & feel and drag frames without finding a target dummy.
- **FR-9.2** — Test mode is automatically disabled when the user enters combat to avoid clutter.

### FR-10 — Saved variables + profiles

- **FR-10.1** — Account-wide DB (`KickCDDB`) holds **all** settings (layout, fonts, colors, spell lists), keyed by Ace3 AceDB-3.0 profiles.
- **FR-10.2** — Per-character is the default profile scope on first login so a Mage and a DH on the same account get distinct spell lists out of the box.
- **FR-10.3** — Schema is versioned (`KickCDDB.dbVersion`). Migrations run on `ADDON_LOADED` and never destructively wipe user data; older schemas are upgraded forward, never backward.
- **FR-10.4** — **Profile management** is exposed via the Profiles subcategory (FR-6.2.5) using the standard Ace3 AceDBOptions-3.0 widget. Users can:
  - Create a named profile (e.g., "Raid", "M+", "PvP", "Alt-DH") from scratch or by copying the active profile.
  - Switch the active profile live without `/reload`.
  - Copy settings from any other profile into the active one.
  - Reset the active profile to addon defaults.
  - Delete any non-active profile.
  - Set the default-resolution scope (per-character / per-class / per-realm / per-faction / global default) used for newly logged-in characters.
- **FR-10.5** — Switching profiles must update the live UI (icon grid, castbar, settings widgets) within 100 ms with no reload required.

---

## 4. Non-Functional Requirements

- **NFR-1 — Performance.** Idle CPU usage must be negligible (event-driven, no `OnUpdate` running when UI is hidden). Event handlers must filter by unit token early to avoid wasted work.
- **NFR-2 — Compatibility.** TOC targets Midnight 12.0.5 only via `## Interface: 120005`. Backward compatibility with TWW 11.2.x is **not** a v0.1 goal. API calls use modern surfaces (`C_Spell.*`, `Settings.*`) without legacy fallbacks. Feature-detection is still preferred over version-gating where signatures may shift across Midnight minor patches.
- **NFR-3 — No taint.** All UI is non-secure. No tampering with secure templates, action bars, or unit frames.
- **NFR-4 — No reload required.** Every settings change applies live.
- **NFR-5 — Libraries.** Uses Ace3 (`AceAddon-3.0`, `AceEvent-3.0`, `AceDB-3.0`, `AceDBOptions-3.0`, `AceConsole-3.0`, `AceGUI-3.0` only if needed for the spell-list editor), `LibStub`, `LibSharedMedia-3.0`. Libraries are embedded under `libs/` (no external dependency on other addons).
- **NFR-6 — Folder layout.** Single addon folder named `KickCD` at the root of the repo (so the repo root *is* the addon folder, per the user's instruction). TOC file is `KickCD.toc` at the root.
- **NFR-7 — Localization.** All user-facing strings go through a localization table; English (`enUS`) is the only locale shipped in v0.1, but the structure is in place.
- **NFR-8 — License.** MIT, declared in `## X-License` and `LICENSE` file.

---

## 5. Out of Scope (for v0.1)

The following are explicitly deferred:

- **Empowered cast** support (Evoker-style) beyond showing the bar — no per-empower-rank tick marks.
- **Party/raid member interrupts** — only the player's own interrupts are tracked. (Tracking `party1`/`party2` interrupts is on the v0.2 wishlist for arena.)
- **Diminishing returns** tracking on PvP CCs.
- **Audio cues** when an interrupt becomes available.
- **Nameplate-anchored** UI variant.
- **WeakAuras export** of the configuration.
- **Drag-and-drop** spell reordering (arrows only in v0.1).
- **Pet-cast** interrupts (Hunter pet Bullhead, Warlock Felhunter Spell Lock) — researched but deferred; can be added by user manually via the spell-list editor.

---

## 6. Acceptance criteria (high-level)

These map 1:1 to scenarios in `UAT.md`. Each criterion is testable by a human in the WoW client.

- **AC-1** — Installing KickCD into `Interface/AddOns/KickCD/` and launching WoW shows "Ka0s KickCD" in the addon list with no Lua errors.
- **AC-2** — Targeting a friendly NPC casting any spell → UI does not appear.
- **AC-3** — Targeting a hostile NPC casting an *uninterruptible* spell → UI does not appear.
- **AC-4** — Targeting a hostile NPC casting an *interruptible* spell → UI appears within 100 ms with the player's spec-correct primary interrupt + CCs and a castbar.
- **AC-5** — Pressing the interrupt mid-cast → cooldown swipe + red/dimmed visual on that icon. UI hides when cast ends.
- **AC-6** — Switching specs in town → tracked spell list updates without /reload.
- **AC-7** — Opening Blizzard Settings → "Ka0s KickCD" appears with all five subcategories. `/kickcd` and `/kcd` open it.
- **AC-8** — Adding/removing/reordering a spell in the editor → live UI reflects change immediately.
- **AC-9** — Unlocking + dragging the icon grid → position persists across `/reload` and logout.
- **AC-10** — Test mode shows fake castbar + icons even with no target; combat auto-disables it.
- **AC-11** — `/reload` and logout/login preserve all user customizations and profile selection.
- **AC-12** — Creating a new profile, copying settings from another, switching active profile, resetting, and deleting non-active profiles all work from the Profiles subcategory and apply live (no /reload).

---

## 7. Known risks (carried from RESEARCH.md §9)

| ID | Risk | Mitigation |
| --- | --- | --- |
| R-1 | Midnight 12.0.5 minor patches may bump Interface number (e.g., 120006 hotfix) | Ship `## Interface: 120005`; verify against live build before each patch and bump as needed |
| R-2 | Class/talent reworks may shuffle spellIDs in default list | Centralize the list in `defaults/spells.lua`; flag verification before each major patch |
| R-3 | `Settings.RegisterAddOnSetting` signature has churned (10.0–10.2) | Wrap in a thin compat shim; feature-detect the latest signature |
| R-4 | Some racials and PvP-talent interrupts (e.g., Mage Improved Counterspell) flagged TBD in research | Verify against in-game tooltips before v0.1 release; default to opt-in if unsure |
| R-5 | DK Asphyxiate has different IDs per spec (Blood vs Unholy/Frost) | Track both IDs; resolve by spec at runtime |
| R-6 | `WebSearch`/`WebFetch` were unavailable during research; spellIDs come from training-cutoff knowledge | Add a "verify-before-ship" step in the execution plan that requires testing each default in-game |

---

## 8. Open assumptions confirmed with user

- **Single tracked spell list** (no PvE/PvP split). Where a default is mode-specific, bias toward PvE. Users who want PvP-specific tracking use a separate Ace3 profile.
- **Midnight 12.0.5** (Interface 120005) is the only supported baseline for v0.1. No TWW back-compat.
- **Full Ace3 profile management** (create, switch, copy, reset, delete, scope toggles) is in scope for v0.1.

---

## 9. Glossary

- **Interrupt** — instant ability that stops a spell cast and locks that school for ~3–5s (Kick, Counterspell, Pummel, etc.).
- **CC (crowd control)** — stuns, knockbacks, incapacitates, silences, fears that **also** stop a cast as a side effect.
- **Notinterruptible** — flag returned by `UnitCastingInfo` indicating the cast cannot be kicked (boss-shielded casts, certain mechanics).
- **DR (diminishing returns)** — escalating duration reduction on the same CC category in PvP. Not modeled in v0.1.
- **CDR (cooldown reduction)** — talents/effects that reduce a spell's cooldown. KickCD relies on the live cooldown API so this is automatic.

---

## 10. Sign-off

**Status:** ⏳ Awaiting user sign-off

Reply with one of:
- ✅ "Approved — proceed to TECHNICAL_DESIGN"
- 🔧 "Changes needed: ..." (with specifics)
