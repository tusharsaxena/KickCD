# TODO

## Fixes

### General

- ☐ Rename the settings panel and entry name in the TOC file to "KickCD" - but the addon name and all references in the addon should continue to be "Ka0s KickCD"
- ☐ Gracefully handle /kcd config in combat (show error message - do not open settings panel)

### All tabs

- ☐ Add some vertical spacing between the sub-header (e.g. Appearance, Debug) and the actual contents inside that sub-header
- ☐ Increase the font size of the sub-header (e.g. Appearance, Debug)
- ✅ Change the look and feel of buttons and drop downs - ask me for screenshots of what this should look like - refer to https://github.com/tusharsaxena/consumablemaster settings panel where it has the look and feel that i want

### General Tab

- ☐ Enable button doesn't work
- ☐ Master scale doesn't work
- ☐ Master alpha does nothing
- ☐ Internal-message logging — rename to "Debug mode"

### Icons Tab

- ☐ Add setting for on-cooldown color
- ☐ Add border settings
- ☐ Add settings for font flags (Outline, Thick Outline, etc.)
- ☐ Add settings for icon border
- ☐ Layout and Primary Anchor are interdependent — Horizontal can be Left/Right, Vertical can be Top/Bottom — fix this
- ☐ Primary Anchor: include Top Right, Bottom Right, etc.
- ☐ Add setting for icon zoom
- ☐ Add settings for grid layout for secondary icons (num rows, num cols; grow horizontal vs grow vertical) - ask me for more details if you're not sure what needs to be done here

### Spells Tab

- ✅ Replace Up / Dn / X buttons with relevant icons - refer to icons from https://github.com/tusharsaxena/consumablemaster and see attached screenshot
- ☐ What is the purpose of the Interrupt / Stun / Knockback / etc. dropdown?
- ☐ Validate that only spells tracked by CDM can be added for tracking — surface an appropriate error message if this isn't happening
- ☐ Unify Class and Specialization dropdowns into a single one; add class/spec icon in the dropdown, color-code dropdown entries with class color, and use proper casing instead of CAPS. Label for this should be "Specialization"
- ☐ When hovering over the spell icon or spell name, show the in game tooltip for that spell
- ☐ Remove the spell id aftyer the spell name
- ☐ Some of the spell icons are destaurated - remove this desaturation (desturation should only happen if the checkbox is de-selected)

## Enhancements

- ☐ Cooldown text shows sometimes (mostly it doesn't show)
- ☐ Cooldown coloring is inconsistent - for example when i use a spell like Blinding Sleet on my blood death knight, it marks all my spells as on cooldown for some time
- ☐ Cooldown swipe shows for GCD actions, but not when the spell is on a longer cooldown
- ☐ General Tab: add setting to always show vs. show in combat vs. show when target is casting
- ☐ Add a target castbar (do not style the default castbar — create a new one; refer)
- ☐ Add the ability to add items along with spells for tracking
- ☐ Add icon glow when primary interrupt spell is ready (proc, action bar, cdm, pixel, etc)
