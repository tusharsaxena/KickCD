-- tests/test_launcher_skin_entry.lua — the launcher menu offers "Open skin selector" (SF-FIX, LibKa0s Launcher minor 6).
-- The library offers the entry only when the host passes openSkinPicker, so the descriptor must carry it
-- and it must reach this addon's picker verb.

local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue

test("launcher descriptor passes openSkinPicker, which runs the skin verb", function()
  local f = assert(io.open("core/LauncherSetup.lua", "r"))
  local src = f:read("*a")
  f:close()
  assertTrue(src:find("openSkinPicker%s*=%s*function") ~= nil, "openSkinPicker is passed")
  assertTrue(src:find("RunSkinVerb") ~= nil, "and it runs RunSkinVerb")
end)
