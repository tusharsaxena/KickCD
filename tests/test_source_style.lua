-- tests/test_source_style.lua — how this addon SPELLS the WoW globals it reads.
--
-- The rule is this repo's own, in docs/common-tasks.md § "Global lookup form": a symbol
-- on the standing `_G.` list is written `_G.X` at every read, because the prefix is what
-- tells a reader "this might not exist" and what makes a read that bypasses
-- core/Compat.lua visible while skimming. Everything else — `CreateFrame`, `Enum`,
-- `Mixin`, `CreateColor`, `UnitClass`, `UnitRace`, `Settings`, `GameTooltip`, `LibStub`,
-- `debugprofilestop` — is a trusted baseline the doc says to write BARE.
--
-- **This gate measures the standing list and nothing else, and that is a deliberate
-- narrowing of the doc's rule.** The doc's other half — "guarded somewhere → `_G.X`
-- everywhere in that module" — is a real instruction for new code but is not an
-- invariant this tree satisfies: `LibStub`, `Settings`, `GameTooltip`, `Enum`,
-- `DEFAULT_CHAT_FRAME`, `C_CooldownViewer` and `RAID_CLASS_COLORS` are all guarded
-- (`X and X(...)`) and all bare, at about seventy sites. A gate over that half would be
-- red the moment it was written, and its only green state is the blanket `_G.` sweep
-- 03_SPEC.md § C31 names as a non-goal. So the guard half stays advisory, the standing
-- list is what is measured, and the doc says which is which.
--
-- This is a SOURCE SCAN, and here that is forced rather than chosen. tests/run.lua:83-97
-- publishes the per-instance mock table AS `mocks._G`, precisely so that `_G.X` and a
-- bare `X` resolve through the same table — the two spellings are behaviorally
-- identical under the harness, and in the client too. No input a case can pass
-- distinguishes them. The rule's whole value is legibility, so the defect is invisible
-- to execution, which is how the violations this now guards sat under 845 green cases
-- until the 2026-09-07 review read the files (KICKCD-R-11, KICKCD-R-12).
local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue

-- The standing `_G.` list, transcribed from docs/common-tasks.md § "Global lookup form".
-- The doc writes two entries as prose families — "every legacy `GetSpell*` / `IsSpell*` /
-- `IsPlayerSpell` / `IsUsableSpell`", and "the cast-event API surface" — expanded here to
-- the names this addon actually reads, because a gate cannot match a family. Keep the two
-- in step: a name added to the doc's list belongs here, and a name added here belongs
-- there.
local BUCKET = {
    "C_Spell", "C_Timer", "C_CurveUtil", "issecretvalue",
    "InCombatLockdown", "IsLoggedIn",
    "UnitCastingInfo", "UnitChannelInfo", "UnitCastingDuration", "UnitChannelDuration",
    "UnitExists", "UnitCanAttack", "UnitName", "UnitIsDead",
    "GameFontNormal", "STANDARD_TEXT_FONT",
    "GetSpellInfo", "GetSpellCooldown", "GetSpellTexture", "GetSpellCharges",
    "IsSpellKnown", "IsSpellKnownOrOverridesKnown", "IsPlayerSpell", "IsUsableSpell",
    "print",
}

--- Everything a Lua reader would not treat as code: comments, and the contents of string
--- literals. Crude on purpose — it only has to be good enough that an identifier
--- surviving into the result is one Lua would resolve, and the failure mode of
--- over-stripping is a missed offender, never a false accusation.
local function codeOnly(line)
    line = line:gsub("%-%-.*$", "")
    line = line:gsub("%[=*%[.-%]=*%]", '""')
    line = line:gsub('\\"', "")
    return (line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"))
end

--- The addon's own files, TOC order, `libs/` dropped. The vendored Ace3 and LibKa0s
--- payloads are upstream code with their own repositories and their own conventions; a
--- read rewritten inside one would be undone by the next re-vendor.
local function ownFiles()
    local out = {}
    for _, rel in ipairs(T.tocFiles) do
        if not rel:match("^libs[/\\]") then out[#out + 1] = rel end
    end
    return out
end

--- `rel`'s lines, comments and strings already stripped.
local function codeLines(rel)
    local fh = io.open(T.root .. "/" .. rel, "r")
    assertTrue(fh ~= nil, "the TOC names a file that does not exist: " .. rel)
    local out = {}
    for line in fh:lines() do out[#out + 1] = codeOnly(line) end
    fh:close()
    return out
end

test("a WoW global on the standing _G. list is never read bare", function()
    local bucketed = {}
    for _, name in ipairs(BUCKET) do bucketed[name] = true end

    local offenders = {}
    for _, rel in ipairs(ownFiles()) do
        for n, code in ipairs(codeLines(rel)) do
            local reported = {}
            for at, name in code:gmatch("()([%a_][%w_]*)") do
                local before = code:sub(at - 1, at - 1)
                -- A field read (`NS.Util.print`, `f:UnitName`) is not a global read, and
                -- neither is a key in a table constructor — `print = function(line)`, the
                -- shape core/PerfSetup.lua and settings/Slash.lua use to hand a sink to
                -- the library. `==` IS a read, so it is excluded from the key test.
                local isField = (before == "." or before == ":")
                local isKey = (code:sub(at + #name):match("^%s*(=?=?)") == "=")
                if bucketed[name] and not isField and not isKey and not reported[name] then
                    reported[name] = true
                    offenders[#offenders + 1] = rel .. ":" .. n .. " (" .. name .. ")"
                end
            end
        end
    end

    assertTrue(#offenders == 0,
        "WoW global read without its _G. prefix (common-tasks: global lookup form) at: "
        .. table.concat(offenders, ", "))
end)
