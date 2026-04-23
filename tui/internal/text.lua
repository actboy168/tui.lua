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

local tui_core = require "tui.core"
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
M.iterChars = iter_chars

function M.display_width(s)
    return wcwidth.string_width(s or "")
end

-- Wrap `s` to lines no wider than `max_cols`. Returns an array of strings.
-- Each line's display width is <= max_cols. A double-wide char that would
-- straddle the boundary is pushed to the next line.
M.wrap = text_c.wrap

-- Hard-wrap `s` at column boundaries (no whitespace detection).
-- Returns an array of line strings.
M.wrap_hard = text_c.wrap_hard

--- wrap_runs(runs, max_cols) -> line_runs
-- Soft-wrap a sequence of {text=str, props=?} runs to fit within max_cols
-- columns.  Returns an array of "line run arrays"; each element is itself an
-- array of {text=str, props=?} segments.
--
-- Word-wrap semantics match M.wrap(): break on whitespace when possible,
-- place an overlong word on its own line (overflow) as a last resort.
-- Trailing spaces at break boundaries are not included in either line.
function M.wrap_runs(runs, max_cols)
    if not runs or #runs == 0 then return {{}} end
    if max_cols <= 0 then return {{}} end

    local grapheme_next = wcwidth.grapheme_next

    local result   = {}     -- array of completed lines
    local cur_segs = {}     -- current line: array of {text, props}
    local cur_w    = 0      -- display width of current line

    local pword   = {}      -- pending word: array of {text, props}
    local pword_w = 0       -- display width of pending word

    -- Append `text/props` to an array of segments, merging with the last
    -- segment when props are identical.
    local function seg_push(arr, text, props)
        if text == "" then return end
        local n = #arr
        if n > 0 and arr[n].props == props then
            arr[n] = { text = arr[n].text .. text, props = props }
        else
            arr[n + 1] = { text = text, props = props }
        end
    end

    -- Commit the pending word to cur_segs (starting a new line when needed).
    local function flush()
        if pword_w == 0 then return end
        if cur_w > 0 and cur_w + pword_w > max_cols then
            result[#result + 1] = cur_segs
            cur_segs = {}
            cur_w    = 0
        end
        for _, wp in ipairs(pword) do
            seg_push(cur_segs, wp.text, wp.props)
        end
        cur_w   = cur_w + pword_w
        pword   = {}
        pword_w = 0
    end

    for _, run in ipairs(runs) do
        local text  = run.text or ""
        local props = run.props
        local i     = 1
        while i <= #text do
            local ch, cw, ni = grapheme_next(text, i)
            if ch == "" then break end
            i = ni
            if ch == "\n" then
                flush()
                result[#result + 1] = cur_segs
                cur_segs = {}
                cur_w    = 0
            elseif cw == 0 then
                -- Zero-width combining: attach to the pending word (or the
                -- current line if there is no pending word yet).
                if pword_w > 0 then
                    seg_push(pword, ch, props)
                else
                    seg_push(cur_segs, ch, props)
                end
            elseif ch:byte(1) <= 0x20 then
                -- ASCII whitespace: word boundary.
                flush()
                -- Keep one space on the line (drop at break boundaries).
                if cur_w > 0 and cur_w < max_cols then
                    seg_push(cur_segs, ch, props)
                    cur_w = cur_w + 1
                end
            else
                -- Regular printable grapheme: accumulate into pending word.
                seg_push(pword, ch, props)
                pword_w = pword_w + cw
            end
        end
    end

    flush()
    -- Always emit the trailing line (preserves single-line output for
    -- short/empty input, matching the behaviour of M.wrap()).
    result[#result + 1] = cur_segs
    return result
end

-- Truncate `s` from the end to fit within `max_cols` display columns.
-- If truncation occurs, replaces the excess with U+2026 (…).
M.truncate = text_c.truncate

-- Truncate `s` from the start; prepend U+2026 if truncation occurs.
M.truncate_start = text_c.truncate_start

-- Truncate `s` from the middle; insert U+2026 at the midpoint.
M.truncate_middle = text_c.truncate_middle

return M
