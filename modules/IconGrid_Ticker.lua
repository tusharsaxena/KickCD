-- modules/IconGrid_Ticker.lua — the icons' cooldown-text ticker (peeled from IconGrid_Render.lua, #26)
--
-- The countdown text an icon draws over its swipe: Icon:StartCooldownText,
-- Icon:StopCooldownText and Icon:_RenderCooldownText, plus the ONE shared
-- C_Timer.NewTicker(0.1) that drives every registered icon
-- (IconGrid:_RegisterTextIcon / _UnregisterTextIcon / _StopTextTicker).
-- A pure move, for layout-§1's band. Named for the role it is about to take: KickCD#9
-- moves the rest of an icon's time-varying render (the curves and the swipe) onto
-- this ticker.
--
-- The Icon methods are defined on the prototype IconGrid_Render.lua publishes
-- (IconGrid.Icon). Mixin copies the prototype when CreateIconWidget builds a
-- widget, at enable time, by which point this file has loaded (KickCD.toc's
-- LOAD-BEARING note puts it after IconGrid_Render.lua).

local _, NS = ...
-- Perf bracket upvalue (performance-§2 / anti-patterns #43): resolved ONCE at
-- file load, never through an NS lookup on the hot path. core/PerfSetup.lua
-- loads before modules/, so this is always the real instance or its stub.
local Perf = NS.Perf
local IconGrid = NS:GetModule("IconGrid")
local Icon = IconGrid.Icon

-- Cooldown-text ticker: the set of icons needing a per-tick FontString refresh and
-- the single shared C_Timer.NewTicker handle.
local _textIcons  = {}
local _textTicker

-- Drive the cooldownText FontString from a CooldownDuration object.
--
-- 12.0 secret-value protection means we cannot read :GetRemainingDuration()
-- into a Lua local in combat (the value is itself secret-tainted, and
-- tostring / string.format / `<` / `-` all error). The trick is to pass
-- the secret directly into a Blizzard C method as a function argument —
-- argument passing crosses into C without ever holding the value in a
-- tainted Lua local. FontString:SetFormattedText(fmt, arg) does the
-- formatting C-side, so this works:
--
--     fontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())
--
-- We can't conditionally choose the format (no comparison on remaining is
-- legal), so we live with a single fixed format ("%.1f").
--
-- A single module-level C_Timer.NewTicker (see _textTicker below) iterates
-- the registered icons every 0.1s and calls _RenderCooldownText on each.
-- Per-icon OnUpdate scripts were the previous implementation but ran a
-- separate frame-driver per visible cooldown — N icons meant N OnUpdate
-- callbacks per tick. The shared ticker collapses the fixed cost to one.
-- For full spell-level cooldowns we additionally re-poll the plain
-- `isActive` bool from Compat.GetSpellCooldown — SPELL_UPDATE_COOLDOWN
-- can lag the actual cooldown end by a few hundred ms, leaving the text
-- stuck at "0.0" until Cooldowns:Refresh re-emits SPELL_STATE. Because
-- isActive is plain (taint-safe), reading it here is free; on the flip
-- we kill the text + clear the swipe locally and let Cooldowns catch up
-- via its own event handler shortly after.
--
-- For the charge-recharge path (cdObject = state.chargeCdObject,
-- isFullCooldown=false), the spell-level isActive stays false the
-- whole time so we skip that early-exit branch — SPELL_UPDATE_CHARGES
-- handles the recharge-end transition with adequate latency.
function Icon:StartCooldownText(cdObject, isFullCooldown)
    local cfg = self.cfg or NS.Units.Icons(self.unit or "target")
    if not cfg.showCooldownText or not cdObject then
        self:StopCooldownText()
        return
    end
    self._cdObject       = cdObject
    self._isFullCooldown = isFullCooldown and true or false
    -- Initial paint. SetFormattedText handles the secret value via its
    -- C-side argument path; the same pattern is used by the shared
    -- ticker driver.
    self.cooldownText:SetFormattedText("%.1f", cdObject:GetRemainingDuration())
    self.cooldownText:Show()
    -- Register with the module-level ticker (see IconGrid:_RegisterTextIcon).
    -- Idempotent — re-registering a widget already in the set is a no-op.
    IconGrid:_RegisterTextIcon(self)
