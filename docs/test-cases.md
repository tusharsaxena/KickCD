# Test Cases

The full inventory of every headless test case in this repo, grouped by the suite file it
lives in. The `## Totals` table below is the **authoritative pass count** — the README test
badge and any count quoted in the docs must agree with it.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.

### test_harness.lua (7)

- harness: the runner is on the shared kit and reports its revision
- harness: the addon's load list is DERIVED from the TOC, in TOC order (testing-§9)
- harness: every derived addon path exists on disk
- harness: no libs/ path leaked into the derived addon list
- harness: the explicit LibKa0s list matches LibKa0s.xml, in XML order (anti-patterns #48)
- harness: every LibKa0s file the runner loads exists on disk
- harness: the libraries load BEFORE the addon's own files

### test_libka0s.lua (46)

- libka0s: every vendored major registers under LibStub
- libka0s: MODULES names every file of every major, at a positive integer minor
- core: the published seams ARE the library's, not a lookalike
- core: the printer emits <prefix><space><body> as one line
- core: the prefix is read at CALL time, not captured at load
- core: the sink is the Lua global print, so the harness can see chat output
- debuglog: the console is the library's instance, and the sink is bound bare
- debuglog: the descriptor keeps the frame globals the old console used
- debuglog: the composed window title is unchanged
- debuglog: the flag stays the addon's — the library never keeps a copy
- debuglog: the [Init] summary is the addon's, reached through the descriptor
- debuglog: the console's user-visible strings resolve to prose, not to their own keys
- debuglog: the gated sink survives a format its arguments cannot satisfy (WG-22)
- options: Settings.Helpers IS the library instance, decorated in place
- options: the host's data seams survived the move onto the instance
- options: the host's RestoreAllDefaults deliberately overrides the library's
- options: a panel write takes the addon's single write seam
- options: no layout constant is restated in this addon's own source
- options: the panel body still builds on the NEXT frame, not inside OnShow
- slash: the help header is the library's, with this addon's alias sentence
- slash: a help row is the one command-row formatter, indented two spaces
- slash: the landing page renders the SAME rows, un-indented (convergence #2)
- slash: the landing page draws those rows and nothing of its own
- slash: `list` renders through the shared key/value formatter
- slash: a number row still renders through its schema `fmt`
- slash: `toggle` survived the adoption, through the descriptor's parse adapter
- slash: the descriptor's L overrides exactly one string and nothing else
- slash: every user-visible CLI string resolves to prose, not to its own key
- degraded: the addon loads with LibKa0s absent
- degraded: the cause clause is published on BOTH paths
- degraded: the printer announces the absence exactly ONCE, then prints normally
- degraded: the fallback printer still degrades a secret in place
- degraded: every DebugLog member the addon calls still answers
- degraded: the console stub copies NO library formatter
- degraded: the schema loads WHOLE with the options library absent (options-ui-§1)
- degraded: the settings stub carries no widget maker and no layout constant
- degraded: the settings panel explains itself once at load and once per config
- degraded: `/wg debug on` still moves the flag and explains the missing window ONCE
- parity: the Core seam's whole namespace surface survives the library's absence
- parity: the DebugLog stub carries the whole live surface
- parity: the Slash stub carries the whole live surface
- parity: the Options helpers stub carries the whole live surface
- libka0s: the L-trap matcher flags the table and the `or` spelling, not the `and` one
- libka0s: no seam file hands a descriptor this addon's locale table (the L trap)
- libka0s: Core has no STRINGS and reads no descriptor L (tripwire)
- libka0s: Options reads no descriptor L (tripwire)

### test_util.lua (26)

- util: SafeToString handles nil / booleans / strings / numbers
- util: SafeToString yields <secret> for a value that raises in concat
- util: IsConcatSafe true for scalars, false for a raising value
- util: NS.Print prepends the [WG] prefix and stringifies each arg
- util: NS.Print degrades a secret-like arg in place, never raising
- util: Windows.Save/Restore round-trips a frame point through db.global (WG-26)
- util: Windows.Restore is a no-op when nothing is saved (WG-26)
- util: SafeToString renders a negative and a fractional number
- util: SafeToString degrades a function and a coroutine
- util: IsConcatSafe reports a boolean as unsafe
- util: IsConcatSafe reports nil as safe (concat of an empty table)
- util: NS.Print with no arguments still prints the prefix
- util: NS.Print joins several arguments with single spaces
- util: NS.Print stringifies nil and boolean arguments in place
- util: PointOf reads a frame's primary anchor
- util: PointOf defaults relPoint to the point and offsets to zero
- util: PointOf returns nil for a frame with no anchor yet
- util: PointOf returns nil for nil or a non-frame
- util: Save is a no-op before the db is ready
- util: Save skips a frame that has no anchor
- util: Save overwrites a previously stored point
- util: windows are stored under independent names
- util: Restore returns false for a frame that cannot be anchored
- util: Restore is a no-op before the db is ready
- util: Restore clears existing anchors before applying the saved one
- util: a Save/Restore round trip survives through the real frame stub

### test_compat.lua (17)

- compat: GetSpellName returns the C_Spell name
- compat: GetSpellTexture is non-nil (caller supplies default)
- compat: GetSpellLink returns a hyperlink for the spell
- compat: IsSpellKnown true when learned
- compat: IsSpellKnown false when not learned
- compat: GetActivityInfoTable passes the table through
- compat: GetSpellName falls back to the legacy GetSpellInfo global
- compat: GetSpellName falls through when the modern API returns nil
- compat: GetSpellName returns nil when no API exists at all
- compat: GetSpellTexture falls back to the legacy global
- compat: GetSpellTexture returns nil with no API (the caller supplies a default)
- compat: GetSpellLink returns nil with no API (the caller renders plain text)
- compat: IsSpellKnown normalizes to a plain boolean
- compat: IsSpellKnown returns false when the API is missing
- compat: GetActivityInfoTable returns nil for an unknown activity
- compat: GetActivityInfoTable returns nil when C_LFGList is absent
- compat: Compat is the sole namespace the addon reads variant APIs through

### test_database.lua (9)

- database: fresh DB lands at schemaVersion 1
- database: RunMigrations is idempotent
- database: RunMigrations re-seeds a missing schemaVersion
- database: BuildDefaults seeds global.schemaVersion from NS.SCHEMA_VERSION
- database: RunMigrations before the db exists is a no-op
- database: an older saved DB is stepped up to the current version
- database: a version move is logged, a no-op migration is silent (debug-logging-§8)
- database: migrations run before any profile read (OnInitialize order)
- database: the profile is untouched by a migration pass

### test_settings.lua (42)

- settings: BuildDefaults threads profile + global defaults
- settings: defaults source from NS.C (defaults/Profile.lua, WG-24)
- settings: BuildDefaults seeds an empty global.windows table (WG-26)
- settings: debug is not a persisted schema row (WG-12)
- settings: ValidateSchema reports zero errors
- settings: Get/Set round-trips through db.profile
- settings: RestoreAllDefaults resets a changed value
- settings: RestoreAllDefaults prunes orphaned profile keys (F1)
- settings: RestoreAllDefaults deep-copies table defaults (F2)
- settings: RestoreAllDefaults skips per-row onChange (F3)
- settings: enabled=false onChange wipes capture
- settings: every schema row declares the fields the panel and CLI need
- settings: schema paths are unique
- settings: every schema row carries a tooltip
- settings: every number row declares min, max and step
- settings: ValidateSchema counts each defect on a broken row
- settings: ValidateSchema reports a non-table row
- settings: a broken row does not stop the panel registering
- settings: BuildDefaults nests dotted paths into real subtables
- settings: BuildDefaults covers every schema row
- settings: BuildDefaults deep-copies table defaults
- settings: BuildDefaults is a fresh table each call
- settings: Get returns nil before the db exists
- settings: Set before the db exists is a harmless no-op
- settings: a write creates the intermediate tables it walks through
- settings: Get on an unknown deep path returns nil and creates no table
- settings: Resolve replaces a non-table intermediate
- settings: RawSet writes without firing onChange
- settings: Set skipOnChange suppresses the side effect
- settings: a throwing onChange is caught and reported, not propagated
- settings: Set on a path with no schema row still writes
- settings: FindSchema matches on the exact path
- settings: RestoreAllDefaults restores every schema row
- settings: RestoreAllDefaults leaves db.global untouched
- settings: RefreshAll runs every refresher on the open page, in registration order
- settings: a throwing refresher does not abort the sweep
- settings: a hidden page is not refreshed — it is flagged dirty (options-ui-§11)
- settings: Set skipRefresh suppresses the widget re-sync
- settings: RestoreAllDefaults refreshes once, not once per row
- settings: EnsureResetPopup is idempotent
- settings: the reset dialog is a blocking, escapable confirmation
- settings: accepting the reset dialog acknowledges in chat

### test_slash.lua (43)

- slash: COMMANDS has a standalone version verb (WG-29)
- slash: /wg version prints [WG] v<version> on its own line (WG-29)
- slash: help header has no trailing colon (WG-19)
- slash: a bare /wg prints the help index
- slash: whitespace-only input is treated as bare /wg
- slash: nil input is tolerated
- slash: help lists one row per COMMANDS entry, plus the header
- slash: every COMMANDS row carries a verb, a description and a handler
- slash: an unknown verb says so and then prints the help index
- slash: the verb is case-insensitive
- slash: only the verb is lower-cased — the argument keeps its case
- slash: /wg version reads the version from TOC metadata
- slash: /wg version falls back to the in-code constant
- slash: /wg list prints every schema row
- slash: /wg list groups rows under their section header
- slash: /wg list shows current values, not defaults
- slash: /wg get prints key = value
- slash: /wg get with no path prints usage
- slash: /wg get reports an unknown path rather than printing nil
- slash: /wg get formats a number through the schema fmt
- slash: /wg set with no path prints usage
- slash: /wg set reports an unknown path
- slash: /wg set accepts 'true' as true
- slash: /wg set accepts '1' as true
- slash: /wg set accepts 'on' as true
- slash: /wg set accepts 'yes' as true
- slash: /wg set accepts 'false' as false
- slash: /wg set accepts '0' as false
- slash: /wg set accepts 'off' as false
- slash: /wg set accepts 'no' as false
- slash: /wg set bool words are case-insensitive
- slash: /wg set toggle flips the current value
- slash: /wg set rejects a non-boolean word and lists the accepted ones
- slash: /wg set writes a number
- slash: /wg set rejects a non-numeric value for a number row
- slash: /wg set clamps a number below the schema min
- slash: /wg set clamps a number above the schema max
- slash: /wg set echoes the STORED value back, not the typed one
- slash: /wg set with a missing value is rejected, not silently applied
- slash: /wg set enabled false runs the master-switch onChange
- slash: /wg debug with a bad subcommand prints both usage lines
- slash: /wg debug (bare) toggles the console window's visibility
- slash: /wg debug on does not open the window

### test_labels.lua (31)

- labels: GetGroupTypeLabel Mythic+
- labels: GetGroupTypeLabel Dungeon by categoryID
- labels: GetGroupTypeLabel Raid by player count
- labels: GetGroupTypeLabel fallback Group
- labels: GetPlaystyleLabel prefers playstyleString
- labels: GetPlaystyleLabel enum lookup when string empty
- teleport: GetTeleportSpell picks the known spell from a list
- teleport: GetTeleportSpell returns first + false when none known
- teleport: GetTeleportSpell nil when no mapping
- labels: GetGroupTypeLabel Raid (Current)
- labels: GetGroupTypeLabel Heroic Raid
- labels: GetGroupTypeLabel PvP by categoryID 2
- labels: GetGroupTypeLabel Dungeon by a small player count
- labels: GetGroupTypeLabel treats exactly 10 players as a Raid
- labels: GetGroupTypeLabel treats 9 players as a Dungeon
- labels: GetGroupTypeLabel falls back to Group at zero players
- labels: Mythic+ outranks every other signal
- labels: the raid flags outrank categoryID
- labels: categoryID outranks the player count
- labels: every playstyle enum maps to its Blizzard-localized wording
- labels: playstyle None (0) has no label
- labels: an unmapped playstyle enum yields an empty label, not nil
- labels: playstyleString wins even when the enum is also set
- labels: a nil playstyleString falls through to the enum
- teleport: a scalar mapping returns (spellID, known) directly
- teleport: a scalar mapping the player has not learned reports known=false
- teleport: mapID takes precedence over activityID
- teleport: activityID is the fallback when the mapID is unmapped
- teleport: a nil mapID and nil activityID resolve to nothing
- teleport: the FIRST known spell in a candidate list wins
- teleport: the shipped mapping table is keyed by numbers only

### test_capture.lua (29)

- capture: inviteaccepted prefers FRESH when both have mapID
- capture: inviteaccepted falls back to QUEUED when fresh lacks mapID
- capture: enabled queues so pendingInfo survives a nil fresh fetch
- capture: master switch off means nothing is queued
- capture: master switch off blocks the inviteaccepted fresh fetch too
- capture: CaptureGroupInfo maps the search-result fields
- capture: CaptureGroupInfo maps the activity fields
- capture: CaptureGroupInfo returns nil when the search result is gone
- capture: missing search-result fields fall back to safe defaults
- capture: an unknown activity leaves the activity fields at their defaults
- capture: no activityIDs at all leaves activityID nil
- capture: fullName falls back to the activity name
- capture: the legacy `playstyle` field is used when generalPlaystyle is absent
- capture: the raid flags are carried through
- capture: applications are matched to captures in FIFO order
- capture: an 'invited' status changes nothing — it waits for the accept
- capture: an unrecognized status is ignored
- capture: accepting clears the queue so a stale apply can't resurface
- capture: 'applied' with nothing queued is a harmless no-op
- capture: accepting with no data anywhere leaves pendingInfo nil
- capture: re-enabling the master switch resumes capturing
- capture: inviteaccepted resolves the searchResultID via GetApplicationInfo
- capture: GetApplicationInfo may return a table; the id is read off it
- capture: an unmapped application falls back to treating appID as the id
- capture: a missing GetApplicationInfo degrades to the appID path
- capture: a raising GetApplicationInfo is caught and falls back
- capture: a search field holding false takes the default, not the false
- capture: an activity field holding false takes the default, not the false
- capture: a stored zero survives the defaults, because 0 is truthy in Lua

### test_notify.lua (44)

- notify: no pendingInfo schedules no timer
- notify: out of a group schedules no timer even with pendingInfo
- notify: in a group with pendingInfo schedules exactly one timer
- notify: the scheduled delay comes from notify.delay
- notify: firing the timer prints the summary and clears the handle
- notify: a second call for the SAME pendingInfo schedules nothing more
- notify: both event paths together fire the summary exactly once
- notify: a NEW pendingInfo is eligible to fire again
- notify: a re-fire cancels the in-flight timer so two can't race
- notify: a callback whose pendingInfo was replaced mid-flight prints nothing
- notify: WipeCapture cancels an in-flight notify so it never fires
- notify: WipeCapture clears pendingInfo
- notify: WipeCapture re-arms a later capture (notifiedFor is cleared)
- notify: the master-switch off-flip wipes an in-flight capture (Schema onChange)
- notify: autoShow on opens the popup when the timer fires
- notify: autoShow off prints the summary but never builds the popup
- notify: autoShow is read at SCHEDULE time, not at fire time
- notify: notify.enabled off prints nothing at all
- notify: no pendingInfo prints nothing
- notify: the default summary carries every row
- notify: the Group row always prints, even with every toggle off
- notify: notify.showInstance off drops the Instance: row
- notify: notify.showInstance on keeps the Instance: row
- notify: notify.showType off drops the Type: row
- notify: notify.showType on keeps the Type: row
- notify: notify.showLeader off drops the Leader: row
- notify: notify.showLeader on keeps the Leader: row
- notify: notify.showPlaystyle off drops the Playstyle: row
- notify: notify.showPlaystyle on keeps the Playstyle: row
- notify: notify.showTeleport off drops the Teleport: row
- notify: notify.showTeleport on keeps the Teleport: row
- notify: notify.showClickLink off drops the [Click here to view details] row
- notify: notify.showClickLink on keeps the [Click here to view details] row
- notify: the Instance row falls back to Unknown when fullName is empty
- notify: the Type row prefers shortName over the derived label
- notify: the Type row derives the label when shortName is empty
- notify: the Playstyle row is skipped when the label resolves empty
- notify: the Teleport row is skipped when the map has no teleport spell
- notify: an unlearned teleport is tagged '(not learned)'
- notify: a learned teleport carries no '(not learned)' tag
- notify: every summary line carries the shared [WG] prefix
- notify: a secret-like title degrades in place instead of raising
- notify: the Leader row still prints when leaderName is nil
- notify: Playstyle and Teleport drop their rows while Leader keeps its own

### test_frame.lua (32)

- frame: nothing is created at addon load
- frame: the first ShowFrame builds and shows the popup
- frame: buildFrame is one-shot — a second show reuses the same frame
- frame: ESC-to-close is registered lazily, on the first show only
- frame: the Close button hides the popup
- frame: fields render the pending capture
- frame: with no pendingInfo every field reads 'No data'
- frame: the no-data playstyle renders the dim em-dash placeholder
- frame: an empty fullName falls back to Unknown
- frame: the Type field prefers shortName
- frame: the Type field derives a label when shortName is empty
- frame: the Playstyle field prefers the server-rendered string
- frame: the Playstyle field falls back to the enum label
- frame: playstyle None (0) renders the dim em-dash, not an empty row
- frame: re-showing with a new capture re-renders the fields
- frame: the teleport button registers exactly one click edge, so one press is one cast
- frame: a known teleport wires the secure /cast macro
- frame: a known teleport renders at full alpha, undesaturated
- frame: an unlearned teleport shows desaturated at half alpha and casts nothing
- frame: a map with no teleport hides the button entirely
- frame: the button clears a stale macro when re-shown for a teleport-less map
- frame: the teleport icon uses the spell's texture
- frame: no pendingInfo hides the teleport button
- frame: a first show in combat defers the build and says so
- frame: leaving combat builds the deferred popup
- frame: the deferred show restores a pendingInfo cleared during the wait
- frame: repeated in-combat shows queue exactly one wait frame
- frame: once built, showing during combat is allowed
- frame: reconfiguring the teleport button in combat stashes and replays it
- frame: a fresh profile leaves the popup at its default center anchor
- frame: dragging the title bar persists the popup position
- frame: a saved position is restored on the next build

### test_panel.lua (47)

- panel: OnEnable registers the parent category and the General subcategory
- panel: the parent category is added to the AddOns list
- panel: Register is idempotent — a second call registers nothing more
- panel: registering during combat still registers (options-ui-§9)
- panel: a login taken in combat needs no second registration
- panel: registration validates the schema
- panel: both panels start hidden
- panel: registration creates no AceGUI widgets
- panel: OnShow itself builds nothing; the deferred hop does
- panel: the build is one-shot across repeated shows
- panel: two OnShows before the hop runs still build only once
- panel: the Defaults button is built lazily, on the General page only
- panel: clicking Defaults raises the confirmation popup rather than resetting
- panel: confirming the popup restores defaults
- panel: the reset dialog is not registered before it is needed (taint)
- panel: every schema row renders a widget
- panel: bool rows render checkboxes and number rows render sliders
- panel: widgets open showing the current profile value
- panel: the slider inherits its bounds and step from the schema row
- panel: each section renders a heading
- panel: paired rows get half width, solo rows go full width
- panel: the General group renders its Test action button
- panel: the Test button runs the same path as /wg test
- panel: a throwing button onClick is caught, not propagated
- panel: the Debug console checkbox renders as a non-schema extra
- panel: ticking Debug console shows the window without touching db.profile
- panel: unticking Debug console hides the window
- panel: opening the console while General is OPEN moves the checkbox
- panel: re-opening General re-syncs the Debug console checkbox
- panel: ticking a checkbox writes through to db.profile
- panel: a checkbox coerces its value to a real boolean
- panel: releasing the slider writes through to db.profile
- panel: the slider snaps its committed value to the schema step
- panel: unticking Enable fires the master-switch onChange
- panel: rendering registers one refresher per rendered widget
- panel: a re-render REPLACES the refresher list rather than growing it
- panel: a /wg set re-syncs the open widget
- panel: RestoreAllDefaults re-syncs every open widget once
- panel: a throwing refresher does not abort the remaining ones
- panel: the scroll container is patched to always show its scrollbar
- panel: the patch is one-shot per widget
- panel: releasing the widget restores AceGUI's stock behavior
- panel: the landing page lists one row per slash command
- panel: the landing page shows the TOC Notes line
- panel: the landing page renders the Slash Commands heading and the logo
- panel: the landing page adds logo, notes, heading and command rows in that order
- panel: a dirty landing page re-renders in place instead of stacking a second copy

### test_lifecycle.lua (37)

- lifecycle: the addon exposes no public global (WG-01)
- lifecycle: NS IS the addon object (AceAddon mixes into the namespace)
- lifecycle: earlier files' fields survive NewAddon
- lifecycle: the shared chat prefix is the cyan [WG] tag
- lifecycle: NS.Print, WhatGroup._print and NS.Util.print are one seam
- lifecycle: debug state is session-only and starts off
- lifecycle: OnInitialize builds the db from the schema defaults
- lifecycle: OnInitialize registers both slash verbs
- lifecycle: OnEnable registers the two capture events
- lifecycle: no events are registered before OnEnable
- lifecycle: OnEnable seeds wasInGroup from the current roster state
- lifecycle: the ApplyToGroup and SetItemRef hooks install at file load
- lifecycle: the ApplyToGroup hook routes into the capture pipeline
- lifecycle: the SetItemRef hook ignores links that aren't ours
- lifecycle: the SetItemRef hook ignores a non-string link argument
- lifecycle: clicking the chat link opens the popup
- lifecycle: a stale chat link prints a hint instead of an empty popup
- lifecycle: joining a group with a capture waiting fires the notify
- lifecycle: a roster tick while already grouped is not a transition
- lifecycle: leaving the group wipes the capture
- lifecycle: leaving the group cancels an in-flight notify
- lifecycle: rejoining after a leave fires a fresh notify
- lifecycle: the retail ordering (ROSTER before inviteaccepted) still notifies
- lifecycle: InitSummary reflects live runtime state
- lifecycle: InitSummary is safe before the db exists
- lifecycle: /wg config opens the parent settings category
- lifecycle: /wg config is refused during combat (options-ui-§2)
- lifecycle: a login taken in combat still registers the panel
- lifecycle: /wg test injects a synthetic capture and runs the full flow
- lifecycle: /wg test bypasses the master switch
- lifecycle: /wg test fires immediately, without the notify delay
- lifecycle: /wg show opens the popup when a capture exists
- lifecycle: /wg show with no capture prints a hint and opens nothing
- lifecycle: /wg reset <path> resets one setting, with no confirmation
- lifecycle: a bare /wg reset explains the change rather than resetting or erroring
- lifecycle: /wg resetall asks for confirmation rather than resetting outright
- lifecycle: /wg resetall and the Defaults button share one OnAccept body

### test_debuglog.lua (21)

- debuglog: FONT_MONO points at the vendored JetBrains Mono TTF
- debuglog: the console renders in the vendored TTF when the client can fetch it
- debuglog: a TTF the client cannot fetch falls back to a Blizzard font (debug-logging-§2)
- debuglog: FormatPlain wraps the tag in brackets, single-space separators
- debuglog: FormatPlain tolerates a nil tag
- debuglog: FormatColored colors timestamp + tag; pipe and content default
- debuglog: /wg debug on enables session state
- debuglog: /wg debug off disables session state
- debuglog: /wg debug (no arg) toggles the window, not the state
- debuglog: header toggle click flips debug state
- debuglog: enabling writes a '[Debug] logging enabled' console line
- debuglog: enabling debug appends the [Init] session summary after the bracket (debug-logging-§5)
- debuglog: [Init] fires only on enable, not on disable (debug-logging-§5)
- debuglog: disabling still appends a '[Debug] logging disabled' line
- debuglog: NS.Debug survives an unsafe format arg without raising (WG-22)
- debuglog: NS.Debug is a no-op (no console write) when debug is off
- debuglog: §11 scrollbar + line-counter sync is a safe no-op under the mock
- debuglog: settings change logs one [Set] line at the write seam (debug-logging-§10)
- debuglog: RestoreAllDefaults coalesces to one [Reset], zero [Set] (debug-logging-§9)
- debuglog: InitSummary leads with the debug-logging-§5 identity fields, then runtime state
- debuglog: enable ack is color-coded green/red matching the header (debug-logging-§5)

### test_vendor_sync.lua (2)

- libs/LibKa0s is the LibKa0s release the README says this addon bundles
- tests/_kit is the test kit that shipped with that release

## Totals

| Suite | Cases |
|-------|------:|
| test_harness.lua | 7 |
| test_libka0s.lua | 46 |
| test_util.lua | 26 |
| test_compat.lua | 17 |
| test_database.lua | 9 |
| test_settings.lua | 42 |
| test_slash.lua | 43 |
| test_labels.lua | 31 |
| test_capture.lua | 29 |
| test_notify.lua | 44 |
| test_frame.lua | 32 |
| test_panel.lua | 47 |
| test_lifecycle.lua | 37 |
| test_debuglog.lua | 21 |
| test_vendor_sync.lua | 2 |
| **Total** | **433** |
