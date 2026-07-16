-- tests/wow_mock.lua
-- WoW API mock builder for the headless test harness (§14A.1).
--
-- Returns a builder: each call to build() produces a FRESH `mocks` table
-- (the fake WoW global namespace) plus a fresh LibStub with fake Ace3 libs,
-- so every test instance is fully isolated. The key correctness requirement
-- (§4.4 / AP-33) is that the AceEvent fake keys message callbacks by
-- (message, target) and fans SendMessage out to EVERY registered target —
-- a no-op bus mock would hide the last-registrant-wins clobber bug.

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = deepcopy(vv) end
    return out
end

-- Numeric frame getters must return numbers, not the frame — otherwise code
-- like `border:SetFrameLevel(btn:GetFrameLevel() + 1)` does arithmetic on a
-- table and throws. Values are inert defaults chosen not to divide-by-zero.
local NUMERIC_GETTERS = {
    GetFrameLevel = 0, GetWidth = 0, GetHeight = 0,
    GetScale = 1, GetEffectiveScale = 1, GetAlpha = 1,
    GetLeft = 0, GetRight = 0, GetTop = 0, GetBottom = 0,
    GetNumPoints = 0, GetStringWidth = 0, GetStringHeight = 0,
    GetTextWidth = 0, GetTextHeight = 0,
}

-- Universal self-returning no-op frame (§14A.1): every method call returns a
-- function that returns the frame, so any `:SetX():SetY()` chain is inert.
-- Numeric getters (NUMERIC_GETTERS) instead return a number so the lifecycle
-- paths (OnEnable → layout/reskin) that do arithmetic on them run headlessly.
local function makeFrame()
    local f = {}
    -- Explicit fields (take precedence over the __index fallback below) so
    -- Util.RegisterUnitCastEvent's dispatch frame is testable headlessly:
    -- record RegisterUnitEvent(event, unit) and let tests fire the stored
    -- OnEvent handler via f:_fire(event, ...). Test-scoped only.
    function f.RegisterUnitEvent(self, ev, unit)
        self._unitEvents = self._unitEvents or {}
        self._unitEvents[ev] = unit
    end
    function f.SetScript(self, which, fn)
        if which == "OnEvent" then self._onevent = fn end
        return self   -- other scripts (OnDragStart/OnUpdate/…) are harmless no-ops
    end
    function f._fire(self, ev, ...)
        if self._onevent then self._onevent(self, ev, ...) end
    end
    -- Explicit SetParent/GetParent (test-scoped, mirrors RegisterUnitEvent/
    -- SetScript above): records the parent so tests can assert which frame a
    -- module reparented onto, without modelling real WoW parent/visibility
    -- inheritance.
    function f.SetParent(self, p) self._parent = p end
    function f.GetParent(self) return self._parent end
    return setmetatable(f, {
        __index = function(_, k)
            local n = NUMERIC_GETTERS[k]
            if n ~= nil then return function() return n end end
            -- WoW frame API methods are PascalCase (SetPoint, CreateTexture);
            -- addon-stored data fields are camelCase/underscore (icon, cfg,
            -- _lastState). Return a no-op method for the former, nil for an
            -- unset data field — a real frame returns nil there, not a
            -- callable. Returning a function masked/created bugs: an unset
            -- self._lastState read back as a function and blew up Icon:Apply.
            if type(k) == "string" and k:match("^%u") then
                return function() return f end
            end
            return nil
        end,
    })
end

--- Resolve an AceEvent callback registration (function OR method-name string)
--- to a single callable of the form fn(message, ...), matching CallbackHandler.
local function resolveCallback(target, method)
    if type(method) == "function" then
        return function(message, ...) return method(message, ...) end
    elseif type(method) == "string" then
        return function(message, ...)
            local fn = target[method]
            if fn then return fn(target, message, ...) end
        end
    end
end

