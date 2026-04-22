-- tui/internal/clipboard.lua — write text to the OS clipboard.
--
-- Priority order:
--   1. OSC 52 terminal escape sequence (works over SSH, tmux, Kitty, WezTerm…)
--   2. wl-copy  (Wayland)
--   3. xclip    (X11)
--   4. xsel     (X11)
--   5. pbcopy   (macOS)
--
-- Silent no-op when none is available.

local M = {}

-- ---------------------------------------------------------------------------
-- Configurable output writer.  During tui.render() this is swapped to the
-- real terminal.write so OSC 52 goes through the same fd as rendering.
-- Default: io.stdout so the module works standalone too.
-- ---------------------------------------------------------------------------
local _write = function(s) io.stdout:write(s) end

--- Set the raw-byte writer used by OSC 52.
-- Called by tui.init once the terminal is active.
function M.set_writer(fn)
    _write = fn
end

-- ---------------------------------------------------------------------------
-- Base64 encoder (pure Lua, RFC 4648 standard alphabet).
-- ---------------------------------------------------------------------------
local _b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(s)
    local out = {}
    local n   = #s
    local i   = 1
    while i <= n do
        local b0 = s:byte(i)     or 0
        local b1 = s:byte(i + 1) or 0
        local b2 = s:byte(i + 2) or 0
        local v  = b0 * 0x10000 + b1 * 0x100 + b2
        local c1 = math.floor(v / 0x40000) % 64 + 1
        local c2 = math.floor(v / 0x1000)  % 64 + 1
        local c3 = math.floor(v / 0x40)    % 64 + 1
        local c4 =             v            % 64 + 1
        local remaining = n - i + 1
        if remaining >= 3 then
            out[#out+1] = _b64chars:sub(c1,c1) .. _b64chars:sub(c2,c2)
                       .. _b64chars:sub(c3,c3) .. _b64chars:sub(c4,c4)
        elseif remaining == 2 then
            out[#out+1] = _b64chars:sub(c1,c1) .. _b64chars:sub(c2,c2)
                       .. _b64chars:sub(c3,c3) .. "="
        else
            out[#out+1] = _b64chars:sub(c1,c1) .. _b64chars:sub(c2,c2) .. "=="
        end
        i = i + 3
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- OSC 52 writer.  Handles tmux passthrough automatically.
-- ---------------------------------------------------------------------------
local function osc52_copy(text)
    local b64  = base64_encode(text)
    local seq  = "\x1b]52;c;" .. b64 .. "\x07"
    -- tmux requires DCS passthrough to forward OSC sequences to the outer terminal.
    local tmux = os.getenv("TMUX")
    if tmux and tmux ~= "" then
        seq = "\x1bPtmux;\x1b" .. seq .. "\x1b\\"
    end
    _write(seq)
    return true
end

-- ---------------------------------------------------------------------------
-- CLI tool helpers
-- ---------------------------------------------------------------------------

--- Check whether a binary is available on PATH.
local function probe_binary(binary)
    local probe = io.popen("command -v " .. binary .. " 2>/dev/null")
    local found = probe and probe:read("*l")
    if probe then probe:close() end
    return found and found ~= ""
end

--- Run a CLI command, feeding text to stdin. Returns true on success.
local function run_with_stdin(cmd, text)
    local f = io.popen(cmd .. " 2>/dev/null", "w")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

--- Run a CLI command, capturing stdout. Returns the output string or nil.
local function run_with_stdout(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    if text and #text > 0 then return text end
    return nil
end

-- ---------------------------------------------------------------------------
-- CLI tool lists
-- ---------------------------------------------------------------------------

local _write_tools = {
    "wl-copy",
    "xclip -selection clipboard",
    "xsel --clipboard --input",
    "pbcopy",
}

local _read_tools = {
    "xclip -selection clipboard -o",
    "xsel --clipboard --output",
    "pbpaste",
    "wl-paste --no-newline",
}

--- Write text to the OS clipboard.
--  Returns true on success, false if no method worked.
function M.copy(text)
    -- Try OSC 52 first (works over SSH, tmux, all modern terminals).
    -- Skip when running inside a test harness that has not set a real writer,
    -- so tests don't pollute stdout; the harness can still override _write.
    if M._osc52_enabled then
        return osc52_copy(text)
    end

    -- Fall back to CLI tools.
    for _, cmd in ipairs(_write_tools) do
        local binary = cmd:match("^%S+")
        if probe_binary(binary) then
            if run_with_stdin(cmd, text) then
                return true
            end
        end
    end
    return false
end

--- Read text from the OS clipboard.
--  Returns the clipboard text, or nil if no tool is available.
function M.read()
    for _, cmd in ipairs(_read_tools) do
        local binary = cmd:match("^%S+")
        if probe_binary(binary) then
            local text = run_with_stdout(cmd)
            if text then return text end
        end
    end
    return nil
end

-- OSC 52 is disabled by default; tui.render() enables it once the terminal
-- is active (interactive mode).  Tests that want to capture the sequence can
-- set _osc52_enabled = true and override set_writer.
M._osc52_enabled = false

-- Expose base64_encode for testing.
M._base64_encode = base64_encode

return M
