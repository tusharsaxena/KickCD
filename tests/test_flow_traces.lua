-- tests/test_flow_traces.lua — debug-logging-§8 flow traces reachable headlessly
local T = _G.KICKCD_TEST
local test, assertTrue, assertEqual = T.test, T.assertTrue, T.assertEqual

test("OnProfileChanged logs a [Profile] line", function()
    local inst = T.load(true, true)
    local NS = inst.NS
    local Database = NS.Database
    inst.mocks.__flushTimers()
    NS.State.debug = true
    NS.DebugLog:Clear()
    Database:OnProfileChanged(nil, NS.db, "Raider")
    -- FindLine (not LastLine): OnProfileChanged's own SendMessage synchronously
    -- fans out to downstream subscribers (e.g. Cooldowns:Rebuild), which may
    -- log their own line after ours. We only assert OUR trace was emitted.
    assertTrue(NS.DebugLog:FindLine("[Profile] switched to 'Raider'"),
        "profile switch logs a [Profile] line naming the key")
    NS.State.debug = false   -- leave the shared/fresh instance clean
end)

-- ---------------------------------------------------------------------------
-- DL-KC-02: the debug-logging-§8 diagnosis lines and the §9 quiet steady state
-- ---------------------------------------------------------------------------
--
-- Each case below pins one line a support read of a pasted log depends on, or
-- pins that a repeating path stays SILENT when nothing it reports changed. The
-- quiet cases count the console's buffer across N passes: the console's `(xN)`
-- folding does not satisfy §9, so a folded repeat still has to fail them.

--- A fresh enabled instance with logging on and an empty console.
local function listening()
    local inst = T.load(true, true)
    local NS = inst.NS
    inst.mocks.__flushTimers()
    NS.DebugLog:SetEnabled(true)
    NS.DebugLog:Clear()
    return inst, NS
end

--- How many buffered lines contain `needle`, repeats included.
local function count(NS, needle)
    local n = 0
    for _, line in ipairs(NS.DebugLog.buffer) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end

local function entry(spellID) return { spellID = spellID, category = "interrupt", enabled = true } end

test("BuildActiveList writes ONE list summary for an unchanged list, however often it rebuilds", function()
    -- §9 quiet steady state: SPELLS_CHANGED fires several times at login and every
    -- `spells` write rebuilds, so an unchanged list must not log again.
    -- red under: drop the `sig == inst.lastListSig` return in modules/IconGrid.lua's logActiveList
    local _, NS = listening()
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = { entry(1766), entry(47528) }
    local gi = IconGrid:GetInstance("target")
    for _ = 1, 6 do IconGrid:BuildActiveList(gi) end
    assertEqual(count(NS, "[IconGrid] [target] list HUNTER/"), 1, "one line for six identical rebuilds")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = { entry(1766) }
    IconGrid:BuildActiveList(gi)
    assertEqual(count(NS, "[IconGrid] [target] list HUNTER/"), 2, "a real change still logs")
    NS.DebugLog:SetEnabled(false)
end)

test("the list summary names the spells it could not draw and the duplicates it skipped", function()
    -- §8: the missing-icon answer. An unlearned choice-node sibling and a
    -- duplicated ID are both "the icon is not there"; the line says which.
    -- red under: drop the `trace.unknown` / `trace.dup` collection in seedList
    local inst, NS = listening()
    inst.mocks.IsPlayerSpell = function(id) return id ~= 47528 end
    inst.mocks.IsSpellKnown = function() return false end
    local IconGrid = NS:GetModule("IconGrid")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = { entry(1766), entry(47528), entry(1766) }
    IconGrid:BuildActiveList(IconGrid:GetInstance("target"))
    assertTrue(NS.DebugLog:FindLine("1 icon(s) (1766); 1 not castable (47528); 1 duplicate spellID(s) skipped (1766)"),
        "the one summary carries drawn, not-castable and duplicate IDs")
    NS.DebugLog:SetEnabled(false)
end)

