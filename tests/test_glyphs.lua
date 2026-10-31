-- tests/test_glyphs.lua — the display-glyph guard over this addon's own Lua (LibKa0s v1.82.0, kit
-- revision 45's tests/_kit/glyphs.lua; KC-04 of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, ruling D-19).
--
-- Ten skins draw this addon's text in a dozen faces, and a character one of them lacks is a box in
-- that skin only. So every string literal in a tracked .lua file outside libs/ and tests/ carries
-- only characters every shipped face draws (the kit's safe set, read from their cmaps). A string
-- drawn in the mono role carries a `glyph: mono` marker on its line, and one that is never drawn
-- carries `glyph: data`; the debug console's lines are skipped by the kit (they draw in mono too).

local T = _G.KICKCD_TEST
local test = T.test

test("glyphs: display strings use only characters every shipped skin face draws", function()
  -- red under: a character outside the kit's safe set in a string the addon paints in a skin face.
  T.assertDisplayGlyphs{ label = "KickCD" }
end)
