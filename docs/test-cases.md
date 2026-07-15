# Test Cases

_Generated — do not hand-edit. Regenerate with `lua tests/run.lua --list > docs/test-cases.md`._

### test_util.lua (7)

- Util.Unpack array-style color
- Util.Unpack hash-style color
- Util.Unpack nil defaults to opaque white
- Util.NormalizeSpecToken strips whitespace and upper-cases
- Util.NormalizeClassToken upper-cases
- Util.DeepCopy clones nested tables (no shared refs)
- Util.Throttle coalesces a burst to one trailing-args call

### test_schema.lua (5)

- Settings.Schema is assembled from the settings/* files
- Helpers.ValidateSchema reports zero malformed rows
- Every schema row has a string path and a known type
- Helpers.Resolve walks a dotted path into db.profile
- Helpers.FindSchema locates a row by path

### test_database.lua (7)

- DEFAULT_PROFILE carries the expected top-level shape
- OnInitialize built a live db with a merged profile
- Schema version lives in db.global, not the profile (KCD-20)
- MigrateProfile is a no-op at the current schema version
- MigrateProfile treats a missing version as v1 and stamps global
- MigrateProfile adopts a legacy per-profile dbVersion even past AceDB backfill (KCD-20)
- GetSpellList returns nil for an unseeded class/spec

### test_bus.lua (4)

- AceEvent mock fans one message out to two distinct targets
- Two receivers on the SAME target clobber (proves keying is by target)
- Addon SendMessage reaches a registered module target
- NewBusTarget gives each receiver its own target — both fire (KCD-09)

### test_compat.lua (5)

- Compat exposes the spec shims
- GetSpecialization prefers C_SpecializationInfo
- GetSpecializationInfo passes the multi-return through
- GetSpecialization falls back to the deprecated global when C_ is absent
- GetSpecializationInfo falls back to the deprecated global when C_ is absent

### test_debuglog.lua (9)

- DebugLog module loaded with its public API
- FormatPlain is clean, un-coloured, and well-shaped (§12.3)
- FormatColored carries the same fields as FormatPlain (no drift)
- debug flag defaults OFF and lives in State, never in SavedVariables (§12.5)
- SetEnabled is the single write seam and toggles State.debug
- SetEnabled brackets each session with a console line at both ends (§12.5)
- NS.Debug is a no-op when disabled (zero capture) and appends when enabled
- NS.Debug sanitizes secret args and never errors
- NS.Debug passes plain args through unchanged

### test_icongrid_layout.lua (8)

- Layout math is published on the IconGrid module
- IconGrid:Layout method survives alongside the geometry table
- parseAnchor normalises modern, legacy, and CENTER tokens
- parseAnchor rejects invalid combos with the RIGHT/CENTER default
- parseGrow accepts perpendicular axes and defaults otherwise
- placeBlock RIGHT/CENTER geometry (primary left, block right, centred)
- placeBlock TOP/CENTER geometry (block above primary)
- placeBlock CENTER stacks both on the grid centre

### test_lifecycle.lua (4)

- addon + all modules enable cleanly on the Ace3 login path
- IconGrid:OnEnable installs its bus subscriptions
- Cooldowns and Castbar subscribe to CONFIG_CHANGED after enable
- post-enable CONFIG_CHANGED re-layout runs end-to-end without error

### test_cooldowns.lua (5)

- SPELL_UPDATE_* burst coalesces to one Refresh per frame
- Refresh logs one coalesced line only when a spell changed
- Refresh coalesces multiple simultaneous changes into ONE line
- Rebuild summary logs on a material change and is silent on a repeat
- Refresh logs nothing when no spell changed

### test_settings_log.lua (2)

- Helpers.Set logs one debounced [Set] line with the settled value
- Helpers.Set formats an RGBA table compactly

### test_flow_traces.lua (1)

- OnProfileChanged logs a [Profile] line

### test_list_mode.lua (4)

- --list emits a generated '# Test Cases' inventory header + regen note
- --list stdout is inventory-only, no run output
- --list per-suite header counts match their bullet counts
- --list Totals row equals the grand total of bullets

## Totals

| Suite | Cases |
| --- | --- |
| test_util.lua | 7 |
| test_schema.lua | 5 |
| test_database.lua | 7 |
| test_bus.lua | 4 |
| test_compat.lua | 5 |
| test_debuglog.lua | 9 |
| test_icongrid_layout.lua | 8 |
| test_lifecycle.lua | 4 |
| test_cooldowns.lua | 5 |
| test_settings_log.lua | 2 |
| test_flow_traces.lua | 1 |
| test_list_mode.lua | 4 |
| **Total** | **61** |
