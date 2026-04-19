-- test/input/test_newline.lua — tests for Newline and Spacer components.
local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local test_newline = lt.test "newline"

-- ---------------------------------------------------------------------------
-- Newline tests

function test_newline:test_newline_default_count()
    -- Default count is 1, creates a single empty line.
    local function App()
        return tui.Box {
            flexDirection = "column",
            tui.Text { key = "first", "first" },
            tui.Newline { key = "nl" },
            tui.Text { key = "second", "second" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })

    local rows = h:rows()
    lt.assertEquals(#rows, 3)
    lt.assertEquals(rows[1]:match("first") ~= nil, true)
    lt.assertEquals(rows[2]:match("^%s*$") ~= nil, true)  -- empty line
    lt.assertEquals(rows[3]:match("second") ~= nil, true)

    h:unmount()
end

function test_newline:test_newline_with_count()
    -- Creates multiple empty lines.
    local function App()
        return tui.Box {
            flexDirection = "column",
            tui.Text { key = "first", "first" },
            tui.Newline { key = "nl", count = 2 },
            tui.Text { key = "second", "second" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })

    local rows = h:rows()
    lt.assertEquals(#rows, 4)
    lt.assertEquals(rows[1]:match("first") ~= nil, true)
    lt.assertEquals(rows[2]:match("^%s*$") ~= nil, true)  -- empty line 1
    lt.assertEquals(rows[3]:match("^%s*$") ~= nil, true)  -- empty line 2
    lt.assertEquals(rows[4]:match("second") ~= nil, true)

    h:unmount()
end

function test_newline:test_newline_in_row_layout()
    -- Newline in row layout should still occupy vertical space.
    local function App()
        return tui.Box {
            flexDirection = "row",
            tui.Text { key = "left", "left" },
            tui.Newline { key = "nl" },
            tui.Text { key = "right", "right" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })

    -- In row layout, Newline (as a Box with height) participates in layout.
    -- The exact rendering depends on Yoga layout, but it shouldn't crash.
    local rows = h:rows()
    lt.assertEquals(#rows >= 1, true)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Spacer tests

function test_newline:test_spacer_fills_space()
    -- Spacer expands to fill available space in a column.
    local function App()
        return tui.Box {
            flexDirection = "column",
            height = 5,
            tui.Text { key = "top", "top" },
            tui.Spacer { key = "spacer" },
            tui.Text { key = "bottom", "bottom" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })

    local rows = h:rows()
    lt.assertEquals(#rows, 5)
    lt.assertEquals(rows[1]:match("top") ~= nil, true)
    lt.assertEquals(rows[5]:match("bottom") ~= nil, true)
    -- Middle rows should be empty (filled by Spacer)
    lt.assertEquals(rows[2]:match("^%s*$") ~= nil, true)
    lt.assertEquals(rows[3]:match("^%s*$") ~= nil, true)
    lt.assertEquals(rows[4]:match("^%s*$") ~= nil, true)

    h:unmount()
end

function test_newline:test_spacer_in_row()
    -- Spacer expands horizontally in a row layout.
    local function App()
        return tui.Box {
            flexDirection = "row",
            width = 20,
            tui.Text { key = "a", "A" },
            tui.Spacer { key = "spacer" },
            tui.Text { key = "b", "B" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })

    local row = h:row(1)
    -- "A" should be at the beginning, "B" at the end
    lt.assertEquals(row:sub(1, 1), "A")
    lt.assertEquals(row:sub(20, 20), "B")

    h:unmount()
end

function test_newline:test_spacer_multiple()
    -- Multiple Spacers share the available space equally.
    local function App()
        return tui.Box {
            flexDirection = "column",
            height = 5,
            tui.Text { key = "top", "top" },
            tui.Spacer { key = "s1" },
            tui.Spacer { key = "s2" },
            tui.Text { key = "bottom", "bottom" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })

    local rows = h:rows()
    lt.assertEquals(#rows, 5)
    lt.assertEquals(rows[1]:match("top") ~= nil, true)
    lt.assertEquals(rows[5]:match("bottom") ~= nil, true)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Combined usage

function test_newline:test_newline_and_spacer_combined()
    -- Using both Newline and Spacer together.
    local function App()
        return tui.Box {
            flexDirection = "column",
            height = 6,
            tui.Text { key = "header", "header" },
            tui.Newline { key = "nl", count = 1 },
            tui.Spacer { key = "spacer" },
            tui.Text { key = "footer", "footer" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 6 })

    local rows = h:rows()
    lt.assertEquals(#rows, 6)
    lt.assertEquals(rows[1]:match("header") ~= nil, true)
    lt.assertEquals(rows[2]:match("^%s*$") ~= nil, true)  -- Newline
    -- rows 3-5 filled by Spacer
    lt.assertEquals(rows[6]:match("footer") ~= nil, true)

    h:unmount()
end
