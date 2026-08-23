-- core/MediaSetup.lua
--
-- The LibKa0s-Media-1.0 seam: where this addon's shared art and its monospace
-- face come from.
--
-- ---------------------------------------------------------------------------
-- THE FONT USED TO BE OURS, AND THAT WAS THE PROBLEM
-- ---------------------------------------------------------------------------
--
-- This addon shipped its own copy of JetBrains Mono under `media/fonts/`, with
-- its own copy of the OFL license beside it, for one consumer: the debug
-- console's timestamps. Five sibling addons shipped the same two files. Two
-- copies of a face is two licenses to track and two provenance stories, and a
-- collection whose addons stop looking like one author's work the first time
-- one copy is replaced and the other is not.
--
-- Both the face and the 113-name icon catalog now ship inside LibKa0s
-- (`LibKa0s-Media-1.0`) and arrive with the vendored library payload under
-- `libs/LibKa0s/media/`. Nothing under `media/` in this repo is art any more —
-- `media/logos/` and `media/screenshots/` are this addon's own branding and
-- stay exactly where they are.
--
-- ---------------------------------------------------------------------------
-- WHY THE LIBRARY HAS TO BE TOLD OUR NAME
-- ---------------------------------------------------------------------------
--
-- A texture path is absolute from `Interface\AddOns\`, and LibKa0s is VENDORED:
-- every consumer has its own copy at its own path, and a copy cannot know which
-- addon folder it was copied into. So the library asks, and this file is where
-- the answer lives — `addonName`, the first vararg every TOC-loaded file gets.
-- It is the FOLDER name, which is a different question from the frame-name
-- prefix and from the `## Title`, even where this addon answers all three with
-- the same string.
--
-- ---------------------------------------------------------------------------
-- WHY THIS LOADS BEFORE core/Constants.lua
-- ---------------------------------------------------------------------------
--
-- `Const.FONT_MONO` is resolved from `NS.MediaFont` at FILE LOAD, so the seam
-- has to be published first. That makes this one of the few files in core/
-- whose TOC position is load-bearing rather than conventional, and the TOC line
-- says so.
--
-- ---------------------------------------------------------------------------
-- WHAT A DEGRADED INSTALL GETS
-- ---------------------------------------------------------------------------
--
-- No LibKa0s means no art and no face: they are inside the payload that is
-- missing. `NS.Icon` answers nil, which every caller must treat as "draw
-- something else" rather than routing around by building a path, and
-- `NS.MediaFont` answers nil, which core/Constants.lua turns into the client's
-- own STANDARD_TEXT_FONT. Neither is an error. Chrome degrades; the console
-- stays readable in a proportional face.

local addonName, NS = ...

local Media = LibStub and LibStub("LibKa0s-Media-1.0", true)

--- The texture path for one shipped icon, or nil.
---
--- NIL IS A REAL ANSWER, twice over: the library may be absent, and the name may
--- not be one the library ships. Both mean the same thing to a caller — draw
--- something else — and both are far better than the alternative this seam
--- exists to remove, which is a plausible path to a texture that does not load,
--- draws nothing, and raises nothing.
---
--- The answer is EXTENSIONLESS. The client appends the extension itself, and a
--- path carrying `.tga` is one of the two spellings that silently draw nothing.
---
--- @param name string  an entry of the library's `ICONS` catalog, e.g. "close"
--- @return string|nil
function NS.Icon(name)
    if not Media then return nil end
    return Media.Icon(addonName, name)
end

--- The path of one shipped font face, or nil when the library is absent.
---
--- @param name string  a key of the library's `FONTS`, e.g. "JetBrains Mono"
--- @return string|nil
function NS.MediaFont(name)
    if not Media then return nil end
    return Media.Font(addonName, name)
end

-- REGISTERED AT FILE LOAD, not at PLAYER_LOGIN. LibSharedMedia is vendored under
-- libs/ and has therefore already run by the time the TOC reaches core/, while
-- defaults/Profile.lua names fonts at load time too; deferring would open a
-- window in which a shipped default named a face LSM had never heard of.
--
-- This replaces the hand-rolled `LSM:Register("font", "JetBrains Mono", FONT)`
-- that used to sit at the top of core/DebugLogSetup.lua. That registration was
-- deliberately placed ABOVE the DebugLog guard, on the argument that exposing
-- the face to other addons is not the console's to skip just because the console
-- is missing (debug-logging-§2) — and it still is not the console's. It is the
-- MEDIA seam's, which is where it now lives, and it is guarded on the library
-- that actually owns the bytes: no Media, no face to register.
--
-- What registration buys over the bare path is the settings panel: a registered
-- face appears in the font dropdown beside every other font the player has, and
-- a profile then stores the NAME — portable across installs — rather than a path
-- naming one addon's folder. The library's call is idempotent and points every
-- consumer at one set of bytes under one key, which is what makes two Ka0s
-- addons registering "JetBrains Mono" agree rather than collide.
if Media then Media.RegisterLSM(addonName) end
