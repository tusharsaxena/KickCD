-- tests/test_spelling.lua — authored English in this repository is US English.
--
-- localization-§5 makes this a rule rather than a taste call, and the reason is the locale seam: a
-- locale KEY IS the English source string (localization-§1/§2), so the day someone wraps "Bar
-- colour" in `NS.L` the British spelling is frozen into every translation file that ever derives
-- from it, and correcting it later orphans the key silently. The same section requires the rule to
-- be enforced mechanically, and this is that gate.
--
-- **Why it exists at all, rather than the sweep being enough.** `M4-13` ran the published list over
-- this tree and left it clean — `git archive 6eddbd4 | scan` returns exactly one line, the
-- deliberate quote waived below. Eight commits later `M4c-02` found fifteen, from five different
-- items: `M4-12` wrote "generalise" into the TOC, `M4-17` "behaviourally" here in the suite, `M4-18`
-- "screen centre" twice, `M4-20` "in favour of" and "behaviour" into the smoke doc, and `M4-21`
-- transplanted a locale lexer from PrettyChat and ConsumableMaster whose residue taxonomy is
-- literally named `SPLIT COLOUR`. Nothing in the repository could see any of it. A sweep is a
-- measurement of one afternoon; the defect is that authored British prose is invisible to
-- `luacheck`, which does not read English, and to every other suite here, which read behaviour. So
-- the sweep gets a gate or the sweep gets re-run forever.
--
-- **The lists are copied WHOLE from localization-§5 and nothing has been added.** That is the
-- section's own instruction and it is not decoration: a gate carrying a private subset is a gate
-- whose green means nothing, because no reader of the suite can tell which spellings it covers, and
-- a gate carrying a private ADDITION drifts away from the nine other repositories that share the
-- rule. A British form this repository meets and the list misses amends the section first and
-- arrives here on the next sync.
local T = _G.KICKCD_TEST
local test, assertTrue = T.test, T.assertTrue

-- localization-§5 · US English is the source dialect. Copy BOTH lists whole.
-- BRITISH: lowercase substrings, matched case-insensitively.
-- ALLOWED: correct US words that contain a BRITISH substring; removed as WHOLE WORDS first.

local BRITISH = {
    -- -our -> -or
    "colour", "behaviour", "favour", "honour", "neighbour", "armour", "flavour",
    "labour", "rumour", "humour", "endeavour", "rigour", "vigour", "saviour",
    -- -re -> -er
    "centre", "centring", "metre", "fibre", "calibre", "theatre", "manoeuvre",
    -- -ce -> -se
    "defence", "licence", "offence", "pretence", "practis",
    -- -ise / -isation -> -ize / -ization, and the -yse verbs
    "initialis", "normalis", "generalis", "specialis", "optimis", "customis",
    "serialis", "summaris", "utilis", "organis", "authoris", "prioritis",
    "alphabetis", "categoris", "sanitis", "visualis", "minimis", "maximis",
    "itemis", "randomis", "tokenis", "capitalis", "localis", "modularis",
    "standardis", "memois", "recognis", "analys", "paralys", "synthesis",
    "emphasis",
    -- a doubled consonant before a suffix, where US English keeps one
    "cancelled", "cancelling", "cancellable", "labelled", "labelling",
    "travelled", "travelling", "modelled", "modelling", "signalled",
    "signalling", "levelled", "levelling", "fuelled", "fuelling", "totalled",
    "totalling", "fulfil",
    -- -ogue -> -og
    "catalogue", "dialogue", "analogue",
    -- no family, just British
    "grey", "artefact", "whilst", "amongst", "learnt", "ageing", "enquir",
    "acknowledgement", "judgement", "sceptic", "mould", "sulphur", "programme",
}

local ALLOWED = {
    "analysis", "analyses", "analyst", "analysts",
    "organism", "organisms", "organist",
    "specialist", "specialists", "generalist", "generalists",
    "optimism", "optimist", "optimists", "optimistic", "optimistically",
    "paralysis", "paralyses", "synthesis", "syntheses", "emphasis", "emphases",
    "fulfill", "fulfills", "fulfilled", "fulfilling", "fulfillment",
    "programmer", "programmers", "programmed",
}

