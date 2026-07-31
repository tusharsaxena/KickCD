# Test Cases

_Generated — do not hand-edit. Regenerate with `lua tests/run.lua --list > docs/test-cases.md`._

### test_util.lua (13)

- Util.Unpack array-style color
- Util.Unpack hash-style color
- Util.Unpack nil defaults to opaque white
- Util.NormalizeSpecToken strips whitespace and upper-cases
- Util.PlayerSpecID returns the numeric spec ID, not the localised name
- Util.SpecTokenForID maps a spec ID to its English token
- Util.SpecDisplay prefers the English token and falls back to the raw ID
- Util.ResolveSpecID accepts a number, a numeric string and an English token
- Util.ResolveSpecID rejects unknown input rather than guessing
- Util.NormalizeClassToken upper-cases
- Util.DeepCopy clones nested tables (no shared refs)
- Util.Throttle coalesces a burst to one trailing-args call
- RegisterUnitCastEvent registers the dispatch frame for the named unit

### test_coresetup.lua (16)

- the harness loads the vendored LibKa0s majors, so the suite is not measuring a stub
- the runner's library load list matches libs/LibKa0s/LibKa0s.xml file for file
- every file the runner loads for LibKa0s exists on disk
- NS.SafeToString renders ordinary values through tostring
- NS.SafeToString answers nil and booleans up front, never masking them
- NS.SafeToString renders an unconcatable value as the shared <secret> sentinel
- NS.IsConcatSafe probes table.concat, not the .. operator
- NS.Util.print renders prefix, one space, then the body — byte for byte
- NS.Util.print space-joins its arguments, mirroring print()
- NS.Util.print is secret-safe: an unconcatable argument cannot raise
- NS.Util.print resolves the prefix at call time, not at load time
- NS.Util.print is the library printer, not a host reimplementation
- core/Util.lua no longer defines a printer of its own
- no addon file emits a bare "secret" sentinel of its own
- with LibKa0s absent the addon still loads and still prints tagged lines
- the degraded printer is still secret-safe and still says <secret>

### test_util_anchor.lua (26)

- SaveAnchor snapshots a frame's first anchor point
- SaveAnchor stores no frame reference, only serialisable fields
- SaveAnchor falls back to a centred anchor for a nil frame
- SaveAnchor falls back to centred for a frame with no points set
- SaveAnchor reads point ONE, ignoring later anchors
- ApplyAnchor positions the frame against UIParent
- ApplyAnchor clears stale points instead of stacking them
- ApplyAnchor fills in centred defaults for a partial saved anchor
- ApplyAnchor is a no-op for a nil frame or nil anchor
- SaveAnchor and ApplyAnchor round-trip a dragged position exactly
- Throttle passes the LAST call's arguments, not the first
- Throttle re-arms after firing, so a later burst is not swallowed
- Throttle preserves embedded nils in the argument list
- Throttle survives a nil delay by treating it as immediate
- SpecDisplayName returns the client's LOCALISED name for display
- SpecDisplayName returns the empty string for a non-number
- SpecDisplayName title-cases the English token for a spec the client can't name
- SpecDisplayName falls back to the raw ID for a spec nothing knows
- SpecTokenForID rejects a non-number rather than indexing with it
- SpecOrderForClass returns Blizzard's order, not numeric order
- SpecOrderForClass normalises a lower-case class token
- SpecOrderForClass is nil for a class the client can't enumerate
- NormalizeClassToken upper-cases and tolerates nil
- RegisterUnitCastEvent forwards the event into the module's handler
- RegisterUnitCastEvent tolerates a handler that isn't defined yet
- RegisterUnitCastEvent returns a frame the caller can unregister

### test_constants.lua (22)

- Constants: the chat prefix is the cyan [KCD] tag and closes its colour code
- Constants: the notice grey is an opener with no closer (callers add |r)
- Constants: the GCD upper bound covers an unhasted 1.5s global
- Constants: the cast bar's inside and outside insets are symmetric
- Constants: the panel header reserves more height than its top inset
- Constants: every panel metric is a positive number
- Constants: FONT_MONO points at a font that is actually shipped
- Constants: the shipped mono font ships its OFL license alongside it
- Constants: every spec ID is a positive integer
- Constants: every spec token is UPPER_SNAKE_CASE
- Constants: no two spec tokens share a spec ID
- Constants: the three Midnight-era spec IDs are present and correct
- Constants: SPEC covers all thirteen player classes at three specs each
- Constants: every spec ID has a reverse token
- Constants: the reverse map is exactly as large as the forward map
- Constants: the reverse map strips the disambiguating class suffix
- Constants: a non-shared token survives the suffix strip unchanged
- Constants: exactly the four reused spec names carry a class suffix
- Constants: every shared spec name is suffixed on every class that has it
- Constants: every spec key in defaults/Spells.lua is a known spec ID
- Constants: every spec ID in Const.SPEC has a shipped default list
- Constants: defaults ship one class table per class, all UPPER-case tokens

