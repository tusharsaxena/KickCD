-- core/Constants.lua — KickCD v0.1
--
-- Named constants pulled out of individual modules so the value lives
-- in exactly one place and a reader doesn't have to puzzle out a magic
-- number's meaning at the use site. Loads early in the TOC (right after
-- core/Compat.lua) so every consumer can read KickCD.Const.* without
-- an existence check.
--
-- This file is intentionally tiny — it MUST stay free of any logic
-- (event registration, frame creation, etc.) so that loading it
-- early has no side effects. Add a constant here only if it is used
-- across modules or a comment at the use site has to explain it.

KickCD = KickCD or {}
local Const = {}
KickCD.Const = Const

-- ---------------------------------------------------------------------------
-- IconGrid: cooldown curve threshold
-- ---------------------------------------------------------------------------

-- Upper bound on the global cooldown duration. WoW's GCD is haste-modified
-- (typically 1.0–1.5s); 1.6s comfortably covers the unhasted case plus a
-- small fp epsilon. The alpha / tint / GCD-suppress curves in IconGrid
-- treat any remaining ≤ this value as "GCD only — show as ready" and
-- remaining > this value as "real CD — apply visual states." Sub-second
-- precision isn't critical because the transition is a step, not a
-- gradient.
Const.GCD_UPPER = 1.6

-- ---------------------------------------------------------------------------
-- Castbar: spell-name FontString insets
-- ---------------------------------------------------------------------------

-- Pixel inset used when the cast bar's name FontString is anchored
-- INSIDE the bar itself (the default position for HORIZONTAL bars).
-- Distance from the bar's edge to the text — visually the gap that
-- prevents the name from touching the bar border.
Const.CASTBAR_INSIDE_INSET  = 4

-- Pixel inset used when the cast bar's name FontString is anchored
-- OUTSIDE the bar (e.g. the "name floats above the bar" layout for
-- vertical orientations). Symmetric to CASTBAR_INSIDE_INSET so the
-- visual gap is identical regardless of which side the text lives on.
Const.CASTBAR_OUTSIDE_INSET = 4

-- ---------------------------------------------------------------------------
-- Settings panel: header layout
-- ---------------------------------------------------------------------------

-- Horizontal padding from the panel's left and right edges to its
-- header / divider / body content. Single value used for both edges so
-- the layout stays symmetric.
Const.PANEL_PADDING_X    = 16

-- Vertical inset of the title (and the per-panel "Defaults" button next
-- to it) from the top of the panel. Roughly half the height of the
-- GameFontNormalHuge title glyph so the header doesn't crowd the
-- panel's top edge.
Const.PANEL_HEADER_TOP    = 20

-- Distance from the top of the panel to the divider underneath the
-- title. Sits in lockstep with PANEL_HEADER_TOP so the title-to-divider
-- gap (and divider-to-body gap below it) stay unchanged when the header
-- block is repositioned vertically.
Const.PANEL_HEADER_HEIGHT = 54

-- Width of the per-panel "Defaults" button in the header. Wide enough
-- to comfortably fit "Restore Defaults" in en-US without truncation.
Const.PANEL_DEFAULTS_W    = 110
