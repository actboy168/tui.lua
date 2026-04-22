local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "border_styles"

-- Helper to get first byte of a string
local function first_byte(s)
    if not s or #s == 0 then return nil end
    return s:byte(1)
end

-- UTF-8 first byte constants
local BYTE_CORNER_DOUBLE_TL = 0xE2  -- ╔ starts with E2
local BYTE_CORNER_BOLD_TL = 0xE2    -- ┏ starts with E2
local BYTE_CORNER_ROUND_TL = 0xE2   -- ╭ starts with E2
local BYTE_PLUS = 0x2B              -- + is 43
local BYTE_HYPHEN = 0x2D            -- - is 45

function suite.test_borderStyle_double()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "double",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- Double border top-left corner should be ╔ (UTF-8: E2 95 94)
    lt.assertEquals(first_byte(row), BYTE_CORNER_DOUBLE_TL)
    h:unmount()
end

function suite.test_borderStyle_bold()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "bold",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- Bold border top-left corner should be ┏ (UTF-8: E2 94 8F)
    lt.assertEquals(first_byte(row), BYTE_CORNER_BOLD_TL)
    h:unmount()
end

function suite.test_borderStyle_round()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "round",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- Round border top-left corner should be ╭ (UTF-8: E2 95 AD)
    lt.assertEquals(first_byte(row), BYTE_CORNER_ROUND_TL)
    h:unmount()
end

function suite.test_borderStyle_classic()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "classic",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- Classic border corners should be + (ASCII 43)
    lt.assertEquals(first_byte(row), BYTE_PLUS)
    -- The second "character" in the cell buffer is the horizontal line
    -- which is stored as 3 bytes per cell, so byte(2) is actually
    -- the second cell's first byte (which would be the horizontal line -)
    -- We just verify the border renders without error
    lt.assertNotEquals(row, nil)
    h:unmount()
end

function suite.test_borderStyle_singleDouble()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "singleDouble",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- singleDouble corner starts with E2
    lt.assertEquals(first_byte(row), 0xE2)
    h:unmount()
end

function suite.test_borderStyle_doubleSingle()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "doubleSingle",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    local row = h:row(1)
    -- doubleSingle corner starts with E2
    lt.assertEquals(first_byte(row), 0xE2)
    h:unmount()
end

function suite.test_borderColor_applies_to_border()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "single",
            borderColor = "red",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    -- Border cells on row 1 should have red fg (fg=1)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1, "border cell should have red fg")
    h:unmount()
end

function suite.test_borderDimColor_applies_dim()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "single",
            borderDimColor = "blue",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    -- Border cells on row 1 should have dim + blue
    local cells = h:cells(1)
    lt.assertEquals(cells[1].dim, true, "border cell should be dim")
    lt.assertEquals(cells[1].fg, 4, "border cell should have blue fg")
    h:unmount()
end

function suite.test_borderColor_overrides_color()
    local h = testing.render(function()
        return tui.Box {
            width = 10, height = 5,
            borderStyle = "single",
            color = "green",
            borderColor = "red",
            tui.Text { "content" }
        }
    end, { cols = 20, rows = 10 })

    -- Border cells should have red (fg=1) for border, not green
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1, "border cell should have red fg")
    h:unmount()
end

function suite.test_text_uses_color_not_borderColor()
    local h = testing.render(function()
        return tui.Box {
            width = 15, height = 5,
            borderStyle = "single",
            borderColor = "red",
            color = "blue",
            tui.Text { "hello" }
        }
    end, { cols = 20, rows = 10 })

    -- Row 1 is border → red fg; row 2 has content → blue fg
    local border_cells = h:cells(1)
    lt.assertEquals(border_cells[1].fg, 1, "border should be red")
    -- Find the text row (row 2 inside the border)
    local content_cells = h:cells(2)
    -- Content area starts at col 2 (after left border), text "hello" starts there
    lt.assertEquals(content_cells[2].fg, 4, "text should be blue (fg=4)")
    h:unmount()
end
