-- test/input/test_ansi.lua — tests for terminal detection, CI/TTY, and ansi sequences.
local lt       = require "ltest"
local ansi     = require "tui.internal.ansi"
local terminal = require "tui.internal.terminal"

local test_ansi = lt.test "ansi"

-- ---------------------------------------------------------------------------
-- 1. Interactive mode

function test_ansi:test_interactive_returns_boolean()
    lt.assertEquals(type(terminal.interactive()), "boolean")
end

-- ---------------------------------------------------------------------------
-- 6. ansi.lua sequence generation

function test_ansi:test_cursor_show_hide()
    lt.assertEquals(ansi.cursorShow, "\x1b[?25h")
    lt.assertEquals(ansi.cursorHide, "\x1b[?25l")
end

function test_ansi:test_cursor_position()
    lt.assertEquals(ansi.cursorPosition(5, 3), "\x1b[3;5H" .. ansi.iterm2SetMark())
    lt.assertEquals(ansi.cursorPosition(1, 1), "\x1b[1;1H" .. ansi.iterm2SetMark())
end

function test_ansi:test_cursor_to()
    lt.assertEquals(ansi.cursorTo(1), "\x1b[G")
    lt.assertEquals(ansi.cursorTo(5), "\x1b[5G")
end

function test_ansi:test_cursor_movement()
    lt.assertEquals(ansi.cursorUp(), "\x1b[A")
    lt.assertEquals(ansi.cursorUp(3), "\x1b[3A")
    lt.assertEquals(ansi.cursorUp(0), "")
    lt.assertEquals(ansi.cursorDown(), "\x1b[B")
    lt.assertEquals(ansi.cursorForward(), "\x1b[C")
    lt.assertEquals(ansi.cursorBackward(), "\x1b[D")
end

function test_ansi:test_cursor_move_combined()
    lt.assertEquals(ansi.cursorMove(3, 2), "\x1b[3C\x1b[2B")
    lt.assertEquals(ansi.cursorMove(-2, -1), "\x1b[2D\x1b[A")
    lt.assertEquals(ansi.cursorMove(0, 0), "")
    lt.assertEquals(ansi.cursorMove(1, 0), "\x1b[C")
    lt.assertEquals(ansi.cursorMove(0, 1), "\x1b[B")
end

function test_ansi:test_cursor_left()
    lt.assertEquals(ansi.cursorLeft, "\x1b[G")
end

function test_ansi:test_cursor_home()
    lt.assertEquals(ansi.cursorHome, "\x1b[H")
end

function test_ansi:test_cursor_save_restore()
    lt.assertEquals(ansi.cursorSave, "\x1b[s")
    lt.assertEquals(ansi.cursorRestore, "\x1b[u")
end

function test_ansi:test_cursor_shape_returns_string_or_empty()
    local s = ansi.cursorShape("block")
    lt.assertEquals(type(s), "string")
end

function test_ansi:test_erase()
    lt.assertEquals(ansi.eraseScreen, "\x1b[2J")
    lt.assertEquals(ansi.eraseScrollback, "\x1b[3J")
    lt.assertEquals(ansi.eraseLine, "\x1b[2K")
    lt.assertEquals(ansi.eraseEndLine, "\x1b[K")
    lt.assertEquals(ansi.eraseStartLine, "\x1b[1K")
end

function test_ansi:test_erase_lines()
    lt.assertEquals(ansi.eraseLines(0), "")
    lt.assertEquals(ansi.eraseLines(1), "\x1b[2K\x1b[G")
    lt.assertEquals(ansi.eraseLines(2), "\x1b[2K\x1b[A\x1b[2K\x1b[G")
end

function test_ansi:test_scroll()
    lt.assertEquals(ansi.scrollUp(), "\x1b[S")
    lt.assertEquals(ansi.scrollUp(3), "\x1b[3S")
    lt.assertEquals(ansi.scrollUp(0), "")
    lt.assertEquals(ansi.scrollDown(), "\x1b[T")
end

function test_ansi:test_scroll_region()
    lt.assertEquals(ansi.setScrollRegion(1, 24), "\x1b[1;24r")
    lt.assertEquals(ansi.resetScrollRegion, "\x1b[r")
end

function test_ansi:test_dec_modes_return_string()
    lt.assertEquals(type(ansi.enterAltScreen()), "string")
    lt.assertEquals(type(ansi.exitAltScreen()), "string")
    lt.assertEquals(type(ansi.beginSyncUpdate()), "string")
    lt.assertEquals(type(ansi.endSyncUpdate()), "string")
    lt.assertEquals(ansi.enableBracketedPaste, "\x1b[?2004h")
    lt.assertEquals(ansi.disableBracketedPaste, "\x1b[?2004l")
    lt.assertEquals(ansi.enableFocusEvents, "\x1b[?1004h")
    lt.assertEquals(ansi.disableFocusEvents, "\x1b[?1004l")
end

function test_ansi:test_sgr()
    lt.assertEquals(ansi.resetSgr, "\x1b[0m")
end

function test_ansi:test_iterm2_setmark_returns_string()
    lt.assertEquals(type(ansi.iterm2SetMark()), "string")
end

function test_ansi:test_composite()
    lt.assertEquals(ansi.clearScreen, "\x1b[H\x1b[2J")
    lt.assertEquals(type(ansi.clearScreenFull()), "string")
end
