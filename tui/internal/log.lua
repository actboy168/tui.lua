-- tui/internal/log.lua — global latest-log store for the implicit bottom log bar.

local bus_mod = require "tui.internal.bus"

local M = {}

local bus = bus_mod.new()
local latest

local function normalize_piece(v)
    local s = tostring(v)
    s = s:gsub("\r\n", " ")
    s = s:gsub("[\r\n\t]", " ")
    return s
end

local function format_message(...)
    local n = select("#", ...)
    if n == 0 then return nil end
    local parts = {}
    for i = 1, n do
        parts[i] = normalize_piece(select(i, ...))
    end
    local message = table.concat(parts, " ")
    if #message == 0 then return nil end
    return message
end

function M.append(...)
    latest = format_message(...)
    bus.dispatch(latest)
end

function M.peek()
    return latest
end

function M.subscribe(fn)
    return bus.subscribe(fn)
end

function M._reset()
    latest = nil
    bus._reset()
end

return M
