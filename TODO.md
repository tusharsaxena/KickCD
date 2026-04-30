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

## Not Yet Started

- ☐ Add as setting for General -> Reset all settings
- ☐ Rearrange all settings panel so every row of settings has 2 columns split exactly halfway through the width of the panel. Also increase vertical spacing between rows
- ☐ General Tab: add setting to always show vs. show in combat vs. show when target is casting
- ☐ Add icon glow when spells are ready (proc, action bar, cdm, pixel, etc). Have separatye glow settings for primary and seconday icons
- ☐ visual state application is inconsistent - for example when i use a spell like Blinding Sleet on my blood death knight, it marks all my spells as on cooldown for some time

## Later

- ☐ Icon zoom is working, but the values seem to be off - see how Weakauras handles icon zoom
- ☐ Cooldown swipe shows for GCD actions, but not when the spell is on a longer cooldown
- ☐ Add the ability to add items along with spells for tracking
