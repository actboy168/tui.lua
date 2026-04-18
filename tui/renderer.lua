-- tui/renderer.lua — paint the laid-out element tree into the C-side
-- screen cell buffer.
--
-- Stage 9: the cell buffer / diff / ANSI generation live in C (see
-- src/tui_core/screen.c). This module now just walks the element tree
-- and issues put / put_border / draw_line calls into that buffer.
-- Stage 15: style props are packed in Lua (tui/sgr.pack_bytes) into the
-- two bytes the C layer stores per cell; we pass (fg_bg, attrs) directly
-- instead of a style table so C never walks Lua tables during paint.

local screen_c = require "tui_core".screen
local sgr      = require "tui.sgr"

local M = {}

-- Pack border-specific style props.
-- borderColor / borderDimColor take precedence over color / dim.
local function pack_border_style(props)
    if not props then return sgr.pack_bytes(nil) end

    -- Build effective style table for border
    local border_props = {
        color     = props.borderColor or props.color,
        backgroundColor = props.backgroundColor,
        bold      = props.bold,
        dim       = props.borderDimColor and true or props.dim,
        underline = props.underline,
        inverse   = props.inverse,
    }

    -- If borderDimColor is set, use it as color with dim
    if props.borderDimColor then
        border_props.color = props.borderDimColor
        border_props.dim = true
    end

    return sgr.pack_bytes(border_props)
end

local function paint(element, screen)
    local r = element.rect
    if not r then return end
    if element.kind == "box" then
        local props = element.props
        local border_style = props and props.borderStyle
        if border_style then
            local fg_bg, attrs = pack_border_style(props)
            screen_c.put_border(screen, r.x, r.y, r.w, r.h, border_style,
                                fg_bg, attrs)
        end
        for _, child in ipairs(element.children or {}) do
            paint(child, screen)
        end
    elseif element.kind == "text" then
        local fg_bg, attrs = sgr.pack_bytes(element.props)
        if element.lines then
            for li, line in ipairs(element.lines) do
                if li - 1 >= r.h then break end
                screen_c.draw_line(screen, r.x, r.y + (li - 1), line, r.w,
                                   fg_bg, attrs)
            end
        else
            screen_c.draw_line(screen, r.x, r.y, element.text or "", r.w,
                               fg_bg, attrs)
        end
    end
end

--- Paint element tree into the given C-owned screen. Caller is responsible
--  for screen_c.clear(...) beforehand and screen_c.diff(...) afterwards.
function M.paint(element, screen)
    paint(element, screen)
end

return M
