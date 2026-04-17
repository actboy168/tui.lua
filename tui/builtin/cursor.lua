-- tui/builtin/cursor.lua — post-paint cursor + IME positioning.
--
-- A TextInput component (or any focusable element that wants a visible
-- cursor) calls cursor.set(col, row) during its render. tui/init.lua reads
-- this value AFTER writing the diff ANSI, then:
--   * if (col, row) is set: show cursor, move it to (col, row), call IME pos.
--   * if nil: hide cursor.
-- The value is cleared each paint so stale positions don't linger.

local M = {}

local pending_col, pending_row = nil, nil

function M.set(col, row)
    pending_col, pending_row = col, row
end

function M.consume()
    local c, r = pending_col, pending_row
    pending_col, pending_row = nil, nil
    return c, r
end

function M._peek()
    return pending_col, pending_row
end

return M
