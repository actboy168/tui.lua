-- tui/ansi.lua — semantic ANSI escape sequence builders.
--
-- Provides named functions instead of raw escape string concatenation.
-- Functions that depend on terminal-specific support accept an optional
-- `caps` table so callers can gate sequences per-terminal.
--
-- Constant sequences are pre-computed as module-level values to avoid
-- per-call string concatenation.

local M = {}

local <const> ESC = "\x1b"
local <const> BEL = "\007"
local <const> ST  = ESC .. "\\"

-- ---------------------------------------------------------------------------
-- Cursor visibility (DECTCEM: DEC mode 25)

M.cursorShow  = ESC .. "[?25h"
M.cursorHide  = ESC .. "[?25l"

-- ---------------------------------------------------------------------------
-- Cursor positioning (CSI)

local <const> _CSI_H = ESC .. "[%d;%dH"
local <const> _CSI_G = ESC .. "[%dG"
local <const> _CSI_A = ESC .. "[%dA"
local <const> _CSI_B = ESC .. "[%dB"
local <const> _CSI_C = ESC .. "[%dC"
local <const> _CSI_D = ESC .. "[%dD"
local <const> _CURSOR_HOME   = ESC .. "[H"
local <const> _CURSOR_LEFT   = ESC .. "[G"
local <const> _CURSOR_UP1    = ESC .. "[A"
local <const> _CURSOR_DOWN1  = ESC .. "[B"
local <const> _CURSOR_FWD1   = ESC .. "[C"
local <const> _CURSOR_BACK1  = ESC .. "[D"
local <const> _CURSOR_TO1    = ESC .. "[G"

--- Move cursor to absolute (col, row). Both 1-based.
function M.cursorPosition(col, row, caps)
    local suffix = ""
    if caps and caps.ime_osc1337 then
        suffix = ESC .. "]1337;SetMark" .. (caps.osc_st and ST or BEL)
    end
    return string.format(_CSI_H, row, col) .. suffix
end

--- Move cursor to absolute column on the current row (CSI n G). 1-based.
function M.cursorTo(col)
    if col == 1 then return _CURSOR_TO1 end
    return string.format(_CSI_G, col)
end

