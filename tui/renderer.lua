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

local function paint(element, screen)
    local r = element.rect
    if not r then return end
    if element.kind == "box" then
        local props = element.props
        local border = props and props.border
        if border then
            local fg_bg, attrs = sgr.pack_bytes(props)
            screen_c.put_border(screen, r.x, r.y, r.w, r.h, border,
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
