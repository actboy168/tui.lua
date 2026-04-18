-- test/test_sgr.lua — coverage for tui.sgr (resolve_color, pack_bytes, pack_props).

local lt  = require "ltest"
local sgr = require "tui.sgr"

local suite = lt.test "sgr"

-- ---------------------------------------------------------------------------
-- pack_bytes: named colors

function suite:test_pack_bytes_named_fg()
    local fg_bg, attrs = sgr.pack_bytes { color = "red" }
    local fg = (fg_bg >> 4) & 0xF
    lt.assertEquals(fg, 1)
end

function suite:test_pack_bytes_named_bg()
    local fg_bg, attrs = sgr.pack_bytes { backgroundColor = "blue" }
    local bg = fg_bg & 0xF
    lt.assertEquals(bg, 4)
end

function suite:test_pack_bytes_grey_is_bright_black()
    local fg_bg = sgr.pack_bytes { color = "grey" }
    lt.assertEquals((fg_bg >> 4) & 0xF, 8)
end

-- ---------------------------------------------------------------------------
-- pack_bytes: integer colors 0..15

function suite:test_pack_bytes_int_fg()
    local fg_bg = sgr.pack_bytes { color = 5 }
    lt.assertEquals((fg_bg >> 4) & 0xF, 5)
end

function suite:test_pack_bytes_int_bg()
    local fg_bg = sgr.pack_bytes { backgroundColor = 12 }
    lt.assertEquals(fg_bg & 0xF, 12)
end

function suite:test_pack_bytes_int_zero()
    local fg_bg = sgr.pack_bytes { color = 0 }
    lt.assertEquals((fg_bg >> 4) & 0xF, 0)
end

-- ---------------------------------------------------------------------------
-- pack_bytes: no props / nil

function suite:test_pack_bytes_nil()
    local fg_bg, attrs = sgr.pack_bytes(nil)
    lt.assertEquals(fg_bg, 0)
    lt.assertEquals(attrs, 0x30)  -- ATTR_DEFAULT
end

function suite:test_pack_bytes_no_styling()
    local fg_bg, attrs = sgr.pack_bytes {}
    lt.assertEquals(fg_bg, 0)
    lt.assertEquals(attrs, 0x30)
end

-- ---------------------------------------------------------------------------
-- pack_bytes: boolean attributes

function suite:test_pack_bytes_bold()
    local _, attrs = sgr.pack_bytes { bold = true }
    lt.assertEquals(attrs & 0x01, 0x01)
end

function suite:test_pack_bytes_inverse()
    local _, attrs = sgr.pack_bytes { inverse = true }
    lt.assertEquals(attrs & 0x08, 0x08)
end

-- ---------------------------------------------------------------------------
-- pack_bytes: error paths

function suite:test_pack_bytes_int_out_of_range()
    lt.assertError(function()
        sgr.pack_bytes { color = 16 }
    end)
end

function suite:test_pack_bytes_negative_int()
    lt.assertError(function()
        sgr.pack_bytes { color = -1 }
    end)
end

function suite:test_pack_bytes_float_int()
    lt.assertError(function()
        sgr.pack_bytes { color = 3.5 }
    end)
end

function suite:test_pack_bytes_unknown_color_name()
    lt.assertError(function()
        sgr.pack_bytes { color = "chartreuse" }
    end)
end

function suite:test_pack_bytes_bad_color_type()
    lt.assertError(function()
        sgr.pack_bytes { color = {} }
    end)
end

-- ---------------------------------------------------------------------------
-- pack_props: returns nil when no styling

function suite:test_pack_props_nil()
    lt.assertEquals(sgr.pack_props(nil), nil)
end

function suite:test_pack_props_no_styling()
    lt.assertEquals(sgr.pack_props {}, nil)
end

function suite:test_pack_props_with_color()
    local style = sgr.pack_props { color = "red" }
    lt.assertNotEquals(style, nil)
    lt.assertEquals(style.fg, 1)
    lt.assertEquals(style.bg, nil)
end

function suite:test_pack_props_with_bg()
    local style = sgr.pack_props { backgroundColor = "cyan" }
    lt.assertEquals(style.bg, 6)
    lt.assertEquals(style.fg, nil)
end

function suite:test_pack_props_with_int_color()
    local style = sgr.pack_props { color = 9 }
    lt.assertEquals(style.fg, 9)
end

function suite:test_pack_props_boolean_attrs()
    local style = sgr.pack_props { bold = true, underline = true }
    lt.assertEquals(style.bold, true)
    lt.assertEquals(style.underline, true)
    lt.assertEquals(style.dim, nil)
    lt.assertEquals(style.inverse, nil)
end

function suite:test_pack_props_false_boolean_is_nil()
    local style = sgr.pack_props { color = "white", bold = false }
    lt.assertEquals(style.fg, 7)
    lt.assertEquals(style.bold, nil)
end

-- ---------------------------------------------------------------------------
-- pack_props: error paths

function suite:test_pack_props_bad_color_name()
    lt.assertError(function()
        sgr.pack_props { color = "invisible" }
    end)
end

function suite:test_pack_props_bad_bg_type()
    lt.assertError(function()
        sgr.pack_props { backgroundColor = true }
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
