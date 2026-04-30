# Slash dispatch

Two ordered tables in `core/KickCD.lua` (`COMMANDS` for top-level, `DEBUG_COMMANDS` for `/kcd debug ...`). Each row is `{name, description, fn}`. The dispatcher:

- Bare `/kcd` → `printHelp` (iterates `COMMANDS`).
- `/kcd <known>` → executes that row's `fn`.
- `/kcd debug` → `printDebugHelp` (iterates `DEBUG_COMMANDS`).
- `/kcd debug <known>` → executes that row's `fn`.
- `/kcd <unknown>` → "unknown command" + help.
- `/kcd options` is aliased to `/kcd config` for backward compat.

`OnSlashCommand` lowercases only the command name and preserves case in
the rest of the input, so schema paths like `icons.primarySize` survive
unchanged through `/kcd set ...`. `runDebug` lowercases its own
subcommand for backward compat.

Three of the top-level commands (`list`, `get`, `set`) are
schema-driven and gain new entries automatically as schema rows are
added — see [ARCHITECTURE_SETTINGS_UI.md](ARCHITECTURE_SETTINGS_UI.md).

Adding a regular command is a one-row append; help text is generated from the same rows that drive dispatch.
