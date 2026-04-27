# Ka0s KickCD — User Acceptance Test

**Version:** 0.1 (draft, awaiting sign-off)
**Companion docs:** [REQUIREMENTS.md](REQUIREMENTS.md) · [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) · [EXECUTION_PLAN.md](EXECUTION_PLAN.md)

This document walks the user through manually validating KickCD v0.1 against every acceptance criterion in REQUIREMENTS.md §6. Run it after the build agents finish.

---

## 0. Test environment

### 0.1 Prerequisites

| Item | Required |
| --- | --- |
| WoW client | Retail Midnight 12.0.5 (build advertised as Interface 120005) |
| Character | Any class — PvE-friendly. Level 60+ recommended (talents matter) |
| Addons | KickCD only (disable other addons during smoke path) |
| Test location | A safe area near a target dummy (e.g., Valdrakken / your faction capital) for solo-runnable scenarios |
| Optional | A Mythic+ key or a hostile NPC zone for "real cast" testing (e.g., any dungeon, world quest with casters) |

### 0.2 Install

1. Locate the KickCD repo folder: `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD/`.
2. Copy or symlink it into your WoW addons folder so it lives at `Interface/AddOns/KickCD/`. The folder name **must** be `KickCD` (case-sensitive on some filesystems).
3. **Verify the layout:** `Interface/AddOns/KickCD/KickCD.toc` must exist directly inside the folder — not nested another level deep.
4. Launch WoW. At the character-select AddOns button, confirm "Ka0s KickCD" appears with version `0.1.0` and is **enabled**.
5. Log in to a max-level (or 60+) character.

### 0.3 Smoke path (5 minutes)

Run scenarios **AC-1 → AC-4 → AC-7 → AC-10** before anything else. If any fail, stop and report — the rest will likely fail too.

### 0.4 How to record results

Each scenario has a checkbox at the bottom. Mark it ✅ Pass or ❌ Fail and paste back to the chat. For a fail, include:
- The step number that failed
- What you expected vs what you saw
- Any Lua error popup (full text)
- A `/console scriptErrors 1` enabled session is recommended throughout testing

---

## 1. AC-1 — Addon loads without errors

**Maps to:** REQUIREMENTS AC-1
**Pre-conditions:** addon installed per §0.2; WoW launched; not yet in-world.

**Steps:**
1. At the character-select screen, click **AddOns**.
2. Confirm "Ka0s KickCD" is listed with no red text.
3. Tick the checkbox if not already enabled. Click **OK**.
4. Log in to any 60+ character.
5. After the loading screen, type `/run print(KickCD)` and press Enter.

**Expected:**
- No error popup at any point (loading screen, login, or after `/run`).
- Step 5 prints something like `table: 0x000...` to chat (the AceAddon table).
- `/run print(KickCD.VERSION)` prints `0.1.0`.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 2. AC-2 — UI hides on friendly target

**Maps to:** REQUIREMENTS AC-2

**Steps:**
1. Stand near any friendly NPC that occasionally casts (any major-city quest giver, innkeeper, vendor casting a spell on themselves, or a friendly faction guard).
2. Target it (`Tab` or click).
3. Wait up to 10 seconds for the NPC to cast something. (Trainer dummies often cast Heal/Repair spells.)

**Expected:**
- KickCD's icon grid and castbar **never appear** while targeting the friendly unit, even when it casts.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 3. AC-3 — UI hides on uninterruptible cast

**Maps to:** REQUIREMENTS AC-3

**Steps:**
1. Find a hostile NPC known to cast an *uninterruptible* spell. Reliable choices:
   - Any boss with shielded casts (raid finder, M+ boss).
   - World boss casts.
   - Some elite casters in The Maw / Plunderstorm have shielded casts.
2. Target the unit.
3. Wait for the unit to begin a shielded cast (cast bar shows with the shield icon in default Blizzard UI).

**Expected:**
- KickCD's icon grid and castbar **do not appear** while the cast is shielded.
- If the same unit later casts an unshielded spell, KickCD **does** appear (covered by AC-4).

**Result:** [ ] Pass [ ] Fail — notes:

---

## 4. AC-4 — UI shows on hostile interruptible cast

**Maps to:** REQUIREMENTS AC-4 (smoke path)

**Steps:**
1. Find any hostile NPC that casts an *interruptible* spell. Easy options:
   - Any caster trash mob in any dungeon (e.g., a Hexer / Mage / Cultist mob).
   - World quest casters in any current zone.
   - A target dummy will not cast — you need an actual hostile.
2. Stand at range so the mob casts at you. Do **not** interrupt yet.
3. Target the mob (`Tab` or click).
4. Watch the screen.

