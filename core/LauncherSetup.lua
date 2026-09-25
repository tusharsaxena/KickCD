local addonName, NS = ...

-- core/LauncherSetup.lua — wires the addon into LibKa0s-Launcher-1.0
-- (launcher-§1), the minimap button and the broker plugin as ONE object
-- registered twice.
--
-- ── WHAT IS OURS AND WHAT IS THE LIBRARY'S ───────────────────────────────────
--
-- The library owns the LibDataBroker object, its `type = "launcher"`, the single
-- click implementation both surfaces dispatch into, the LibDBIcon registration
-- and the idempotence of it, the status tooltip (Launcher version 3) and, since
-- Launcher version 4, what both buttons do and the options menu itself. What is
-- genuinely ours is our FOLDER name, our logo, how the settings panel opens,
-- and the accessor-and-toggle pair for each state this addon really has.
-- Nothing else belongs here, and in particular no click handler and no menu: an
-- addon that builds a minimap button with its own handler and a broker object
-- with a second one has written the feature twice and they drift on the next
-- behavior change (anti-pattern #81).
--
-- ── THE TWO BUTTONS, AND THE HANDLERS THE MENU DRIVES ────────────────────────
--
-- launcher-§2 (standard v2.67.0): LEFT-click opens the settings panel, in either
-- state; RIGHT-click opens the client's context menu, one checkbox per pair the
-- descriptor passes, in the library's order. KickCD passes two pairs, so its
-- menu is `Enabled` and `Locked` (ADDONS.md's row): it has no test mode --
-- since v2.49.0 Lock frame alone is the preview switch, unlocking IS the
-- preview, which is why there is no Test mode row and no `/kcd test` verb
-- (options-ui-§15's exemption, recorded in settings/General.lua's header) --
-- and it has no primary window.
--
-- Each toggle is the SAME function the slash verb runs, so refusals, messages
-- and the write seam are the addon's: setEnabled is NS.SetMasterEnabled, the
-- handler `/kcd enable` and `/kcd disable` run (it is `/kcd set enabled`, the
-- Master-controls row's path); toggleLock is NS.ToggleLock, the handler
-- `/kcd toggle` runs, which lands on Store.Set("locked", v) like the `Lock
-- frame` checkbox. There is deliberately no `db.profile` write here and no copy
-- of either state. While the addon is disabled the LIBRARY grays Locked and
-- calls nothing for it (slash-commands-§7: a feature refuses while disabled),
-- which is the same answer the gated `/kcd toggle` gives; Enabled stays live.

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

    -- LEFT-click, always (Launcher version 4), and the right click's fallback
    -- where the client has no context-menu API.
    openSettings = function() NS:OpenSettings() end,

    -- ── THE OPTIONS MENU (launcher-§2, standard v2.67.0; Launcher version 4) ──
    --
    -- One pair per state this addon really has; an entry needs both halves.
    -- Each accessor is asked when the menu opens and on every tooltip show,
    -- never cached. Each toggle is resolved through NS at click time, so it is
    -- the live handler the slash verb runs, never a copy captured at file load.
    --
    -- Enabled: the Master-controls row's one reader, and the handler
    -- `/kcd enable` / `/kcd disable` run, handed the state to move TO.
    isEnabled  = function() return NS.MasterEnabled == nil or NS.MasterEnabled() end,
    setEnabled = function(on) if NS.SetMasterEnabled then NS.SetMasterEnabled(on) end end,
    -- Locked: the path the `Lock frame` row writes, and the handler `/kcd toggle`
    -- runs. Grayed by the library while the addon is disabled.
    isLocked   = function() return NS.db and NS.db.profile and NS.db.profile.locked and true or false end,
    toggleLock = function() if NS.ToggleLock then NS.ToggleLock() end end,
    -- No isTestMode / toggleTestMode (no test mode: unlocking IS the preview) and
    -- no isWindowShown / toggleWindow (no primary window). A pair for a state
    -- nobody can find would be a menu entry that lies.

    -- ── THE STATUS TOOLTIP (launcher-§1; Launcher version 3) ─────────────────
    --
    -- The LIBRARY draws it, enabled or disabled: title and version, Enabled
    -- (isEnabled above), Locked (isLocked above), the fixed click hints. No
    -- `onTooltipShow`: KickCD has no lines of its own, and a host title or click
    -- hint beside the library's is anti-pattern #89.
    --
    -- The TOC's `## Version`, through the one resolver `/kcd version` uses.
    version = function() return NS.Version and NS.Version() end,

    print = function(line) if NS.Util and NS.Util.print then NS.Util.print(line) end end,
    debug = function(tag, message) if NS.Debug then NS.Debug(tag, "%s", message) end end,
})
