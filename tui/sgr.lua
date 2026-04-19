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
        return nil
    end

    return {
        fg           = resolve_color(color, "color"),
        bg           = resolve_color(bg, "backgroundColor"),
        bold         = bold and true or nil,
        dim          = dim and true or nil,
        underline    = underline and true or nil,
        inverse      = inverse and true or nil,
        italic       = italic and true or nil,
        strikethrough = strikethrough and true or nil,
    }
end

-- Attribute bits — must stay in lock-step with src/tui_core/screen.c.
-- The C layer consumes these two bytes unchanged; any mismatch shows up as
-- wrong SGR output and the test suite fails loudly.
local <const> ATTR_BOLD          = 0x01
local <const> ATTR_DIM           = 0x02
local <const> ATTR_UNDERLINE     = 0x04
local <const> ATTR_INVERSE       = 0x08
local <const> ATTR_FG_DEFAULT    = 0x10
local <const> ATTR_BG_DEFAULT    = 0x20
local <const> ATTR_ITALIC        = 0x40
local <const> ATTR_STRIKETHROUGH = 0x80
local <const> ATTR_DEFAULT       = ATTR_FG_DEFAULT | ATTR_BG_DEFAULT

--- pack_bytes(props) -> fg_bg:uint8, attrs:uint8
-- Packs element props directly into the two style bytes the C cell format
-- uses (fg_bg: high nibble fg, low nibble bg; attrs bitmask). Returns
-- (0, ATTR_DEFAULT) when props omit all styling so cells stay in the
-- terminal-default state.
function M.pack_bytes(props)
    if not props then return 0, ATTR_DEFAULT end
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
        return 0, ATTR_DEFAULT
    end

    local attrs = ATTR_DEFAULT
    local fg_nib, bg_nib = 0, 0
    if color ~= nil then
        fg_nib = resolve_color(color, "color")
        attrs = attrs & ~ATTR_FG_DEFAULT
    end
    if bg ~= nil then
        bg_nib = resolve_color(bg, "backgroundColor")
        attrs = attrs & ~ATTR_BG_DEFAULT
    end
    if bold        then attrs = attrs | ATTR_BOLD          end
    if dim         then attrs = attrs | ATTR_DIM           end
    if underline   then attrs = attrs | ATTR_UNDERLINE     end
    if inverse     then attrs = attrs | ATTR_INVERSE       end
    if italic      then attrs = attrs | ATTR_ITALIC        end
    if strikethrough then attrs = attrs | ATTR_STRIKETHROUGH end

    return ((fg_nib << 4) | (bg_nib & 0xF)) & 0xFF, attrs & 0xFF
end

--- pack_border_bytes(props) -> fg_bg:uint8, attrs:uint8
-- Like pack_bytes but applies border-specific color overrides inline.
-- Eliminates the temporary border_props table that renderer.lua used to build.
-- Future StylePool: add _border_cache lookup here before the computation.
function M.pack_border_bytes(props)
    if not props then return 0, ATTR_DEFAULT end
    -- borderDimColor: overrides color and forces dim.
    -- borderColor: overrides color only.
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
        return 0, ATTR_DEFAULT
    end

    local attrs = ATTR_DEFAULT
    local fg_nib, bg_nib = 0, 0
    if color ~= nil then
        fg_nib = resolve_color(color, "color")
        attrs = attrs & ~ATTR_FG_DEFAULT
    end
    if bg ~= nil then
        bg_nib = resolve_color(bg, "backgroundColor")
        attrs = attrs & ~ATTR_BG_DEFAULT
    end
    if bold        then attrs = attrs | ATTR_BOLD          end
    if dim         then attrs = attrs | ATTR_DIM           end
    if underline   then attrs = attrs | ATTR_UNDERLINE     end
    if inverse     then attrs = attrs | ATTR_INVERSE       end
    if italic      then attrs = attrs | ATTR_ITALIC        end
    if strikethrough then attrs = attrs | ATTR_STRIKETHROUGH end

    return ((fg_nib << 4) | (bg_nib & 0xF)) & 0xFF, attrs & 0xFF
end

return M
