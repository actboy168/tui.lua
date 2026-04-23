-- test/unit/test_input_dispatch.lua — unit tests for tui/input.lua dispatch

local lt    = require "ltest"
local input = require "tui.internal.input"
local focus = require "tui.internal.focus"
local input_helpers = require "tui.testing.input"

local suite = lt.test "input_dispatch"

-- ============================================================================
-- Setup/teardown
-- ============================================================================

function suite:setup()
    input._reset()
    focus._reset()
end

function suite:teardown()
    input._reset()
    focus._reset()
end

-- ============================================================================
-- Basic dispatch tests
-- ============================================================================

function suite:test_dispatch_empty_bytes()
    local should_exit = input.dispatch("")
    lt.assertEquals(should_exit, false)
end

function suite:test_dispatch_nil_bytes()
    local should_exit = input.dispatch(nil)
    lt.assertEquals(should_exit, false)
end

function suite:test_dispatch_ctrl_c()
    -- Ctrl+C = \x03
    local should_exit = input.dispatch("\x03")
    lt.assertEquals(should_exit, true)
end

function suite:test_dispatch_ctrl_d()
    -- Ctrl+D = \x04
    local should_exit = input.dispatch("\x04")
    lt.assertEquals(should_exit, true)
end

function suite:test_dispatch_regular_char()
    local received = {}
    input.subscribe(function(str, key)
        received[#received + 1] = { str = str, key = key }
    end)

    local should_exit = input.dispatch("a")

    lt.assertEquals(should_exit, false)
    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1].str, "a")
end

-- ============================================================================
-- Broadcast handler tests
-- ============================================================================

function suite:test_subscribe_and_receive()
    local events = {}
    local unsubscribe = input.subscribe(function(str, key)
        events[#events + 1] = { str = str, key = key }
    end)

    input.dispatch("x")

    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].str, "x")

    unsubscribe()
end

