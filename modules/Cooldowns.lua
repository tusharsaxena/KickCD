-- modules/Cooldowns.lua
--
-- Per-spell cooldown observer. Owns a `watched` table keyed by spellID
-- derived from the active spec's spell list in the current profile, polls
-- state via KickCD.Compat.* on every relevant event, and emits
-- Ka0s_KickCD_SPELL_STATE only for those spells whose state actually changed
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
--       - cdObj:EvaluateTotalDuration(curve)      (GCD-vs-real-CD filter
--                                                  for alpha/tint visuals)
--   * UNIT_SPELLCAST_SUCCEEDED is suppressed by Blizzard for protected
--     interrupts (Mind Freeze, Pummel, Kick, ...) — the event simply does
--     not fire when the player casts one of those spells. So a cast-event
--     tracker can never disambiguate "real CD" from "just GCD" for the
--     primary icon. Instead, we hand the duration object straight to the
--     IconGrid; the IconGrid evaluates it against a step-shaped curve
--     keyed on the cooldown's TOTAL length (ready alpha for a total ≤ ~GCD
--     upper bound, cooldown alpha beyond), and Blizzard's curve evaluation
--     runs C-side so no Lua comparison ever happens. Keying on the
--     REMAINING time instead reads the last ~1.5s of a real cooldown as a
--     GCD and shows the spell ready before it is.
--
-- Both Rebuild and Refresh short-circuit when db.profile.enabled is
-- false (master disable); a "general" Ka0s_KickCD_CONFIG_CHANGED triggers a
-- full Rebuild so the watched-list comes back online when the user
-- re-enables.
--
-- Message contract (closed):
--   FIRE:    Ka0s_KickCD_SPELL_STATE
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
--   LISTEN:  Ka0s_KickCD_PROFILE_CHANGED,
--            Ka0s_KickCD_CONFIG_CHANGED (section=="spells" or "general")

local addonName, NS = ...
local Cooldowns = NS:NewModule("Cooldowns", "AceEvent-3.0")
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf

-- ---------------------------------------------------------------------------
-- Spec resolution
-- ---------------------------------------------------------------------------

--- Look up the (CLASS, specID) pair used to key db.profile.spells.
-- Both are locale-invariant: CLASS is the file token from UnitClass()'s
-- second return, and the spec is the NUMERIC specID from
-- GetSpecializationInfo's first return. Deriving the spec key from the
-- localized spec NAME instead is issue #8 — it left every non-English
-- client tracking nothing.
-- @return classToken (string|nil), specID (number|nil), classID (number|nil)
local function ResolveClassSpec()
    local _, classFile, classID = UnitClass("player")
    if not classFile then return nil, nil, nil end
    classFile = NS.Util.NormalizeClassToken(classFile)
    return classFile, NS.Util.PlayerSpecID(), classID
end

-- ---------------------------------------------------------------------------
-- Watched-list management
-- ---------------------------------------------------------------------------

