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
--  force_clear: optional boolean; when true, force a full clear+redraw (used
--  for resize in main-screen mode).
function M.diff(ud, force_clear, content_h)
    return screen_c.diff(ud, force_clear, content_h)
end

--- Return an array of H row strings. Strings are backed by a ring pool;
--  they remain valid for 3 subsequent rows() calls before being recycled.
--  Test harness / snapshot callers finish reading within one frame and are
--  safe.
function M.rows(ud)
    return screen_c.rows(ud)
end

--- Set the rendering mode: "main" (relative moves + cursor restore) or
--  "alt" (CUP-based, default). Resets virtual cursor state.
function M.set_mode(ud, mode)
    screen_c.set_mode(ud, mode)
end

--- Return (x, y) — the virtual cursor position after the last cursor_restore
--  (0-based). Used by init.lua to compute the TextInput cursor offset.
function M.cursor_pos(ud)
    return screen_c.cursor_pos(ud)
end

--- Record where the TextInput cursor was placed (0-based).
--  Call with x=-1, y=-1 to clear (no declared cursor).
function M.set_display_cursor(ud, x, y)
    screen_c.set_display_cursor(ud, x, y)
end

--- Return an array of styled cell tables for the given 1-based row.
-- Each entry: {char, width, bold, dim, underline, inverse, italic,
--              strikethrough, fg, bg}.  Wide-tail slots are omitted.
-- Attr fields are booleans (true/false). fg/bg: nil=default, integer=16/256-color,
-- string "#RRGGBB"=24-bit truecolor.
function M.cells(ud, row)
    return screen_c.cells(ud, row)
end

return M
