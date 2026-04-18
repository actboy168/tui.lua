-- tui/ime.lua — IME candidate window positioning for POSIX terminals.
--
-- Provides terminal-specific IME candidate window positioning by choosing
-- the optimal escape sequence based on the detected terminal emulator:
--
--   * iTerm2  → OSC 1337 CursorShape / IME positioning (ime_osc1337)
--   * kitty   → kitty keyboard protocol IME features (ime_kitty_proto)
--   * others  → standard CSI CUP fallback (ime_csi_cup)
--
-- The public API is a single function:
--   ime.set_pos(terminal, col, row)
--
-- where `terminal` is the tui_core.terminal module (or a fake in tests)
-- and (col, row) are 1-based absolute terminal coordinates.

local info = require "tui.terminal_info"

local M = {}

-- Platform detection: Windows uses IMM API via terminal.set_ime_pos (C layer),
-- POSIX uses terminal escape sequences via Lua-level dispatch.
local <const> IS_WINDOWS = (package.config:sub(1, 1) == "\\")

-- ---------------------------------------------------------------------------
-- OSC 1337 IME positioning for iTerm2
--
-- iTerm2 supports OSC 1337 for various extensions. For IME candidate
-- window positioning, we use the cursor position tracking approach:
-- the terminal tracks the cursor position and places the IME candidate
-- window near it. We move the cursor to the target position, then
-- restore it — same strategy as the C-level CSI CUP, but using OSC 1337
-- allows iTerm2 to know this is an IME-related cursor move.
--
-- OSC 1337 SetMark: \033]1337;SetMark\007
-- This tells iTerm2 to record the current cursor position for IME.
-- Combined with CUP to the target position, iTerm2 will position the
-- candidate window at that location.

local function iterm2_ime_pos(terminal, col, row)
    -- Save cursor, move to target, set mark for IME, restore cursor.
    terminal.write("\0277")                          -- DECSC: save cursor
    terminal.write(string.format("\027[%d;%dH", row, col))  -- CUP: move to target
    terminal.write("\027]1337;SetMark\007")          -- OSC 1337: mark for IME
    terminal.write("\0278")                          -- DECRC: restore cursor
end

-- ---------------------------------------------------------------------------
-- kitty keyboard protocol IME positioning
--
-- kitty uses the keyboard protocol for enhanced input handling. For IME
-- candidate window positioning, kitty tracks the cursor position
-- automatically. The standard CSI CUP approach works well — kitty
-- positions the candidate window near the current cursor location.
-- We use the same save/move/restore pattern as the C-level fallback.

local function kitty_ime_pos(terminal, col, row)
    terminal.write("\0277")                          -- DECSC: save cursor
    terminal.write(string.format("\027[%d;%dH", row, col))  -- CUP: move to target
    terminal.write("\0278")                          -- DECRC: restore cursor
end

-- ---------------------------------------------------------------------------
-- Standard CSI CUP fallback
--
-- For terminals without specific IME support, we move the cursor to the
-- target position (which most terminals use to track IME candidate window
-- location) and then restore the cursor. All POSIX IME positioning is
-- handled in Lua via terminal.write(); the C-level set_ime_pos is a
-- no-op on POSIX (used only on Windows for the IMM API).

local function csi_cup_ime_pos(terminal, col, row)
    terminal.write("\0277")                          -- DECSC: save cursor
    terminal.write(string.format("\027[%d;%dH", row, col))  -- CUP: move to target
    terminal.write("\0278")                          -- DECRC: restore cursor
end

-- ---------------------------------------------------------------------------
-- Public API

--- Position the IME candidate window at the given terminal coordinates.
-- @param terminal  the tui_core.terminal module (or compatible fake)
-- @param col       1-based column
-- @param row       1-based row
function M.set_pos(terminal, col, row)
    if not col or not row then return end

    -- Windows: delegate to C-level IMM API (terminal.set_ime_pos).
    if IS_WINDOWS then
        terminal.set_ime_pos(col, row)
        return
    end

    -- POSIX: dispatch to terminal-specific escape sequence.
    local caps = info.capabilities()

    if caps.ime_osc1337 then
        iterm2_ime_pos(terminal, col, row)
    elseif caps.ime_kitty_proto then
        kitty_ime_pos(terminal, col, row)
    else
        csi_cup_ime_pos(terminal, col, row)
    end
end

--- Expose the per-terminal sequence builders for testing.
-- These return the raw string that would be written, without
-- actually writing to the terminal.
M._iterm2_sequence = function(col, row)
    return "\0277"
        .. string.format("\027[%d;%dH", row, col)
        .. "\027]1337;SetMark\007"
        .. "\0278"
end

M._kitty_sequence = function(col, row)
    return "\0277"
        .. string.format("\027[%d;%dH", row, col)
        .. "\0278"
end

M._csi_cup_sequence = function(col, row)
    return "\0277"
        .. string.format("\027[%d;%dH", row, col)
        .. "\0278"
end

return M
