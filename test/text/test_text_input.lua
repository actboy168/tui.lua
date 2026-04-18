-- test/test_text_input.lua — unit tests for <TextInput> component.
--
-- Drives the component offscreen via tui.testing: type a key → auto-render →
-- inspect the produced tree and (for onSubmit) the collected callback
-- invocations.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local wcwidth = require "tui_core".wcwidth

-- Local mirror of text_input.lua's to_chars for asserting grapheme counts.
local function to_chars(s)
    local chars = {}
    if not s or s == "" then return chars end
    local n, i = #s, 1
    while i <= n do
        local ch, _, ni = wcwidth.grapheme_next(s, i)
        if ch == "" then break end
        chars[#chars + 1] = ch
        i = ni
    end
    return chars
end

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
    h:rerender()  -- consume autoFocus isFocused state
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
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
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
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
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
            borderStyle = "round", paddingX = 1,
            tui.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
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
    h:rerender()  -- consume autoFocus isFocused state
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
    h:rerender()  -- consume autoFocus isFocused state
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
    h:rerender()  -- consume autoFocus isFocused state
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

-- Right arrow moves the caret one cluster right.
function suite:test_right_arrow_moves_caret()
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
    h:press("home")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    h:press("right")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    h:press("right")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    h:unmount()
end

-- Right arrow across a wide-char cluster jumps by the cluster's display width.
function suite:test_right_arrow_over_wide_char()
    local value = "a\228\184\173b"  -- "a中b"
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
    h:press("home")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    h:press("right")  -- past "a" → col 1
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    h:press("right")  -- past "中" (wide) → col 3
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    h:unmount()
end

-- Right arrow at end of input is a no-op (caret stays, onChange not fired).
function suite:test_right_arrow_at_end_noop()
    local value = "ab"
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
    h:press("right")
    h:press("right")
    lt.assertEquals(fired, 0, "right at end must not fire onChange")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    h:unmount()
end

-- Home moves caret to beginning, End moves it to the end.
function suite:test_home_and_end()
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
    h:press("home")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    h:press("end")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    h:unmount()
end

-- Delete on empty value is a no-op.
function suite:test_delete_on_empty_noop()
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
    h:press("delete")
    h:press("delete")
    lt.assertEquals(value, "")
    lt.assertEquals(fired, 0, "delete on empty must not fire onChange")
    h:unmount()
end

-- Delete at end of value is a no-op.
function suite:test_delete_at_end_noop()
    local value = "abc"
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
    h:press("delete")
    lt.assertEquals(fired, 0, "delete at end must not fire onChange")
    lt.assertEquals(value, "abc")
    h:unmount()
end

-- When the controlled value shrinks externally, the caret is clamped.
function suite:test_caret_clamped_on_value_shrink()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- caret starts at end (col 5)
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 5)
    -- Shrink value externally; caret was at 5 but only 2 chars now.
    v = "ab"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2, "caret clamped to #chars after shrink")
    h:unmount()
end

-- Placeholder is shown when empty and unfocused, hidden when focused.
function suite:test_placeholder_hidden_when_focused()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = setV,
                placeholder = "type here",
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- autoFocus=true by default, so placeholder should NOT be shown,
    -- but isFocused state takes effect on the next paint.
    h:rerender()
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te ~= nil, true, "focused input should have cursor")
    lt.assertEquals(te.text, "", "placeholder should be hidden when focused")
    h:unmount()
end

-- Placeholder shown when value is empty and focus=false.
function suite:test_placeholder_shown_when_unfocused()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                placeholder = "type here",
                focus = false,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te, nil, "unfocused input should have no cursor")
    -- The row should show the placeholder text
    lt.assertEquals(h:row(1):match("type here") ~= nil, true)
    h:unmount()
end

-- Horizontal scroll: when text exceeds the explicit width prop, the window
-- scrolls to keep the caret visible.
function suite:test_horizontal_scroll_keeps_caret_visible()
    local value = "abcdefghij"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                width = 5,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    local te = testing.find_text_with_cursor(h:tree())
    -- Caret sits at end; with width=5 the window scrolls so the caret
    -- column is within the visible window.
    lt.assertEquals(te._cursor_offset <= 5, true,
        "caret col within visible window")
    h:unmount()
