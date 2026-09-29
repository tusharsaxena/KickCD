# Candidates (KickCD)

One surface is new at v1.63.0, and it is the reason for this re-vendor:

- **Slash minor 17's profile verb** (`profiles` descriptor field, `Sl:CliProfile`,
  `Sl:ProfileSwitch`, `lib.ProfileNames`, nine `PROFILE_*` strings). KickCD already has AceDB
  profiles and a Profiles page (`settings/Profiles.lua`) but no CLI route to switch profiles.
  Owner decision D1 of the 2026-09-29 run puts the verb's logic in the library and has each addon
  register its own `profile` row.

The kit did not move, so there is nothing else to weigh.
