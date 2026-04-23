-- test/hooks/test_use_terminal_focus_title.lua
-- Tests for useTerminalFocus() and useTerminalTitle() hooks.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local input_helpers = require "tui.testing.input"

local suite = lt.test "use_terminal_focus_title"

-- ---------------------------------------------------------------------------
-- useTerminalFocus

-- Helper: focus-aware component that renders its state as text.
local function FocusApp()
    local state = tui.useTerminalFocus()
    return tui.Text {
        width = 20, height = 1,
        state.focused and "focused" or "blurred",
    }
end

function suite:test_initial_state_is_focused()
    local h = testing.render(FocusApp, { cols = 20, rows = 1 })
    lt.assertEquals(h:row(1):match("^%S+"), "focused")
    h:unmount()
end

function suite:test_focus_out_event_changes_state()
    local h = testing.render(FocusApp, { cols = 20, rows = 1 })
    -- ESC [ O  →  CSI O  →  focus_out
    h:dispatch("\x1b[O")
    h:rerender()
    lt.assertEquals(h:row(1):match("^%S+"), "blurred")
    h:unmount()
end

function suite:test_focus_in_event_restores_state()
    local h = testing.render(FocusApp, { cols = 20, rows = 1 })
    h:dispatch("\x1b[O")  -- lose focus
    h:rerender()
    h:dispatch("\x1b[I")  -- regain focus
    h:rerender()
    lt.assertEquals(h:row(1):match("^%S+"), "focused")
    h:unmount()
end

function suite:test_focus_events_not_dispatched_to_useInput()
    -- useInput should NOT see focus_in / focus_out events.
    local seen = {}
    local function App()
        tui.useInput(function(_, key)
            seen[#seen + 1] = key.name
        end)
        return tui.Text { width = 5, height = 1, "x" }
    end
    local h = testing.render(App, { cols = 5, rows = 1 })
    h:dispatch("\x1b[I")
    h:dispatch("\x1b[O")
    lt.assertEquals(#seen, 0, "focus events must not reach useInput handlers")
    h:unmount()
end

function suite:test_multiple_subscribers()
    -- Two components each track focus independently.
    local a_states = {}
    local b_states = {}
    local function A()
        local s = tui.useTerminalFocus()
        return tui.Text { width = 5, height = 1, s.focused and "A:Y" or "A:N" }
    end
    local function B()
        local s = tui.useTerminalFocus()
        return tui.Text { width = 5, height = 1, s.focused and "B:Y" or "B:N" }
    end
    local function App()
        return tui.Box {
            width = 10, height = 2, flexDirection = "column",
            tui.component(A)  {},
            tui.component(B)  {},
        }
    end
    local h = testing.render(App, { cols = 10, rows = 2 })
    local r1 = h:row(1):match("^%S+")
    local r2 = h:row(2):match("^%S+")
    lt.assertEquals(r1, "A:Y")
    lt.assertEquals(r2, "B:Y")
    h:dispatch("\x1b[O")
    h:rerender()
    lt.assertEquals(h:row(1):match("^%S+"), "A:N")
    lt.assertEquals(h:row(2):match("^%S+"), "B:N")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- useTerminalTitle
--
-- Effects write through the harness terminal, captured in h:ansi().

local function MountWithTitle(props)
    tui.useTerminalTitle(props.title or "mytitle")
    return tui.Text { width = 5, height = 1, "x" }
end

local function escape_ctrl(s)
    return s:gsub("%c", function(c) return ("\\x%02x"):format(c:byte()) end)
end

function suite:test_title_osc_sequence_format()
    local h = testing.render(tui.component(MountWithTitle), { cols = 5, rows = 1 })
    local raw = h:ansi()
    h:unmount()
    -- Must contain ESC ] 0 ; mytitle  (BEL or ST terminator follows)
    lt.assertTrue(raw:find("\x1b]0;mytitle", 1, true) ~= nil,
                  "expected OSC 0;mytitle sequence, got: " .. escape_ctrl(raw))
end

function suite:test_title_updates_on_prop_change()
    local set_title_ref = {}
    local function DynTitleApp()
        local title, setTitle = tui.useState("first")
        set_title_ref.set = setTitle
        tui.useTerminalTitle(title)
        return tui.Text { width = 5, height = 1, title }
    end

    local h = testing.render(DynTitleApp, { cols = 5, rows = 1 })
    set_title_ref.set("second")
    h:rerender()
    local raw = h:ansi()
    h:unmount()
    lt.assertTrue(raw:find("\x1b]0;second", 1, true) ~= nil,
                  "title should update to 'second', got: " .. escape_ctrl(raw))
end

function suite:test_title_cleared_on_unmount()
    local function DynApp()
        tui.useTerminalTitle("clearing-test")
        return tui.Text { width = 5, height = 1, "x" }
    end

    -- Capture only the unmount phase so we verify the cleanup effect fires.
    local h = testing.render(DynApp, { cols = 5, rows = 1 })
    h:clear_ansi()
    h:unmount()
    local raw = h:ansi()
    -- Cleanup effect should write setTitle("") → ESC ] 0 ; <terminator>
    lt.assertTrue(raw:find("\x1b]0;", 1, true) ~= nil,
                  "cleanup should write a title-clear sequence, got: " .. escape_ctrl(raw))
end

return suite