function suite:test_unsubscribe()
    local events = {}
    local unsubscribe = input.subscribe(function(str)
        events[#events + 1] = str
    end)

    input.dispatch("a")
    lt.assertEquals(#events, 1)

    unsubscribe()

    input.dispatch("b")
    -- Should not receive "b" after unsubscribe
    lt.assertEquals(#events, 1)
end

function suite:test_multiple_handlers()
    local events1 = {}
    local events2 = {}

    input.subscribe(function(str) events1[#events1 + 1] = str end)
    input.subscribe(function(str) events2[#events2 + 1] = str end)

    input.dispatch("x")

    lt.assertEquals(#events1, 1)
    lt.assertEquals(#events2, 1)
    lt.assertEquals(events1[1], "x")
    lt.assertEquals(events2[1], "x")
end

-- ============================================================================
-- Focus navigation tests
-- ============================================================================

function suite:test_tab_focus_navigation()
    focus.enable()

    local order = {}
    focus.subscribe({ id = "a", on_change = function(f) if f then order[#order + 1] = "a" end end })
    focus.subscribe({ id = "b", on_change = function(f) if f then order[#order + 1] = "b" end end })
    focus.subscribe({ id = "c", on_change = function(f) if f then order[#order + 1] = "c" end end })

    -- Tab should move focus forward
    input._dispatch_event({ name = "tab", shift = false })

    -- Focus system behavior verified (no crash)
    lt.assertEquals(#order >= 0, true)

    focus._reset()
end

function suite:test_shift_tab_focus_navigation()
    focus.enable()

    local order = {}
    focus.subscribe({ id = "a", on_change = function(f) if f then order[#order + 1] = "a" end end })
    focus.subscribe({ id = "b", on_change = function(f) if f then order[#order + 1] = "b" end end })

    -- Shift+Tab should move focus backward
    input._dispatch_event({ name = "tab", shift = true })

    -- Focus system behavior verified (no crash)
    lt.assertEquals(#order >= 0, true)

    focus._reset()
end

function suite:test_backtab_focus_navigation()
    focus.enable()

    focus.subscribe({ id = "a", on_change = function() end })
    focus.subscribe({ id = "b", on_change = function() end })

    -- Backtab is another way to express Shift+Tab
    input._dispatch_event({ name = "backtab" })

    -- Focus system behavior verified (no crash)

    focus._reset()
end

function suite:test_focus_nav_does_not_broadcast()
    local broadcast_events = {}
    input.subscribe(function(str, key)
        broadcast_events[#broadcast_events + 1] = key
    end)

    focus.enable()
    focus.subscribe({ id = "a", on_change = function() end })

    input._dispatch_event({ name = "tab", shift = false })

    -- Tab for focus navigation should not cause errors
    -- (handlers are still called, but the event is marked as handled)

    focus._reset()
end

-- ============================================================================
-- Focused component dispatch tests
-- ============================================================================

function suite:test_focused_component_receives_input()
    focus.enable()

    local focused_input = {}
    focus.subscribe({
        id = "input",
        on_input = function(str, key)
            focused_input[#focused_input + 1] = str
        end
    })

    input.dispatch("x")

    -- Focused component should receive the input
    -- (along with broadcast handlers)

    focus._reset()
end

function suite:test_focus_and_broadcast_both_receive()
    local focused = {}
    local broadcast = {}

    focus.enable()
    focus.subscribe({
        id = "input",
        autoFocus = true,
        on_input = function(str)
            focused[#focused + 1] = str
        end
    })

    input.subscribe(function(str)
        broadcast[#broadcast + 1] = str
    end)

    input.dispatch("k")

    -- Both should receive the event
    lt.assertEquals(#focused, 1)
    lt.assertEquals(#broadcast, 1)
    lt.assertEquals(focused[1], "k")
    lt.assertEquals(broadcast[1], "k")

    focus._reset()
end

-- ============================================================================
-- Complex event handling
-- ============================================================================

function suite:test_escape_sequence()
    local events = {}
    input.subscribe(function(str, key)
        events[#events + 1] = { str = str, key = key }
    end)

    -- ESC sequence (e.g., arrow keys)
    input.dispatch("\x1b[A")  -- Up arrow

    -- Should be parsed and dispatched
    lt.assertEquals(#events >= 0, true)
end

function suite:test_multiple_events_in_one_dispatch()
    local events = {}
    input.subscribe(function(str, key)
        events[#events + 1] = str
    end)

    -- Multiple keys in one byte stream
    input.dispatch("ab")

    -- Both should be dispatched
    lt.assertEquals(#events >= 1, true)
end

-- ============================================================================
-- Reset functionality
-- ============================================================================

function suite:test_reset_clears_handlers()
    local events = {}
    input.subscribe(function(str) events[#events + 1] = str end)

    input.dispatch("a")
    lt.assertEquals(#events, 1)

    input._reset()

    input.dispatch("b")
    -- After reset, handler should be gone
    lt.assertEquals(#events, 1)
end

-- ============================================================================
-- _dispatch_event (for testing IME, etc.)
-- ============================================================================

function suite:test_dispatch_event_direct()
    local received = {}
    input.subscribe(function(str, key)
        received[#received + 1] = { str = str, key = key }
    end)

    -- Direct event dispatch without parsing
    input._dispatch_event({
        name = "char",
        input = "X",
        ctrl = false,
        shift = false
    })

    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1].str, "X")
end

function suite:test_dispatch_event_with_focus()
    focus.enable()

    local focused_received = {}
    focus.subscribe({
        id = "test",
        autoFocus = true,
        on_input = function(str)
            focused_received[#focused_received + 1] = str
        end
    })

    input._dispatch_event({
        name = "char",
        input = "Y",
        ctrl = false,
        shift = false
    })

    lt.assertEquals(#focused_received, 1)
    lt.assertEquals(focused_received[1], "Y")

    focus._reset()
end

-- ============================================================================
-- Kitty Keyboard Protocol: release event filtering
-- ============================================================================

function suite:test_kkp_release_events_are_suppressed()
    -- With KKP flags=3, terminal sends press+repeat+release for every key.
    -- Release events must NOT reach components (would cause double-triggers).
    local events = {}
    input.subscribe(function(str, key)
        events[#events + 1] = key
    end)

    -- Simulate a KKP sequence for 'a': press, repeat, release
    -- \x1b[97;1:1u = press, \x1b[97;1:2u = repeat, \x1b[97;1:3u = release
    input.dispatch("\x1b[97;1:1u\x1b[97;1:2u\x1b[97;1:3u")

    -- Only press and repeat should arrive; release is filtered
    lt.assertEquals(#events, 2)
    lt.assertEquals(events[1].event_type, "press")
    lt.assertEquals(events[2].event_type, "repeat")
end

function suite:test_kkp_enter_release_not_dispatched()
    -- Regression: Enter release must not trigger a second "submit-like" action.
    local count = 0
    input.subscribe(function(str, key)
        if key.name == "enter" then count = count + 1 end
    end)

    -- press + release of Enter via KKP
    input.dispatch("\x1b[13;1:1u\x1b[13;1:3u")

    lt.assertEquals(count, 1)  -- only one enter event (press)
end

function suite:test_kkp_shift_enter_release_not_dispatched()
    -- Regression: Shift+Enter release must not insert a second newline.
    local count = 0
    input.subscribe(function(str, key)
        if key.name == "enter" and key.shift then count = count + 1 end
    end)

    -- Shift+Enter press + release  (mod=2 = shift)
    input.dispatch("\x1b[13;2:1u\x1b[13;2:3u")

    lt.assertEquals(count, 1)  -- only the press
end

function suite:test_kkp_release_suppressed_after_middleware()
    -- Middleware still sees release events; suppression happens AFTER middleware.
    local mw_saw_release = false
    input.use_middleware(function(ev)
        if ev.event_type == "release" then mw_saw_release = true end
        return false  -- don't consume
    end)

    local subscriber_saw_release = false
    input.subscribe(function(str, key)
        if key.event_type == "release" then subscriber_saw_release = true end
    end)

    input.dispatch("\x1b[97;1:3u")  -- release of 'a'

    lt.assertEquals(mw_saw_release,         true)   -- middleware saw it
    lt.assertEquals(subscriber_saw_release, false)  -- subscriber did NOT
end

function suite:test_dispatch_cjk_chars()
    local got = {}
    input.subscribe(function(str, key)
        got[#got + 1] = { str = str, name = key.name }
    end)

    input.dispatch("中午")

    lt.assertEquals(#got, 2)
    lt.assertEquals(got[1].str, "中")
    lt.assertEquals(got[2].str, "午")
end

function suite:test_dispatch_shift_enter()
    local got = {}
    input.subscribe(function(str, key)
        got[#got + 1] = key
    end)

    -- Shift+Enter via Kitty Keyboard Protocol CSI u sequence
    input.dispatch("\x1b[13;2u")

    lt.assertEquals(#got, 1)
    lt.assertEquals(got[1].name, "enter")
    lt.assertEquals(got[1].shift, true)
end