### test_state.lua (23)

- State: the combat flag starts false and holds `debug` session-only
- State.SetInCombat coerces any truthy value to a real boolean
- State: the bootstrap frame owns all three combat/login events
- State: PLAYER_REGEN_DISABLED / _ENABLED drive the flag both ways
- State: PLAYER_LOGIN seeds the flag from InCombatLockdown
- State: PLAYER_LOGIN releases its own registration after seeding
- State: every combat transition fans out COMBAT_STATE with the new flag
- IsHostileUnitCasting is false for a nil unit or one that doesn't exist
- IsHostileUnitCasting is false for a friendly caster
- IsHostileUnitCasting is true for a hostile CAST
- IsHostileUnitCasting is true for a hostile CHANNEL
- IsHostileUnitCasting is false for a hostile unit doing nothing
- IsHostileUnitCasting only truth-tests the cast name, never reads it
- IsHostileUnitCasting collapses the API multi-return to position 1
- ApplyInterruptibleAlpha refuses a frame that can't take the secret
- ApplyInterruptibleAlpha declines when the unit is absent or friendly
- ApplyInterruptibleAlpha declines when the unit has no cast at all
- ApplyInterruptibleAlpha maps interruptible -> alpha, uninterruptible -> 0
- ApplyInterruptibleAlpha defaults the visible alpha to 1
- ApplyInterruptibleAlpha passes a SECRET notInterruptible through verbatim
- ApplyInterruptibleAlpha reads the CHANNEL flag from position 7, not 8
- ApplyInterruptibleAlpha prefers the cast over a simultaneous channel
- ApplyInterruptibleAlpha never inspects the cast name it gates on

### test_locale.lua (9)

