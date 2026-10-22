local _, NS = ...

-- core/GlowSetup.lua — wires the addon into LibKa0s-Glow-1.0 (library-stack-§7, LibKa0s#56).
--
-- The driver maps a style and its named knobs onto LibCustomGlow-1.0's positional _Start
-- arguments, and it resolves LibCustomGlow at every call. modules/IconGrid_Render.lua's
-- StartGlow / StopGlow are its only callers: they keep the triggers, the knob ranges and clamp,
-- and the unchanged-repaint gate, which are this addon's policy rather than facts about LCG.
--
-- A DEGRADED INSTALL (the major absent) gets no glow, the same outcome as an absent
-- LibCustomGlow-1.0: Start answers false, so StartGlow records no state, and Stop does nothing.
-- Never a local copy of the style mapping (anti-pattern #47) — tests/test_icongrid_glow_knobs.lua
-- fails if an authored file calls a LibCustomGlow _Start or _Stop itself.

local G = LibStub and LibStub("LibKa0s-Glow-1.0", true)

NS.GlowLib = G or {
    Start = function() return false end,
    Stop = function() end,
}
