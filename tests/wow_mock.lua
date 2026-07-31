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

-- Numeric frame getters that are NOT modelled as real state. Code like
-- `border:SetFrameLevel(btn:GetFrameLevel() + 1)` does arithmetic on the
-- result, so these must return numbers rather than the frame. Values are
-- inert defaults chosen not to divide-by-zero. Everything load-bearing —
-- visibility, geometry, scale, alpha, text, colour, bar values — is real
-- state on the frame instead (see FRAME_METHODS below).
local NUMERIC_GETTERS = {
    GetLeft = 0, GetRight = 0, GetTop = 0, GetBottom = 0,
    GetStringWidth = 0, GetStringHeight = 0,
    GetTextWidth = 0, GetTextHeight = 0,
    GetNumRegions = 0, GetNumChildren = 0,
}

-- Frame stub with REAL STATE for the properties the addon's correctness
-- actually depends on. A blanket no-op stub (what this used to be) makes
-- whole subsystems untestable, because "the module did the right thing" and
-- "the module did nothing" produce identical observations:
--
--   * VISIBILITY — IsShown() on a no-op stub returns the frame, i.e. is
--     permanently truthy, so every visibility mode looks alike and a grid
--     that never hides is indistinguishable from one that does. Real frames
--     start shown and Show/Hide/SetShown flip that, so the stub does too.
--   * GEOMETRY — position is persisted to SavedVariables and restored on the
--     next login; without a SetPoint/GetPoint round trip, "we saved the
--     anchor" and "we saved garbage" are the same observation. Size and
--     SCALE matter for the cast bar's auto-size math, which divides by
--     GetEffectiveScale.
--   * TEXT and COLOUR — the cooldown countdown, the unit label and the cast
--     bar's per-state colours are the visible output of large code paths;
--     recording them is what turns those paths into assertable behaviour.
--   * STATUS BAR values — the cast bar's fill is min/max/value, so pinning
--     them is how a progress regression gets caught headlessly.
--
-- Anything NOT in this list keeps the old self-returning no-op, so unmodelled
-- chains (`:SetClampedToScreen():SetToplevel()`) stay inert.

--- Normalise SetPoint's two overloads into one record. Addon code uses both
--- the (point, x, y) and (point, relativeTo, relativePoint, x, y) forms.
local function recordPoint(point, a, b, c, d)
    if type(a) == "number" or a == nil then
        return { point = point, relativeTo = nil, relativePoint = point, x = a or 0, y = b or 0 }
    end
    return { point = point, relativeTo = a, relativePoint = b or point, x = c or 0, y = d or 0 }
end

local makeFrame   -- forward declaration (regions are frames too)

-- Shared method table: state lives on each frame, behaviour is defined once.
local FRAME_METHODS = {}

-- ── Visibility ──────────────────────────────────────────────────────────────
function FRAME_METHODS.Show(self)
    local was = self.__shown
    self.__shown = true
    if not was then self:_run("OnShow") end
    return self
end
function FRAME_METHODS.Hide(self)
    local was = self.__shown
    self.__shown = false
    -- Real frames run OnHide only on a genuine shown → hidden transition.
    if was then self:_run("OnHide") end
    return self
end
function FRAME_METHODS.SetShown(self, v)
    if v then self:Show() else self:Hide() end
    return self
end
function FRAME_METHODS.IsShown(self) return self.__shown end
--- IsVisible() is IsShown() AND every ancestor shown — the distinction the
--- addon relies on when it parents a cast bar onto a hidden grid.
function FRAME_METHODS.IsVisible(self)
    local f = self
    while f do
        if not f.__shown then return false end
        f = f.__parent
    end
    return true
end