--- Is this spellID worth polling at all? All three rejection guards live here
--- so PollSpell keeps exactly two exits, both inside the Perf bracket.
-- @return boolean  false when the grid should hide the entry
local function isPollable(spellID)
    -- Reject obviously-bad IDs early.
    if not spellID or type(spellID) ~= "number" then return false end

    -- A spell that doesn't return GetSpellInfo at all is definitely not in
    -- the player's spellbook (or the ID is wrong).
    local name = NS.Compat.GetSpellInfo(spellID)
    if not name then return false end

    -- GetSpellInfo only proves the ID exists in the spell DB, not that the
    -- player has chosen / learned it. IsSpellAvailable is the
    -- "can the player actually cast this right now" check — needed to hide
    -- the unpicked branch of a talent choice node (e.g. Blood DK's
    -- Gorefiend's Grasp ↔ Abomination Limb) and pet spells whose pet isn't
    -- currently summoned.
    return NS.Compat.IsSpellAvailable(spellID)
end

--- Charges may come back secret on guarded spells. If so, conservatively
--- assume the spell has charges available — better to flag a spell as
--- ready when it isn't than to spam errors.
local function chargesAvailable(cur)
    if cur == nil then return true end
    if _G.issecretvalue and _G.issecretvalue(cur) then return true end
    return cur > 0
end

--- Charge-recharge handle: when the spell has charges and the spell-level
--- cooldown is NOT active (i.e. at least one charge is available), a missing
--- charge is silently recharging in the background. The IconGrid uses this to
--- render the recharge swipe + countdown text WITHOUT applying the
--- on-cooldown alpha/tint — the spell IS castable, it just has fewer charges
--- available than max.
---
--- GetSpellCooldownDuration returns nil at full charges and the recharge timer
--- otherwise, so we can call it unconditionally here (no Lua compare on the
--- possibly-secret charge counts needed). For combat when those counts are
--- secret we trust the API — if it says there's no cooldown, there isn't one.
local function rechargeHandle(spellID, cur, isActive)
    if cur ~= nil and not isActive then
        return NS.Compat.GetSpellCooldownDuration(spellID)
    end
    return nil
end

--- The state record for a spell that passed isPollable.
local function buildSpellState(spellID)
    -- Plain-bool active flag from the legacy API. We deliberately discard
    -- start/duration here — they're secret in combat and the duration
    -- object covers every legitimate downstream use.
    local _, _, _, _, isActive = NS.Compat.GetSpellCooldown(spellID)
    local usable    = NS.Compat.IsSpellUsable(spellID)
    -- Only the current-charge count is needed; the max is discarded (it is
    -- equally secret-prone and nothing downstream compares against it).
    local cur = NS.Compat.GetSpellCharges(spellID)

    -- Secret-aware cooldown handle. We never call :GetRemainingDuration()
    -- on it from Lua; the IconGrid passes it through to
    -- Cooldown:SetCooldownFromDurationObject (swipe),
    -- FontString:SetFormattedText (text), and
    -- cdObj:EvaluateTotalDuration(curve) (GCD-vs-real-CD visual filter)
    -- — all of which accept secret values via C-side argument paths.
    local cdObject = isActive and NS.Compat.GetSpellCooldownDuration(spellID) or nil

    -- `ready` is the canonical "this spell can be cast right now" boolean.
    -- It's used for the spec-locked-spells filter and for downstream UI
    -- "show charges?" decisions, but NOT for visual states — visual states
    -- are derived in the IconGrid by evaluating cdObject against curves so
    -- that a GCD-only "active" period reads as ready visually while still
    -- being uncastable.
    local ready = (not isActive) and usable and chargesAvailable(cur)

    return {
        spellID        = spellID,
        ready          = ready,
        isActive       = isActive == true,
        cdObject       = cdObject,
        chargeCdObject = rechargeHandle(spellID, cur, isActive),
        charges        = cur,
    }
end

--- Compute the freshly-polled state for a single spellID.
-- @param spellID number
-- @return table|nil  { spellID, ready, isActive, cdObject, chargeCdObject, charges }
--   Returns nil if the spell isn't actually known by the player so the
--   icon grid can hide entries the player can't see in their own spellbook.
function Cooldowns:PollSpell(spellID)
    -- TWO exits, and both are instrumented on purpose.
    --
    -- This bucket was left undeclared at first precisely because of them: a
    -- single fall-through bracket would have under-counted `calls` and reported
    -- a total that quietly excluded the rejected paths. The first live capture
    -- then made the omission expensive — spellPoll totaled 125.02 ms of which
    -- its declared child spellState accounted for only 51.14, leaving 73.9 ms
    -- (the largest single cost in the addon) attributed to nothing. So the
    -- bracket opens ABOVE the guards, because GetSpellInfo and IsSpellAvailable
    -- are themselves API calls and part of the poll's real cost, and every exit
    -- closes it. tests/test_perfsetup.lua pins that no exit is left unclosed.
    local __t0 = Perf.on and debugprofilestop()

    if not isPollable(spellID) then
        if __t0 then Perf.Note("pollSpell", debugprofilestop() - __t0) end
        return nil
    end

    -- Built into a local rather than returned inline, so the bracket can close
    -- on this path too. Lua forbids a statement after `return`, and a bracket
    -- that skipped the SUCCESS path would measure only the rejections.
    local state = buildSpellState(spellID)
    if __t0 then Perf.Note("pollSpell", debugprofilestop() - __t0) end
    return state
end

--- Determine whether two state snapshots differ enough to merit emitting
--- Ka0s_KickCD_SPELL_STATE. The IconGrid drives its swipe and countdown text
--- via the cdObject reference once it's handed over, so per-tick re-
--- emission isn't needed — only state transitions matter (ready ↔ on-CD,
--- charges available ↔ none).
--- Does a transition warrant a DEBUG LINE? Deliberately narrower than
--- StateChanged.
---
--- StateChanged returns true whenever the cooldown handle differs, and
--- C_Spell.GetSpellCooldownDuration hands back a FRESH object on every call
--- — so a spell parked on an unchanged 60s cooldown compares unequal on
--- every poll. That re-emit is load-bearing (Icon:Apply re-evaluates the
--- alpha / tint / GCD-suppression curves off the emitted object, and nothing
--- else re-runs them), but logging it produced ~10 identical
--- `[Cooldowns] N/M changed: active=[...]` lines per second for the whole
--- cooldown, drowning the console — the same per-gesture spam §9 forbids
--- and the same reason _logRebuild has its own material-change gate.
---
--- So: key on what actually changed about the spell's STATE, treating the
--- handles as present/absent rather than comparing identity.
local function MaterialChange(prev, next_)
    if not prev then return true end
    if prev.ready    ~= next_.ready    then return true end
    if prev.isActive ~= next_.isActive then return true end
    -- Presence, not identity: "a cooldown started / ended" is material,
    -- "the API minted a new wrapper for the same cooldown" is not.
    if (prev.cdObject       == nil) ~= (next_.cdObject       == nil) then return true end
    if (prev.chargeCdObject == nil) ~= (next_.chargeCdObject == nil) then return true end

    local a, b = prev.charges, next_.charges
    if a == nil and b == nil then return false end
    local aSecret = a ~= nil and _G.issecretvalue and _G.issecretvalue(a)
    local bSecret = b ~= nil and _G.issecretvalue and _G.issecretvalue(b)
    -- Secret charges CANNOT be compared (§ secret values), so we genuinely
    -- cannot tell whether they moved. StateChanged resolves that ambiguity by
    -- emitting conservatively — correct there, since a redundant render is
    -- harmless. Here the conservative answer is the opposite: logging every
    -- poll for every charged spell in combat is exactly the flood this gate
    -- exists to stop, and it would make the console useless in the one
    -- situation you most need it. A charge change that matters almost always
    -- moves `ready` or `isActive` too, which is caught above.
    if aSecret or bSecret then return false end
    return a ~= b
