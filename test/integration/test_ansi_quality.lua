-- test/integration/test_ansi_quality.lua — ANSI output quality assertions
--
-- Uses vterm + cells/cursor query APIs to verify that the framework emits
-- correct ANSI sequences at the right moments (cursor show, incremental diff
-- efficiency, term_type OSC1337).

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local extra   = require "tui.extra"
local vterm   = require "tui.testing.vterm"

local suite = lt.test "ansi_quality"

-- ============================================================================
-- Cursor show lifecycle
-- ============================================================================

-- An app with a focused TextInput should show the cursor.
function suite:test_cursor_show_with_text_input()
    local App = function()
        return tui.Box {
            width = 30, height = 3,
            extra.TextInput {
                key   = "inp",
                value = "", onChange = function() end,
                width = 20,
            },
        }
    end

    local h = testing.harness(App, { cols = 35, rows = 5, interactive = true })
    h:rerender()  -- ensure cursor position is emitted

    local vt = h:vterm()
    -- cursor-show must appear in the output
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?25h"), true,
        "expected cursor-show sequence with focused TextInput")

    -- A cursor positioning sequence must appear (cursorMove or CUP)
    lt.assertEquals(vterm.has_sequence_pattern(vt, "\x1b%[%d*[ABCD]"), true,
        "expected a cursor positioning sequence")

    h:unmount()
end

-- An app with no TextInput should hide the cursor.
function suite:test_no_cursor_show_without_text_input()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            tui.Text { "Hello, world!" },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5, interactive = true })

    local vt = h:vterm()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?25l"), true,
        "cursor should be hidden when there is no TextInput")

    h:unmount()
end

-- ============================================================================
-- Incremental diff — only changed cells emitted
-- ============================================================================

-- After an unrelated state change, the diff should only contain sequences for
-- the row that actually changed. We use a counter app: pressing "up" changes
-- exactly one row, so the next diff must be much smaller than a full-redraw.
function suite:test_incremental_diff_size()
    local App = function()
        local count, setCount = tui.useState(0)
        tui.useInput(function(_, key)
            if key.name == "up" then setCount(count + 1) end
        end)
        return tui.Box {
            flexDirection = "column",
            width = 20, height = 10,
            tui.Text { key = "k1", "Count:" },
            tui.Text { key = "k2", tostring(count) },
            tui.Text { key = "k3", "Line 3" },
            tui.Text { key = "k4", "Line 4" },
            tui.Text { key = "k5", "Line 5" },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 12, interactive = true })

    -- Capture the size of the first (full-redraw) paint
    local full_size = #h:ansi()

    -- Clear ANSI buffer, then perform one keypress (incremental diff)
    h:clear_ansi()
    h:press("up")
    h:rerender()
    local incremental_size = #h:ansi()

    -- The incremental diff must be strictly smaller than the full redraw
    lt.assertTrue(incremental_size < full_size,
        ("incremental diff (%d bytes) should be smaller than full redraw (%d bytes)")
            :format(incremental_size, full_size))

    h:unmount()
end

-- ============================================================================
-- Resize triggers full redraw
-- ============================================================================

function suite:test_resize_triggers_full_redraw()
    local App = function()
        return tui.Box {
            width = 30, height = 8,
            tui.Text { key = "t1", "Static content" },
            tui.Text { key = "t2", "More content" },
        }
    end

    local h = testing.harness(App, { cols = 35, rows = 10, interactive = true })
    local first_size = #h:ansi()

    -- Normal re-render after no changes (no key, no state) → minimal diff
    h:clear_ansi()
    h:rerender()
    local stable_size = #h:ansi()

    -- Resize forces a full redraw
    h:clear_ansi()
    h:resize(40, 12)
    h:rerender()
    local resize_size = #h:ansi()

    lt.assertTrue(resize_size > stable_size,
        ("resize diff (%d bytes) should be larger than stable re-render (%d bytes)")
            :format(resize_size, stable_size))
    lt.assertTrue(resize_size > 0, "resize diff must not be empty")

    -- Suppress unused variable warning in tests that only validate structure
    _ = first_size

    h:unmount()
end

-- ============================================================================
-- h:cells(row) — per-cell style data
-- ============================================================================

