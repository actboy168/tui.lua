-- test/input/test_input_middleware.lua
-- Tests for input.use_middleware() pluggable middleware chain.

local lt        = require "ltest"
local testing   = require "tui.testing"
local tui       = require "tui"
local input_mod = require "tui.internal.input"
local input_helpers = require "tui.testing.input"
local mouse_helpers = require "tui.testing.mouse"

local suite = lt.test "input_middleware"

-- ---------------------------------------------------------------------------
-- Helper: component that registers a middleware for its lifetime.

local function make_app(mw_fn, input_fn)
    return function()
        tui.useEffect(function()
            return input_mod.use_middleware(mw_fn)
        end, {})
        if input_fn then
            tui.useInput(input_fn)
        end
        return tui.Text { width = 10, height = 1, "" }
    end
end

-- ---------------------------------------------------------------------------

function suite:test_middleware_observes_events()
    local seen = {}
    local h = testing.harness(make_app(function(ev)
        seen[#seen+1] = ev.name
    end), { cols = 10, rows = 1 })
    input_mod.dispatch("a")
    h:paint()
    lt.assertEquals(#seen, 1)
    lt.assertEquals(seen[1], "char")
    h:unmount()
end

function suite:test_middleware_can_consume_event()
    local broadcast_count = 0
    local function App()
        tui.useEffect(function()
            -- Swallow all events
            return input_mod.use_middleware(function(_ev) return true end)
        end, {})
        tui.useInput(function(_ev) broadcast_count = broadcast_count + 1 end)
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    input_mod.dispatch("a")
    h:paint()
    lt.assertEquals(broadcast_count, 0, "consumed event must not reach useInput")
    h:unmount()
end

function suite:test_middleware_runs_in_registration_order()
    local order = {}
    local function App()
        tui.useEffect(function()
            local u1 = input_mod.use_middleware(function(_ev) order[#order+1] = 1 end)
            local u2 = input_mod.use_middleware(function(_ev) order[#order+1] = 2 end)
            return function() u1(); u2() end
        end, {})
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    input_mod.dispatch("a")
    h:paint()
    lt.assertEquals(order[1], 1)
    lt.assertEquals(order[2], 2)
    h:unmount()
end

function suite:test_middleware_stops_at_first_consumer()
    local second_called = false
    local function App()
        tui.useEffect(function()
            local u1 = input_mod.use_middleware(function(_ev) return true end)  -- consumes
            local u2 = input_mod.use_middleware(function(_ev) second_called = true end)
            return function() u1(); u2() end
        end, {})
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    input_mod.dispatch("a")
    h:paint()
    lt.assertFalse(second_called, "second middleware must not run after event is consumed")
    h:unmount()
end

function suite:test_unsubscribe_removes_middleware()
    local called = false
    local unsub
    local function App()
        tui.useEffect(function()
            unsub = input_mod.use_middleware(function(_ev) called = true end)
            return unsub
        end, {})
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    unsub()
    input_mod.dispatch("a")
    h:paint()
    lt.assertFalse(called, "unsubscribed middleware must not be called")
    h:unmount()
end

function suite:test_middleware_sees_assembled_paste_event()
    -- The assembled paste event (name="paste") must flow through user middlewares,
    -- not bypass the chain as it did before the unified _process_event refactor.
    local mw_names = {}
    local function App()
        tui.useEffect(function()
            return input_mod.use_middleware(function(ev)
                mw_names[#mw_names+1] = ev.name
            end)
        end, {})
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    input_mod.dispatch(input_helpers.paste("hello"))
    h:paint()
    -- Middleware must see exactly one "paste" event
    local paste_count = 0
    for _, name in ipairs(mw_names) do
        if name == "paste" then paste_count = paste_count + 1 end
    end
    lt.assertEquals(paste_count, 1, "assembled paste event must flow through middleware")
    h:unmount()
end

function suite:test_middleware_does_not_intercept_paste_accumulation()
    -- Paste start/end are consumed internally before middleware runs.
    local mw_names = {}
    local pasted = {}
    local function App()
        tui.useEffect(function()
            return input_mod.use_middleware(function(ev) mw_names[#mw_names+1] = ev.name end)
        end, {})
        tui.usePaste(function(text) pasted[#pasted+1] = text end)
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    input_mod.dispatch(input_helpers.paste("hello"))
    h:paint()
    -- paste_start / paste_end should NOT appear in middleware (consumed before chain)
    for _, name in ipairs(mw_names) do
        lt.assertTrue(name ~= "paste_start" and name ~= "paste_end",
            "paste_start/end must not reach middleware")
    end
    -- The assembled paste should arrive via usePaste
    lt.assertEquals(#pasted, 1)
    lt.assertEquals(pasted[1], "hello")
    h:unmount()
end

function suite:test_middleware_sees_mouse_events_before_bus()
    local mw_types = {}
    local bus_types = {}
    local function App()
        tui.useEffect(function()
            return input_mod.use_middleware(function(ev)
                if ev.name == "mouse" then mw_types[#mw_types+1] = ev.type end
            end)
        end, {})
        tui.useMouse(function(ev) bus_types[#bus_types+1] = ev.type end)
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    h:dispatch(mouse_helpers.sgr { type = "down", button = 1, x = 1, y = 1 })
    h:rerender()
    lt.assertEquals(#mw_types, 1)
    lt.assertEquals(#bus_types, 1)
    lt.assertEquals(mw_types[1], "down")
    lt.assertEquals(bus_types[1], "down")
    h:unmount()
end

function suite:test_middleware_can_consume_mouse_before_bus()
    local bus_called = false
    local function App()
        tui.useEffect(function()
            return input_mod.use_middleware(function(ev)
                if ev.name == "mouse" then return true end
            end)
        end, {})
        tui.useMouse(function(_ev) bus_called = true end)
        return tui.Text { width = 10, height = 1, "" }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    h:dispatch(mouse_helpers.sgr { type = "down", button = 1, x = 1, y = 1 })
    lt.assertFalse(bus_called, "middleware consumed mouse; bus must not fire")
    h:unmount()
end

function suite:test_reset_clears_middlewares()
    -- _reset is called between renders; middlewares registered without useEffect
    -- cleanup would leak — verify _reset clears the list.
    input_mod.use_middleware(function() end)
    lt.assertEquals(#input_mod._middleware_list(), 1)
    input_mod._reset()
    lt.assertEquals(#input_mod._middleware_list(), 0)
end

return suite