-- ---------------------------------------------------------------------------
-- What is scanned, and the four exclusions named one by one
-- ---------------------------------------------------------------------------
--
-- The candidate set is what git TRACKS, for the reason `tests/_kit/test_eol.lua` gives about its
-- own: a hand-typed file list is a list a new document quietly falls out of, and this repository
-- has thirty-one live Markdown files that no suite would otherwise reach. An untracked scratch file
-- is not this repository's authored text and is not scanned — `.superpowers/` is gitignored and
-- carries four British spellings that belong to a tool, not to us.
--
-- Extensions rather than a text sniff, because the set is small and saying it is cheaper than
-- guessing: Lua sources, Markdown prose, the TOC, and the two authored dotfiles. `.luacheckrc` is
-- named for the reason PanelMaster learned the hard way — it is neither `.lua` nor `.md`, which is
-- exactly how a British-spelled comment survived a sweep meant to remove it.
local SCANNED_EXT  = { lua = true, md = true, toc = true }
local SCANNED_FILE = { [".luacheckrc"] = true, [".pkgmeta"] = true }

-- localization-§5's four exclusions, each named directory by directory or file by file rather than
-- inferred from a pattern, so the list cannot quietly grow.
--
--   libs/, tests/_kit/   Vendored code. This repository MUST NOT edit either, and a word respelled
--                        inside one forks the copy — which tests/test_vendor_sync.lua then reports
--                        as drift, so the "fix" is red twice over.
--   the five docs/       Frozen dated bundles: audits, reviews, automated-tests, revendor and
--                        perf-analysis are the record of what was true on a past day and are not
--                        rewritten. `M4-13` already established this boundary; the audit's own
--                        count of 51 hits was inflated because it had folded these in.
--   this file            The section's fourth exclusion — a document whose subject is the rule and
--                        which therefore spells the forbidden forms in order to forbid them. The
--                        gate's own copy of the lists is named there explicitly.
--
-- There is no `locales/enGB.lua` here to exclude; if one is ever added it belongs on this list.
local EXCLUDED_DIR = {
    "libs/",
    "tests/_kit/",
    "docs/audits/",
    "docs/reviews/",
    "docs/automated-tests/",
    "docs/revendor/",
    "docs/perf-analysis/",
}
local EXCLUDED_FILE = { ["tests/test_spelling.lua"] = true }

-- One narrower waiver, per file and per WORD rather than per file alone, because the whole-file
-- form would have hidden three of the five regressions this gate was written to catch —
-- `docs/smoke-tests.md` is where two of them sat.
--
-- The waived line is the session-3 perf-string check. `LibKa0s-Perf-1.0` minor 8 respelled five
-- player-facing strings, and the step quotes `CANCELLED` and `unlabelled` in order to tell the
-- reader that a double L in the client means the string did NOT come from the vendored payload.
-- Correcting the quote deletes the check. `M4-13` made the same call and said so; this records it
-- somewhere a gate can read instead of somewhere only a commit message can.
local WAIVED = {
    ["docs/smoke-tests.md"] = { cancelled = true, labelled = true },
}

--- Every path git tracks, as repo-relative strings.
---
--- FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK, the bargain `tests/_kit/test_eol.lua` strikes: no
--- `io.popen`, no handle or no output is a red, because a gate that goes quiet when it is blind
--- reports success and that is worse than not existing.
local function trackedFiles()
    assertTrue(io.popen ~= nil,
        "spelling gate: io.popen is unavailable, so this gate cannot run and must not be reported "
        .. "as passing")
    -- `git -C` rather than a bare `git`, because tests/run.lua resolves the repo root from its own
    -- argv and may be invoked from anywhere; a bare call would scan whatever tree the CWD is in.
    local p = io.popen('git -C "' .. T.root .. '" ls-files 2>/dev/null')
    assertTrue(p ~= nil,
        "spelling gate: io.popen returned no handle, so this gate cannot run and must not be "
        .. "reported as passing")
    local out = {}
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    assertTrue(#out > 0,
        "spelling gate: `git ls-files` named no files, so this gate scanned nothing")
    return out
end

