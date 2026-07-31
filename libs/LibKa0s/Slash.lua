-- LibKa0s-Slash-1.0 — the slash dispatcher, the help renderer, the schema CLI, and the parser.
--
-- Four-plus copies across the collection in two different shapes, and the divergence is not
-- cosmetic: one shape parses values by bare coercion, so `set barWidth 99999` stores 99999 and
-- `set` on a color prints a table address. This library takes the type-aware shape — clamping,
-- enum validation, color tuples — because a CLI that silently accepts a value it cannot honor is
-- worse than one that refuses.
--
-- What the host keeps, and why it is not squeamishness: the COMMANDS table itself. A host owns its
-- verbs, passes the table in, and renders the same table on its own About page. If the library
-- owned it, an options module rendering that page would have to consume this one — and two
-- libraries reaching for each other is a real dependency cycle. The table crossing between them as
-- plain data is what keeps them independent.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Slash-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Slash = MINOR

-- ── strings ────────────────────────────────────────────────────────────────────────────────

lib.STRINGS = {
  HELP_HEADER      = "v%s \226\128\148 slash commands",
  HELP_ALIAS       = " (|cFFFFFF00%s|r is an alias for |cFFFFFF00%s|r)",
  UNKNOWN_COMMAND  = "unknown command '%s'",
  -- Green header, azure group headings. Lowercase hex, deliberately: only the command-row
  -- formatter above converges on uppercase, and quietly recasing these would be a user-visible
  -- change nobody asked for.
  LIST_HEADER      = "|cff33ff99Available settings|r",
  LIST_GROUP       = "  |cff3399ff[%s]|r",
  LIST_EMPTY       = "No settings registered yet",
  USAGE_GET        = "Usage: %s get <path>",
  USAGE_SET        = "Usage: %s set <path> <value>  (try %s list)",
  USAGE_RESET      = "Usage: %s reset <path>",
  NOT_FOUND        = "Setting not found: %s",
  INVALID          = "Invalid value for %s",
  RESET_ALL        = "All settings reset to defaults",
  VERSION          = "v%s",
  NONE             = "(none)",
  ERR_BOOL         = "expected true/false/on/off/1/0/yes/no",
  ERR_NUMBER       = "expected a number",
  ERR_STRING       = "expected a value",
  ERR_ALLOWED      = "allowed values: %s",
  ERR_COLOR        = "expected: r g b [a] (each 0-1 or 0-255)",
  ERR_TYPE         = "unknown setting type '%s'",
}

-- ── the formatters ─────────────────────────────────────────────────────────────────────────
--
-- Lib-level and stateless: a host's tests call them directly, and nothing about a rendered row
-- depends on which instance rendered it.

--- One row of a command list: gold command, an em dash with a single space either side, white
--- description. NOT indented — the indent belongs to whoever is rendering, because a chat line
--- needs one to sit under a header and a settings-panel label does not.
function lib.FormatRow(command, description)
  return ("|cFFFFFF00%s|r \226\128\148 |cFFFFFFFF%s|r"):format(tostring(command), tostring(description))
end

--- One `key = value` pair: gold key, white value, no trailing colon. Used by the list rows and by
--- the get/set echo, so the shape reads identically wherever a setting is printed.
function lib.FormatKV(path, valueStr)
  return ("|cFFFFFF00%s|r = |cFFFFFFFF%s|r"):format(tostring(path), tostring(valueStr))
end

