# TODO

## Completed

- ✅ Rename the settings panel and entry name in the TOC file to "KickCD" - but the addon name and all references in the addon should continue to be "Ka0s KickCD"
- ✅ Gracefully handle /kcd config in combat (show error message - do not open settings panel)
- ✅ In the general panel, move the reset position to master controls header, remove the label (just the button) and delete the position sub header
- ✅ Some of the edit boxes sometimes add " px" or " x" or some other text when you change the value via the sliders - do not do this - if you need to specify that it is pixels add that in the label e.g. Primary size (in px)
- ✅ Add some vertical spacing between the sub-header (e.g. Appearance, Debug) and the actual contents inside that sub-header (add spacing both above and below)
- ✅ Increase the font size of the sub-header (e.g. Appearance, Debug)
- ✅ Change the look and feel of buttons and drop downs - ask me for screenshots of what this should look like - refer to https://github.com/tusharsaxena/consumablemaster settings panel where it has the look and feel that i want
- ✅ Do not apply the visual states settings (i.e. reduce alpha, change color of icons) for GCD cooldowns - only when the actual spell is on cooldown
- ✅ Cooldown text doesnt show up after i use a spell - it should always show (text should obey visual state rules like cooldown alpha)
- ✅ Enable button doesn't work
- ✅ Master scale doesn't work
- ✅ Master alpha doesn't work
- ✅ Internal-message logging — rename to "Debug"
- ✅ Add setting for on-cooldown color
- ✅ Add border settings
- ✅ Add settings for font flags (Outline, Thick Outline, etc.)
- ✅ Add settings for icon border
- ✅ Layout and Primary Anchor are interdependent — Horizontal can be Left/Right, Vertical can be Top/Bottom — fix this
- ✅ Primary Anchor: include Top Right, Bottom Right, etc.
- ✅ Add setting for icon zoom
- ✅ Add settings for grid layout for secondary icons (num rows, num cols; grow horizontal vs grow vertical) - ask me for more details if you're not sure what needs to be done here
- ✅ Add a scroll bar in the icons panel
- ✅ Replace Up / Dn / X buttons with relevant icons - refer to icons from https://github.com/tusharsaxena/consumablemaster and see attached screenshot
- ✅ What is the purpose of the Interrupt / Stun / Knockback / etc. dropdown? (kept for future filtering; tooltip added)
- ✅ Validate that only spells tracked by CDM can be added for tracking — surface an appropriate error message if this isn't happening
- ✅ Unify Class and Specialization dropdowns into a single one; add class/spec icon in the dropdown, color-code dropdown entries with class color, and use proper casing instead of CAPS. Label for this should be "Specialization"
- ✅ When hovering over the spell icon or spell name, show the in game tooltip for that spell
- ✅ Remove the spell id aftyer the spell name
- ✅ Some of the spell icons are destaurated - remove this desaturation (desturation should only happen if the checkbox is de-selected)
- ✅ In the Spells > Spec selector, use both class icons and spec icons - [class icon][spec icon] [Class Name] [Spec Name]
- ✅ Add a target castbar (do not style the default castbar — create a new one; refer)
- ✅ Color code cast bar based on interruptable, non interruptable.
- ✅ Cast bar icon position settings should be left/right/off (off is new)
- ✅ Cast bar text position anchors (inside left, inside right, center, outside left, outside right) - with x/y offset - for both the text elements independently (spell name, spell timer)
- ✅ Cast bar border color is not being used - it seems to be using the bar color as the border color
- ✅ For icons, show in game tooltip when hovering over an icon (with a setting to toggle this behavior on and off)
- ✅ For icons, charges text shows out of combat but not in combat
- ✅ Add as setting for General -> Reset all settings
- ✅ Rearrange all settings panel so every row of settings has 2 columns split exactly halfway through the width of the panel. Also increase vertical spacing between rows
- ✅ Add position settings for the cast bar. Give it anchor settings relative to the primary icon (TOP LEFT, TOP CENTER, TOP RIGHT, etc) and anchor position of the cast bar
- ✅ Add orientation (horizontal and vertical) and growth direction (left/right for horizontal and up/down for vertical)
- ✅ Add auto sizing option for the cast bar, which intelligently resizes the cast bar basis the orientation, growth direction and width of the icons shown (both primary and secondary)
- ✅ General Tab: add setting to always show vs. show in combat vs. show when target is casting
- ✅ Add icon glow when spells are ready (proc, pixel) — separate type+color settings for primary and secondary icons
- ✅ Add a dropdown for glows: Show always / show when target is casting / show when target is casting interruptible / never. Glow style picker (Button / Proc / Pixel / Auto cast) is independent of the trigger.
- ✅ Adopt LibCustomGlow-1.0 as the glow rendering backend — gives access to Blizzard's full glow palette (rotating rays, proc flipbook, pixel border, autocast sparkles)
- ✅ Sometimes the cooldown text gets stuck at 0.0 for a few seconds even after it comes off cooldown
- ✅ Cooldown text and swipe shows for GCD actions, add a toggle to disable this (only show for genuine cooldowns) — `icons.suppressGCDSwipe`, default on
- ✅ Cooldown text and swipe doesnt show when a spell with charges is partially off cooldown — added `chargeCdObject` to SPELL_STATE; swipe + text render without changing alpha/tint while the spell is still castable
- ✅ "When target is casting an interruptible spell" is not working - it still shows the addon when a non interruptible spell is being cast. This applies to both the general visibility, and the glow settings classifiers
- ✅ On secondary icons, if a glow is meannt to be shown, it appears like the glow initial animation is redrawn every 0.1 seconds - makes it very janky. This does not happen in the alwats trigger case, only if some other option is selected
- ✅ Remove all DB migration paths — addon is unreleased, so the migration scaffolding (Migrations table, RunMigrations, dbVersion, LATEST_VERSION) was deleted outright
- ✅ Documentation MD files have become too large and bloated. Split CLAUDE.md and ARCHITECTURE.md into smaller files with every file being a section have having a naming convention like CLAUDE_<SECTION_NAME>.md. The main file references these sub files. 
- ✅ Do a deep review of the addon code and update CLAUDE_*.md and ARCHITECTURE_*.md
- ✅ General > Reset All Settings doesnt seem to properly restore default spells for every spec sometimes
- ✅ There's a lot of default spells available in defaults/Spells.lua. Please validate that the spells are only shown on the icon grid only if the spell is known (too low level, not learned, other talent chosen, etc)
- ✅ Do a deep review of all settings panels, make sure all settings are covered, the settings dop what is expected, and the layout of all panels is readable and easy to use.
- ✅ Cast bar vertical layout is not working as expected. My expectation is to rotate the bar by 90 degrees when in vertical mode, so nothing else breaks
- ✅ Add an option to truncate Spell Name text after X characters. 0 Means no truncate, add a slider to set truncate character limit. Add this as a setting option in Cast Bars > Spell name - under the X offset setting (occipies half the row width - i.e. one column) 
- ✅ The Cast bar > Orientation > "Auto-size to icon grid" setting is not working as I expected. Current behavior is that it auto sizes basis the number of columns defined in Icons > Layout > Rows OR Columns (depending on the orientation). My expectation is that it auto sizes basis in the actual visible rows or columns actually shown in the icon grid.
- ✅ Do a deep review of the settings panel and slash command handler, and make sure all settings have a correspoding slash command handler
- ✅ Earlier in commit 2108fbf, you had made fixes for visibility, specifically about differentiating between interuptible and non interuptible casts. This applies to "General Visibility" and "Glow triggers". This isnt working anymore though - please figure out whats wrong. Add some debug statements and ask me for logs in case that helps. For example, when i set general visibility to "When target is casting an interuptible spell", it still shows when the target is casting a non interruptible spell. 
- ✅ Change the name of the addon in the TOC (So addon name shows up as Ka0s KickCD in the addon selector)
- ✅ Change the name of the addon in the Settings Panel (So addon shows up as Ka0s KickCD in the Settings Panel)

