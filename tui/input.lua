-- tui/input.lua — input dispatcher for tui.lua.
--
-- Responsibilities:
--   * maintain a list of currently subscribed useInput handlers
--   * parse raw byte batches (from terminal.read_raw) via tui_core.keys.parse
--   * broadcast each resulting event to every subscriber (Stage 3 has no focus)
--
-- Subscribers register with `subscribe(handler)`; they get back an
-- unsubscribe function. Hooks use this in a useEffect cleanup to tear down
-- on unmount (or on handler identity change).

local tui_core = require "tui_core"
local keys     = tui_core.keys

local M = {}

-- Array of active handlers. Order is registration order, but dispatch to
-- everyone — order isn't observable yet.
local handlers = {}

--- subscribe(fn) -> unsubscribe(fn)
-- `fn` will be called as fn(input_str, key) for each parsed event.
function M.subscribe(fn)
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

--- dispatch(bytes) - parse and broadcast.
function M.dispatch(bytes)
    if not bytes or #bytes == 0 then return end
    local events = keys.parse(bytes)
    for _, ev in ipairs(events) do
        -- Snapshot handlers so that a handler unsubscribing mid-dispatch
        -- doesn't skew iteration.
        local snapshot = {}
        for i, h in ipairs(handlers) do snapshot[i] = h end
        for _, h in ipairs(snapshot) do
            -- React/Ink-compatible signature: handler(input, key).
            h(ev.input or "", ev)
        end
    end
end

-- Introspection for tests.
function M._handlers() return handlers end
function M._reset()   handlers = {} end

return M
