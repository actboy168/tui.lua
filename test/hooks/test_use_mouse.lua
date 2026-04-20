-- test/hooks/test_use_mouse.lua
-- Tests for useMouse() hook: SGR protocol parsing, event fields, modifiers, X10.

local lt        = require "ltest"
local testing   = require "tui.testing"
local tui       = require "tui"
local input_mod = require "tui.internal.input"

local suite = lt.test "use_mouse"

-- ---------------------------------------------------------------------------
-- Helper: component that collects mouse events into a caller-supplied table.

local function make_app(events)
    return function()
        tui.useMouse(function(ev) events[#events+1] = ev end)
        return tui.Text { width = 10, height = 1, "" }
    end
end

-- ---------------------------------------------------------------------------
-- SGR: basic button events

function suite:test_left_button_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<0;10;5M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "down")
    lt.assertEquals(events[1].button, 1)
    lt.assertEquals(events[1].x,      10)
    lt.assertEquals(events[1].y,      5)
    h:unmount()
end

function suite:test_left_button_up()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<0;3;7m")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "up")
    lt.assertEquals(events[1].button, 1)
    lt.assertEquals(events[1].x,      3)
    lt.assertEquals(events[1].y,      7)
    h:unmount()
end

function suite:test_middle_button_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<1;1;1M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "down")
    lt.assertEquals(events[1].button, 2)
    h:unmount()
end

function suite:test_right_button_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<2;1;1M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "down")
    lt.assertEquals(events[1].button, 3)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- SGR: scroll wheel (bit 6 = 64)

function suite:test_scroll_up()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<64;1;1M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "scroll")
    lt.assertEquals(events[1].scroll, 1)
    h:unmount()
end

function suite:test_scroll_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<65;1;1M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "scroll")
    lt.assertEquals(events[1].scroll, -1)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- SGR: motion (bit 5 = 32)

function suite:test_mouse_move()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<32;15;8M")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type, "move")
    lt.assertEquals(events[1].x,    15)
    lt.assertEquals(events[1].y,    8)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- SGR: modifier keys

function suite:test_shift_modifier()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<4;5;5M")   -- btn=0 + shift(4)
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertTrue(events[1].shift)
    lt.assertFalse(events[1].meta)
    lt.assertFalse(events[1].ctrl)
    h:unmount()
end

function suite:test_meta_modifier()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<8;5;5M")   -- btn=0 + meta(8)
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertFalse(events[1].shift)
    lt.assertTrue(events[1].meta)
    lt.assertFalse(events[1].ctrl)
    h:unmount()
end

function suite:test_ctrl_modifier()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<16;5;5M")  -- btn=0 + ctrl(16)
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertFalse(events[1].shift)
    lt.assertFalse(events[1].meta)
    lt.assertTrue(events[1].ctrl)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Mouse events are NOT forwarded to useInput

function suite:test_mouse_not_forwarded_to_useInput()
    local got_key = false
    local function App()
        tui.useInput(function(_ev) got_key = true end)
        tui.useMouse(function(_ev) end)
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    input_mod.dispatch("\x1b[<0;1;1M")
    h:_paint()
    lt.assertFalse(got_key, "mouse event must not reach useInput")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Harness:mouse() convenience helper

function suite:test_harness_mouse_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    h:mouse("down", 1, 5, 3)
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "down")
    lt.assertEquals(events[1].button, 1)
    lt.assertEquals(events[1].x,      5)
    lt.assertEquals(events[1].y,      3)
    h:unmount()
end

function suite:test_harness_mouse_up()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    h:mouse("up", 1, 5, 3)
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "up")
    lt.assertEquals(events[1].button, 1)
    h:unmount()
end

function suite:test_harness_mouse_scroll_up()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    h:mouse("scroll_up", nil, 1, 1)
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "scroll")
    lt.assertEquals(events[1].scroll, 1)
    h:unmount()
end

function suite:test_harness_mouse_scroll_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    h:mouse("scroll_down", nil, 1, 1)
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "scroll")
    lt.assertEquals(events[1].scroll, -1)
    h:unmount()
end

function suite:test_harness_mouse_modifiers()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    h:mouse("down", 1, 1, 1, { shift = true, ctrl = true })
    lt.assertEquals(#events, 1)
    lt.assertTrue(events[1].shift)
    lt.assertTrue(events[1].ctrl)
    lt.assertFalse(events[1].meta)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Legacy X10 protocol: ESC [ M <b+32> <x+32> <y+32>

function suite:test_x10_button_down()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    -- left button (0) at col=10 (10+32=42=0x2A), row=5 (5+32=37=0x25)
    input_mod.dispatch("\x1b[M\x20\x2a\x25")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type,   "down")
    lt.assertEquals(events[1].button, 1)
    lt.assertEquals(events[1].x,      10)
    lt.assertEquals(events[1].y,      5)
    h:unmount()
end

function suite:test_x10_release()
    local events = {}
    local h = testing.render(make_app(events), { cols = 10, rows = 1 })
    -- X10 release = btn bits 0-1 == 3 → 3+32=35=0x23
    input_mod.dispatch("\x1b[M\x23\x21\x21")
    h:_paint()
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].type, "up")
    -- X10 release does not carry button identity
    lt.assertNil(events[1].button)
    h:unmount()
end

return suite
