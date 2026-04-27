-- modules/TestMode.lua — KickCD v0.1
-- See docs/TECHNICAL_DESIGN.md §3.8
--
-- Synthesizes a 5-second cast loop on the same internal-message bus the
-- real Tracker uses, so the Castbar + IconGrid render exactly as they
-- would in combat. Used for WYSIWYG editing of layout / colors / fonts
-- without needing a live target.
--
-- Message contract (closed list):
--   FIRES: KickCD_TEST_MODE                { enabled = bool }
--          KickCD_TARGET_CAST_START        { spellID, name, texture, startMS, endMS, isChannel, notInterruptible }
--          KickCD_TARGET_CAST_END          { reason }
--   LISTENS: nothing through messages — auto-disable hook is on the WoW
--            event PLAYER_REGEN_DISABLED (FR-9.2).

local KickCD   = LibStub("AceAddon-3.0"):GetAddon("KickCD")
local TestMode = KickCD:NewModule("TestMode", "AceEvent-3.0")

-- ---------------------------------------------------------------------------
-- Fake spell
-- ---------------------------------------------------------------------------
--
-- Polymorph (118) is a stable, universally-recognized spell with a known
-- texture every client has cached. Using a real spellID means
-- C_Spell.GetSpellTexture / GetSpellInfo return real data even in the test
-- mode payload, which keeps the IconGrid + Castbar render logic identical
-- to a real cast — no special-casing for fake IDs.
local FAKE_SPELL_ID = 118
local CAST_DURATION = 5  -- seconds; FR-9.1 specifies a 5s loop

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function TestMode:OnEnable()
    self.enabled  = false
    self.ticker   = nil
    self.castOn   = false  -- alternates between START and END within a cycle

    -- FR-9.2: any time the player enters combat, force test mode off.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
end

function TestMode:OnDisable()
    self:Stop()
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------

--- Public toggle. Flips the internal flag, fires KickCD_TEST_MODE so the
--- Tracker can suppress real-target events, then either starts or stops the
--- 5-second simulation loop.
function TestMode:Toggle()
    if self.enabled then
        self:Stop()
    else
        self:Start()
    end
end

function TestMode:Start()
    if self.enabled then return end
    self.enabled = true

    -- Persist preference if a profile is available; settings UI also
    -- watches this flag.
    if KickCD.db and KickCD.db.profile then
        KickCD.db.profile.testMode = true
    end

    -- Tracker listens for this and switches to a no-op real-event mode so
    -- our synthesized START/END pairs aren't fought by genuine target events.
    KickCD:SendMessage("KickCD_TEST_MODE", { enabled = true })

    -- Fire the first START immediately so the user sees instant feedback
    -- after toggling, then drive the 5s rhythm with a repeating ticker.
    self:FireStart()

    -- After CAST_DURATION seconds we fire the matching END and immediately
    -- a new START — that's one "cycle". A repeating ticker every
    -- CAST_DURATION seconds keeps that cadence going.
    self.ticker = C_Timer.NewTicker(CAST_DURATION, function()
        if not self.enabled then return end
        if self.castOn then
            self:FireEnd("completed")
            self:FireStart()
        else
            -- Should not normally hit this branch — defensive: if we
            -- somehow get out of sync, kick a fresh START.
            self:FireStart()
        end
    end)
end

function TestMode:Stop()
    if not self.enabled and not self.ticker then return end
    self.enabled = false

    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    if self.castOn then
        self:FireEnd("stopped")
    end

    if KickCD.db and KickCD.db.profile then
        KickCD.db.profile.testMode = false
    end

    KickCD:SendMessage("KickCD_TEST_MODE", { enabled = false })
end

-- ---------------------------------------------------------------------------
-- Synthesized cast START / END
-- ---------------------------------------------------------------------------

--- Fire a START matching the KickCD_TARGET_CAST_START payload exactly
--- (TECHNICAL_DESIGN §1).
function TestMode:FireStart()
    local now = GetTime()
    local name, _, _, _, _, _, _ = KickCD.Compat.GetSpellInfo(FAKE_SPELL_ID)
    local texture = KickCD.Compat.GetSpellTexture(FAKE_SPELL_ID)

    self.castOn = true
    KickCD:SendMessage("KickCD_TARGET_CAST_START", {
        spellID          = FAKE_SPELL_ID,
        name             = name or "Test Cast",
        texture          = texture,
        startMS          = now * 1000,
        endMS            = (now + CAST_DURATION) * 1000,
        isChannel        = false,
        notInterruptible = false,
    })
end

function TestMode:FireEnd(reason)
    self.castOn = false
    KickCD:SendMessage("KickCD_TARGET_CAST_END", { reason = reason or "completed" })
end

-- ---------------------------------------------------------------------------
-- Combat auto-disable (FR-9.2)
-- ---------------------------------------------------------------------------

function TestMode:OnCombatStart()
    if self.enabled then
        local p = KickCD.Util and KickCD.Util.print or print
        p("Test mode auto-disabled (entering combat).")
        self:Toggle()
    end
end

-- ---------------------------------------------------------------------------
-- Slash-command bridge
-- ---------------------------------------------------------------------------
--
-- core/KickCD.lua's slash dispatcher already does:
--     if msg == "test" then self:ToggleTestMode() end
-- — so we wire that method onto the addon object here. Keeping the bridge
-- in this file means the slash command still works when test mode is the
-- ONLY consumer of the addon (early dev) without making core/KickCD.lua
-- aware of internal module names.

function KickCD:ToggleTestMode()
    local m = self:GetModule("TestMode", true)
    if m and m.Toggle then
        m:Toggle()
    else
        local p = self.Util and self.Util.print or print
        p("TestMode module not loaded")
    end
end
