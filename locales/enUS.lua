-- locales/enUS.lua
-- Localization table. See docs/module-map.md (load order).
--
-- Default (and currently only) localization. The `L` table is wired with
-- a fall-back metatable: any missing key returns the key itself, so a
-- module can ship `L["Some New String"]` without us having to remember to
-- update enUS.lua before the addon loads. Translators (future) just add
-- their own locale file modeled on this one.

-- locales/enUS.lua loads BEFORE core/Compat.lua per the TOC, so we have
-- to bootstrap the global namespace ourselves here.
local addonName, NS = ...

local L = setmetatable({}, {
    __index = function(_, k) return k end,
})
NS.L = L

-- ---------------------------------------------------------------------------
-- Strings
-- ---------------------------------------------------------------------------
-- Keep the right-hand side identical to the key when the key is already a
-- human-readable English phrase. Translators copy this file, change the RHS,
-- and rename it to e.g. deDE.lua. The fall-back metatable means anything
-- missing from a translation gracefully degrades to the English key.

-- Addon shell
L["Ka0s KickCD"]                 = "Ka0s KickCD"
L["Tracks interrupt and CC cooldowns on a movable icon grid."] =
    "Tracks interrupt and CC cooldowns on a movable icon grid."
L["Slash Commands"]              = "Slash Commands"

-- Settings: top-level subcategory titles
L["General"]                     = "General"
L["Icons"]                       = "Icons"
L["Spells"]                      = "Spells"
L["Profiles"]                    = "Profiles"

-- General tab — section headers
L["Master controls"]             = "Master controls"
L["Appearance"]                  = "Appearance"
L["Position"]                    = "Position"
L["Debug"]                       = "Debug"
L["Units"]                       = "Units"

-- General tab — controls
L["Enable KickCD"]               = "Enable KickCD"
L["Master enable for the addon."] = "Master enable for the addon."
L["Lock frame"]                  = "Lock frame"
L["When unlocked, you can drag the icon grid to reposition it."] =
    "When unlocked, you can drag the icon grid to reposition it."
L["Master scale"]                = "Master scale"
L["Scale multiplier applied to the entire icon grid."] =
    "Scale multiplier applied to the entire icon grid."
L["Master alpha"]                = "Master alpha"
L["Global opacity for the icon grid."] =
    "Global opacity for the icon grid."
L["Enable Target grid"]          = "Enable Target grid"
L["Enable Focus grid"]           = "Enable Focus grid"
L["Show Target label"]           = "Show Target label"
L["Show Focus label"]            = "Show Focus label"
L["Target label text"]           = "Target label text"
L["Focus label text"]            = "Focus label text"

-- Icons / Cast bar tabs — unit selector + Focus link/copy header (Task 8)
L["Unit"]                        = "Unit"
L["Target"]                      = "Target"
L["Focus"]                       = "Focus"
L["Use same styling as Target"]  = "Use same styling as Target"
L["Copy styling from Target"]    = "Copy styling from Target"
L["Linked to Target — uncheck to customize."] =
    "Linked to Target — uncheck to customize."
L["Reset position"]              = "Reset position"
L["Restore the icon grid to its default screen position."] =
    "Restore the icon grid to its default screen position."
L["Print every internal message to chat. Useful for diagnosing module wiring."] =
    "Print every internal message to chat. Useful for diagnosing module wiring."
L["General visibility"]          = "General visibility"
L["When the addon (icon grid + cast bar) should be visible. Master enable still wins — disabled hides everything."] =
    "When the addon (icon grid + cast bar) should be visible. Master enable still wins — disabled hides everything."
L["Always"]                      = "Always"
L["In combat"]                   = "In combat"
L["When target is casting"]      = "When target is casting"
L["When target is casting an interruptible spell"] =
    "When target is casting an interruptible spell"

-- Icons tab — section headers
L["Sizing"]                      = "Sizing"
L["Visual states"]               = "Visual states"
L["Annotations"]                 = "Annotations"

-- Icons tab — controls
L["Pixel size of the primary interrupt icon."] =
    "Pixel size of the primary interrupt icon."
L["Secondary size"]              = "Secondary size"
L["Secondary icon size as a fraction of the primary."] =
    "Secondary icon size as a fraction of the primary."
L["Layout"]                      = "Layout"
L["Horizontal"]                  = "Horizontal"
L["Vertical"]                    = "Vertical"
L["Left"]                        = "Left"
L["Right"]                       = "Right"
L["Pixel gap between adjacent icons."] =
    "Pixel gap between adjacent icons."
