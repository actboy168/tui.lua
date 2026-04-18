-- tui/ansi.lua — semantic ANSI escape sequence builders with terminal
-- capability awareness.
--
-- Inspired by Ink's termio/ module: provides named functions instead of raw
-- escape string concatenation. Functions that depend on terminal-specific
-- support (Synchronized Output, cursor shape, alternate screen) return ""
-- when the current terminal lacks that capability — callers never need to
-- gate-check themselves.
--
-- Design:
--   * Capabilities are auto-detected on module load.
--   * Universal sequences (cursor movement, erase, etc.) always produce output.
--   * Capability-gated sequences return "" when unsupported.
--   * Capability-dependent values are pre-computed so runtime calls are
--     branch-free string concatenations / table lookups.
--   * Cursor movement defaults to count=1; count is omitted when 1 to match
--     common terminal expectations (`\x1b[A` not `\x1b[1A`).
--   * cursorPosition(col, row) uses 1-based coordinates (ANSI convention).
--   * SGR color/style sequences are NOT here — the C layer (screen.c)
--     generates them per diff; Lua-level SGR is limited to resetSgr.

local M = {}

local <const> ESC = "\x1b"
local <const> BEL = "\007"
local <const> ST  = ESC .. "\\"
local <const> IS_WINDOWS = (require "bee.platform").os == "windows"

-- ---------------------------------------------------------------------------
-- Terminal type detection

--- Detect the current terminal emulator.
-- Returns a string identifier: "iterm2", "kitty", "apple_terminal",
-- "alacritty", "wezterm", "windows_terminal", "vscode", "ghostty",
-- "zed", "hyper", "foot", "mintty", "tmux", "windows_legacy", or "unknown".
local function detect()
    local term_program = os.getenv("TERM_PROGRAM") or ""
    local term         = os.getenv("TERM") or ""

    if term_program == "iTerm.app" then
        return "iterm2"
    elseif term_program == "Apple_Terminal" then
        return "apple_terminal"
    elseif term_program == "WezTerm" then
        return "wezterm"
    elseif term_program == "Alacritty" then
        return "alacritty"
    elseif term_program == "vscode" then
        return "vscode"
    elseif term_program == "ghostty" then
        return "ghostty"
    elseif term_program == "Hyper" then
        return "hyper"
    elseif term_program == "mintty" then
        return "mintty"
    end

    if IS_WINDOWS and os.getenv("WT_SESSION") then
        return "windows_terminal"
    end

    if IS_WINDOWS and (os.getenv("WEZTERM_EXECUTABLE") or "") ~= "" then
        return "wezterm"
    end

    if os.getenv("ALACRITTY_WINDOW_ID") then
        return "alacritty"
    end

    if os.getenv("KITTY_WINDOW_ID") then
        return "kitty"
    end

    if os.getenv("ZED_TERM") then
        return "zed"
    end

    if os.getenv("TMUX") then
        return "tmux"
    end

    if term == "xterm-kitty" then
        return "kitty"
    elseif term == "xterm-ghostty" then
        return "ghostty"
    elseif term == "foot" or term == "foot-direct" then
        return "foot"
    elseif term == "wezterm" then
        return "wezterm"
    elseif term:find("alacritty", 1, true) then
        return "alacritty"
    elseif term:find("kitty", 1, true) then
        return "kitty"
    elseif term:find("foot", 1, true) then
        return "foot"
    end

    if IS_WINDOWS then
        return "windows_legacy"
    end

    return "unknown"
end

-- ---------------------------------------------------------------------------
-- Capability detection
--
-- Per-terminal base flags (only true values listed; nil → false).
-- Derived flags (sync_output, cursor_shape, alt_screen, legacy_windows)
-- are computed from the detected terminal type.

local CAPABILITIES = {
    iterm2  = { ime_osc1337 = true },
    kitty   = { osc_st      = true },
}

local function check_sync_output(term_type)
    if term_type == "tmux" then return false end
    if term_type == "iterm2" then return true end
    if term_type == "wezterm" then return true end
    if term_type == "ghostty" then return true end
    if term_type == "kitty" then return true end
    if term_type == "vscode" then return true end
    if term_type == "alacritty" then return true end
    if term_type == "foot" then return true end
    if term_type == "zed" then return true end
    if term_type == "windows_terminal" then return true end
    local vte = os.getenv("VTE_VERSION")
    if vte then
        local version = tonumber(vte)
        if version and version >= 6800 then return true end
    end
    return false
