# Forever probes — Ka0s KickCD

The in-game facts the WoW Forever port could not settle from source (Ka0sAddonsCommonTasks
`docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT/`, `00_DESIGN.md`, and the research's unknowns
U14-U25 in `inputs/research/SYNTHESIS.md` §5 as the critic amended them), in one sheet. The build
ships a **safe default** for each one, so the port does not wait for them (the rulings R3 and R4
of 2026-11-22). A probe answer that contradicts its default becomes a follow-up item, never a
silent edit.

These are the owner's to run. An agent never fills a `Result:` line. Record the answer there with
the date and the client build.

## The probe verbs

`/kcd debug probe` records most of these facts by itself, so one play session answers most of the
sheet:

| Verb | What it does |
|---|---|
| `/kcd debug probe start` | Starts recording, stamps the record with the client key, its version and build, and the addon version, and writes a `start` entry. |
| `/kcd debug probe stop` | Stops recording: every probe event unregistered, every pending read canceled. |
| `/kcd debug probe status` (or bare `/kcd debug probe`) | One chat line: running or stopped, entries against the cap, dropped count, client and build. |
| `/kcd debug probe clear` | Drops the record. While running, recording goes on in a fresh record. |

The record is `db.global.probe` inside `KickCDDB`. There is no new SavedVariables global. It holds
at most 500 entries (`NS.Probe.CAP`) and drops the oldest first, counting them in `dropped`; a
`start` entry is never the one dropped, so its facts survive a long session. It is
**session-only**: a reload or relog stops it, the record stays, and you start it again. It records
nothing while a simulation runs, and the start refuses during one, so every fact comes from the
live client. Every value is cut to 400 characters, and a secret value is stored as `<secret>`.

**How to read it.** Log out (or `/reload`) so the client writes the file, then open
`_forever_/WTF/Account/<account>/SavedVariables/KickCD.lua` (`_retail_` for the Retail answers) and
find `["probe"]` under `["global"]`. Each entry has a `kind` and a `t` (`time()`).

**A session that answers the sheet.** On WoW Forever, on each class you play: `/kcd debug probe
start`; target a casting mob, a mob whose cast cannot be interrupted, and focus another caster;
press an instant and then your kick at once; enter combat; as a Druid change between caster, bear
and cat forms; as a Warlock summon and dismiss a Felhunter; zone into a dungeon; `/kcd debug probe
stop`; log out. Then start and stop it once on Retail.

