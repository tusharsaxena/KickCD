local addonName, NS = ...

-- core/SkinSetup.lua — the LibKa0s-Skin-1.0 seam: which skin this addon wears (skinning-§1, §2).
--
-- ── WHAT IT PUBLISHES ────────────────────────────────────────────────────────────────────────
--
--   NS.Skin                 the owner's facade, `Skin:For("KickCD")`: the painting vocabulary
--                           (Shell, Button, Text, IconBorder, ...) and Token / Color / Resolve /
--                           OnLooksChanged. Every surface that draws reads its look here.
--   NS.SkinChoice()         the stored (source, skin) pair, read through NS.Settings.Store.Get;
--                           "ka0s", "ka0s" before Database:Init has built the profile store.
--   NS.WriteSkinChoice(s,k,i,m) the write seam: every half through NS.Settings.Store.Set, the one
--                           seam `/kcd set` and the panel already write through (architecture-§5);
--                           `i`, the Scope's `{ panel, fonts }`, writes the two exceptions, and
--                           `m`, the Font and texture section's `{ font, texture }`, writes the two
--                           overrides, "" for false (the skin's own).
--   NS.ApplySkinIgnore(p,f) moves the applied exceptions: `Skin:SetIgnore`, live; no argument
--                           applies the stored pair, a nil half keeps that half.
--   NS.SkinOverride()       the stored overrides: font, texture, each an LSM key or false for the
--                           skin's own; false, false before the store exists.
--   NS.ApplySkinOverride(f,t) moves the applied overrides: `Skin:SetOverride`, live; no argument
--                           applies the stored pair, a nil half keeps that half, false or "" clears.
--   NS.ApplySkinChoice(s,k) moves the applied skin: `Skin:SetChoice`, which resolves, repaints
--                           every frame recorded for this owner and THEN fires OnLooksChanged. No
--                           argument applies the stored pair (NS:OnInitialize, every profile
--                           event), and with it the stored exceptions and overrides; a nil half
--                           keeps that half (each skin row's onChange).
--   NS.SKIN_SOURCE_VALUES   the source row's values, and NS.SKIN_VALUES the skin row's (every
--   NS.SKIN_VALUES          registered skin), each a { key = label } map with its *_ORDER list,
--                           the shape every KickCD dropdown row carries. settings/General.lua
--                           reads all four.
--   NS.SKIN_FALLBACK        the host copy of the Ka0s Default tokens the degraded facade answers.
--   NS.SkinColor(name)      a SETTINGS PAGE color token as a call site writes it (three components
--                           when opaque), so a literal that became a token keeps its arity on Ka0s
--                           Default. While the Scope's "Ignore settings panel" is on it answers the
--                           Ka0s Default host copy (NS.SKIN_FALLBACK): the pages stay the client's.
--   NS.SkinEscape(name)     the same token as a "|cffrrggbb" escape, rounded to the byte, so markup
--                           written as a literal keeps its bytes on Ka0s Default.
--   NS.SkinResolve(k,v,f)   a HUD media pick as drawn: the skin's token `k` while the companion `f`
--                           is true, else (or when the skin answers nothing) the stored pick `v`.
--   NS.OnSkinLooksChanged(fn) a HUD module's repaint, run after a skin, source or override change.
--   NS.SkinPaintAce(w)      an AceGUI widget this addon acquired itself, painted for this owner:
--   NS.SkinPaintAceTree(c)  `Skin:PaintAce` / `Skin:PaintAceTree` with the owner bound (the facade
--                           carries neither). Release restores stock.
--   NS.SkinOnRelease(w, fn) host release work chained onto the widget's own OnRelease
--                           (`Skin:OnRelease`), so it and the skin's restore both run.
--   NS.MaybeShowSkinPicker() the first-run skin picker (LibKa0s OptionsSkinPicker 1, owner ruling
--                           O3): the Options instance's SkinPicker while the profile's
--                           `skin.pickerSeen` is false and the addon stands up; held to
--                           PLAYER_REGEN_ENABLED in combat. Answers the frame, or nil, "queued"
--                           behind another Ka0s addon's picker.
--   NS.HideSkinPicker()     takes a shown picker down (its pending preview put back) or out of the
--                           queue WITHOUT marking it seen: the stand-down, a profile that has seen
--                           it, and first on every profile event; drops a held combat deferral.
--   NS.SkinPickerSpec()     the spec MaybeShowSkinPicker hands the library.
--
-- ── WHERE IT LOADS ───────────────────────────────────────────────────────────────────────────
--
-- Straight after core/CoreSetup.lua (NS.Util.print, which the reload line below prints through)
-- and before every module that builds a frame, so NS.Skin exists for all of them. The schema rows
-- (settings/General.lua) read the four value tables at file load and are far below. The fixed name
-- is the one LibKa0s's docs/api/CONSUMERS.md cites. Nothing here reads the profile at load:
-- RegisterOwner calls `get` once, before AceDB exists, and it answers Ka0s Default; the profile's
-- pair is applied by NS.ApplySkinChoice right after Database:Init (core/KickCD.lua).
--
-- ── NO OWNER TOKENS ──────────────────────────────────────────────────────────────────────────
--
-- The M0 inventory found no color KickCD draws that a library token does not hold exactly
-- (Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT/inputs/inventory/KickCD.md §5: no
-- gaps), so RegisterOwner carries no `tokens` table (X1, X2, X12 have nothing to name here).
--
-- ── WHY A ROW'S onChange PASSES ONE HALF ─────────────────────────────────────────────────────
--
-- The Skin tab and another addon's "Copy to every Ka0s addon" both call Skin:SetChoice FIRST and
-- write the store after, one half at a time. A row reaction that re-applied the whole stored pair
-- would apply the half-written one in between: a second repaint, to a skin the player never
-- picked. Applying only the row's own half against the applied choice makes each write a no-op
-- (SetChoice is idempotent), so a pick is ONE effective SetChoice and one repaint, while a bare
-- `/kcd set skin.skin obsidian` still repaints.
--
-- Nothing skin-related keys off CONFIG_CHANGED. A surface that has to rebuild on a skin change
-- subscribes to NS.Skin.OnLooksChanged, which fires after the new skin is resolved and the
-- recorded frames are repainted.

local Skin = LibStub and LibStub("LibKa0s-Skin-1.0", true)
local L = NS.L

local SOURCE_PATH, SKIN_PATH = "skin.source", "skin.skin"
local PANEL_PATH, FONTS_PATH = "skin.ignorePanel", "skin.ignoreFonts"
local FONT_PATH, TEXTURE_PATH = "skin.font", "skin.texture"
local DEFAULT = "ka0s"

-- Every stored skin path, for settings/General.lua's rows and the seam's resetExempt
-- (settings/SchemaSetup.lua): the General page's Defaults restores Master controls, never the skin.
NS.SKIN_PATHS = {
    SOURCE_PATH, SKIN_PATH, PANEL_PATH, FONTS_PATH, FONT_PATH, TEXTURE_PATH, "skin.pickerSeen",
}

-- The Ka0s Default tokens the DEGRADED facade answers, copied from the library and limited to the
-- ones this addon reads. Both arms publish the table, so tests/test_surface_parity.lua holds each
-- entry to the live library's Ka0s Default value: a copy that drifts goes red there. A surface
-- converted to a token adds the token here in the same change.
NS.SKIN_FALLBACK = {
    ["title.text"]  = { 1, 0.82, 0, 1 },
    ["text.accent"] = { 1, 0.82, 0, 1 },
    ["close.hot"]   = { 1, 0.3, 0.3, 1 },   -- the Spells rows' Remove mark
    ["sem.warn"]    = { 1, 0.5, 0, 1 },     -- the add box's "not tracked" tag
    ["gtip.title"]  = { 1, 0.82, 0, 1 },    -- the Spells rows' own tooltip hints
}

--- A settings page's color token, as drawn: the skin's while this owner's settings panel is skinned,
--- and the Ka0s Default host copy while the Scope ignores it (Skin:GetIgnore, the APPLIED pair, so a
--- toggle answers at once; SetIgnore fires OnLooksChanged and the page re-renders). Every caller of
--- NS.SkinColor / NS.SkinEscape is a settings page, which is why the gate lives here.
local function pageColor(name)
    if Skin and type(Skin.GetIgnore) == "function" and Skin:GetIgnore(addonName) == true then
        local c = NS.SKIN_FALLBACK[name]
        if c then return c[1], c[2], c[3], c[4] or 1 end
    end
    return NS.Skin.Color(name)
end

--- A color token's components AS A CALL SITE WRITES THEM: r, g, b for an opaque color and r, g, b,
--- a otherwise, so a site that passed three components before it read a token still passes three
--- on Ka0s Default. nil for a token the skin leaves alone. Read through pageColor at call time.
function NS.SkinColor(name)
    local r, g, b, a = pageColor(name)
    if r == nil then return nil end
    if a == nil or a == 1 then return r, g, b end
    return r, g, b, a
end

--- A color token as a "|cffrrggbb" escape, each channel rounded to the nearest byte, so markup a
--- call site wrote as a literal keeps its bytes on Ka0s Default. nil for a token the skin leaves
--- alone.
function NS.SkinEscape(name)
    local r, g, b = pageColor(name)
    if r == nil then return nil end
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

--- A HUD media pick as the HUD draws it (KC-03, skinning-§6): the skin's token `kind` while the
--- pick's "Use the skin's ..." companion is true, the stored pick otherwise, and the stored pick
--- again when the skin answers nothing (the degraded facade's host copy holds no HUD token), so
--- the HUD never draws a nil face, texture or border. Read in the config paths only (Layout,
--- Reskin, Apply), never in a ticker: it is a token read per call.
function NS.SkinResolve(kind, value, fromSkin)
    local S = NS.Skin
    if fromSkin ~= true or not (S and S.Resolve) then return value end
    local v = S.Resolve(kind, value, true)
    if v == nil then return value end
    return v
end

--- Subscribe a HUD module's repaint to the owner's looks (a skin switch, a source switch, a font
--- or texture override): the listener runs after the library has resolved the new skin. Nothing
--- without the library, whose skin never changes.
function NS.OnSkinLooksChanged(fn)
    local S = NS.Skin
    if S and S.OnLooksChanged then return S.OnLooksChanged(fn) end
end

NS.SKIN_SOURCE_VALUES = { ka0s = L["Ka0s skins"], eui = L["EllesmereUI"] }
NS.SKIN_SOURCE_ORDER  = { "ka0s", "eui" }

-- The skin row's values: every registered skin, in the library's order (Ka0s Default first).
-- Without the library the one skin the degraded facade can draw.
NS.SKIN_VALUES, NS.SKIN_ORDER = {}, {}
if Skin and type(Skin.Skins) == "function" then
    for _, def in ipairs(Skin:Skins()) do
        NS.SKIN_VALUES[def.key] = def.label or def.key
        NS.SKIN_ORDER[#NS.SKIN_ORDER + 1] = def.key
    end
end
if #NS.SKIN_ORDER == 0 then
    NS.SKIN_VALUES[DEFAULT] = L["Ka0s Default"]
    NS.SKIN_ORDER[1] = DEFAULT
end

--- The seam's read, nil-safely: nil before the profile store exists.
local function stored(path)
    local Store = NS.db and NS.Settings and NS.Settings.Store
    if not (Store and Store.Get) then return nil end
    return Store.Get(path)
end

--- The stored pair, lazily and nil-safely: Ka0s Default until the profile store exists.
function NS.SkinChoice()
    return stored(SOURCE_PATH) or DEFAULT, stored(SKIN_PATH) or DEFAULT
end

--- A stored override as the profile keeps it: the LSM key, or "" for the skin's own (false, nil, "").
local function storedKey(v)
    if type(v) == "string" and v ~= "" then return v end
    return ""
end

--- The write seam: every half through NS.Settings.Store.Set (validate, store, the [Set] line,
--- onChange). `media` is `{ font = key|false, texture = key|false }`: the Skin tab's Font and
--- texture pick and another addon's copy both hand it here, after Skin:SetOverride moved the
--- applied pair, so each row's onChange re-applies its own half as a no-op.
function NS.WriteSkinChoice(source, skin, ignore, media)
    local Store = NS.db and NS.Settings and NS.Settings.Store
    if not (Store and Store.Set) then return end
    if source ~= nil then Store.Set(SOURCE_PATH, source) end
    if skin ~= nil then Store.Set(SKIN_PATH, skin) end
    if type(ignore) == "table" then
        Store.Set(PANEL_PATH, ignore.panel == true)
        Store.Set(FONTS_PATH, ignore.fonts == true)
    end
    if type(media) == "table" then
        Store.Set(FONT_PATH, storedKey(media.font))
        Store.Set(TEXTURE_PATH, storedKey(media.texture))
    end
end

--- The stored overrides, nil-safely: each an LSM key, or false for the skin's own.
function NS.SkinOverride()
    local font, texture = storedKey(stored(FONT_PATH)), storedKey(stored(TEXTURE_PATH))
    return font ~= "" and font or false, texture ~= "" and texture or false
end

--- The stored exceptions, nil-safely: the settings panel left the client's, the fonts skinned,
--- until the profile store exists (the defaults, defaults/Profile.lua).
local function storedIgnore()
    local panel, fonts = stored(PANEL_PATH), stored(FONTS_PATH)
    if panel == nil then panel = true end
    return panel == true, fonts == true
end

-- AceGUI keeps ONE callback per event name (options-ui-§19). Without the library's chain there is
-- no skin restore to share the release with, so the host's work takes the callback, as it did
-- before the skin engine.
local function releaseByCallback(widget, fn)
    if type(widget) ~= "table" or type(fn) ~= "function" or type(widget.SetCallback) ~= "function" then
        return nil
    end
    widget:SetCallback("OnRelease", function(w) fn(w) end)
    return fn
end

-- ── the first-run skin picker (LibKa0s OptionsSkinPicker 1, owner ruling O3) ─────────────────
--
-- WHEN. Once per session at login (NS:OnEnable, after the options panel is registered, so the
-- gear has a page to open, and after the `disabled` hold is taken, so a switched-off addon shows
-- nothing), and again after every profile event (Database:OnProfileChanged), because a new, copied
-- or reset profile carries its own `skin.pickerSeen`. Never while the addon stands down, and never
-- in combat: a start in combat is held for the PLAYER_REGEN_ENABLED edge, one target at most (the
-- library's queue waits out combat only for the NEXT owner's picker; a first call with nothing up
-- shows at once, whatever the lockdown). The test is InCombatLockdown alone, not NS.State.inCombat:
-- the held start runs ON the PLAYER_REGEN_ENABLED edge, possibly before core/State.lua's own
-- handler clears its flag, and a flag still set there would hold the start for the next combat.
--
-- SEEN. The library calls `onClose` once per showing, by any route the player takes (Apply, its
-- close control, the gear, Escape), and once for a picker still queued behind another Ka0s addon's
-- when that addon's "Apply to all Ka0s addons" dismisses it unshown; that is the one write of
-- `skin.pickerSeen`, through NS.Settings.Store.Set. A close this addon makes itself
-- (NS.HideSkinPicker: the stand-down, a profile event) is not the player's and writes nothing.
--
-- NO EYE (the rollout's X6). KickCD draws no window of its own. It has a simulator (`/kcd sim`,
-- modules/Sim.lua), but that is a scripted session, not a preview mode: it swaps the world the
-- HUD reads for a timed story, opens its own step panel and strip, ends on combat, a loading
-- screen or a group, and refuses a start in combat, an instance, a group or while unlocked. Starting one from the picker would play
-- a story the player did not ask for. The other preview, unlocking the grid and the cast bars, is
-- a stored write (`locked`) and refuses a running simulation. So `onPreview` is absent and the
-- library hides the button; a pick still previews live on the HUD (OnLooksChanged), the drag
-- handles and the settings chrome, and a simulation the player started wears the pick too.
--
-- PREVIEW. A pick only previews: the Skin major moves and the HUD repaints, but `set`
-- (NS.WriteSkinChoice) runs only on Apply, the gear or Apply to all. The close control and Escape
-- put back the stored choice as it reads at the close (the library's revert reads `get`). A
-- profile event takes the picker down FIRST, before the new profile's skin is applied, so the new
-- profile's whole pair is what NS.ApplySkinChoice leaves worn.
--
-- Above the degraded arm because it reads only the Options instance: without the library the
-- stub's SkinPicker answers nil and draws nothing (settings/OptionsSetup.lua).

local PICKER_PATH = "skin.pickerSeen"
local pickerTarget       -- the one-shot PLAYER_REGEN_ENABLED target, while a start is held
local quietClose = false -- true while NS.HideSkinPicker takes the picker down

--- The Options instance (settings/OptionsSetup.lua's NS.Settings.Helpers), read at call time: it
--- loads after this file.
local function options() return NS.Settings and NS.Settings.Helpers end

--- The player's close: the picker seen, and nothing else. The library's put-back already wears the
--- stored choice, so the skin is not this callback's to move.
local function pickerClosed()
    if quietClose then return end
    local Store = NS.db and NS.Settings and NS.Settings.Store
    if not (Store and Store.Set) then return end
    Store.Set(PICKER_PATH, true)
end

function NS.SkinPickerSpec()
    return {
        owner = addonName, get = NS.SkinChoice, set = NS.WriteSkinChoice,
        -- The gear's default: O.OpenOptionsPanel("general"), the key settings/General.lua gave
        -- RegisterOptionsPage, then O.SelectTab("general", "Appearance"), the Skin tab's key.
        page = "general", tab = "Appearance",
        onClose = pickerClosed,
    }
end

local function dropPickerDeferral()
    if pickerTarget then pickerTarget:UnregisterAllEvents(); pickerTarget = nil end
end

local function inCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown()) == true
end

--- True while this profile has not closed the picker and the addon stands up.
local function pickerDue()
    if stored(PICKER_PATH) ~= false then return false end
    return not (NS.IsDown and NS.IsDown())
end

function NS.HideSkinPicker()
    dropPickerDeferral()
    local O = options()
    if not (O and type(O.HideSkinPicker) == "function") then return end
    quietClose = true
    local ok, err = pcall(O.HideSkinPicker)
    quietClose = false
    if not ok then error(err, 0) end
end

--- Show the picker when this profile has not seen it: answers the library's frame, or nil,
--- "queued" while another Ka0s addon's picker is up (it shows when that one closes), or nil.
function NS.MaybeShowSkinPicker()
    local O = options()
    if not (O and type(O.SkinPicker) == "function") then return nil end
    if not pickerDue() then
        NS.HideSkinPicker()
        return nil
    end
    if inCombat() then
        if pickerTarget then return nil end
        pickerTarget = NS.NewBusTarget and NS.NewBusTarget()
        if not pickerTarget then return nil end
        NS.SafeRegisterEvent(pickerTarget, "PLAYER_REGEN_ENABLED", function()
            dropPickerDeferral()
            NS.MaybeShowSkinPicker()
        end, NS.State and NS.State.rejectedEvents)
        return nil
    end
    return O.SkinPicker(NS.SkinPickerSpec())
end

-- ── the degraded arm ─────────────────────────────────────────────────────────────────────────

if not Skin then
    local function color(name)
        local c = NS.SKIN_FALLBACK[name]
        if c then return c[1], c[2], c[3], c[4] or 1 end
    end
    local function noop() end
    local S = { owner = addonName, apiVersion = 3, FROM_SKIN = "@skin" }
    -- Every vocabulary name answers, and a primitive with no host meaning is a no-op that never
    -- raises: without the library every KickCD frame keeps the look it builds itself. The list is
    -- LibKa0s-Skin-1.0's VOCAB; tests/test_surface_parity.lua holds this table to the live facade
    -- key for key.
    for _, name in ipairs({
        "Shell", "Panel", "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel",
        "StateButtonLabel", "EditBox", "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection",
        "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar", "Font", "White", "ApplyBarFill",
        "GetAccentColor", "GetPanelColor", "GetFont",
        "TitleBar", "Divider", "Footer", "Card", "Slider", "NavItem", "Drawer", "ListRow", "MenuFrame",
        "Tooltip", "Strip", "Cover", "Text", "ChartStyle", "BarStyle", "IconBorder", "GlowColor",
        "BarTexture",
    }) do S[name] = noop end

    S.Token = function(name) return NS.SKIN_FALLBACK[name] end
    S.Color = color
    -- A HUD value that follows the skin keeps the player's stored value when the host copy holds no
    -- token for it, so a degraded HUD draws what it drew before skins rather than nothing.
    S.Resolve = function(kind, value, fromSkin)
        if fromSkin or value == S.FROM_SKIN then
            local t = S.Token(kind)
            if t ~= nil then return t end
            if value == S.FROM_SKIN then return nil end
        end
        return value
    end
    S.OnLooksChanged = function(fn) return fn end   -- the skin never changes without the library
    S.IsEnabled = function() return false end
    S.GetStyle = function() return "ka0s:" .. DEFAULT end
    S.Text = function(fs, role)
        local r, g, b, a = color(role == "title" and "title.text" or ("text." .. tostring(role)))
        if r and fs and fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
    end
    S.GetFont = function() return _G.STANDARD_TEXT_FONT end
    S.ChartStyle = function() return {} end
    S.BarStyle = function() return {} end

    NS.Skin = S
    function NS.ApplySkinChoice() return false, false end
    function NS.ApplySkinIgnore() return false, false end
    function NS.ApplySkinOverride() return false end
    -- Nothing to paint an AceGUI row with: stock AceGUI, as the client draws it.
    function NS.SkinPaintAce() return false end
    function NS.SkinPaintAceTree() return 0 end
    NS.SkinOnRelease = releaseByCallback
    return
end

-- ── the live seam ────────────────────────────────────────────────────────────────────────────

NS.Skin = Skin:For(addonName)
Skin:RegisterOwner(addonName, {
    label = L["Ka0s KickCD"],
    get = NS.SkinChoice,
    set = NS.WriteSkinChoice,
})

-- The one line a reload request earns on the path that has no popup of its own (a profile event
-- leaving an EllesmereUI that painted this session). The Skin tab raises the library's popup for
-- its own picks.
local RELOAD_LINE = L["Reload your interface (/reload) to finish changing the skin."]

local function say(line)
    if NS.Util and NS.Util.print then NS.Util.print(line) end
end

-- The AceGUI rows (SkinAce.lua). Each guards on the member, so a copy whose SkinAce secondary did
-- not attach paints nothing.
function NS.SkinPaintAce(widget)
    if type(Skin.PaintAce) ~= "function" then return false end
    return Skin:PaintAce(addonName, widget)
end

function NS.SkinPaintAceTree(container)
    if type(Skin.PaintAceTree) ~= "function" then return 0 end
    return Skin:PaintAceTree(addonName, container)
end

function NS.SkinOnRelease(widget, fn)
    if type(Skin.OnRelease) ~= "function" then return releaseByCallback(widget, fn) end
    return Skin:OnRelease(widget, fn)
end

function NS.ApplySkinIgnore(panel, fonts)
    if type(Skin.SetIgnore) ~= "function" then return false, false end
    if panel == nil and fonts == nil then panel, fonts = storedIgnore() end
    local changed, reload = Skin:SetIgnore(addonName, panel, fonts)
    if reload then say(RELOAD_LINE) end
    return changed, reload
end

--- No argument applies the stored overrides; a nil half keeps that half, false or "" clears it
--- (the skin's own). A copy without SetOverride (a Skin major before minor 6) moves nothing.
function NS.ApplySkinOverride(font, texture)
    if type(Skin.SetOverride) ~= "function" then return false end
    if font == nil and texture == nil then font, texture = NS.SkinOverride() end
    return Skin:SetOverride(addonName, font, texture)
end

--- No argument applies the stored pair AND the stored exceptions and overrides (NS:OnInitialize,
--- the profile events); a nil half keeps that half and leaves the rest alone (each skin row).
function NS.ApplySkinChoice(source, skin)
    local whole = source == nil and skin == nil
    if whole then source, skin = NS.SkinChoice() end
    local changed, reload = Skin:SetChoice(addonName, source, skin)
    if reload then say(RELOAD_LINE) end
    if whole then
        NS.ApplySkinIgnore()
        NS.ApplySkinOverride()
    end
    return changed, reload
end
