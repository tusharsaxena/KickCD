-- tests/test_doc_structure.lua — docs/ARCHITECTURE.md's mandated shape, and the anchors into it.
--
-- WHAT IT PROVES. That this repository's architecture hub carries the two section names
-- `documentation-§3` names for it — `## Overview` and `## Module map` — and that every markdown
-- link in the repository that points INTO one of ARCHITECTURE.md's headings lands on a heading that
-- exists.
--
-- WHY IT EXISTS. KickCD spent this cycle as the only sibling of the nine whose hub used private
-- heading names: the overview material sat under "What it does" and the module table under
-- "Subsystems at a glance". Nothing was missing — it was all there, under names no reader arriving
-- from another repository would look for, and no reader could tell whether that was a deviation or
-- an oversight because the register carried no row either way. `M5-03` renamed them, and this is the
-- gate that stops the rename being undone by the next person who prefers their own wording.
--
-- The anchor half is the other side of the same rename. A heading rename silently orphans every
-- `](…#old-slug)` pointing at it: markdown does not raise on a dead fragment, GitHub scrolls to the
-- top of the page and the reader assumes they misread the link. So the rename and the anchor sweep
-- are one act, and a gate that checked only the names would leave the half that actually breaks
-- readers unguarded.
--
-- WHAT IT DOES NOT DO, DELIBERATELY. It does not check every anchor in the repository — only the
-- ones aimed at ARCHITECTURE.md, which is the file this item renames headings in. It does not
-- police heading ORDER or the presence of any other section: `documentation-§3` names sections, not
-- a sequence, and pinning the order would redden on every ordinary addition.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK. No `io.popen`, no git, no ARCHITECTURE.md are
-- each a failure, not a skip — the same bargain tests/_kit/test_eol.lua strikes.

local T = _G.KICKCD_TEST
local test, fail, assertTrue = T.test, T.fail, T.assertTrue
local assertEqual = T.assertEqual
local ROOT = T.root or "."

local ARCHITECTURE = "docs/ARCHITECTURE.md"

-- `documentation-§3`'s ten mandated hub sections, named rather than counted because a bare count
-- goes stale silently. Matched case-insensitively on every word but the first: the collection is
-- split between `## Module map` and `## Module Map`, and the section names a section, not a
-- capitalization. `## Overview` and `## Module map` are the two this repository did not have.
local MANDATED = {
    "Overview",
    "Module Map",
    "Settings Schema",
    "Message Bus",
    "Slash Commands",
    "Event Subscriptions",
    "Taint Notes",
    "Known Limitations",
    "Documentation map",
    "Documented deviations",
}

--- `## <Name>` as a case-insensitive whole-line pattern.
local function heading(name)
    return "^##%s+" .. name:gsub("%a", function(c)
        return "[" .. c:upper() .. c:lower() .. "]"
    end):gsub(" ", "%%s+") .. "%s*$"
end

--- A file's contents with line endings normalized, or a failure.
local function read(rel)
    local fh = io.open(ROOT .. "/" .. rel, "r")
    if not fh then fail("doc gate: " .. rel .. " could not be opened", 2) end
    local body = fh:read("*a") or ""
    fh:close()
    return (body:gsub("\r\n", "\n"))
end

--- GitHub's heading-fragment slug: lowercased, formatting and punctuation dropped, spaces hyphened.
local function slug(text)
    local s = text:lower():gsub("`", "")
    s = s:gsub("[^%w%s%-]", "")
    s = s:gsub("%s+", "-")
    return s
end

--- Every heading slug ARCHITECTURE.md offers, as a set.
local function architectureSlugs()
    local set = {}
    for line in (read(ARCHITECTURE) .. "\n"):gmatch("([^\n]*)\n") do
        local text = line:match("^#+%s+(.-)%s*$")
        if text then set[slug(text)] = true end
    end
    return set
end

