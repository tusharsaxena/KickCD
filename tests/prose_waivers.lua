-- tests/prose_waivers.lua — what the kit's US-English gate MUST NOT correct here.
--
-- Read by `tests/_kit/test_prose.lua` (localization-5). Per FILE and per WORD, never per file
-- alone: a whole-file waiver hides every OTHER British spelling in a file this repo edits often,
-- which is how a gate acquires a blind spot the size of a module.
--
-- Every entry carries its reason. A waiver with no stated reason is indistinguishable from a
-- spelling nobody got round to fixing, and the next sweep either re-fixes it or widens it.

return {
    waived = {
        -- A FIELD NAME, not prose. tests/wow_mock.lua's C_Timer.NewTicker handle carries AceTimer's
        -- own spelling of the flag, which is what tests/_kit/mock_record.lua's live-timer survey
        -- reads off it. A US respelling would not be a correction -- it would be a handle the
        -- survey can never see as canceled, and a stand-down suite whose timer assertion is
        -- unfalsifiable is exactly what slash-commands-7 says a conformance suite must not be.
        ["tests/wow_mock.lua"] = { ["cancel" .. "led"] = true },
    },
}