L["Ready alpha"]                 = "Ready alpha"
L["Icon alpha when the spell is off cooldown."] =
    "Icon alpha when the spell is off cooldown."
L["Cooldown alpha"]              = "Cooldown alpha"
L["Icon alpha while the spell is on cooldown."] =
    "Icon alpha while the spell is on cooldown."
L["Cooldown tint"]               = "Cooldown tint"
L["RGB tint applied to icons during cooldown."] =
    "RGB tint applied to icons during cooldown."
L["Suppress GCD swipe + text"]   = "Suppress GCD swipe + text"
L["Hide the cooldown swipe and countdown text during the global cooldown period (≤1.6s remaining). The icon body still pops back to ready alpha/tint regardless of this setting."] =
    "Hide the cooldown swipe and countdown text during the global cooldown period (≤1.6s remaining). The icon body still pops back to ready alpha/tint regardless of this setting."
L["Show cooldown text"]          = "Show cooldown text"
L["Render numeric seconds remaining on each icon."] =
    "Render numeric seconds remaining on each icon."
L["Font"]                        = "Font"
L["Font for the cooldown text overlay."] =
    "Font for the cooldown text overlay."
L["Font size"]                   = "Font size"
L["Cooldown text size in pixels."] =
    "Cooldown text size in pixels."
L["Show charges"]                = "Show charges"
L["Render a charges badge for spells with charges."] =
    "Render a charges badge for spells with charges."
L["Ready glow"]                  = "Ready glow"
L["Never"]                       = "Never"
L["Primary glow trigger"]        = "Primary glow trigger"
L["When to show the glow on the primary icon."] =
    "When to show the glow on the primary icon."
L["Primary glow style"]          = "Primary glow style"
L["Visual style of the primary-icon glow. Inert when the trigger is set to Never."] =
    "Visual style of the primary-icon glow. Inert when the trigger is set to Never."
L["Primary glow color"]          = "Primary glow color"
L["Glow color on the primary icon."] = "Glow color on the primary icon."
L["Secondary glow trigger"]      = "Secondary glow trigger"
L["When to show the glow on secondary icons."] =
    "When to show the glow on secondary icons."
L["Secondary glow style"]        = "Secondary glow style"
L["Visual style of secondary-icon glow. Inert when the trigger is set to Never."] =
    "Visual style of secondary-icon glow. Inert when the trigger is set to Never."
L["Secondary glow color"]        = "Secondary glow color"
L["Glow color on secondary icons."] = "Glow color on secondary icons."
L["Button (rotating rays)"]      = "Button (rotating rays)"
L["Proc (flipbook)"]             = "Proc (flipbook)"
L["Pixel border"]                = "Pixel border"
L["Auto cast sparkles"]          = "Auto cast sparkles"

-- Unified panel chrome
L["Defaults"]                    = "Defaults"

-- Slash commands (/kcd list|get|set)
L["Available settings"]          = "Available settings"
L["Setting not found: %s"]       = "Setting not found: %s"
L["Usage: /kcd set <path> <value>"] = "Usage: /kcd set <path> <value>"
L["Usage: /kcd get <path>"]      = "Usage: /kcd get <path>"
L["Invalid value for %s"]        = "Invalid value for %s"
L["Allowed values: %s"]          = "Allowed values: %s"
L["Cannot open settings during combat."] = "Cannot open settings during combat."

-- Spells editor
L["Specialization"]              = "Specialization"
L["Add spell..."]                = "Add spell..."
L["Remove"]                      = "Remove"
L["Move up"]                     = "Move up"
L["Move down"]                   = "Move down"
L["Spell ID or name"]            = "Spell ID or name"
L["Invalid spell"]               = "Invalid spell"
L["Reset all spells for this spec to addon defaults?"] =
    "Reset all spells for this spec to addon defaults?"

-- Categories (closed set; matches CATEGORIES in settings/Spells.lua)
L["interrupt"]                   = "Interrupt"
L["stun"]                        = "Stun"
L["knockback"]                   = "Knockback"
L["incapacitate"]                = "Incapacitate"
L["silence"]                     = "Silence"
L["root"]                        = "Root"
L["fear"]                        = "Fear"
L["displace"]                    = "Displace"
L["racial"]                      = "Racial"
L["other"]                       = "Other"

-- Misc / debug
L["Yes"]                         = "Yes"
L["No"]                          = "No"
L["OK"]                          = "OK"
L["Cancel"]                      = "Cancel"