--- Every markdown path git tracks, minus the vendored and frozen trees.
---
--- `git ls-files` rather than a directory walk: Lua 5.1 has no directory API, and the tracked set is
--- the right set anyway. `libs/` and `tests/_kit/` are vendored whole and byte-pinned by
--- tests/test_vendor_sync.lua, and the dated bundles under `docs/audits/`, `docs/reviews/`,
--- `docs/automated-tests/`, `docs/revendor/`, `docs/perf-analysis/` and `docs/superpowers/` are
--- frozen records of the tree as it stood on their stamp — a rename today must not rewrite them, so
--- a stale anchor inside one is history rather than a defect.
local function trackedMarkdown()
    if not io.popen then
        fail("doc gate: io.popen is unavailable, so this gate cannot run and must not be reported "
            .. "as passing", 2)
    end
    local p = io.popen("git ls-files '*.md' 2>/dev/null")
    if not p then
        fail("doc gate: io.popen returned no handle, so this gate cannot run and must not be "
            .. "reported as passing", 2)
    end
    local out = {}
    for path in p:lines() do
        local frozen = path:match("^libs/") or path:match("^tests/_kit/")
            or path:match("^docs/audits/") or path:match("^docs/reviews/")
            or path:match("^docs/automated%-tests/") or path:match("^docs/revendor/")
            or path:match("^docs/perf%-analysis/") or path:match("^docs/superpowers/")
        if not frozen then out[#out + 1] = path end
    end
    p:close()
    if #out == 0 then
        fail("doc gate: git tracks no markdown outside the vendored and frozen trees, which cannot "
            .. "be true here — treating a blind gate as a failure", 2)
    end
    return out
end

test("docs/ARCHITECTURE.md carries the section names documentation-§3 mandates", function()
    local body = read(ARCHITECTURE)
    local missing = {}
    for _, name in ipairs(MANDATED) do
        local pattern, found = heading(name), false
        for line in (body .. "\n"):gmatch("([^\n]*)\n") do
            if line:match(pattern) then found = true break end
        end
        if not found then missing[#missing + 1] = "## " .. name end
    end
    assertTrue(#missing == 0, ARCHITECTURE .. " is missing " .. table.concat(missing, ", ")
        .. " — these are the sections a reader arriving from a sibling addon looks for, and "
        .. "documentation-§3 names all ten rather than counting them")
end)

test("every anchor pointing into docs/ARCHITECTURE.md resolves to a heading", function()
    local slugs = architectureSlugs()
    local dead = {}
    for _, path in ipairs(trackedMarkdown()) do
        local body = read(path)
        -- `](…ARCHITECTURE.md#frag)` from anywhere, plus bare `](#frag)` inside the hub itself.
        for frag in body:gmatch("%]%([^%)%s]-ARCHITECTURE%.md#([^%)%s]+)%)") do
            if not slugs[frag] then dead[#dead + 1] = path .. " -> #" .. frag end
        end
        if path == ARCHITECTURE then
            for frag in body:gmatch("%]%(#([^%)%s]+)%)") do
                if not slugs[frag] then dead[#dead + 1] = path .. " -> #" .. frag end
            end
        end
    end
    assertTrue(#dead == 0, "anchors into " .. ARCHITECTURE .. " that land on no heading: "
        .. table.concat(dead, ", "))
end)

-- ── The deviation register's own citations resolve ─────────────────────────────

-- `audit-review-history`'s third MUST: an id a register row cites in **Why** has to resolve -- a
-- deviation id into `docs/audits/`, a finding id into `docs/reviews/`, an issue number onto this
-- repo. An id that resolves to nothing is worse than no citation at all, because it reads as
-- evidence and leads to none, and it survives every re-read by a maintainer who knows the shape of
-- an id and never goes looking for what it names.
--
-- The check is deliberately NOT "the string appears somewhere under `docs/audits/`". A bundle that
-- REPORTS a dead citation quotes the dead id while doing so, so a substring search goes green on
-- the very defect it was written for -- `testing-§12`'s failure mode, sitting inside the gate for
-- it. What counts is the id being ASSIGNED: standing at the head of a markdown table cell, a
-- heading or a bullet, which is where every bundle in this repo puts a row's own id, and where
-- prose that merely mentions one never puts it.
--
-- Scope is the **deviation** id -- this repo's own audit-bundle prefix, which is what
-- `documentation-§3` puts in a row's Why cell and what a bundle under `docs/audits/` assigns.

local DEVIATION_ID = { "%f[%w]KCD%-[%u%-]*%d+", "%f[%w]KICKCD%-[%u%-]*%d+" }

--- Every `.md` under a dated bundle directory.
local function bundleFiles()
        if not io.popen then
        fail("register gate: io.popen is unavailable, so this gate cannot run and must not be "
            .. "reported as a pass")
        end
        local p = io.popen("ls -1 " .. ROOT .. "/docs/audits/*/*.md 2>/dev/null")
        if not p then fail("register gate: io.popen returned no handle") end
        local out, prefix = {}, ROOT .. "/"
        for line in p:lines() do
        if line ~= "" then
            out[#out + 1] = (line:sub(1, #prefix) == prefix) and line:sub(#prefix + 1) or line
        end
        end
        p:close()
        return out
end

--- Does `id` head a table cell, a heading or a bullet anywhere in `files`?
local function isAssigned(id, files)
    local function heads(s)
        return s:sub(1, #id) == id and not s:sub(#id + 1, #id + 1):match("[%w%-]")
    end
    for _, path in ipairs(files) do
        for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
            local trimmed = line:gsub("^%s+", "")
            local lead = trimmed:match("^#+%s*(.*)$") or trimmed:match("^[%-%*]%s+(.*)$")
            if lead and heads((lead:gsub("^[%s%*`%[]+", ""))) then return true end
            if trimmed:sub(1, 1) == "|" then
        for field in (trimmed .. "|"):gmatch("([^|]*)|") do
          if heads((field:gsub("^[%s%*`%[]+", ""))) then return true end
        end
            end
        end
    end
    return false
end

test("every deviation id the register cites is assigned by a bundle in docs/audits/", function()
  -- The sentinel is what lets the register be the file's LAST `##` section without the slice
  -- silently coming back nil and the case passing on an empty string.
    local body = read(ARCHITECTURE) .. "\n## \n"
    local section = body:match("\n## Documented deviations\r?\n(.-)\r?\n## ")
    assertTrue(section ~= nil,
        "docs/ARCHITECTURE.md has no `## Documented deviations` section to read")

    local files = bundleFiles()
    if #files == 0 then fail("register gate: no bundle files under docs/audits/ to resolve against") end

    local seen, cited, offenders = {}, 0, {}
    for _, pattern in ipairs(DEVIATION_ID) do
        for pos, id in section:gmatch("()(" .. pattern .. ")") do
      -- A hyphen in front means this is the tail of a longer id (a work-item `M1-LK-11`), not a
      -- citation of a bundle row.
            if section:sub(pos - 1, pos - 1) ~= "-" and not id:find("%-R%-") and not seen[id] then
        seen[id] = true
        cited = cited + 1
        if not isAssigned(id, files) then offenders[#offenders + 1] = id end
            end
        end
    end

    assertTrue(cited > 0,
        "the register cites no deviation id at all -- either the rows changed or DEVIATION_ID did")
    assertEqual(#offenders, 0,
        "cited by a register row and assigned by no bundle under docs/audits/: "
            .. table.concat(offenders, ", "))
end)

-- ---------------------------------------------------------------------------------------------
-- KickCD.toc's load-bearing positions for the module siblings (toc-file-§2).
--
-- A sibling file that runs `NS:GetModule("X")` at FILE scope raises during load if X's parent has
-- not registered yet: AceAddon's GetModule is not silent. So the sibling's TOC position is
-- load-bearing, and the rule is that such a position says so in a `# LOAD-BEARING POSITION` comment
-- a reader meets before moving the line. The comment may sit directly above the line or above its
-- group (one note above modules\IconGrid_Layout.lua covers IconGrid_Render.lua below it), but it
-- must NAME the file, so a note written for one sibling cannot silently vouch for another.
--
-- red under: deleting either module-sibling LOAD-BEARING note from KickCD.toc, or dropping a
-- sibling's name from it, or moving a sibling above its parent.

--- KickCD.toc's lines, CRLF normalized, in order.
local function tocLines()
    local lines = {}
    for line in (read("KickCD.toc") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

--- The comment text a TOC line inherits: walk up over sibling file lines to the first comment
--- block, and collect that block, stopping at a blank line.
local function inheritedComment(lines, at)
    local i, block = at - 1, {}
    while i >= 1 and lines[i] ~= "" and lines[i]:sub(1, 1) ~= "#" do i = i - 1 end
    while i >= 1 and lines[i]:sub(1, 1) == "#" do
        table.insert(block, 1, lines[i])
        i = i - 1
    end
    return table.concat(block, "\n")
end

test("every file-scope NS:GetModule sits below its parent under a LOAD-BEARING comment", function()
    local lines = tocLines()
    local position, parentOf, siblings = {}, {}, {}
    for i, line in ipairs(lines) do
        local rel = line:match("^(modules\\[%w_]+%.lua)%s*$")
        if rel then
            local path = rel:gsub("\\", "/")
            position[path] = i
            for src in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
                local made = src:match("^local %w+ = NS:NewModule%(\"(%w+)\"")
                if made then parentOf[made] = path end
                local wanted = src:match("^[^%s%-].-NS:GetModule%(\"(%w+)\"%)")
                if wanted then siblings[#siblings + 1] = { path = path, parent = wanted, line = i } end
            end
        end
    end

    assertTrue(#siblings > 0,
        "no modules/*.lua calls NS:GetModule at file scope -- either the siblings changed or the scan did")
    local offenders = {}
    for _, s in ipairs(siblings) do
        local parentPath = parentOf[s.parent]
        local base = s.path:match("([^/]+)$")
        local note = inheritedComment(lines, s.line)
        if not parentPath or position[parentPath] > s.line then
            offenders[#offenders + 1] = s.path .. " (loads above its parent " .. s.parent .. ")"
        elseif not note:find("LOAD-BEARING POSITION", 1, true) or not note:find(base, 1, true) then
            offenders[#offenders + 1] = s.path .. " (no LOAD-BEARING POSITION note naming it)"
        end
    end
    assertEqual(#offenders, 0,
        "file-scope NS:GetModule siblings without a stated TOC position: " .. table.concat(offenders, ", "))
end)
