-- tui/text.lua — text measurement and soft-wrapping helpers.
--
-- Stage 4:
--   * iter(s)                : UTF-8 iterator yielding (char, width) pairs
--   * display_width(s)       : total display columns (alias to wcwidth.string_width)
--   * wrap(s, max_cols)      : soft-wrap to an array of line strings,
--                              breaking on whitespace when possible, otherwise
--                              at the last full-width boundary.
--
-- Stage 15: wrap is now a delegate to `tui_core.text.wrap`. The C version
-- uses the same grapheme-aware algorithm as the old Lua impl but avoids
-- the C→Lua→C per-cluster round trip.

local tui_core = require "tui_core"
local wcwidth  = tui_core.wcwidth
local text_c   = tui_core.text

local M = {}

-- UTF-8 iterator over (char, width) pairs, walking grapheme clusters so a
-- combining mark attaches to its base, ZWJ sequences fuse, VS16 promotes
-- width, RI pairs form a flag, and Hangul jamo L/V/T conjoin.
--
-- Width is already clamped to >=0 by grapheme_next (controls get 0). The
-- iterator does not drop clusters: callers that want to ignore width-0
-- glyphs can filter themselves (wrap() relies on "\n" being delivered so
-- it can flush the current line).
local function iter_chars(s)
    local n, i = #s, 1
    return function()
        if i > n then return nil end
        local ch, cw, ni = wcwidth.grapheme_next(s, i)
        if ch == "" then
            i = n + 1
            return nil
        end
        i = ni
        return ch, cw
    end
end
M.iter = iter_chars

function M.display_width(s)
    return wcwidth.string_width(s or "")
end

-- Wrap `s` to lines no wider than `max_cols`. Returns an array of strings.
-- Each line's display width is <= max_cols. A double-wide char that would
-- straddle the boundary is pushed to the next line.
function M.wrap(s, max_cols)
    return text_c.wrap(s or "", max_cols or 0)
end

return M
