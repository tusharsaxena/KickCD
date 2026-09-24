-- tests/wow_mock.lua
-- KickCD's half of the WoW-API mock, layered over the shared base in tests/_kit (testing-§1).
--
-- Returns a builder: each call to build() produces a FRESH `mocks` table (the
-- fake WoW global namespace), so every test instance is fully isolated.
--
-- ── WHAT THE KIT PROVIDES, AND WHAT THIS FILE LAYERS ON TOP ────────────────
--
-- build() starts from tests/_kit/mock_base.lua's builder and then overwrites,
-- per key, what is genuinely KickCD's. Plain per-key overwrite, per the kit's
-- README: the base hands back a fresh table on every call.
--
-- LibStub and the Ace layer are the KIT'S (#21), so every kit revision to them
-- reaches this suite. That covers the strict LibStub, whose NewLibrary registers
-- the vendored LibKa0s files for real. It covers AceAddon, with NewAddon
-- honoring its mixin list, NewModule / GetModule and the lifecycle. It covers
-- AceEvent's two CallbackHandler registries, which carry the architecture-§4
-- requirement: callbacks keyed by (message, target), SendMessage fanned out to
-- every target, string methods, and the recorded, validated event half with
-- mocks.__fireEvent. And it covers AceConsole (Print, Printf), AceTimer, and
-- AceGUI with Release. mocks.__msgRegistry is the message registry.
--
-- What stays here is KickCD's own: its non-Ace library fakes (LibSharedMedia,
-- LibCustomGlow, the AceConfig trio, AceDBOptions, CallbackHandler) and its
-- AceDB, registered into mocks.__libs; the SetHighlight recorder, wrapped onto
-- AceGUI:Create; __enableAll, one line over AceAddon:EnableAddon; the frame
-- model below; and a C_Timer queue of plain functions drained by __flushTimers.
-- Production embeds no AceTimer, so the kit's __fireTimers and its table-shaped
-- entries are never used here.
--
-- MEASURED, not assumed: of the base's 60 keys, this file reassigns 27 and
-- inherits 33, LibStub, __libs, __msgRegistry, __fireEvent and __badEvents
-- among them.
--
-- The overrides are NOT the base being wrong. The base's own header states the
-- policy — single-consumer fidelity lives in the consumer's extender — and
-- names this addon's frame model as a deliberate divergence it is not going to
-- adopt unilaterally: CreateTexture / CreateFontString here return DISTINCT
-- objects rather than the frame itself, because a font string and its parent
-- are not one object and several suites assert on the difference. The rest of
-- the overrides are the same story at a smaller scale: real state for
-- visibility, geometry, scale, text, color and status-bar values (see the
-- FRAME_METHODS note below), and the spec/cooldown/cast APIs this addon is
-- built on.

-- The repo root, forwarded by tests/run.lua's `loadfile(...)(root)` so the kit
-- resolves the same way every other vendored path in the harness does, rather
-- than assuming the process was started from the repo root.
local root = ... or "."
local kitMockBase = dofile(root .. "/tests/_kit/mock_base.lua")

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = deepcopy(vv) end
    return out
end

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

--- The three AceDB sections the mock materializes, in the order the real lib
--- would. Module-level so the fake New() allocates nothing extra per call.
local DB_SECTIONS = { "profile", "global", "char" }

--- Pull one section out of a staged-SavedVariables or defaults table. Returns a
--- FRESH `{}` when the table or the section is absent — never a shared table,
--- or two sections would silently alias each other.
local function dbSection(t, key)
    return t and t[key] or {}
end

--- The profile-management surface the addon calls on its db that the fake
--- does not model: harmless no-ops. Module-level table, copied onto each db.
--- SetProfile, GetCurrentProfile, GetProfiles and ResetProfile are real, and
--- New() builds them per db below.
local DB_STUBS = {
    RegisterCallback  = function() end,
    ResetProfile      = function() end,
    CopyProfile       = function() end,
    DeleteProfile     = function() end,
}

--- The staged SavedVariables' stored profiles, by name, as the raw tables the
--- client would hand over (identity kept, so a merge mutates the staged
--- table exactly as AceDB mutates the real one). A staged `profile` section is
--- the older shorthand for `profiles.Default`, kept so a suite can stage one
--- profile without spelling the whole SV shape.
local function stagedProfiles(saved)
    local out = {}
    if type(saved) ~= "table" then return out end
    if type(saved.profiles) == "table" then
        for name, p in pairs(saved.profiles) do out[name] = p end
    end
    if out.Default == nil and type(saved.profile) == "table" then
        out.Default = saved.profile
    end
    return out