--- Render a stored value for display, by the row's declared type.
---
--- Every branch guards its input through the Core seam BEFORE the value reaches a format. The
--- invariant that would make that unnecessary, that a stored settings value is never a
--- combat-protected value, is true of every host today, but it is written down nowhere and
--- enforced nowhere: a host whose `d.get` returns a derived or live value (an absorb total, a
--- health fraction) hands us a secret, and a secret RAISES inside `string.format` exactly as it
--- does inside `table.concat`. Guarding the input rather than the output keeps every rendered
--- byte of an ordinary value identical.
function lib.FormatValue(row, v)
  row = row or {}
  if v == nil then return "nil" end
  if row.type == "color" and type(v) == "table" then
    -- The table itself is never concat-safe; it is the four COMPONENTS that reach %.2f.
    local r, g, b, a = v.r or 0, v.g or 0, v.b or 0, v.a or 1
    if not (core.IsConcatSafe(r) and core.IsConcatSafe(g)
            and core.IsConcatSafe(b) and core.IsConcatSafe(a)) then return core.SECRET end
    return ("{%.2f, %.2f, %.2f, %.2f}"):format(r, g, b, a)
  end
  if row.type == "number" then
    if not core.IsConcatSafe(v) then return core.SECRET end
    if row.fmt then return row.fmt:format(v) end
    return tostring(v)
  end
  if row.type == "bool" then return v and "true" or "false" end
  if row.type == "string" and v == "" then return lib.STRINGS.NONE end
  return core.SafeToString(v)
end

-- ── the parser ─────────────────────────────────────────────────────────────────────────────
--
-- Type-aware, and that is the whole point of taking this shape rather than the coercing one. A
-- number out of range CLAMPS rather than failing, because a user typing a width larger than the
-- panel allows means "as wide as it goes"; a string outside its enum FAILS, because there is no
-- such reading of a misspelt texture name.
--
-- Failure is signalled by a nil first return plus a message. A row type whose valid value could
-- itself be nil would be indistinguishable from an error — none exists, and adding one would be a
-- contract change, not a new type.

local function parseBool(args)
  local s = (args[1] or ""):lower()
  if s == "true"  or s == "1" or s == "on"  or s == "yes" then return true  end
  if s == "false" or s == "0" or s == "off" or s == "no"  then return false end
  return nil, lib.STRINGS.ERR_BOOL
end

local function parseNumber(args, row)
  local n = tonumber(args[1])
  if not n then return nil, lib.STRINGS.ERR_NUMBER end
  if row.min then n = math.max(row.min, n) end
  if row.max then n = math.min(row.max, n) end
  return n
end

-- Evaluated at call time, not at load: a host's media list is populated by another addon and is
-- not knowable when the schema row is declared.
local function allowedValues(row)
  local v = type(row.values) == "function" and row.values() or row.values or {}
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function parseString(args, row)
  local v = args[1]
  if not v then return nil, lib.STRINGS.ERR_STRING end
  for _, a in ipairs(allowedValues(row)) do
    if a == v then return v end
  end
  return nil, lib.STRINGS.ERR_ALLOWED:format(table.concat(allowedValues(row), ", "))
end

local function parseColor(args)
  local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  local a = tonumber(args[4]) or 1
  if not (r and g and b) then return nil, lib.STRINGS.ERR_COLOR end
  -- Rescaled JOINTLY, not per channel: "255 128 0" is one color expressed in one scale, and
  -- dividing only the channels that happen to exceed 1 would mangle the others.
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
  if a > 1 then a = a / 255 end
  local function clamp01(n) return math.max(0, math.min(1, n)) end
  return { r = clamp01(r), g = clamp01(g), b = clamp01(b), a = clamp01(a) }
end

