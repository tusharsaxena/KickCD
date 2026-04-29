-- modules/Cooldowns.lua — KickCD v0.1
--
-- Per-spell cooldown observer. Owns a `watched` table keyed by spellID
-- derived from the active spec's spell list in the current profile, polls
-- state via KickCD.Compat.* on every relevant event, and emits
-- KickCD_SPELL_STATE only for those spells whose state actually changed
-- since the last emission. This avoids spamming the IconGrid on every
-- SPELL_UPDATE_COOLDOWN tick.
--
-- Both Rebuild and Refresh short-circuit when db.profile.enabled is
-- false (master disable); a "general" KickCD_CONFIG_CHANGED triggers a
-- full Rebuild so the watched-list comes back online when the user
-- re-enables.
--
-- Message contract (closed):
--   FIRE:    KickCD_SPELL_STATE { spellID, ready, start, duration, charges }
--   LISTEN:  KickCD_PROFILE_CHANGED,
--            KickCD_CONFIG_CHANGED (section=="spells" or "general")

local KickCD    = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Cooldowns = KickCD:NewModule("Cooldowns", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Spec resolution
-- ---------------------------------------------------------------------------

--- Look up the (CLASS, SPEC) tokens used to key db.profile.spells.
-- CLASS is the localization-independent file token from UnitClass(); SPEC
-- is GetSpecializationInfo's name uppercased to match the keys built in
-- defaults/Spells.lua.
-- @return classToken (string|nil), specToken (string|nil)
local function ResolveClassSpec()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end

    local idx = GetSpecialization and GetSpecialization()
    if not idx then return classFile, nil end

    local _, specName = GetSpecializationInfo(idx)
    if not specName then return classFile, nil end

    return classFile, specName:upper()
end

-- ---------------------------------------------------------------------------
-- Watched-list management
-- ---------------------------------------------------------------------------

--- Compute the freshly-polled state for a single spellID.
-- @param spellID number
-- @return table|nil  { spellID, ready, start, duration, charges }
--   Returns nil if the spell isn't actually known by the player (skip it
--   per FR-2.8).
local function PollSpell(spellID)
    -- Reject obviously-bad IDs early.
    if not spellID or type(spellID) ~= "number" then return nil end

    -- A spell that doesn't return GetSpellInfo at all is definitely not in
    -- the player's spellbook (or the ID is wrong).
    local name = KickCD.Compat.GetSpellInfo(spellID)
    if not name then return nil end

    local start, duration, _, _, isActive = KickCD.Compat.GetSpellCooldown(spellID)
    local usable    = KickCD.Compat.IsSpellUsable(spellID)
    local cur, maxC = KickCD.Compat.GetSpellCharges(spellID)

    -- 12.0 secret-value safety: never compare start/duration in tainted scope.
    -- Use the plain `isActive` boolean from C_Spell.GetSpellCooldown instead.
    local cdActive = isActive
    -- Charges may also come back secret on guarded spells. If so, conserva-
    -- tively assume the spell has charges available — better to flag a spell
    -- as ready when it isn't than to spam errors.
    local hasCharges
    if cur == nil then
        hasCharges = true
    elseif issecretvalue and issecretvalue(cur) then
        hasCharges = true
    else
        hasCharges = cur > 0
    end
    local ready = (not cdActive) and usable and hasCharges

    return {
        spellID  = spellID,
        ready    = ready,
        isActive = isActive,
        start    = start,    -- pass through opaquely (may be secret)
        duration = duration, -- ditto; downstream uses are C-side / gated
        charges  = cur,
        _maxC    = maxC,
    }
end

--- Determine whether two state snapshots differ enough to merit emitting
--- KickCD_SPELL_STATE. We compare the user-visible fields only; modRate
--- and other internal info are ignored.
--- Note: 12.0 secret-value protection means we cannot diff start/duration
--- (the `>` and `-` ops error on secret values). The Cooldown frame ticks
--- itself once SetCooldown is called, so per-tick re-emission isn't needed.
local function StateChanged(prev, next_)
    if not prev then return true end
    if prev.ready    ~= next_.ready    then return true end
    if prev.isActive ~= next_.isActive then return true end
    -- Charges may be secret on guarded spells; only diff when both are plain.
    local a, b = prev.charges, next_.charges
    local aSecret = a ~= nil and issecretvalue and issecretvalue(a)
    local bSecret = b ~= nil and issecretvalue and issecretvalue(b)
    if not (aSecret or bSecret) and a ~= b then return true end
    return false
end

--- True when the master enable flag is set. Defaults to true on a fresh
--- profile, so a missing field reads as enabled.
local function isEnabled()
    local profile = KickCD.db and KickCD.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

