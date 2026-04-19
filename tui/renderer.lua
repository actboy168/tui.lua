-- tui/renderer.lua — paint the laid-out element tree into the C-side
-- screen cell buffer.
--
-- Stage 9: the cell buffer / diff / ANSI generation live in C (see
-- src/tui_core/screen.c). This module now just walks the element tree
-- and issues put / put_border / draw_line calls into that buffer.
-- Stage 15: style props are packed in Lua (tui/sgr.pack_bytes) into the
-- two bytes the C layer stores per cell; we pass (fg_bg, attrs) directly
-- instead of a style table so C never walks Lua tables during paint.
--
-- Color inheritance: `color` and `backgroundColor` on a Box propagate down
-- to all descendant Text nodes, mirroring Ink's CSS-style color context.
-- A child Text (or Box) that sets its own explicit color overrides the
-- inherited value for itself and its subtree.

local screen_c = require "tui_core".screen
local sgr      = require "tui.sgr"

local M = {}

-- Merge `color` / `backgroundColor` from `inherit` into `props` when the
-- child doesn't already set them. Returns `props` unchanged when there is
-- nothing to inherit, avoiding any table allocation on the common fast path.
local function effective_props(props, inherit)
    if not inherit then return props end
    local ic  = inherit.color
    local ibg = inherit.backgroundColor
    if not ic and not ibg then return props end
    local needs_color = ic  and not (props and (props.color or props.dimColor))
    local needs_bg    = ibg and not (props and props.backgroundColor)
    if not needs_color and not needs_bg then return props end
    local merged = {}
    if props then for k, v in pairs(props) do merged[k] = v end end
    if needs_color then merged.color           = ic  end
    if needs_bg    then merged.backgroundColor = ibg end
    return merged
end

-- Build the inherited color context that children will see.
-- Returns `inherit` unchanged when the box adds nothing new (avoids alloc).
local function child_inherit(props, inherit)
    if not props then return inherit end
    local c  = props.color or (inherit and inherit.color)
    local bg = props.backgroundColor or (inherit and inherit.backgroundColor)
    if c  == (inherit and inherit.color)
    and bg == (inherit and inherit.backgroundColor) then
        return inherit
    end
    return { color = c, backgroundColor = bg }
end

local function paint(element, screen, inherit)
    local r = element.rect
    if not r then return end
    if element.kind == "box" then
        local props = element.props
        local border_style = props and props.borderStyle
        if border_style then
            local fg_bg, attrs = sgr.pack_border_bytes(props)
            -- When the box overflows the screen vertically, clamp draw_h so
            -- the bottom border lands on the last visible row. Only apply
            -- when the clamped height still has room for both border rows
            -- (>= 2); otherwise keep r.h so OOB writes are dropped naturally
            -- by the C layer (top border chars still appear).
            local _, sh = screen_c.size(screen)
            local draw_h = r.h
            if r.y + r.h > sh then
                local clamped = sh - r.y
                if clamped >= 2 then draw_h = clamped end
            end
            screen_c.put_border(screen, r.x, r.y, r.w, draw_h, border_style,
                                fg_bg, attrs)
        end
        local ci = child_inherit(props, inherit)
        for _, ch in ipairs(element.children or {}) do
            paint(ch, screen, ci)
        end
    elseif element.kind == "text" then
        local props = effective_props(element.props, inherit)
        local fg_bg, attrs = sgr.pack_bytes(props)
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
    paint(element, screen, nil)
end

return M
