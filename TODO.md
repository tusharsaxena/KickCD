# TODO

## Fixes

### All tabs

- [ ] Add some vertical spacing between the sub-header (e.g. Appearance, Debug) and the actual contents inside that sub-header

### General Tab

- [ ] Enable button doesn't work
- [ ] Master scale doesn't work
- [ ] Master alpha does nothing
- [ ] Internal-message logging — rename to "Debug mode"

### Icons Tab

- [ ] Cooldown text shows sometimes (mostly it doesn't show)
- [ ] Add setting for on-cooldown color
- [ ] Add border settings
- [ ] Add settings for font flags (Outline, Thick Outline, etc.)
- [ ] Add settings for icon border
- [ ] Layout and Primary Anchor are interdependent — Horizontal can be Left/Right, Vertical can be Top/Bottom — fix this
- [ ] Primary Anchor: include Top Right, Bottom Right, etc.
- [ ] Add setting for icon zoom
- [ ] Add settings for grid layout for secondary icons (num rows, num cols; grow horizontal vs grow vertical)

### Spells Tab

- [ ] Replace Up / Dn / X buttons with relevant icons
- [ ] What is the purpose of the Interrupt / Stun / Knockback / etc. dropdown?
- [ ] Validate that only spells tracked by CDM can be added for tracking — surface an appropriate error message if this isn't happening
- [ ] Unify Class and Specialization dropdowns into a single one; add class/spec icon in the dropdown, color-code dropdown entries with class color, and use proper casing instead of CAPS

## Enhancements

- [ ] General Tab: add setting to always show vs. show in combat vs. show when target is casting
- [ ] Add a target castbar (do not style the default castbar — create a new one; refer)