end

local function check_cursor_shape(term_type)
    if term_type == "apple_terminal" then return false end
    if term_type == "windows_legacy" then return false end
    if term_type == "unknown" then return false end
    return true
end

local function check_alt_screen(term_type)
    if term_type == "apple_terminal" then return false end
    if term_type == "unknown" then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Pre-computed values (set once on module load, branch-free at runtime)

local _osc_term
local _osc1337_suffix
local _clearScreenFull
local _cursor_shape_on
local _alt_screen_enter
local _alt_screen_exit
local _sync_begin
local _sync_end

do
    local term_type = detect()
    local base = CAPABILITIES[term_type] or {}
    local osc_st         = base.osc_st      and true or false
    local ime_osc1337    = base.ime_osc1337 and true or false
    local sync_output    = check_sync_output(term_type)
    local cursor_shape   = check_cursor_shape(term_type)
    local alt_screen     = check_alt_screen(term_type)
    local legacy_windows = term_type == "windows_legacy"

    _osc_term = osc_st and ST or BEL

    if ime_osc1337 then
        _osc1337_suffix = ESC .. "]1337;SetMark" .. _osc_term
    else
        _osc1337_suffix = ""
    end

    if legacy_windows then
        _clearScreenFull = ESC .. "[2J" .. ESC .. "[0f"
    else
        _clearScreenFull = ESC .. "[H" .. ESC .. "[2J" .. ESC .. "[3J"
    end

    _cursor_shape_on = cursor_shape

    if alt_screen then
        _alt_screen_enter = ESC .. "[?1049h"
        _alt_screen_exit  = ESC .. "[?1049l"
    else
        _alt_screen_enter = ""
        _alt_screen_exit  = ""
    end

    if sync_output then
        _sync_begin = ESC .. "[?2026h"
        _sync_end   = ESC .. "[?2026l"
    else
        _sync_begin = ""
        _sync_end   = ""
    end
end

-- ---------------------------------------------------------------------------
-- Cursor visibility (DECTCEM: DEC mode 25)

function M.cursorShow()
    return ESC .. "[?25h"
end

function M.cursorHide()
    return ESC .. "[?25l"
end

-- ---------------------------------------------------------------------------
-- Cursor positioning (CSI)

--- Move cursor to absolute (col, row). Both 1-based.
-- On iTerm2 (ime_osc1337), automatically appends OSC 1337 SetMark
-- so the IME candidate window tracks the cursor position.
function M.cursorPosition(col, row)
    return string.format(ESC .. "[%d;%dH", row, col) .. _osc1337_suffix
end

--- Move cursor to absolute column on the current row (CSI n G). 1-based.
function M.cursorTo(col)
    if col == 1 then return ESC .. "[G" end
    return string.format(ESC .. "[%dG", col)
end