test("a cast bar logs its outcome once per change, not once per cast", function()
    -- §9 quiet steady state on a per-cast path, and §8's no-op reason: a bar the
    -- visibility mode suppressed says so, once.
    -- red under: drop the `outcome == inst.lastOutcome` return in modules/Castbar.lua's logCastOutcome
    local _, NS = listening()
    local Castbar = NS:GetModule("Castbar")
    NS.db.profile.locked, NS.db.profile.visibility = true, "always"
    local inst = Castbar:GetInstance("target")
    local rec = function()
        return { name = "Bolt", texture = "t", spellID = 1, notInterruptible = false, isChannel = false,
            duration = { GetTotalDuration = function() return 3 end,
                         GetElapsedDuration = function() return 1 end,
                         GetRemainingDuration = function() return 2 end } }
    end
    for _ = 1, 5 do Castbar:Start(inst, rec()); Castbar:Stop(inst) end
    assertEqual(count(NS, "[Castbar] [target] cast shown"), 1, "five shown casts are one line")
    NS.db.profile.visibility = "in_combat"
    NS.State.inCombat = false
    for _ = 1, 5 do Castbar:Start(inst, rec()) end
    assertEqual(count(NS, "[Castbar] [target] cast suppressed: visibility in_combat"), 1,
        "the suppression is named once, with the mode that did it")
    local noDuration = rec(); noDuration.duration = nil
    Castbar:Start(inst, noDuration)
    assertTrue(NS.DebugLog:FindLine("[Castbar] [target] cast skipped: the client returned no duration object"))
    NS.DebugLog:SetEnabled(false)
end)

test("a per-unit enable and disable edge is one line from each module", function()
    -- §8 diagnosis: the addon's own enable transitions. ReconcileUnits acts only
    -- on a mismatch, so a settings write that changes nothing logs nothing.
    -- red under: drop the `unit enabled` / `unit disabled` lines from EnableUnit / DisableUnit
    local _, NS = listening()
    local IconGrid, Castbar = NS:GetModule("IconGrid"), NS:GetModule("Castbar")
    NS.db.profile.units.focus.enabled = false
    IconGrid:ReconcileUnits(); Castbar:ReconcileUnits()
    assertTrue(NS.DebugLog:FindLine("[IconGrid] [focus] unit disabled"))
    assertTrue(NS.DebugLog:FindLine("[Castbar] [focus] unit disabled"))
    IconGrid:ReconcileUnits(); Castbar:ReconcileUnits()
    assertEqual(count(NS, "[focus] unit disabled"), 2, "a reconcile with no mismatch writes nothing")
    NS.db.profile.units.focus.enabled = true
    IconGrid:ReconcileUnits(); Castbar:ReconcileUnits()
    assertTrue(NS.DebugLog:FindLine("[IconGrid] [focus] unit enabled"))
    assertTrue(NS.DebugLog:FindLine("[Castbar] [focus] unit enabled"))
    NS.DebugLog:SetEnabled(false)
end)

test("the stand-down and stand-up edges are logged, naming the hold", function()
    -- §8 diagnosis: a player who says "it stopped working" with the addon
    -- disabled is answered by this line and nothing else.
    -- red under: drop logEdge from core/LifecycleSetup.lua's standDown / standUp
    local _, NS = listening()
    NS.SetMasterEnabled(false)
    assertTrue(NS.DebugLog:FindLine("[State] stood down (holds: disabled)"))
    NS.SetMasterEnabled(true)
    assertTrue(NS.DebugLog:FindLine("[State] standing up"))
    NS.DebugLog:SetEnabled(false)
end)

