-- tui/renderer.lua — rasterize laid-out elements into a cell buffer
-- and flush as a single ANSI string.
--
-- Stage 1: no diffing, no color, no wrapping — just draw the whole screen
-- each time. Box borders supported. CJK/emoji width handling is Stage 4.

local M = {}

-- Box-drawing glyphs. Keyed by style name.
local BORDERS = {
    single = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" },
    double = { tl = "╔", tr = "╗", bl = "╚", br = "╝", h = "═", v = "║" },
    round  = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
}

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

local function put(buf, x, y, ch)
    -- 0-based (x,y) from yoga → 1-based buffer coords.
    local cy = y + 1
    local cx = x + 1
    if cy < 1 or cy > buf.h then return end
    if cx < 1 or cx > buf.w then return end
    buf[cy][cx] = ch
end

local function draw_border(buf, x, y, w, h, style)
    local g = BORDERS[style] or BORDERS.single
    if w < 2 or h < 2 then return end
    -- corners
    put(buf, x,         y,         g.tl)
    put(buf, x + w - 1, y,         g.tr)
    put(buf, x,         y + h - 1, g.bl)
    put(buf, x + w - 1, y + h - 1, g.br)
    -- horizontal edges
    for i = 1, w - 2 do
        put(buf, x + i, y,         g.h)
        put(buf, x + i, y + h - 1, g.h)
    end
    -- vertical edges
    for i = 1, h - 2 do
        put(buf, x,         y + i, g.v)
        put(buf, x + w - 1, y + i, g.v)
    end
end

-- UTF-8 safe iteration over characters of a string.
local function iter_utf8(s)
    local i, n = 1, #s
    return function()
        if i > n then return nil end
        local b = s:byte(i)
        local size
        if b < 0x80 then size = 1
        elseif b < 0xE0 then size = 2
        elseif b < 0xF0 then size = 3
        else size = 4 end
        local ch = s:sub(i, i + size - 1)
        i = i + size
        return ch
    end
end

local function draw_text(buf, x, y, text)
    local cx = x
    for ch in iter_utf8(text) do
        put(buf, cx, y, ch)
        cx = cx + 1
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
        draw_text(buf, r.x, r.y, element.text or "")
    end
end

-- Serialize buffer to ANSI: move to home, then write each row followed by CRLF.
local function buffer_to_ansi(buf)
    local parts = { "\27[H" }  -- cursor home
    for y = 1, buf.h do
        parts[#parts + 1] = table.concat(buf[y])
        if y < buf.h then
            parts[#parts + 1] = "\r\n"
        end
    end
    return table.concat(parts)
end

--- Render element tree into a fresh buffer of size (w, h) and return an ANSI string.
function M.render(element, w, h)
    local buf = new_buffer(w, h)
    paint(element, buf)
    return buffer_to_ansi(buf)
end

return M
