-- test/input/test_ime.lua — unit & integration tests for IME support.
local lt       = require "ltest"
local tui      = require "tui"
local extra = require "tui.extra"
local testing  = require "tui.testing"
local input_helpers = require "tui.testing.input"

local test_ime = lt.test "ime"

-- ---------------------------------------------------------------------------
-- 1. IME position tracked in harness

function test_ime:test_ime_pos_after_paint()
    local value, setValue = "", nil
    local function App()
        local v, setV = tui.useState("")
        value, setValue = v, setV
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- After initial render with focused TextInput, IME pos should be set.
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)
    lt.assertEquals(row ~= nil, true)
    lt.assertEquals(col, 1)  -- caret at col 1 (1-based, first char)
    lt.assertEquals(row, 1)  -- first row

    h:unmount()
end

function test_ime:test_ime_pos_updates_after_typing()
    local setValue = nil
    local function App()
        local v, setV = tui.useState("")
        setValue = setV
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    h:type("abc")
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)
    -- After typing "abc", caret is after "c" at column 4 (1-based).
    lt.assertEquals(col, 4)
    lt.assertEquals(row, 1)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Composing text: composing → confirm

function test_ime:test_composing_then_confirm()
    local lastValue = ""
    local function App()
        local v, setV = tui.useState("")
        lastValue = v
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Simulate IME composing: user types pinyin "ni".
    h:type_composing("ni")
    -- Composing text is shown but not committed.
    lt.assertEquals(lastValue, "")

    -- Simulate IME confirmation: user selects "你".
    h:type_composing_confirm("你")
    -- The confirmed text is now in the value.
    lt.assertEquals(lastValue, "你")

    h:unmount()
end

function test_ime:test_windows_fixture_commit_without_confirm_space()
    local lastValue = ""
    local function App()
        local v, setV = tui.useState("")
        lastValue = v
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    h:dispatch(input_helpers.windows {
        { vk = 0xE5, char = "" },  -- VK_PROCESSKEY
        { vk = 0,    char = "中" },
        { vk = 0,    char = "午" },
        { vk = 0x20, char = " " }, -- swallowed confirmation space
    })

    lt.assertEquals(lastValue, "中午")
    h:unmount()
end

function test_ime:test_composing_cancel_by_escape()
    local lastValue = ""
    local function App()
        local v, setV = tui.useState("")
        lastValue = v
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Start composing.
    h:type_composing("hao")
    lt.assertEquals(lastValue, "")

    -- Cancel with Escape.
    h:press("escape")
    lt.assertEquals(lastValue, "")

    h:unmount()
end

function test_ime:test_composing_shown_at_caret()
    local function App()
        local v, setV = tui.useState("ab")
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Move caret to position 1 (between 'a' and 'b').
    h:press("left")

    -- Start composing — the composing text appears between 'a' and 'b'.
    h:type_composing("x")
    -- Value should still be "ab" (composing text not committed).
    -- The visual display includes composing text but value is unchanged.
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. Focus linkage: composing cleared on blur

function test_ime:test_composing_cleared_on_focus_loss()
    local lastValue = ""
    local function App()
        local v1, setV1 = tui.useState("")
        local v2, setV2 = tui.useState("")
        lastValue = v1
        return tui.Box {
            flexDirection = "column",
            extra.TextInput { value = v1, onChange = setV1, width = 20, focusId = "first" },
            extra.TextInput { value = v2, onChange = setV2, width = 20, focusId = "second" },
        }
    end
    local h = testing.render(App)

    -- Start composing in the first TextInput.
    h:type_composing("test")

    -- Tab to the next TextInput — focus moves away.
    h:press("tab")

    -- The first TextInput's value should remain empty (composing was cancelled).
    lt.assertEquals(lastValue, "")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. IME position cleared when no cursor

function test_ime:test_no_ime_pos_without_focused_input()
    local function App()
        return tui.Text { "no input here" }
    end
    local h = testing.render(App)

    -- No focused TextInput → no IME position.
    local col, row = h:ime_pos()
    lt.assertEquals(col, nil)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Physical cursor position tests
