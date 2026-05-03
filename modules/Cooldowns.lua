-- modules/Cooldowns.lua
--
-- Per-spell cooldown observer. Owns a `watched` table keyed by spellID
-- derived from the active spec's spell list in the current profile, polls
-- state via KickCD.Compat.* on every relevant event, and emits
-- KickCD_SPELL_STATE only for those spells whose state actually changed
-- since the last emission. This avoids spamming the IconGrid on every
-- SPELL_UPDATE_COOLDOWN tick.
--
-- 12.0 secret-value strategy:
--   * In COMBAT, every watched spell's start/duration AND its
--     CooldownDuration:GetRemainingDuration() come back as secret-tainted
--     numbers. Any arithmetic / comparison / format / tostring on those
--     values from tainted scope errors out. (Out of combat, the same
--     calls return plain numbers — that's why a comparison-based filter
--     can look correct in testing but blow up the moment combat opens.)
--   * The CooldownDuration object itself is safe to pass through to
--     Blizzard C methods. The IconGrid module routes it to:
--       - Cooldown:SetCooldownFromDurationObject  (swipe)
--       - FontString:SetFormattedText             (countdown text)
--       - cdObj:EvaluateRemainingDuration(curve)  (GCD-vs-real-CD filter
--                                                  for alpha/tint visuals)
--   * UNIT_SPELLCAST_SUCCEEDED is suppressed by Blizzard for protected
--     interrupts (Mind Freeze, Pummel, Kick, ...) — the event simply does
--     not fire when the player casts one of those spells. So a cast-event
--     tracker can never disambiguate "real CD" from "just GCD" for the
--     primary icon. Instead, we hand the duration object straight to the
--     IconGrid; the IconGrid evaluates it against a step-shaped curve
--     (ready alpha for remaining ≤ ~GCD upper bound, cooldown alpha
--     beyond), and Blizzard's curve evaluation runs C-side so no Lua
--     comparison ever happens.
--
-- Both Rebuild and Refresh short-circuit when db.profile.enabled is
-- false (master disable); a "general" KickCD_CONFIG_CHANGED triggers a
-- full Rebuild so the watched-list comes back online when the user
-- re-enables.
--
-- Message contract (closed):
--   FIRE:    KickCD_SPELL_STATE
--              { spellID, ready, isActive, cdObject, chargeCdObject, charges }
--            charges is the raw currentCharges from
--            C_Spell.GetSpellCharges (or nil for uncharged spells). A
--            value of 0 means "no charges available right now" — the
--            IconGrid renders it as a "0" badge but state.ready is false
--            so the icon body still dims.
--            cdObject is the secret-aware duration object for the
--            spell-level cooldown — non-nil whenever the legacy isActive
--            flag is true (real CD or just GCD; the IconGrid
--            distinguishes via curve evaluation).
--            chargeCdObject is the duration object for the recharge
--            timer of a partially-charged spell (charges < maxCharges
--            while isActive=false). The IconGrid renders its swipe +
--            countdown text but does NOT apply the cooldown alpha/tint —
--            the spell IS castable (state.ready stays true), it just
--            has fewer charges available than max.
--   LISTEN:  KickCD_PROFILE_CHANGED,
--            KickCD_CONFIG_CHANGED (section=="spells" or "general")

