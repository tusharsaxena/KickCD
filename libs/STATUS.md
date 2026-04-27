# libs/ status

**Status:** `manual-install required`

**Reason:** The Phase 1 build sandbox blocked outbound network (git/svn/curl
to CurseForge, GitHub, and the WoWAce SVN trunk are all denied). Agent A1
could not vendor the libraries automatically.

**What the user needs to do:** follow `libs/MANUAL_INSTALL.md` to drop in
Ace3 and LibSharedMedia-3.0 from CurseForge (or one of the listed
mirrors). Total time: ~3 minutes.

**Verification (run from the repo root):**

```bash
find libs -type f \( -name '*.lua' -o -name '*.xml' \) | sort | wc -l
```

Should be **45 or more** once the libs are populated. Currently: 0.

**Blockers for downstream agents:** none. Empty placeholder lib folders
already exist, so other agents (A2/A3/A4, B*, C*) can write their files
in parallel; the addon just won't *load in WoW* until the user finishes
the manual install. All TOC paths and contracts are unchanged.

**Flip this file to `vendored` when the libs are dropped in.**
