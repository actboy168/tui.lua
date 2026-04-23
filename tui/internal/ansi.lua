-- tui/ansi.lua — semantic ANSI escape sequence builders.
--
-- Provides named functions instead of raw escape string concatenation.
-- Functions that depend on terminal-specific support accept an optional
-- `caps` table so callers can gate sequences per-terminal.

local M = {}

local <const> ESC = "\x1b"
local <const> BEL = "\007"
local <const> ST  = ESC .. "\\"

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
function M.cursorPosition(col, row, caps)
    local suffix = ""
    if caps and caps.ime_osc1337 then
        suffix = ESC .. "]1337;SetMark" .. (caps.osc_st and ST or BEL)
    end
    return string.format(ESC .. "[%d;%dH", row, col) .. suffix
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

function M.cursorSave()
    return ESC .. "[s"
end

function M.cursorRestore()
    return ESC .. "[u"
end

-- ---------------------------------------------------------------------------
-- Cursor shape (DECSCUSR: CSI n SP q)

local <const> CURSOR_SHAPE_MAP = {
    block     = { blinking = 1, steady = 2 },
    underline = { blinking = 3, steady = 4 },
    bar       = { blinking = 5, steady = 6 },
}

function M.cursorShape(style, blinking, caps)
    if caps and not caps.cursor_shape then return "" end
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

function M.scrollUp(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[S" end
    return string.format(ESC .. "[%dS", n)
end

function M.scrollDown(n)
    n = n or 1
    if n == 0 then return "" end
    if n == 1 then return ESC .. "[T" end
    return string.format(ESC .. "[%dT", n)
end

function M.setScrollRegion(top, bottom)
    return string.format(ESC .. "[%d;%dr", top, bottom)
end

M.resetScrollRegion = ESC .. "[r"

-- ---------------------------------------------------------------------------
-- DEC private modes

function M.enterAltScreen(caps)
    if caps and not caps.alt_screen then return "" end
    return ESC .. "[?1049h"
end

function M.exitAltScreen(caps)
    if caps and not caps.alt_screen then return "" end
    return ESC .. "[?1049l"
end

function M.beginSyncUpdate(caps)
    if caps and not caps.sync_output then return "" end
    return ESC .. "[?2026h"
end

function M.endSyncUpdate(caps)
    if caps and not caps.sync_output then return "" end
    return ESC .. "[?2026l"
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

function M.setTitle(title, caps)
    local term = BEL
    if caps and caps.osc_st then
        term = ST
    end
    return ESC .. "]0;" .. (title or "") .. term
end

-- ---------------------------------------------------------------------------
-- SGR

M.resetSgr = ESC .. "[0m"

-- ---------------------------------------------------------------------------
-- iTerm2 extensions

function M.iterm2SetMark(caps)
    if not caps or not caps.ime_osc1337 then return "" end
    return ESC .. "]1337;SetMark" .. (caps.osc_st and ST or BEL)
end

-- ---------------------------------------------------------------------------
-- Composite helpers

M.clearScreen = ESC .. "[H" .. ESC .. "[2J"

function M.clearScreenFull(caps)
    if caps and caps.legacy_windows then
        return ESC .. "[2J" .. ESC .. "[0f"
    end
    return ESC .. "[H" .. ESC .. "[2J" .. ESC .. "[3J"
end

return M