end

-- Typing past the width prop scrolls the window so the caret stays in view.
function suite:test_typing_past_width_scrolls()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput { value = v, onChange = setV, autoFocus = true, width = 5 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:type("abcdef")  -- 6 chars in a 5-col window
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset <= 5, true,
        "caret stays within window after overflow typing")
    h:unmount()
end

-- Mask replaces each character including CJK with the mask char.
function suite:test_mask_with_cjk_chars()
    local value = "\228\184\173\230\150\135"  -- "中文"
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
    h:rerender()  -- consume autoFocus isFocused state
    local te = testing.find_text_with_cursor(h:tree())
    -- Each grapheme cluster is replaced by one mask char
    lt.assertEquals(te.text, "**")
    h:unmount()
end

-- Enter on empty value fires onSubmit with empty string.
function suite:test_enter_on_empty_fires_onsubmit()
    local submitted = nil
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = setV,
                onSubmit = function(val) submitted = val end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("enter")
    lt.assertEquals(submitted, "")
    h:unmount()
end

-- width prop constrains the visible rendering width.
function suite:test_width_prop_constrains_render()
    local value = "abcdefghij"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                width = 5,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    local te = testing.find_text_with_cursor(h:tree())
    -- With width=5, only 5 cells of text should be visible
    lt.assertEquals(#te.text <= 5, true,
        "rendered text should be at most width columns")
    h:unmount()
end

-- Left arrow at position 0 is a no-op.
function suite:test_left_at_start_noop()
    local value = "abc"
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
    h:press("home")  -- caret to 0
    h:press("left")  -- no-op at start
    lt.assertEquals(fired, 0, "left at start must not fire onChange")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    h:unmount()
end

-- Insert after navigating with home → right → right → type.
function suite:test_insert_after_home_right_right()
    local value = "abcde"
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
    h:press("home")
    h:press("right")   -- caret at 1 (after "a")
    h:press("right")   -- caret at 2 (after "b")
    h:type("X")        -- insert "X" at position 2 → "abXcde"
    lt.assertEquals(value, "abXcde")
    h:unmount()
end

-- Delete in the middle removes the character to the right of the caret.
function suite:test_delete_in_middle()
    local value = "abcde"
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
    h:press("home")
    h:press("right")   -- caret at 1 (after "a")
    h:press("delete")  -- remove "b" → "acde"
    lt.assertEquals(value, "acde")
    h:unmount()
end

-- Backspace in the middle removes the character to the left of the caret.
function suite:test_backspace_in_middle()
    local value = "abcde"
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
    h:press("home")
    h:press("right")      -- caret at 1
    h:press("right")      -- caret at 2 (after "b")
    h:press("backspace")  -- remove "b" → "acde"
    lt.assertEquals(value, "acde")
    h:unmount()
end

-- Multiple key operations in sequence produce the correct final value.
function suite:test_key_sequence_home_delete_end_backspace()
    local value = "abcde"
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
    h:press("home")     -- caret at 0
    h:press("delete")   -- remove "a" → "bcde"
    lt.assertEquals(value, "bcde")
    h:press("end")      -- caret at 4 (end of "bcde")
    h:press("backspace") -- remove "e" → "bcd"
    lt.assertEquals(value, "bcd")
    h:unmount()
end

-- =========================================================================
-- IME input tests
-- =========================================================================
--
-- IME-confirmed text arrives as UTF-8 bytes through the terminal.  The C
-- parser (keys.parse) splits them into one `name="char"` event per codepoint.
-- Two dispatch modes matter:
--
--   h:type(str)  – one codepoint per dispatch + re-render (matches real
--                   keystroke-by-keystroke input)
--   h:dispatch(bytes) – all codepoints in one batch, one re-render at end
--                   (matches a single terminal read() that returns a buffer
--                   full of characters — e.g. IME commit of multiple chars)
--
-- Bulk dispatch now works correctly: on_input eagerly updates ctxRef.chars
-- and ctxRef.caret after each mutation, so intra-dispatch events see the
-- accumulated state.