--- True when `rel` is authored text this repository is responsible for spelling.
local function isAuthored(rel)
    if EXCLUDED_FILE[rel] then return false end
    for _, dir in ipairs(EXCLUDED_DIR) do
        if rel:sub(1, #dir) == dir then return false end
    end
    local base = rel:match("([^/]+)$")
    if SCANNED_FILE[base] then return true end
    local ext = rel:match("%.([%w]+)$")
    return ext ~= nil and SCANNED_EXT[ext:lower()] == true
end

local function authoredFiles()
    local out = {}
    for _, rel in ipairs(trackedFiles()) do
        if isAuthored(rel) then out[#out + 1] = rel end
    end
    return out
end

local allowed = {}
for _, word in ipairs(ALLOWED) do allowed[word] = true end

--- The BRITISH entry `text` carries, or nil.
---
--- ALLOWED is removed as WHOLE WORDS FIRST, which is the half of the algorithm easiest to get
--- wrong. Delimit on non-letters, blank the matched tokens, then run the substrings over what is
--- left. Matching ALLOWED as a substring instead would swallow *analysed* inside the allowance for
--- *analyses* and hide the very defect the gate exists to find; skipping the removal entirely would
--- redden the build on *optimistic*, *specialist* and *organism*, and a gate that fails on correct
--- US English is one the next reader routes around rather than obeys.
---
--- Blanked to dots rather than deleted, so the tokens either side of an allowance cannot be joined
--- into a word neither of them is.
local function british(text, waived)
    local lower = text:lower()
    local scrubbed = lower:gsub("%a+", function(token)
        if allowed[token] then return string.rep(".", #token) end
    end)
    for _, word in ipairs(BRITISH) do
        if not (waived and waived[word]) and scrubbed:find(word, 1, true) then return word end
    end
    return nil
end

test("the spelling scan reaches this repository's authored text and skips the vendored and frozen", function()
    local seen = {}
    for _, rel in ipairs(authoredFiles()) do seen[rel] = true end

    -- One file per layer, so a broken `git ls-files` or a mistyped exclusion fails HERE, loudly,
    -- rather than downstream as a sweep that scanned nothing and called it green.
    for _, rel in ipairs({ "core/KickCD.lua", "locales/enUS.lua", "settings/Slash.lua",
                           "tests/test_locale.lua", "KickCD.toc", "README.md", "CLAUDE.md",
                           "docs/smoke-tests.md", "docs/test-cases.md", ".luacheckrc" }) do
        assertTrue(seen[rel], "the spelling scan does not cover " .. rel)
    end
    for _, rel in ipairs({ "libs/LibKa0s/LibKa0s.lua", "tests/_kit/framework.lua",
                           "tests/test_spelling.lua" }) do
        assertTrue(not seen[rel], "the spelling scan reaches " .. rel .. ", which it must not")
    end
    assertTrue(#authoredFiles() > 60,
        "the spelling scan covers suspiciously few files (" .. #authoredFiles() .. ")")
end)

test("the spelling matcher catches the published British forms and spares the US words ALLOWED names", function()
    -- Both directions pinned on literal strings rather than on the tree, because a matcher that has
    -- quietly stopped catching things looks exactly like a clean repository.
    for _, word in ipairs({ "colour", "coloured", "SPLIT COLOUR", "behaviourally", "generalise",
                            "licence", "screen centre", "in favour of", "cancelled", "unlabelled",
                            "grey", "judgement", "whilst", "dialogue", "analysed" }) do
        assertTrue(british(word) ~= nil, "the scan would not catch '" .. word .. "'")
    end
    -- Correct US English that contains a BRITISH substring. Every one of these reddens the build
    -- if the ALLOWED removal is dropped or is done as a substring match.
    for _, word in ipairs({ "analysis", "analyses", "analyst", "organism", "organist",
                            "specialist", "generalist", "optimistic", "paralysis", "synthesis",
                            "emphasis", "fulfillment", "programmer", "color", "gray", "center",
                            "behavior", "canceled", "labeled" }) do
        assertTrue(british(word) == nil,
            "the scan fails the build on US English '" .. word .. "' (matched '"
            .. tostring(british(word)) .. "')")
    end
    -- The waiver is per word, not per file: the same document is still scanned for everything else.
    assertTrue(british("unlabelled", WAIVED["docs/smoke-tests.md"]) == nil,
        "the smoke doc's waived quote must not redden the gate")
    assertTrue(british("behaviour", WAIVED["docs/smoke-tests.md"]) == "behaviour",
        "the smoke doc's waiver must not widen past the two words it names")
end)

test("authored English is US English", function()
    local offenders = {}
    for _, rel in ipairs(authoredFiles()) do
        local fh = io.open(T.root .. "/" .. rel, "r")
        assertTrue(fh ~= nil, "git tracks a file that cannot be read: " .. rel)
        local n = 0
        for line in fh:lines() do
            n = n + 1
            local word = british(line, WAIVED[rel])
            if word then
                offenders[#offenders + 1] = rel .. ":" .. n .. " (" .. word .. ")"
            end
        end
        fh:close()
    end
    assertTrue(#offenders == 0,
        "British spelling in authored text (localization-\194\1675) at: "
        .. table.concat(offenders, ", "))
end)
