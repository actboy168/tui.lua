-- test/integration/test_focus_flow.lua — multi-field focus cycling tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local extra   = require "tui.extra"

local suite = lt.test "focus_flow"

-- Three-field form with explicit focusIds so we can assert the active field.
local function ThreeFieldForm(props)
    props = props or {}
    local a, setA = tui.useState("")
    local b, setB = tui.useState("")
    local c, setC = tui.useState("")

    return tui.Box {
        flexDirection = "column",
        width = 40, height = 8,
        tui.Box {
            key = "row_a",
            flexDirection = "row",
            tui.Text { key = "la", "A: " },
            extra.TextInput {
                key = "ia",
                focusId = "field_a",
                autoFocus = true,
                value = a, onChange = setA, width = 20,
            },
        },
        tui.Box {
            key = "row_b",
            flexDirection = "row",
            tui.Text { key = "lb", "B: " },
            extra.TextInput {
                key = "ib",
                focusId = "field_b",
                autoFocus = false,
                value = b, onChange = setB, width = 20,
            },
        },
        tui.Box {
            key = "row_c",
            flexDirection = "row",
            tui.Text { key = "lc", "C: " },
            extra.TextInput {
                key = "ic",
                focusId = "field_c",
                autoFocus = false,
                value = c, onChange = setC, width = 20,
            },
        },
    }
end

-- ============================================================================
-- Initial focus
-- ============================================================================

function suite:test_initial_focus()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()  -- needed after autoFocus to register cursor

    lt.assertEquals(h:focus_id(), "field_a")

    -- Cursor must be in row 1 (field_a is on the first content row)
    local col, row = h:cursor()
    lt.assertNotEquals(col, nil)
    lt.assertEquals(row, 1)

    h:unmount()
end

-- ============================================================================
-- Tab cycles forward through fields
-- ============================================================================

function suite:test_tab_forward()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    lt.assertEquals(h:focus_id(), "field_a")

    tui_input.press("tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_b")

    tui_input.press("tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_c")

    -- Tab wraps from last back to first
    tui_input.press("tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_a")

    h:unmount()
end

-- ============================================================================
-- Shift+Tab cycles backward
-- ============================================================================

function suite:test_shift_tab_backward()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    lt.assertEquals(h:focus_id(), "field_a")

    -- Shift+Tab from first wraps to last
    tui_input.press("shift+tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_c")

    tui_input.press("shift+tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_b")

    tui_input.press("shift+tab")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_a")

    h:unmount()
end

-- ============================================================================
-- Cursor row follows focus field
-- ============================================================================

function suite:test_cursor_follows_focus()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    local _, row_a = h:cursor()
    lt.assertEquals(row_a, 1)

    tui_input.press("tab")
    h:rerender()
    local _, row_b = h:cursor()
    lt.assertEquals(row_b, 2)

    tui_input.press("tab")
    h:rerender()
    local _, row_c = h:cursor()
    lt.assertEquals(row_c, 3)

    h:unmount()
end

-- ============================================================================
-- Cursor column advances as text is typed
-- ============================================================================

function suite:test_cursor_col_advances()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    local col0 = h:cursor()
    lt.assertNotEquals(col0, nil)

    tui_input.type("hi")
    h:rerender()
    local col2 = h:cursor()
    lt.assertEquals(col2, col0 + 2)

    h:unmount()
end

-- ============================================================================
-- focus() API jumps directly to a named field
-- ============================================================================

function suite:test_focus_direct()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    h:focus("field_c")
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_c")

    local _, row = h:cursor()
    lt.assertEquals(row, 3)

    h:unmount()
end

-- ============================================================================
-- focus_next / focus_prev match Tab / Shift+Tab
-- ============================================================================

function suite:test_focus_next_prev_api()
    local h = testing.render(ThreeFieldForm, { cols = 45, rows = 10 })
    h:rerender()

    h:focus_next()
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_b")

    h:focus_prev()
    h:rerender()
    lt.assertEquals(h:focus_id(), "field_a")

    h:unmount()
end
