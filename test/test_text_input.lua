-- test/test_text_input.lua — unit tests for <TextInput> component.
--
-- Drives the component offscreen via tui.testing: type a key → auto-render →
-- inspect the produced tree and (for onSubmit) the collected callback
-- invocations.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "text_input"

function suite:test_initial_empty_with_placeholder()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                placeholder = "type here",
                focus = false,  -- unfocused to show placeholder
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    -- focus=false → no cursor tag.
    lt.assertEquals(te, nil)
    h:unmount()
end

function suite:test_char_insertion_updates_value()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:type("hi")   -- 'h' then 'i'; each keystroke auto-rerenders between
    lt.assertEquals(value, "hi")
    h:unmount()
end

function suite:test_cjk_insertion_updates_value()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- Simulate IME-confirmed "中" then "文" as two UTF-8 bursts; :type walks
    -- UTF-8 boundaries so each 3-byte codepoint goes out as one dispatch.
    h:type("\228\184\173\230\150\135")  -- "中文"
    lt.assertEquals(value, "\228\184\173\230\150\135")
    h:unmount()
end

function suite:test_backspace_deletes_last_char()
    local value = "abc"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("backspace")
    lt.assertEquals(value, "ab")
    h:unmount()
end

function suite:test_left_arrow_moves_caret_and_insert_in_middle()
    local value = "ac"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("left")  -- caret 2 → 1; :press auto-rerenders so caret is committed
    h:type("b")      -- insert "b" at position 1 → "abc"
    lt.assertEquals(value, "abc")
    h:unmount()
end

function suite:test_enter_triggers_onsubmit()
    local submitted = nil
    local value = "hello"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("enter")
    lt.assertEquals(submitted, "hello")
    h:unmount()
end

function suite:test_unfocused_ignores_input()
    local value = "start"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                focus = false,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:type("xyz")
    lt.assertEquals(value, "start")
    h:unmount()
end

function suite:test_cursor_offset_tracks_caret_column()
    local value = "\228\184\173a"  -- "中a": 2 cols + 1 col = caret at end = col 3
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te ~= nil, true)
    lt.assertEquals(te._cursor_offset, 3)
    h:unmount()
end

-- Cursor absolute (col,row) is at the expected screen cell — catches both
-- the float-coord regression and any off-by-one in the rect math.
function suite:test_cursor_absolute_position_at_caret()
    local function App()
        local v, setV = tui.useState("hello")
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local col, row = h:cursor()
    -- TextInput sits at the top-left of the 20x1 Box with no padding.
    -- "hello" is 5 cols, caret at end -> offset 5; 1-based abs = (6, 1).
    lt.assertEquals(col, 6)
    lt.assertEquals(row, 1)
    h:unmount()
end

-- Typing characters advances the cursor column; deleting moves it back.
function suite:test_cursor_advances_on_type_and_backspace()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 30, height = 1,
            tui.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 1 })
    local col0 = h:cursor()
    lt.assertEquals(col0, 1, "empty input caret sits at col 1")
    h:type("abc")
    local col1 = h:cursor()
    lt.assertEquals(col1, 4, "after 'abc' caret sits at col 4")
    h:press("backspace")
    local col2 = h:cursor()
    lt.assertEquals(col2, 3, "after backspace caret moves one back")
    h:unmount()
end

-- Cursor in a padded/bordered parent must account for the offset that
-- Yoga applies to the TextInput's rect.
function suite:test_cursor_inside_bordered_padded_box()
    local function App()
        local v, setV = tui.useState("x")
        return tui.Box {
            width = 20, height = 3,
            border = "round", paddingX = 1,
            tui.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    local col, row = h:cursor()
    -- Border adds 1 to x/y, paddingX adds 1 to x. "x" is 1 char wide,
    -- caret at end -> offset 1. Absolute = (1+1+1+1, 1+1) = (4, 2).
    lt.assertEquals(col, 4)
    lt.assertEquals(row, 2)
    h:unmount()
end

function suite:test_mask_hides_chars_but_preserves_width()
    local value = "abcd"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                mask = "*",
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te.text, "****")
    lt.assertEquals(te._cursor_offset, 4)
    h:unmount()
end

-- Stage 12: backspace removes a whole grapheme cluster, not just one code point.
function suite:test_backspace_removes_cluster()
    -- "e" + COMBINING ACUTE (2 bytes) forms one grapheme. A single
    -- backspace should delete the entire cluster, leaving the field empty.
    local value = "e\204\129"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("backspace")
    lt.assertEquals(value, "")
    h:unmount()
end

-- Stage 12: regional indicator pair counts as a single char column-wise.
function suite:test_flag_is_single_cluster()
    local value = "\240\159\135\175\240\159\135\181"  -- 🇯🇵
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te ~= nil, true)
    -- Caret sits after the single flag cluster (width 2).
    lt.assertEquals(te._cursor_offset, 2)
    -- One backspace should remove the whole flag.
    h:press("backspace")
    lt.assertEquals(value, "")
    h:unmount()
end

-- Stage 15: 1000 sequential character insertions grow the value correctly.
-- Uses h:type (re-renders between keystrokes) which matches real keyboard
-- input. A single bundled dispatch is a different case (stale caret state
-- across intra-dispatch events) and is not what TextInput is designed for.
function suite:test_large_sequential_typing()
    local value = ""
    local function App()
        return tui.Box {
            width = 1000, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 1000, rows = 1 })
    local payload = string.rep("a", 1000)
    h:type(payload)
    lt.assertEquals(#value, 1000)
    lt.assertEquals(value:sub(1, 5), "aaaaa")
    lt.assertEquals(value:sub(-5), "aaaaa")
    h:unmount()
end

-- Stage 15: backspace on empty value is a no-op (no error, onChange not fired).
function suite:test_backspace_on_empty_noop()
    local value = ""
    local fired = 0
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v; fired = fired + 1 end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("backspace")
    h:press("backspace")
    lt.assertEquals(value, "")
    lt.assertEquals(fired, 0, "onChange must not fire on empty backspace")
    h:unmount()
end

-- Stage 15: left-arrow across a wide-char grapheme boundary moves one cluster,
-- not one code point — caret column decreases by the full cluster width.
function suite:test_left_arrow_over_wide_char_moves_one_cluster()
    local value = "a\228\184\173b"  -- "a中b": cols 1, 2(wide), 1
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    -- Initial caret at end: col = 1 + 2 + 1 = 4.
    lt.assertEquals(te._cursor_offset, 4)
    h:press("left")  -- past "b" → col 3
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    h:press("left")  -- past "中" (wide) → col 1
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    h:press("left")  -- past "a" → col 0
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    h:unmount()
end

-- Stage 15: delete key at caret removes the cluster to the right (not just
-- a single code point).
function suite:test_delete_removes_cluster_forward()
    local value = "e\204\129x"  -- "é" + "x"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("home")         -- caret to 0
    h:press("delete")       -- remove the "é" cluster
    lt.assertEquals(value, "x")
    h:unmount()
end
