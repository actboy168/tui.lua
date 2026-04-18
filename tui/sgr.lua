-- tui/sgr.lua — map Text / Box style props to the style table that
-- tui_core.screen APIs understand.
--
-- The C layer accepts `{ fg, bg, bold, dim, underline, inverse }` where
-- fg / bg are integers 0..15 (ANSI 16-color) and the rest are booleans.
-- This module translates user-facing props into that shape.
--
-- Accepted color representations (both for `color` and `backgroundColor`):
--   - name: "black", "red", "green", "yellow", "blue", "magenta", "cyan",
--           "white", "gray" / "brightBlack", "brightRed", "brightGreen",
--           "brightYellow", "brightBlue", "brightMagenta", "brightCyan",
--           "brightWhite"
--   - integer 0..15 (normal 0..7, bright 8..15)
--
-- Any unknown color name raises an error at render time — mistyped colors
-- should fail fast rather than silently render as default.

local M = {}

-- Canonical ANSI 16-color name → nibble 0..15.
local COLORS = {
    black         = 0,
    red           = 1,
    green         = 2,
    yellow        = 3,
    blue          = 4,
    magenta       = 5,
    cyan          = 6,
    white         = 7,
    gray          = 8,
    grey          = 8,   -- common alt spelling
    brightBlack   = 8,
    brightRed     = 9,
    brightGreen   = 10,
    brightYellow  = 11,
    brightBlue    = 12,
    brightMagenta = 13,
    brightCyan    = 14,
    brightWhite   = 15,
}

M.COLORS = COLORS

local function resolve_color(name_or_int, which)
    if name_or_int == nil then return nil end
    if type(name_or_int) == "number" then
        local n = name_or_int
        if n ~= math.floor(n) or n < 0 or n > 15 then
            error(("tui.sgr: %s must be integer 0..15, got %s"):format(
                which, tostring(name_or_int)), 3)
        end
        return n
    elseif type(name_or_int) == "string" then
        local nib = COLORS[name_or_int]
        if not nib then
            error(("tui.sgr: unknown color name for %s: %q"):format(
                which, name_or_int), 3)
        end
        return nib
    else
        error(("tui.sgr: %s must be string or integer, got %s"):format(
            which, type(name_or_int)), 3)
    end
end

--- pack_props(props) -> style_table_or_nil
-- Extract styling from element props. Returns nil if no styling applies so
-- the caller can skip passing a style table to the C layer entirely (saves
-- a table alloc per cell-heavy frame).
function M.pack_props(props)
    if not props then return nil end
    local color     = props.color
    local bg        = props.backgroundColor
    local bold      = props.bold
    local dim       = props.dim
    local underline = props.underline
    local inverse   = props.inverse

    if color == nil and bg == nil
        and not bold and not dim and not underline and not inverse
    then
        return nil
    end

    return {
        fg        = resolve_color(color, "color"),
        bg        = resolve_color(bg, "backgroundColor"),
        bold      = bold and true or nil,
        dim       = dim and true or nil,
        underline = underline and true or nil,
        inverse   = inverse and true or nil,
    }
end

return M