test("a rebuild that watches nothing says why, once for a repeated reason", function()
    -- §8's no-op reason for an empty grid, change-gated per §9: a slider drag
    -- rebuilds about twenty times a second.
    -- red under: drop the `sig == self._lastRebuildSig` return in Cooldowns:_logRebuildSkip
    local _, NS = listening()
    local Cooldowns = NS:GetModule("Cooldowns")
    NS.db.profile.spells.HUNTER[NS.Const.SPEC.BEASTMASTERY] = nil
    for _ = 1, 5 do Cooldowns:Rebuild() end
    assertEqual(count(NS, "[Cooldowns] rebuild skipped: no stored spell list"), 1)
    NS.DebugLog:SetEnabled(false)
end)

test("Cooldowns:Refresh stays silent across passes that change nothing", function()
    -- §9 quiet steady state on the hottest path: SPELL_UPDATE_* fires many times
    -- a second in combat. Pinned rather than fixed: it already logs only material
    -- changes, and this keeps it that way.
    -- red under: log the `%d/%d changed` line when `logged == 0`
    local _, NS = listening()
    local Cooldowns = NS:GetModule("Cooldowns")
    Cooldowns:Rebuild()
    Cooldowns:Refresh()
    local before = NS.DebugLog:BufferSize()
    for _ = 1, 10 do Cooldowns:Refresh() end
    assertEqual(NS.DebugLog:BufferSize(), before, "ten unchanged polls added lines")
    NS.DebugLog:SetEnabled(false)
end)

test("a settings open refused in combat names the guard in the log", function()
    -- §8 diagnosis: refusals with the reason. Chat has the notice; the pasted
    -- log is what a report carries.
    -- red under: drop the `[Open] settings panel refused` line from NS:OpenSettings
    local _, NS = listening()
    NS.State.inCombat = true
    NS:OpenSettings()
    NS.State.inCombat = false
    assertTrue(NS.DebugLog:FindLine("[Open] settings panel refused: in combat"))
    NS.DebugLog:SetEnabled(false)
end)

test("the Cooldown Manager walk logs one build line, with the calls that raised", function()
    -- §8 diagnosis: a dependency's answer and the errors its pcalls caught, once
    -- per build; then the add it refuses names that gate.
    -- red under: drop logCmBuild from SpellInput.CooldownManagerSet, or the refusal line from Admissible
    local inst, NS = listening()
    local SI = NS.SpellInput
    SI.StandUp()
    inst.mocks.Enum = inst.mocks.Enum or {}
    inst.mocks.Enum.CooldownViewerCategory = { Essential = 0 }
    inst.mocks.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function() return { 1, 2, 3 } end,
        GetCooldownViewerCooldownInfo = function(id)
            if id == 3 then error("bad cooldown id", 0) end
            return { spellID = 100 + id }
        end,
    }
    SI.CooldownManagerSet(); SI.CooldownManagerSet()
    assertEqual(count(NS, "[Spells] cooldown-manager set built: 2 spell(s); 1 viewer call(s) raised"), 1,
        "the memo means one build line")
    -- red under: drop noteError from collectCategorySpells, or the %s clause from logCmBuild
    assertEqual(count(NS, "1 viewer call(s) raised: GetCooldownViewerCooldownInfo: bad cooldown id"), 1,
        "the build line names the site and the message of the caught error")
    local ok = SI.Admissible(999, "HUNTER", NS.Const.SPEC.BEASTMASTERY)
    assertTrue(ok == false, "999 is not in the set")
    assertTrue(NS.DebugLog:FindLine("[Spells] add 999 to HUNTER/"), "the refusal is logged")
    assertTrue(NS.DebugLog:FindLine("refused: not in the cooldown-manager set"))
    inst.mocks.C_CooldownViewer = nil
    NS.DebugLog:SetEnabled(false)
end)

