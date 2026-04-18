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
            borderStyle = "round", paddingX = 1,
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
    -- autoFocus=true by default, so placeholder should NOT be shown
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
