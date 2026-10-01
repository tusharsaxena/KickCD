-- tests/wow_mock_frames.lua
-- The frame model of KickCD's WoW-API mock, peeled from tests/wow_mock.lua (#27).
--
-- Returns { makeFrame, FRAME_METHODS, recordHook } (recordHook is the HookScript
-- ledger build() also writes for widgets it wraps). tests/wow_mock.lua
-- loads it with `assert(loadfile(root .. "/tests/wow_mock_frames.lua"))(root)` --
-- loadfile-and-call, never require, so it resolves against the root the runner was
-- invoked through. The frame model is stateless across builds: each frame carries
-- its own state, and the shared tables below hold behavior only, so one copy
-- serves every fresh `mocks` table build() makes. Not a suite: it is not a
-- test_*.lua and is not declared in tests/run.lua's SUITES.

-- Numeric frame getters that are NOT modeled as real state. Code like
-- `border:SetFrameLevel(btn:GetFrameLevel() + 1)` does arithmetic on the
-- result, so these must return numbers rather than the frame. Values are
-- inert defaults chosen not to divide-by-zero. Everything load-bearing —
-- visibility, geometry, scale, alpha, text, color, bar values — is real
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
--   * TEXT and COLOR — the cooldown countdown, the unit label and the cast
--     bar's per-state colors are the visible output of large code paths;
--     recording them is what turns those paths into assertable behavior.
--   * STATUS BAR values — the cast bar's fill is min/max/value, so pinning
--     them is how a progress regression gets caught headlessly.
--
-- Anything NOT in this list keeps the old self-returning no-op, so unmodeled
-- chains (`:SetClampedToScreen():SetToplevel()`) stay inert.

--- Normalize SetPoint's two overloads into one record. Addon code uses both
--- the (point, x, y) and (point, relativeTo, relativePoint, x, y) forms.
local function recordPoint(point, a, b, c, d)
    if type(a) == "number" or a == nil then
        return { point = point, relativeTo = nil, relativePoint = point, x = a or 0, y = b or 0 }
    end
    return { point = point, relativeTo = a, relativePoint = b or point, x = c or 0, y = d or 0 }
end

local makeFrame   -- forward declaration (regions are frames too)

-- Shared method table: state lives on each frame, behavior is defined once.
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
-- The drop shadow. RECORDED rather than swallowed by the catch-all metatable,
-- because "font shadow" is a setting now (options-ui-§16) and the only way it
-- can be wrong is by not being CLEARED: a FontString outlives a config change,
-- so a shadow turned off that nobody clears keeps drawing. A no-op mock cannot
-- tell the two apart.
function FRAME_METHODS.SetShadowOffset(self, x, y)
    self.__shadowOffset = { x, y }
    return self
end
function FRAME_METHODS.GetShadowOffset(self)
    local o = self.__shadowOffset
    if not o then return nil end
    return o[1], o[2]
end
function FRAME_METHODS.SetShadowColor(self, r, g, b, a)
    self.__shadowColor = { r, g, b, a }
    return self
end
function FRAME_METHODS.GetShadowColor(self)
    local c = self.__shadowColor
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end
function FRAME_METHODS.SetJustifyH(self, v) self.__justifyH = v; return self end
function FRAME_METHODS.GetJustifyH(self) return self.__justifyH end

-- ── Textures / color ───────────────────────────────────────────────────────
function FRAME_METHODS.SetTexture(self, t) self.__texture = t; return self end
function FRAME_METHODS.GetTexture(self) return self.__texture end
function FRAME_METHODS.SetAtlas(self, a) self.__atlas = a; return self end
function FRAME_METHODS.GetAtlas(self) return self.__atlas end
function FRAME_METHODS.SetColorTexture(self, r, g, b, a)
    self.__colorTexture = { r, g, b, a or 1 }
    return self
end
function FRAME_METHODS.GetColorTexture(self)
    local c = self.__colorTexture
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
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
function FRAME_METHODS.GetBackdropBorderColor(self)
    local c = self.__backdropBorderColor
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
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

-- ── Enabled / saturation ────────────────────────────────────────────────────
--
-- Both are RECORDED rather than swallowed. A control the page deliberately makes
-- inert -- the tab strip on a linked Focus, which has one thing to show whichever
-- tab is picked -- is a state a case has to be able to read back, and a
-- PascalCase no-op answers "did the page disable it?" with nothing at all. The
-- mock cannot make a disabled button refuse a directly-fired script, so the flag
-- is what a case asserts (the library's own makeTab says the same thing about its
-- redundant `if active then return end` guard).
function FRAME_METHODS.SetEnabled(self, v) self.__enabled = not not v; return self end
function FRAME_METHODS.IsEnabled(self) return self.__enabled ~= false end
function FRAME_METHODS.SetDesaturated(self, v) self.__desaturated = not not v; return self end
function FRAME_METHODS.IsDesaturated(self) return self.__desaturated == true end
function FRAME_METHODS.GetRegions(self) return unpack(self.__regions or {}) end

-- ── Scripts / events ────────────────────────────────────────────────────────
function FRAME_METHODS.SetScript(self, which, fn)
    self.__scripts[which] = fn and { fn } or nil
    if which == "OnEvent" then self._onevent = fn end
    return self
end
--- A hook is RECORDED as well as run, in `self.__hooks` ({ which, fn } per
--- call). A hook cannot be removed, so one laid on a frame AceGUI pools outlives
--- the widget and follows the frame into whoever acquires it next (KICKCD-R-02);
--- the ledger is how a suite asserts that nothing did.
local function recordHook(self, which, fn)
    local hooks = rawget(self, "__hooks")
    if not hooks then hooks = {}; rawset(self, "__hooks", hooks) end
    hooks[#hooks + 1] = { which, fn }
end
function FRAME_METHODS.HookScript(self, which, fn)
    recordHook(self, which, fn)
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
--- Util.NewUnitCastFilter's suite drives its filter frame through it.
function FRAME_METHODS._fire(self, ev, ...)
    if self._onevent then self._onevent(self, ev, ...) end
end
--- The client RAISES on a name it does not know, before it records anything:
--- `Attempt to register unknown event "<NAME>"`, the kit's mock_base message byte
--- for byte. The bad set is the owning build's `__badEvents`, reached through
--- `self.__mocks` (stamped by mocks.CreateFrame) and read at CALL time, so a test
--- that swaps the table is heard. A frame with no owning build (a region, or one
--- built by hand) knows no bad names.
local function refuseUnknown(self, ev)
    local bad = self.__mocks and self.__mocks.__badEvents
    if type(bad) == "table" and bad[ev] then
        error("Attempt to register unknown event \"" .. tostring(ev) .. "\"", 3)
    end
end
function FRAME_METHODS.RegisterEvent(self, ev)
    refuseUnknown(self, ev)
    self.__events[ev] = true
    return self
end
function FRAME_METHODS.RegisterUnitEvent(self, ev, unit)
    refuseUnknown(self, ev)
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

return { makeFrame = makeFrame, FRAME_METHODS = FRAME_METHODS, recordHook = recordHook }