-- Single CJK character via dispatch (one IME commit of one character).
function suite:test_ime_single_cjk_via_dispatch()
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
    h:dispatch("\228\184\173")  -- "中" as a single 3-byte event
    lt.assertEquals(value, "\228\184\173")
    h:unmount()
end

-- Multiple CJK characters via dispatch: all characters survive because
-- on_input eagerly updates ctxRef.chars/caret after each mutation.
function suite:test_ime_multi_cjk_via_dispatch()
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
    h:dispatch("\228\184\173\230\150\135")  -- "中文" as two codepoints in one batch
    lt.assertEquals(value, "\228\184\173\230\150\135")
    h:unmount()
end

-- Same two CJK characters via h:type (one codepoint per dispatch + render):
-- works correctly because each character gets its own render pass.
function suite:test_ime_multi_cjk_via_type_works()
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
    h:type("\228\184\173\230\150\135")  -- "中文" — one char at a time
    lt.assertEquals(value, "\228\184\173\230\150\135")
    h:unmount()
end

-- Combining character sequence via h:type: each codepoint arrives as its
-- own dispatch, but to_chars() re-clusters them into a single grapheme.
-- After 'e' is inserted, the next dispatch inserts the combining mark;
-- the combined character occupies one grapheme slot and one display column.
function suite:test_ime_combining_mark_via_type()
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
    -- "e" + COMBINING ACUTE (U+0301) = "é"
    h:type("e\204\129")
    -- The combined "é" is one grapheme cluster; value should be the full
    -- 3-byte sequence (1 byte 'e' + 2 bytes combining mark).
    lt.assertEquals(value, "e\204\129")
    lt.assertEquals(#to_chars(value), 1, "combining mark fuses with base into one cluster")
    h:unmount()
end

-- Flag emoji (two Regional Indicator codepoints) via h:type: each RI
-- codepoint arrives separately, but to_chars() pairs them into one
-- grapheme cluster.
function suite:test_ime_flag_emoji_via_type()
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
    -- 🇯🇵 = RI_J + RI_P, each 4 bytes
    h:type("\240\159\135\175\240\159\135\181")
    lt.assertEquals(value, "\240\159\135\175\240\159\135\181")
    lt.assertEquals(#to_chars(value), 1, "two RI codepoints form one flag cluster")
    h:unmount()
end

-- IME commit in the middle of existing text: move caret, then type a CJK
-- character (simulating an IME commit at that position).
function suite:test_ime_insert_cjk_in_middle()
    local value = "ab"
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
    h:press("home")
    h:press("right")  -- caret at 1 (between "a" and "b")
    h:type("\228\184\173")  -- insert "中" at caret → "a中b"
    lt.assertEquals(value, "a\228\184\173b")
    h:unmount()
end

-- IME commit at the beginning (home then type CJK).
function suite:test_ime_insert_cjk_at_start()
    local value = "ab"
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
    h:press("home")  -- caret at 0
    h:type("\228\184\173")  -- insert "中" → "中ab"
    lt.assertEquals(value, "\228\184\173ab")
    h:unmount()
end

-- Single CJK character via dispatch correctly updates cursor position.
function suite:test_ime_single_cjk_dispatch_cursor()
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
    h:dispatch("\228\184\173")  -- "中"
    local te = testing.find_text_with_cursor(h:tree())
    -- "中" is width 2; caret at end → offset 2
    lt.assertEquals(te._cursor_offset, 2)
    h:unmount()
end

-- IME commit with mixing ASCII and CJK in sequence via h:type.
function suite:test_ime_mixed_ascii_cjk_via_type()
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
    h:type("a\228\184\173b")  -- "a" + "中" + "b"
    lt.assertEquals(value, "a\228\184\173b")
    local te = testing.find_text_with_cursor(h:tree())
    -- a(1) + 中(2) + b(1) = 4 display cols; caret at end = offset 4
    lt.assertEquals(te._cursor_offset, 4)
    h:unmount()
end

-- Multiple ASCII characters via dispatch (one batch, no re-render between).
function suite:test_ime_multi_ascii_via_dispatch()
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
    h:dispatch("abc")  -- 3 ASCII chars in one batch
    lt.assertEquals(value, "abc")
    h:unmount()
end

-- Bulk dispatch followed by a key press operates on the accumulated value.
function suite:test_ime_bulk_dispatch_then_backspace()
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
    h:dispatch("abc")   -- bulk: 3 chars
    h:press("backspace") -- delete "c" → "ab"
    lt.assertEquals(value, "ab")
    h:unmount()
end

-- Mixed ASCII + CJK via dispatch (one batch).
function suite:test_ime_mixed_ascii_cjk_via_dispatch()
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
    -- "a" + "中" + "b" in one dispatch batch
    h:dispatch("a\228\184\173b")
    lt.assertEquals(value, "a\228\184\173b")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 4)
    h:unmount()
end

-- =========================================================================
-- IME composition state transition tests
-- =========================================================================
--
-- The C layer (terminal.c) filters VK_PROCESSKEY during IME composition and
-- only delivers the final committed text as ordinary char events. Therefore
-- "state transitions" in this framework manifest as: how committed text
-- interacts with existing content and cursor position.
--
-- Test dimensions:
--   1. Consecutive IME commits (simulate CJK user typing char by char)
--   2. Cursor operations immediately after IME commit (backspace/left/right)
--   3. Scroll behavior when IME commit overflows a narrow window
--   4. Second commit after a previous one (state persistence)
--   5. Correct cursor offset after IME commit of wide characters

-- Two consecutive IME commits: simulate CJK user typing "你好".
function suite:test_ime_consecutive_commits()
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
    h:dispatch("\228\189\160")  -- "你"
    lt.assertEquals(value, "\228\189\160")
    h:dispatch("\229\165\189")  -- "好"
    lt.assertEquals(value, "\228\189\160\229\165\189")
    local te = testing.find_text_with_cursor(h:tree())
    -- "你好" width = 2 + 2 = 4; caret at end → offset 4
    lt.assertEquals(te._cursor_offset, 4)
    h:unmount()
end

-- Backspace immediately after IME commit deletes the just-committed character.
function suite:test_ime_commit_then_backspace()
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
    h:dispatch("\228\184\173")  -- "中"
    lt.assertEquals(value, "\228\184\173")
    h:press("backspace")
    lt.assertEquals(value, "", "backspace after IME commit should clear value")
    h:unmount()
end

-- After IME commit, press left to move caret, then type to insert.
function suite:test_ime_commit_then_left_then_insert()
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
    h:dispatch("\228\184\173\230\150\135")  -- "中文"
    h:press("left")  -- caret moves past "文" to col 2 (after "中")
    h:type("x")      -- insert "x" between "中" and "文" → "中x文"
    lt.assertEquals(value, "\228\184\173x\230\150\135")
    h:unmount()
end

-- IME commit of wide characters scrolls in a narrow window.
function suite:test_ime_commit_in_narrow_window_scrolls()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = value,
                onChange = function(v) value = v end,
                width = 5,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- Type 3 CJK chars (6 display cols) into width=5 window
    h:dispatch("\228\184\173\230\150\135\228\186\186")  -- "中文人"
    lt.assertEquals(value, "\228\184\173\230\150\135\228\186\186")
    local te = testing.find_text_with_cursor(h:tree())
    -- Caret should be within the visible window (≤ width=5)
    lt.assertEquals(te._cursor_offset <= 5, true,
        "caret must stay within narrow window after IME commit overflow")
    h:unmount()
end

-- Second IME commit after a previous one: cursor and value accumulate correctly.
function suite:test_ime_two_phase_commit()
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
    -- Phase 1: commit "你"
    h:dispatch("\228\189\160")
    lt.assertEquals(value, "\228\189\160")
    local te1 = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te1._cursor_offset, 2, "after first commit caret at col 2")
    -- Phase 2: commit "好" at end
    h:dispatch("\229\165\189")
    lt.assertEquals(value, "\228\189\160\229\165\189")
    local te2 = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te2._cursor_offset, 4, "after second commit caret at col 4")
    h:unmount()