--- Move cursor up by n rows (default 1).
function M.cursorUp(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[A" end
    return string.format(ESC .. "[%dA", n)
end

--- Move cursor down by n rows (default 1).
function M.cursorDown(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[B" end
    return string.format(ESC .. "[%dB", n)
end

--- Move cursor forward by n columns (default 1).
function M.cursorForward(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[C" end
    return string.format(ESC .. "[%dC", n)
end

--- Move cursor backward by n columns (default 1).
function M.cursorBackward(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[D" end
    return string.format(ESC .. "[%dD", n)
end

--- Move cursor relative: positive x=right, negative x=left,
-- positive y=down, negative y=up. Composes from primitives.
function M.cursorMove(x, y)
    local parts = {}
    if x and x < 0 then
        parts[#parts + 1] = M.cursorBackward(-x)
    elseif x and x > 0 then
        parts[#parts + 1] = M.cursorForward(x)
    end
    if y and y < 0 then
        parts[#parts + 1] = M.cursorUp(-y)
    elseif y and y > 0 then
        parts[#parts + 1] = M.cursorDown(y)
    end
    return table.concat(parts)
end

--- Move cursor to the beginning of the current line (column 1).
M.cursorLeft = ESC .. "[G"

--- Move cursor to home position (row 1, column 1).
M.cursorHome = ESC .. "[H"

-- ---------------------------------------------------------------------------
-- Cursor save / restore
-- Uses CSI s/u (ANSI SCOSC/SCORC) — saves position only, not SGR state.
-- Ink uses the same; DECSC/DECRC (ESC 7/8) saves position + SGR which
-- can interact with the C layer's SGR management during diff rendering.

function M.cursorSave()
    return ESC .. "[s"
end

function M.cursorRestore()
    return ESC .. "[u"
end

-- ---------------------------------------------------------------------------
-- Cursor shape (DECSCUSR: CSI n SP q)
-- Capability-gated: returns "" if cursor_shape is false.

local <const> CURSOR_SHAPE_MAP = {
    block     = { blinking = 1, steady = 2 },
    underline = { blinking = 3, steady = 4 },
    bar       = { blinking = 5, steady = 6 },
}

--- Set cursor shape. Returns "" if terminal doesn't support DECSCUSR.
-- @param style     "block", "underline", or "bar"
-- @param blinking  true (default) or false
function M.cursorShape(style, blinking)
    if not _cursor_shape_on then return "" end
    local shapes = CURSOR_SHAPE_MAP[style]
    if not shapes then return "" end
    local n = (blinking ~= false) and shapes.blinking or shapes.steady
    return string.format(ESC .. "[%d q", n)
end

-- ---------------------------------------------------------------------------
-- Erase

M.eraseScreen      = ESC .. "[2J"
M.eraseScrollback  = ESC .. "[3J"
M.eraseLine        = ESC .. "[2K"
M.eraseEndLine     = ESC .. "[K"
M.eraseStartLine   = ESC .. "[1K"

--- Erase n lines starting from cursor, ending at column 1.
function M.eraseLines(n)
    if n <= 0 then return "" end
    local parts = {}
    for i = 1, n do
        parts[#parts + 1] = M.eraseLine
        if i < n then
            parts[#parts + 1] = M.cursorUp()
        end
    end
    parts[#parts + 1] = M.cursorLeft
    return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Scroll

--- Scroll up by n lines (CSI n S).
function M.scrollUp(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[S" end
    return string.format(ESC .. "[%dS", n)
end

--- Scroll down by n lines (CSI n T).
function M.scrollDown(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[T" end
    return string.format(ESC .. "[%dT", n)
end

--- Set scroll region (DECSTBM: CSI top;bottom r). 1-based, inclusive.
function M.setScrollRegion(top, bottom)
    return string.format(ESC .. "[%d;%dr", top, bottom)
end

--- Reset scroll region to full screen.
M.resetScrollRegion = ESC .. "[r"

-- ---------------------------------------------------------------------------
-- DEC private modes (pre-computed on module load)

--- Enter alternate screen buffer. Returns "" if unsupported.
function M.enterAltScreen()
    return _alt_screen_enter
end

--- Exit alternate screen buffer. Returns "" if unsupported.
function M.exitAltScreen()
    return _alt_screen_exit
end

--- Begin Synchronized Update (BSU). Returns "" if unsupported.
function M.beginSyncUpdate()
    return _sync_begin
end

--- End Synchronized Update (ESU). Returns "" if unsupported.
function M.endSyncUpdate()
    return _sync_end
end

-- Bracketed paste (DEC mode 2004)
M.enableBracketedPaste  = ESC .. "[?2004h"
M.disableBracketedPaste = ESC .. "[?2004l"

-- Focus events (DEC mode 1004)
M.enableFocusEvents  = ESC .. "[?1004h"
M.disableFocusEvents = ESC .. "[?1004l"

-- ---------------------------------------------------------------------------
-- SGR

M.resetSgr = ESC .. "[0m"

-- ---------------------------------------------------------------------------
-- iTerm2 extensions

--- OSC 1337 SetMark. Returns "" if terminal doesn't support OSC 1337.
-- Usually not needed directly — cursorPosition() already includes this
-- on iTerm2. Exposed for cases where a mark is needed without moving
-- the cursor (e.g. save/move/mark/restore patterns).
function M.iterm2SetMark()
    return _osc1337_suffix
end

-- ---------------------------------------------------------------------------
-- Composite helpers

--- Clear screen: move cursor home then erase.
M.clearScreen = ESC .. "[H" .. ESC .. "[2J"

--- Clear screen with scrollback: home + erase screen + erase scrollback.
-- On legacy Windows (conhost), uses HVP instead of CUP and omits
-- scrollback clear (CSI 3J unsupported). Matches Ink's clearTerminal.ts.
function M.clearScreenFull()
    return _clearScreenFull
end

return M