## Not Yet Started

- ☐ Add more customization options for the glow effects
- ☐ Add a glowing background animated texture behind the cast bars - this will give a strong indication that a cast is happening. Color this animated texture the same color as the castbar color (depending on interuptable/non-interuptable). Add this as a toggleable feature separately for interuptable/non-interuptable. Also add a texture selector and color selector (default color is same as bar color, with a checkbox to select same as bar color)
- ☐ Bug — partial-charge swipe: New chargeCdObject field on the SPELL_STATE payload. Cooldowns:PollSpell calls GetSpellCooldownDuration whenever the spell has charges and the spell-level cooldown is inactive — Blizzard's API returns nil at full charges, so no Lua compare on possibly-secret cur < maxC is needed. Icon:Apply gains a third branch: when cdObject is nil but chargeCdObject is non-nil, it renders the swipe + countdown text without touching alpha/tint (icon stays at readyAlpha, white tint). state.ready stays true so the glow trigger keeps firing as configured.
- ☐ Icon zoom is working, but the values seem to be off - see how Weakauras handles icon zoom
- ☐ Add the ability to add items along with spells for tracking

## Pre Release

- ☐ You are a princicpal engineer, an experienced LUA developer and experienced wow add developer. I want you to do a deep design and code review of this addon, and share findings. Look for core architectural gaps, design inconsistencies, design patterns, anti patterns, logic gaps, performance issues and bugs. Share your findings in docs/legacy/PE_REVIEW.md. After that, create an a comprehensive set of changes required to address all the feedback in docs/legacy/PE_REVIEW.md, and save that in docs/legacy/CHANGES_PE_REVIEW.md. After that, create an execution plan and save that in docs/legacy/EXECUTION_PLAN_PE_REVIEW.md. Ensure that the docs/legacy/EXECUTION_PLAN_PE_REVIEW.md can be parallelized. Then finally, spawn a team of sub agents and execute docs/legacy/EXECUTION_PLAN_PE_REVIEW.md.
- ☐ Update default settings
- ☐ Change addon icon
- ☐ Take screenshots and in combat video (convert to GIF)
- ☐ Update README with critical settings (especially visibility modes, castbar settings, anchoring, autosize), FAQS, Troubleshooting and Changelog
