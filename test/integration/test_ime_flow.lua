-- test/integration/test_ime_flow.lua — IME composing + confirm integration

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local extra   = require "tui.extra"

local suite = lt.test "ime_flow"

-- ============================================================================
-- Single TextInput app for IME testing
-- ============================================================================

local function IMEApp()
    local val, setVal = tui.useState("")

    return tui.Box {
        width = 30, height = 3,
        extra.TextInput {
            key      = "inp",
            value    = val,
            onChange = setVal,
            width    = 25,
        },
    }
end

-- ============================================================================
-- Composing phase shows candidate text
-- ============================================================================

function suite:test_composing_appears()
    local h = testing.render(IMEApp, { cols = 35, rows = 5 })

    h:type_composing("ni")

    -- During composing the text should be visible in the frame
    local frame = h:frame()
    lt.assertNotEquals(frame:find("ni"), nil,
        "composing text should appear in the frame")

    h:unmount()
end

-- ============================================================================
-- Confirm commits the composed text into the value
-- ============================================================================

function suite:test_confirm_commits_text()
    local committed = ""

    local App = function()
        local val, setVal = tui.useState("")
        committed = val
        return tui.Box {
            width = 30, height = 3,
            extra.TextInput {
                key      = "inp",
                value    = val,
                onChange = function(v)
                    setVal(v)
                    committed = v
                end,
                width    = 25,
            },
        }
    end

    local h = testing.render(App, { cols = 35, rows = 5 })

    h:type_composing("你好")
    h:type_composing_confirm("你好")

    lt.assertEquals(committed, "你好")

    h:unmount()
end

-- ============================================================================
-- Cursor advances past double-width characters
-- ============================================================================

function suite:test_cursor_past_double_width()
    local h = testing.render(IMEApp, { cols = 35, rows = 5 })
    h:rerender()

    -- Record cursor at empty state
    local col0 = h:cursor()
    lt.assertNotEquals(col0, nil, "cursor position should be defined")

    -- ASCII: cursor moves 1 per character
    h:type("ab")
    local col_ascii = h:cursor()
    lt.assertEquals(col_ascii, col0 + 2)

    -- Confirm a double-width character: cursor moves 2 per character
    h:type_composing_confirm("你")   -- 1 wide char = 2 columns
    local col_after = h:cursor()
    lt.assertEquals(col_after, col_ascii + 2,
        "double-width char should advance cursor by 2 columns")

    h:unmount()
end

-- ============================================================================
-- IME position is reported after composing
-- ============================================================================

function suite:test_ime_pos_after_composing()
    local h = testing.render(IMEApp, { cols = 35, rows = 5 })
    h:rerender()

    h:type_composing("a")

    local col, row = h:ime_pos()
    lt.assertNotEquals(col, nil, "ime_pos col should be set during composing")
    lt.assertNotEquals(row, nil, "ime_pos row should be set during composing")
    lt.assertTrue(col >= 1, "ime_pos col must be positive")
    lt.assertTrue(row >= 1, "ime_pos row must be positive")

    h:unmount()
end

-- ============================================================================
-- Snapshot — composing and confirmed states
-- ============================================================================

function suite:test_snapshot_composing()
    local h = testing.render(IMEApp, { cols = 35, rows = 5 })
    h:type_composing("abc")
    h:match_snapshot("ime_composing_35x5")
    h:unmount()
end

function suite:test_snapshot_confirmed()
    local h = testing.render(IMEApp, { cols = 35, rows = 5 })
    h:type_composing_confirm("Hello")
    h:match_snapshot("ime_confirmed_35x5")
    h:unmount()
end
