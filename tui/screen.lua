-- tui/screen.lua — thin Lua wrapper over tui_core.screen.
--
-- Stage 9: all state (cell buffer / slab / ring pool) and the diff/ANSI
-- generation live in C. This wrapper exists only so existing call sites
-- (tui/init.lua, tui/testing.lua) can keep their `screen_mod.new / diff /
-- rows / ...` style instead of reaching into tui_core directly.

local screen_c = require "tui_core".screen

local M = {}

--- Create a fresh screen userdata with the given dimensions.
function M.new(w, h)
    return screen_c.new(w, h)
end

--- Return (w, h).
function M.size(ud)
    return screen_c.size(ud)
end

--- Resize in place. All row buffers are invalidated and next diff will
--  issue a full redraw.
function M.resize(ud, w, h)
    screen_c.resize(ud, w, h)
end

--- Force the next diff to be a full redraw.
function M.invalidate(ud)
    screen_c.invalidate(ud)
end

--- Clear the next-frame cell buffer (call at the start of each paint pass).
function M.clear(ud)
    screen_c.clear(ud)
end

--- Commit the next-frame buffer and return the ANSI bytes needed to update
--  the terminal from the previous committed frame. After this call, rows()
--  reads the just-committed frame.
function M.diff(ud)
    return screen_c.diff(ud)
end

--- Return an array of H row strings. Strings are backed by a ring pool;
--  they remain valid for 3 subsequent rows() calls before being recycled.
--  Test harness / snapshot callers finish reading within one frame and are
--  safe.
function M.rows(ud)
    return screen_c.rows(ud)
end

return M
