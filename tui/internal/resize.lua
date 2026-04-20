-- tui/resize.lua — terminal-resize event bus.
--
-- Stage 4: tui/init.lua polls terminal.get_size() each paint; when the
-- dimensions differ from the last observed pair, we fire subscribers.
-- useWindowSize (in hooks.lua) subscribes here to drive re-renders.

local bus_mod = require "tui.internal.bus"

local M = {}

local _bus = bus_mod.new()
local last_w, last_h = nil, nil

M.subscribe = _bus.subscribe

function M.observe(w, h)
    if last_w == w and last_h == h then return false end
    last_w, last_h = w, h
    _bus.dispatch(w, h)
    return true
end

function M.current()
    return last_w, last_h
end

function M._reset()
    _bus._reset()
    last_w, last_h = nil, nil
end

return M