test("a settings link whose click raises names the site and the error in the log", function()
    -- §8 diagnosis: an error caught by an owned pcall reaches the pasted log, not
    -- only the chat line the player saw.
    -- red under: drop the [Open] line from Helpers.LinkRow's OnClick in settings/Panel_Widgets.lua
    local inst, NS = listening()
    local H = NS.Settings.Helpers
    local AceGUI = inst.mocks.LibStub("AceGUI-3.0")
    local ctx = H.CreatePanel("KickCDLinkRaise", "general", { pageKey = "general" })
    ctx.scroll = AceGUI:Create("ScrollFrame")
    local w = H.LinkRow(ctx, "go", function() error("no such page", 0) end)
    assertTrue(w ~= nil, "the link row must draw")
    w:__fire("OnClick")
    assertEqual(count(NS, "[Open] settings link click raised: no such page"), 1,
        "the caught error is logged once, with its site")
    NS.DebugLog:SetEnabled(false)
end)

test("a refused spell-list write names its guard, once, from the writer or the verb", function()
    -- §8 diagnosis: a command refused or a write rejected names the guard. The
    -- writer's line is shared by the Spells page and `/kcd spells`; the verb logs
    -- only the guards it owns (parse, usage, no list, db not ready).
    -- red under: drop refused() from core/Database.lua's writers, or refuse() from core/KickCD.lua's spells verbs
    local _, NS = listening()
    local DB, BM = NS.Database, NS.Const.SPEC.BEASTMASTERY
    assertTrue(DB:AddSpell("HUNTER", BM, 424240) ~= nil, "seed a list to refuse against")
    assertTrue(DB:RemoveSpell("HUNTER", BM, 424242) == false)
    assertTrue(NS.DebugLog:FindLine("[Spells] remove 424242 in HUNTER/"), "the writer names the act")
    assertEqual(count(NS, "refused: not in the list"), 1, "and the guard, once")
    assertTrue(DB:MoveSpell("HUNTER", BM, 1, 1) == false)
    assertTrue(NS.DebugLog:FindLine("refused: same position"))
    assertTrue(DB:MoveSpell("HUNTER", BM, 1, 999) == false)
    assertTrue(NS.DebugLog:FindLine("refused: index out of range"))
    assertTrue(DB:AddSpell("WARLORD", BM, 1) == nil)
    assertTrue(NS.DebugLog:FindLine("refused: unknown class"))
    NS:OnSlashCommand("spells add Zzqxnotaspell")
    assertTrue(NS.DebugLog:FindLine("[Spells] /kcd spells add refused: Unknown spell: Zzqxnotaspell"),
        "the verb names the parse failure")
    NS:OnSlashCommand("spells category 424240 bogus")
    assertTrue(NS.DebugLog:FindLine("[Spells] /kcd spells category refused: unknown category 'bogus'"))
    NS:OnSlashCommand("spells frobnicate")
    assertTrue(NS.DebugLog:FindLine("[Spells] /kcd spells frobnicate refused: unknown subcommand"))
    local db = NS.db
    NS.db = nil
    NS:OnSlashCommand("lock")
    NS.db = db
    assertTrue(NS.DebugLog:FindLine("[Set] /kcd lock refused: db not ready"), "a top-level host verb names its guard too")
    NS:OnSlashCommand("reset spells")
    assertTrue(NS.DebugLog:FindLine("[Set] /kcd reset spells refused: a retired page word, redirected"))
    NS.DebugLog:SetEnabled(false)
end)

test("the [Init] line names an optional library that did not load", function()
    -- §8 diagnosis: a dependency missing, once, at enable. The launcher's own
    -- missing-library line lands at login with the flag off, so this clause is
    -- the only place a pasted log learns it.
    -- red under: drop missingClause() from core/DebugLogSetup.lua's initSummary
    local inst = T.load(true, true, function(mocks) mocks.__libs["LibCustomGlow-1.0"] = nil end)
    local NS = inst.NS
    NS.DebugLog:Clear()
    NS.DebugLog:SetEnabled(true)
    assertTrue(NS.DebugLog:FindLine(", missing LibCustomGlow-1.0"), "the missing glow library is named")
    NS.DebugLog:SetEnabled(false)
end)
