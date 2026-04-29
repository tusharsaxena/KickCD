-- locales/enUS.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.1, REQUIREMENTS NFR-7
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

-- General tab
L["Enable KickCD"]               = "Enable KickCD"
L["Master enable for the addon."] = "Master enable for the addon."
L["Lock frame"]                  = "Lock frame"
L["When unlocked, you can drag the icon grid to reposition it."] =
    "When unlocked, you can drag the icon grid to reposition it."
L["Scale"]                       = "Scale"
L["Alpha"]                       = "Alpha"
L["Reset position"]              = "Reset position"

-- Icons tab
L["Primary size"]                = "Primary size"
L["Secondary size"]              = "Secondary size"
L["Layout"]                      = "Layout"
L["Horizontal"]                  = "Horizontal"
L["Vertical"]                    = "Vertical"
L["Primary anchor"]              = "Primary anchor"
L["Left"]                        = "Left"
L["Right"]                       = "Right"
L["Top"]                         = "Top"
L["Bottom"]                      = "Bottom"
L["Gap"]                         = "Gap"
L["Ready alpha"]                 = "Ready alpha"
L["Cooldown alpha"]              = "Cooldown alpha"
L["Cooldown tint"]               = "Cooldown tint"
L["Show cooldown text"]          = "Show cooldown text"
L["Show charges"]                = "Show charges"

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
L["racial"]                      = "Racial"
L["other"]                       = "Other"

-- Misc / debug
L["Settings not yet registered"] = "Settings not yet registered"
L["Yes"]                         = "Yes"
L["No"]                          = "No"
L["OK"]                          = "OK"
L["Cancel"]                      = "Cancel"
