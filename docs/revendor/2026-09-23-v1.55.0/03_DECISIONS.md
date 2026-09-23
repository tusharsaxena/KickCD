# 03 - Decisions

Non-interactive. The owner delegated the Step 6 interview (CP-6) to the orchestrator's decision rules:
adopt each delta the spec prescribes for this repo; decline as "not now" where the spec lets the repo
defer, where there is no prescribed delta, or where an adoption cannot land green without changing
behavior a test pins or a player would see (after one honest attempt, rolled back); decline as "never"
only for a structural misfit the spec or this repo's docs record. A decline is filed as a public GitHub
issue in this repo. Each entry below was written as the decision landed.

## C1. `LibKa0s-Compat-1.0` - adopt

**Why.** `3b-specs/compat.md:465-485` prescribes the KickCD delta member by member, and rule 1 says
adopt a prescribed delta. It closes a recorded gap (the secret test has no seam today: 12 inline
`_G.issecretvalue(` calls, measured in `02_CANDIDATES.md`). The four behavior changes the spec names sit on
the legacy rungs, on bad input, or on a library-absent load; none is a path a 12.x client with the payload
present takes, and no existing test pins the old answer except the legacy `GetSpellInfo` fixture, which
the spec says encodes the wrong shape and corrects (`compat.md:120-125`, J2).

**Shape.** Host seam names kept (`NS.Compat.X`); readers take the reader arm (absent value) and
`IsSecret` the guard arm (the one-rung body, commented as the documented duplication). Members the spec
does not route stay host code (`GetSpellCooldownDuration`, `GetSpellCharges`, `IsSpellUsable`,
`IsSpellAvailable`, the cast readers, `DebugInterrupt`, `_firstReturn`). `CanAccess` and `IsSafeKey` are
not wired: KickCD has no caller for either, and the spec's KickCD delta names only `IsSecret`.

**Landed:** 45cc03f.

## C2. `LibKa0s-Bus-1.0` - adopt (Catalog only)

**Why.** `3b-specs/bus.md:628-636` prescribes the KickCD delta: declare `NS.MSG` with the current wire
strings and sweep the 23 literal lines, then rename to PascalCase and wrap in `Catalog`. It closes a
recorded gap (debt row 9+13; the `architecture-section-4` declare-once MUST is unmet). A message name is not
something a player sees, and no other addon listens for these names (`02_CANDIDATES.md` C2). Tests that
type the literal are moved onto `NS.MSG` constants, so they keep asserting the same wiring.

**Shape.** Two commits inside the one candidate, in the spec's order. The table lives in
`core/Constants.lua` (no `core/Bus.lua` here). `NS.NewBusTarget` stays untracked, and no record is built:
KickCD's receivers are AceAddon modules plus one settings target (`bus.md:635-636`). The degraded arm is
the `bus.md` section 6 idiom, `Bus and Bus.Catalog(addonName, MSG) or MSG`: the plain table.

**Wire names.** Mechanical PascalCase of the existing suffix (`SPELL_STATE` -> `SpellState`, and so on),
which is what the spec prescribes. The naming-cheatsheet's past-participle SHOULD (`SpellStateChanged`,
`CombatStateChanged`, ...) is not taken in this run and is flagged in `05_SUMMARY.md` for the owner.

**Parity gate.** Not added as a by-name `assertSurfaceParity` call: the host wires one library member
inline and keeps no stub table for the call to measure. The degraded-load case pins the degraded
`NS.MSG` against the live one instead (same keys, same values).

**Landed:** c0ea075 (declare-once sweep), ae286ce (PascalCase rename and `Catalog`).

## C3. `LibKa0s-Schema-1.0` - decline, not now

**Why.** The spec prescribes no KickCD delta (`3b-specs/schema.md:465-603` names nine adopters; KickCD is
not one, and the survey at `:6-15` did not read it). KickCD's write seam `Helpers.Set(path, section,
value)` (`settings/Panel.lua:380`) is fronted by special-path tables (`:73-122`, `:386-395`) and takes the
master-switch hook in the same turn as the write (`:417`); the spec's common block binds descriptors to
the instance only for a host with no pre-seam gate (`schema.md:467-482`). Mapping that onto the library is a
design survey, not a prescribed delta. It is not "never": nothing recorded says the major misfits KickCD,
and the duplication it would end is real.

**Filed.** `state:triaged`, `severity:medium` (deferred duplication):
[#22](https://github.com/tusharsaxena/KickCD/issues/22), "Adopt LibKa0s-Schema-1.0 for the settings schema
runtime".