end

local function build()
    local mocks = kitMockBase()

    -- ── Timers: the KIT's queue, not a second one ──────────────────────────
    --
    -- This file used to replace C_Timer wholesale with a plain array of
    -- callbacks and drain it from __flushTimers. Kit revision 22 made the queue
    -- CALLABLE -- `mocks.__timers()` answers the LIVE set: every un-canceled
    -- timer and ticker and every frame still carrying an OnUpdate -- and that
    -- is the surface tests/test_disabled.lua asks "is anything still going to
    -- wake up?" through (slash-commands-§7 step 4). A local array here would
    -- answer that question over a table the addon's own timers never reach, and
    -- a stand-down suite that measures the wrong queue passes over a live one.
    --
    -- So After and NewTimer are the kit's now, cancellation and all, and
    -- __flushTimers is the kit's __fireTimers under the name every existing
    -- suite already calls.
    mocks.__flushTimers = mocks.__fireTimers

    -- NewTicker is KickCD's to add: the kit models one-shots and AceTimer, and
    -- this addon's cooldown-text countdown is a REPEATING C_Timer ticker
    -- (modules/IconGrid_Render.lua). Modeled as a queue entry that re-arms
    -- itself after each fire and carries the handle, so the live set reports it
    -- for as long as it is armed and stops the moment it is canceled. Until
    -- now this returned a bare frame stub: a ticker that never fired, never
    -- appeared in any queue, and could not be told apart from a canceled one --
    -- which is exactly the survivor the stand-down rule is about.
    local function newTicker(delay, fn)
        local handle = {}
        -- `cancelled` with two Ls is the KIT's field name, not this file's
        -- prose: tests/_kit/mock_record.lua's live-set survey reads
        -- `t.timer.cancelled`, and AceTimer-3.0 spells it that way too. A US
        -- spelling here would be a handle the survey cannot see as cancelled.
        handle.Cancel      = function() handle.cancelled = true end
        handle.IsCancelled = function() return handle.cancelled == true end
        local function arm()
            mocks.__timers[#mocks.__timers + 1] = {
                delay = delay,
                timer = handle,
                fn    = function()
                    if handle.cancelled then return end
                    fn(handle)
                    arm()
                end,
            }
        end
        arm()
        return handle
    end
    mocks.C_Timer.NewTicker = newTicker

    -- ── The registration set, in ONE place ─────────────────────────────────
    --
    -- The kit's `__registrations()` surveys the AceEvent halves -- events,
    -- messages, buckets -- and the frames the KIT built. This addon's frames are
    -- this file's own model (see the header: CreateTexture returns a distinct
    -- object, which the kit deliberately does not adopt), so the kit's survey
    -- cannot see the kind that matters most here: the per-unit UNIT_SPELLCAST_*
    -- cast-filter frames.
    --
    -- This is the union, in the kit's own row shape, so a suite asks ONE
    -- question. It removes on unregister in both halves -- the kit's registry
    -- does, and UnregisterEvent / UnregisterAllEvents above clear `__events` --
    -- which is the half that makes "the registration set is empty" falsifiable.
    mocks.__registrationSet = function()
        local out = {}
        for _, reg in ipairs(mocks.__registrations()) do out[#out + 1] = reg end
        for _, f in ipairs(mocks.__frames or {}) do
            for event, unit in pairs(f.__events or {}) do
                out[#out + 1] = {
                    target = f,
                    kind   = unit == true and "frame" or "unit",
                    event  = event,
                    unit   = unit ~= true and unit or nil,
                }
            end
        end
        table.sort(out, function(a, b)
            local ka, kb = tostring(a.kind), tostring(b.kind)
            if ka ~= kb then return ka < kb end
            if a.event ~= b.event then return tostring(a.event) < tostring(b.event) end
            return tostring(a.unit) < tostring(b.unit)
        end)
        return out
    end

    -- -------------------------------------------------------------------
    -- Fake AceDB: static default merge is enough for headless assertions
    -- -------------------------------------------------------------------
    --- Merge `src` into `dst` IN PLACE, leaving every key `dst` already has
    --- alone. This is AceDB's real `copyDefaults` behavior and the awkward half
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
            local db = { keys = { profile = "Default" } }
            -- Argument order is the contract: the STAGED saved section is `dst`
            -- and the declared defaults are `src`, so defaults only fill keys
            -- the account is missing. Flip it and migration tests would be
            -- migrating a defaults-shaped table and passing for the wrong reason.
            for _, key in ipairs(DB_SECTIONS) do
                if key ~= "profile" then
                    db[key] = copyDefaults(dbSection(saved, key), dbSection(defaults, key))
                end
            end
            for stub, fn in pairs(DB_STUBS) do db[stub] = fn end

            -- ── Stored profiles, and a real SetProfile ──────────────────────
            --
            -- Every stored profile, seeded from the staged SV `profiles` table.
            -- Each is defaults-merged IN PLACE the first time it is accessed and
            -- keeps its identity per name after that, which is AceDB-3.0's own
            -- lazy profile materialization. A profile migration that walks only
            -- `db.profile` is invisible to a suite that never switches, and a
            -- SetProfile no-op made the switch impossible to test (KICKCD-R-01).
            db.__profiles = stagedProfiles(saved)
            local merged = {}
            local function profileFor(key)
                if not merged[key] then
                    db.__profiles[key] = copyDefaults(db.__profiles[key] or {},
                        dbSection(defaults, "profile"))
                    merged[key] = true
                end
                return db.__profiles[key]
            end
            db.profile = profileFor("Default")
            db.GetCurrentProfile = function() return db.keys.profile end
            db.GetProfiles = function(_, t)
                t = t or {}
                for i = #t, 1, -1 do t[i] = nil end
                for key in pairs(db.__profiles) do t[#t + 1] = key end
                table.sort(t)
                return t, #t
            end

            -- ── ResetProfile, for real ──────────────────────────────────────
            --
            -- It was one of the no-op DB_STUBS, and that stopped being harmless
            -- the moment the global reset became a PROFILE reset (options-ui-§12,
            -- settings/OptionsSetup.lua). A no-op here does not fail a case, it
            -- passes one: the suite measures a reset that never ran.
            --
            -- Two fidelities matter and both are the real library's:
            --
            --   * the profile table keeps its IDENTITY across a reset. It is
            --     wiped in place, so `NS.db.profile` — captured at load by
            --     several modules — keeps pointing at the live table. Replacing
            --     the table instead would leave every holder on a stale one, and
            --     that bug is invisible to a suite that re-reads `db.profile`.
            --   * the callbacks fire, in CallbackHandler's BOTH registration
            --     forms. core/Database.lua registers all three profile events as
            --     `db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")`
            --     — the string-METHOD form, dispatched as `obj:method(event, ...)`.
            --     A fake that stores the handler and calls it raises on a string,
            --     which is why the registration stub swallowed everything.
            local callbacks = {}
            db.RegisterCallback = function(target, event, handler)
                callbacks[event] = callbacks[event] or {}
                callbacks[event][#callbacks[event] + 1] = { target = target, handler = handler }
            end

            -- Hands a handler exactly what the caller passes after the event,
            -- nothing substituted, so each event carries AceDB-3.0's own shape.
            local function fire(event, ...)
                for _, entry in ipairs(callbacks[event] or {}) do
                    local target, handler = entry.target, entry.handler
                    if type(handler) == "function" then
                        handler(event, db, ...)
                    elseif type(handler) == "string" and type(target) == "table"
                        and type(target[handler]) == "function"
                    then
                        target[handler](target, event, db, ...)
                    end
                end
            end

            db.ResetProfile = function()
                local profile = db.profile
                for k in pairs(profile) do profile[k] = nil end
                copyDefaults(profile, dbSection(defaults, "profile"))
                -- AceDB-3.0 ends ResetProfile with
                -- `self.callbacks:Fire("OnProfileReset", self)`: the database and no
                -- key. Database:OnProfileChanged names the active profile itself.
                fire("OnProfileReset")
            end

            -- AceDB-3.0's SetProfile: a no-op onto the active name, otherwise
            -- swap the key and the profile table, then
            -- `self.callbacks:Fire("OnProfileChanged", self, name)`.
            db.SetProfile = function(_, key)
                if key == db.keys.profile then return end
                db.keys.profile = key
                db.profile = profileFor(key)
                fire("OnProfileChanged", key)
            end

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
    -- Registration is RECORDED rather than swallowed. core/MediaSetup.lua hands the
    -- library the addon folder name and the library registers every face it ships
    -- under its own key; a no-op Register would let a seam that registered nothing,
    -- or registered a path built from the wrong folder, pass unnoticed.
    LSM.__registered = {}
    -- The locale bits are LibSharedMedia-3.0.lua's own constants (:31-35). Left
    -- to noopLib's __index they would answer a FUNCTION, and LibKa0s-Media adds
    -- western + ruRU into the langmask it hands Register, so the arithmetic
    -- would raise at file load. Register records that 5th argument per key.
    LSM.LOCALE_BIT_koKR    = 1
    LSM.LOCALE_BIT_ruRU    = 2
    LSM.LOCALE_BIT_zhCN    = 4
    LSM.LOCALE_BIT_zhTW    = 8
    LSM.LOCALE_BIT_western = 128
    LSM.__langmask = {}
    function LSM.Register(_, mediaType, key, path, langmask)
        LSM.__registered[mediaType] = LSM.__registered[mediaType] or {}
        LSM.__registered[mediaType][key] = path
        LSM.__langmask[mediaType] = LSM.__langmask[mediaType] or {}
        LSM.__langmask[mediaType][key] = langmask
        return true
    end
    function LSM.Fetch(_, mediaType, key)
        local byType = LSM.__registered[mediaType]
        return (byType and byType[key]) or "Fonts\\FRIZQT__.TTF"
    end
    function LSM.List() return {} end
    function LSM.HashTable() return {} end
    function LSM.IsValid() return true end

    -- ── the launcher's two libraries (launcher-§1) ──────────────────────────
    --
    -- RECORDING fakes rather than noopLib, and rather than the real vendored
    -- files. The real ones are skipped by the harness on purpose --
    -- Loader.tocFiles drops every `libs\` entry -- and LibDBIcon's own code
    -- builds a live minimap button out of CreateFrame, Minimap, and a drag
    -- handler measuring the ring in screen coordinates, none of which this mock
    -- client has. What the suites actually need to see is the three facts
    -- launcher-§1/§3 bind: that there is exactly ONE object, that it is
    -- registered under the addon's FOLDER name with the SAME table the settings
    -- row writes, and that Show/Hide follow the checkbox. A noopLib would answer
    -- every one of those with a shrug.
    local LDB = { __objects = {} }
    --- nil for a name already taken, as the real one does -- which is the branch
    --- LibKa0s-Launcher-1.0 falls back to GetDataObjectByName on.
    function LDB.NewDataObject(_, name, obj)
        if LDB.__objects[name] then return nil end
        LDB.__objects[name] = obj
        return obj
    end
    function LDB.GetDataObjectByName(_, name) return LDB.__objects[name] end

    local DBIcon = { __registered = {}, __shown = {} }
    function DBIcon.Register(_, name, obj, db)
        DBIcon.__registered[name] = { object = obj, db = db }
        DBIcon.__shown[name] = not (db and db.hide)
    end
    function DBIcon.Show(_, name) DBIcon.__shown[name] = true  end
    function DBIcon.Hide(_, name) DBIcon.__shown[name] = false end
    function DBIcon.IsRegistered(_, name) return DBIcon.__registered[name] ~= nil end

    local libs = {
        ["AceDB-3.0"]           = AceDB,
        ["LibDataBroker-1.1"]     = LDB,
        ["LibDBIcon-1.0"]         = DBIcon,
        ["AceConfig-3.0"]         = noopLib(),
        ["AceConfigDialog-3.0"]   = noopLib(),
        ["AceConfigRegistry-3.0"] = noopLib(),
        ["AceDBOptions-3.0"]      = noopLib(),
        ["LibSharedMedia-3.0"]    = LSM,
        ["LibCustomGlow-1.0"]     = noopLib(),
        ["CallbackHandler-1.0"]   = noopLib(),
    }

    -- LibStub is the kit's (mocks.LibStub): strict about the silent flag, and its
    -- NewLibrary registers the vendored LibKa0s files for real, so a file offered
    -- at an equal or lower minor gets nil back. KickCD's fakes go into
    -- mocks.__libs, the table the kit's LibStub reads.
    for name, lib in pairs(libs) do mocks.__libs[name] = lib end

    -- AceGUI is the kit's: its recording widgets, __created, Release,
    -- WidgetVersions and layouts. KickCD adds one recorder on top. SetHighlight is
    -- RECORDED, not swallowed: AceGUI's InteractiveLabel forwards it to
    -- Texture:SetTexture, whose four-number form is the deprecated color API, and
    -- the client answers that with a solid bright-green block across the whole
    -- label on mouseover. A no-op cannot tell "no highlight" from "a highlight
    -- nobody meant", which is exactly what shipped.
    local AceGUI = mocks.__libs["AceGUI-3.0"]
    local kitCreate = AceGUI.Create
    function AceGUI.Create(self, wtype)
        local w = kitCreate(self, wtype)
        if w.SetHighlight == nil then
            function w.SetHighlight(widget, ...) widget.__highlight = { ... }; return widget end
        end
        return w
    end
    mocks.__aceGUI = AceGUI

    -- AceAddon is the kit's: NewAddon honoring its mixin list, NewModule /
    -- GetModule, and the lifecycle. The one KickCD layer is __enableAll, the
    -- enable cascade alone for a load-only harness (the path where the
    -- IconGrid.Layout clobber hid, KCD-05): the addon's OnEnable, then each
    -- module in creation order, through the real public member the client's
    -- PLAYER_LOGIN pass calls per addon. The kit raises the first error once the
    -- cascade has finished, so a throwing OnEnable still fails its case.
    local AceAddon = mocks.__libs["AceAddon-3.0"]
    local kitNewAddon = AceAddon.NewAddon
    function AceAddon.NewAddon(self, ...)
        local obj = kitNewAddon(self, ...)
        function obj.__enableAll(addon) return AceAddon:EnableAddon(addon) end
        return obj
    end

    -- -------------------------------------------------------------------
    -- Frames / UI
    -- -------------------------------------------------------------------
    -- CreateFrame(frameType, name, parent, template): the parent is wired so
    -- IsVisible / GetEffectiveScale can walk the real chain. Frames created
    -- without an explicit parent fall back to UIParent, as in the client.
    local UIParent = makeFrame("Frame", nil)
    mocks.UIParent = UIParent
    -- Every CreateFrame'd frame is also recorded, in creation order. A frame
    -- can be a file-local with no published handle at all, so the registry
    -- plus __findFrame is how a suite reaches one to fire its OnEvent —
    -- without having to widen the addon's public surface just for the tests.
    -- (AceEvent targets, such as core/State.lua's combat listener, are fired
    -- through the kit's __fireEvent instead.)
    local created = {}
    mocks.__frames = created
    mocks.CreateFrame = function(frameType, name, parent, template)
        -- The NAME is honored rather than discarded: the library derives frame
        -- globals from a descriptor and the scrollbar patch builds a name from
        -- GetName(), so a test that cannot see the name cannot assert either.
        local f = makeFrame(frameType or "Frame", parent ~= nil and parent or UIParent, name)
        f.__template = template
        -- The owning build, so the frame's RegisterEvent can read THIS build's
        -- __badEvents at call time (see refuseUnknown above).
        f.__mocks = mocks
        created[#created + 1] = f
        return f
    end
    --- How many created frames are CURRENTLY registered for `event`.
    --- Recorded rather than no-opped because a test needs to observe it: the
    --- per-unit UNIT_SPELLCAST_* cast filters are the thing a perf suspend
    --- has to disarm, and "did they come back?" is only answerable by counting.
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

    -- The client's own fallback face. core/Constants.lua falls back to it when the
    -- LibKa0s payload — which is where the monospace face lives now — is absent, and
    -- a nil here would make that fallback look like it worked while SetFont drew
    -- nothing.
    mocks.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
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

    -- C_AddOns.GetAddOnMetadata, reading the REAL TOC so a version the addon
    -- reports cannot drift from the packaged manifest in a test either. The
    -- addon reads Version through this in two places (the `version` verb and the
    -- perf capture record), and a mock answering nil made both fall back — which
    -- is exactly how a record stamped "v?" passed the suite while failing in game.
    local tocMeta
    local function readTOCMeta()
        if tocMeta then return tocMeta end
        tocMeta = {}
        local fh = io.open(root .. "/KickCD.toc", "r")
        if fh then
            for line in fh:lines() do
                local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*\r?$")
                if k then tocMeta[k] = v end
            end
            fh:close()
        end
        return tocMeta
    end
    -- Reads the REAL TOC, and therefore answers nil for a field the TOC does not
    -- carry as `## Field:` — which includes `Interface` only by accident of it
    -- being one. Blizzard does NOT serve Interface through this API, so the mock
    -- must not either: the library shipped an `interface` field stuck at 0
    -- precisely because its own mock answered every field asked of it.
    mocks.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            if field == "Interface" then return nil end
            return readTOCMeta()[field]
        end,
        IsAddOnLoaded    = function() return true end,
    }

    -- Where the interface version actually comes from: GetBuildInfo's FOURTH
    -- return. Sourced from the TOC so the mock and the addon cannot disagree.
    mocks.GetBuildInfo = function()
        return "12.0.7", "60000", "Jul 31 2026", tonumber(readTOCMeta()["Interface"]) or 0
    end

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
    -- C_Timer is the KIT's -- see "Timers: the KIT's queue, not a second one"
    -- above, where NewTicker is layered onto it. Not re-declared here: a second
    -- table would drop the recording half on the floor.

    -- -------------------------------------------------------------------
    -- Spell / unit / combat APIs (safe inert returns)
    -- -------------------------------------------------------------------
    -- Seeded per spell by a suite. Spell 61304 is the GLOBAL COOLDOWN, and whether it reports
    -- active is the only plain boolean that separates a GCD flip from a real cooldown starting —
    -- every duration involved is secret in combat, so nothing else can be branched on in Lua.
    mocks.spellCooldowns = {}

    mocks.C_Spell = {
        GetSpellInfo = function(id) return { name = "Spell" .. tostring(id), iconID = 12345, spellID = id } end,
        -- Per spell now. Anything unseeded answers the inert "ready" shape this returned for every
        -- id before, so no existing suite changes behavior.
        GetSpellCooldown = function(id)
            return mocks.spellCooldowns[id]
                or { isEnabled = true, startTime = 0, duration = 0, isActive = false }
        end,
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
    -- specName is deliberately the LOCALIZED display name (as Blizzard
    -- returns it) while specID is locale-invariant: that asymmetry is the
    -- whole point of the frFR regression coverage (issue #8).
    local classSpecs = {
        -- [classID] = { classFile, { {specID, localizedName}, ... } }
        [3]  = { "HUNTER",  { { 253, "Beast Mastery" }, { 254, "Marksmanship" }, { 255, "Survival" } } },
        [7]  = { "SHAMAN",  { { 262, "Elemental" }, { 263, "Enhancement" }, { 264, "Restoration" } } },
        [9]  = { "WARLOCK", { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } } },
    }
    local player = { classID = 3, specIndex = 1 }

    --- Reshape the simulated client. Call from a loadInstance mutate hook.
    -- @param classID number        key into classSpecs above
    -- @param specIndex number      1-based index within that class's spec list
    -- @param localizedNames table|nil  optional { [specID] = "localized name" }
    --        overrides, simulating a non-English client.
    function mocks.__setPlayerSpec(classID, specIndex, localizedNames)
        player.classID, player.specIndex = classID, specIndex
        if localizedNames then
            for _, entry in pairs(classSpecs) do
                for _, spec in ipairs(entry[2]) do
                    if localizedNames[spec[1]] then spec[2] = localizedNames[spec[1]] end
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
    -- Three returns like the live API: localized name, file token, classID.
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
        -- routes every per-state alpha and the name color through it rather
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
    --
    --- `total` is what separates a GCD-only lockout from the tail of a real
    --- cooldown: both can sit at the same tiny REMAINING, and only the total
    --- length tells them apart. Defaults to `remaining` so the many callers
    --- that only care about a deep cooldown keep reading the same.
    -- @param remaining number  value EvaluateRemainingDuration resolves to
    -- @param total     number  value EvaluateTotalDuration resolves to
    function mocks.__makeDurationObject(remaining, total)
        local o = {}
        local function evalAt(curve, at)
            -- Read the curve's actual control points so the caller's CHOICE of
            -- curve is observable. Falls back to the raw value (number) or
            -- a stand-in color only when a curve carries no points at all.
            local v = evaluateCurve(curve, at)
            if v ~= nil then return v end
            if curve and curve.__kind == "color" then return makeColor(1, 0.4, 0.4) end
            return at
        end
        function o.EvaluateRemainingDuration(_, curve) return evalAt(curve, remaining or 0.4) end
        function o.EvaluateTotalDuration(_, curve) return evalAt(curve, total or remaining or 0.4) end
        function o.GetRemainingDuration() return remaining or 0.4 end
        function o.GetTotalDuration() return total or remaining or 0.4 end
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