| `kind` | When | What it holds | Probes |
|---|---|---|---|
| `start` | At start | `rules` (the target cast-bar game rule, the game mode, the cast-bar CVar), `gcd` (whether 61304 answers), `deprecation` (the fallbacks CVar and which shims exist), `classes` (`GetNumClasses`, `GetClassInfo` for ids 1..13, `C_SpecializationInfo.GetAllClassIDs`), `spec` (the spec index and info, the spec id the list is keyed on, the level), `ranks` (every Forever rank family, rank by rank: known, in the player's book, in the pet's; and the rank the resolver picks), `runes` (425609, 410176 known), `feral` (form, Feral Charge's override, in the book, its cooldown), `spells` (the live list: stored id, resolved id, available, usable, max charges), `secrets` (the kick and its cooldown secrecy), `viewer` (whether the Cooldown Manager exists) | P1, P3, P4, P5, P6, P7, P8, P9, P10, P11 |
| `cast` | Every target or focus `UNIT_SPELLCAST_START`, `CHANNEL_START`, `INTERRUPTIBLE`, `NOT_INTERRUPTIBLE` | The unit, the spell, its name, and the interrupt flag as `"nil"`, `true`, `false` or `<secret>` (`none` when no cast could be read) | P1 |
| `player` | Every `UNIT_SPELLCAST_SUCCEEDED` of the player | The spell | P2 |
| `gcd` | 0.1 s after each `player` entry | The kick's cooldown fields (`isActive`, `isOnGCD`, `duration`) and `C_Spell.IsSpellUsable` | P2 |
| `form` | Every `UPDATE_SHAPESHIFT_FORM` | The `feral` facts above | P4 |
| `spellbook` | `SPELLS_CHANGED`, `UNIT_PET`, `PLAYER_LEVEL_UP`, `TRAIT_CONFIG_UPDATED`, only when the answers moved | Spell Lock 19244 and 19647 in the pet's book, the level, Feral Charge in the book | P5 |
| `combat` | Every `PLAYER_REGEN_DISABLED` | The kick, its cooldown fields and `C_Secrets.ShouldSpellCooldownBeSecret` in combat | P8 |
| `world` | Every `PLAYER_ENTERING_WORLD` | The game mode and `GetInstanceInfo()` | P9 |
| `error` | A probe handler that raised | The event and the message (the raise never leaves the probe) | n/a |
| `stop` | At stop | Nothing; it marks the end of a session | n/a |

The record's `rejected` lists any probe event this client refused to register. That is a fact too:
an absent event is one the addon cannot listen for on that client.

## The sheet

Each probe is the fact, what the probe verbs record for it, the `/run` fallback for a client where
the verbs are not loaded, and the safe default the build ships.

**P1. Enemy casts reach the addon, and the interrupt flag is plain and not nil (U14, the critic's
L11).** WoW Forever, first. Recorded: `start.rules`, `cast`. Read whether the target cast-bar rule
is active, and for an interruptible and an immune mob whether `flag` is `false`, `true`, `nil` or
`<secret>`. The default visibility mode, `target_casting_interruptible`, hides the whole grid
without a readable cast, so this is the first fact to check. Fallback:
`/dump C_GameRules.IsGameRuleActive(Enum.GameRule.TargetCastBarDisabled)`, then during a cast
`/run local v=select(8,UnitCastingInfo("target")) print(issecretvalue(v) and "secret" or type(v))`.
Safe default: casts pass through; a plain nil reads as interruptible false (`Compat.InterruptFlag`,
MKF-KC-05); a secret is tested before its type (MKF-KC-06). Result:

**P2. A kick during the global cooldown (U21, the critic's C2).** WoW Forever. Recorded: `player`
and `gcd`. Press an instant, then read the next `gcd` entry: `cooldown.isActive` and `usable` for the
kick. Fallback: press an instant, then at once
`/dump C_Spell.GetSpellCooldown(6552).isActive, C_Spell.IsSpellUsable(6552)`. Safe default: the
icon's brightness follows the cooldown only (ruling R5), so an icon may dim for the GCD; the
optional glow (off by default) drops during it. Result:

**P3. The global cooldown spell (U21).** WoW Forever. Recorded: `start.gcd`. `answers = false`
confirms 61304 is absent there. Fallback: `/dump C_Spell.GetSpellCooldown(61304)`. Safe default:
the debug log's `(gcd)` mark never fires on WoW Forever; nothing drawn reads it. Result:

**P4. Feral Charge per form (U16, the critic's C4).** WoW Forever, a Druid with Feral Charge. Recorded:
`form` on each change. Read the override in bear (16979) and in cat (414924), and whether `inBook`
stays true in cat. Fallback: in each form
`/dump GetShapeshiftFormID(), C_Spell.GetOverrideSpell(1238122), C_SpellBook.IsSpellInSpellBook(1238122,0,false)`.
Safe default: the row stores 1238122, resolves to the form's override, is re-read on
`UPDATE_SHAPESHIFT_FORM`, and the cat leap never counts as usable (MKF-KC-10). Result:

**P5. The pet's Spell Lock and the refresh edge (U17).** WoW Forever, a Warlock. Recorded:
`spellbook`. Summon a Felhunter, then dismiss it: read `pet[19244]` going true then false, and which
event carried each. Fallback: `/dump C_SpellBook.IsSpellInSpellBook(19244,1,false)`. Safe default:
the pet's book is asked through the rank resolver, refreshed on `SPELLS_CHANGED`. Result:

**P6. A superseded rank stays known (U15).** WoW Forever, a Rogue past level 26 or a Shaman past
level 8. Recorded: `start.ranks`. Read whether Kick 1766 still answers `known` once 1767 is learned,
and that `resolved` is the highest rank. Fallback:
`/dump C_SpellBook.IsSpellKnown(1766), C_SpellBook.IsSpellKnown(1767)`. Safe default: the resolver
asks every rank, highest first, so either answer resolves to the right rank (MKF-KC-09). Result:

**P7. The spec at runtime and the class loop (U18, U19).** WoW Forever, on each class, and once
below level 10. Recorded: `start.spec`, `start.classes`. Read that the spec info's id is the
class's own (1482..1491), and what `GetClassInfo(9)` and `(11)` answer. Fallback:
`/dump C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())` and
`/dump GetNumClasses(), GetClassInfo(9), GetClassInfo(11), C_SpecializationInfo.GetAllClassIDs()`.
Safe default: a spec id of 0 or none falls back to the class's id (`Const.SPEC_FOREVER`), and the
class list is the static per-client table, never `1..GetNumClasses()` (MKF-KC-04, MKF-KC-13).
Result:

**P8. Cooldown secrecy and charges (U20).** WoW Forever, in combat. Recorded: `start.secrets`,
`combat`, `start.spells[*].maxCharges`. Read `shouldBeSecret` for the kick in and out of combat,
and that no seeded kick reports charges. Fallback, in combat:
`/dump C_Secrets.ShouldSpellCooldownBeSecret(6552)`, and `/dump C_Spell.GetSpellCharges(6552)`.
Safe default: every cooldown is treated as secret, drawn through duration objects, and no charge
badge appears on WoW Forever. Result:

**P9. Focus and the game mode (U23).** WoW Forever. Recorded: `start.rules.gameMode`, `world`.
Then `/focus` a mob and check the focus grid follows it, which no recorder can do for you.
Fallback: `/dump C_GameRules.GetActiveGameMode(), UnitExists("focus")`. Safe default: the focus
unit is ported as on Retail. Result:

**P10. The rune spells (U24).** WoW Forever, a Paladin and a Druid. Recorded: `start.runes`.
Fallback: `/dump C_SpellBook.IsSpellKnown(425609), C_SpellBook.IsSpellKnown(410176)`. Safe default:
Rebuke and Skull Bash are left out of the Forever lists; a player can still add a known one.
Result:

**P11. The deprecation fallbacks (U25).** WoW Forever. Recorded: `start.deprecation`. Fallback:
`/dump GetCVarBool("loadDeprecationFallbacks"), IsPlayerSpell`. Safe default: availability reads
`C_SpellBook` on both clients (MKF-KC-03), so the answer changes nothing. Result:

**P12. The addon loads clean.** After the branch is on the Forever install: `/kcd diagnostics`,
and `/kcd debug events` reads `no rejected events`. Owner smoke; nothing to record. Result:

## The smaller questions the port left open

These ride along with the probes above.

- **Silence's lockout (U22).** Silence a caster as a Shadow Priest, then try the same school after
  5 s. No recorder reads a lockout. Safe default: Silence is tracked as a silence; no lockout is
  shown. Result:
- **Glow art under the Forever skin (U26).** Try all four glow styles. Result:
- **A hyphen in a surname (U27).** `/dump GetUnitName("target",true)` on such a name, if one
  exists. Safe default: a whole name is never split. Result:
