-- tui/renderer.lua — rasterize laid-out elements into a cell buffer
-- and flush as a single ANSI string.
--
-- Stage 4:
--   * wcwidth-aware drawing: double-wide chars occupy two cells; the cell
--     immediately to the right is marked with "" (empty string) so that it
--     is skipped during row concatenation — the terminal itself advances
--     two columns for the wide char.
--   * Multi-line text via element.lines (populated by tui/layout readback
--     when the text node has soft-wrap enabled).

local tui_core = require "tui_core"
local wcwidth  = tui_core.wcwidth

local M = {}

-- Box-drawing glyphs. Keyed by style name.
local BORDERS = {
    single = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" },
    double = { tl = "╔", tr = "╗", bl = "╚", br = "╝", h = "═", v = "║" },
    round  = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
}

-- Sentinel marking the right half of a wide character. table.concat skips it
-- because it's the empty string, while its presence prevents put() from
-- overwriting the right half with a later draw.
local WIDE_TAIL = ""

-- Allocate a 2-D cell buffer [row][col] filled with spaces.
local function new_buffer(w, h)
    local buf = { w = w, h = h }
    for y = 1, h do
        local row = {}
        for x = 1, w do
            row[x] = " "
        end
        buf[y] = row
    end
    return buf
end

-- Put a single character (1 or 2 columns wide) at (x,y). 0-based to match yoga.
-- Returns the number of columns actually consumed.
local function put(buf, x, y, ch, cw)
    local cy = y + 1
    local cx = x + 1
    if cy < 1 or cy > buf.h then return cw end
    if cx < 1 or cx > buf.w then return cw end
    if cw == 2 then
        -- Need two adjacent cells in-bounds; otherwise downgrade to a space.
        if cx + 1 > buf.w then
            buf[cy][cx] = " "
            return 1
        end
        buf[cy][cx]     = ch
        buf[cy][cx + 1] = WIDE_TAIL
    else
        buf[cy][cx] = ch
    end
    return cw
end

local function draw_border(buf, x, y, w, h, style)
    local g = BORDERS[style] or BORDERS.single
    if w < 2 or h < 2 then return end
    put(buf, x,         y,         g.tl, 1)
    put(buf, x + w - 1, y,         g.tr, 1)
    put(buf, x,         y + h - 1, g.bl, 1)
    put(buf, x + w - 1, y + h - 1, g.br, 1)
    for i = 1, w - 2 do
        put(buf, x + i, y,         g.h, 1)
        put(buf, x + i, y + h - 1, g.h, 1)
    end
    for i = 1, h - 2 do
        put(buf, x,         y + i, g.v, 1)
        put(buf, x + w - 1, y + i, g.v, 1)
    end
end

-- Draw one logical line of text at (x,y) within max_w cells. Handles double-
-- wide chars and skips controls.
local function draw_line(buf, x, y, text, max_w)
    if not text or text == "" then return end
    local cx = x
    local stop = x + (max_w or buf.w)
    local i, n = 1, #text
    while i <= n do
        local cw, ni = wcwidth.char_width(text, i)
        local ch = text:sub(i, ni - 1)
        i = ni
        if cw == 0 then
            -- Skip combining / control chars (they'd misalign cells).
        else
            if cx + cw > stop then break end
            put(buf, cx, y, ch, cw)
            cx = cx + cw
        end
    end
end

-- Walk the element tree and paint into buf.
local function paint(element, buf)
    local r = element.rect
    if not r then return end
    if element.kind == "box" then
        local border = element.props and element.props.border
        if border then
            draw_border(buf, r.x, r.y, r.w, r.h, border)
        end
        for _, child in ipairs(element.children or {}) do
            paint(child, buf)
        end
    elseif element.kind == "text" then
        if element.lines then
            for li, line in ipairs(element.lines) do
                if r.y + (li - 1) >= r.y + r.h then break end
                draw_line(buf, r.x, r.y + (li - 1), line, r.w)
            end
        else
            draw_line(buf, r.x, r.y, element.text or "", r.w)
        end
    end
end

-- Serialize buffer to ANSI: move to home, then write each row followed by CRLF.
local function buffer_to_ansi(buf)
    local parts = { "\27[H" }
    for y = 1, buf.h do
        parts[#parts + 1] = table.concat(buf[y])
        if y < buf.h then
            parts[#parts + 1] = "\r\n"
        end
    end
    return table.concat(parts)
end

-- Serialize buffer to an array of row strings (for row-level diff).
local function buffer_to_rows(buf)
    local rows = {}
    for y = 1, buf.h do
        rows[y] = table.concat(buf[y])
    end
    return rows
end

--- Render element tree into a fresh buffer of size (w, h) and return an ANSI string.
function M.render(element, w, h)
    local buf = new_buffer(w, h)
    paint(element, buf)
    return buffer_to_ansi(buf)
end

--- Render element tree into a fresh buffer and return (rows, w, h).
function M.render_rows(element, w, h)
    local buf = new_buffer(w, h)
    paint(element, buf)
    return buffer_to_rows(buf), w, h
end

return M
