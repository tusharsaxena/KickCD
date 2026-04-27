-- settings/Profiles.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §5.4, docs/REQUIREMENTS.md FR-6.2.5 + FR-10.4
--
-- Pure delegation to AceDBOptions-3.0. The AceDBOptions:GetOptionsTable call
-- builds the full create / switch / copy / reset / delete UI plus the
-- per-character / per-class / per-realm / per-faction / default scope
-- dropdowns automatically — there's no widget code we need to write here,
-- only the wiring. AceConfig + AceConfigDialog do the rendering.

local KickCD = LibStub and LibStub("AceAddon-3.0", true)
                  and LibStub("AceAddon-3.0"):GetAddon("KickCD", true)
                  or _G.KickCD
KickCD = KickCD or {}

local L = KickCD.L or setmetatable({}, { __index = function(_, k) return k end })

local Profiles = {}
KickCD.SettingsProfiles = Profiles

--- Build the Profiles subcategory under the main KickCD settings category.
-- Idempotent: if the libs are missing or the parent category isn't ready,
-- we silently no-op. The PLAYER_LOGIN driver below retries until both
-- conditions are satisfied.
function Profiles:Register()
    if self._registered then return true end
    if not LibStub then return false end

    local AceDBOptions   = LibStub("AceDBOptions-3.0",   true)
    local AceConfig      = LibStub("AceConfig-3.0",      true)
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    if not (AceDBOptions and AceConfig and AceConfigDialog) then
        return false
    end
    if not (KickCD.db and KickCD.db.profile) then
        return false
    end
    -- AceConfigDialog calls Settings.GetCategory(parentID) which on 12.0+
    -- requires the numeric category ID. Panel.lua stamps this once the
    -- main "Ka0s KickCD" category is registered; until then, retry.
    if not KickCD.SettingsCategoryID then
        return false
    end

    -- AceDBOptions returns a fully-formed AceConfig-3.0 options table that
    -- describes the entire profile management UI. We register it under a
    -- KickCD-namespaced key so it can be opened independently and added
    -- to Blizzard's settings tree.
    local opts = AceDBOptions:GetOptionsTable(KickCD.db)
    AceConfig:RegisterOptionsTable("KickCD-Profiles", opts)

    -- AddToBlizOptions returns a Frame compatible with the legacy
    -- InterfaceOptions panel. On modern clients (10.0+) Blizzard's
    -- Settings shim still routes legacy panels through Settings, so this
    -- shows up as a sibling subcategory next to General/Icons/Castbar/Spells
    -- under the KickCD parent — meeting REQUIREMENTS FR-6.2.5.
    local frame = AceConfigDialog:AddToBlizOptions(
        "KickCD-Profiles",
        L["Profiles"],
        KickCD.SettingsCategoryID)

    KickCD.Settings = KickCD.Settings or {}
    KickCD.Settings.sub = KickCD.Settings.sub or {}
    KickCD.Settings.sub.profiles = frame

    self._registered = true
    return true
end

-- Drive registration from PLAYER_LOGIN. PLAYER_LOGIN fires once per session
-- after every addon's OnInitialize and OnEnable, so KickCD.db is guaranteed
-- to be in place by the time we get here. If a prerequisite is somehow
-- missing (e.g. AceDBOptions not vendored), we retry briefly and then give
-- up silently — Profiles is non-essential to runtime behavior.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not Profiles:Register() then
        local attempts = 0
        local ticker
        ticker = C_Timer.NewTicker(0.25, function()
            attempts = attempts + 1
            if Profiles:Register() or attempts >= 8 then
                if ticker and ticker.Cancel then ticker:Cancel() end
            end
        end)
    end
end)
