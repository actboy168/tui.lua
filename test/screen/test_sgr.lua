-- test/test_sgr.lua — coverage for tui.sgr (resolve_color, pack_style, pack_border_style).

local lt       = require "ltest"
local sgr      = require "tui.internal.sgr"
local tui_core = require "tui.core"
local screen_c = tui_core.screen

local suite = lt.test "sgr"

-- Helper: make a small screen and read back the first cell's color info.
-- Returns the cells() table for column 1 of row 1 after painting one cell.
local function cell_style(props)
    local s = screen_c.new(4, 1)
    screen_c.clear(s)
    local style_id = sgr.pack_style(s, props)
    screen_c.put(s, 0, 0, "X", 1, style_id)
    screen_c.diff(s)
    local cells = screen_c.cells(s, 1)
    return cells and cells[1]
end

-- ---------------------------------------------------------------------------
-- pack_style: named colors

function suite:test_pack_style_named_fg()
    local c = cell_style { color = "red" }
    lt.assertNotEquals(c, nil)
    lt.assertEquals(c.fg, 1)
end

function suite:test_pack_style_named_bg()
    local c = cell_style { backgroundColor = "blue" }
    lt.assertNotEquals(c, nil)
    lt.assertEquals(c.bg, 4)
end

function suite:test_pack_style_grey_is_bright_black()
    local c = cell_style { color = "grey" }
    lt.assertEquals(c.fg, 8)
end

-- ---------------------------------------------------------------------------
-- pack_style: integer 16-color

function suite:test_pack_style_int_fg()
    local c = cell_style { color = 5 }
    lt.assertEquals(c.fg, 5)
end

function suite:test_pack_style_int_bg()
    local c = cell_style { backgroundColor = 12 }
    lt.assertEquals(c.bg, 12)
end

function suite:test_pack_style_int_zero()
    local c = cell_style { color = 0 }
    lt.assertEquals(c.fg, 0)
end

-- ---------------------------------------------------------------------------
-- pack_style: 256-color (integer 16..255)

function suite:test_pack_style_256_fg()
    local c = cell_style { color = 200 }
    lt.assertEquals(c.fg, 200)
end

function suite:test_pack_style_256_bg()
    local c = cell_style { backgroundColor = 16 }
    lt.assertEquals(c.bg, 16)
end

-- ---------------------------------------------------------------------------
-- pack_style: 24-bit truecolor ("#RRGGBB")

function suite:test_pack_style_truecolor_fg()
    local c = cell_style { color = "#FF0000" }
    -- fg returned as "#rrggbb" hex string
    lt.assertEquals(type(c.fg), "string")
    lt.assertEquals(c.fg:lower(), "#ff0000")
end

function suite:test_pack_style_truecolor_bg()
    local c = cell_style { backgroundColor = "#1A2B3C" }
    lt.assertEquals(type(c.bg), "string")
    lt.assertEquals(c.bg:lower(), "#1a2b3c")
end

-- ---------------------------------------------------------------------------
-- pack_style: no props / nil → style_id = 0

function suite:test_pack_style_nil()
    local s = screen_c.new(4, 1)
    lt.assertEquals(sgr.pack_style(s, nil), 0)
end

function suite:test_pack_style_no_styling()
    local s = screen_c.new(4, 1)
    lt.assertEquals(sgr.pack_style(s, {}), 0)
end

-- ---------------------------------------------------------------------------
-- pack_style: boolean attributes

function suite:test_pack_style_bold()
    local c = cell_style { bold = true }
    lt.assertEquals(c.bold, true)
end

function suite:test_pack_style_inverse()
    local c = cell_style { inverse = true }
    lt.assertEquals(c.inverse, true)
end

function suite:test_pack_style_italic()
    local c = cell_style { italic = true }
    lt.assertEquals(c.italic, true)
end

function suite:test_pack_style_italic_off()
    local c = cell_style { bold = true }
    lt.assertEquals(c.italic, false)
end

function suite:test_pack_style_strikethrough()
    local c = cell_style { strikethrough = true }
    lt.assertEquals(c.strikethrough, true)
end

function suite:test_pack_style_italic_and_strikethrough()
    local c = cell_style { italic = true, strikethrough = true }
    lt.assertEquals(c.italic, true)
    lt.assertEquals(c.strikethrough, true)
end

-- ---------------------------------------------------------------------------
-- pack_style: dimColor

function suite:test_pack_style_dimColor_sets_dim_bit()
    local c = cell_style { dimColor = "red" }
    lt.assertEquals(c.dim, true)
end

function suite:test_pack_style_dimColor_sets_fg()
    local c = cell_style { dimColor = "red" }
    lt.assertEquals(c.fg, 1)
end

function suite:test_pack_style_dimColor_overrides_color()
    -- dimColor takes precedence over color
    local c = cell_style { dimColor = "blue", color = "red" }
    lt.assertEquals(c.fg, 4)  -- blue, not red
    lt.assertEquals(c.dim, true)
end

function suite:test_pack_style_color_no_dim()
    -- plain color does not set dim
    local c = cell_style { color = "red" }
    lt.assertEquals(c.dim, false)
end

-- ---------------------------------------------------------------------------
-- pack_style: error paths

function suite:test_pack_style_float_int()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { color = 3.5 })
    end)
end

function suite:test_pack_style_negative_int()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { color = -1 })
    end)
end

function suite:test_pack_style_int_out_of_range()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { color = 256 })
    end)
end

function suite:test_pack_style_unknown_color_name()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { color = "chartreuse" })
    end)
end

function suite:test_pack_style_bad_color_type()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { color = {} })
    end)
end

function suite:test_pack_style_bad_bg_type()
    lt.assertError(function()
        local s = screen_c.new(4, 1)
        sgr.pack_style(s, { backgroundColor = true })
    end)
end

-- ---------------------------------------------------------------------------
-- COLORS table completeness

function suite:test_colors_table_has_gray_and_grey()
    lt.assertEquals(sgr.COLORS.gray, 8)
    lt.assertEquals(sgr.COLORS.grey, 8)
end

function suite:test_colors_table_bright_colors()
    lt.assertEquals(sgr.COLORS.brightRed, 9)
    lt.assertEquals(sgr.COLORS.brightWhite, 15)
end