end

function Icon:StopCooldownText()
    IconGrid:_UnregisterTextIcon(self)
    self._cdObject = nil
    self.cooldownText:Hide()
end

--- Per-tick render for one icon's cooldown text. Called by the module-
--- level ticker for every registered widget. Mirrors the per-frame work
--- the previous OnUpdate did (full-cooldown plain-bool early-exit +
--- secret-safe SetFormattedText), but the iteration cadence comes from
--- the shared ticker, not a per-icon script.
function Icon:_RenderCooldownText()
    local obj = self._cdObject
    if not obj then
        self:StopCooldownText()
        return
    end
    if self._isFullCooldown then
        local _, _, _, _, isActive = NS.Compat.GetSpellCooldown(self.spellID)
        if not isActive then
            self:StopCooldownText()
            if self.cooldown then
                self.cooldown:Hide()
                self.cooldown:Clear()
            end
            return
        end
    end
    self.cooldownText:SetFormattedText("%.1f", obj:GetRemainingDuration())
end

-- ---------------------------------------------------------------------------
-- Shared cooldown-text ticker
-- ---------------------------------------------------------------------------
--
-- One C_Timer.NewTicker(0.1) drives every visible cooldown's countdown
-- text. Icons register on StartCooldownText and deregister on
-- StopCooldownText (or ReleaseAll); the ticker pauses (Cancel + nil)
-- the moment the set goes empty so the addon costs nothing while no
-- cooldowns are active. Re-arms on the next register call.

local function _tickAllTextIcons()
    local __t0 = Perf.on and debugprofilestop()
    -- Snapshot the count and short-circuit if empty — guards against
    -- a race where the ticker fires after the last icon deregistered
    -- but before we got around to canceling the timer.
    if next(_textIcons) == nil then
        if _textTicker and _textTicker.Cancel then
            _textTicker:Cancel()
        end
        _textTicker = nil
        -- Close the bracket on THIS exit too. The tick that finds the set
        -- empty still paid for the ticker callback and the `next` probe, and
        -- it is the exit taken on the very last tick of every cooldown burst
        -- — so leaving it unclosed under-counts `cdText.calls` by exactly the
        -- number of bursts and drops their teardown cost on the floor.
        if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
        return
    end
    for icon in pairs(_textIcons) do
        if icon and icon._RenderCooldownText then
            icon:_RenderCooldownText()
        end
    end
    if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
end

function IconGrid:_RegisterTextIcon(icon)
    if not icon then return end
    -- Idempotent — re-registering an already-active icon is a no-op.
    if _textIcons[icon] then return end
    _textIcons[icon] = true
    -- Lazy-start the ticker on the first registered icon.
    if not _textTicker and _G.C_Timer and _G.C_Timer.NewTicker then
        _textTicker = _G.C_Timer.NewTicker(0.1, _tickAllTextIcons)
    end
end

--- Cancel the shared ticker and forget every icon registered on it.
---
--- The stand-down's half of the pair (slash-commands-§7, modules/IconGrid.lua's
--- Suspend). The lazy self-cancel below is fine while the addon is running — the
--- ticker notices the empty set on its next fire — but "on its next fire" is one
--- more wake-up than a stood-down addon is allowed, and the set does not empty
--- itself on the way down: Suspend hides the grids, it does not release the
--- icons. So this cancels eagerly and clears the set. The ticker re-arms on the
--- first StartCooldownText after the addon stands back up, which is the same
--- lazy start a fresh login takes.
function IconGrid:_StopTextTicker()
    if _textTicker and _textTicker.Cancel then _textTicker:Cancel() end
    _textTicker = nil
    for icon in pairs(_textIcons) do _textIcons[icon] = nil end
end

function IconGrid:_UnregisterTextIcon(icon)
    if not icon then return end
    if not _textIcons[icon] then return end
    _textIcons[icon] = nil
    -- The ticker itself notices the empty set on its next fire and
    -- self-cancels — see _tickAllTextIcons above. We could cancel
    -- eagerly here too, but lazy cancel keeps the deregister path
    -- O(1) and avoids double-free races if Cancel is non-idempotent
    -- on a given Blizzard build.
end
