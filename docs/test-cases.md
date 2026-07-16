# Test Cases

_Generated — do not hand-edit. Regenerate with `lua tests/run.lua --list > docs/test-cases.md`._

### test_util.lua (8)

- Util.Unpack array-style color
- Util.Unpack hash-style color
- Util.Unpack nil defaults to opaque white
- Util.NormalizeSpecToken strips whitespace and upper-cases
- Util.NormalizeClassToken upper-cases
- Util.DeepCopy clones nested tables (no shared refs)
- Util.Throttle coalesces a burst to one trailing-args call
- RegisterUnitCastEvent registers the dispatch frame for the named unit

### test_units.lua (11)

- Units.LIST is target then focus
- target is never linked; focus honors its link flag
- Icons(focus) resolves to target's icons when linked
- IsEnabled combines master and per-unit enable
- CopyStyling snapshots target appearance into focus and unlinks
- Label.text is per-unit and not link-resolved
- IconGrid:ReconcileUnits enables focus once units.focus.enabled is true
- Castbar:ReconcileUnits mirrors IconGrid's enable/disable transitions
- master-enable off then on disables then revives both units without a reload
- LabelStyle resolves to target's style when focus is linked
- CopyStyling snapshots target label.style but keeps focus text/show

### test_schema.lua (11)

- Settings.Schema is assembled from the settings/* files
- Helpers.ValidateSchema reports zero malformed rows
- Every schema row has a string path and a known type
- Helpers.Resolve walks a dotted path into db.profile
- icons/castbar/label schema rows are unit-scoped and valid
- Helpers.FindSchema locates a row by path
- General exposes focus rows; unit-selector panels still filter them out
- label panel carries per-unit label rows; General no longer does
- RenderRows survives a row whose render throws (no blank panel)
- every label-panel row's default is a member of its static values list
- PartitionUnitRows splits alwaysPerUnit rows from styled rows

### test_database.lua (15)

- DEFAULT_PROFILE carries the expected top-level shape
- OnInitialize built a live db with a merged profile
- Schema version lives in db.global, not the profile (KCD-20)
- MigrateProfile is a no-op at the current schema version
- MigrateProfile treats a missing version as v1 and walks forward to current
- MigrateProfile adopts a legacy per-profile dbVersion even past AceDB backfill (KCD-20)
- GetSpellList returns nil for an unseeded class/spec
- DEFAULT_PROFILE nests appearance under units.target / units.focus
- FoldLegacyUnits moves a legacy top-level config under units.target
- FoldLegacyUnits is idempotent and leaves a fresh v2 profile untouched
- DEFAULT_PROFILE ships an identical label.style for target and focus
- BackfillLabelStyle adds a missing label.style and preserves show/text
- BackfillLabelStyle is idempotent and leaves an existing style untouched
- BackfillLabelStyle key-fills a missing field onto an existing style, leaving other keys untouched
- DB label.style.color default matches the settings schema color row default (DB<->schema sync)

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

### test_unitlabel.lua (4)

- UnitLabel module is registered
- UnitLabel.ApplyAll runs without error for both units
- Castbar:GetCastbarFrame does not create an instance for an unknown unit
- UnitLabel:Apply parents the label to the icon grid, not the cast bar (General-visibility, not cast-gated)

### test_cooldowns.lua (5)

- SPELL_UPDATE_* burst coalesces to one Refresh per frame
- Refresh logs one coalesced line only when a spell changed
- Refresh coalesces multiple simultaneous changes into ONE line
- Rebuild summary logs on a material change and is silent on a repeat
- Refresh logs nothing when no spell changed

### test_settings_log.lua (4)

- Helpers.Set logs one debounced [Set] line with the settled value
- Helpers.Set formats an RGBA table compactly
- ResetIconPosition restores units.target.anchors.icons to the default (Task 8 fix)
- ResetAll (via ResetAllPositions) restores both units' icons+castbar anchors to default (resetall bug fix)

### test_flow_traces.lua (1)

- OnProfileChanged logs a [Profile] line

### test_version.lua (3)

- `version` is a registered COMMANDS verb (slash-commands-§3)
- `/kcd version` prints v<version> on exactly one line
- `version` falls back to the NS.VERSION stamp when TOC metadata is absent

### test_list_mode.lua (5)

- --list emits a generated '# Test Cases' inventory header + regen note
- --list stdout is inventory-only, no run output
- --list emits CRLF line endings (matches the repo eol=crlf policy)
- --list per-suite header counts match their bullet counts
- --list Totals row equals the grand total of bullets

## Totals

| Suite | Cases |
| --- | --- |
| test_util.lua | 8 |
| test_units.lua | 11 |
| test_schema.lua | 11 |
| test_database.lua | 15 |
| test_bus.lua | 4 |
| test_compat.lua | 5 |
| test_debuglog.lua | 9 |
| test_icongrid_layout.lua | 8 |
| test_lifecycle.lua | 4 |
| test_unitlabel.lua | 4 |
| test_cooldowns.lua | 5 |
| test_settings_log.lua | 4 |
| test_flow_traces.lua | 1 |
| test_version.lua | 3 |
| test_list_mode.lua | 5 |
| **Total** | **97** |