end

-- IME commit in middle of existing text at non-trivial caret position.
function suite:test_ime_commit_in_middle_with_wide_chars()
    local value = "a\228\184\173b"  -- "a中b"
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
    -- Move caret to position after "a" (caret index 1)
    h:press("home")
    h:press("right")  -- past "a"
    -- Commit "好" at caret position 1 → "a好中b"
    h:dispatch("\229\165\189")
    lt.assertEquals(value, "a\229\165\189\228\184\173b")
    -- Cursor offset: a(1) + 好(2) = 3; but caret index is now 2 (after "a","好")
    -- Display: a(1) + 好(2) = offset 3
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    h:unmount()
end

-- IME commit of a flag emoji (4-byte pair) in middle of text.
-- Via dispatch the two RI codepoints arrive as separate char events,
-- so TextInput stores them as two independent graphemes. Each RI has
-- display width 1, so the caret offset after insertion is:
--   x(1) + RI_1(1) + RI_2(1) + remaining = ...
-- The exact offset depends on wcwidth; we verify cursor validity.
function suite:test_ime_commit_flag_in_middle()
    local value = "xy"
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
    h:press("home")
    h:press("right")  -- caret between "x" and "y"
    h:dispatch("\240\159\135\175\240\159\135\181")  -- 🇯🇵 (two RI codepoints)
    lt.assertEquals(value, "x\240\159\135\175\240\159\135\181y")
    local te = testing.find_text_with_cursor(h:tree())
    -- Caret must be valid (non-nil, non-negative) and within the
    -- visible window. The exact offset depends on per-RI display width.
    lt.assertEquals(te ~= nil, true, "cursor must exist after IME flag commit")
    lt.assertEquals(te._cursor_offset >= 0, true,
        "cursor offset must be non-negative after IME flag commit")
    h:unmount()
