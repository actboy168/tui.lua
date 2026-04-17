-- tui/resize.lua — terminal-resize event bus.
--
-- Stage 4: tui/init.lua polls terminal.get_size() each paint; when the
-- dimensions differ from the last observed pair, we fire subscribers.
-- useWindowSize (in hooks.lua) subscribes here to drive re-renders.

local M = {}

local subs = {}
local last_w, last_h = nil, nil

function M.subscribe(fn)
    subs[#subs + 1] = fn
    local active = true
    return function()
        if not active then return end
        active = false
        for i = #subs, 1, -1 do
            if subs[i] == fn then table.remove(subs, i); break end
        end
    end
end

function M.observe(w, h)
    if last_w == w and last_h == h then return false end
    last_w, last_h = w, h
    local snapshot = {}
    for i, f in ipairs(subs) do snapshot[i] = f end
    for _, f in ipairs(snapshot) do f(w, h) end
    return true
end

function M.current()
    return last_w, last_h
end

function M._reset()
    subs = {}
    last_w, last_h = nil, nil
end

return M
