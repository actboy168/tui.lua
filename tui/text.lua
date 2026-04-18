-- tui/text.lua — text measurement and soft-wrapping helpers.
--
-- Stage 4:
--   * iter(s)                : UTF-8 iterator yielding (char, width) pairs
--   * display_width(s)       : total display columns (alias to wcwidth.string_width)
--   * wrap(s, max_cols)      : soft-wrap to an array of line strings,
--                              breaking on whitespace when possible, otherwise
--                              at the last full-width boundary.
--
-- The wrap algorithm is deliberately simple (Knuth-Plass overkill for a TUI):
--   scan chars, accumulate into a current line until adding the next char
--   would exceed max_cols; remember the last whitespace position so we can
--   back up to it. Hard line breaks (\n) always split.

local tui_core = require "tui_core"
local wcwidth  = tui_core.wcwidth

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
        if ch == "" then i = n + 1; return nil end
        i = ni
        return ch, cw
    end
end
M.iter = iter_chars

function M.display_width(s)
    return wcwidth.string_width(s or "")
end

local function is_space(ch)
    return ch == " " or ch == "\t"
end

-- Wrap `s` to lines no wider than `max_cols`. Returns an array of strings.
-- Each line's display width is <= max_cols. A double-wide char that would
-- straddle the boundary is pushed to the next line.
function M.wrap(s, max_cols)
    if not s or s == "" then return { "" } end
    if not max_cols or max_cols <= 0 then return { s } end

    local lines = {}
    local line  = {}       -- array of chars on current line
    local col   = 0        -- current display column
    local last_space_idx = nil  -- index into `line` where we can break
    local last_space_col = 0    -- column AFTER the space

    local function flush(include_trailing_space)
        -- Drop a single trailing space if we broke on it (mimics typical wrap).
        local n = #line
        if not include_trailing_space and n > 0 and is_space(line[n]) then
            line[n] = nil
        end
        lines[#lines + 1] = table.concat(line)
        line = {}
        col  = 0
        last_space_idx = nil
        last_space_col = 0
    end

    for ch, cw in iter_chars(s) do
        if ch == "\n" then
            flush(true)
        else
            -- Track the last whitespace boundary so we can back-up on overflow.
            if is_space(ch) then
                last_space_idx = #line + 1   -- this char's position-to-be
                last_space_col = col + cw    -- column after consuming this space
            end

            if col + cw > max_cols then
                if last_space_idx and last_space_idx > 1 then
                    -- Break at the last whitespace: everything up to but not
                    -- including last_space_idx becomes a line, the remainder
                    -- (after the space) becomes the start of the next line.
                    local head = {}
                    for k = 1, last_space_idx - 1 do head[k] = line[k] end
                    -- Trim trailing space on head.
                    if #head > 0 and is_space(head[#head]) then head[#head] = nil end
                    lines[#lines + 1] = table.concat(head)

                    local tail = {}
                    for k = last_space_idx + 1, #line do
                        tail[#tail + 1] = line[k]
                    end
                    line = tail
                    -- Recompute col for tail.
                    col = 0
                    for _, c in ipairs(line) do
                        local _, w = iter_chars(c)()
                        col = col + (w or 0)
                    end
                    last_space_idx = nil
                    last_space_col = 0
                else
                    -- Hard break: no whitespace available.
                    flush(true)
                end
            end

            line[#line + 1] = ch
            col = col + cw
        end
    end

    -- Final line (even if empty, keep it so callers see at least one row).
    lines[#lines + 1] = table.concat(line)
    return lines
end

return M