--- Rebuild the watched-list from db.profile.spells[CLASS][SPEC] and emit
--- one initial KickCD_SPELL_STATE per surviving spell. Skips spells the
--- player doesn't know. Short-circuits to an empty watched-list when the
--- master enable is off.
function Cooldowns:Rebuild()
    self.watched = {}

    if not isEnabled() then return end

    local profile = KickCD.db and KickCD.db.profile
    if not profile or type(profile.spells) ~= "table" then
        return
    end

    local class, spec = ResolveClassSpec()
    if not class or not spec then
        return
    end

    local list = profile.spells[class] and profile.spells[class][spec]
    if type(list) ~= "table" then
        return
    end

    -- Walk the spec list in order and build the watched dict. We deliberately
    -- ignore order here — the IconGrid module is responsible for layout
    -- ordering, and Cooldowns just needs O(1) state lookup by spellID.
    for _, entry in ipairs(list) do
        if entry.enabled ~= false then
            local id = entry.spellID
            local state = PollSpell(id)
            if state then
                self.watched[id] = state
                KickCD:SendMessage("KickCD_SPELL_STATE", {
                    spellID  = state.spellID,
                    ready    = state.ready,
                    isActive = state.isActive,
                    start    = state.start,
                    duration = state.duration,
                    charges  = state.charges,
                })
            elseif KickCD._debugLog then
                local p = KickCD.Util and KickCD.Util.print or print
                p(("Cooldowns: skipping unknown/unlearned spellID %s"):format(tostring(id)))
            end
        end
    end
end

--- Re-poll all watched spells, fire KickCD_SPELL_STATE only for those whose
--- state changed since last poll.
function Cooldowns:Refresh()
    if not isEnabled() then return end
    if not self.watched then return end
    for id, prev in pairs(self.watched) do
        local next_ = PollSpell(id)
        if next_ and StateChanged(prev, next_) then
            self.watched[id] = next_
            KickCD:SendMessage("KickCD_SPELL_STATE", {
                spellID  = next_.spellID,
                ready    = next_.ready,
                isActive = next_.isActive,
                start    = next_.start,
                duration = next_.duration,
                charges  = next_.charges,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Cooldowns:OnEnable()
    self.watched = {}

    -- Game events that signal cooldown / usability / charge changes.
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "Refresh")
    self:RegisterEvent("SPELL_UPDATE_USABLE",          "Refresh")
    self:RegisterEvent("SPELL_UPDATE_CHARGES",         "Refresh")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",        "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","OnSpecChanged")

    -- Internal messages (closed list).
    self:RegisterMessage("KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("KickCD_CONFIG_CHANGED",  "OnConfigChanged")

    -- Initial build deferred to PLAYER_ENTERING_WORLD when the spec / spellbook
    -- are guaranteed to be populated. If the addon enables late, also try a
    -- best-effort rebuild now.
    if IsLoggedIn and IsLoggedIn() then
        self:Rebuild()
    end
end

function Cooldowns:OnPlayerEnteringWorld()
    self:Rebuild()
end

function Cooldowns:OnSpecChanged(_, unit)
    -- PLAYER_SPECIALIZATION_CHANGED's payload is the unit token; ignore for
    -- units other than the player.
    if unit and unit ~= "player" then return end
    self:Rebuild()
end

function Cooldowns:OnProfileChanged()
    self:Rebuild()
end

function Cooldowns:OnConfigChanged(_, payload)
    local section = payload and payload.section
    if section == "spells" or section == "general" then
        -- "general" covers the master enable flipping on/off — rebuild
        -- so the watched list comes back fully populated when re-enabled
        -- and is cleared when disabled.
        self:Rebuild()
    end
end

-- ---------------------------------------------------------------------------
-- Debug
-- ---------------------------------------------------------------------------

--- /kickcd debug spells — print the watched-list with current state.
function Cooldowns:DebugDump()
    local p = KickCD.Util and KickCD.Util.print or print
    local class, spec = ResolveClassSpec()
    p(("Cooldowns: class=%s spec=%s"):format(tostring(class), tostring(spec)))
    if not self.watched or next(self.watched) == nil then
        p("  (no watched spells)")
        return
    end
    -- Stable-ish output: collect IDs and sort.
    local ids = {}
    for id in pairs(self.watched) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local s = self.watched[id]
        local name = KickCD.Compat.GetSpellInfo(id) or "?"
        -- duration may be a 12.0 "secret value" — %.1f formatting would error.
        local durStr
        if s.duration ~= nil and issecretvalue and issecretvalue(s.duration) then
            durStr = "secret"
        else
            durStr = string.format("%.1f", s.duration or 0)
        end
        p(("  [%d] %s ready=%s active=%s dur=%s charges=%s"):format(
            id, name,
            tostring(s.ready),
            tostring(s.isActive),
            durStr,
            tostring(s.charges)))
    end
end
