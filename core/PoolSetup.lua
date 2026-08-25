local _, NS = ...

-- core/PoolSetup.lua — wires the addon into LibKa0s-Pool-1.0 (library-stack-§7).
--
-- ── WHY THIS ADOPTION WAITED FOR MINOR 2 ─────────────────────────────────────────────────────
--
-- The library shipped at v1.15.0 and this addon could not take it. `active` here is a MAP KEYED BY
-- spellID, and the keying is load-bearing rather than incidental: it is the O(1) index the
-- `Ka0s_KickCD_SPELL_STATE` fan-out uses on every cooldown-state message, and it is what makes the
-- one-widget-per-spellID invariant enforceable at all. Minor 1's `active` was an array.
--
-- Porting anyway would have been worse than not porting. Minor 1's `ReleaseAll` walks
-- `for i = 1, #active`, which over a spellID-keyed table iterates NOTHING — so every icon would
-- have been hidden, none returned to the free list, and `Acquire` would have called the factory
-- forever. The grid still draws, the suite still passes, and the client gets heavier every time a
-- group composition changes. That is the exact leak the library exists to end, reached through its
-- own documented API. Minor 2 added the keyed members and made `ReleaseAll` raise on a keyed pool
-- instead of silently recycling nothing (LibKa0s#13).
--
-- ── WHAT THE ADOPTION DID AND DID NOT CHANGE ─────────────────────────────────────────────────
--
-- The free/active mechanics are the library's now. What stays here is everything that is about an
-- ICON rather than about a pool: the five stamped fields, the shared cooldown-text ticker
-- unregistration, the cooldown clear and the glow stop. That is most of the code either way, which
-- is why this is a small change with a large reason.
--
-- One behavior genuinely improved. `AcquireKeyed` on a spellID that is already live returns the
-- button already sitting there; the old code took a second button from the free list and
-- overwrote the map entry, orphaning the first — it could never reach the free list again. Nothing
-- in this addon acquires a live key today, so it was a latent leak rather than an active one.
--
-- ── WHAT A DEGRADED INSTALL GETS ─────────────────────────────────────────────────────────────
--
-- The same three members, locally, keyed. Making every call site branch on the library's presence
-- would mean an icon grid that leaks on a broken install and not on a whole one — invisible to
-- everyone except the player who has the broken one.

local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)

NS.Pool = Pool or {
    NewKeyed = function() return { free = {}, active = {} } end,

    AcquireKeyed = function(pool, key, factory)
        local live = pool.active[key]
        if live then return live end
        local o = table.remove(pool.free)
        if not o then o = factory() end
        pool.active[key] = o
        o:Show()
        return o
    end,

    ReleaseAllKeyed = function(pool, before)
        local active, free = pool.active, pool.free
        for key, o in pairs(active) do
            if before then before(o, key) end
            o:Hide()
            free[#free + 1] = o
            active[key] = nil
        end
    end,

    CountsKeyed = function(pool)
        local n = 0
        for _ in pairs(pool.active) do n = n + 1 end
        return #pool.free, n
    end,
}
