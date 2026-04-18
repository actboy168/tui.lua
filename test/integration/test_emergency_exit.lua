-- test/test_emergency_exit.lua — Stage 15: Ctrl+C / Ctrl+D semantic dispatch.
--
-- input.dispatch now returns a boolean telling the outer loop whether a
-- framework-level exit key was seen. Unlike the old raw-byte scan, the
-- semantic check only fires for actual Ctrl+C / Ctrl+D *key events*;
-- literal bytes 0x03 / 0x04 appearing inside an escape sequence no longer
-- trigger a spurious exit.

local lt        = require "ltest"
local input_mod = require "tui.input"
local tui       = require "tui"
local testing   = require "tui.testing"

local suite = lt.test "emergency_exit"

-- ---------------------------------------------------------------------------
-- Case 1: Ctrl+C returns true and still broadcasts to useInput.

function suite:test_ctrl_c_returns_true_and_broadcasts()
    input_mod._reset()
    local seen = {}
    input_mod.subscribe(function(inp, key)
        seen[#seen + 1] = { inp = inp, name = key.name, ctrl = key.ctrl }
    end)
    local should_exit = input_mod.dispatch("\3")  -- 0x03 = Ctrl+C
    lt.assertEquals(should_exit, true)
    lt.assertEquals(#seen, 1)
    lt.assertEquals(seen[1].inp, "c")
    lt.assertEquals(seen[1].name, "char")
    lt.assertEquals(seen[1].ctrl, true)
    input_mod._reset()
end

-- ---------------------------------------------------------------------------
-- Case 2: Ctrl+D same behavior.

function suite:test_ctrl_d_returns_true()
    input_mod._reset()
    local should_exit = input_mod.dispatch("\4")  -- 0x04 = Ctrl+D
    lt.assertEquals(should_exit, true)
    input_mod._reset()
end

-- ---------------------------------------------------------------------------
-- Case 3: plain printable key returns false.

function suite:test_plain_char_returns_false()
    input_mod._reset()
    local should_exit = input_mod.dispatch("x")
    lt.assertEquals(should_exit, false)
    input_mod._reset()
end

-- ---------------------------------------------------------------------------
-- Case 4: useInput handler observes Ctrl+C via harness (end-to-end).

function suite:test_useinput_sees_ctrl_c()
    local saw_ctrl_c = false
    local function App()
        tui.useInput(function(_, key)
            if key.ctrl and key.input == "c" then saw_ctrl_c = true end
        end)
        return tui.Text { "x" }
    end
    local h = testing.render(App, { cols = 1, rows = 1 })
    h:dispatch("\3")
    lt.assertEquals(saw_ctrl_c, true)
    h:unmount()
end