local function build()
    local mocks = {}

    -- Deferred-timer queue so Throttle / C_Timer.After can be flushed on demand.
    local timers = {}
    mocks.__timers = timers
    mocks.__flushTimers = function()
        -- Copy-and-clear so a callback that schedules another timer doesn't
        -- mutate the list mid-iteration.
        local pending = timers
        mocks.__timers = {}
        timers = mocks.__timers
        for _, cb in ipairs(pending) do cb() end
    end

    -- -------------------------------------------------------------------
    -- Shared message bus (the whole point of the mock — see header)
    -- -------------------------------------------------------------------
    -- registry[message][target] = resolvedCallback   (keyed by target!)
    local registry = {}
    mocks.__busRegistry = registry

    local function embedAceEvent(t)
        function t.RegisterMessage(self, message, method, arg)
            registry[message] = registry[message] or {}
            registry[message][self] = resolveCallback(self, method or message)
            return arg
        end
        function t.UnregisterMessage(self, message)
            if registry[message] then registry[message][self] = nil end
        end
        function t.SendMessage(self, message, ...)
            local targets = registry[message]
            if not targets then return end
            for _, cb in pairs(targets) do cb(message, ...) end
        end
        -- Event side is a no-op for headless tests (no game events fire).
        function t.RegisterEvent() end
        function t.UnregisterEvent() end
        function t.UnregisterAllEvents() end
        return t
    end
    mocks.__embedAceEvent = embedAceEvent

    local function embedAceTimer(t)
        function t.ScheduleTimer(_, method, delay) return { method = method, delay = delay } end
        function t.ScheduleRepeatingTimer(_, method, delay) return { method = method, delay = delay } end
        function t.CancelTimer() end
        function t.CancelAllTimers() end
        return t
    end

    local function embedAceConsole(t)
        function t.RegisterChatCommand() end
        function t.UnregisterChatCommand() end
        function t.Print() end
        return t
    end

    -- -------------------------------------------------------------------
    -- Fake AceAddon: addon object + module lifecycle
    -- -------------------------------------------------------------------
    local addons = {}

    local function newModule(addon, name, ...)
        local m = { moduleName = name }
        embedAceEvent(m)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin == "AceTimer-3.0" then embedAceTimer(m) end
            if mixin == "AceConsole-3.0" then embedAceConsole(m) end
        end
        addon.__modules = addon.__modules or {}
        addon.__moduleOrder = addon.__moduleOrder or {}
        addon.__modules[name] = m
        addon.__moduleOrder[#addon.__moduleOrder + 1] = name
        return m
    end

    local AceAddon = {
        NewAddon = function(_, objOrName, ...)
            local obj, name, firstMixin
            if type(objOrName) == "table" then
                obj, name, firstMixin = objOrName, (select(1, ...)), 2
            else
                obj, name, firstMixin = {}, objOrName, 1
            end
            embedAceEvent(obj)
            for i = firstMixin, select("#", ...) do
                local mixin = select(i, ...)
                if mixin == "AceTimer-3.0" then embedAceTimer(obj) end
                if mixin == "AceConsole-3.0" then embedAceConsole(obj) end
            end
            function obj.NewModule(self, modName, ...) return newModule(self, modName, ...) end
            function obj.GetModule(self, modName)
                return self.__modules and self.__modules[modName]
            end
            function obj.EnableModule() end
            -- Faithful stand-in for AceAddon's PLAYER_LOGIN EnableAddon cascade:
            -- enable the addon, then every module in registration order, calling
            -- OnEnable where defined. A load-only harness never reaches OnEnable,
            -- so this is what lets headless tests exercise the module lifecycle
            -- (the path where the IconGrid.Layout method/table clobber hid — KCD-05).
            -- Errors propagate so the calling test's pcall reports the failure.
            function obj.__enableAll(self)
                self.enabledState = true
                if self.OnEnable then self:OnEnable() end
                for _, modName in ipairs(self.__moduleOrder or {}) do
                    local m = self.__modules[modName]
                    m.enabledState = true
                    if m.OnEnable then m:OnEnable() end
                end
            end
            addons[name] = obj
            return obj
        end,
        GetAddon = function(_, name) return addons[name] end,
    }

    -- -------------------------------------------------------------------
    -- Fake AceDB: static default merge is enough for headless assertions
    -- -------------------------------------------------------------------
    local AceDB = {
        New = function(_, _name, defaults, _defaultProfile)
            local db = {
                keys = { profile = "Default" },
                profile = deepcopy(defaults and defaults.profile or {}),
                global  = deepcopy(defaults and defaults.global or {}),
                char    = deepcopy(defaults and defaults.char or {}),
            }
            function db.RegisterCallback() end
            function db.GetCurrentProfile() return "Default" end
            function db.GetProfiles(_, t) t = t or {}; t[1] = "Default"; return t end
            function db.SetProfile() end
            function db.ResetProfile() end
            function db.CopyProfile() end
            function db.DeleteProfile() end
            return db
        end,
    }

    -- Generic self-returning no-op lib for everything else we LibStub.
    local function noopLib()
        local l = {}
        return setmetatable(l, { __index = function() return function() return l end end })
    end

    local LSM = noopLib()
    LSM.MediaType = { FONT = "font", STATUSBAR = "statusbar", BORDER = "border", SOUND = "sound" }
    function LSM.Register() return true end
    function LSM.Fetch() return "Fonts\\FRIZQT__.TTF" end
    function LSM.List() return {} end
    function LSM.HashTable() return {} end
    function LSM.IsValid() return true end

    local libs = {
        ["AceAddon-3.0"]        = AceAddon,
        ["AceDB-3.0"]           = AceDB,
        ["AceEvent-3.0"]        = { Embed = function(_, t) return embedAceEvent(t) end },
        ["AceTimer-3.0"]        = { Embed = function(_, t) return embedAceTimer(t) end },
        ["AceConsole-3.0"]      = { Embed = function(_, t) return embedAceConsole(t) end },
        ["AceGUI-3.0"]          = (function()
            local g = noopLib()
            function g.Create() return makeFrame() end
            function g.RegisterWidgetType() end
            return g
        end)(),
        ["AceConfig-3.0"]         = noopLib(),
        ["AceConfigDialog-3.0"]   = noopLib(),
        ["AceConfigRegistry-3.0"] = noopLib(),
        ["AceDBOptions-3.0"]      = noopLib(),
        ["LibSharedMedia-3.0"]    = LSM,
        ["LibCustomGlow-1.0"]     = noopLib(),
        ["CallbackHandler-1.0"]   = noopLib(),
    }

    mocks.LibStub = setmetatable({}, {
        __call = function(_, name, silent)
            local lib = libs[name]
            if not lib and not silent then error("mock LibStub: missing lib " .. tostring(name)) end
            return lib
        end,
        __index = { GetLibrary = function(_, name) return libs[name] end },
    })
    mocks.__libs = libs

    -- -------------------------------------------------------------------
    -- Frames / UI
    -- -------------------------------------------------------------------
    mocks.CreateFrame = function() return makeFrame() end
    mocks.UIParent = makeFrame()
    mocks.UISpecialFrames = {}
    mocks.DEFAULT_CHAT_FRAME = makeFrame()
    mocks.GameTooltip = makeFrame()
    mocks.Mixin = function(t, ...)
        for i = 1, select("#", ...) do
            local src = select(i, ...)
            if type(src) == "table" then for k, v in pairs(src) do t[k] = v end end
        end
        return t
    end
    mocks.CreateFromMixins = function(...) return mocks.Mixin({}, ...) end
    mocks.BackdropTemplateMixin = {}

    -- -------------------------------------------------------------------
    -- Time / timers
    -- -------------------------------------------------------------------
    mocks.GetTime = function() return 0 end
    mocks.GetTimePreciseSec = function() return 0 end
    mocks.C_Timer = {
        After = function(_, fn) timers[#timers + 1] = fn end,
        NewTimer = function(_, fn) timers[#timers + 1] = fn; return makeFrame() end,
        NewTicker = function() return makeFrame() end,
    }

    -- -------------------------------------------------------------------
    -- Spell / unit / combat APIs (safe inert returns)
    -- -------------------------------------------------------------------
    mocks.C_Spell = {
        GetSpellInfo = function(id) return { name = "Spell" .. tostring(id), iconID = 12345, spellID = id } end,
        GetSpellCooldown = function() return { isEnabled = true, startTime = 0, duration = 0 } end,
        GetSpellTexture = function() return 12345 end,
        IsSpellUsable = function() return true end,
    }
    mocks.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 253, "Beast Mastery", nil, 12345, "DAMAGER" end,
    }
    mocks.GetSpecialization = function() return 1 end
    mocks.GetSpecializationInfo = function() return 253, "Beast Mastery", nil, 12345, "DAMAGER" end
    mocks.GetSpellInfo = function(id) return "Spell" .. tostring(id), nil, 12345 end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
    mocks.UnitExists = function() return false end
    mocks.UnitCanAttack = function() return true end
    mocks.UnitClass = function() return "Hunter", "HUNTER" end
    mocks.UnitRace = function() return "Orc", "Orc" end
    mocks.UnitIsUnit = function() return false end
    mocks.UnitIsDead = function() return false end
    mocks.UnitGUID = function() return "Player-0000-00000000" end
    mocks.UnitName = function() return "Tester" end
    mocks.IsPlayerSpell = function() return true end
    mocks.IsSpellKnown = function() return true end
    mocks.IsSpellKnownOrOverridesKnown = function() return true end
    mocks.IsLoggedIn = function() return true end
    mocks.InCombatLockdown = function() return false end
    mocks.issecretvalue = function() return false end
    mocks.securecallfunction = function(fn, ...) if fn then return fn(...) end end
    mocks.hooksecurefunc = function() end
    mocks.PlaySound = function() end
    mocks.GetLocale = function() return "enUS" end

    -- Class / atlas / popup helpers used by settings/Spells.lua
    mocks.GetNumClasses = function() return 0 end
    mocks.GetClassInfo = function() return nil end
    mocks.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
    mocks.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
    mocks.CreateAtlasMarkup = function() return "" end
    mocks.C_CooldownViewer = nil
    mocks.Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 0 end }) end })
    mocks.StaticPopupDialogs = {}
    mocks.StaticPopup_Show = function() end

    -- -------------------------------------------------------------------
    -- Colors
    -- -------------------------------------------------------------------
    local function makeColor(r, g, b, a)
        return {
            r = r, g = g, b = b, a = a or 1,
            GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
            GetRGB = function(self) return self.r, self.g, self.b end,
        }
    end
    mocks.CreateColor = function(r, g, b, a) return makeColor(r, g, b, a) end
    mocks.CreateColorFromHexString = function() return makeColor(1, 1, 1, 1) end
    mocks.WrapTextInColorCode = function(text) return text end
    mocks.NORMAL_FONT_COLOR = makeColor(1, 0.82, 0)
    mocks.HIGHLIGHT_FONT_COLOR = makeColor(1, 1, 1)
    mocks.RED_FONT_COLOR = makeColor(1, 0.1, 0.1)
    mocks.GREEN_FONT_COLOR = makeColor(0.1, 1, 0.1)

    -- Blizzard Settings API (canvas subcategory registration)
    mocks.Settings = setmetatable({
        RegisterCanvasLayoutCategory = function() return makeFrame() end,
        RegisterCanvasLayoutSubcategory = function() return makeFrame() end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }, { __index = function() return function() return makeFrame() end end })
    mocks.SettingsPanel = makeFrame()
    mocks.InterfaceOptionsFrame_OpenToCategory = function() end

    -- Misc string/table helpers WoW exposes globally
    mocks.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    mocks.CopyTable = deepcopy
    mocks.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    mocks.strsplit = function(sep, s) return string.match(s, "(.-)" .. sep .. "(.*)") end
    mocks.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    mocks.strjoin = function(sep, ...) return table.concat({ ... }, sep) end

    return mocks
end

return { build = build }
