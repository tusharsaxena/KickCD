# Conventions

- Module files start with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to should keep that list in sync with the actual code.
- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in `core/Database.lua`.
- All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM.
