local addonName, NS = ...

-- core/LauncherSetup.lua — wires the addon into LibKa0s-Launcher-1.0
-- (launcher-§1), the minimap button and the broker plugin as ONE object
-- registered twice.
--
-- ── WHAT IS OURS AND WHAT IS THE LIBRARY'S ───────────────────────────────────
--
-- The library owns the LibDataBroker object, its `type = "launcher"`, the single
-- click implementation both surfaces dispatch into, the LibDBIcon registration
-- and the idempotence of it. What is genuinely ours is four answers: our FOLDER
-- name, our logo, what the left button does, and how the settings panel opens.
-- Nothing else belongs here, and in particular no second click handler: an addon
-- that builds a minimap button with its own handler and a broker object with a
-- second one has written the feature twice and they drift on the next behavior
-- change (anti-pattern #81).
--
-- ── THE RUNG, AND THE SEAM IT DRIVES ─────────────────────────────────────────
--
-- launcher-§2 is a three-rung rule, first match wins. KickCD has no primary
-- window, so rung (a) does not apply; it does have a PREVIEW SWITCH, and since
-- v2.49.0 that switch is Lock frame alone — unlocking IS the preview, which is
-- why this addon has no Test mode row and no `/kcd test` verb (options-ui-§15's
-- exemption, recorded in settings/General.lua's header). So the rung is (b) and
-- the left button toggles the lock.
--
-- It toggles it through NS.ToggleLock, which is the SAME seam `/kcd toggle`
-- runs and which lands on Helpers.SetAndRefresh("locked", v) — the addon's
-- single write seam (options-ui-§1). There is deliberately no `db.profile.locked`
-- write here and no copy of the state: the launcher, the `Lock frame` checkbox
-- and the three slash verbs are four callers of one writer.
--
-- RIGHT-click is the library's and always opens the settings panel, so it is not
-- passed and cannot be reassigned. That is what lets the left button spend
-- itself on the lock.
--
-- ── WHY `minimap` IS A FUNCTION ──────────────────────────────────────────────
--
-- `db.global.minimap` does not exist when this file loads: core/Database.lua
-- builds the AceDB instance from NS:OnInitialize, long after. A table captured
-- here would be a table AceDB later replaces, so LibDBIcon would keep writing
-- `minimapPos` into an orphan while the Master-controls row wrote the live one.
-- The library resolves the function at Register time instead, which is what
-- keeps both halves on one table (launcher-§3).
--
-- ── WHERE REGISTRATION HAPPENS ───────────────────────────────────────────────
--
-- NS:OnEnable, beside NS.CreateOptionsPanel, because Register reads
-- `db.global.minimap` and OnInitialize is what builds the db. Register is
-- idempotent, so a re-enable is harmless.
--
-- ── WHAT A DEGRADED INSTALL GETS ─────────────────────────────────────────────
--
-- Three shapes of missing, and only one of them is ours. No LibKa0s means the
-- stub below: every member answers, Register reports false, and the one
-- user-visible line says why once. No LibDataBroker-1.1 or no LibDBIcon-1.0 is
-- the LIBRARY's own degradation — it resolves both with LibStub(..., true) at
-- Register time and reports by name — so this file does not test for them and
-- must not, or the report would be written twice in two spellings.

local Launcher = LibStub and LibStub("LibKa0s-Launcher-1.0", true)

if not Launcher then
    -- Load-completing, like every other seam in core/: settings/Panel.lua's
    -- write seam calls NS.Launcher:SetShown on every `global.minimap.shown`
    -- write, and settings/General.lua's composed row reads IsShown, so a nil
    -- here would be a raise inside `/kcd set` rather than a missing button.
    local announced = false
    local MISSING = NS.LIBKA0S_MISSING .. ", so there is no minimap button."

    local function say()
        if announced then return end
        announced = true
        if NS.Util and NS.Util.print then NS.Util.print(MISSING) end
    end

    NS.Launcher = {
        Register     = function() say() return false end,
        IsRegistered = function() return false end,
        Object       = function() return nil end,
        -- Both still read and write the STORE, which is ours and is present:
        -- a player who hides the button on a broken install must still find the
        -- checkbox unticked after a reload.
        IsShown      = function()
            local t = NS.db and NS.db.global and NS.db.global.minimap
            return not (t and t.hide)
        end,
        SetShown     = function(_, shown)
            local t = NS.db and NS.db.global and NS.db.global.minimap
            if t then t.hide = not shown end
            return false
        end,
    }
    return
end

NS.Launcher = Launcher:New({
    -- THE FOLDER NAME, and it is not cosmetic: LibDBIcon keys the button's saved
    -- position by it, so a second spelling drops the angle the player dragged the
    -- button to and labels the broker plugin with the other name. `addonName` is
    -- the first vararg every TOC-loaded file gets, which is the only spelling
    -- that cannot drift from what the client loads.
    name  = addonName,
    -- THE BRAND NAME IN PLAIN TEXT, `Ka0s <Name>` (launcher-§1, standard
    -- v2.54.0). `label` is the string a broker display prints in its own row,
    -- and it prints it BESIDE THE OTHER TEN, so it is the single field that
    -- decides whether the collection reads as one collection in Titan Panel or
    -- as eleven unrelated addons that happen to be installed together. Across
    -- the eleven adoptions it came out three ways because nothing said what it
    -- was; this is the spelling that is now stated.
    --
    -- It is NOT the TOC's `## Title`, and the two must not be wired to each
    -- other even here, where they happen to read the same. A Title MAY carry
    -- color escapes and one in the collection does -- Ka0s Pretty Chat's is
    -- `Ka0s |cffff0000P|cffff9900r|cffffff00e|...` -- and handed to a display
    -- that draws the string raw that addon's row splatters across a list in
    -- which every other row is plain text. So: no escape sequence of any kind.
    --
    -- It is not the FOLDER name either. That is `name` above, which LibDBIcon
    -- keys the saved position by and which a player reads nowhere as prose:
    -- `KickCD` is an identifier, `Ka0s KickCD` is a name. Two fields, two jobs.
    label = "Ka0s KickCD",
    -- The same file KickCD.toc's `## IconTexture` names (launcher-§4). Not the
    -- landing page's logo, which is a larger asset drawn at 300x300
    -- (options-ui-§5), and never a Blizzard icon path or a file id
    -- (anti-pattern #82).
    icon  = "Interface\\AddOns\\" .. addonName .. "\\media\\logos\\kickcd.logo.128.tga",

    minimap = function() return NS.db and NS.db.global and NS.db.global.minimap end,

    openSettings = function() NS:OpenSettings() end,

    -- THE RUNG. Its presence is the whole declaration (launcher-§2): a rung-(c)
    -- addon passes nothing rather than passing openSettings, so a skipped rule
    -- cannot look like a choice.
    --
    -- REFUSED WHILE THE ADDON IS DISABLED (launcher-§2, slash-commands-§7). Rung
    -- (b) drives a preview switch and a preview switch is a FEATURE, so the left
    -- button prints the collection's one refusal line and does nothing else --
    -- and in particular does not write SavedVariables, which is what a minimap
    -- button with no disabled gate does every single time it is clicked. The line
    -- comes from the library through NS.Slash.PrintDisabledLine, never re-spelled
    -- here.
    --
    -- THE RUNG-(c) CARVE-OUT DOES NOT REACH THIS ADDON, and it is worth saying
    -- why rather than leaving a reader to wonder: a rung-(c) left click opens the
    -- settings panel, which §7 keeps standing, so refusing it would decline one
    -- button for doing exactly what the button beside it must keep doing. KickCD
    -- is rung (b) -- this click toggles the lock, not the panel -- so the refusal
    -- applies. RIGHT-click is the library's and opens the panel in either state,
    -- which is what keeps the panel one click away from a disabled addon.
    onClick = function()
        if NS.MasterEnabled and not NS.MasterEnabled() then
            if NS.Slash and NS.Slash.PrintDisabledLine then NS.Slash.PrintDisabledLine() end
            return
        end
        if NS.ToggleLock then NS.ToggleLock() end
    end,

    print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
    debug = function(tag, message) if NS.Debug then NS.Debug(tag, "%s", message) end end,
})
