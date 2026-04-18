-- test/test_keys.lua — unit tests for tui_core.keys.parse and tui.input.

local lt        = require "ltest"
local tui_core  = require "tui_core"
local keys      = tui_core.keys
local input_mod = require "tui.input"

local suite = lt.test "keys_parse"

local function first(bytes)
    local evs = keys.parse(bytes)
    return evs[1]
end

-- Printable ASCII.
function suite:test_char_ascii()
    local ev = first("a")
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(ev.input, "a")
    lt.assertEquals(ev.ctrl, false)
    lt.assertEquals(ev.meta, false)
end

-- Multi-byte UTF-8 as a single char event.
function suite:test_char_utf8_cjk()
    local ev = first("中")  -- 3-byte UTF-8
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(ev.input, "中")
end

function suite:test_char_utf8_emoji()
    local ev = first("\240\159\154\128")  -- 🚀, 4-byte
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(#ev.input, 4)
end

-- Enter, Tab, Backspace, Escape.
function suite:test_enter_cr()
    lt.assertEquals(first("\r").name, "enter")
end
function suite:test_enter_lf()
    lt.assertEquals(first("\n").name, "enter")
end
function suite:test_tab()
    lt.assertEquals(first("\t").name, "tab")
end
function suite:test_backspace_del()
    lt.assertEquals(first("\127").name, "backspace")
end
function suite:test_backspace_bs()
    lt.assertEquals(first("\8").name, "backspace")
end
function suite:test_escape_alone()
    local ev = first("\27")
    lt.assertEquals(ev.name, "escape")
end

-- Ctrl+letter.
function suite:test_ctrl_a()
    local ev = first("\1")
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(ev.input, "a")
    lt.assertEquals(ev.ctrl, true)
end
function suite:test_ctrl_z()
    local ev = first("\26")
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(ev.input, "z")
    lt.assertEquals(ev.ctrl, true)
end

-- Arrow keys (CSI).
function suite:test_arrow_up()
    lt.assertEquals(first("\27[A").name, "up")
end
function suite:test_arrow_down()
    lt.assertEquals(first("\27[B").name, "down")
end
function suite:test_arrow_right()
    lt.assertEquals(first("\27[C").name, "right")
end
function suite:test_arrow_left()
    lt.assertEquals(first("\27[D").name, "left")
end
function suite:test_home_end()
    lt.assertEquals(first("\27[H").name, "home")
    lt.assertEquals(first("\27[F").name, "end")
end

-- Tilde keys.
function suite:test_delete()
    lt.assertEquals(first("\27[3~").name, "delete")
end
function suite:test_pageup()
    lt.assertEquals(first("\27[5~").name, "pageup")
end
function suite:test_pagedown()
    lt.assertEquals(first("\27[6~").name, "pagedown")
end
function suite:test_f5()
    lt.assertEquals(first("\27[15~").name, "f5")
end
function suite:test_f12()
    lt.assertEquals(first("\27[24~").name, "f12")
end

-- SS3 function keys.
function suite:test_ss3_f1_f4()
    lt.assertEquals(first("\27OP").name, "f1")
    lt.assertEquals(first("\27OQ").name, "f2")
    lt.assertEquals(first("\27OR").name, "f3")
    lt.assertEquals(first("\27OS").name, "f4")
end

-- Modifier decoding: ESC [ 1 ; 5 A  => ctrl+up.
function suite:test_ctrl_up()
    local ev = first("\27[1;5A")
    lt.assertEquals(ev.name, "up")
    lt.assertEquals(ev.ctrl, true)
    lt.assertEquals(ev.shift, false)
    lt.assertEquals(ev.meta, false)
end
-- ESC [ 1 ; 2 A => shift+up.
function suite:test_shift_up()
    local ev = first("\27[1;2A")
    lt.assertEquals(ev.name, "up")
    lt.assertEquals(ev.shift, true)
end
-- ESC [ 1 ; 7 A => ctrl+meta+up (bits 4+2+1 -> mod=7? no: shift=1,meta=2,ctrl=4; 7-1=6=meta+ctrl).
function suite:test_ctrl_meta_right()
    local ev = first("\27[1;7C")
    lt.assertEquals(ev.name, "right")
    lt.assertEquals(ev.ctrl, true)
    lt.assertEquals(ev.meta, true)
end

-- Alt/Meta + char: ESC <letter>.
function suite:test_meta_char()
    local ev = first("\27x")
    lt.assertEquals(ev.name, "char")
    lt.assertEquals(ev.input, "x")
    lt.assertEquals(ev.meta, true)
end

-- Multiple events in one buffer.
function suite:test_multiple_events()
    local evs = keys.parse("ab\27[A")
    lt.assertEquals(#evs, 3)
    lt.assertEquals(evs[1].input, "a")
    lt.assertEquals(evs[2].input, "b")
    lt.assertEquals(evs[3].name, "up")
end

-- Shift-tab (CSI Z).
function suite:test_backtab()
    lt.assertEquals(first("\27[Z").name, "backtab")
end

-- -------------------------------------------------------------------------
-- input.lua dispatch tests

local dsuite = lt.test "input_dispatch"

function dsuite:test_subscribe_receives_events()
    input_mod._reset()
    local got = {}
    local unsub = input_mod.subscribe(function(input, key)
        got[#got + 1] = { input = input, name = key.name }
    end)
    input_mod.dispatch("a\27[A")
    lt.assertEquals(#got, 2)
    lt.assertEquals(got[1].input, "a")
    lt.assertEquals(got[1].name, "char")
    lt.assertEquals(got[2].name, "up")
    unsub()
end

function dsuite:test_unsubscribe_stops_events()
    input_mod._reset()
    local count = 0
    local unsub = input_mod.subscribe(function() count = count + 1 end)
    input_mod.dispatch("a")
    lt.assertEquals(count, 1)
    unsub()
    input_mod.dispatch("b")
    lt.assertEquals(count, 1)
end

function dsuite:test_multiple_subscribers_all_notified()
    input_mod._reset()
    local a, b = 0, 0
    input_mod.subscribe(function() a = a + 1 end)
    input_mod.subscribe(function() b = b + 1 end)
    input_mod.dispatch("x")
    lt.assertEquals(a, 1)
    lt.assertEquals(b, 1)
end

function dsuite:test_unsubscribe_mid_dispatch_is_safe()
    input_mod._reset()
    local a_calls, b_calls = 0, 0
    local unsub_b
    input_mod.subscribe(function()
        a_calls = a_calls + 1
        unsub_b()  -- unsubscribe b while we're iterating
    end)
    unsub_b = input_mod.subscribe(function() b_calls = b_calls + 1 end)
    input_mod.dispatch("x")
    lt.assertEquals(a_calls, 1)
    -- b might or might not receive this event (snapshot behavior); subsequent
    -- events must not reach b.
    input_mod.dispatch("y")
    -- After the second dispatch, b_calls should be the same as after the first.
    local b_after = b_calls
    input_mod.dispatch("z")
    lt.assertEquals(b_calls, b_after)
end
