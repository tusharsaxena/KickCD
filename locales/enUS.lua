-- locales/enUS.lua — KickCD v0.1
-- Localization table. See docs/CLAUDE_MODULE_LAYOUT.md (load order)
-- and docs/ARCHITECTURE_BOOT_SEQUENCE.md.
--
-- Default (and currently only) localization. The `L` table is wired with
-- a fall-back metatable: any missing key returns the key itself, so a
-- module can ship `L["Some New String"]` without us having to remember to
-- update enUS.lua before the addon loads. Translators (future) just add
-- their own locale file modeled on this one.

-- locales/enUS.lua loads BEFORE core/Compat.lua per the TOC, so we have
-- to bootstrap the global namespace ourselves here.
KickCD = KickCD or {}

local L = setmetatable({}, {
    __index = function(_, k) return k end,
})
KickCD.L = L

-- ---------------------------------------------------------------------------
-- Strings
-- ---------------------------------------------------------------------------
-- Keep the right-hand side identical to the key when the key is already a
-- human-readable English phrase. Translators copy this file, change the RHS,
-- and rename it to e.g. deDE.lua. The fall-back metatable means anything
-- missing from a translation gracefully degrades to the English key.

-- Addon shell
L["Ka0s KickCD"]                 = "Ka0s KickCD"
L["KickCD"]                      = "KickCD"
L["Tracks interrupt and CC cooldowns on a movable icon grid."] =
    "Tracks interrupt and CC cooldowns on a movable icon grid."

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
L["Reset position"]              = "Reset position"
L["Reset"]                       = "Reset"
L["Restore the icon grid to its default screen position."] =
    "Restore the icon grid to its default screen position."
L["Internal-message logging"]    = "Internal-message logging"
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
L["Primary size"]                = "Primary size"
L["Pixel size of the primary interrupt icon."] =
    "Pixel size of the primary interrupt icon."
L["Secondary size"]              = "Secondary size"
L["Secondary icon size as a fraction of the primary."] =
    "Secondary icon size as a fraction of the primary."
L["Layout"]                      = "Layout"
L["Arrange icons horizontally or vertically."] =
    "Arrange icons horizontally or vertically."
L["Horizontal"]                  = "Horizontal"
L["Vertical"]                    = "Vertical"
L["Primary anchor"]              = "Primary anchor"
L["Where the primary icon sits relative to the secondaries."] =
    "Where the primary icon sits relative to the secondaries."
L["Left"]                        = "Left"
L["Right"]                       = "Right"
L["Top"]                         = "Top"
L["Bottom"]                      = "Bottom"
L["Gap"]                         = "Gap"
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
L["Available settings:"]         = "Available settings:"
L["Setting not found: %s"]       = "Setting not found: %s"
L["Usage: /kcd set <path> <value>"] = "Usage: /kcd set <path> <value>"
L["Usage: /kcd get <path>"]      = "Usage: /kcd get <path>"
L["Invalid value for %s"]        = "Invalid value for %s"
L["Allowed values: %s"]          = "Allowed values: %s"

-- Spells editor
L["Class"]                       = "Class"
L["Specialization"]              = "Specialization"
L["Add spell..."]                = "Add spell..."
L["Remove"]                      = "Remove"
L["Reset to defaults"]           = "Reset to defaults"
L["Move up"]                     = "Move up"
L["Move down"]                   = "Move down"
L["Spell ID or name"]            = "Spell ID or name"
L["Invalid spell"]               = "Invalid spell"
L["Reset all spells for this spec to addon defaults?"] =
    "Reset all spells for this spec to addon defaults?"
L["Category"]                    = "Category"

-- Categories (FR-7.6 closed set)
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
L["Settings not yet registered"] = "Settings not yet registered"
L["Yes"]                         = "Yes"
L["No"]                          = "No"
L["OK"]                          = "OK"
L["Cancel"]                      = "Cancel"
