-- tui/screen.lua — double-buffered screen with row-level diffing.
--
-- Stage 2: track previous frame's rows; on new frame, emit ANSI only for
-- changed rows. If dimensions change, do a full redraw.
--
-- NOTE: Cell-level diff is Stage 6 (plan S2.5). Row-level is good enough to
-- keep the counter demo flicker-free because only the line holding the number
-- changes each tick.

local M = {}

-- Build a fresh screen state.
-- Caller is expected to hold one per tui.render() invocation.
function M.new()
    return {
        prev_rows = nil,   -- array of strings, or nil before first frame
        prev_w    = 0,
        prev_h    = 0,
    }
end

-- Compose ANSI diff between prev_rows and new_rows of the same dimensions.
-- If prev is nil or size mismatched, return a full redraw.
function M.diff(state, new_rows, w, h)
    local parts = {}

    if state.prev_rows == nil or state.prev_w ~= w or state.prev_h ~= h then
        -- Full redraw: home, clear, then every row.
        parts[#parts + 1] = "\27[H\27[2J"
        for y = 1, h do
            parts[#parts + 1] = "\27[" .. y .. ";1H"
            parts[#parts + 1] = new_rows[y] or ""
        end
    else
        for y = 1, h do
            if new_rows[y] ~= state.prev_rows[y] then
                -- Move to row y, column 1; clear the line; write new content.
                parts[#parts + 1] = "\27[" .. y .. ";1H\27[2K"
                parts[#parts + 1] = new_rows[y] or ""
            end
        end
    end

    -- Copy new_rows into state for next diff.
    local snapshot = {}
    for y = 1, h do snapshot[y] = new_rows[y] end
    state.prev_rows = snapshot
    state.prev_w    = w
    state.prev_h    = h

    return table.concat(parts)
end

-- Clear diff state (e.g. after terminal resize or manual refresh).
function M.invalidate(state)
    state.prev_rows = nil
    state.prev_w    = 0
    state.prev_h    = 0
end

return M
