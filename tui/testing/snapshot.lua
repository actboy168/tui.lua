local M = {}

local <const> SNAPSHOT_DIR = "test/__snapshots__"

local function snapshot_path(name)
    if type(name) ~= "string" or #name == 0 then
        error("match_snapshot: name must be non-empty string", 3)
    end
    if name:find("[/\\%s]") then
        error("match_snapshot: name must not contain slashes or whitespace, got " .. name, 3)
    end
    return SNAPSHOT_DIR .. "/" .. name .. ".txt"
end

local function trim_trailing(s)
    s = s:gsub("\r\n", "\n")
    return (s:gsub("[ \t]+\n", "\n"):gsub("[ \t]+$", ""))
end

local function file_read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function ensure_dir(path)
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
    end
end

local function file_write(path, content)
    ensure_dir(SNAPSHOT_DIR)
    local f, err = io.open(path, "wb")
    if not f then error("match_snapshot: cannot write " .. path .. ": " .. tostring(err), 3) end
    f:write(content)
    f:close()
end

local function split_lines(s)
    local out = {}
    local i = 1
    while i <= #s do
        local j = s:find("\n", i, true)
        if not j then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, j - 1)
        i = j + 1
    end
    if s:sub(-1) == "\n" then out[#out + 1] = "" end
    return out
end

local function format_diff(name, expected, actual)
    local e_lines = split_lines(expected)
    local a_lines = split_lines(actual)
    local n = math.max(#e_lines, #a_lines)
    local first = nil
    for i = 1, n do
        if e_lines[i] ~= a_lines[i] then
            first = i
            break
        end
    end
    if not first then
        return ("snapshot %s: contents differ but no line-level diff found"):format(name)
    end
    local lo = math.max(1, first - 3)
    local hi = math.min(n, first + 3)
    local buf = { ("snapshot mismatch: %s"):format(name) }
    buf[#buf + 1] = ("first diff at line %d (expected %d rows, got %d rows)"):format(first, #e_lines, #a_lines)
    buf[#buf + 1] = "context (lines " .. lo .. ".." .. hi .. "):"
    for i = lo, hi do
        local e = e_lines[i] or "<<missing>>"
        local a = a_lines[i] or "<<missing>>"
        if e == a then
            buf[#buf + 1] = ("  %3d  %s"):format(i, e)
        else
            buf[#buf + 1] = ("- %3d  %s"):format(i, e)
            buf[#buf + 1] = ("+ %3d  %s"):format(i, a)
        end
    end
    buf[#buf + 1] = "re-run with TUI_UPDATE_SNAPSHOTS=1 to accept the new output."
    return table.concat(buf, "\n")
end

function M.install(Harness)
    function Harness:match_snapshot(name)
        local path = snapshot_path(name)
        local actual = trim_trailing(self:frame() .. "\n")

        if os.getenv("TUI_UPDATE_SNAPSHOTS") == "1" then
            file_write(path, actual)
            return self
        end

        local expected = file_read(path)
        if not expected then
            file_write(path, actual)
            return self
        end

        if trim_trailing(expected) == actual then return self end

        error(format_diff(name, expected, actual), 2)
    end
end

return M