end

-- IME commit followed by Enter should trigger onSubmit with correct value.
function suite:test_ime_commit_then_submit()
    local submitted = nil
    local value = ""
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
    h:dispatch("\228\184\173")  -- "中"
    h:press("enter")
    lt.assertEquals(submitted, "\228\184\173")
    h:unmount()
end

-- IME commit replacing text after backspace: backspace removes last char,
-- then IME commit inserts new char at same position.
function suite:test_ime_after_backspace_replace()
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
    h:press("backspace")  -- "abc" → "ab"
    lt.assertEquals(value, "ab")
    h:dispatch("\228\184\173")  -- commit "中" → "ab中"
    lt.assertEquals(value, "ab\228\184\173")
    local te = testing.find_text_with_cursor(h:tree())
    -- a(1) + b(1) + 中(2) = 4
    lt.assertEquals(te._cursor_offset, 4)
    h:unmount()
end

-- =========================================================================
-- Cursor out-of-bounds boundary tests
-- =========================================================================
--
-- When the external value shrinks, the caret may exceed the new chars length.
-- TextInput uses useEffect to clamp the caret to #chars, but we must verify
-- correctness in various edge cases.

-- Value externally shrunk to empty string: caret clamped from end to 0.
function suite:test_caret_clamped_to_zero_on_empty_value()
    local v = "hello"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- Caret starts at end of "hello" = col 5
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 5)
    -- Shrink value to empty
    v = ""
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0, "caret clamped to 0 when value becomes empty")
    h:unmount()
end

-- Value externally shrunk to 1 character: caret clamped from far end to 1.
function suite:test_caret_clamped_on_shrink_to_one_char()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- Caret at end = col 5
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 5)
    v = "a"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1, "caret clamped to #chars after shrink to 1 char")
    h:unmount()
end

-- Value externally shrunk with wide chars: offset after clamping uses display width.
function suite:test_caret_clamped_on_shrink_with_wide_chars()
    local v = "\228\184\173\230\150\135abc"  -- "中文abc"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- Caret at end: 中(2)+文(2)+a(1)+b(1)+c(1) = 7
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 7)
    v = "\228\184\173\230\150\135"  -- "中文"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 4,
        "caret clamped to end of wide-char string (2+2=4)")
    h:unmount()
end

-- Progressive shrink of value: caret clamped to new end each time.
function suite:test_caret_clamped_on_progressive_shrink()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 5)
    v = "abcd"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 4)
    v = "ab"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    v = ""
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0, "caret reaches 0 after shrink to empty")
    h:unmount()
end

