local addonName, NS = ...
NS.Util = NS.Util or {}
local Util = NS.Util

-- core/CoreSetup.lua — wires the addon into LibKa0s-Core-1.0.
--
-- The secret-safe stringifier and the prefixed chat printer are identical in
-- every Ka0s addon and wrong in slightly different ways in several of them, so
-- they now live in libs/LibKa0s/Core.lua. What stays here is only the part that
-- is ours: which tag the lines carry, and what happens when the library is not
-- installed.
--
-- WHAT THIS REPLACED, and why it was worth replacing. core/Util.lua's printer
-- ran `tostring(v)` over its arguments and handed the result to `table.concat`
-- with NO secret guard at all. A 12.0 combat-protected value survives tostring
-- AND the `..` operator and raises only inside table.concat, so any Unit*-derived
-- value reaching a chat line raised on its way out — and when that happened on a
-- repeating ticker it killed the ticker, freezing the display until /reload.
-- Three correct guards already existed elsewhere in this addon (core/Compat.lua,
-- modules/DebugLog.lua, modules/Cooldowns.lua); the shared printer was the one
-- place that had none.
--
-- TOC POSITION. Two constraints bind, and only two:
--   * after core/Constants.lua, which defines NS.PREFIX. Belt and braces: the
--     prefix is passed as the FUNCTION form anyway, so it is re-read on every
--     call and a later change to NS.PREFIX is never frozen out.
--   * after core/Util.lua, whose `NS.Util = Util` assignment would otherwise
--     replace the table this file publishes into. (`NS.Util or {}` above makes
--     the reverse order survivable, but the TOC states the real order.)
-- Nothing downstream constrains it: unlike the other addons in the collection,
-- NO file in KickCD takes the printer as a load-time upvalue. Every one of the
-- ~20 call sites resolves it at call time as `NS.Util and NS.Util.print`, so the
-- swap cannot silently no-op.
--
-- PUBLISHED AS NS.Util.print, NEVER NS.Print. core/KickCD.lua embeds
-- AceConsole-3.0 into NS via AceAddon:NewAddon, which stamps AceConsole's own
-- `:Print` onto the namespace. Publishing the printer at NS.Print would put it
-- directly in that mixin's path (anti-patterns #36): every call would render
-- `|cff33ff99<msg>|r:` — green, trailing colon, no cyan tag — with no error and
-- nothing to say so. Keeping the key at NS.Util.print sidesteps the collision
-- entirely, which is why this addon has no reclaim line and does not need one.

-- The ONE cause clause, shared by every seam that has to explain the same
-- absence: this file, core/DebugLogSetup.lua, core/PerfSetup.lua,
-- settings/Slash.lua and settings/OptionsSetup.lua. Each appends its own
-- "so <what> is unavailable" and its own terminal punctuation, so a degraded
-- install says the same thing about WHY five times and a different thing about
-- WHAT each time.
--
-- Converging on this wording — rather than KickCD's five separate sentences —
-- is the user's decision (adoption 2026-08-01 §8), taken so a player with a
-- broken install reads the same sentence whichever Ka0s addon they have.
-- AbsorbTracker established the shape in its PLAN-04; ConsumableMaster follows
-- it. Keep the phrasing byte-identical across the collection apart from the
-- addon name.
--
-- Set OUTSIDE the branch below because the seams that read it are reached on
-- both paths — a half-vendored libs/LibKa0s can have Core.lua present and
-- DebugLog.lua missing — and set HERE because core/CoreSetup.lua is the first
-- of the five the TOC loads (KickCD.toc:43, ahead of 44/49/66/67).
NS.LIBKA0S_MISSING = "The LibKa0s library is missing from this installation of KickCD " ..
    "(expected in libs/LibKa0s)"

local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)

if not lib then
    -- A missing vendored lib must degrade, not error at load. Silence is not an
    -- option the way it is for a diagnostics harness: ~20 call sites across
    -- core/, modules/ and settings/ print through this seam, and a nil printer
    -- would take `/kcd` and the schema validator's error reporting with it.
    --
    -- So the fallbacks WORK — they are the pre-library implementations, kept
    -- short — and the honest "it is not installed" line is said ONCE, on the
    -- first line the addon prints, rather than stapled to every one of them.
    --
    -- The guard is reproduced here even though the stub "must not re-implement
    -- the library's rendering", because a concat probe is not rendering: it is
    -- the difference between a chat line and a Lua error on a repeating ticker.
    -- What is deliberately NOT copied is any formatter — no row shape, no
    -- key/value coloring, no console line format.
    local function probeConcat(v) return table.concat({ v }) end

    function NS.IsConcatSafe(v)
        return (pcall(probeConcat, v))
    end

    function NS.SafeToString(v)
        if v == nil then return "nil" end
        if type(v) == "boolean" then return tostring(v) end
        if NS.IsConcatSafe(v) then return tostring(v) end
        return "<secret>"
    end

    -- The degraded branch owes the caller the same NAME the live half publishes,
    -- because tests/test_surface_parity.lua is right that a member which exists on
    -- one path and not the other is a nil-call waiting for a half-vendored install.
    -- nil is the honest answer: the art is inside the payload that is missing, and
    -- every caller already treats a nil close button as "do without one".
    function NS.MakeCloseButton() return nil end

    local announced = false
    function Util.print(...)
        if not DEFAULT_CHAT_FRAME then return end
        if not announced then
            announced = true
            DEFAULT_CHAT_FRAME:AddMessage(NS.SafeToString(NS.PREFIX) .. " " ..
                NS.LIBKA0S_MISSING .. "; running on reduced built-in fallbacks.")
        end
        local parts = { NS.SafeToString(NS.PREFIX) }
        for i = 1, select("#", ...) do parts[i + 1] = NS.SafeToString((select(i, ...))) end
        DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
    end
    return
end

NS.IsConcatSafe = lib.IsConcatSafe
NS.SafeToString = lib.SafeToString

-- WRAPPED, TO SAY WHO IS ASKING — and the only seam here that is wrapped rather
-- than handed over. LibKa0s draws this collection's own `close` mark when it is
-- told which addon FOLDER to build a texture path from, and it cannot work that
-- out for itself: the library is vendored, so there is no one path to it and a
-- copy cannot know which folder it was copied into. `addonName` is that answer,
-- and this file has it as its first vararg.
--
-- ONE WRAPPER, so every close control this addon builds gets the same mark
-- instead of each call site remembering — today that is core/PerfSetup.lua's step
-- panel, and tomorrow it is whatever window is added next. A passthrough that
-- dropped the third argument would be green in every suite and wrong on screen:
-- the library falls back to a multiplication sign, which is what a degraded
-- install should get and not what a working one should (anti-patterns-§64).
NS.MakeCloseButton = function(parent, onClick)
    return lib.MakeCloseButton(parent, onClick, addonName)
end

-- The prefix is handed over as a FUNCTION rather than as the value of NS.PREFIX.
-- It reads the same here, where core/Constants.lua has already run — but the
-- printer is built once at load, and the function form is what keeps a later
-- change to NS.PREFIX (a profile-driven retag, a test swapping it) from being
-- frozen out. `sep` is left at its default single space: NS.PREFIX is
-- "|cff00ffff[KCD]|r" with no trailing space of its own.
local printer = lib:New({
    prefix = function() return NS.PREFIX end,
})

Util.print = printer.Print
