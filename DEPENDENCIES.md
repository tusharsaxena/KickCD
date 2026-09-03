# Dependencies

Everything you need installed to build, run, test or release **Ka0s KickCD**, with commands that
work on the collection's development environment: **WSL2 / Ubuntu 24.04**.

Read only the group you need. **Players** need nothing beyond the game. **Contributors** need the
toolchain in [Development](#development). Nobody needs a graphics stack.

This file answers *what to install*. [`docs/testing.md`](docs/testing.md) answers *how to verify*.
Neither repeats the other (documentation-§7).

---

## Runtime (in-game)

**World of Warcraft (Retail). Nothing else.**

- `KickCD.toc` declares **no** `## Dependencies` line, so no addon is required.
- `KickCD.toc:8` declares `## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0`.
  Every one of those is **vendored** under `libs/` and committed (`KickCD.toc:17-29`,
  `libs/AceAddon-3.0/`, `libs/LibStub/`, `libs/CallbackHandler-1.0/`, `libs/LibSharedMedia-3.0/`),
  so `OptionalDeps` only affects **load order** when the player happens to have a standalone copy —
  it is not an install instruction. `libs/LibKa0s/` and `libs/LibCustomGlow-1.0/` are vendored the
  same way and are deliberately absent from `OptionalDeps`, because no standalone copy of either
  exists to defer to.
- Client version: `KickCD.toc:1` is `## Interface: 120007` — WoW 12.0.7 (Midnight).
- The addon **MUST NOT** fetch a library at build time; vendoring is the rule (library-stack,
  packaging). Listing a library above does not license fetching it.

---

## Development

The whole contributor toolchain. There is no build step and no compiler.

| Tool | Version | Why it is needed (evidence) |
|---|---|---|
| **Lua 5.1** | **5.1 exactly — not 5.2+** | `tests/_kit/loader.lua:72` calls `setfenv(chunk, makeEnv(mocks))` to sandbox each source file. `setfenv` was **removed in Lua 5.2**, so the harness does not merely prefer 5.1, it will not run on anything newer. |
| **`lua` on `PATH`** | same 5.1 binary | `tests/test_list_mode.lua:10` re-invokes the runner as a child process: `io.popen("lua " .. T.root .. "/tests/run.lua --list")`. The command is literally `lua`, so `lua5.1` alone on `PATH` is not enough. |
| **luacheck** | any recent (1.2.0 here) | The lint gate. `.luacheckrc` is a full config for it (`std = "lua51"`, the `read_globals` list at `.luacheckrc:10-43`); `docs/testing.md:7` names `luacheck .` as half the green commit gate. Pinning a version would be false precision — the config uses no version-specific feature. |
| **git** | any recent | The repo, obviously — but also a **test dependency**: the vendored gate `tests/_kit/vendor_sync.lua` (driven by the five-line `tests/test_vendor_sync.lua`) shells out with `git -C "%s" %s` to read the LibKa0s sibling checkout's tag — the tag named by the provenance line in **`CLAUDE.md`**, not `README.md` — and [docs/testing.md](docs/testing.md#verifying-the-vendored-copies) documents the four `diff -r` vendored-copy checks. |
| **POSIX `ls`, `diff`** | coreutils / diffutils, any recent | `tests/test_coresetup.lua:214` and `tests/test_slash_style.lua:132` enumerate source files with `io.popen("ls ...")`; the vendored-copy gate in [docs/testing.md](docs/testing.md#verifying-the-vendored-copies) is four `diff -r` invocations. Both ship with Ubuntu — listed so a minimal container image is not a mystery failure. |
| **bash** + `awk`, `sed`, `grep`, `tr`, `date` | any recent | `tests/_kit/run-automated-tests.sh:1` is `#!/usr/bin/env bash` — the vendored consolidated runner that produces every `docs/automated-tests/<stamp>/` bundle. It drives the four suites and formats their output with those coreutils; it is **not** needed for the plain `luacheck .` / `lua tests/run.lua` gate. Never edit it — it is vendored from `../LibKa0s/testkit`. |
| **lizard** | any recent (1.23.0 here) | Drives the `complexity` suite of the automated-test runner with the exact invocation the standard fixes (performance-§10). **Optional** — absent `lizard` means the report is stale, not that the addon is broken. |

`file` is worth having for one documented troubleshooting path — `docs/testing.md:108` uses
`file -b <path>` to establish which side of a CRLF divergence drifted — but nothing requires it.

### Install (WSL2 / Ubuntu 24.04)

```bash
# Lua 5.1 + luacheck
sudo apt install -y lua5.1 luarocks
sudo luarocks install luacheck

# lizard — via pipx, NOT pip (see the note below)
sudo apt install -y pipx
pipx ensurepath          # then restart the shell, or: source ~/.bashrc
pipx install lizard

# git, ls, diff, file are present on a stock Ubuntu; if not:
sudo apt install -y git coreutils diffutils file
```

The `lua5.1` package registers the `lua-interpreter` alternative, so `/usr/bin/lua` resolves to the
5.1 binary and the `lua` spelling `tests/test_list_mode.lua` needs works out of the box. If `lua`
is missing while `lua5.1` is present, point it at 5.1:

```bash
sudo update-alternatives --set lua-interpreter /usr/bin/lua5.1
```

> **`pip install lizard` fails on Ubuntu 24.04, and the error looks like your mistake.** 24.04 marks
> its system Python **`EXTERNALLY-MANAGED`** (PEP 668), so `pip` refuses to install into it. Use
> `pipx`, as above — it is the working instruction, not a preference. The documented alternative,
> if you want `lizard` in your user site-packages rather than its own venv, is
> `pip3 install --user --break-system-packages lizard`; it does what its name says, so prefer `pipx`.

### Verification

One line per tool. Run them from the repo root after installing.

```bash
lua -v                # Lua 5.1.x   <- must say 5.1
lua5.1 -v             # Lua 5.1.x
luacheck --version    # Luacheck: 1.x  /  Lua: PUC-Rio Lua 5.1
lizard --version      # 1.x
git --version         # git version 2.x
diff --version        # diffutils
```

If `lua -v` reports 5.4, the harness will fail on `setfenv` and nothing else will make sense —
fix that first.

---

## Release / assets

**Nothing here is needed to build, run or test the addon.** You can fix a typo, run the full suite
and open a PR with only the Development group installed.

- **Packaging is a hosted service, not local software.** `.pkgmeta` is consumed by the
  **BigWigs packager** that CurseForge runs on tag push; it sets `package-as: KickCD` and the
  `ignore:` list (`.pkgmeta:1-17`) and declares **no externals**, because the libraries are
  vendored. There is nothing to install and no packaging script to run locally — the repo's only
  script of any kind is the vendored test runner `tests/_kit/run-automated-tests.sh` (Development,
  above), and there is no `.py`, no `.ps1`, no `Makefile` and no CI workflow.
- **Asset tooling: none.** `media/logos/` and `media/screenshots/` hold committed binaries (the
  logo, the screenshots). They are **shipped assets, not build outputs** — nothing in this repo
  regenerates them, so no image or font toolchain is a dependency of this addon. Do not install
  one on this file's account. The monospace face and the shared icon set are **not this addon's
  assets at all**: they arrive inside the vendored LibKa0s payload at `libs/LibKa0s/media/`, with
  the OFL license beside the font, and the tool that produces them lives in the LibKa0s repo. One
  copy for the collection, one license to track — `media/fonts/` used to hold a duplicate here and
  no longer exists.
- **No Python, no Node, no image libraries.** Stated positively so nobody goes looking. The only
  Python-adjacent thing in the toolchain is `lizard`, which is in Development above and is optional.
- **The LibKa0s sibling checkout** (`../LibKa0s`) is not software you install, but the vendored-copy
  gate in [docs/testing.md](docs/testing.md#verifying-the-vendored-copies) cannot run without it, and
  `tests/_kit/vendor_sync.lua` degrades to a skip when it is absent. Clone it next to this repo if you touch `libs/LibKa0s/`.

---

## Am I set up correctly?

The exact commands this repo is verified with. All run from the repo root.

```bash
luacheck .                                          # must be 0 warnings, 0 errors
lua tests/run.lua                                   # must exit 0, all cases passing
lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .   # the `complexity` suite; recorded in each run bundle
```

The first two are the **green commit gate**. The third is a **release** checkpoint and is
deliberately **not** a commit gate (performance-§10). What each one means, what to do when one goes
red, and the vendored-copy diffs that run alongside them are all in
[`docs/testing.md`](docs/testing.md).

---

## Keeping this file honest

Checked at release with the rest of the doc set (documentation-§5). A new script, a new `require`,
a new `io.popen` target, or a dropped tool changes **this file in the same change** — a dependency
list that is wrong is the specific failure that makes a new contributor's first hour their last.
Every entry above names a `file:line`; keep new entries sourced the same way, and record anything
only *plausibly* required in those words rather than as a fact.
