-- core/EnvSetup.lua
--
-- The LibKa0s-Env-1.0 seam: where this addon's own version comes from
-- (library-stack-§7).
--
-- ---------------------------------------------------------------------------
-- WHAT THIS REPLACED, AND WHY NOTHING WAS DELETED FROM core/Compat.lua
-- ---------------------------------------------------------------------------
--
-- Three copies of the same six-line C_AddOns ladder, INLINE at three call
-- sites: `addonVersion()` in core/KickCD.lua for the `/kcd version` verb and
-- the help header, the `version =` field of the perf descriptor in
-- core/PerfSetup.lua, and `addonVersion()` again in settings/Slash.lua. Not
-- one of them was in core/Compat.lua, and that is the point: the same reader
-- was written eleven times across nine addons, six copies in a Compat file and
-- five inlined where no audit of the shim files would ever have found them.
-- KickCD contributed three of the five.
--
-- So this file deletes nothing from core/Compat.lua — there was nothing there
-- to delete. Compat keeps every shim it has, because those are spell, cast and
-- specialization readers that behave like this addon needs them to; a manifest
-- read behaves like nobody's in particular, which is what made it the
-- library's business.
--
-- ---------------------------------------------------------------------------
-- WHY THE LIBRARY HAS TO BE TOLD OUR NAME
-- ---------------------------------------------------------------------------
--
-- Same reason core/MediaSetup.lua passes it: LibKa0s is VENDORED, so a copy
-- cannot know which addon folder it sits in. `addonName` is the FIRST VARARG
-- every TOC-loaded file gets — not the "[KCD]" frame prefix, not the `## Title`
-- ("Ka0s KickCD") and not a hand-typed literal. Only the first of those three
-- live strings is the folder name. A wrong one reads some other addon's
-- manifest, or none at all, and answers nil without raising a thing.
--
-- ---------------------------------------------------------------------------
-- WHY THE FALLBACK LADDER STOPS AT C_AddOns
-- ---------------------------------------------------------------------------
--
-- Because that is where all three deleted copies stopped. The reference seam
-- in the plan carries a third rung onto the bare `GetAddOnMetadata` global,
-- and this addon deliberately does not: that global is deprecated and
-- architecture-§1 forbids reading it, which core/KickCD.lua:116 said in a
-- comment before this file existed. A seam is not the place to acquire a
-- reach this addon has never had. The library's own reader still has that rung
-- and is welcome to it; what changes here is only what a LibKa0s-less install
-- falls back to, and that must be exactly what this addon did before.
--
-- ---------------------------------------------------------------------------
-- WHAT A DEGRADED INSTALL GETS
-- ---------------------------------------------------------------------------
--
-- Its own TOC, read the same way, and then NS.VERSION. That is why the
-- fallbacks are written out rather than left to answer nil: this is a seam,
-- not a feature. Nothing here resolves at load beyond the LibStub lookup, so
-- this file's TOC position is conventional rather than load-bearing — unlike
-- core/MediaSetup.lua immediately below it.

local addonName, NS = ...

local Env = LibStub and LibStub("LibKa0s-Env-1.0", true)

--- One field of this addon's TOC manifest, or nil.
---
--- NIL IS A REAL ANSWER, twice over: the library may be absent AND the client
--- may expose no reader at all. A field the TOC does not carry also answers nil
--- on a perfectly healthy client — `Interface` is one, because Blizzard does
--- not serve it here (see core/PerfSetup.lua). Callers that need a value supply
--- their own.
---
--- @param field string  a TOC key: "Version", "Title", "Notes", "Author", …
--- @return string|nil
function NS.Meta(field)
    if Env then return Env.GetAddOnMetadata(addonName, field) end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, field)
    end
    return nil
end

--- This addon's version string, preferring the TOC over the in-code stamp.
---
--- The manifest is preferred because the packager stamps it and it therefore
--- cannot drift from the packaged build (slash-commands-§3). The fallback stays
--- visible HERE rather than inside the library because which constant this
--- addon falls back to is genuinely its own business — and because a packaged
--- addon whose TOC can be read should never report the constant somebody forgot
--- to edit.
---
--- `NS.VERSION` — this addon spells it upper-case — is read at CALL time, not
--- captured as an upvalue: core/KickCD.lua publishes it and loads well after
--- this file. Both callers that resolve a version at FILE LOAD rather than on
--- demand (core/PerfSetup.lua's descriptor, which the library takes as a plain
--- string) sit below core/KickCD.lua in the TOC for exactly that reason, and
--- tests/test_perfsetup.lua pins that order.
---
--- Never nil: the answer goes straight into a chat banner and a capture record.
---
--- @return string
function NS.Version()
    if Env then return Env.Version(addonName, NS.VERSION) or "?" end
    local v = NS.Meta("Version")
    if type(v) == "string" and v ~= "" then return v end
    return NS.VERSION or "?"
end