local KickCD    = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local Cooldowns = KickCD:NewModule("Cooldowns", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Spec resolution
-- ---------------------------------------------------------------------------

--- Look up the (CLASS, SPEC) tokens used to key db.profile.spells.
-- CLASS is the localization-independent file token from UnitClass(); SPEC
-- is GetSpecializationInfo's localised name routed through
-- Util.NormalizeSpecToken so multi-word names (English "Beast Mastery"
-- and several non-English specs) collapse to the keys built in
-- defaults/Spells.lua.
-- @return classToken (string|nil), specToken (string|nil)
local function ResolveClassSpec()
    local _, classFile = UnitClass("player")
    if not classFile then return nil, nil end
    classFile = KickCD.Util.NormalizeClassToken(classFile)

    local idx = GetSpecialization and GetSpecialization()
    if not idx then return classFile, nil end

    local _, specName = GetSpecializationInfo(idx)
    if not specName then return classFile, nil end

    return classFile, KickCD.Util.NormalizeSpecToken(specName)
end

-- ---------------------------------------------------------------------------
-- Watched-list management
-- ---------------------------------------------------------------------------

local function dprint(...)
    if KickCD._debugLog and KickCD.Util and KickCD.Util.print then
        KickCD.Util.print("Cooldowns:", ...)
    end
end

--- Compute the freshly-polled state for a single spellID.
-- @param spellID number
-- @return table|nil  { spellID, ready, isActive, cdObject, chargeCdObject, charges }
--   Returns nil if the spell isn't actually known by the player so the
--   icon grid can hide entries the player can't see in their own spellbook.
function Cooldowns:PollSpell(spellID)
    -- Reject obviously-bad IDs early.
    if not spellID or type(spellID) ~= "number" then return nil end

    -- A spell that doesn't return GetSpellInfo at all is definitely not in
    -- the player's spellbook (or the ID is wrong).
    local name = KickCD.Compat.GetSpellInfo(spellID)
    if not name then return nil end

    -- GetSpellInfo only proves the ID exists in the spell DB, not that the
    -- player has chosen / learned it. IsSpellAvailable is the
    -- "can the player actually cast this right now" check — needed to hide
    -- the unpicked branch of a talent choice node (e.g. Blood DK's
    -- Gorefiend's Grasp ↔ Abomination Limb) and pet spells whose pet isn't
    -- currently summoned.
    if not KickCD.Compat.IsSpellAvailable(spellID) then return nil end

    -- Plain-bool active flag from the legacy API. We deliberately discard
    -- start/duration here — they're secret in combat and the duration
    -- object covers every legitimate downstream use.
    local _, _, _, _, isActive = KickCD.Compat.GetSpellCooldown(spellID)
    local usable    = KickCD.Compat.IsSpellUsable(spellID)
    local cur, maxC = KickCD.Compat.GetSpellCharges(spellID)

    -- Secret-aware cooldown handle. We never call :GetRemainingDuration()
    -- on it from Lua; the IconGrid passes it through to
    -- Cooldown:SetCooldownFromDurationObject (swipe),
    -- FontString:SetFormattedText (text), and
    -- cdObj:EvaluateRemainingDuration(curve) (GCD-vs-real-CD visual filter)
    -- — all of which accept secret values via C-side argument paths.
    local cdObject = isActive and KickCD.Compat.GetSpellCooldownDuration(spellID) or nil

    -- Charges may come back secret on guarded spells. If so, conservatively
    -- assume the spell has charges available — better to flag a spell as
    -- ready when it isn't than to spam errors.
    local hasCharges
    if cur == nil then
        hasCharges = true
    elseif _G.issecretvalue and _G.issecretvalue(cur) then
        hasCharges = true
    else
        hasCharges = cur > 0
    end

    -- Charge-recharge handle: when the spell has charges and the
    -- spell-level cooldown is NOT active (i.e. at least one charge is
    -- available), a missing charge is silently recharging in the
    -- background. The IconGrid uses this to render the recharge swipe +
    -- countdown text WITHOUT applying the on-cooldown alpha/tint — the
    -- spell IS castable, it just has fewer charges available than max.
    --
    -- GetSpellCooldownDuration returns nil at full charges and the
    -- recharge timer otherwise, so we can call it unconditionally here
    -- (no Lua compare on possibly-secret cur/maxC needed). For combat
    -- when both cur and maxC are secret we trust the API — if it says
    -- there's no cooldown, there isn't one.
    local chargeCdObject
    if cur ~= nil and not isActive then
        chargeCdObject = KickCD.Compat.GetSpellCooldownDuration(spellID)
    end

    -- `ready` is the canonical "this spell can be cast right now" boolean.
    -- It's used for the spec-locked-spells filter and for downstream UI
    -- "show charges?" decisions, but NOT for visual states — visual states
    -- are derived in the IconGrid by evaluating cdObject against curves so
    -- that a GCD-only "active" period reads as ready visually while still
    -- being uncastable.
    local ready = (not isActive) and usable and hasCharges

    if KickCD._debugLog then
        dprint(("poll [%d] %s isActive=%s usable=%s ready=%s cdObj=%s chargeCdObj=%s"):format(
            spellID, tostring(name),
            tostring(isActive),
            tostring(usable),
            tostring(ready),
            cdObject and "yes" or "nil",
            chargeCdObject and "yes" or "nil"))
    end

    return {
        spellID        = spellID,
        ready          = ready,
        isActive       = isActive == true,
        cdObject       = cdObject,
        chargeCdObject = chargeCdObject,
        charges        = cur,
    }
end

--- Determine whether two state snapshots differ enough to merit emitting
--- KickCD_SPELL_STATE. The IconGrid drives its swipe and countdown text
--- via the cdObject reference once it's handed over, so per-tick re-
--- emission isn't needed — only state transitions matter (ready ↔ on-CD,
--- charges available ↔ none).
local function StateChanged(prev, next_)
    if not prev then return true end
    if prev.ready          ~= next_.ready          then return true end
    if prev.isActive       ~= next_.isActive       then return true end
    if prev.cdObject       ~= next_.cdObject       then return true end
    if prev.chargeCdObject ~= next_.chargeCdObject then return true end
    -- Charges in combat: C_Spell.GetSpellCharges returns secret-tainted
    -- numbers for charged spells (Blood Boil, Death Grip, talented Mind
    -- Freeze...). We can't `~=` two secrets without erroring. Previously
    -- we skipped the diff entirely when either side was secret — but
    -- that suppresses real transitions for spells whose only changing
    -- field is `charges` (e.g. a charge recharging on a spell whose
    -- spell-level cooldown stays inactive because at-least-one-charge
    -- is available; cdObject stays nil, ready/active stay unchanged).
    -- The 1→2 transition for Blood Boil hit exactly this trap.
    --
    -- Solution: when either side is secret, conservatively emit. The
    -- IconGrid render path uses FontString:SetFormattedText("%d", c)
    -- which accepts secret args C-side, so a redundant emit with the
    -- (possibly identical) value is harmless and cheap. The cost is a
    -- per-event re-emit for charged spells in combat — well within
    -- budget (a SetFormattedText call per SPELL_UPDATE_*).
    local a, b = prev.charges, next_.charges
    if a == nil and b == nil then return false end
    local aSecret = a ~= nil and _G.issecretvalue and _G.issecretvalue(a)
    local bSecret = b ~= nil and _G.issecretvalue and _G.issecretvalue(b)
    if aSecret or bSecret then return true end
    if a ~= b then return true end
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

    local class, spec = ResolveClassSpec()
    if not class or not spec then
        return
    end

    -- Read-only lookup via Database:GetSpellList — never lazy-creates
    -- a per-spec table, so a class+spec the user has never customised
    -- doesn't pollute the saved-vars with an empty entry.
    local list = KickCD.Database and KickCD.Database:GetSpellList(class, spec)
    if not list then
        return
    end

    -- Walk the spec list in order and build the watched dict. We deliberately
    -- ignore order here — the IconGrid module is responsible for layout
    -- ordering, and Cooldowns just needs O(1) state lookup by spellID.
    for _, entry in ipairs(list) do
        if entry.enabled ~= false then
            local id = entry.spellID
            local state = self:PollSpell(id)
            if state then
                self.watched[id] = state
                KickCD:SendMessage("KickCD_SPELL_STATE", {
                    spellID        = state.spellID,
                    ready          = state.ready,
                    isActive       = state.isActive,
                    cdObject       = state.cdObject,
                    chargeCdObject = state.chargeCdObject,
                    charges        = state.charges,
                })
            elseif KickCD._debugLog then
                local p = KickCD.Util and KickCD.Util.print or print
                p(("Cooldowns: skipping unknown/unlearned spellID %s"):format(tostring(id)))
            end
        end
    end
end

--- Re-poll all watched spells, fire KickCD_SPELL_STATE only for those whose
--- state changed since last poll. When a previously-watched spell becomes
--- unavailable mid-fight (PollSpell returns nil — pet dismissed, talent
--- swapped to the other branch of a choice node, encounter mechanic
--- suppresses the spell), emit a sentinel "ready / no cooldown" payload
--- and drop the entry from self.watched. The IconGrid's OnSpellState path
--- already handles a no-cdObject branch (renders ready visuals); the next
--- Rebuild on SPELLS_CHANGED / TRAIT_CONFIG_UPDATED removes the now-
--- orphaned icon from ordered[]. Without this cleanup the icon would
--- linger with whatever state was current when the spell vanished, until
--- a manual /reload.
function Cooldowns:Refresh()
    if not isEnabled() then return end
    if not self.watched then return end
    for id, prev in pairs(self.watched) do
        local next_ = self:PollSpell(id)
        if next_ == nil then
            -- Spell disappeared (pet dismiss, talent untrain, ...). Force
            -- the icon back to ready visuals and stop polling it; the next
            -- Rebuild trims it out of the watched list entirely.
            self.watched[id] = nil
            KickCD:SendMessage("KickCD_SPELL_STATE", {
                spellID        = id,
                ready          = false,
                isActive       = false,
                cdObject       = nil,
                chargeCdObject = nil,
                charges        = nil,
            })
            if KickCD._debugLog then
                dprint(("drop  [%d] became unavailable; sentinel SPELL_STATE emitted"):format(id))
            end
        elseif StateChanged(prev, next_) then
            self.watched[id] = next_
            KickCD:SendMessage("KickCD_SPELL_STATE", {
                spellID        = next_.spellID,
                ready          = next_.ready,
                isActive       = next_.isActive,
                cdObject       = next_.cdObject,
                chargeCdObject = next_.chargeCdObject,
                charges        = next_.charges,
            })
            if KickCD._debugLog then
                dprint(("emit  [%d] ready=%s isActive=%s cdObj=%s"):format(
                    next_.spellID,
                    tostring(next_.ready),
                    tostring(next_.isActive),
                    next_.cdObject and "yes" or "nil"))
            end
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
    -- Talent / spellbook changes within the active spec also flip the
    -- "available" set (a choice-node swap, learning a new ability, pet
    -- summon/dismiss for pet spells). Rebuild on either signal so spells
    -- the player just gained appear and ones they just lost disappear
    -- without waiting for a spec change.
    self:RegisterEvent("SPELLS_CHANGED",               "Rebuild")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED",         "Rebuild")

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
    -- charges may be secret in combat for charged spells; tostring on a
    -- secret returns a secret, which then trips string.format and
    -- table.concat downstream. Substitute a safe placeholder.
    local function safeStr(v)
        if v == nil then return "nil" end
        if _G.issecretvalue and _G.issecretvalue(v) then return "secret" end
        return tostring(v)
    end
    for _, id in ipairs(ids) do
        local s = self.watched[id]
        local name = KickCD.Compat.GetSpellInfo(id) or "?"
        -- We deliberately don't print remaining time — :GetRemainingDuration()
        -- is secret in combat and even tostring would error in tainted scope.
        p(("  [%d] %s ready=%s active=%s cdObj=%s chargeCdObj=%s charges=%s"):format(
            id, name,
            tostring(s.ready),
            tostring(s.isActive),
            s.cdObject and "yes" or "nil",
            s.chargeCdObject and "yes" or "nil",
            safeStr(s.charges)))
    end
end