-- ── Geometry ────────────────────────────────────────────────────────────────
function FRAME_METHODS.SetPoint(self, point, a, b, c, d)
    self.__points[#self.__points + 1] = recordPoint(point, a, b, c, d)
    return self
end
function FRAME_METHODS.ClearAllPoints(self) self.__points = {}; return self end
function FRAME_METHODS.GetNumPoints(self) return #self.__points end
function FRAME_METHODS.GetPoint(self, i)
    local p = self.__points[i or 1]
    if not p then return nil end
    return p.point, p.relativeTo, p.relativePoint, p.x, p.y
end
function FRAME_METHODS.SetAllPoints(self, rel)
    self.__allPoints = rel or self.__parent or true
    return self
end
function FRAME_METHODS.SetSize(self, w, h) self.__w, self.__h = w or 0, h or 0; return self end
function FRAME_METHODS.SetWidth(self, w) self.__w = w or 0; return self end
function FRAME_METHODS.SetHeight(self, h) self.__h = h or 0; return self end
function FRAME_METHODS.GetWidth(self) return self.__w end
function FRAME_METHODS.GetHeight(self) return self.__h end
function FRAME_METHODS.GetSize(self) return self.__w, self.__h end

function FRAME_METHODS.SetScale(self, s) self.__scale = s or 1; return self end
function FRAME_METHODS.GetScale(self) return self.__scale end
--- Effective scale is the product down the parent chain, exactly as in the
--- client. The cast bar's auto-size divides by this, so a flat 1 would let a
--- master-scale regression through unnoticed.
function FRAME_METHODS.GetEffectiveScale(self)
    local s, f = 1, self
    while f do
        s = s * (f.__scale or 1)
        f = f.__parent
    end
    return s
end
function FRAME_METHODS.SetAlpha(self, a) self.__alpha = a or 1; return self end
function FRAME_METHODS.GetAlpha(self) return self.__alpha end
--- The C-side alpha setter that accepts a SECRET boolean. It is the only
--- 12.0-correct way to gate visibility on `notInterruptible`, so the stub
--- both applies the alpha AND records the raw flag: a test has to be able to
--- prove the secret was passed through rather than read in Lua.
function FRAME_METHODS.SetAlphaFromBoolean(self, flag, whenTrue, whenFalse)
    self.__alphaFromBoolean = { flag = flag, whenTrue = whenTrue, whenFalse = whenFalse }
    -- Branching on `flag` here is safe: the stub is the C side, which is
    -- exactly the layer allowed to look at a secret.
    if flag then self.__alpha = whenTrue else self.__alpha = whenFalse end
    return self
end
function FRAME_METHODS.SetFrameLevel(self, l) self.__level = l or 0; return self end
function FRAME_METHODS.GetFrameLevel(self) return self.__level end
function FRAME_METHODS.SetFrameStrata(self, s) self.__strata = s; return self end
function FRAME_METHODS.GetFrameStrata(self) return self.__strata end
function FRAME_METHODS.GetObjectType(self) return self.__objectType end
--- A real STRING, not the frame. Kit fidelity rule 2: getters used in
--- concatenation must return real strings — the always-shown-scrollbar patch
--- builds a global name out of this one, and a table there raises inside the
--- library on the first panel render.
function FRAME_METHODS.GetName(self) return self.__name end
function FRAME_METHODS.SetName(self, n) self.__name = n; return self end

-- ── Parenting ───────────────────────────────────────────────────────────────
function FRAME_METHODS.SetParent(self, p) self.__parent = p; self._parent = p; return self end
function FRAME_METHODS.GetParent(self) return self.__parent end

-- ── Text ────────────────────────────────────────────────────────────────────
function FRAME_METHODS.SetText(self, t) self.__text = t; return self end
function FRAME_METHODS.GetText(self) return self.__text end
function FRAME_METHODS.SetFormattedText(self, fmt, ...)
    self.__text = fmt and string.format(fmt, ...) or nil
    return self
end
function FRAME_METHODS.SetTextColor(self, r, g, b, a)
    self.__textColor = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.GetTextColor(self)
    local c = self.__textColor
    if not c then return 1, 1, 1, 1 end
    return c[1], c[2], c[3], c[4]
end
function FRAME_METHODS.SetFont(self, path, size, flags)
    self.__font = { path = path, size = size, flags = flags }
    return self
end
function FRAME_METHODS.GetFont(self)
    local f = self.__font
    if not f then return nil end
    return f.path, f.size, f.flags
end
function FRAME_METHODS.SetJustifyH(self, v) self.__justifyH = v; return self end
function FRAME_METHODS.GetJustifyH(self) return self.__justifyH end

-- ── Textures / colour ───────────────────────────────────────────────────────
function FRAME_METHODS.SetTexture(self, t) self.__texture = t; return self end
function FRAME_METHODS.GetTexture(self) return self.__texture end
function FRAME_METHODS.SetAtlas(self, a) self.__atlas = a; return self end
function FRAME_METHODS.GetAtlas(self) return self.__atlas end
function FRAME_METHODS.SetColorTexture(self, r, g, b, a)
    self.__colorTexture = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.SetVertexColor(self, r, g, b, a)
    self.__vertexColor = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.GetVertexColor(self)
    local c = self.__vertexColor
    if not c then return 1, 1, 1, 1 end
    return c[1], c[2], c[3], c[4]
end
function FRAME_METHODS.SetBackdropColor(self, r, g, b, a)
    self.__backdropColor = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.SetBackdropBorderColor(self, r, g, b, a)
    self.__backdropBorderColor = { r, g, b, a or 1 }
    return self
end

-- ── Status bar ──────────────────────────────────────────────────────────────
function FRAME_METHODS.SetMinMaxValues(self, mn, mx) self.__min, self.__max = mn, mx; return self end
function FRAME_METHODS.GetMinMaxValues(self) return self.__min, self.__max end
function FRAME_METHODS.SetValue(self, v) self.__value = v; return self end
function FRAME_METHODS.GetValue(self) return self.__value end
function FRAME_METHODS.SetStatusBarColor(self, r, g, b, a)
    self.__barColor = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.GetStatusBarColor(self)
    local c = self.__barColor
    if not c then return 1, 1, 1, 1 end
    return c[1], c[2], c[3], c[4]
end
function FRAME_METHODS.SetStatusBarTexture(self, t)
    self.__barTexture = t
    -- The live API accepts a path OR a texture object and GetStatusBarTexture
    -- always hands back an object, so keep a region either way.
    if type(t) == "table" then
        self.__barTextureObj = t
    else
        self.__barTextureObj = self.__barTextureObj or makeFrame("Texture", self)
        self.__barTextureObj.__texture = t
    end
    return self
end
function FRAME_METHODS.GetStatusBarTexture(self)
    self.__barTextureObj = self.__barTextureObj or makeFrame("Texture", self)
    return self.__barTextureObj
end

-- ── Child regions ───────────────────────────────────────────────────────────
--- Real CreateTexture/CreateFontString return NEW objects; the old stub
--- returned the parent itself, which silently aliased every region onto one
--- table and made "which widget got the text" unanswerable. Creation order
--- and the requested template are recorded so a suite can assert them.
local function createRegion(self, objectType, template)
    local r = makeFrame(objectType, self)
    r.__template = template
    self.__regions[#self.__regions + 1] = r
    return r
end
function FRAME_METHODS.CreateTexture(self, _name, _layer, template)
    return createRegion(self, "Texture", template)
end
function FRAME_METHODS.CreateFontString(self, _name, _layer, template)
    return createRegion(self, "FontString", template)
end
function FRAME_METHODS.CreateLine(self) return createRegion(self, "Line", nil) end
function FRAME_METHODS.CreateMaskTexture(self) return createRegion(self, "MaskTexture", nil) end

-- ── Scripts / events ────────────────────────────────────────────────────────
function FRAME_METHODS.SetScript(self, which, fn)
    self.__scripts[which] = fn and { fn } or nil
    if which == "OnEvent" then self._onevent = fn end
    return self
end
function FRAME_METHODS.HookScript(self, which, fn)
    local list = self.__scripts[which]
    if not list then list = {}; self.__scripts[which] = list end
    list[#list + 1] = fn
    return self
end
function FRAME_METHODS.GetScript(self, which)
    local list = self.__scripts[which]
    return list and list[1]
end
--- Run every handler bound to a script, in registration order. Test-scoped.
function FRAME_METHODS._run(self, which, ...)
    local list = self.__scripts[which]
    if not list then return end
    for _, fn in ipairs(list) do fn(self, ...) end
end
--- Fire the OnEvent handler. Kept as the historical name because
--- Util.RegisterUnitCastEvent's suite drives its dispatch frame through it.
function FRAME_METHODS._fire(self, ev, ...)
    if self._onevent then self._onevent(self, ev, ...) end
end
function FRAME_METHODS.RegisterEvent(self, ev)
    self.__events[ev] = true
    return self
end
function FRAME_METHODS.RegisterUnitEvent(self, ev, unit)
    self._unitEvents = self._unitEvents or {}
    self._unitEvents[ev] = unit
    self.__events[ev] = unit or true
    return self
end
function FRAME_METHODS.UnregisterEvent(self, ev) self.__events[ev] = nil; return self end
function FRAME_METHODS.UnregisterAllEvents(self) self.__events = {}; return self end
function FRAME_METHODS.IsEventRegistered(self, ev) return self.__events[ev] ~= nil end

--- Build a frame stub. `objectType` mirrors CreateFrame's first argument
--- (or "Texture"/"FontString" for regions); `parent` wires the chain that
--- IsVisible and GetEffectiveScale walk.
local frameSeq = 0
function makeFrame(objectType, parent, name)
    frameSeq = frameSeq + 1
    local f = {
        __objectType = objectType or "Frame",
        -- Always a STRING. An anonymous frame gets a synthetic unique name
        -- rather than nil, because the scrollbar patch concatenates GetName()
        -- and a nil there is the same crash as a table.
        __name       = name or ("KickCDMockFrame" .. frameSeq),
        __parent     = parent,
        _parent      = parent,   -- historical alias asserted by existing suites
        __shown      = true,     -- CreateFrame'd frames start shown
        __points     = {},
        __regions    = {},
        __scripts    = {},
        __events     = {},
        __w = 0, __h = 0, __scale = 1, __alpha = 1, __level = 0,
    }
    return setmetatable(f, {
        __index = function(_, k)
            local m = FRAME_METHODS[k]
            if m ~= nil then return m end
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
    --- Merge `src` into `dst` IN PLACE, leaving every key `dst` already has
    --- alone. This is AceDB's real `copyDefaults` behaviour and the awkward half
    --- of it is what matters: a saved value always wins over the default, and
    --- the saved table is mutated rather than replaced. A mock that returned a
    --- fresh copy of the defaults instead would make every migration untestable
    --- — the code under test would never see the saved shape it exists to
    --- convert.
    local function copyDefaults(dst, src)
        if type(src) ~= "table" then return dst end
        if type(dst) ~= "table" then dst = {} end
        for k, v in pairs(src) do
            if type(v) == "table" then
                dst[k] = copyDefaults(dst[k], v)
            elseif dst[k] == nil then
                dst[k] = v
            end
        end
        return dst
    end

    local AceDB = {
        --- Reads the named SavedVariables global when the sandbox has one, so a
        --- suite can stage a pre-migration account exactly as the client would
        --- hand it over, then merges defaults into it in place.
        New = function(_, name, defaults, _defaultProfile)
            local saved = name and mocks[name] or nil
            if type(saved) ~= "table" then saved = nil end
            local db = {
                keys = { profile = "Default" },
                profile = copyDefaults(saved and saved.profile or {},
                                       defaults and defaults.profile or {}),
                global  = copyDefaults(saved and saved.global or {},
                                       defaults and defaults.global or {}),
                char    = copyDefaults(saved and saved.char or {},
                                       defaults and defaults.char or {}),
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

    -- AceGUI-3.0. The previous stub handed back a bare frame, so SetCallback was
    -- a no-op and NOT ONE widget callback in the addon was reachable — the whole
    -- schema -> widget -> write path was untestable, which is exactly why the
    -- adoption prompt gates the Options milestone on this.
    --
    -- Widgets are inert data recorders rather than frames: they remember what
    -- was set on them and expose __fire so a test can drive OnValueChanged /
    -- OnMouseUp / OnValueConfirmed the way a real click would.
    --
    -- Deliberately a VERBATIM port of tests/_kit/mock_base.lua's builder, so
    -- adopting the shared kit deletes this block rather than reconciling two
    -- divergent widget fakes.
    local function makeWidget(wtype)
        local w = {
            type      = wtype,
            children  = {},
            callbacks = {},
            frame     = makeFrame(),
        }
        function w:SetLabel(v) self.labelText = v; return self end
        function w:SetText(v) self.text = v; return self end
        function w:SetValue(v) self.value = v; return self end
        function w:GetValue() return self.value end
        function w:SetList(items, order) self.list, self.order = items, order; return self end
        function w:SetColor(r, g, b, a) self.color = { r = r, g = g, b = b, a = a }; return self end
        function w:SetHasAlpha(v) self.hasAlpha = v; return self end
        function w:SetDisabled(v) self.disabled = v and true or false; return self end
        function w:SetSliderValues(mn, mx, st) self.min, self.max, self.step = mn, mx, st; return self end
        function w:SetIsPercent(v) self.isPercent = v; return self end
        function w:SetWidth(v) self.width = v; return self end
        function w:SetHeight(v) self.height = v; return self end
        function w:SetRelativeWidth(v) self.relativeWidth = v; return self end
        function w:SetFullWidth(v) self.fullWidth = v and true or false; return self end
        function w:SetLayout(v) self.layout = v; return self end
        function w:SetAutoAdjustHeight(v) self.autoAdjustHeight = v; return self end
        function w:SetImage(...) self.image = { ... }; return self end
        function w:SetImageSize(...) self.imageSize = { ... }; return self end
        function w:SetMaxLetters(v) self.maxLetters = v; return self end
        function w:SetCallback(name, fn) self.callbacks[name] = fn; return self end
        function w:AddChild(child) self.children[#self.children + 1] = child; return self end
        function w:ReleaseChildren() self.children = {}; return self end
        function w:DoLayout() self.layoutCount = (self.layoutCount or 0) + 1; return self end
        -- AceGUI invokes a callback as fn(widget, eventName, ...); mirrored
        -- exactly, because the makers destructure it as function(_, _, value).
        function w:__fire(name, ...)
            local fn = self.callbacks[name]
            if fn then return fn(self, name, ...) end
        end

        if wtype == "ScrollFrame" then
            -- The always-shown-scrollbar patch reaches into these three by name
            -- and does real arithmetic with them.
            w.scrollbar   = makeFrame()
            w.scrollframe = makeFrame()
            w.content     = makeFrame()
            w.content.original_width = 400
            w.localstatus = { offset = 0 }
            function w:FixScroll() self.fixScrollCount = (self.fixScrollCount or 0) + 1 end
            function w:MoveScroll(v) self.movedTo = v end
            function w:SetScroll(v) self.scrolledTo = v end
        end
        return w
    end

    local function makeAceGUI()
        local g = {
            -- Empty by default, which models AceGUI-3.0-SharedMediaWidgets being
            -- absent: a dropdown maker asks GetWidgetVersion about LSM30_* and
            -- falls back to a plain Dropdown when it comes back nil.
            WidgetRegistry   = {},
            __widgetVersions = {},
            -- Every widget handed out, in creation order. The only way a test can
            -- reach a widget on a page whose ctx the toolkit keeps private.
            __created        = {},
        }
        function g:Create(wtype)
            local ctor = self.WidgetRegistry[wtype]
            local w = ctor and ctor() or makeWidget(wtype)
            self.__created[#self.__created + 1] = w
            return w
        end
        function g:GetWidgetVersion(wtype) return self.__widgetVersions[wtype] end
        function g:RegisterWidgetType(wtype, ctor, version)
            self.WidgetRegistry[wtype]   = ctor
            self.__widgetVersions[wtype] = version
        end
        return g
    end

    local libs = {
        ["AceAddon-3.0"]        = AceAddon,
        ["AceDB-3.0"]           = AceDB,
        ["AceEvent-3.0"]        = { Embed = function(_, t) return embedAceEvent(t) end },
        ["AceTimer-3.0"]        = { Embed = function(_, t) return embedAceTimer(t) end },
        ["AceConsole-3.0"]      = { Embed = function(_, t) return embedAceConsole(t) end },
        ["AceGUI-3.0"]          = makeAceGUI(),
        ["AceConfig-3.0"]         = noopLib(),
        ["AceConfigDialog-3.0"]   = noopLib(),
        ["AceConfigRegistry-3.0"] = noopLib(),
        ["AceDBOptions-3.0"]      = noopLib(),
        ["LibSharedMedia-3.0"]    = LSM,
        ["LibCustomGlow-1.0"]     = noopLib(),
        ["CallbackHandler-1.0"]   = noopLib(),
    }

    -- Registered minors, for NewLibrary below. Ace fakes above are handed to us
    -- pre-built and carry no minor, so they simply never participate.
    local minors = {}

    --- The real LibStub:NewLibrary contract, reproduced because the vendored
    --- LibKa0s files are loaded as REAL SOURCE by tests/loader.lua rather than
    --- faked (testing-§9: a suite that measures the degradation stub instead of
    --- the library is green and tests nothing).
    ---
    --- Minor comparison is the whole mechanism: LibStub keeps the highest minor
    --- it is offered and discards the rest, so a file re-registering at an equal
    --- or lower minor must get nil back and `return` — which is exactly what the
    --- paired-minor guards in OptionsWidgets/OptionsScroll/PerfPanel rely on.
    local function newLibrary(_, major, minor)
        minor = tonumber(minor)
        if not minor then error("mock LibStub: NewLibrary needs a numeric minor", 2) end
        local old = minors[major]
        if old and old >= minor then return nil end
        minors[major] = minor
        libs[major] = libs[major] or {}
        return libs[major], old
    end

    mocks.LibStub = setmetatable({}, {
        __call = function(_, name, silent)
            local lib = libs[name]
            if not lib and not silent then error("mock LibStub: missing lib " .. tostring(name)) end
            return lib
        end,
        __index = {
            GetLibrary = function(_, name, silent)
                local lib = libs[name]
                if not lib and not silent then
                    error("mock LibStub: missing lib " .. tostring(name))
                end
                return lib
            end,
            NewLibrary = newLibrary,
            minors = minors,
        },
    })
    mocks.__aceGUI = libs["AceGUI-3.0"]
    mocks.__libs = libs
    mocks.__libMinors = minors

    -- -------------------------------------------------------------------
    -- Frames / UI
    -- -------------------------------------------------------------------
    -- CreateFrame(frameType, name, parent, template): the parent is wired so
    -- IsVisible / GetEffectiveScale can walk the real chain. Frames created
    -- without an explicit parent fall back to UIParent, as in the client.
    local UIParent = makeFrame("Frame", nil)
    mocks.UIParent = UIParent
    -- Every CreateFrame'd frame is also recorded, in creation order. Some
    -- bootstrap frames are file-locals with no published handle at all (the
    -- PLAYER_REGEN_* listener in core/State.lua is the case that forced this),
    -- so the registry plus __findFrame is how a suite reaches one to fire its
    -- OnEvent — without having to widen the addon's public surface just for
    -- the tests.
    local created = {}
    mocks.__frames = created
    mocks.CreateFrame = function(frameType, name, parent, template)
        -- The NAME is honoured rather than discarded: the library derives frame
        -- globals from a descriptor and the scrollbar patch builds a name from
        -- GetName(), so a test that cannot see the name cannot assert either.
        local f = makeFrame(frameType or "Frame", parent ~= nil and parent or UIParent, name)
        f.__template = template
        created[#created + 1] = f
        return f
    end
    --- How many created frames are CURRENTLY registered for `event`.
    --- Recorded rather than no-opped because a test needs to observe it: the
    --- per-unit UNIT_SPELLCAST_* dispatch frames are the thing a perf suspend
    --- has to release, and "did they come back?" is only answerable by counting.
    mocks.__countFramesFor = function(event)
        local n = 0
        for _, f in ipairs(created) do
            if f.__events[event] then n = n + 1 end
        end
        return n
    end

    --- First created frame registered for `event`, or nil.
    mocks.__findFrame = function(event)
        for _, f in ipairs(created) do
            if f.__events[event] then return f end
        end
    end
    mocks.UISpecialFrames = {}
    -- WoW aliases the table.insert/remove/wipe globals; the addon uses `tinsert`
    -- (e.g. registering windows into UISpecialFrames), so the debug console can
    -- only build headlessly if the sandbox provides it.
    mocks.tinsert = table.insert
    mocks.tremove = table.remove
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

    -- WoW's millisecond profile clock, used by every Perf bracket
    -- (performance-§2). MONOTONICALLY INCREASING rather than fixed: a constant
    -- would make every measured span exactly 0, and a bucket asserting it
    -- recorded a positive duration could then never fail. The step is small and
    -- deterministic so a test can reason about it if it ever needs to.
    local profileClock = 0
    mocks.debugprofilestop = function()
        profileClock = profileClock + 0.01
        return profileClock
    end

    -- WoW exposes `date` as a GLOBAL (it is in .luacheckrc's read_globals), and
    -- stock Lua does not — it only has os.date. modules/DebugLog.lua papered
    -- over the gap with its own `_G.date or os.date` fallback; the library
    -- rightly just calls date(), so the mock has to model the client instead.
    -- Fixed rather than live so a timestamp can be asserted on if a case ever
    -- needs to.
    mocks.date = function(fmt) return os.date(fmt or "%H:%M:%S", 0) end
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
    -- ---------------------------------------------------------------------
    -- Specialization API
    -- ---------------------------------------------------------------------
    --
    -- The simulated client is a table so a suite can reshape it via the
    -- loadInstance `mutate` hook BEFORE sources load — mocks.__setPlayerSpec
    -- swaps class/spec/locale wholesale. Default is an enUS Beast Mastery
    -- Hunter, matching the historical mock.
    --
    -- specName is deliberately the LOCALISED display name (as Blizzard
    -- returns it) while specID is locale-invariant: that asymmetry is the
    -- whole point of the frFR regression coverage (issue #8).
    local classSpecs = {
        -- [classID] = { classFile, { {specID, localisedName}, ... } }
        [3]  = { "HUNTER",  { { 253, "Beast Mastery" }, { 254, "Marksmanship" }, { 255, "Survival" } } },
        [7]  = { "SHAMAN",  { { 262, "Elemental" }, { 263, "Enhancement" }, { 264, "Restoration" } } },
        [9]  = { "WARLOCK", { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } } },
    }
    local player = { classID = 3, specIndex = 1 }

    --- Reshape the simulated client. Call from a loadInstance mutate hook.
    -- @param classID number        key into classSpecs above
    -- @param specIndex number      1-based index within that class's spec list
    -- @param localisedNames table|nil  optional { [specID] = "localised name" }
    --        overrides, simulating a non-English client.
    function mocks.__setPlayerSpec(classID, specIndex, localisedNames)
        player.classID, player.specIndex = classID, specIndex
        if localisedNames then
            for _, entry in pairs(classSpecs) do
                for _, spec in ipairs(entry[2]) do
                    if localisedNames[spec[1]] then spec[2] = localisedNames[spec[1]] end
                end
            end
        end
    end

    local function specInfoFor(classID, index)
        local entry = classSpecs[classID]
        local spec = entry and entry[2][index]
        if not spec then return nil end
        return spec[1], spec[2], nil, 12345, "DAMAGER"
    end

    mocks.C_SpecializationInfo = {
        GetSpecialization = function() return player.specIndex end,
        GetSpecializationInfo = function(index)
            return specInfoFor(player.classID, index or player.specIndex)
        end,
    }
    mocks.GetSpecialization = function() return player.specIndex end
    mocks.GetSpecializationInfo = function(index)
        return specInfoFor(player.classID, index or player.specIndex)
    end
    mocks.GetNumSpecializationsForClassID = function(classID)
        local entry = classSpecs[classID]
        return entry and #entry[2] or 0
    end
    mocks.GetSpecializationInfoForClassID = function(classID, index)
        return specInfoFor(classID, index)
    end
    mocks.GetSpellInfo = function(id) return "Spell" .. tostring(id), nil, 12345 end
    mocks.UnitCastingInfo = function() return nil end
    mocks.UnitChannelInfo = function() return nil end
    mocks.UnitExists = function() return false end
    mocks.UnitCanAttack = function() return true end
    -- Three returns like the live API: localised name, file token, classID.
    mocks.UnitClass = function() return "Hunter", "HUNTER", 3 end
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

    -- Class / atlas / popup helpers used by settings/Spells.lua.
    -- GetNumClasses spans the real 1..13 range so callers that iterate it see
    -- the same sparse shape as the live client (classSpecs above only fills
    -- the three classes the suites exercise; the rest return nil, which is
    -- exactly what a class the caller doesn't care about looks like).
    local CLASS_FILES = { [3] = "HUNTER", [7] = "SHAMAN", [9] = "WARLOCK" }
    mocks.GetNumClasses = function() return 13 end
    mocks.GetClassInfo = function(classID)
        local file = CLASS_FILES[classID]
        if not file then return nil end
        return file:sub(1, 1) .. file:sub(2):lower(), file, classID
    end
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

    -- -------------------------------------------------------------------
    -- Curves (12.0 C_CurveUtil)
    -- -------------------------------------------------------------------
    --
    -- Without these, IconGrid_Render's BuildCurves bails and alphaCurve stays
    -- nil, so Icon:Apply's branch 1 (the full-cooldown render — the main path)
    -- is unreachable and silently untested. Curves are tagged with their kind
    -- so a mock DurationObject can return a number or a color to match, the
    -- way the real EvaluateRemainingDuration does.
    local function makeCurve(kind)
        local c = { __kind = kind, points = {} }
        function c.SetType() return c end
        function c.AddPoint(self, at, value)
            self.points[#self.points + 1] = { at = at, value = value }
            return self
        end
        return c
    end

    --- Evaluate a mock curve at `at`, the way the C side does: return the value
    --- of the last control point at or below `at`, falling back to the first
    --- point below the curve's start.
    ---
    --- This HAS to read the control points. The addon's curves are step-shaped
    --- and every one of them is built from config — so a stub that ignores the
    --- points and returns a constant makes "this icon used ITS unit's curve"
    --- and "this icon used some other unit's curve" the same observation. That
    --- blind spot is exactly what let a per-unit curve regression ship green.
    local function evaluateCurve(curve, at)
        local pts = curve and curve.points
        if not (pts and pts[1]) then return nil end
        local chosen = pts[1]
        for _, p in ipairs(pts) do
            if p.at <= at then chosen = p else break end
        end
        return chosen.value
    end
    mocks.C_CurveUtil = {
        CreateCurve      = function() return makeCurve("number") end,
        CreateColorCurve = function() return makeCurve("color") end,
        -- The C-side boolean selector: returns `whenTrue` or `whenFalse`
        -- depending on the flag, and accepts a SECRET flag. Castbar:ApplyState
        -- routes every per-state alpha and the name colour through it rather
        -- than branching in Lua, so without this the whole cast-render path is
        -- unreachable headlessly. Written as an explicit if — the `and/or`
        -- idiom would collapse a legitimate `whenTrue` of 0 to `whenFalse`,
        -- and 0 is exactly what the module passes to hide a bar.
        EvaluateColorValueFromBoolean = function(flag, whenTrue, whenFalse)
            if flag then return whenTrue end
            return whenFalse
        end,
    }

    --- Build a stand-in DurationObject. Mirrors the live API's two defining
    --- traits: a FRESH object per call, and getters that may be secret.
    -- @param remaining number  value EvaluateRemainingDuration resolves to
    function mocks.__makeDurationObject(remaining)
        local o = {}
        function o.EvaluateRemainingDuration(_, curve)
            -- Read the curve's actual control points so the caller's CHOICE of
            -- curve is observable. Falls back to the raw remaining (number) or
            -- a stand-in colour only when a curve carries no points at all.
            local v = evaluateCurve(curve, remaining or 0.4)
            if v ~= nil then return v end
            if curve and curve.__kind == "color" then return makeColor(1, 0.4, 0.4) end
            return remaining or 0.4
        end
        function o.GetRemainingDuration() return remaining or 0.4 end
        function o.HasSecretValues() return false end
        return o
    end
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