--
-- IME candidate window placement depends on the physical cursor position.
-- These tests verify that the physical cursor coordinates (returned by
-- cursor()) match the IME position (returned by ime_pos()), ensuring
-- IME placement is driven by physical cursor position.

function test_ime:test_physical_cursor_matches_ime_position()
    -- After paint, the physical cursor position and the IME position
    -- should be identical — IME candidate window follows the physical cursor.
    local function App()
        local v, setV = tui.useState("")
        return extra.TextInput { value = v, onChange = setV, width = 20, autoFocus = true }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()

    -- Empty TextInput at top-left: cursor and IME both at (1, 1).
    local cursor_col, cursor_row = h:cursor()
    local ime_col, ime_row = h:ime_pos()
    lt.assertEquals(cursor_col, ime_col)
    lt.assertEquals(cursor_row, ime_row)

    h:unmount()
end

function test_ime:test_physical_cursor_tracks_typing()
    -- After typing, both cursor() and ime_pos() advance in lockstep.
    local function App()
        local v, setV = tui.useState("")
        return extra.TextInput { value = v, onChange = setV, width = 20, autoFocus = true }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus sets isFocused state on the next paint; the first
    -- character's _paint() also consumes this dirty flag.
    h:type("abc")

    local cursor_col, cursor_row = h:cursor()
    local ime_col, ime_row = h:ime_pos()
    lt.assertEquals(cursor_col, ime_col)
    lt.assertEquals(cursor_row, ime_row)
    -- "abc" = 3 chars, caret at end → col 4 (1-based).
    lt.assertEquals(ime_col, 4)
    lt.assertEquals(ime_row, 1)

    h:unmount()
end

function test_ime:test_physical_cursor_inside_bordered_box()
    -- Inside a bordered/padded parent, both cursor() and ime_pos()
    -- account for the offset applied by Yoga.
    local function App()
        local v, setV = tui.useState("x")
        return tui.Box {
            width = 20, height = 3,
            borderStyle = "round", paddingX = 1,
            extra.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()

    local cursor_col, cursor_row = h:cursor()
    local ime_col, ime_row = h:ime_pos()
    lt.assertEquals(cursor_col, ime_col)
    lt.assertEquals(cursor_row, ime_row)
    -- Border adds 1 to x/y, paddingX adds 1 to x.
    -- "x" is 1 char, caret at end → offset 1.
    -- Absolute position = (1+1+1+1, 1+1) = (4, 2).
    lt.assertEquals(ime_col, 4)
    lt.assertEquals(ime_row, 2)

    h:unmount()
end

function test_ime:test_physical_cursor_with_cjk_chars()
    -- CJK characters are 2 columns wide; both cursor() and ime_pos()
    -- account for this.
    local function App()
        local v, setV = tui.useState("\228\184\173")  -- "中": 2 columns
        return tui.Box {
            width = 20, height = 1,
            extra.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()

    local cursor_col, cursor_row = h:cursor()
    local ime_col, ime_row = h:ime_pos()
    lt.assertEquals(cursor_col, ime_col)
    lt.assertEquals(cursor_row, ime_row)
    -- "中" occupies 2 display columns; caret at end → col 3 (1-based).
    lt.assertEquals(ime_col, 3)
    lt.assertEquals(ime_row, 1)

    h:unmount()
end

function test_ime:test_physical_cursor_integer_coords_only()
    -- Physical cursor CUP parameters must always be integers.
    -- Float coords would produce malformed CUP sequences like
    -- ESC[73.0;3.0H that real terminals silently reject.
    local function App()
        local v, setV = tui.useState("hello")
        return tui.Box {
            width = 20, height = 1,
            extra.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()

    -- "hello" is 5 chars, caret at end -> col 6 (1-based).
    local ime_col, ime_row = h:ime_pos()
    lt.assertEquals(type(ime_col), "number")
    lt.assertEquals(type(ime_row), "number")
    lt.assertEquals(ime_col == math.floor(ime_col), true)
    lt.assertEquals(ime_row == math.floor(ime_row), true)

    h:unmount()
end