**Expected:**
- Within ~100 ms of the cast starting, KickCD's icon grid and castbar appear at the configured anchor.
- The castbar shows the spell name and animates to fill (or drain for a channel).
- The icon grid shows your spec's primary interrupt as the **larger** icon and your spec's CCs as **smaller** icons to its right.
- All icons that are off cooldown look "ready" (full alpha, normal color); any on cooldown look "dimmed" (red tint, lower alpha, swipe).

**Result:** [ ] Pass [ ] Fail — notes:

---

## 5. AC-5 — Cooldown indicator activates after kick

**Maps to:** REQUIREMENTS AC-5

**Steps:**
1. Repeat AC-4: find a casting hostile.
2. While KickCD is showing its UI, press your **interrupt** ability (Kick, Counterspell, Pummel, etc.) to kick the cast.
3. Observe the icon grid the moment the kick lands.
4. Continue watching for ~5 seconds, then for the full cooldown duration of your interrupt.

**Expected:**
- The instant the kick is used, the primary icon turns dimmed/red with a cooldown swipe ticking down.
- The castbar disappears within ~100 ms (the cast is interrupted).
- The icon grid disappears within ~100 ms (no active cast = no UI per FR-1).
- If you re-target another casting hostile before your kick comes off cooldown, the primary icon shows as on-cooldown there too.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 6. AC-6 — Spec change updates spell list live

**Maps to:** REQUIREMENTS AC-6
**Skip if:** your character has only one spec.

**Steps:**
1. While in town (or rested area), open the talents pane (default `N`).
2. Switch to a different specialization on the same character. Confirm.
3. Without `/reload`, enable test mode: `/kickcd test` (or open Settings → Ka0s KickCD → General → Test Mode).
4. Observe the icon grid.

**Expected:**
- The icon grid shows the **new spec's** primary interrupt and CCs — not the old spec's list.
- No Lua errors.
- Disable test mode after observing: `/kickcd test` again.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 7. AC-7 — Settings panel and slash commands

**Maps to:** REQUIREMENTS AC-7 (smoke path)

**Steps:**
1. Type `/kickcd` in chat and press Enter.
2. Confirm the Blizzard Settings panel opens to "Ka0s KickCD".
3. Confirm five subcategories are visible in the left tree: **General**, **Icons**, **Castbar**, **Spells**, **Profiles**.
4. Close Settings.
5. Type `/kcd` and press Enter.
6. Confirm Settings opens to the same place.

**Expected:**
- Steps 2 and 6 both open Settings to "Ka0s KickCD".
- All five subcategories are present and can be clicked into without Lua errors.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 8. AC-8 — Spell editor live updates

**Maps to:** REQUIREMENTS AC-8

**Steps:**
1. Open Settings → Ka0s KickCD → **Spells**.
2. The editor should show your active class+spec and the current tracked-spell list (e.g., for a Demon Hunter Havoc: Disrupt, Imprison, Chaos Nova, Sigil of Misery).
3. **Reorder:** click the ▲ next to the second spell to move it above the first. Confirm the list visually updates.
4. **Toggle off:** click the enabled-toggle next to one spell to disable it.
5. **Remove:** click the ✕ next to one spell.
6. **Add:** click "Add spell..." → enter spell ID `1766` (Rogue Kick — should validate even on non-Rogues; this just tests the input form). Confirm.
7. Close Settings.
8. Enable test mode: `/kickcd test`.
9. Observe the icon grid.

**Expected:**
- Steps 3–6 each update the list visually inside the editor.
- Step 9: the icon grid reflects every change — reordered, removed, added — without `/reload`.
- After validating, click "Reset to defaults" (with confirmation popup) and confirm the spec list returns to the shipped defaults.
- Disable test mode: `/kickcd test`.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 9. AC-9 — Drag-to-position persists

**Maps to:** REQUIREMENTS AC-9

**Steps:**
1. Open Settings → Ka0s KickCD → **General**.
2. Uncheck **Lock frame**.
3. Enable test mode (still in General → **Test Mode** checkbox).
4. Drag the icon grid to a new position on the screen.
5. Drag the castbar to a different new position.
6. Re-check **Lock frame**.
7. Disable test mode.
8. Type `/reload` and confirm.
9. After reload, enable test mode again.

**Expected:**
- After step 8 (reload), both icon grid and castbar reappear at the positions you dragged them to in steps 4–5 — not the defaults.
- Repeat with `/logout` instead of `/reload` and re-login: positions still persist.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 10. AC-10 — Test mode

**Maps to:** REQUIREMENTS AC-10 (smoke path)

