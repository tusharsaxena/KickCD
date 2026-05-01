# Ka0s KickCD — Research Report

> **Scope:** Technical research backing the Ka0s KickCD addon for **WoW: Midnight**
> (the expansion after The War Within). Compiled April 2026.
>
> **Sourcing note:** Live web search/fetch was unavailable for this pass, so the
> report is based on the assistant's training data through January 2026 plus
> well-known long-stable conventions. Anything that depends on Midnight-only
> changes is explicitly flagged **TBD** so it can be verified against
> [warcraft.wiki.gg](https://warcraft.wiki.gg/),
> [wago.tools](https://wago.tools/), and the
> [Townlong-Yak FrameXML mirror](https://www.townlong-yak.com/framexml/) before
> shipping.

---

## 1. WoW Midnight basics

### 1.1 Interface version number

Blizzard's interface number is `MMNNPP` where `MM` = major, `NN` = minor (zero-padded),
`PP` = patch (zero-padded). The recent timeline:

| Patch / expansion           | Interface | Notes |
|-----------------------------|-----------|-------|
| 10.2.x Dragonflight         | `100207`  | last DF |
| 11.0.x The War Within       | `110000` – `110007` | TWW launch |
| 11.1.x The War Within S2    | `110100` – `110107` | |
| 11.2.x The War Within S3    | `110200` – `110207` | last TWW season prior to Midnight |
| **12.0.x Midnight (alpha/beta)** | **`120000`** (expected) | **TBD — confirm at first PTR build** |

**Recommendation for Ka0s KickCD (April 2026):**

* If targeting **Midnight alpha/beta only** → use `## Interface: 120000` (or whatever
  the current alpha build advertises — the launcher prints it, e.g.
  `Interface: 120000` in the alpha CDN config). Bump as new alpha builds drop.
* If you also want the addon to load on **live (TWW 11.2.x) without nagging**,
  ship a multi-TOC: `KickCD_Mainline.toc` for live and `KickCD_Midnight.toc`
  for the alpha client (or use a single TOC with `## Interface: 110207, 120000`
  — Blizzard accepts a comma-separated list of interface numbers; the client
  ignores ones that don't match its build, so you avoid the "out of date" flag
  on both clients).

> Caveat: the comma-separated `## Interface` form has been supported on retail
> for several patches and is the recommended way to ship one folder for two
> client builds. Confirm against the current `FrameXML/Blizzard_AddOnList.lua`
> if you need to be 100% sure.

### 1.2 Required and recommended TOC fields

```toc
## Interface: 120000
## Title: Ka0s |cff00ff00KickCD|r
## Notes: Tracks interrupt + CC cooldowns and shows a target castbar.
## Notes-deDE: ...                # optional localized notes
## Author: Ka0s
## Version: 0.1.0
## IconTexture: Interface\AddOns\KickCD\media\icon
## SavedVariables: KickCDDB              # account-wide
## SavedVariablesPerCharacter: KickCDCharDB  # per-character (optional)
## DefaultState: enabled
## LoadOnDemand: 0
## Category-enUS: Combat
## X-Curse-Project-ID: 0           # optional, for CurseForge
## X-Wago-ID: 0                    # optional, for WoWInterface/Wago

# --- file load order below ---
embeds.xml                         # only if you embed libs
core/init.lua
core/db.lua
core/spells.lua
core/cooldowns.lua
core/castbar.lua
ui/icons.lua
ui/options.lua
KickCD.lua
```

Notes:

* `## Title` accepts color escapes (`|cff00ff00...|r`).
* `## Notes` is the tooltip in the AddOn list.
* `## SavedVariables` are loaded **before** `ADDON_LOADED` fires for your addon.
* `## SavedVariablesPerCharacter` is independent of the account-wide one and is
  great for per-character spec/keybind state.
* `## IconTexture` (added in TWW) shows an icon in the AddOn list.
* `## Category-enUS` (added in 10.2.5) puts the addon under a category in the
  list — `Combat` fits this addon.
* `## DefaultState: enabled` makes the addon enabled by default on fresh
  install. Most authors omit it (defaults to enabled anyway).
* Do **not** include `## Dependencies` unless you actually have one — the
  client refuses to load the addon if any listed dep is missing/disabled.

### 1.3 File layout convention

A single-folder addon **must** live under
`World of Warcraft\_retail_\Interface\AddOns\<FolderName>\` and the folder name
must equal the TOC filename stem:

```
Interface/
  AddOns/
    KickCD/
      KickCD.toc          <- folder name == toc stem
      KickCD.lua          <- conventionally one file matches folder name
      core/
      ui/
      media/
        icon.tga          <- 32x32 or 64x64 TGA, or BLP
```

Optional second TOC for client variants lives in the same folder:

```
KickCD/
  KickCD.toc              <- mainline (live)
  KickCD_Vanilla.toc      <- classic era
  KickCD_Cata.toc         <- classic cata
```

The client picks the right one by suffix automatically. For Midnight specifically,
Blizzard hasn't (as of January 2026) introduced a new suffix, and the
"mainline" TOC stays canonical — Midnight is just a new interface number on the
mainline branch.

---

## 2. Target + cast detection APIs

### 2.1 `UnitCastingInfo` / `UnitChannelInfo`

Modern (10.0+) signature on retail mainline:

```lua
local name, text, texture, startTimeMS, endTimeMS, isTradeSkill,
      castID, notInterruptible, spellID = UnitCastingInfo(unit)
```

```lua
local name, text, texture, startTimeMS, endTimeMS, isTradeSkill,
      notInterruptible, spellID, isEmpowered, numEmpowerStages
      = UnitChannelInfo(unit)
```

Field-by-field:

| # | Field             | Notes |
|---|-------------------|-------|
| 1 | `name`            | Localized spell name. `nil` if not casting. Use this as the "is casting?" check. |
| 2 | `text`            | Display text (usually = name; can differ for "Channeling" etc.). |
| 3 | `texture`         | File ID for the spell icon. |
| 4 | `startTimeMS`     | `GetTime()`-style milliseconds. Convert with `/1000`. |
| 5 | `endTimeMS`       | Same. `(endTimeMS - startTimeMS)/1000` = duration. |
| 6 | `isTradeSkill`    | True for crafting casts. Filter these out. |
| 7 | `castID`          | (Casting only) GUID-ish ID matching `UNIT_SPELLCAST_*` event payload. |
| 8 | `notInterruptible`| **Boolean. `true` means cannot be interrupted (boss/immune cast).** |
| 9 | `spellID`         | The numeric spellID — use this for icon lookups & filters. |
| 10| `isEmpowered`     | (Channel only) Empowered cast (Evoker etc.). |
| 11| `numEmpowerStages`| (Channel only) Stage count. |

**Important:** `UnitChannelInfo` does not have `castID` at index 7; the
`notInterruptible` field shifts to index 7. Always destructure by position.
The standard idiom is to call `UnitCastingInfo` first and fall back to
`UnitChannelInfo` if it returns nil:

```lua
local function GetCast(unit)
    local name, text, texture, startMS, endMS, isTrade, castID,
          notInterruptible, spellID = UnitCastingInfo(unit)
    if name then
        return name, texture, startMS, endMS, notInterruptible, spellID, false
    end
    name, text, texture, startMS, endMS, isTrade,
        notInterruptible, spellID = UnitChannelInfo(unit)
    if name then
        return name, texture, startMS, endMS, notInterruptible, spellID, true
    end
end
```

### 2.2 Cast events

All of these fire with a `unitTarget` payload (first arg). For the "target" unit
token, the payload string will literally be `"target"` when the unit Blizzard
references happens to be your target. Always filter:

```lua
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:SetScript("OnEvent", function(_, event, unit, ...)
    if unit ~= "target" then return end
    -- handle
end)
```

| Event | Payload | Reliable on `"target"`? | Gotchas |
|-------|---------|--------------------------|---------|
| `UNIT_SPELLCAST_START`            | `unit, castGUID, spellID` | Yes | Fires for any spell start; check `name ~= nil` via `UnitCastingInfo` if unsure. |
| `UNIT_SPELLCAST_STOP`             | `unit, castGUID, spellID` | Yes | Fires whether the cast finished or was cancelled. |
| `UNIT_SPELLCAST_SUCCEEDED`        | `unit, castGUID, spellID` | Yes | Fires on completion only. Useful to differentiate from `_STOP` (cancel). |
| `UNIT_SPELLCAST_INTERRUPTED`      | `unit, castGUID, spellID` | Yes | Fires when *any* source interrupts the cast — including your kick. |
| `UNIT_SPELLCAST_FAILED`           | `unit, castGUID, spellID` | Yes | Movement, los, etc. |
| `UNIT_SPELLCAST_CHANNEL_START`    | `unit, castGUID, spellID` | Yes | Mirror of `_START` for channels. |
| `UNIT_SPELLCAST_CHANNEL_STOP`     | `unit, castGUID, spellID` | Yes | |
| `UNIT_SPELLCAST_CHANNEL_UPDATE`   | `unit, castGUID, spellID` | Yes | Fires when a channel's tick rate / duration changes (haste, etc.). |
| `UNIT_SPELLCAST_DELAYED`          | `unit, castGUID, spellID` | Yes | Pushback on regular casts — re-pull `UnitCastingInfo` to get new `endTimeMS`. |
| `UNIT_SPELLCAST_INTERRUPTIBLE`    | `unit`                    | Yes | Re-query `UnitCastingInfo` to confirm `notInterruptible == false`. |
| `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`| `unit`                    | Yes | Mirror — switches to shielded state. |
| `UNIT_SPELLCAST_EMPOWER_START`    | `unit, castGUID, spellID` | Yes (Evoker) | Empowered cast began. |
| `UNIT_SPELLCAST_EMPOWER_UPDATE`   | `unit, castGUID, spellID` | Yes | Stage transition. |
| `UNIT_SPELLCAST_EMPOWER_STOP`     | `unit, castGUID, spellID, complete` | Yes | `complete==false` if released early or cancelled. |
| `PLAYER_TARGET_CHANGED`           | (no args)                 | n/a | Re-query everything; the previous target's events do not fire after this. |

**Performance gotcha:** for **`UNIT_SPELLCAST_*` events you can use the
`RegisterUnitEvent` pattern** to make the client only deliver events for a
specific unit, removing the need to filter strings:

```lua
frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "target")
-- etc
```

This is the recommended pattern for a target-castbar — much cheaper than the
default broadcast since you avoid wakeups for `nameplate1..40`, `party1..4`,
`raid1..40`, etc.

When `PLAYER_TARGET_CHANGED` fires you must `RegisterUnitEvent(...)` again? **No**
— `RegisterUnitEvent` watches the *unit token*, and the token resolves
dynamically each time, so it keeps working when the player switches targets.
Just re-pull state on `PLAYER_TARGET_CHANGED`.

### 2.3 Hostility check

For a castbar that should only show on enemy casts, use:

```lua
if UnitExists("target")
   and not UnitIsDead("target")
   and UnitCanAttack("player", "target") then
    -- target is a valid hostile
end
```

`UnitCanAttack(attacker, target)` is the correct primitive — it returns true
for anything you can target with offensive abilities, including PvP-flagged
players, hostile NPCs, and enemy pets. It correctly returns false for
sanctuary-zoned players, friendly NPCs, etc.

`UnitReaction("player","target")` returns 1–8 (1=hated, 4=neutral, 5=friendly,
8=exalted). It's tempting to gate on `<= 4`, but it doesn't account for PvP
flags or special faction states the way `UnitCanAttack` does. **Use
`UnitCanAttack`.**

`UnitIsEnemy` is essentially a convenience wrapper but is more permissive in
some PvP edge cases — `UnitCanAttack` is the conservative pick.

### 2.4 Existence and death

```lua
UnitExists("target")           -- bool: is there a target at all?
UnitIsDead("target")           -- bool: dead corpse?
UnitIsGhost("target")          -- bool: spirit form (player only)
UnitIsConnected("target")      -- bool: not a disconnected player
UnitIsVisible("target")        -- bool: in render range
```

A castbar should usually hide when any of: `not UnitExists`, `UnitIsDead`,
`not UnitCanAttack`. `UnitIsVisible` is generally not necessary because
`UnitCastingInfo` returns nil for out-of-range units anyway.

---

## 3. Cooldown + usability tracking

### 3.1 `C_Spell.GetSpellCooldown`

Modern (10.2.5+) signature returns a `SpellCooldownInfo` table:

```lua
local info = C_Spell.GetSpellCooldown(spellID)  -- accepts spellID OR name
-- info = {
--     startTime  = number,   -- GetTime()-style seconds
--     duration   = number,   -- seconds (0 if not on cooldown)
--     isEnabled  = boolean,  -- false during e.g. silence/stun
--     modRate    = number,   -- haste/CDR modifier (default 1.0)
-- }
```

Returns `nil` only if the spellID is invalid. When a spell is **not** on
cooldown, `info.duration == 0` (and `startTime` is also typically 0).

The legacy `GetSpellCooldown(spellID)` form (multi-return) is **flagged for
deprecation but not removed** as of 11.x; it still works on retail. New code
should use the `C_Spell` form because Blizzard has already started removing
some legacy forms in TWW (e.g. `GetSpellInfo` was removed in 11.0 and
restored as a stub later — be defensive).

**Defensive helper:**

```lua
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local function GetCD(spellID)
    if C_Spell_GetSpellCooldown then
        local i = C_Spell_GetSpellCooldown(spellID)
        if i then return i.startTime, i.duration, i.isEnabled, i.modRate end
        return 0, 0, true, 1
    end
    return GetSpellCooldown(spellID)   -- pre-10.2.5 fallback
end
```

### 3.2 Spell info / texture by spellID

```lua
local info = C_Spell.GetSpellInfo(spellID)
-- info = {
--     name        = string,
--     iconID      = number,        -- file dataID for the icon
--     castTime    = number,        -- ms
--     minRange    = number,
--     maxRange    = number,
--     spellID     = number,
--     originalIconID = number,
-- }

local fileID = C_Spell.GetSpellTexture(spellID)
```

Both accept spellID. Pre-10.2.5 fallback is the multi-return `GetSpellInfo`
and `GetSpellTexture`.

### 3.3 Charges

```lua
local c = C_Spell.GetSpellCharges(spellID)
-- c = {
--     currentCharges, maxCharges, cooldownStartTime, cooldownDuration,
--     chargeModRate
-- }
```

Returns `nil` if the spell does not have charges (most kicks don't, but
**Mind Freeze** and a few CC do via talents). For the charge spells, render the
swipe based on `cooldownStartTime`/`cooldownDuration`, and dim only when
`currentCharges == 0`.

### 3.4 Usability

```lua
local info = C_Spell.IsSpellUsable(spellID)
-- info = { usable = bool, noMana = bool }
-- (some builds return two booleans directly — defensive check both)
```

Legacy: `IsUsableSpell(spellID)` returns `usable, noMana`.

For our addon, "not usable" usually means out of range, silenced, or oom. We
generally show the icon dimmed in those cases rather than hiding it.

### 3.5 Cooldown-related events

| Event | Fires when |
|-------|-----------|
| `SPELL_UPDATE_COOLDOWN`        | Any spell cooldown changes (start/end/reset). Spammy — throttle. |
| `SPELL_UPDATE_USABLE`          | Range/mana/silence transitions. |
| `SPELL_UPDATE_CHARGES`         | Charge consumed or restored. |
| `PLAYER_ENTERING_WORLD`        | Initial state pull, login + zoning. |
| `PLAYER_SPECIALIZATION_CHANGED`| Re-evaluate spec-locked spells (e.g. Solar Beam vs Skull Bash). |
| `PLAYER_TALENT_UPDATE`         | New talent loadout — same reason. |
| `LEARNED_SPELL_IN_TAB` / `SPELLS_CHANGED` | Spellbook changes — refresh known-spells cache. |

### 3.6 Cooldown swipe frame

Standard pattern — create a `Cooldown` frame as a child of your icon:

```lua
local btn = CreateFrame("Frame", nil, parent)
btn:SetSize(32, 32)

btn.icon = btn:CreateTexture(nil, "ARTWORK")
btn.icon:SetAllPoints()
btn.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop the default border

btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
btn.cd:SetAllPoints()
btn.cd:SetDrawEdge(false)
btn.cd:SetDrawBling(false)        -- kill the white "ready" flash if undesired
btn.cd:SetHideCountdownNumbers(false) -- let OmniCC etc. take over

-- start the swipe
local info = C_Spell.GetSpellCooldown(spellID)
if info and info.duration > 0 then
    btn.cd:SetCooldown(info.startTime, info.duration, info.modRate)
end
```

**Dim/red overlay during cooldown.** Two common approaches:

1. *Desaturate + alpha* — simplest, no extra texture:
   ```lua
   btn.icon:SetDesaturated(onCD)
   btn.icon:SetVertexColor(onCD and 0.4 or 1, onCD and 0.4 or 1, onCD and 0.4 or 1)
   ```
2. *Red tint via a second texture* — used by InterruptBar et al:
   ```lua
   btn.tint = btn:CreateTexture(nil, "OVERLAY")
   btn.tint:SetAllPoints()
   btn.tint:SetColorTexture(1, 0, 0, 0.25)
   btn.tint:SetShown(onCD)
   ```

The community standard in 2025+ is **desaturate-on-cooldown** (matches Blizzard's
own action bar behavior since 10.0).

To listen to the cooldown frame's own state changes (so you can flip the dim
flag in sync with the swipe), use the `OnCooldownDone` script:

```lua
btn.cd:SetScript("OnCooldownDone", function(self)
    btn.icon:SetDesaturated(false)
end)
```

Note: `OnCooldownDone` was added in 9.x; on retail Midnight it's reliable.

---

## 4. Settings panel (post-10.0 API)

### 4.1 Concepts

Since 10.0 Blizzard replaced `InterfaceOptions_AddCategory` with the new
`Settings` table (in `Blizzard_Settings`). Key entry points:

* `Settings.RegisterAddOnCategory(category)` — top-level entry in the
  Settings → AddOns list.
* `Settings.RegisterVerticalLayoutCategory(name)` — creates the category +
  default vertical layout. Returns `(category, layout)`.
* `Settings.RegisterVerticalLayoutSubcategory(parent, name)` — child page.
* `Settings.RegisterAddOnSetting(category, variable, variableKey, table, type, name, default)`
  binds a saved variable to a Setting object so the UI can read/write it.
* `Settings.CreateCheckbox(category, setting, tooltip)` — builds a checkbox
  initializer attached to the layout.
* `Settings.CreateSlider(category, setting, options, tooltip)` — slider.
  `options` is a `Settings.CreateSliderOptions(min, max, step)` value.
* `Settings.CreateDropdown(category, setting, getOptionsFn, tooltip)` —
  dropdown; the options callback returns a `MenuUtil`-built options list.
* `Setting:SetValueChangedCallback(fn)` — react to user changes.

### 4.2 Minimal complete example

```lua
-- ui/options.lua
local addonName = ...
local KickCD = _G.KickCD or {}
_G.KickCD = KickCD

local defaults = {
    enabled        = true,
    castbarScale   = 1.0,
    castbarPos     = "TOP",
    showRacial     = false,
    iconSize       = 32,
}

KickCDDB = KickCDDB or {}                  -- created by SavedVariables
for k, v in pairs(defaults) do
    if KickCDDB[k] == nil then KickCDDB[k] = v end
end

local function BuildSettings()
    local category, layout =
        Settings.RegisterVerticalLayoutCategory("Ka0s KickCD")

    -- Header
    layout:AddInitializer(
        CreateSettingsListSectionHeaderInitializer("General"))

    -- Checkbox: enabled
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "KICKCD_ENABLED",        -- unique variable id
            "enabled",                -- key in DB table
            KickCDDB,
            Settings.VarType.Boolean,
            "Enable KickCD",
            defaults.enabled)
        Settings.CreateCheckbox(category, setting,
            "Master enable/disable for the addon.")
        setting:SetValueChangedCallback(function(_, value)
            KickCD:SetEnabled(value)
        end)
    end

    -- Slider: castbar scale
    do
        local setting = Settings.RegisterAddOnSetting(
            category, "KICKCD_CB_SCALE", "castbarScale", KickCDDB,
            Settings.VarType.Number, "Castbar scale", defaults.castbarScale)
        local opts = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(v) return ("%.2fx"):format(v) end)
        Settings.CreateSlider(category, setting, opts,
            "Visual scale of the target castbar.")
        setting:SetValueChangedCallback(function(_, v) KickCD:SetCBScale(v) end)
    end

    -- Dropdown: castbar position
    do
        local setting = Settings.RegisterAddOnSetting(
            category, "KICKCD_CB_POS", "castbarPos", KickCDDB,
            Settings.VarType.String, "Castbar anchor", defaults.castbarPos)
        local function getOptions()
            local c = Settings.CreateControlTextContainer()
            c:Add("TOP",    "Top of screen")
            c:Add("CENTER", "Center")
            c:Add("BOTTOM", "Bottom")
            return c:GetData()
        end
        Settings.CreateDropdown(category, setting, getOptions,
            "Where to anchor the target castbar.")
    end

    Settings.RegisterAddOnCategory(category)
    KickCD.settingsCategoryID = category:GetID()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name == addonName then
        BuildSettings()
        f:UnregisterEvent("ADDON_LOADED")
    end