-- Caret in middle position when value shrinks below caret: should clamp to #chars.
function suite:test_caret_in_middle_clamped_when_value_shrinks_below()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- Move caret to position 3 (between "c" and "d")
    h:press("home")
    h:press("right")
    h:press("right")
    h:press("right")  -- caret at index 3
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    -- Shrink value to "ab" (2 chars); caret 3 > #chars 2 → clamp to 2
    v = "ab"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2,
        "caret in middle clamped when value shrinks below caret position")
    h:unmount()
end

-- Select-all delete: set value to empty string to simulate select-all delete scenario.
function suite:test_caret_after_select_all_delete()
    local v = "hello world"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- Caret at end
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 11)
    -- Simulate select-all delete by externally setting value to ""
    v = ""
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0, "caret at 0 after select-all delete")
    -- Can type again after select-all delete
    h:type("x")
    lt.assertEquals(v, "x")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    h:unmount()
end

-- After caret clamped from value shrink, typing a new char should insert correctly.
function suite:test_type_after_caret_clamp_from_shrink()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- Shrink value to "a"; caret clamps to 1
    v = "a"
    h:rerender()
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    -- Type "x" at clamped position → "ax"
    h:type("x")
    lt.assertEquals(v, "ax")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    h:unmount()
end

-- Backspace on wide char: caret display offset retreats correctly.
function suite:test_backspace_wide_char_caret_offset()
    local value = "a\228\184\173b"  -- "a中b"
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
    h:rerender()  -- consume autoFocus isFocused state
    -- Initial caret at end: a(1)+中(2)+b(1) = offset 4
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 4)
    -- Backspace removes "b": value = "a中", offset = a(1)+中(2) = 3
    h:press("backspace")
    lt.assertEquals(value, "a\228\184\173")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 3)
    -- Backspace removes "中" (wide): value = "a", offset = 1
    h:press("backspace")
    lt.assertEquals(value, "a")
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 1)
    h:unmount()
end

-- Delete on wide char: caret display offset stays unchanged (caret does not move).
function suite:test_delete_wide_char_caret_offset_unchanged()
    local value = "\228\184\173\230\150\135b"  -- "中文b"
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
    -- Move caret to after "中" (index 1), offset = 2
    h:press("home")
    h:press("right")  -- past "中"
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    -- Delete removes "文" (wide char ahead): value = "中b"
    h:press("delete")
    lt.assertEquals(value, "\228\184\173b")
    te = testing.find_text_with_cursor(h:tree())
    -- Caret still at index 1 (after "中"), display offset still 2
    lt.assertEquals(te._cursor_offset, 2,
        "delete of wide char ahead does not move caret offset")
    h:unmount()
end

-- Value externally changed to a longer string: caret stays at previous position without going out of bounds.
function suite:test_caret_stays_when_value_grows_externally()
    local v = "ab"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:rerender()  -- consume autoFocus isFocused state
    -- Caret at end = offset 2
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2)
    -- Value grows externally; caret stays at 2 (valid index within new value)
    v = "abcdefgh"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2,
        "caret stays at previous position when value grows externally")
    h:unmount()
end

-- Value externally replaced with wide-char string: caret stays within valid range.
function suite:test_caret_valid_after_external_wide_char_replacement()
    local v = "abc"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    -- Caret at end of "abc" = offset 3, index 3
    -- Replace with "中" (1 grapheme); caret 3 > #chars 1 → clamp to 1
    v = "\228\184\173"
    h:rerender()
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 2,
        "caret clamped to end of single wide char")
    h:unmount()
end

-- Caret at home position (0): value shrink should not affect caret.
function suite:test_caret_at_home_unaffected_by_shrink()
    local v = "abcde"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:press("home")
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0)
    v = "ab"
    h:rerender()
    te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te._cursor_offset, 0,
        "caret at home unaffected by value shrink")
    h:unmount()
end

-- After caret clamping, absolute cursor position remains a valid integer coordinate.
function suite:test_cursor_integer_after_caret_clamp()
    local v = "abc"
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value = v,
                onChange = function(new_v) v = new_v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    v = ""
    h:rerender()
    local col, row = h:cursor()
    lt.assertEquals(col, 1, "cursor col is integer after clamp to empty")
    lt.assertEquals(row, 1, "cursor row is integer after clamp to empty")
    h:unmount()
end
