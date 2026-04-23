-- tui/sgr.lua — map Text / Box style props to a style_id via the C-side
-- StylePool (screen_c.intern_style). The C layer stores one uint16 style_id
-- per cell; the pool resolves it to full 24-bit color + attrs at SGR-emit
-- time, with automatic downgrade to the screen's color_level.
--
-- Accepted color representations (both for `color` and `backgroundColor`):
--   - name: "black", "red", "green", "yellow", "blue", "magenta", "cyan",
--           "white", "gray" / "brightBlack", "brightRed", "brightGreen",
--           "brightYellow", "brightBlue", "brightMagenta", "brightCyan",
--           "brightWhite"
--   - integer 0..15   (16-color; backward compat)
--   - integer 16..255 (xterm 256-color)
--   - "#RRGGBB"       (24-bit truecolor)
--
-- Any unknown color name raises an error at render time — mistyped colors
-- should fail fast rather than silently render as default.

local screen_c = require "tui.core".screen

local M = {}

-- Color mode constants — must stay in sync with tui_screen.c.
local <const> COLOR_MODE_DEFAULT = 0
local <const> COLOR_MODE_16      = 1
local <const> COLOR_MODE_256     = 2
local <const> COLOR_MODE_24BIT   = 3

-- Canonical ANSI 16-color name → index 0..15.
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

-- Resolve a color spec to (mode, val).
-- Returns (COLOR_MODE_DEFAULT, 0) for nil input.
local function resolve_color(name_or_int, which)
    if name_or_int == nil then return COLOR_MODE_DEFAULT, 0 end
    if type(name_or_int) == "number" then
        local n = name_or_int
        if n ~= math.floor(n) or n < 0 or n > 255 then
            error(("tui.sgr: %s must be integer 0..255, got %s"):format(
                which, tostring(name_or_int)), 3)
        end
        if n <= 15 then return COLOR_MODE_16, n
        else             return COLOR_MODE_256, n end
    elseif type(name_or_int) == "string" then
        -- "#RRGGBB" hex truecolor
        local r, g, b = name_or_int:match("^#(%x%x)(%x%x)(%x%x)$")
        if r then
            local val = tonumber(r, 16) * 0x10000
                      + tonumber(g, 16) * 0x100
                      + tonumber(b, 16)
            return COLOR_MODE_24BIT, val
        end
        local nib = COLORS[name_or_int]
        if nib then return COLOR_MODE_16, nib end
        error(("tui.sgr: unknown color name for %s: %q"):format(
            which, name_or_int), 3)
    else
        error(("tui.sgr: %s must be string or integer, got %s"):format(
            which, type(name_or_int)), 3)
    end
end

-- Attribute bits — must stay in lock-step with src/tui_core/tui_screen.c.
local <const> ATTR_BOLD          = 0x01
local <const> ATTR_DIM           = 0x02
local <const> ATTR_UNDERLINE     = 0x04
local <const> ATTR_INVERSE       = 0x08
local <const> ATTR_ITALIC        = 0x40
local <const> ATTR_STRIKETHROUGH = 0x80

--- pack_style(screen_ud, props) -> style_id:uint16
-- Translates element props into a style_id by interning into the screen's
-- StylePool. Returns 0 (terminal default) when props carry no styling.
function M.pack_style(screen_ud, props)
    if not props then return 0 end
    local color       = props.dimColor or props.color
    local bg          = props.backgroundColor
    local bold        = props.bold
    local dim         = (props.dimColor ~= nil) or props.dim
    local underline   = props.underline
    local inverse     = props.inverse
    local italic      = props.italic
    local strikethrough = props.strikethrough

    if color == nil and bg == nil
        and not bold and not dim and not underline and not inverse
        and not italic and not strikethrough
    then
        return 0
    end

    local fg_mode, fg_val = resolve_color(color, "color")
    local bg_mode, bg_val = resolve_color(bg, "backgroundColor")

    local attrs = 0
    if bold        then attrs = attrs | ATTR_BOLD          end
    if dim         then attrs = attrs | ATTR_DIM           end
    if underline   then attrs = attrs | ATTR_UNDERLINE     end
    if inverse     then attrs = attrs | ATTR_INVERSE       end
    if italic      then attrs = attrs | ATTR_ITALIC        end
    if strikethrough then attrs = attrs | ATTR_STRIKETHROUGH end

    return screen_c.intern_style(screen_ud, fg_mode, fg_val, bg_mode, bg_val, attrs)
end

--- pack_border_style(screen_ud, props) -> style_id:uint16
-- Like pack_style but applies border-specific color overrides inline
-- (borderColor / borderDimColor take precedence over color).
function M.pack_border_style(screen_ud, props)
    if not props then return 0 end
    local color       = props.borderDimColor or props.borderColor or props.color
    local dim         = (props.borderDimColor ~= nil) or props.dim
    local bg          = props.backgroundColor
    local bold        = props.bold
    local underline   = props.underline
    local inverse     = props.inverse
    local italic      = props.italic
    local strikethrough = props.strikethrough

    if color == nil and bg == nil
        and not bold and not dim and not underline and not inverse
        and not italic and not strikethrough
    then
        return 0
    end

    local fg_mode, fg_val = resolve_color(color, "color")
    local bg_mode, bg_val = resolve_color(bg, "backgroundColor")

    local attrs = 0
    if bold        then attrs = attrs | ATTR_BOLD          end
    if dim         then attrs = attrs | ATTR_DIM           end
    if underline   then attrs = attrs | ATTR_UNDERLINE     end
    if inverse     then attrs = attrs | ATTR_INVERSE       end
    if italic      then attrs = attrs | ATTR_ITALIC        end
    if strikethrough then attrs = attrs | ATTR_STRIKETHROUGH end

    return screen_c.intern_style(screen_ud, fg_mode, fg_val, bg_mode, bg_val, attrs)
end

return M