- frFR Elemental Shaman seeds a non-empty default spell list (issue #8)
- frFR and enUS Elemental Shaman seed byte-identical spell lists
- frFR player spec resolves to the locale-invariant numeric spec ID
- frFR client resolves a localised spec name typed at the slash command
- frFR Elemental Shaman actually watches its cooldowns end-to-end (issue #8)
- the Spells editor labels specs in the client's own language
- SpecDisplayName falls back to the English token for an unknown spec
- a spec-name lookup that ran before the client was ready retries later
- every default spell list is reachable on a French client

### test_units.lua (12)

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
- LabelShow follows the link: a linked focus mirrors target's show (spec 2b)
- CopyStyling snapshots target label.style + show, keeps focus text (spec 2a/2b)

### test_schema.lua (11)

- Settings.Schema is assembled from the settings/* files
- Helpers.ValidateSchema reports zero malformed rows
- Every schema row has a string path and a known type
- Helpers.Resolve walks a dotted path into db.profile
- icons/castbar/label schema rows are unit-scoped and valid
- Helpers.FindSchema locates a row by path
- General exposes focus rows; unit-selector panels still filter them out
- label panel carries per-unit label rows; General no longer does
- every label-panel row's default is a member of its static values list
- PartitionUnitRows splits alwaysPerUnit rows from styled rows
- debug console stays session-only: no schema row targets it (§12.5)

### test_database.lua (20)

- DEFAULT_PROFILE carries the expected top-level shape
- OnInitialize built a live db with a merged profile
- Schema version lives in db.global, not the profile (KCD-20)
- MigrateProfile is a no-op at the current schema version
- MigrateProfile treats a missing version as v1 and walks forward to current
- MigrateProfile adopts a legacy per-profile dbVersion even past AceDB backfill (KCD-20)
- GetSpellList returns nil for an unseeded class/spec
- MigrateSpecKeys rewrites an English spec-name key to its numeric spec ID
- MigrateSpecKeys rewrites a LOCALISED spec-name key to its numeric spec ID (issue #8)
- MigrateSpecKeys is idempotent on an already-numeric profile
- MigrateSpecKeys leaves an unmappable key in place rather than dropping data
- MigrateSpecKeys does not clobber an existing numeric key on collision
- DEFAULT_PROFILE nests appearance under units.target / units.focus
- FoldLegacyUnits moves a legacy top-level config under units.target
- FoldLegacyUnits is idempotent and leaves a fresh v2 profile untouched
- DEFAULT_PROFILE ships an identical label.style for target and focus
- BackfillLabelStyle adds a missing label.style and preserves show/text
- BackfillLabelStyle is idempotent and leaves an existing style untouched
- BackfillLabelStyle key-fills a missing field onto an existing style, leaving other keys untouched
- DB label.style.color default matches the settings schema color row default (DB<->schema sync)

### test_color_shape.lua (20)

- the schema declares at least one colour row per colour-bearing panel
- every schema colour default is keyed, never positional
- every schema colour default carries all four channels
- every colour row declares hasAlpha, so the picker keeps its alpha channel
- the built profile stores colours keyed
- DEFAULT_PROFILE and the schema agree on every colour
- Util.Unpack reads the keyed shape
- Util.Unpack still reads a positional array, so a stray one renders rather than blanks
- no module reads a colour by positional index any more
- a pre-migration profile's array colours convert to the keyed shape
- the migration bumps the stored schema version so it runs once
- an already-keyed colour passes through the migration untouched
- the slash layer needs no colour codec now the shapes agree
- set and get round-trip a colour through the library with no translation
- every dropdown row's values is a keyed hash, never an array of records
- every static dropdown declares its order, so nothing silently alphabetises
- the anchor dropdown still reads top row, bottom row, sides, centre
- an LSM-backed row resolves its values at call time, never at declaration
- the valueGate hint explains WHY a gated dropdown value was rejected
- a rejected gated value carries the hint through the slash layer

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

### test_compat_api.lua (46)

- Compat._firstReturn tolerates a nil API (pre-12.0 client)
- Compat._firstReturn collapses a multi-return to position 1
- Compat._firstReturn forwards its arguments to the API
- Compat._firstReturn returns a nil first value even when later ones are set
- GetSpellCooldown reads the modern C_Spell info table
- GetSpellCooldown returns the inert tuple when the API yields no info
- GetSpellCooldown treats a missing isEnabled as enabled, missing isActive as inactive
- GetSpellCooldown coerces a non-boolean isActive to false
- GetSpellCooldown passes SECRET timings through without touching them
- GetSpellCooldown falls back to the deprecated global on a pre-12.0 client
- GetSpellCooldown's legacy path reports a zero duration as off cooldown
- GetSpellCooldown's legacy path refuses to compare a secret duration
- GetSpellCooldown returns the inert tuple when NO cooldown API exists
- GetSpellCooldownDuration hands back the opaque handle unchanged
- GetSpellCooldownDuration is nil on a client without the 12.0 API
- GetSpellTexture prefers C_Spell and falls back to the global
- GetSpellTexture is nil when neither API exists
- GetSpellInfo flattens the modern info table into the legacy tuple order
- GetSpellInfo is nil for an unknown spell, without falling through
- GetSpellInfo falls back to the deprecated global's multi-return
- GetSpellCharges flattens the modern charge table
- GetSpellCharges is nil for a spell without charges
- GetSpellCharges passes a SECRET charge count through untouched
- GetSpellCharges falls back to the deprecated global
- IsSpellAvailable rejects a non-number spell ID outright
- IsSpellAvailable is true when IsPlayerSpell says so
- IsSpellAvailable falls back to the spellbook for racials and professions
- IsSpellAvailable catches PET spells via the IsSpellKnown pet flag
- IsSpellAvailable is false for an unpicked talent choice-node sibling
- IsSpellUsable reads the SpellUsabilityInfo table form
- IsSpellUsable reads the two-boolean form some Midnight builds return
- IsSpellUsable normalises the legacy API's 1/nil into real booleans
- IsSpellUsable defaults to usable when no API is available
- GetCastingInfo builds a record from the CAST API's positions
- GetCastingInfo falls through to the channel shim when not casting
- GetCastingInfo is nil when the unit is neither casting nor channeling
- GetChannelInfo reads notInterruptible from position 7, spellID from 8
- GetChannelInfo is nil when the API itself is missing
- a FRIENDLY unit's cast is forced to uninterruptible regardless of the API
- a HOSTILE unit's raw notInterruptible flag is returned unchanged
- the friendly override applies to CHANNELS too, not just casts
- the cast record carries SECRET name/texture/flag/id without inspecting them
- the cast record attaches the plain-number CastingDuration object
- a channel record sources its duration from UnitChannelDuration
- a record survives a client with no duration API at all
- isChannel is a real boolean on both record paths

### test_debuglog.lua (13)

- DebugLog module loaded with its public API
- FormatPlain is clean, un-coloured, and well-shaped (§12.3)
- FormatColored carries the same fields as FormatPlain (no drift)
- debug flag defaults OFF and lives in State, never in SavedVariables (§12.5)
- SetEnabled is the single write seam and toggles State.debug
- SetEnabled brackets each session with a console line at both ends (§12.5)
- NS.Debug is a no-op when disabled (zero capture) and appends when enabled
- NS.Debug sanitizes secret args and never errors
- NS.Debug passes plain args through unchanged
- scrollbar + line-counter sync methods exist (§11)
- sync methods are a clean no-op before the window is built (§11)
- building the console + Add/Clear run the guarded sync headlessly (§11)
- console WINDOW visibility is decoupled from the capture flag (§12.5)

### test_debuglogsetup.lua (18)

- modules/DebugLog.lua has been deleted, not left beside the library
- the TOC lists core/DebugLogSetup.lua and no longer lists modules/DebugLog.lua
- FormatPlain renders <ts> | [<tag>] <msg> byte for byte
- FormatColored keeps the steel-blue stamp, tan tag and escaped pipe
- a nil tag renders as empty brackets rather than the string 'nil'
- the console registers under the same frame name modules/DebugLog.lua hardcoded
- the console title is the brand plus the library's own suffix
- the debug flag stays the addon's — the library never keeps a copy
- the enable ack renders the state word green, through the addon's tagged printer
- the disable ack renders the state word red
- enabling brackets the session and follows it with the host's [Init] summary
- NS.Debug is bound bare off the instance and takes no self
- NS.Debug is zero-cost when the flag is off
- a numeric format slot still renders correctly now the library stringifies every arg
- a secret argument renders as the shared sentinel and cannot raise
- with LibKa0s absent the stub answers every DebugLog member the addon calls
- the degraded stub still flips the flag and still prints the ack
- the degraded stub carries no copy of the line formatters

### test_icongrid_layout.lua (8)

- Layout math is published on the IconGrid module
- IconGrid:Layout method survives alongside the geometry table
- parseAnchor normalises modern, legacy, and CENTER tokens
- parseAnchor rejects invalid combos with the RIGHT/CENTER default
- parseGrow accepts perpendicular axes and defaults otherwise
- placeBlock RIGHT/CENTER geometry (primary left, block right, centred)
- placeBlock TOP/CENTER geometry (block above primary)
- placeBlock CENTER stacks both on the grid centre

### test_icongrid_apply.lua (6)

- Icon:Apply skips glow work when no plain state field moved
- Icon:Apply STILL re-arms the swipe when only the handle changed
- Icon:Apply redoes glow work when `ready` actually flips
- Icon:Apply redoes glow work when the cooldown ends
- Icon:Apply forced re-apply redoes state work even when nothing moved
- Icon:Apply keeps the charges badge live when charges are secret

### test_icongrid_visibility.lua (22)

- the visibility deciders are published for testing
- visibilityMode reads the addon-wide setting
- visibilityMode defaults to 'always' when the field is missing
- the cast bar reads the SAME visibility setting as the grid
- master enable off hides the grid in every mode
- a fresh profile with no enable field reads as enabled
- unlocked shows the grid even in a mode that would hide it
- locked restores the mode's own decision
- 'always' shows regardless of combat or casting
- an unrecognised mode falls back to always-visible
- 'in_combat' follows State.inCombat in both directions
- 'in_combat' ignores InCombatLockdown, which lags the regen events
- 'target_casting' shows while the unit casts and hides when it stops
- 'target_casting' counts a CHANNEL as casting
- 'target_casting' hides when the unit doesn't exist
- 'target_casting' does NOT filter on hostility, unlike the interruptible mode
- 'target_casting_interruptible' shows for any HOSTILE cast
- 'target_casting_interruptible' hides for a FRIENDLY cast
- 'target_casting_interruptible' hides when nothing is being cast
- each unit's decision is made against its OWN unit token
- instanceCasting truth-tests the cast name without ever reading it
- instanceCasting is false for a unit that doesn't exist

### test_icongrid_render.lua (21)

- the render helpers are published for testing
- SafeUnpackColor reads both the array and hash colour shapes
- SafeUnpackColor honours the caller's cooldown-tint fallback
- SafeUnpackColor falls back to opaque white with no fallback given
- UnpackGlowColor reads a configured array colour
- UnpackGlowColor falls back to the shipped yellow glow for a non-table
- UnpackGlowColor fills missing channels rather than returning nils
- the 'always' trigger glows unconditionally
- the 'never' trigger and any unknown token keep the glow off
- 'target_casting' asks the INSTANCE whether its unit is casting
- 'target_casting' is false for an instance with no predicate yet
- 'target_casting_interruptible' glows for ANY hostile cast
- 'target_casting_interruptible' does NOT glow for a friendly cast
- 'target_casting_interruptible' resolves per-unit, defaulting to target
- PlainStateMoved treats a first render as a change
- PlainStateMoved is false when nothing plain moved
- PlainStateMoved fires on a ready or isActive flip
- PlainStateMoved watches handle PRESENCE, not handle identity
- PlainStateMoved watches the charge timer's presence independently
- PlainStateMoved deliberately IGNORES charges, unlike the cooldown gates
- PlainStateMoved never compares a secret charge value

### test_icongrid_curves.lua (12)

- each unit gets its own curve pair
- an unlinked focus builds its curve from ITS OWN readyAlpha
- an unlinked focus builds its tint curve from ITS OWN cooldownTint
- a LINKED focus resolves to target's values
- CurvesFor never falls back to another unit's curves
- rebuilding with an unchanged config reuses the same curve objects
- an unrelated icons edit does NOT recreate the curves
- a readyAlpha edit DOES recreate the curve
- a cooldownAlpha edit DOES recreate the curve
- a cooldownTint edit DOES recreate the curve
- one unit's rebuild does not disturb the other's cached curves
- CurveSignature covers exactly the three curve-shaping fields

### test_icongrid_curve_link.lua (6)

- the mock's curve evaluation actually reads control points
- a LINKED focus renders with target's cooldown alpha
- unlinking focus via the `units` section re-renders with ITS OWN alpha
- re-linking focus via the `units` section restores target's alpha
- unlinking picks up focus's own cooldown TINT, not target's
- a per-unit enable toggle also refreshes curves

### test_icongrid_buildlist.lua (20)

- BuildActiveList renders one icon per enabled entry
- BuildActiveList preserves the saved list's ORDER
- the first entry becomes the primary icon the cast bar anchors to
- BuildActiveList replaces the previous list rather than appending to it
- an empty list produces an empty grid, not an error
- a disabled entry is skipped
- an entry with no enabled field is treated as enabled
- an entry with no spellID is skipped rather than acquiring a nil-keyed icon
- a spell the player cannot currently cast is not rendered
- a spell missing from the client's spell DB is not rendered
- a pet spell appears only while its pet is out
- a duplicate spellID is skipped, keeping the pool 1:1 with the ID
- the FIRST occurrence of a duplicated spellID is the one kept
- a duplicate that is DISABLED doesn't suppress the enabled original
- a duplicate is reported to the debug console when logging is on
- a SECRET icon texture is skipped instead of erroring the whole build
- a plain texture IS applied to the icon widget
- a class+spec with no saved list renders nothing and creates no entry
- BuildActiveList caches the unit's resolved icon config on the instance
- each unit builds from its own resolved config

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

### test_unitlabel_apply.lua (21)

- Apply writes the unit's own label text
- Apply writes an empty string rather than nil for a cleared label
- label TEXT stays per-unit even when the units are linked
- Apply pushes the configured size and colour onto the FontString
- Apply always resolves a non-nil font path
- Apply falls back to a 14pt outline for a style with no size or flags
- Apply applies the configured horizontal justification
- Apply defaults justification to CENTER
- a LINKED focus renders target's styling but its own text
- Apply positions the label against its chosen ATTACH frame
- Apply parents the label to the ICON GRID even when attached to the cast bar
- Apply anchors POSITION to the cast bar while parenting to the grid
- re-applying never stacks anchors on the holder frame
- the label shows when the unit is enabled and show is on
- turning the label's show off hides it
- disabling the unit hides its label regardless of the show flag
- the master enable gates the label too
- a LINKED focus mirrors target's show flag (spec 2b)
- EnsureFrame builds the holder once and reuses it
- target and focus each get their own label widgets
- ApplyAll renders every unit in one pass

### test_castbar.lua (7)

- Castbar exposes the pure AutoSizeLong helper
- AutoSizeLong copies the grid extent verbatim when scales match
- AutoSizeLong shrinks the bar when the grid is scaled down (master scale < 1)
- AutoSizeLong grows the bar when the grid is scaled up (master scale > 1)
- AutoSizeLong honors the bar's own effective scale
- AutoSizeLong returns the fallback for a zero/nil grid extent
- AutoSizeLong treats a zero/nil scale as 1 (never divides by zero)

### test_castbar_helpers.lua (27)

- the Castbar pure helpers are published for testing
- UnpackColor reads an array-style colour
- UnpackColor reads a hash-style colour
- UnpackColor uses the CALLER's fallback for a nil colour
- UnpackColor falls back to opaque white when the caller gives no fallback
- UnpackColor defaults a missing alpha to fully opaque
- TruncateName leaves a name shorter than the cap alone
- TruncateName leaves a name EXACTLY at the cap alone
- TruncateName clips and appends an ellipsis past the cap
- TruncateName treats 0 and nil as 'no truncation'
- TruncateName treats a negative cap as 'no truncation'
- TruncateName returns an empty string for a nil name
- TruncateName passes a SECRET name through without measuring it
- StateConfig returns the configured per-state table when present
- StateConfig falls back when the state key is missing
- StateConfig rejects a non-table value stored under the state key
- the interruptible fallback is gold with no border, the uninterruptible red with one
- both state fallbacks carry every field the reskin path reads
- ToSetPoint maps every schema anchor token to a real SetPoint token
- ToSetPoint defaults a nil anchor to CENTER
- ToSetPoint passes an already-valid SetPoint token straight through
- FetchStatusBarTexture returns the LSM path when the key resolves
- FetchStatusBarTexture degrades to a client-shipped path for an unknown key
- FetchBorderTexture degrades to a client-shipped border
- FetchFont always yields a usable font path
- AutoSizeLong matches on-screen extents for frames at different scales
- AutoSizeLong accounts for scale INHERITED from a parent frame

### test_castbar_frame.lua (36)

- EnsureFrame builds the full widget stack once and reuses it
- EnsureFrame creates BOTH state bars and both backgrounds
- EnsureFrame parents the state bars inside the bar container
- EnsureFrame seeds both bars to an empty 0..1 range
- target and focus get separate frames, not one shared bar
- GetCastbarFrame never creates an instance for an unknown unit
- Start renders the cast name into the bar's FontString
- Start applies the user's name truncation
- Start blanks the name entirely when showName is off
- Start pushes the cast's icon texture onto the icon widget
- a CAST fills the bar 0 -> total
- a CHANNEL drains the bar total -> 0
- both stacked bars carry identical values so the alpha switch is seamless
- Start shows the frame and arms the per-frame OnUpdate
- Start refuses a record with no duration object rather than faking one
- the OnUpdate tick advances the bar as the cast progresses
- the OnUpdate tick writes the remaining/total countdown when showTime is on
- the OnUpdate tick leaves the countdown alone when showTime is off
- the OnUpdate script disarms itself once the cast record is gone
- an INTERRUPTIBLE cast shows the interruptible widgets and hides the others
- an UNINTERRUPTIBLE cast flips the whole stack the other way
- the alpha switch never branches on notInterruptible in Lua
- the no-cast state falls back to interruptible visuals
- the uninterruptible warning border is on and the interruptible one off
- Stop clears the cast, empties both bars and disarms the animation
- Stop HIDES the bar while locked
- Stop leaves a PREVIEW on screen while unlocked, so it stays draggable
- the preview resets the bar range so it doesn't inherit the last cast's total
- Stop is safe before the frame has ever been built
- a cast starting out of combat is suppressed in the in_combat mode
- the same cast shows once combat is flagged
- disabling the cast bar for a unit keeps its frame hidden through a cast
- the interruptible mode masks the bar's alpha from the SECRET flag
- an interruptible cast in that mode stays fully visible
- ApplyAnchor in FREE mode restores the saved anchor against UIParent
- re-anchoring never stacks a second point on the frame

### test_castbar_skin.lua (20)

- StructureSignature is stable for identical inputs
- StructureSignature moves when a structural field moves
- StructureSignature moves when the RESOLVED size moves
- StructureSignature ignores pure colour fields
- StructureSignature DOES move for border size/texture
- Reskin stamps a structure signature on the instance
- a structural config change re-sizes the frame
- a SECOND structural change still lands (the guard is not one-shot)
- re-skinning with no config change leaves the signature untouched
- a colour-only change does NOT move the structure signature
- a colour-only change still repaints the bar
- force rebuilds the geometry even when the signature matches
- Reskin is safe before the frame has ever been built
- target and focus carry independent structure signatures
- ResolveBarSize floors the long and thick axes
- ResolveBarSize returns the configured size when auto-size is off
- ResolveBarSize leaves thickness alone in vertical orientation
- Reskin survived the peel as a method on the Castbar module
- the skin sibling reads its helpers off the module, not a private copy
- modules/Castbar.lua sits under the 1500-LOC hard cap (layout-§1)

### test_cooldowns.lua (11)

- SPELL_UPDATE_* burst coalesces to one Refresh per frame
- Refresh logs one coalesced line only when a spell changed
- Refresh coalesces multiple simultaneous changes into ONE line
- Refresh does not log when only the cooldown handle identity changed
- Refresh STILL emits SPELL_STATE when the cooldown handle changed
- Refresh logs a genuine on-cooldown -> ready transition
- Rebuild summary names the class/spec IDs and every watched + skipped spell
- Rebuild summary distinguishes an empty watched set from an empty skipped set
- Rebuild summary re-logs when only the SKIPPED set changes
- Rebuild summary logs on a material change and is silent on a repeat
- Refresh logs nothing when no spell changed

### test_cooldowns_gates.lua (22)

- both gates are published for testing
- both gates treat a missing previous state as a change (first poll)
- both gates are silent when nothing at all moved
- both gates fire on a ready flip — the transition that matters most
- both gates fire on an isActive flip
- both gates fire when a cooldown handle APPEARS
- both gates fire when a cooldown handle DISAPPEARS
- both gates fire when a charge-recharge timer appears
- StateChanged fires on a NEW handle for the same cooldown
- MaterialChange ignores a new handle for the same cooldown
- MaterialChange ignores a new CHARGE handle too
- both gates ignore charges that stayed nil
- both gates fire on a plain charge count that moved
- both gates ignore a plain charge count that held still
- both gates fire when charges appear from nothing
- StateChanged EMITS conservatively when either charge count is secret
- MaterialChange stays QUIET when either charge count is secret
- one secret side is enough to trigger each gate's secret rule
- a secret charge count never blocks a real ready/isActive transition
- neither gate ever reads a secret charge value itself
- Cooldowns.MasterEnabled defaults to true when the field is absent
- Cooldowns.MasterEnabled is false only for an explicit false

### test_settings_log.lua (5)

- Helpers.Set logs one debounced [Set] line with the settled value
- Helpers.Set formats an RGBA table compactly
- ResetIconPosition restores units.target.anchors.icons to the default (Task 8 fix)
- ResetAll (via ResetAllPositions) restores both units' icons+castbar anchors to default (resetall bug fix)
- ResetAll (via RestoreUnitLinks) restores each unit's link flag to default (link reset bug fix)

### test_settings_spells.lua (4)

- Spells editor seeds its selection to the player's own class and spec
- Spells editor selection follows an in-game spec change (dropdown regression)
- Spells editor spec change also tracks a class it can render
- Spells editor exposes specs in Blizzard's order, not numeric order

### test_settings_widgets.lua (20)

- the settings helpers are published for testing
- SortedKeys returns a deterministic ordering
- SortedKeys returns an empty list for a nil or non-table input
- SpecOrder lists specs in Blizzard's order, not numeric order
- SpecOrder falls back to sorted numeric keys when the client can't be queried
- SpecOrder only offers specs the addon ships defaults for
- SpecOrder lists EVERY spec the defaults ship for that class
- SpecOrder is empty for a class with no shipped defaults
- Druid's four specs all survive the ordering
- ValidateSpellInput accepts a numeric spell ID and resolves its name
- ValidateSpellInput accepts an ID typed as a string
- ValidateSpellInput rejects empty and nil input
- ValidateSpellInput rejects an ID the client doesn't know
- ValidateSpellInput resolves a spell NAME to its numeric ID
- ValidateSpellInput rejects a name that resolves to no spell
- ValidateSpellInput refuses a name whose lookup yields no ID
- ClassDisplayName spaces the two-word class tokens
- TitleCaseToken lower-cases everything after the first letter
- TitleCaseToken returns an empty string for nil rather than erroring
- every shipped class token produces a non-empty display name

### test_options_panel.lua (22)

- NS.Settings.Helpers IS the library instance, decorated in place
- the host ships no widget maker, flow engine or layout constant of its own
- a bool row renders a checkbox labelled from the row
- a number row renders a slider carrying the row's range
- a string row renders a dropdown listing the KEYED options in declared order
- a colour row renders a picker with alpha and the decoded colour
- ticking a checkbox writes through the addon's single write seam
- a checkbox write fires CONFIG_CHANGED with the row's section
- dragging a slider commits on mouse-up
- choosing a dropdown option stores the option KEY, never its index
- confirming a colour stores the keyed shape the modules read
- an external write re-syncs an open widget through its refresher
- releasing a page's widgets drops that page's refreshers
- InlinePair puts both caller-supplied widgets in ONE row
- SessionToggle adapts this addon's argument order onto the library's
- a session toggle never becomes a saved setting
- the Profiles page is vetoed from a global reset
- a global reset also clears the state no schema row owns
- with LibKa0s absent the schema still loads COMPLETE
- the degraded stub keeps the global reset real
- the degraded stub opens no panel and says so once
- the degraded stub carries no widget maker or layout constant

### test_settings_refreshers.lua (5)

- rendering rows registers refreshers
- ClearScroll empties the refresher registry
- a clear-and-rebuild cycle does not grow the registry
- RefreshAllPanels never runs a refresher from a cleared render
- ClearScroll is safe on a ctx that never rendered

### test_flow_traces.lua (1)

- OnProfileChanged logs a [Profile] line

### test_version.lua (3)

- `version` is a registered COMMANDS verb (slash-commands-§3)
- `/kcd version` prints v<version> on exactly one line
- `version` falls back to the NS.VERSION stamp when TOC metadata is absent

### test_slash_style.lua (10)

- /kcd help emits no line ending in ':' (slash-commands-§4)
- bare /kcd emits no line ending in ':'
- /kcd debug sub-header emits no line ending in ':'
- /kcd spells sub-header emits no line ending in ':'
- every COMMANDS verb description is free of a trailing ':'
- an unknown verb's error line does not end in ':'
- /kcd debug spells emits no line ending in ':'
- /kcd debug castbar emits no line ending in ':'
- /kcd debug interrupt emits no line ending in ':'
- no addon source passes a ':'-terminated literal to a printer

### test_slash.lua (24)

- the dispatcher instance is built from LibKa0s-Slash-1.0
- NS.COMMANDS stays the host's, as ordered positional triples
- every COMMANDS handler takes (rest), not (self, rest)
- an unknown verb names it and then prints the help index
- only the verb is lowercased — a schema path keeps its case
- the `options` alias still reaches `config`
- the help header now carries the em dash the standard mandates
- a help row is the one shared formatter, two-space indented
- the landing page renders the SAME rows, un-indented
- the panel no longer carries a second command-row formatter
- list groups by the row's panel, in the addon's declared page order
- get echoes the shared key = value pair
- set clamps out of range and echoes what was actually STORED
- set routes through the host's single write seam
- a colour round-trips through the library with no host translation
- a colour given in 0-255 rescales jointly
- an unknown path says so rather than writing anything
- reset takes a PATH and resets exactly that one row
- the old page-shaped reset names its replacement instead of going quiet
- `reset spells` names the verb its database rebuild moved to
- the spell-database rebuild survives, under its new verb
- resetall keeps its four-part host semantics rather than becoming CliResetAll
- with LibKa0s absent /kcd still answers and host verbs still work
- the degraded stub carries no copy of the row formatter or the parser

### test_perfsetup.lua (16)

- NS.Perf is the library instance, with the hot-path gate as a plain field
- the capture ring is declared in the TOC as a second SavedVariables global
- every bracket call site reads the gate through a load-time upvalue
- every declared bucket is reached by a real bracket
- the declared bucket list and the bracketed call sites agree exactly
- nesting is declared for every bucket that runs inside another
- instrumentation is inert when capture is off
- the show decisions consult Perf.suspended as step 0, at the source
- suspend releases the per-unit dispatch frames AceEvent cannot reach
- enabling a unit while suspended does not re-register its frames mid-capture
- resume restores from CURRENT state, not from a snapshot
- the suspended flag is session-only and never persisted
- `perf` is a host verb in NS.COMMANDS, not registered by the library
- a bare /kcd perf answers through the addon's tagged printer
- with LibKa0s absent the probe stub answers every member the addon calls
- with LibKa0s absent the bracketed paths still run

### test_list_mode.lua (5)

- --list emits a generated '# Test Cases' inventory header + regen note
- --list stdout is inventory-only, no run output
- --list emits CRLF line endings (matches the repo eol=crlf policy)
- --list per-suite header counts match their bullet counts
- --list Totals row equals the grand total of bullets

## Totals

| Suite | Cases |
| --- | --- |
| test_util.lua | 13 |
| test_coresetup.lua | 16 |
| test_util_anchor.lua | 26 |
| test_constants.lua | 22 |
| test_state.lua | 23 |
| test_locale.lua | 9 |
| test_units.lua | 12 |
| test_schema.lua | 11 |
| test_database.lua | 20 |
| test_color_shape.lua | 20 |
| test_bus.lua | 4 |
| test_compat.lua | 5 |
| test_compat_api.lua | 46 |
| test_debuglog.lua | 13 |
| test_debuglogsetup.lua | 18 |
| test_icongrid_layout.lua | 8 |
| test_icongrid_apply.lua | 6 |
| test_icongrid_visibility.lua | 22 |
| test_icongrid_render.lua | 21 |
| test_icongrid_curves.lua | 12 |
| test_icongrid_curve_link.lua | 6 |
| test_icongrid_buildlist.lua | 20 |
| test_lifecycle.lua | 4 |
| test_unitlabel.lua | 4 |
| test_unitlabel_apply.lua | 21 |
| test_castbar.lua | 7 |
| test_castbar_helpers.lua | 27 |
| test_castbar_frame.lua | 36 |
| test_castbar_skin.lua | 20 |
| test_cooldowns.lua | 11 |
| test_cooldowns_gates.lua | 22 |
| test_settings_log.lua | 5 |
| test_settings_spells.lua | 4 |
| test_settings_widgets.lua | 20 |
| test_options_panel.lua | 22 |
| test_settings_refreshers.lua | 5 |
| test_flow_traces.lua | 1 |
| test_version.lua | 3 |
| test_slash_style.lua | 10 |
| test_slash.lua | 24 |
| test_perfsetup.lua | 16 |
| test_list_mode.lua | 5 |
| **Total** | **620** |