--- Move cursor up by n rows (default 1).
function M.cursorUp(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _CURSOR_UP1 end
    return string.format(_CSI_A, n)
end

--- Move cursor down by n rows (default 1).
function M.cursorDown(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _CURSOR_DOWN1 end
    return string.format(_CSI_B, n)
end

--- Move cursor forward by n columns (default 1).
function M.cursorForward(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _CURSOR_FWD1 end
    return string.format(_CSI_C, n)
end

--- Move cursor backward by n columns (default 1).
function M.cursorBackward(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _CURSOR_BACK1 end
    return string.format(_CSI_D, n)
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
M.cursorLeft = _CURSOR_LEFT

--- Move cursor to home position (row 1, column 1).
M.cursorHome = _CURSOR_HOME

-- ---------------------------------------------------------------------------
-- Cursor save / restore

M.cursorSave    = ESC .. "[s"
M.cursorRestore = ESC .. "[u"

-- ---------------------------------------------------------------------------
-- Cursor shape (DECSCUSR: CSI n SP q)

local <const> CURSOR_SHAPE_MAP = {
    block     = { blinking = 1, steady = 2 },
    underline = { blinking = 3, steady = 4 },
    bar       = { blinking = 5, steady = 6 },
}

local <const> _CSI_Q = ESC .. "[%d q"

function M.cursorShape(style, blinking, caps)
    if caps and not caps.cursor_shape then return "" end
    local shapes = CURSOR_SHAPE_MAP[style]
    if not shapes then return "" end
    local n = (blinking ~= false) and shapes.blinking or shapes.steady
    return string.format(_CSI_Q, n)
end

-- ---------------------------------------------------------------------------
-- Erase

M.eraseScreen      = ESC .. "[2J"
M.eraseScrollback  = ESC .. "[3J"
M.eraseLine        = ESC .. "[2K"
M.eraseEndLine     = ESC .. "[K"
M.eraseStartLine   = ESC .. "[1K"

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

local <const> _CSI_S = ESC .. "[%dS"
local <const> _CSI_T = ESC .. "[%dT"
local <const> _SCROLL_UP1   = ESC .. "[S"
local <const> _SCROLL_DOWN1 = ESC .. "[T"

function M.scrollUp(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _SCROLL_UP1 end
    return string.format(_CSI_S, n)
end

function M.scrollDown(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return _SCROLL_DOWN1 end
    return string.format(_CSI_T, n)
end

local <const> _CSI_R = ESC .. "[%d;%dr"

function M.setScrollRegion(top, bottom)
    return string.format(_CSI_R, top, bottom)
end

M.resetScrollRegion = ESC .. "[r"

-- ---------------------------------------------------------------------------
-- DEC private modes

local <const> _ALT_SCREEN_ON  = ESC .. "[?1049h"
local <const> _ALT_SCREEN_OFF = ESC .. "[?1049l"
local <const> _SYNC_ON        = ESC .. "[?2026h"
local <const> _SYNC_OFF       = ESC .. "[?2026l"

function M.enterAltScreen(caps)
    if caps and not caps.alt_screen then return "" end
    return _ALT_SCREEN_ON
end

function M.exitAltScreen(caps)
    if caps and not caps.alt_screen then return "" end
    return _ALT_SCREEN_OFF
end

function M.beginSyncUpdate(caps)
    if caps and not caps.sync_output then return "" end
    return _SYNC_ON
end

function M.endSyncUpdate(caps)
    if caps and not caps.sync_output then return "" end
    return _SYNC_OFF
end

M.enableBracketedPaste  = ESC .. "[?2004h"
M.disableBracketedPaste = ESC .. "[?2004l"

M.enableFocusEvents  = ESC .. "[?1004h"
M.disableFocusEvents = ESC .. "[?1004l"

M.mouseMode = {
    sgr_on    = ESC .. "[?1006h",
    sgr_off   = ESC .. "[?1006l",
    click_on  = ESC .. "[?1000h",
    click_off = ESC .. "[?1000l",
    drag_on   = ESC .. "[?1002h",
    drag_off  = ESC .. "[?1002l",
    any_on    = ESC .. "[?1003h",
    any_off   = ESC .. "[?1003l",
}

M.kittyKeyboard = {
    push = ESC .. "[>3u",
    pop  = ESC .. "[<u",
}

-- ---------------------------------------------------------------------------
-- Terminal title (OSC 0/2)

local <const> _OSC_0 = ESC .. "]0;"

function M.setTitle(title, caps)
    local term = BEL
    if caps and caps.osc_st then
        term = ST
    end
    return _OSC_0 .. (title or "") .. term
end

-- ---------------------------------------------------------------------------
-- SGR

M.resetSgr = ESC .. "[0m"

-- ---------------------------------------------------------------------------
-- iTerm2 extensions

local <const> _ITERM2_SETMARK = ESC .. "]1337;SetMark"

function M.iterm2SetMark(caps)
    if not caps or not caps.ime_osc1337 then return "" end
    return _ITERM2_SETMARK .. (caps.osc_st and ST or BEL)
end

-- ---------------------------------------------------------------------------
-- Composite helpers

M.clearScreen = ESC .. "[H" .. ESC .. "[2J"

local <const> _CLEAR_FULL          = ESC .. "[H" .. ESC .. "[2J" .. ESC .. "[3J"
local <const> _CLEAR_FULL_LEGACY   = ESC .. "[2J" .. ESC .. "[0f"

function M.clearScreenFull(caps)
    if caps and caps.legacy_windows then
        return _CLEAR_FULL_LEGACY
    end
    return _CLEAR_FULL
end

return M
