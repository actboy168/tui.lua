-- tui/hook/terminal.lua — terminal-related hooks.
--
-- useStdout, useStderr, useTerminalTitle, useTerminalFocus,
-- _set_terminal_write, _set_terminal_caps.

local core       = require "tui.hook.core"
local effect_mod = require "tui.hook.effect"

local M = {}

-- ---------------------------------------------------------------------------
-- Terminal write / caps injection (set by app_base during startup)

local _terminal_write
local _terminal_caps

function M._set_terminal_write(fn)
    _terminal_write = fn
end

function M._set_terminal_caps(caps)
    _terminal_caps = caps
end

-- ---------------------------------------------------------------------------
-- useStdout() -> { write = fn(s) }
-- Returns a handle for writing directly to the terminal's output stream.
-- Intended for use inside effects or event handlers, not during render.

function M.useStdout()
    core._current()
    return {
        write = function(s)
            if _terminal_write then
                _terminal_write(s)
            end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- useStderr() -> { write = fn(s) }
-- Returns a handle for writing to stderr (diagnostics, debug output, etc.).

function M.useStderr()
    core._current()
    return {
        write = function(s) io.stderr:write(s) end,
    }
end

-- ---------------------------------------------------------------------------
-- useTerminalFocus() -> { focused: bool }
--
-- Subscribes to DEC 1004 terminal focus/blur events for the component's
-- lifetime. Returns a state table with a single `focused` boolean field.
-- Assumes focused = true on mount (the terminal window is usually in
-- focus when the app starts).
--
-- Note: requires DEC 1004 to be enabled by the render loop (tui.render
-- enables it automatically alongside bracketed-paste).

local _terminal_focus_input_mod
local state_mod -- lazy

function M.useTerminalFocus()
    if not _terminal_focus_input_mod then
        _terminal_focus_input_mod = require "tui.internal.input"
    end
    state_mod = state_mod or require "tui.hook.state"
    local state, setState = state_mod.useState({ focused = true })
    effect_mod.useEffect(function()
        return _terminal_focus_input_mod.subscribe_focus(function(event_name)
            setState({ focused = event_name == "focus_in" })
        end)
    end, {})
    return state
end

-- ---------------------------------------------------------------------------
-- useTerminalTitle(title)
--
-- Sets the terminal window/tab title (OSC 0) for the component's lifetime.
-- Title is updated whenever `title` changes. On unmount the title is cleared
-- to an empty string so the terminal reverts to its default.

local _ansi_mod_for_title

function M.useTerminalTitle(title)
    core._current()
    if not _ansi_mod_for_title then
        _ansi_mod_for_title = require "tui.internal.ansi"
    end
    effect_mod.useEffect(function()
        if _terminal_write then
            _terminal_write(_ansi_mod_for_title.setTitle(title or "", _terminal_caps))
        end
        return function()
            if _terminal_write then
                _terminal_write(_ansi_mod_for_title.setTitle("", _terminal_caps))
            end
        end
    end, { title })
end

return M