-- General — visibility, master controls, resets
L["Visibility"]                  = "Visibility"
L["Reset all settings"]          = "Reset all settings"
L["Reset every General, Icons, and Cast bar setting to its default, and rebuild every spec's spell list from the addon defaults. Profiles are left alone."] =
    "Reset every General, Icons, and Cast bar setting to its default, and rebuild every spec's spell list from the addon defaults. Profiles are left alone."
L["Reset every schema-driven setting (General, Icons, Cast bar) AND every spec's spell list to addon defaults? The active profile is the only one affected."] =
    "Reset every schema-driven setting (General, Icons, Cast bar) AND every spec's spell list to addon defaults? The active profile is the only one affected."

-- Icons tab — sizing and layout
L["Sizing and Layout"]           = "Sizing and Layout"
L["Primary size (in px)"]        = "Primary size (in px)"
L["Gap (in px)"]                 = "Gap (in px)"
L["Columns"]                     = "Columns"
L["Rows"]                        = "Rows"
L["Horizontal extent of the secondary block — number of vertical lines arranged left/right."] =
    "Horizontal extent of the secondary block — number of vertical lines arranged left/right."
L["Vertical extent of the secondary block — number of horizontal lines stacked up/down."] =
    "Vertical extent of the secondary block — number of horizontal lines stacked up/down."
L["Anchor point (of secondary icons relative to primary)"] =
    "Anchor point (of secondary icons relative to primary)"
L["Side and alignment of the primary icon the secondary block attaches to."] =
    "Side and alignment of the primary icon the secondary block attaches to."
L["Growth direction"]            = "Growth direction"
L["Growth direction (of secondary icons)"] =
    "Growth direction (of secondary icons)"
L["Fill order inside the secondary block. The first axis is the within-line direction; the second axis picks which way the next row/column wraps."] =
    "Fill order inside the secondary block. The first axis is the within-line direction; the second axis picks which way the next row/column wraps."
L["First left then down"]        = "First left then down"
L["First left then up"]          = "First left then up"
L["First right then down"]       = "First right then down"
L["First right then up"]         = "First right then up"
L["First down then left"]        = "First down then left"
L["First down then right"]       = "First down then right"
L["First up then left"]          = "First up then left"
L["First up then right"]         = "First up then right"
L["Horizontal pixel shift applied to the secondary block (positive = right, negative = left)."] =
    "Horizontal pixel shift applied to the secondary block (positive = right, negative = left)."
L["Vertical pixel shift applied to the secondary block (positive = down, negative = up)."] =
    "Vertical pixel shift applied to the secondary block (positive = down, negative = up)."
L["Horizontal pixel shift on top of the anchor (positive = right, negative = left)."] =
    "Horizontal pixel shift on top of the anchor (positive = right, negative = left)."
L["Vertical pixel shift on top of the anchor (positive = up, negative = down)."] =
    "Vertical pixel shift on top of the anchor (positive = up, negative = down)."
L["Icon zoom"]                   = "Icon zoom"
L["Crop the inner area of each icon (0 = no crop, 0.25 = aggressive crop to remove the Blizzard border)."] =
    "Crop the inner area of each icon (0 = no crop, 0.25 = aggressive crop to remove the Blizzard border)."
L["Show border"]                 = "Show border"
L["Draw a thin border around each icon."] =
    "Draw a thin border around each icon."
L["Border thickness (in px)"]    = "Border thickness (in px)"
L["Border thickness in pixels."] = "Border thickness in pixels."
L["Border color"]                = "Border color"
L["Border color (RGBA)."]        = "Border color (RGBA)."
L["LibSharedMedia border texture (edge style) used to draw each icon's border."] =
    "LibSharedMedia border texture (edge style) used to draw each icon's border."
L["Show tooltip on hover"]       = "Show tooltip on hover"
L["Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."] =
    "Show the in-game spell tooltip when hovering over an icon. Only active while the grid is locked — unlock to drag."
L["Truncate after (characters)"] = "Truncate after (characters)"
L["Maximum visible characters in the spell name before replacing the tail with an ellipsis. 0 disables truncation."] =
    "Maximum visible characters in the spell name before replacing the tail with an ellipsis. 0 disables truncation."

-- 13-anchor labels (used by anchor / icon-position pickers)
L["Top left"]                    = "Top left"
L["Top middle"]                  = "Top middle"
L["Top right"]                   = "Top right"
L["Left top"]                    = "Left top"
L["Left middle"]                 = "Left middle"
L["Left bottom"]                 = "Left bottom"
L["Right top"]                   = "Right top"
L["Right middle"]                = "Right middle"
L["Right bottom"]                = "Right bottom"
L["Bottom left"]                 = "Bottom left"
L["Bottom middle"]               = "Bottom middle"
L["Bottom right"]                = "Bottom right"
L["Center"]                      = "Center"
L["Inside left"]                 = "Inside left"
L["Inside right"]                = "Inside right"
L["Outside left"]                = "Outside left"
L["Outside right"]               = "Outside right"

