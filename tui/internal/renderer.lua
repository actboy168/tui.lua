-- tui/renderer.lua — paint the laid-out element tree into the C-side
-- screen cell buffer.
--
-- Stage 9: the cell buffer / diff / ANSI generation live in C (see
-- src/tui_core/screen.c). This module now just walks the element tree
-- and issues put / put_border / draw_line calls into that buffer.
-- Stage 16 (Truecolor/StylePool): style props are interned into the C-side
-- StylePool via sgr.pack_style(screen, props) → style_id (uint16). The C
-- layer stores one style_id per cell and downgrades to the screen's
-- color_level at SGR-emit time.
--
-- Color inheritance: `color` and `backgroundColor` on a Box propagate down
-- to all descendant Text nodes, mirroring Ink's CSS-style color context.
-- A child Text (or Box) that sets its own explicit color overrides the
-- inherited value for itself and its subtree.

local screen_c = require "tui.core".screen
local sgr      = require "tui.internal.sgr"
local text_mod = require "tui.internal.text"

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

-- Merge base style props with span-level override props.
-- If the span sets `color` (but not `dimColor`), any inherited `dimColor` is
-- cleared so the span's plain color wins.
local function merge_span_props(base, span_props)
    local merged = {}
    if base then for k, v in pairs(base) do merged[k] = v end end
    for k, v in pairs(span_props) do merged[k] = v end
    if span_props.color ~= nil and span_props.dimColor == nil then
        merged.dimColor = nil
    end
    return merged
end

local function paint(element, screen, inherit, y_off)
    local r = element.rect
    if not r then return end
    local ry = r.y - y_off
    if element.kind == "box" then
        local props = element.props
        local border_style = props and props.borderStyle
        if border_style then
            local style_id = sgr.pack_border_style(screen, props)
            -- When the box overflows the screen vertically, clamp draw_h so
            -- the bottom border lands on the last visible row.
            local _, sh = screen_c.size(screen)
            local draw_h = r.h
            if ry + r.h > sh then
                local clamped = sh - ry
                if clamped >= 2 then draw_h = clamped end
            end
            screen_c.put_border(screen, r.x, ry, r.w, draw_h, border_style,
                                style_id)
        end
        local ci = child_inherit(props, inherit)
        for _, ch in ipairs(element.children or {}) do
            paint(ch, screen, ci, y_off)
        end
    elseif element.kind == "text" then
        local props = effective_props(element.props, inherit)
        if element.line_runs then
            -- Inline mixed styles: one pass per line, one draw_line per segment.
            local base_style_id = sgr.pack_style(screen, props)
            for li, segs in ipairs(element.line_runs) do
                if li - 1 >= r.h then break end
                local y = ry + (li - 1)
                -- Fill the whole line with the base style first (handles
                -- background colour and trailing space after the last segment).
                screen_c.draw_line(screen, r.x, y, "", r.w, base_style_id)
                local x_off = 0
                for _, seg in ipairs(segs) do
                    local seg_props
                    if seg.props then
                        seg_props = merge_span_props(props, seg.props)
                    else
                        seg_props = props
                    end
                    local style_id = sgr.pack_style(screen, seg_props)
                    local seg_w    = text_mod.display_width(seg.text)
                    screen_c.draw_line(screen, r.x + x_off, y, seg.text,
                                       seg_w, style_id)
                    x_off = x_off + seg_w
                end
            end
        elseif element.runs then
            local base_style_id = sgr.pack_style(screen, props)
            screen_c.draw_line(screen, r.x, ry, "", r.w, base_style_id)
            local x_off = 0
            for _, seg in ipairs(element.runs) do
                local seg_props
                if seg.props then
                    seg_props = merge_span_props(props, seg.props)
                else
                    seg_props = props
                end
                local style_id = sgr.pack_style(screen, seg_props)
                local seg_w    = text_mod.display_width(seg.text)
                screen_c.draw_line(screen, r.x + x_off, ry, seg.text, seg_w,
                                   style_id)
                x_off = x_off + seg_w
            end
        elseif element.lines then
            local style_id = sgr.pack_style(screen, props)
            for li, line in ipairs(element.lines) do
                if li - 1 >= r.h then break end
                screen_c.draw_line(screen, r.x, ry + (li - 1), line, r.w,
                                   style_id)
            end
        else
            local style_id = sgr.pack_style(screen, props)
            screen_c.draw_line(screen, r.x, ry, element.text or "", r.w,
                               style_id)
        end
    end
end

--- Paint element tree into the given C-owned screen. Caller is responsible
--  for screen_c.clear(...) beforehand and screen_c.diff(...) afterwards.
-- y_off: rows to skip from the top of the content tree (used when content
-- height exceeds the terminal height; the bottom content_h rows are rendered).
---@param element table
---@param screen userdata
---@param y_off integer|nil rows to skip from top (default 0)
function M.paint(element, screen, y_off)
    paint(element, screen, nil, y_off or 0)
end

return M
