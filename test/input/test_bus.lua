-- test/input/test_bus.lua — unit tests for tui.bus (make_subscription_bus).

local lt  = require "ltest"
local bus = require "tui.bus"

local suite = lt.test "bus"

-- Basic dispatch reaches registered handler.
function suite:test_dispatch_calls_handler()
    local b = bus.new()
    local got = {}
    b.subscribe(function(v) got[#got + 1] = v end)
    b.dispatch(42)
    lt.assertEquals(got, { 42 })
end

-- Multiple handlers all receive the event.
function suite:test_dispatch_multiple_handlers()
    local b = bus.new()
    local calls = 0
    b.subscribe(function() calls = calls + 1 end)
    b.subscribe(function() calls = calls + 1 end)
    b.dispatch()
    lt.assertEquals(calls, 2)
end

-- Variadic args are forwarded.
function suite:test_dispatch_variadic()
    local b = bus.new()
    local a, c = nil, nil
    b.subscribe(function(x, y) a = x; c = y end)
    b.dispatch("hello", "world")
    lt.assertEquals(a, "hello")
    lt.assertEquals(c, "world")
end

-- Unsubscribe removes handler.
function suite:test_unsubscribe_removes_handler()
    local b = bus.new()
    local calls = 0
    local unsub = b.subscribe(function() calls = calls + 1 end)
    b.dispatch()
    lt.assertEquals(calls, 1)
    unsub()
    b.dispatch()
    lt.assertEquals(calls, 1)   -- not called again
end

-- Double-unsubscribe is harmless.
function suite:test_double_unsubscribe_is_noop()
    local b = bus.new()
    local calls = 0
    local unsub = b.subscribe(function() calls = calls + 1 end)
    unsub()
    unsub()   -- should not error
    b.dispatch()
    lt.assertEquals(calls, 0)
end

-- Handler can safely unsubscribe itself during dispatch (snapshot safety).
function suite:test_unsubscribe_during_dispatch()
    local b = bus.new()
    local calls = 0
    local unsub
    unsub = b.subscribe(function()
        calls = calls + 1
        unsub()     -- removes self mid-dispatch
    end)
    b.dispatch()    -- should not error
    b.dispatch()    -- handler is gone; call count stays at 1
    lt.assertEquals(calls, 1)
end

-- _handlers() returns the live handler list.
function suite:test_handlers_introspection()
    local b = bus.new()
    local fn = function() end
    b.subscribe(fn)
    local h = b._handlers()
    lt.assertEquals(#h, 1)
    lt.assertEquals(h[1], fn)
end

-- _reset() clears all handlers.
function suite:test_reset_clears_handlers()
    local b = bus.new()
    local calls = 0
    b.subscribe(function() calls = calls + 1 end)
    b._reset()
    b.dispatch()
    lt.assertEquals(calls, 0)
    lt.assertEquals(#b._handlers(), 0)
end

-- Two bus instances are fully independent.
function suite:test_buses_are_independent()
    local b1 = bus.new()
    local b2 = bus.new()
    local c1, c2 = 0, 0
    b1.subscribe(function() c1 = c1 + 1 end)
    b2.subscribe(function() c2 = c2 + 1 end)
    b1.dispatch()
    lt.assertEquals(c1, 1)
    lt.assertEquals(c2, 0)
    b2.dispatch()
    lt.assertEquals(c1, 1)
    lt.assertEquals(c2, 1)
end