--- Parse `text` for `row`. Returns the value, or nil plus a reason.
function lib.ParseValue(row, text)
  row = row or {}
  local args = {}
  for w in (text or ""):gmatch("%S+") do args[#args + 1] = w end

  if row.type == "bool"   then return parseBool(args)        end
  if row.type == "number" then return parseNumber(args, row) end
  if row.type == "string" then return parseString(args, row) end
  if row.type == "color"  then return parseColor(args)       end
  return nil, lib.STRINGS.ERR_TYPE:format(tostring(row.type))
end

-- ── the instance ───────────────────────────────────────────────────────────────────────────

--- Build a dispatcher for one host.
---
--- Descriptor:
---   slash        string    required. The command prefix, with its slash: "/at". Every usage line
---                          and every help row is composed from it.
---   commands     table     required. The HOST's ordered { name, description, handler } triples.
---                          Passed in rather than owned, so the host's own About page can render
---                          the same table without that page's library depending on this one.
---   slashAliases table     optional. Other chat commands that reach the same dispatcher, named in
---                          the help header.
---   aliases      table     optional. Map of typed verb -> real verb, for backwards compatibility.
---   print        function  optional. Where lines go. Defaults to the chat frame.
---   version      function  optional. Returns the host's version string.
---   get/set      function  optional. Read and write one setting by path.
---   findRow      function  optional. Resolve a path to a schema row, or nil.
---   allRows      function  optional. Every row, in declaration order.
---   applyDefault function  optional. Restore one row to its default.
---   parse        function  optional, defaults to lib.ParseValue.
---   groupKey     function  optional. Row -> the heading it lists under. Defaults to row.page.
---   L            table     optional. Locale override, keyed to lib.STRINGS.
function lib:New(d)
  d = type(d) == "table" and d or {}
  if type(d.slash) ~= "string" or d.slash == "" then
    error(MAJOR .. ":New requires descriptor.slash — the command prefix, e.g. \"/at\"", 2)
  end
  if type(d.commands) ~= "table" then
    error(MAJOR .. ":New requires descriptor.commands — the host's own verb table", 2)
  end

  local strings = type(d.L) == "table" and d.L or nil
  local parse   = type(d.parse) == "function" and d.parse or lib.ParseValue
  local aliases = type(d.aliases) == "table" and d.aliases or {}
  local groupKey = type(d.groupKey) == "function" and d.groupKey
    or function(row) return row.page or "settings" end

  local emit = type(d.print) == "function" and d.print or function(line)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end

  local Sl = {}
  local annotator

  --- Resolve one user-visible string, host override first.
  ---
  --- rawget, NOT a plain index, and this is load-bearing rather than pedantic. Every Ka0s host's
  --- locale table carries a metatable fallback that answers an unknown key WITH THE KEY (the
  --- standard mandates it — anti-patterns #2). A plain index therefore accepts that synthesised
  --- string for every key, these STRINGS become unreachable, and the host renders raw keys like
  --- LIST_HEADER in place of English. It shipped exactly that way in a consumer's perf panel, for
  --- every string at once, and no headless case caught it because a synthesised value IS a string.
  ---
  --- rawget asks the only question that matters — did the host actually put a value here? — so a
  --- genuine entry still wins and a fallback-only table correctly falls through.
  function Sl:Text(key)
    local v = strings and rawget(strings, key)
    if type(v) == "string" then return v end
    return lib.STRINGS[key]
  end

  --- Whatever the host wants appended to a rendered setting — a note that a value is not the one
  --- actually in effect, most usefully. Applied at exactly three sites: a list row, a get echo and
  --- a set echo. Never on reset or resetall: an explanation of what a value means is noise stapled
  --- to an acknowledgement that the value went away.
  function Sl:SetRowAnnotator(fn)
    annotator = type(fn) == "function" and fn or nil
  end

  local function annotate(row)
    if not annotator then return "" end
    return annotator(row) or ""
  end

  local function kv(row, value)
    return lib.FormatKV(row.path, lib.FormatValue(row, value)) .. annotate(row)
  end

  -- ── help ─────────────────────────────────────────────────────────────────────────────────

  local function rows(indent)
    local out = {}
    for _, entry in ipairs(d.commands) do
      out[#out + 1] = indent .. lib.FormatRow(d.slash .. " " .. entry[1], entry[2])
    end
    return out
  end

  --- The chat form: indented, because each row sits under a header.
  function Sl:HelpRows() return rows("  ") end

  --- The panel form: identical colors and spacing, no indent. A landing page renders each row as
  --- its own label, where a leading indent reads as a mistake rather than as structure.
  function Sl:LandingRows() return rows("") end

  function Sl:HelpHeader()
    local version = type(d.version) == "function" and d.version() or "?"
    local header = self:Text("HELP_HEADER"):format(core.SafeToString(version))
    local alias = type(d.slashAliases) == "table" and d.slashAliases[1]
    if alias then header = header .. self:Text("HELP_ALIAS"):format(alias, d.slash) end
    return header
  end

  function Sl:PrintHelp()
    emit(self:HelpHeader())
    for _, line in ipairs(self:HelpRows()) do emit(line) end
  end

  -- ── the schema verbs ─────────────────────────────────────────────────────────────────────

  local function rowFor(path)
    return type(d.findRow) == "function" and d.findRow(path) or nil
  end

  -- Spelled out rather than folded into an `and`/`or` chain. A stored `false` is a perfectly good
  -- value, and `x and false or nil` yields nil — which would render every unticked checkbox in
  -- the addon as "nil" instead of "false".
  local function read(path)
    if type(d.get) ~= "function" then return nil end
    return d.get(path)
  end

  function Sl:BuildListLines()
    local all = type(d.allRows) == "function" and d.allRows() or {}
    if #all == 0 then return { self:Text("LIST_EMPTY") } end

    local out = { self:Text("LIST_HEADER") }
    -- Grouped in the order the rows were declared, not alphabetically: a schema's own order is the
    -- order its panel shows, and a list that disagreed with the panel would be its own puzzle.
    local order, grouped = {}, {}
    for _, row in ipairs(all) do
      local key = groupKey(row)
      if not grouped[key] then
        grouped[key] = {}
        order[#order + 1] = key
      end
      local g = grouped[key]
      g[#g + 1] = row
    end
    for _, key in ipairs(order) do
      out[#out + 1] = self:Text("LIST_GROUP"):format(key)
      for _, row in ipairs(grouped[key]) do
        out[#out + 1] = "    " .. kv(row, read(row.path))
      end
    end
    return out
  end

  function Sl:CliList()
    for _, line in ipairs(self:BuildListLines()) do emit(line) end
  end

  function Sl:CliGet(rest)
    local path = (rest or ""):match("^(%S+)")
    if not path then return emit(self:Text("USAGE_GET"):format(d.slash)) end
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end
    emit(kv(row, read(row.path)))
  end

  function Sl:CliSet(rest)
    local path, value = (rest or ""):match("^(%S+)%s*(.*)$")
    if not path then return emit(self:Text("USAGE_SET"):format(d.slash, d.slash)) end
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end

    local v, err = parse(row, value or "")
    if v == nil then
      emit(self:Text("INVALID"):format(row.path))
      if err and err ~= "" then emit("  " .. err) end
      return
    end

    if type(d.set) == "function" then d.set(row.path, v) end
    -- Re-read rather than echo what was parsed: a clamped number is only visible to the user
    -- because the echo reports what was actually stored.
    emit(kv(row, read(row.path)))
  end

  --- Reset ONE setting. There is deliberately no page-shaped form: a page is a property of a
  --- settings panel, and every such panel already carries a Defaults button that resets its page.
  function Sl:CliReset(rest)
    local path = (rest or ""):match("^(%S+)")
    if not path then return emit(self:Text("USAGE_RESET"):format(d.slash)) end
    -- Not lowercased. A path is case-sensitive, so folding it would resolve a setting the user did
    -- not name.
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end
    if type(d.applyDefault) == "function" then d.applyDefault(row) end
    emit(lib.FormatKV(row.path, lib.FormatValue(row, read(row.path))))
  end

  function Sl:CliResetAll()
    local all = type(d.allRows) == "function" and d.allRows() or {}
    for _, row in ipairs(all) do
      if type(d.applyDefault) == "function" then d.applyDefault(row) end
    end
    emit(self:Text("RESET_ALL"))
  end

  function Sl:CliVersion()
    local version = type(d.version) == "function" and d.version() or "?"
    emit(self:Text("VERSION"):format(core.SafeToString(version)))
  end

  -- ── dispatch ─────────────────────────────────────────────────────────────────────────────

  local function findCommand(name)
    for _, entry in ipairs(d.commands) do
      if entry[1] == name then return entry end
    end
  end

  function Sl:OnSlash(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
    if raw == "" then return self:PrintHelp() end

    -- Only the verb is lowercased. `rest` keeps its case because schema paths are case-sensitive,
    -- and its internal spacing because a color is several tokens.
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd  = (cmd or ""):lower()
    rest = rest or ""

    if aliases[cmd] then cmd = aliases[cmd] end

    local entry = findCommand(cmd)
    if entry then return entry[3](rest) end

    emit(self:Text("UNKNOWN_COMMAND"):format(cmd))
    self:PrintHelp()
  end

  return Sl
end