**Steps:**
1. Stand somewhere safe with **no target**. Click off any current target.
2. Type `/kickcd test` (or check **Test Mode** in General settings).
3. Observe the screen.
4. Wait through 2 full cycles (each cycle is 5 seconds).
5. Now engage a hostile mob to put yourself in combat.
6. Observe what happens to the test UI.

**Expected:**
- Steps 2–4: a fake castbar animates a 5-second cast on loop, with the icon grid showing your spec's spells in real ready/cooldown states. Even with no target.
- Step 5–6: when combat starts (`PLAYER_REGEN_DISABLED`), test mode auto-disables. The fake UI disappears (and only reappears for real interruptible casts per AC-4).

**Result:** [ ] Pass [ ] Fail — notes:

---

## 11. AC-11 — `/reload` and re-login preserve state

**Maps to:** REQUIREMENTS AC-11

**Steps:**
1. Customize several settings to non-defaults:
   - General → scale = 1.25
   - Icons → primary size = 56
   - Castbar → width = 320
   - Spells → remove one spell from the active spec
   - General → drag the icon grid to a non-default position
2. Type `/reload`.
3. Re-open Settings and verify each customization survived.
4. Log out to character select.
5. Log back in to the same character.
6. Verify all customizations are still in place.

**Expected:**
- All five customizations survive both `/reload` (step 3) and full logout (step 6).

**Result:** [ ] Pass [ ] Fail — notes:

---

## 12. AC-12 — Profile management

**Maps to:** REQUIREMENTS AC-12 + FR-10.4

**Steps:**
1. Open Settings → Ka0s KickCD → **Profiles**.
2. **Create:** in the "New" box, type `M+` and press Enter (or click the create button). The active profile dropdown should switch to `M+`.
3. **Edit:** go to Spells, remove one spell from the M+ profile.
4. **Switch:** Profiles → set active profile back to `Default` from the dropdown.
5. Open Spells. The list should be the original Default — not the M+ list with the spell removed.
6. **Copy:** Profiles → "Copy from" → select `M+`. Confirm. The Default profile should now match M+ (one spell removed from active spec list).
7. **Reset:** Profiles → "Reset profile" button. Confirm popup. The Default profile reverts to shipped defaults.
8. **Delete:** Profiles → switch active back to `Default` → use "Delete a profile" → select `M+` → confirm.

**Expected:**
- Each step (2, 4, 6, 7, 8) applies live with no `/reload` required.
- After step 8, the `M+` profile is gone from all dropdowns.
- No Lua errors throughout.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 13. Edge cases (non-AC, but useful)

These are not blocking but should be sanity-checked:

### 13.1 Rapid target switching
Tab-target rapidly between 5+ different units (mix of friendly, hostile-not-casting, hostile-casting). The UI should appear/hide cleanly with no Lua errors and no stuck castbar.

**Result:** [ ] Pass [ ] Fail — notes:

### 13.2 Dead target
Kill a target mid-cast. The UI should hide instantly the moment the unit dies (`UnitIsDead("target") == true`).

**Result:** [ ] Pass [ ] Fail — notes:

### 13.3 Pet cast (informational)
Targeting an enemy pet (e.g., a hunter pet in PvP) that casts a spell — KickCD should detect it (same conditions). Note: pet-owner kicks are out of scope for v0.1.

**Result:** [ ] Pass [ ] Fail — notes:

### 13.4 Race-specific default
Log in to a Tauren / Pandaren / Highmountain / Kul Tiran / Nightborne character. Open Settings → Spells. The race's cast-stopper (War Stomp / Quaking Palm / Bull Rush / Haymaker / Arcane Pulse) should be present in the default list.

**Result:** [ ] Pass [ ] Fail — notes:

### 13.5 LibSharedMedia textures
Settings → Castbar → Texture dropdown. Choose any non-default texture from the list (e.g., a SharedMedia bar texture from another addon). The bar should restyle live without `/reload`.

**Result:** [ ] Pass [ ] Fail — notes:

---

## 14. Bug report template

If a scenario fails, paste this back:

```
Scenario:    AC-#   (e.g., AC-5)
Step that failed: # (e.g., step 3)
Expected:    [paste expected]
Actual:      [what happened]
Lua error:   [full popup text, or "none"]
Class+spec:  [e.g., DH Havoc]
Race:        [e.g., Blood Elf]
Other addons enabled: [list, or "only KickCD"]
Repro rate:  [always | sometimes | once]
```

---

## 15. Sign-off

**Status:** ⏳ Awaiting user sign-off on this UAT plan (not yet executed)

Reply with:
- ✅ "Approved — start the build"
- 🔧 "Changes needed: ..." (with specifics)

Once approved, the orchestrator will dispatch all build phases per EXECUTION_PLAN.md, and then return here for you to execute scenarios §1 through §13.