-- Cast bar tab
L["Cast bar"]                    = "Cast bar"
L["Enable cast bar"]             = "Enable cast bar"
L["Show the target cast bar."]   = "Show the target cast bar."
L["Anchor"]                      = "Anchor"
L["Anchor mode"]                 = "Anchor mode"
L["Free (drag to move)"]         = "Free (drag to move)"
L["Anchored to primary icon"]    = "Anchored to primary icon"
L["Free: drag the bar anywhere. Anchored to primary icon: the bar follows the icon grid's primary icon at the configured anchor points and offsets."] =
    "Free: drag the bar anywhere. Anchored to primary icon: the bar follows the icon grid's primary icon at the configured anchor points and offsets."
L["Anchor on primary icon"]      = "Anchor on primary icon"
L["Which point on the primary icon the cast bar attaches to (only used when Anchor mode is set to Anchored to primary icon)."] =
    "Which point on the primary icon the cast bar attaches to (only used when Anchor mode is set to Anchored to primary icon)."
L["Anchor on cast bar"]          = "Anchor on cast bar"
L["Which point on the cast bar attaches to the primary icon (only used when Anchor mode is set to Anchored to primary icon)."] =
    "Which point on the cast bar attaches to the primary icon (only used when Anchor mode is set to Anchored to primary icon)."
L["X offset (in px)"]            = "X offset (in px)"
L["Y offset (in px)"]            = "Y offset (in px)"
L["Horizontal pixel offset between the cast bar's anchor point and the icon's anchor point."] =
    "Horizontal pixel offset between the cast bar's anchor point and the icon's anchor point."
L["Vertical pixel offset between the cast bar's anchor point and the icon's anchor point."] =
    "Vertical pixel offset between the cast bar's anchor point and the icon's anchor point."
L["Orientation"]                 = "Orientation"
L["Horizontal: bar stretches across width. Vertical: bar runs up/down."] =
    "Horizontal: bar stretches across width. Vertical: bar runs up/down."
L["Up"]                          = "Up"
L["Down"]                        = "Down"
L["Which side the cast bar fills toward. Options change with Orientation: horizontal → Right / Left, vertical → Up / Down."] =
    "Which side the cast bar fills toward. Options change with Orientation: horizontal → Right / Left, vertical → Up / Down."
L["Auto-size to icon grid"]      = "Auto-size to icon grid"
L["When on, a horizontal bar's width matches the icon grid's width and a vertical bar's height matches the icon grid's height. The orthogonal dimension stays as configured below."] =
    "When on, a horizontal bar's width matches the icon grid's width and a vertical bar's height matches the icon grid's height. The orthogonal dimension stays as configured below."
L["Cast bar width (in px)"]      = "Cast bar width (in px)"
L["Cast bar width in pixels."]   = "Cast bar width in pixels."
L["Cast bar height (in px)"]     = "Cast bar height (in px)"
L["Cast bar height in pixels."]  = "Cast bar height in pixels."
L["Icon position"]               = "Icon position"
L["Where to place the spell icon, or hide it entirely."] =
    "Where to place the spell icon, or hide it entirely."
L["Icon size (in px)"]           = "Icon size (in px)"
L["Spell icon size in pixels (0 hides the icon)."] =
    "Spell icon size in pixels (0 hides the icon)."
L["Show spark"]                  = "Show spark"
L["Render the leading-edge spark on the bar."] =
    "Render the leading-edge spark on the bar."
L["Spell name"]                  = "Spell name"
L["Show spell name"]             = "Show spell name"
L["Display the cast spell's name on the bar."] =
    "Display the cast spell's name on the bar."
L["Where to anchor the spell name relative to the bar."] =
    "Where to anchor the spell name relative to the bar."
L["Cast time"]                   = "Cast time"
L["Show cast time"]              = "Show cast time"
L["Display the remaining / total cast time on the bar."] =
    "Display the remaining / total cast time on the bar."
L["Where to anchor the remaining-time text relative to the bar."] =
    "Where to anchor the remaining-time text relative to the bar."
L["Spell name color"]            = "Spell name color"
L["RGBA color of the spell-name text."] =
    "RGBA color of the spell-name text."
