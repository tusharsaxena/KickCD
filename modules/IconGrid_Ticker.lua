-- modules/IconGrid_Ticker.lua — the icons' cooldown ticker (peeled from IconGrid_Render.lua, #26;
-- given the whole time-varying render by KickCD#9)
--
-- EMIT = STATE CHANGED, TICKER = TIME PASSED. Cooldowns emits a
-- Ka0s_KickCD_SpellState only when a plain field moves, and Icon:Apply
-- (modules/IconGrid_Render.lua) does the state work on it: branch choice, swipe
-- arm, first paint, and registration here. Everything that varies with TIME
-- inside one cooldown is this file's: ONE shared C_Timer.NewTicker(0.1) visits
-- every registered icon, re-fetches its duration handle and re-runs the body
-- alpha / tint curves, the GCD-suppression alpha and the countdown text.
--
-- Why the ticker has to fetch the handle itself: C_Spell.GetSpellCooldownDuration
-- mints a fresh object per call and, in combat, every getter on it is secret, so
-- nothing in Lua can tell "the same cooldown" from "a new one". Before KickCD#9
-- Cooldowns re-emitted on every poll to carry a fresh handle to Icon:Apply;
-- docs/midnight-quirks.md has the history.
--
-- The swipe is NOT re-armed per tick: a fresh handle every 0.1s risks restarting
-- the animation, and the C side keeps animating the handle it was given. It is
-- re-armed only once it has stopped while the spell is still on cooldown — the
-- Cooldown frame's OnCooldownDone (wired in CreateIconWidget) or this ticker's
-- own isActive=false hide — which is the GCD -> real-cooldown handoff, the next
-- charge's recharge, or a recast inside SPELL_UPDATE_COOLDOWN's lag.
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
-- Published by modules/IconGrid_Render.lua, which loads first; resolved once
-- here because the tick path runs ten times a second.
local curvesFor                = IconGrid.CurvesFor
local evaluateByTotal          = IconGrid.EvaluateByTotal
local applyGcdSuppressionAlpha = IconGrid.ApplyGcdSuppressionAlpha
-- modules/Cooldowns.lua loads before modules/IconGrid.lua (KickCD.toc), so the
-- module object exists; its RechargeHandle is read at call time.
local Cooldowns = NS:GetModule("Cooldowns", true)

-- The icons on the ticker, each mapped to its render branch (1 = full spell
-- cooldown, 2 = charge recharge), and the single shared ticker handle.
local _cdIcons = {}
local _cdTicker

local function cfgOf(icon)
    return icon.cfg or NS.Units.Icons(icon.unit or "target")
end

--- Paint the time-varying half of an icon from duration handle `h`. The same
--- call paints Apply's first frame and every tick after it. Never touches the
--- swipe.
---
--- 12.0 secret values: nothing here holds a getter's result in a Lua local or
--- compares it. The curve results go straight into SetAlphaFromBoolean /
--- SetVertexColor, and :GetRemainingDuration() is passed as an ARGUMENT to
--- FontString:SetFormattedText, which formats it C-side. We cannot choose the
--- format conditionally (no comparison on remaining is legal), so it is a single
--- fixed "%.1f".
-- @param h      DurationObject  a fresh handle
-- @param isFull boolean         branch 1: the body alpha / tint curves apply too.
--   Branch 2 (charge recharge) leaves the body at its ready visuals, because the
--   spell IS castable.
function Icon:_PaintCooldown(h, isFull)
    if isFull then
        local curves = curvesFor(self.unit)
        if curves.alpha then
            -- SetAlphaFromBoolean accepts secret values for its alpha args;
            -- passing `true` as the condition selects the second arg.
            local alpha = evaluateByTotal(h, curves.alpha)
            if self.SetAlphaFromBoolean then
                self:SetAlphaFromBoolean(true, alpha, 0)
            else
                self:SetAlpha(alpha)
            end
        end
        if curves.tint then
            local color = evaluateByTotal(h, curves.tint)
            if color and color.GetRGB then
                self.icon:SetVertexColor(color:GetRGB())
            end
        end
    end
    applyGcdSuppressionAlpha(self, h)
    if cfgOf(self).showCooldownText then
        self.cooldownText:SetFormattedText("%.1f", h:GetRemainingDuration())
    end
end

--- Put this icon on the ticker on `branch`, painting its first frame. Called by
--- Icon:Apply's state work right after it arms the swipe, whatever
--- cfg.showCooldownText says: the text is one of three things a tick drives.
function Icon:StartCooldownTick(h, branch)
    self._swipeDone, self._cdEnded = nil, nil
    if cfgOf(self).showCooldownText then
        self.cooldownText:Show()
    else
        self.cooldownText:Hide()
    end
    self:_PaintCooldown(h, branch == 1)
    IconGrid:_RegisterCdIcon(self, branch)
end

function Icon:StopCooldownTick()
    IconGrid:_UnregisterCdIcon(self)
    self._swipeDone, self._cdEnded = nil, nil
    self.cooldownText:Hide()
end

--- Hide the swipe and the text the moment the plain isActive flips false.
--- SPELL_UPDATE_COOLDOWN can lag the real end by a few hundred ms, which left
--- the text stuck at "0.0" until Cooldowns caught up. The icon STAYS on the
--- ticker in this ended state until Apply takes it to idle, so a recast inside
--- that lag (Cooldowns sees active -> active and emits nothing) is still seen.
function Icon:_HideCooldown()
    self._cdEnded = true
    self.cooldownText:Hide()
    self.cooldown:Hide()
    self.cooldown:Clear()
