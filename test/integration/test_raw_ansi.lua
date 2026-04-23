local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "raw_ansi"

function suite:test_empty_lines_render_nothing()
    local function App()
        return tui.Box {
            width = 4,
            height = 1,
            tui.RawAnsi {
                lines = {},
                width = 0,
            },
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:row(1), "    ")
    h:unmount()
end

function suite:test_raw_ansi_does_not_inherit_box_color()
    local function App()
        return tui.Box {
            width = 2,
            height = 1,
            color = "green",
            tui.RawAnsi {
                lines = { "ok" },
                width = 2,
            },
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, nil)
    lt.assertEquals(cells[2].fg, nil)
    h:unmount()
end

function suite:test_sgr_reset_does_not_leak_to_sibling_text()
    local function App()
        return tui.Box {
            width = 4,
            height = 1,
            flexDirection = "row",
            tui.RawAnsi {
                lines = { "\27[31mhi\27[0m" },
                width = 2,
            },
            tui.Text { "ok" },
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1)
    lt.assertEquals(cells[2].fg, 1)
    lt.assertEquals(cells[3].fg, nil)
    lt.assertEquals(cells[4].fg, nil)
    lt.assertEquals(h:row(1), "hiok")
    h:unmount()
end

function suite:test_multiline_layout_inside_border_and_padding()
    local function App()
        return tui.Box {
            width = 7,
            height = 4,
            borderStyle = "single",
            paddingX = 1,
            tui.RawAnsi {
                lines = { "A", "B" },
                width = 1,
            },
        }
    end

    local h = testing.render(App, { cols = 7, rows = 4 })
    local row2 = h:cells(2)
    local row3 = h:cells(3)
    lt.assertEquals(row2[3].char, "A")
    lt.assertEquals(row3[3].char, "B")
    h:unmount()
end

function suite:test_bold_and_background_sgr()
    local function App()
        return tui.Box {
            width = 1,
            height = 1,
            tui.RawAnsi {
                lines = { "\27[1;44mX\27[0m" },
                width = 1,
            },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].bold, true)
    lt.assertEquals(cells[1].bg, 4)
    lt.assertEquals(h:row(1), "X")
    h:unmount()
end

function suite:test_unsupported_ansi_control_sequence_errors()
    local function App()
        return tui.Box {
            width = 1,
            height = 1,
            tui.RawAnsi {
                lines = { "\27[2J" },
                width = 0,
            },
        }
    end

    local ok, err = pcall(testing.render, App, { cols = 2, rows = 1 })
    lt.assertEquals(ok, false)
    lt.assertNotEquals(tostring(err):find("unsupported ANSI control sequence", 1, true), nil)
end