L["Font for the spell name and cast time text."] =
    "Font for the spell name and cast time text."
L["Cast-bar text size in pixels."]= "Cast-bar text size in pixels."
L["Font flags"]                  = "Font flags"
L["Outline / monochrome flags applied to cast-bar text."] =
    "Outline / monochrome flags applied to cast-bar text."
L["Outline / monochrome flags applied to cooldown text."] =
    "Outline / monochrome flags applied to cooldown text."
L["None"]                        = "None"
L["Off"]                         = "Off"
L["Outline"]                     = "Outline"
L["Thick outline"]               = "Thick outline"
L["Monochrome"]                  = "Monochrome"
L["Interruptible casts"]         = "Interruptible casts"
L["Non-interruptible casts"]     = "Non-interruptible casts"
L["Bar texture"]                 = "Bar texture"
L["LibSharedMedia statusbar texture used for interruptible casts."] =
    "LibSharedMedia statusbar texture used for interruptible casts."
L["LibSharedMedia statusbar texture used for non-interruptible casts."] =
    "LibSharedMedia statusbar texture used for non-interruptible casts."
L["Bar color"]                   = "Bar color"
L["RGBA bar fill color when the target's cast is interruptible."] =
    "RGBA bar fill color when the target's cast is interruptible."
L["RGBA bar fill color when the target's cast cannot be interrupted."] =
    "RGBA bar fill color when the target's cast cannot be interrupted."
L["Background color"]            = "Background color"
L["RGBA color drawn behind the bar."] =
    "RGBA color drawn behind the bar."
L["Border"]                      = "Border"
L["Border style"]                = "Border style"
L["LibSharedMedia border texture (edge style) for interruptible casts."] =
    "LibSharedMedia border texture (edge style) for interruptible casts."
L["LibSharedMedia border texture (edge style) for non-interruptible casts."] =
    "LibSharedMedia border texture (edge style) for non-interruptible casts."
L["Border edge size in pixels."] = "Border edge size in pixels."
L["Draw a border around the cast bar for interruptible casts."] =
    "Draw a border around the cast bar for interruptible casts."
L["Draw a border around the cast bar for non-interruptible casts."] =
    "Draw a border around the cast bar for non-interruptible casts."
L["RGBA border color for interruptible casts."] =
    "RGBA border color for interruptible casts."
L["RGBA border color for non-interruptible casts."] =
    "RGBA border color for non-interruptible casts."
L["Text"]                        = "Text"

-- Cast bar runtime labels
L["KickCD castbar"]              = "KickCD castbar"
L["KickCD castbar — drag to move"] =
    "KickCD castbar — drag to move"

-- Text Label tab
L["Text Label"]                  = "Text Label"
L["Label"]                       = "Label"
L["Show label"]                  = "Show label"
L["Show this unit's identity label."] =
    "Show this unit's identity label."
L["Label text"]                  = "Label text"
L["Text shown on this unit's label."] =
    "Text shown on this unit's label."
L["Placement"]                   = "Placement"
L["Attach to"]                   = "Attach to"
L["Which widget the label anchors to."] =
    "Which widget the label anchors to."
L["Icon grid"]                   = "Icon grid"
L["Label anchor point"]          = "Label anchor point"
L["Which point of the label attaches."] =
    "Which point of the label attaches."
L["Attach point"]                = "Attach point"
L["Which point of the target widget the label attaches to."] =
    "Which point of the target widget the label attaches to."
L["Horizontal pixel shift (positive = right)."] =
    "Horizontal pixel shift (positive = right)."
L["Vertical pixel shift (positive = up)."] =
    "Vertical pixel shift (positive = up)."
L["Horizontal justify"]          = "Horizontal justify"
L["Horizontal text alignment."]  = "Horizontal text alignment."
L["Vertical justify"]            = "Vertical justify"
L["Vertical text alignment."]    = "Vertical text alignment."
L["Rotation (degrees)"]          = "Rotation (degrees)"
L["Rotate the label. 0 = upright."] =
    "Rotate the label. 0 = upright."
L["Top"]                         = "Top"
L["Middle"]                      = "Middle"
L["Bottom"]                      = "Bottom"
L["LSM font for the label."]     = "LSM font for the label."
L["Label font size in pixels."]  = "Label font size in pixels."
L["Outline / monochrome flags."] = "Outline / monochrome flags."

-- Spells editor extras
L["Spell known"]                 = "Spell known"
L["Spell not known"]             = "Spell not known"
L["Category for future filtering. Currently informational only."] =
    "Category for future filtering. Currently informational only."