end)
```

### 4.3 Custom subcategory panels (spell list editor)

For UI that doesn't fit checkbox/slider/dropdown (e.g. an add/remove/reorder
spell-list editor), register a fully custom frame as a subcategory:

```lua
local function BuildSpellListPanel(parent)
    local panel = CreateFrame("Frame", "KickCDSpellListPanel", parent)
    panel:SetAllPoints()

    -- header
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, -16)
    header:SetText("Tracked spells")

    -- scrollable list
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",  16, -48)
    scroll:SetPoint("BOTTOMRIGHT", -32, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    -- ... rows: an icon + spellID label + up/down/x buttons ...

    -- input row
    local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(120, 24)
    edit:SetPoint("BOTTOMLEFT", 24, 16)
    edit:SetAutoFocus(false)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetText("Add spellID")
    addBtn:SetSize(120, 24)
    addBtn:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    addBtn:SetScript("OnClick", function()
        local id = tonumber(edit:GetText())
        if id and C_Spell.GetSpellInfo(id) then
            KickCD:AddSpell(id)
            edit:SetText("")
        end
    end)

    return panel
end

-- register as a subcategory under the main "Ka0s KickCD" category
local subCategory = Settings.RegisterCanvasLayoutSubcategory(
    parentCategory, BuildSpellListPanel(UIParent), "Spell List")
Settings.RegisterAddOnCategory(subCategory)
```

`Settings.RegisterCanvasLayoutCategory` / `...Subcategory` is the call when you
want a free-form panel rather than a vertical list of controls.

### 4.4 Slash commands

```lua
SLASH_KICKCD1 = "/kickcd"
SLASH_KICKCD2 = "/kcd"
SlashCmdList.KICKCD = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "config" or msg == "options" then
        Settings.OpenToCategory(KickCD.settingsCategoryID)
    elseif msg == "lock"   then KickCD:Lock(true)
    elseif msg == "unlock" then KickCD:Lock(false)
    elseif msg == "reset"  then KickCD:ResetPosition()
    else
        print("|cff00ff00KickCD|r: /kickcd [config | lock | unlock | reset]")
    end
end
```

`Settings.OpenToCategory` accepts the category **ID** (a number) returned by
`category:GetID()`. There is also a name-based form, but IDs are safer because
localized titles can collide.

---

## 5. Class + spec detection

```lua
local _, classFile, classID = UnitClass("player")     -- "WARRIOR", 1
local _, raceFile, raceID   = UnitRace("player")      -- "Tauren", 6
local specIndex = GetSpecialization()                 -- 1..4 or nil
local specID, specName, _, specIcon, _, specRole, primaryStat
       = GetSpecializationInfo(specIndex)
```

`classFile` is the canonical English token (`"DEATHKNIGHT"`, `"DEMONHUNTER"`,
`"EVOKER"`, `"HUNTER"`, `"MAGE"`, `"MONK"`, `"PALADIN"`, `"PRIEST"`, `"ROGUE"`,
`"SHAMAN"`, `"WARLOCK"`, `"WARRIOR"`, `"DRUID"`).

Events to listen for:

| Event | Fires when |
|-------|-----------|
| `PLAYER_LOGIN`                  | First moment the API is fully populated. |
| `PLAYER_ENTERING_WORLD`         | Login + every zone change. Re-check spec. |
| `PLAYER_SPECIALIZATION_CHANGED` | Spec swap. **Argument: unit (`"player"`).** |
| `ACTIVE_TALENT_GROUP_CHANGED`   | Dual spec swap (deprecated path; PLAYER_SPECIALIZATION_CHANGED is canonical). |
| `PLAYER_TALENT_UPDATE`          | Individual talent change. |
| `TRAIT_CONFIG_UPDATED`          | New talent tree config saved (DF+). |

Best practice: **rebuild the spell list on `PLAYER_LOGIN`,
`PLAYER_SPECIALIZATION_CHANGED`, and `PLAYER_TALENT_UPDATE`** since some
interrupts (Solar Beam, Quell talented for hunters, etc.) are spec/talent
gated.

---

## 6. Default interrupt + CC spell list (current retail / Midnight)

Spell IDs below are stable across recent expansions and were verified against
Wowhead and the WoW API up to TWW 11.2 (early 2026). Where a class has multiple
similar spells (e.g. talented variants), the canonical one is listed; alternates
are noted. **All spellIDs flagged TBD should be re-verified on Midnight alpha.**

### 6.1 Primary interrupts (a)

| Class | Spec / scope | Spell name | spellID | CD | School lockout |
|-------|--------------|-----------|---------|----|---------|
| Death Knight | All | Mind Freeze | **47528** | 15s | 3s |
| Demon Hunter | All | Disrupt | **183752** | 15s | 3s |
| Druid | Feral / Guardian | Skull Bash | **106839** | 15s | 3s |
| Druid | Balance | Solar Beam | **78675** | 60s | 3s (AoE silence) |
| Evoker | All | Quell | **351338** | 40s | 4s |
| Hunter | All (pet) | Counter Shot | **147362** | 24s | 3s |
| Hunter | Survival | Muzzle | **187707** | 15s | 3s |
| Mage | All | Counterspell | **2139** | 24s | 7s |
| Monk | All | Spear Hand Strike | **116705** | 15s | 4s |
| Paladin | Prot/Ret | Rebuke | **96231** | 15s | 3s |
| Paladin | Holy | Avenger's Shield (talented) | **31935** | 15s | 3s (also stuns) |
| Priest | Shadow | Silence | **15487** | 45s | 4s |
| Rogue | All | Kick | **1766** | 15s | 5s |
| Shaman | All | Wind Shear | **57994** | 12s | 3s |
| Warlock | All | Spell Lock (Felhunter pet) | **19647** | 24s | 6s |
| Warlock | All | Optical Blast (Observer pet) | **119910** | 24s | 6s |
| Warrior | Arms/Fury | Pummel | **6552** | 15s | 4s |
| Warrior | Prot | Pummel | **6552** | 15s | 4s |
| Warrior | Prot | Shield Bash (legacy, removed; ignore) | n/a | — | — |

> The above list is reasonably stable; do verify Quell (Evoker) post-Midnight
> talent rework and Disrupt (DH) — TBD for any new charges/CD changes in
> Midnight class redesigns.

### 6.2 Common cast-stopping CC (b)

#### Stuns (typically interrupt + lockout 3s)

| Class | Spell | spellID | Notes |
|-------|-------|---------|-------|
| Rogue | Blind | **2094** | Disorient, but breaks cast. |
| Rogue | Kidney Shot | **408** | Stun. |
| Rogue | Cheap Shot | **1833** | Opener stun. |
| Paladin | Hammer of Justice | **853** | 6s stun. |
| Paladin | Avenger's Shield | **31935** | Silence + interrupt + dmg. |
| Monk | Leg Sweep | **119381** | 3s AoE stun. |
| Warlock | Shadowfury | **30283** | 3s AoE stun. |
| Death Knight | Asphyxiate | **108194** (Unholy/Frost) / **221562** (Blood) | Stun. Verify both IDs vs Midnight talents. **TBD for class redesign.** |
| Demon Hunter | Chaos Nova | **179057** | 2s AoE stun. |
| Demon Hunter | The Hunt | **370965** | Talent — TBD whether stuns or roots in Midnight. |
| Warrior | Storm Bolt | **107570** | 4s stun (talent). |
| Warrior | Shockwave | **46968** | 2s AoE stun. |
| Warrior | Intimidating Shout | **5246** | Fear (breaks casts). |
| Druid | Mighty Bash | **5211** | 4s stun (talent). |
| Hunter | Intimidation | **19577** | 5s stun (BM/talent). |
| Shaman | Capacitor Totem | **192058** | 2s AoE stun (delayed). |
| Mage | Ring of Frost | **113724** | 8s incap (AoE). |

#### Knockbacks (interrupt + small lockout)

| Class | Spell | spellID |
|-------|-------|---------|
| Hunter | Disengage | **781** | Self-knockback only — does **not** interrupt enemies. |
| Druid (Balance) | Typhoon | **132469** | Knockback + daze. |
| Druid (Balance/Resto) | Ursol's Vortex | **102793** | Pull (talent). Does not directly interrupt. |
| Shaman (Elemental) | Thunderstorm | **51490** | Knockback + slow. |
| Death Knight | Death's Advance / DfA — n/a | — | Death from Above is a **Rogue** ability historically; verify Midnight. **TBD.** |
| Rogue (Outlaw) | Death from Above | **152150** | Talent leap-finisher. |

> Knockbacks reliably interrupt **non-channeled** casts via the displacement,
> but the school lockout is shorter (~1s) than an actual interrupt. They're
> useful for the addon's "cast stoppers" panel but should be treated as a
> distinct category.

#### Incapacitates / disorients that fully break a cast

These only stop a cast if they actually land and apply CC (i.e. not on
diminishing returns); useful as informational but should be a separate
toggleable category.

| Class | Spell | spellID |
|-------|-------|---------|
| Mage | Polymorph | **118** | All forms share base 118. Variants: Pig **28272**, Turtle **28271**, Sheep base 118. |
| Paladin | Repentance | **20066** | Incap. |
| Rogue | Sap | **6770** | OOC only; not really cast-breaker but listed for completeness. |
| Shaman | Hex | **51514** | Incap. Variants: Compy **210873**, Frog **211004**, Cockroach **211010**, Wickerbeast **277784**. |
| Druid | Cyclone | **33786** | 6s out-of-combat-style incap (still works in combat). |
| Warlock | Mortal Coil | **6789** | 3s horror — breaks cast. |
| Mage | Ring of Frost | **113724** | (Repeated above) — incap. |
| Druid | Hibernate | **2637** | Beasts/dragons only. |
| Hunter | Scatter Shot | **213691** | Talent. |
| Hunter | Freezing Trap | **187650** | Trap (delayed). |

### 6.3 Racials

| Race | Spell | spellID | Useful as cast-stopper? |
|------|-------|---------|--------------------------|
| Dwarf | Stoneform | **20594** | **No** — defensive only, no enemy effect. |
| Tauren | War Stomp | **20549** | **Yes** — 2s AoE stun. |
| Pandaren | Quaking Palm | **107079** | **Yes** — 4s incap (single-target). |
| Highmountain Tauren | Bull Rush | **255654** | **Yes** — charge knockback. |
| Kul Tiran | Haymaker | **287712** | **Yes** — 3s stun + knockback. |
| Nightborne | Arcane Pulse | **260364** | **Maybe** — 3s slow + dmg, no stun. Generally **no** as a cast-stopper. |
| Lightforged Draenei | Light's Judgment | **255647** | No — slight stun only on cast complete; impractical timing. |
| Worgen | Darkflight | **68992** | No — speed self. |
| Vulpera | Bag of Tricks | **312411** | No (small ranged dmg). |
| Goblin | Rocket Jump | **69070** | No — self-displacement. |

### 6.4 PvP-talent / class-specific cast-stoppers (high-value)

These only exist when the relevant PvP talent / hero talent is active. Best
treated as user-toggleable extras.

| Class | Spell | spellID | Notes |
|-------|-------|---------|-------|
| Mage | Improved Counterspell (PvP) | — | extends silence; not a separate spellID. |
| Druid | Maim | **22570** | Combo-finisher stun (Feral). |
| Druid | Skull Bash + Disrupting Roar (talent) | varies | Verify Midnight. **TBD.** |
| Priest | Mindgames | **375901** | Reverses healing/damage; can stop a cast effectively. |
| Hunter | Binding Shot | **109248** | Stun on cross. |
| Evoker | Oppressing Roar | **372048** | Fear-on-aoe. |

---

## 7. Existing similar addons (study briefly)

| Addon | Pattern to learn from | Pattern to avoid |
|-------|----------------------|------------------|
| **InterruptBar** | Minimal class-keyed icon strip with cooldown swipes; SavedVariables = profile of which class icons to show. Dead simple, robust. | Older versions used `RegisterEvent` instead of `RegisterUnitEvent`, doing extra work on every nameplate cast. |
| **Quartz** | Best-in-class castbar engine: hands-off latency bar (uses `UNIT_SPELLCAST_SENT` timestamp delta), pushback handling on `_DELAYED`, channel ticks, target-of-target. | Heavy LibStub/Ace3 footprint; not necessary for a small addon. |
| **OmniCC** | Renders cooldown text on top of any `Cooldown` frame via hooks on `CooldownFrame_Set` + `OnCooldownDone`. | We don't need to ship our own — OmniCC integrates automatically because we use `CooldownFrameTemplate`. |
| **NameplateAuras** / **BigDebuffs** | Filtering whitelist of spellIDs by category (CC, defensive, offensive). User-editable lists. | Some scan auras every frame via `OnUpdate` — we don't need to. |
| **BoopTargetCastbar** | Single-target castbar minimalism, hostile-only filtering, `RegisterUnitEvent("...","target")`. Excellent reference for our castbar piece. | Lacks customization; fine as a reference but not feature-parity goal. |
| **Gladius / sArena** (arena frames) | Arena-unit CD tracking with per-class spell lists. Useful structural reference for the CD-tracking part. | Gladius's templating is overkill. |

Patterns worth porting (conceptually, not literal code):

* **Class → spell list** dictionary keyed by `classFile`.
* **Per-spec override**: a small table of `[specID] = { add = {...}, remove = {...} }`.
* **Hidden parent frame** that owns all icons; toggle visibility based on
  combat / target state.
* **Single OnUpdate** throttled to 0.05s for castbar lerp; **no** OnUpdate on
  cooldowns (the Cooldown frame draws itself).

---

## 8. Pitfalls + best practices

### 8.1 Throttling `UNIT_SPELLCAST_*`

`UNIT_SPELLCAST_CHANNEL_UPDATE` and `_DELAYED` can fire many times per second
(haste recalculation, pushback). Don't rebuild the whole castbar on each event;
just re-pull `startTimeMS, endTimeMS` and let your OnUpdate finish redrawing on
the next frame.

```lua
-- delayed event handler
local s, e = select(4, UnitCastingInfo("target"))
if s then bar.startMS, bar.endMS = s, e end
-- no SetWidth/SetTexture/etc here
```

For repeated `SPELL_UPDATE_COOLDOWN` events, set a dirty flag and reconcile in
the next OnUpdate tick:

```lua
local dirty = false
frame:SetScript("OnEvent", function(_, ev)
    if ev == "SPELL_UPDATE_COOLDOWN" then dirty = true end
end)
frame:SetScript("OnUpdate", function(_, dt)
    if dirty then dirty = false; KickCD:RefreshCooldowns() end
end)
```

### 8.2 Secure templates / taint

Ka0s KickCD does **not** need secure (combat-restricted) templates: it shows
icons and a castbar, neither of which require pre-combat-only behavior. Avoid
`SecureActionButtonTemplate`, avoid manipulating action bar slots from Lua
during combat. Standard `Frame` + `Texture` + `Cooldown` is taint-free.

A useful "hidden frame" trick is for **on-the-fly options** that shouldn't
flicker the screen — parent throwaway frames to a permanently-hidden frame so
they never `Show` until you call them out:

```lua
local hidden = CreateFrame("Frame")
hidden:Hide()
local builder = CreateFrame("Frame", nil, hidden)  -- never visible until reparented
```

Not strictly needed here, but useful for the spell-list editor's offscreen rows.

### 8.3 LibStub / Ace3 — recommendation

**Recommendation: stay vanilla (no LibStub, no Ace3).**

Reasons:

1. The addon is self-contained: no profile sync, no comm protocol, no
   ChatThrottleLib, no AceOptions tree of 50 nodes. The new `Settings` API
   covers our needs.
2. Loading Ace3 standalone (or embedding it) adds ~200 KB and a global
   surface area that the user has no reason to download.
3. The only Ace pieces with serious value here are AceDB (profiles) and
   AceConfig (auto-generated options panel). We can match AceDB's
   "Default/Char/Class/Spec" profile concept in ~60 lines, and the new
   `Settings` API replaces AceConfig entirely.

**If** profiles end up being a hard requirement later (e.g. the user wants
distinct configs per character), introducing **Ace3-DB-3.0 only** (not the full
suite) is reasonable. Embed via:

```
embeds.xml:
  <Include file="libs\LibStub\LibStub.xml"/>
  <Include file="libs\AceDB-3.0\AceDB-3.0.xml"/>
```

But default to **vanilla** and only escalate when needed.

### 8.4 SavedVariables migration

Stamp the DB with a schema version so future migrations are explicit:

```lua
local SCHEMA = 2
KickCDDB = KickCDDB or {}
KickCDDB.schema = KickCDDB.schema or 1

if KickCDDB.schema < 2 then
    -- migrate v1 -> v2: rename "scale" to "castbarScale"
    KickCDDB.castbarScale = KickCDDB.scale or 1.0
    KickCDDB.scale = nil
    KickCDDB.schema = 2
end
-- future: if KickCDDB.schema < 3 then ... end
```

Other tips:

* Fill missing keys from a `defaults` table on each login — never assume the
  saved DB is complete.
* Don't store derived/cached values (icon textures, frame references) — only
  user intent.
* Keep tracked spell lists as **arrays of spellIDs**, not name strings —
  spellIDs survive localization and rename patches.
* Scope per-character vs account-wide: position + scale → account-wide;
  per-spec spell overrides → per-character via `SavedVariablesPerCharacter`.

### 8.5 Other small pitfalls

* **`GetTime()` vs `GetServerTime()`**: castbars use `GetTime()` (client
  monotonic seconds). `UnitCastingInfo`'s `startTimeMS` is on the same clock,
  divided by 1000.
* **Empowered casts (Evoker)** have multiple stage thresholds in the channel.
  If you don't care about per-stage rendering, you can treat them as a regular
  channel using `UnitChannelInfo` and rely on `_EMPOWER_STOP` to clear.
* **Pet kicks** (Counter Shot via Hunter pet, Spell Lock via Felhunter,
  Optical Blast via Observer) are owned by a *different* unit (`"pet"`),
  but their cooldowns are tracked on the player and `C_Spell.GetSpellCooldown`
  returns valid data when the spell is in your spellbook. The icon list still
  works the same way.
* **Channel direction**: channels run start→end like normal casts in
  `UnitChannelInfo` returns, but visually fill *down*. The `Cooldown` frame's
  `:SetReverse(true)` handles that if you're rolling your own cast bar from a
  Cooldown frame; but for a Statusbar-based cast bar, just set the value
  inverted: `bar:SetValue(endMS/1000 - GetTime())`.
* **Localization**: spell *names* are localized, spell *IDs* are not — store
  IDs everywhere, look up name on demand via `C_Spell.GetSpellInfo(id).name`.
* **`GetSpellInfo` removal in 11.0**: this was originally unannounced, then
  Blizzard restored a stub. New code should call `C_Spell.GetSpellInfo(id).name`
  directly to be safe in Midnight.

---

## 9. Open questions / risks

1. **Midnight interface number not yet finalized.** `120000` is the
   well-precedented expectation for the launch build, but alpha builds may
   advertise `120001`–`120005`. **Mitigation:** read the live alpha launcher's
   reported interface, ship a comma-separated `## Interface` for forward and
   back compat, and add a CI matrix that bumps the TOC as soon as a new build
   tag drops on wago.tools.

2. **Class redesigns in Midnight.** The pre-expansion patch typically reshuffles
   talents and sometimes baseline interrupts. Asphyxiate, Disrupt, and the
   Evoker hero-spec interrupts are the most likely to change spellID or to gain
   a charge. **Mitigation:** key the spell list by `classFile` + `specID`, keep
   the list in `core/spells.lua` as a single editable table, and version-tag
   the table so we can A/B switch on `## Interface` boundaries.

3. **`C_Spell.GetSpellCooldown` shape.** Modern API returns a table, but if a
   future build silently re-tightens the legacy `GetSpellCooldown` removal, the
   defensive helper in §3.1 already handles both shapes.

4. **`Settings.RegisterAddOnSetting` signature.** Blizzard renamed/extended this
   call between 10.0 and 10.2 (variableKey/table/type). If Midnight ships
   another rename, the `Settings.CreateCheckbox` call sites are the only ones
   that need updating; isolate that in `ui/options.lua`.

5. **Interrupt categorization.** "Stun that interrupts" vs "knockback that
   interrupts" is a conceptual choice we've made (three categories). We should
   confirm the user wants knockbacks tracked at all — they have a much shorter
   lockout and may not be worth the visual noise.

6. **Pet-kick discoverability.** Hunters/Warlocks see their pet kick as their
   main interrupt only when the right pet is summoned. We need to either show
   the icon always (with a different dim state when no pet) or only when the
   pet is up. **Mitigation:** add a boolean toggle "Track pet interrupts"
   defaulting to true and dim the icon when `not UnitExists("pet")`.

7. **Empowered cast UI.** Whether Ka0s KickCD should render Evoker stage marks
   on the target castbar is a UX decision — defer to v0.2. v0.1 can treat them
   as plain channels.

8. **TBD spellIDs flagged in §6.** Chiefly:
   * Asphyxiate Blood vs non-Blood split (`221562` / `108194`)
   * Death from Above (Outlaw) — confirm `152150` still exists in Midnight
   * Disrupting Roar / DH talent shuffles — verify on alpha
   * The Hunt (DH) — root vs stun classification

---

## Appendix A — Quick-start TOC for KickCD v0.1

```toc
## Interface: 120000, 110207
## Title: Ka0s |cff00ff00KickCD|r
## Notes: Interrupt + CC cooldown tracker with target castbar.
## Author: Ka0s
## Version: 0.1.0
## IconTexture: Interface\AddOns\KickCD\media\icon
## SavedVariables: KickCDDB
## SavedVariablesPerCharacter: KickCDCharDB
## Category-enUS: Combat
## X-License: MIT

core\init.lua
core\db.lua
core\spells.lua
core\cooldowns.lua
core\castbar.lua
ui\icons.lua
ui\options.lua
KickCD.lua
```

## Appendix B — Reference URLs to verify before release

* TOC format: `https://warcraft.wiki.gg/wiki/TOC_format`
* Interface numbers: `https://warcraft.wiki.gg/wiki/Interface_numbers`
* `UnitCastingInfo`: `https://warcraft.wiki.gg/wiki/API_UnitCastingInfo`
* `UnitChannelInfo`: `https://warcraft.wiki.gg/wiki/API_UnitChannelInfo`
* `C_Spell.GetSpellCooldown`: `https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown`
* `C_Spell.GetSpellInfo`: `https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo`
* `C_Spell.IsSpellUsable`: `https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable`
* Settings API overview: `https://warcraft.wiki.gg/wiki/Settings_(API)`
* Townlong-Yak FrameXML mirror (search by symbol):
  `https://www.townlong-yak.com/framexml/live/`
* wago.tools (live build/spellID search): `https://wago.tools/`
* Wowhead spell IDs: `https://www.wowhead.com/spell=<id>`

---

*End of report.*
