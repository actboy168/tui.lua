-- test/test_cursor_integer_coords.lua — regression for 2026-04-18 cursor bug.
--
-- Symptom: in a real terminal, the cursor stuck at whatever character the
-- last SGR diff had written (e.g. the "s" in "uptime 4s") instead of
-- landing in the focused TextInput.
--
-- Root cause: Yoga can produce fractional rect origins (e.g. y=72.0). The
-- paint loop formatted those directly into `\27[<row>;<col>H`, producing
-- `\27[73.0;3.0H`, which terminals parse-reject silently.
--
-- Guarantee: for any focused TextInput, `find_cursor` must return integer
-- (col, row). Framework-level fix currently lives in tui/init.lua's
-- find_cursor (math.floor); the long-term fix is Yoga PointScaleFactor=1
-- (see roadmap). Either way, this test stays the canary.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "cursor_integer_coords"

local function is_integer(n)
    return type(n) == "number" and n == math.floor(n)
end

-- Simple TextInput at the root — cursor should land inside it at (1, 1).
function suite:test_cursor_coords_are_integers_simple()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 40, height = 3,
            tui.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 3 })
    local col, row = h:cursor()
    lt.assertEquals(is_integer(col), true,
                    ("cursor col must be integer, got %s"):format(tostring(col)))
    lt.assertEquals(is_integer(row), true,
                    ("cursor row must be integer, got %s"):format(tostring(row)))
    lt.assertEquals(col, 1, "empty TextInput at (0,0) -> caret at (1,1)")
    lt.assertEquals(row, 1)
    h:unmount()
end

-- Nested flex layout — Yoga is most likely to produce floats here. The
-- input sits at the bottom of an 80x75 column stack; caret must be on
-- the last row, inside the padding/border (col 3, row 74).
function suite:test_cursor_coords_are_integers_nested_flex()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            flexDirection = "column",
            width = 80, height = 75,
            tui.Box { key = "header", border = "round", paddingX = 1,
                tui.Text { key = "t", "title" },
            },
            tui.Box { key = "grow", flex = 1 },
            tui.Box { key = "input", border = "round", paddingX = 1,
                tui.TextInput { value = v, onChange = setV, autoFocus = true },
            },
        }
    end
    local h = testing.render(App, { cols = 80, rows = 75 })
    local col, row = h:cursor()
    lt.assertEquals(is_integer(col), true,
                    ("cursor col must be integer, got %s"):format(tostring(col)))
    lt.assertEquals(is_integer(row), true,
                    ("cursor row must be integer, got %s"):format(tostring(row)))
    -- Bottom box is 3 rows tall (border+content+border). Height 75 minus
    -- 3 puts its top at y=72; caret lands on y=73 (border skipped), 1-based
    -- row 74. paddingX=1 inside the border -> col 3.
    lt.assertEquals(col, 3)
    lt.assertEquals(row, 74)
    h:unmount()
end

-- The all_in_one example is the scenario that first exposed the bug; make
-- sure it specifically produces integer coords under its usual geometry,
-- AND that the cursor actually lands inside the bottom input box.
function suite:test_cursor_coords_in_all_in_one_example()
    local App = require "examples.all_in_one"
    -- 75 rows is where the original user reproduction landed (cursor.log
    -- showed crow=73.0 at that height).
    local h = testing.render(App, { cols = 120, rows = 75 })
    local col, row = h:cursor()
    lt.assertEquals(type(col), "number", "all_in_one should have a cursor")
    lt.assertEquals(is_integer(col), true,
                    ("all_in_one cursor col must be integer, got %s"):format(tostring(col)))
    lt.assertEquals(is_integer(row), true,
                    ("all_in_one cursor row must be integer, got %s"):format(tostring(row)))
    -- The input box is 3 rows tall at the bottom, with a 1-row footer
    -- below it. Caret lives on the input box's content row. At rows=75:
    -- footer is row 75; input box rows 72..74; caret row = 73 (1-based).
    -- Inside round border + paddingX=1 -> col 3.
    lt.assertEquals(col, 3)
    lt.assertEquals(row, 73)
    h:unmount()
end

-- Sanity: an unfocused/disabled input returns nil cursor, not an error.
function suite:test_no_cursor_when_input_disabled()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 40, height = 3,
            tui.TextInput { value = v, onChange = setV, focus = false },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 3 })
    local col, row = h:cursor()
    lt.assertEquals(col, nil, "disabled input should not advertise a cursor")
    lt.assertEquals(row, nil)
    h:unmount()
end