end

--- The handle a tick paints from, fetched fresh. Branch 1 first reads the plain
--- `isActive` from Compat.GetSpellCooldown — the one taint-safe "has it ended?"
--- signal; the handle's own IsActive/HasExpired are secret in combat.
-- @return DurationObject|nil, boolean  the handle, and true when branch 1's
--   cooldown has ended
local function liveHandle(icon, branch)
    if branch == 1 then
        local _, _, _, _, isActive = NS.Compat.GetSpellCooldown(icon.spellID)
        if not isActive then return nil, true end
        return NS.Compat.GetSpellCooldownDuration(icon.spellID), false
    end
    return Cooldowns and Cooldowns.RechargeHandle(icon.spellID), false
end

--- One tick for one icon.
function Icon:_TickCooldown(branch)
    local h, ended = liveHandle(self, branch)
    if ended then
        if not self._cdEnded then self:_HideCooldown() end
        return
    end
    if not h then
        -- Branch 2 with no recharge handle: the spell lost its charges or went
        -- on its full cooldown, and Cooldowns' emit for that re-arms the icon.
        IconGrid:_UnregisterCdIcon(self)
        return
    end
    -- The swipe has stopped while the spell is still on cooldown. Re-arm it
    -- ONCE from the fresh handle; a running swipe is never touched.
    if self._cdEnded or self._swipeDone then
        self.cooldown:SetCooldownFromDurationObject(h)
        self.cooldown:Show()
        if self._cdEnded and cfgOf(self).showCooldownText then self.cooldownText:Show() end
        self._swipeDone, self._cdEnded = nil, nil
    end
    self:_PaintCooldown(h, branch == 1)
end

-- ---------------------------------------------------------------------------
-- Shared cooldown ticker
-- ---------------------------------------------------------------------------
--
-- One C_Timer.NewTicker(0.1) drives every icon on a cooldown. Icons register
-- from Icon:Apply's state work and deregister on idle (or ReleaseAll); the
-- ticker pauses (Cancel + nil) the moment the set goes empty so the addon costs
-- nothing while no cooldowns are active. Re-arms on the next register call.
-- Per-icon OnUpdate scripts were an earlier implementation, N frame-drivers for
-- N icons; the shared ticker collapses the fixed cost to one.
--
-- The Perf bucket keeps its shipped name, `cdText`, so in-game captures from
-- before and after KickCD#9 stay comparable; it now times the whole
-- time-varying render, not only the text.

local function _tickAllCdIcons()
    local __t0 = Perf.on and debugprofilestop()
    -- Snapshot the count and short-circuit if empty — guards against
    -- a race where the ticker fires after the last icon deregistered
    -- but before we got around to canceling the timer.
    if next(_cdIcons) == nil then
        if _cdTicker and _cdTicker.Cancel then
            _cdTicker:Cancel()
        end
        _cdTicker = nil
        -- Close the bracket on THIS exit too. The tick that finds the set
        -- empty still paid for the ticker callback and the `next` probe, and
        -- it is the exit taken on the very last tick of every cooldown burst
        -- — so leaving it unclosed under-counts `cdText.calls` by exactly the
        -- number of bursts and drops their teardown cost on the floor.
        if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
        return
    end
    -- Unregistering the visited icon inside the loop is safe: assigning nil to
    -- an existing key during `pairs` is allowed.
    for icon, branch in pairs(_cdIcons) do
        if icon._TickCooldown then
            icon:_TickCooldown(branch)
        end
    end
    if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
end

--- Register `icon` on the ticker on `branch` (1 = full cooldown, 2 = charge
--- recharge). Re-registering updates the branch.
function IconGrid:_RegisterCdIcon(icon, branch)
    if not icon then return end
    _cdIcons[icon] = branch or 1
    -- Lazy-start the ticker on the first registered icon.
    if not _cdTicker and _G.C_Timer and _G.C_Timer.NewTicker then
        _cdTicker = _G.C_Timer.NewTicker(0.1, _tickAllCdIcons)
    end
end

--- Cancel the shared ticker and forget every icon registered on it.
---
--- The stand-down's half of the pair (slash-commands-§7, modules/IconGrid.lua's
--- Suspend). The lazy self-cancel above is fine while the addon is running — the
--- ticker notices the empty set on its next fire — but "on its next fire" is one
--- more wake-up than a stood-down addon is allowed, and the set does not empty
--- itself on the way down: Suspend hides the grids, it does not release the
--- icons. So this cancels eagerly and clears the set. Each icon also forgets its
--- last state, so the first payload after the addon stands back up does the
--- state work (and re-registers) even when its plain fields did not move.
function IconGrid:_StopCdTicker()
    if _cdTicker and _cdTicker.Cancel then _cdTicker:Cancel() end
    _cdTicker = nil
    for icon in pairs(_cdIcons) do
        icon._lastState = nil
        _cdIcons[icon] = nil
    end
end

function IconGrid:_UnregisterCdIcon(icon)
    if not icon then return end
    if not _cdIcons[icon] then return end
    _cdIcons[icon] = nil
    -- The ticker itself notices the empty set on its next fire and
    -- self-cancels — see _tickAllCdIcons above. We could cancel
    -- eagerly here too, but lazy cancel keeps the deregister path
    -- O(1) and avoids double-free races if Cancel is non-idempotent
    -- on a given Blizzard build.
end
