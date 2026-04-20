-- tui/bus.lua — generic subscription bus factory.
--
-- Extracts the "subscriber table + dispatch-with-snapshot" pattern that was
-- duplicated across tui.input (broadcast channel) and tui.resize.
--
-- Usage:
--   local bus = require "tui.internal.bus"
--   local b = bus.new()
--
--   local unsub = b.subscribe(fn)   -- register; returns unsubscribe closure
--   b.dispatch(...)                 -- call all live handlers (snapshot-safe)
--   b._handlers()                   -- introspection: returns handler table
--   b._reset()                      -- clear all handlers (teardown / tests)

local M = {}

function M.new()
    local handlers = {}
    local b = {}

    function b.subscribe(fn)
        handlers[#handlers + 1] = fn
        local active = true
        return function()
            if not active then return end
            active = false
            for i = #handlers, 1, -1 do
                if handlers[i] == fn then
                    table.remove(handlers, i)
                    break
                end
            end
        end
    end

    -- Dispatch takes a snapshot before iterating so mid-dispatch unsubscribes
    -- do not skew iteration (matches the manual pattern it replaces).
    function b.dispatch(...)
        local snapshot = {}
        for i, f in ipairs(handlers) do snapshot[i] = f end
        for _, f in ipairs(snapshot) do f(...) end
    end

    function b._handlers() return handlers end
    function b._reset() handlers = {} end

    return b
end

return M
