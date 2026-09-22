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
        -- The session-3 perf-string check. `LibKa0s-Perf-1.0` minor 8 respelled five player-facing
        -- strings, and the step quotes the British forms in order to tell the reader that a double
        -- L in the client means the string did NOT come from the vendored payload. Correcting the
        -- quote deletes the check.
        ["docs/smoke-tests.md"] = { ["cancel" .. "led"] = true, ["label" .. "led"] = true },
        -- A FIELD NAME, not prose. tests/wow_mock.lua's C_Timer.NewTicker handle carries AceTimer's
        -- own spelling of the flag, which is what tests/_kit/mock_record.lua's live-timer survey
        -- reads off it. A US respelling would not be a correction -- it would be a handle the
        -- survey can never see as canceled, and a stand-down suite whose timer assertion is
        -- unfalsifiable is exactly what slash-commands-7 says a conformance suite must not be.
        ["tests/wow_mock.lua"] = { ["cancel" .. "led"] = true },
    },
}