-- Bold text cells report bold = true.
function suite:test_cells_bold_attribute()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            tui.Text { bold = true, "BOLD" },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5 })

    local cells = h:cells(1)
    lt.assertNotEquals(cells, nil, "cells() must return a table")
    lt.assertTrue(#cells >= 4, "must have at least 4 cells for 'BOLD'")

    -- Every character of "BOLD" should be bold
    for i = 1, 4 do
        lt.assertEquals(cells[i].bold, true,
            ("cell %d of 'BOLD' should have bold=true"):format(i))
    end

    h:unmount()
end

-- Dim text cells report dim = true; default-colored cells have fg/bg == nil.
function suite:test_cells_dim_and_default_color()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            tui.Text { dim = true, "dim" },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5 })

    local cells = h:cells(1)
    lt.assertTrue(#cells >= 3, "must have at least 3 cells for 'dim'")

    for i = 1, 3 do
        lt.assertEquals(cells[i].dim, true,
            ("cell %d should have dim=true"):format(i))
        lt.assertEquals(cells[i].fg, nil,
            ("cell %d fg should be nil (default color)"):format(i))
        lt.assertEquals(cells[i].bg, nil,
            ("cell %d bg should be nil (default color)"):format(i))
    end

    h:unmount()
end

-- Cell chars concatenate to the original text content.
function suite:test_cells_chars_concat_to_text()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            tui.Text { "Hello" },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5 })

    local cells = h:cells(1)
    local s = ""
    for _, cell in ipairs(cells) do
        s = s .. cell.char
    end
    -- The row has trailing spaces; the prefix must be "Hello"
    lt.assertEquals(s:sub(1, 5), "Hello")

    h:unmount()
end

-- ============================================================================
-- term_type option — terminal capability override
-- ============================================================================

-- With term_type = "iterm2", cursorPosition() appends the OSC1337 SetMark
-- suffix so iTerm2 can track the cursor. This is a non-interactive paint path
-- feature, so we use vterm without interactive mode.
function suite:test_term_type_iterm2_adds_osc1337()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                key = "inp",
                value = "", onChange = function() end,
                width = 15,
            },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5, term_type = "iterm2", interactive = false })
    h:rerender()

    -- OSC1337 SetMark = ESC ] 1337 ; SetMark BEL (0x07)
    local ansi = h:ansi()
    lt.assertNotEquals(ansi:find("\27%]1337;SetMark", 1, false), nil,
        "iterm2 term_type should produce OSC1337 SetMark in cursor-position sequence")

    h:unmount()
end

-- With term_type = "unknown", no OSC1337 suffix is appended.
function suite:test_term_type_unknown_no_osc1337()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                key = "inp",
                value = "", onChange = function() end,
                width = 15,
            },
        }
    end

    local h = testing.harness(App, { cols = 25, rows = 5, term_type = "unknown", interactive = false })
    h:rerender()

    local ansi = h:ansi()
    lt.assertEquals(ansi:find("\27%]1337;SetMark", 1, false), nil,
        "unknown term_type should NOT produce OSC1337")

    h:unmount()
end

-- term_type overrides are restored after unmount: a subsequent render with
-- a different term_type should not see the previous override.
function suite:test_term_type_restored_after_unmount()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                key = "inp",
                value = "", onChange = function() end,
                width = 15,
            },
        }
    end

    -- First render: force iterm2
    local h1 = testing.harness(App, { cols = 25, rows = 5, term_type = "iterm2", interactive = false })
    h1:rerender()
    lt.assertNotEquals(h1:ansi():find("\27%]1337;SetMark", 1, false), nil,
        "iterm2 should emit OSC1337")
    h1:unmount()

    -- Second render: no term_type override — must NOT see iterm2 OSC1337
    local h2 = testing.harness(App, { cols = 25, rows = 5, term_type = "unknown", interactive = false })
    h2:rerender()
    lt.assertEquals(h2:ansi():find("\27%]1337;SetMark", 1, false), nil,
        "after unmount, iterm2 override should be restored; unknown should not emit OSC1337")
    h2:unmount()
end


function suite:test_paste_received_by_text_input()
    local received = ""

    local App = function()
        local val, setVal = tui.useState("")
        received = val  -- capture via upvalue
        return tui.Box {
            width = 30, height = 3,
            extra.TextInput {
                key = "inp",
                value = val,
                onChange = function(v)
                    setVal(v)
                    received = v
                end,
                width = 25,
            },
        }
    end

    local h = testing.harness(App, { cols = 35, rows = 5, interactive = true })
    h:paste("hello world")

    h:rerender()

    lt.assertEquals(received, "hello world")

    h:unmount()
end