end

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
    local profile = NS.db and NS.db.profile
    if not profile then return true end
    return profile.enabled ~= false
end

--- Rebuild the watched-list from db.profile.spells[CLASS][SPEC] and emit
--- one initial Ka0s_KickCD_SPELL_STATE per surviving spell. Skips spells the
--- player doesn't know. Short-circuits to an empty watched-list when the
--- master enable is off.
function Cooldowns:Rebuild()
    self.watched = {}

    if not isEnabled() then return end

    local class, spec, classID = ResolveClassSpec()
    if not class or not spec then
        return
    end

    -- Read-only lookup via Database:GetSpellList — never lazy-creates
    -- a per-spec table, so a class+spec the user has never customized
    -- doesn't pollute the saved-vars with an empty entry.
    local list = NS.Database and NS.Database:GetSpellList(class, spec)
    if not list then
        return
    end

    -- Walk the spec list in order and build the watched dict. We deliberately
    -- ignore order here — the IconGrid module is responsible for layout
    -- ordering, and Cooldowns just needs O(1) state lookup by spellID.
    -- Collected (not just counted) so the debug summary can name them: a
    -- pasted log then shows WHICH spells were dropped, not merely how many.
    local watchedIDs, skippedIDs = {}, {}
    for _, entry in ipairs(list) do
        if entry.enabled ~= false then
            local id = entry.spellID
            local state = self:PollSpell(id)
            if state then
                self.watched[id] = state
                watchedIDs[#watchedIDs + 1] = id
                NS:SendMessage("Ka0s_KickCD_SPELL_STATE", {
                    spellID        = state.spellID,
                    ready          = state.ready,
                    isActive       = state.isActive,
                    cdObject       = state.cdObject,
                    chargeCdObject = state.chargeCdObject,
                    charges        = state.charges,
                })
            else
                skippedIDs[#skippedIDs + 1] = id
            end
        end
    end

    self:_logRebuild(class, classID, spec, watchedIDs, skippedIDs)
end

--- Log a rebuild summary, but only when the result MATERIALLY changed since
--- the last logged rebuild. A cosmetic reactor rebuild spams otherwise:
--- the Master scale / alpha sliders are `general`-section, so dragging one
--- fires Helpers.Set ~20/sec → a synchronous Rebuild ~20/sec, none of which
--- changes the watched spell list. Without this gate that produced ~20
--- identical `[Cooldowns] rebuild …` lines/sec — exactly the per-gesture spam
--- §9 forbids. Signature = class/spec + both spellID lists; built only when
--- debug is on (§4 zero-alloc).
---
--- The line names every watched and skipped spellID, plus the numeric class
--- and spec IDs alongside their English tokens. That combination is what
--- makes a pasted debug log diagnosable on its own: issue #8 needed exactly
--- this — the ID proves which spec the addon actually resolved, and the
--- skipped list distinguishes "the spec list is empty" from "the spells are
--- there but the player can't cast them".
---
-- @param class        string  class file token, e.g. "SHAMAN"
-- @param classID      number|nil  UnitClass()'s third return
-- @param spec         number|nil  numeric specID
-- @param watchedIDs   table  array of spellIDs now being watched, in list order
-- @param skippedIDs   table  array of spellIDs skipped as unknown/unavailable
function Cooldowns:_logRebuild(class, classID, spec, watchedIDs, skippedIDs)
    if not (NS.State and NS.State.debug) then return end
    watchedIDs = watchedIDs or {}
    skippedIDs = skippedIDs or {}
    local watchedList = table.concat(watchedIDs, ",")
    local skippedList = table.concat(skippedIDs, ",")

    local sig = tostring(class) .. "/" .. tostring(spec)
        .. "|" .. watchedList .. "|" .. skippedList
    if sig == self._lastRebuildSig then return end
    self._lastRebuildSig = sig

    NS.Debug("Cooldowns", "rebuild %s(%s) %s(%s): %d watched (%s); %d skipped (%s)",
        tostring(class), tostring(classID),
        NS.Util.SpecDisplay(spec), tostring(spec),
        #watchedIDs, watchedList,
        #skippedIDs, skippedList)
end

--- Re-poll all watched spells, fire Ka0s_KickCD_SPELL_STATE only for those whose
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
    local __t0 = Perf.on and debugprofilestop()

    local dbg = NS.State and NS.State.debug
    local readyIds, activeIds, dropIds  -- built only when debug-on (§9 zero-alloc)
    if dbg then readyIds, activeIds, dropIds = {}, {}, {} end
    -- `logged` counts MATERIAL changes (see MaterialChange), which is a subset
    -- of the emits: a fresh cooldown handle for an unchanged cooldown re-emits
    -- to the renderer but must not reach the log. The printed count has to
    -- match the ids actually listed, so the line reports `logged`.
    local watched, logged = 0, 0

    for id, prev in pairs(self.watched) do
        watched = watched + 1
        local next_ = self:PollSpell(id)
        if next_ == nil then
            -- Spell disappeared (pet dismiss, talent untrain, ...). Force
            -- the icon back to ready visuals and stop polling it; the next
            -- Rebuild trims it out of the watched list entirely.
            self.watched[id] = nil
            -- A vanished spell is always material.
            logged = logged + 1
            if dbg then dropIds[#dropIds + 1] = id end
            NS:SendMessage("Ka0s_KickCD_SPELL_STATE", {
                spellID = id, ready = false, isActive = false,
                cdObject = nil, chargeCdObject = nil, charges = nil,
            })
        elseif StateChanged(prev, next_) then
            -- Emit unconditionally — the renderer needs the fresh handle to
            -- re-evaluate its curves. Log only a material change.
            if MaterialChange(prev, next_) then
                logged = logged + 1
                if dbg then
                    if next_.ready then readyIds[#readyIds + 1] = id
                    elseif next_.isActive then activeIds[#activeIds + 1] = id end
                end
            end
            self.watched[id] = next_
            NS:SendMessage("Ka0s_KickCD_SPELL_STATE", {
                spellID = next_.spellID, ready = next_.ready, isActive = next_.isActive,
                cdObject = next_.cdObject, chargeCdObject = next_.chargeCdObject,
                charges = next_.charges,
            })
        end
    end

    if dbg and logged > 0 then
        local parts = {}
        if #readyIds  > 0 then parts[#parts+1] = "ready=["  .. table.concat(readyIds, ",")  .. "]" end
        if #activeIds > 0 then parts[#parts+1] = "active=[" .. table.concat(activeIds, ",") .. "]" end
        if #dropIds   > 0 then parts[#parts+1] = "drop=["   .. table.concat(dropIds, ",")   .. "]" end
        NS.Debug("Cooldowns", "%d/%d changed: %s", logged, watched, table.concat(parts, " "))
    end
    if __t0 then Perf.Note("spellPoll", debugprofilestop() - __t0) end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- The module's GAME-event registrations, split out of OnEnable so a perf
--- Resume can re-arm the same set without re-running the rest of the enable path
--- (rebuilding the watched table, re-subscribing to messages it never dropped).
--- Idempotent: AceEvent keys on (event, target).
function Cooldowns:RegisterLifecycleEvents()
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "OnCooldownEvent")
    self:RegisterEvent("SPELL_UPDATE_USABLE",          "OnCooldownEvent")
    self:RegisterEvent("SPELL_UPDATE_CHARGES",         "OnCooldownEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",        "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","OnSpecChanged")
    -- Talent / spellbook changes within the active spec also flip the
    -- "available" set (a choice-node swap, learning a new ability, pet
    -- summon/dismiss for pet spells). Rebuild on either signal so spells
    -- the player just gained appear and ones they just lost disappear
    -- without waiting for a spec change.
    self:RegisterEvent("SPELLS_CHANGED",               "Rebuild")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED",         "Rebuild")
end

function Cooldowns:OnEnable()
    self.watched = {}

    -- Game events that signal cooldown / usability / charge changes.
    -- SPELL_UPDATE_COOLDOWN / _USABLE are global (they don't name the changed
    -- spell) and chatty — they fire many times per frame in combat, and each
    -- fire would re-poll EVERY watched spell. Coalesce a same-frame burst into
    -- one Refresh on the next frame via a zero-delay throttle. Refresh ignores
    -- its args (it re-polls the watched table fresh), so the throttle's
    -- trailing-args semantics are irrelevant here.
    self._refreshCoalesced = NS.Util.Throttle(0, function() self:Refresh() end)
    self:RegisterLifecycleEvents()

    -- Internal messages (closed list).
    self:RegisterMessage("Ka0s_KickCD_PROFILE_CHANGED", "OnProfileChanged")
    self:RegisterMessage("Ka0s_KickCD_CONFIG_CHANGED",  "OnConfigChanged")

    -- Initial build deferred to PLAYER_ENTERING_WORLD when the spec / spellbook
    -- are guaranteed to be populated. If the addon enables late, also try a
    -- best-effort rebuild now.
    if IsLoggedIn and IsLoggedIn() then
        self:Rebuild()
    end
end

--- AceEvent handler for the chatty SPELL_UPDATE_* family. Forwards into the
--- per-frame coalescer built in OnEnable so a burst of these events triggers
--- a single Refresh() on the next frame rather than one full re-poll each.
function Cooldowns:OnCooldownEvent()
    if self._refreshCoalesced then self._refreshCoalesced() end
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
    local p = NS.Util and NS.Util.print or print
    local class, spec = ResolveClassSpec()
    -- English token, not the localized name: this line is what users paste
    -- into bug reports (issue #8).
    p(("Cooldowns: class=%s spec=%s (%s)"):format(
        tostring(class), NS.Util.SpecDisplay(spec), tostring(spec)))
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
    --
    -- The shared stringifier (LibKa0s-Core-1.0, via core/CoreSetup.lua), not a
    -- local copy. Two things change and both are improvements: the sentinel is
    -- now "<secret>" — the same one core/Compat.lua already used, so a pasted
    -- log spells the condition one way — and the probe is `table.concat` rather
    -- than `issecretvalue`, which tests the operation that actually rejects a
    -- secret instead of asking the API whether it thinks it has one.
    --
    -- NB: only the STRINGIFIER moves. The issecretvalue calls in StateChanged
    -- and MaterialChange above are control flow over an incomparable value, not
    -- rendering, and must stay exactly as they are.
    local safeStr = NS.SafeToString
    for _, id in ipairs(ids) do
        local s = self.watched[id]
        local name = NS.Compat.GetSpellInfo(id) or "?"
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

-- ---------------------------------------------------------------------------
-- Exposed for unit testing
-- ---------------------------------------------------------------------------
--
-- The two change-detection gates are pure and carry the module's trickiest
-- rule — that a secret `charges` is treated OPPOSITELY by each (StateChanged
-- emits conservatively, MaterialChange stays quiet). Published so the harness
-- can pin that asymmetry; internal call sites still use the locals.
-- NB: named MasterEnabled, NOT IsEnabled — AceAddon embeds its own
-- IsEnabled(self) (returns self.enabledState) directly onto every module
-- object, so publishing under that name would silently shadow the library
-- method with one that answers a different question.
Cooldowns.MaterialChange = MaterialChange
Cooldowns.StateChanged   = StateChanged
Cooldowns.MasterEnabled  = isEnabled
