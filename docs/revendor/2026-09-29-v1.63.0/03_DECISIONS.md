# Decisions (KickCD)

- **No adoption interview and no GitHub issues.** The adoption was decided upstream, by owner
  decisions D1-D3 of the 2026-09-29 run
  (`Ka0sAddonsCommonTasks/docs/2026-09-29-SMOKE_REWORK_AND_PROFILE_VERB/00_OVERVIEW.md`), and this
  addon's item is SP-KC-02 (spec S3).
- **Adopted: only the Slash minor 17 profile surface**, by SP-KC-02 itself: the `profiles`
  descriptor field, a `profile` COMMANDS row routed to `CliProfile`, and `profile` added to the
  addon's own live verbs (`NS.EXTRA_LIVE_VERBS`). It lands in a second commit, after this
  re-vendor commit.
- The library-absent stub in `settings/Slash.lua` gains `CliProfile` and `ProfileSwitch` in the
  re-vendor commit, because the parity gate goes red without them (`01_DELTA.md`, *Blockers*).
- Nothing else is adopted. `lib.ProfileNames` has no caller here: KickCD has no profile sub-tree
  of its own.
