-- test/input/test_ime.lua — unit & integration tests for IME support.
local lt       = require "ltest"
local tui      = require "tui"
local extra = require "tui.extra"
local testing  = require "tui.testing"
local input_helpers = require "tui.testing.input"

local test_ime = lt.test "ime"

-- ---------------------------------------------------------------------------
-- 1. IME position tracked in harness

function test_ime:test_cursor_after_paint()
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
    local col, row = h:cursor()
    lt.assertEquals(col ~= nil, true)
    lt.assertEquals(row ~= nil, true)
    lt.assertEquals(col, 1)  -- caret at col 1 (1-based, first char)
    lt.assertEquals(row, 1)  -- first row

    h:unmount()
end

function test_ime:test_cursor_updates_after_typing()
    local setValue = nil
    local function App()
        local v, setV = tui.useState("")
        setValue = setV
        return extra.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    h:type("abc")
    h:rerender()
    local col, row = h:cursor()
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
    h:rerender()
    -- The confirmed text is now in the value.
    lt.assertEquals(lastValue, "你")
    h:rerender()

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
    h:rerender()

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
    h:rerender()
    -- Value should still be "ab" (composing text not committed).
    -- The visual display includes composing text but value is unchanged.
    local col, row = h:cursor()
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

function test_ime:test_no_cursor_without_focused_input()
    local function App()
        return tui.Text { "no input here" }
    end
    local h = testing.render(App)

    -- No focused TextInput → no IME position.
    local col, row = h:cursor()
    lt.assertEquals(col, nil)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Physical cursor position tests

function test_ime:test_cursor_tracks_typing()
    -- After typing, cursor advances correctly.
    local function App()
        local v, setV = tui.useState("")
        return extra.TextInput { value = v, onChange = setV, width = 20, autoFocus = true }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus sets isFocused state on the next paint; the first
    -- character's _paint() also consumes this dirty flag.
    h:type("abc")
    h:rerender()

    local col, row = h:cursor()
    -- "abc" = 3 chars, caret at end → col 4 (1-based).
    lt.assertEquals(col, 4)
    lt.assertEquals(row, 1)

    h:unmount()
end

function test_ime:test_cursor_inside_bordered_box()
    -- Inside a bordered/padded parent, cursor accounts for the offset applied by Yoga.
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

    local col, row = h:cursor()
    -- Border adds 1 to x/y, paddingX adds 1 to x.
    -- "x" is 1 char, caret at end → offset 1.
    -- Absolute position = (1+1+1+1, 1+1) = (4, 2).
    lt.assertEquals(col, 4)
    lt.assertEquals(row, 2)

    h:unmount()
end

function test_ime:test_cursor_with_cjk_chars()
    -- CJK characters are 2 columns wide; cursor accounts for this.
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

    local col, row = h:cursor()
    -- "中" occupies 2 display columns; caret at end → col 3 (1-based).
    lt.assertEquals(col, 3)
    lt.assertEquals(row, 1)

    h:unmount()
end

function test_ime:test_cursor_integer_coords_only()
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
    local col, row = h:cursor()
    lt.assertEquals(type(col), "number")
    lt.assertEquals(type(row), "number")
    lt.assertEquals(col == math.floor(col), true)
    lt.assertEquals(row == math.floor(row), true)

    h:unmount()
end
