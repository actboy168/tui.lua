-- test/extra/test_textarea.lua — unit tests for <Textarea> component.
--
-- Drives the component offscreen via tui.testing: dispatch input bytes →
-- auto-render → inspect onChange callbacks and cursor position.

local lt       = require "ltest"
local tui      = require "tui"
local Textarea = require "tui.extra.textarea".Textarea
local testing  = require "tui.testing"
local input_helpers = require "tui.testing.input"

local suite = lt.test "textarea"

local function key_event(name, input, ctrl, shift, meta)
    return {
        name = name,
        input = input or "",
        raw = input or "",
        ctrl = ctrl or false,
        shift = shift or false,
        meta = meta or false,
    }
end

-- ---------------------------------------------------------------------------
-- Helpers.
-- ---------------------------------------------------------------------------

-- Find all Text elements in the tree and collect their string content.
local function collect_lines(tree)
    local out = {}
    local function walk(node)
        if not node then return end
        if node._type == "text" or node.type == "text" then
            local s = ""
            if node.children then
                for _, ch in ipairs(node.children) do
                    if type(ch) == "string" then s = s .. ch end
                end
            end
            out[#out + 1] = s
        end
        if node.children then
            for _, ch in ipairs(node.children) do
                if type(ch) == "table" then walk(ch) end
            end
        end
    end
    walk(tree)
    return out
end

-- ---------------------------------------------------------------------------
-- Basic insertion.
-- ---------------------------------------------------------------------------

function suite:test_initial_value_shown()
    local value = "hello"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Value should not change without any input.
    lt.assertEquals(value, "hello")
    h:unmount()
end

function suite:test_char_insertion()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type("hi")
    lt.assertEquals(value, "hi")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Enter inserts a newline.
-- ---------------------------------------------------------------------------

-- Enter submits; Shift+Enter inserts a newline.
function suite:test_enter_submits()
    local value = "hello"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("enter")
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "hello")
    h:unmount()
end

function suite:test_shift_enter_inserts_newline()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type("a")
    h:dispatch(input_helpers.raw("\x1b[13;2u"))  -- Shift+Enter → insert newline
    h:type("b")
    lt.assertEquals(value, "a\nb")
    h:unmount()
end

-- Auto-grow: after inserting a newline the cursor should sit on the NEW last
-- line and both lines must be visible (scroll_top must stay 0).
-- This test would have failed before the make_emit vis_height fix because
-- clamp_scroll used the stale vis_height=1, pushing scroll_top to 1 and
-- scrolling line 1 out of view.
function suite:test_newline_cursor_on_last_line()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 10,
            Textarea { value = value, onChange = function(v) value = v end },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 10 })
    h:type("hello")
    h:dispatch(input_helpers.raw("\x1b[13;2u"))  -- Shift+Enter → insert newline
    -- Cursor must be on row 2 (second line), column 1 (after the scroll origin).
    local col, row = h:cursor()
    lt.assertEquals(row, 2, "cursor should be on line 2 after newline")
    lt.assertEquals(col, 1, "cursor should be at column 1 (start of new line)")
    -- Both lines must be visible: row 1 shows "hello", row 2 shows "".
    lt.assertEquals(h:row(1), "hello               ")
    lt.assertEquals(h:row(2), "                    ")
    h:unmount()
end
-- When content grows beyond the terminal height, the textarea should cap its
-- height at terminal rows and scroll so the cursor remains visible.
-- Previously vis_height was unbounded (= nlines), causing the terminal to clip
-- the top rows and leaving the cursor off-screen.
function suite:test_scroll_when_taller_than_terminal()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 5,
            Textarea { value = value, onChange = function(v) value = v end },
        }
    end
    -- Terminal is only 5 rows; type 7 lines.
    local h = testing.render(App, { cols = 20, rows = 5 })
    for i = 1, 6 do
        h:type("line" .. i)
        h:dispatch(input_helpers.raw("\x1b[13;2u"))  -- Shift+Enter
    end
    h:type("line7")
    -- value should have 7 lines
    lt.assertEquals(value, "line1\nline2\nline3\nline4\nline5\nline6\nline7")
    -- Cursor must be visible (within the 5-row terminal)
    local col, row = h:cursor()
    assert(row ~= nil, "cursor should be visible")
    assert(row >= 1 and row <= 5, "cursor row must be within terminal: got " .. tostring(row))
    -- The last line "line7" must appear somewhere in the visible rows
    local found = false
    for r = 1, 5 do
        if h:row(r):match("^line7") then found = true; break end
    end
    assert(found, "last line 'line7' should be visible in the terminal")
    h:unmount()
end

-- When content grows beyond the terminal height inside a BORDERED container,
-- the bottom border must appear on the last visible row and the cursor must
-- remain visible (not pushed behind the border).
function suite:test_scroll_taller_than_terminal_with_border()
    local value = ""
    local function App()
        -- 7-row terminal; bordered box fills it; textarea inside.
        -- border takes 2 rows (top+bottom), leaving 5 for textarea content.
        return tui.Box {
            flexDirection = "column",
            tui.Box {
                borderStyle = "single",
                Textarea { value = value, onChange = function(v) value = v end },
            },
        }
    end
    -- Terminal is only 7 rows; type 8 lines so textarea overflows.
    local h = testing.render(App, { cols = 20, rows = 7 })
    for i = 1, 7 do
        h:type("L" .. i)
        h:dispatch(input_helpers.raw("\x1b[13;2u"))  -- Shift+Enter
    end
    h:type("L8")
    -- Cursor must be visible (within the 7-row terminal)
    local col, row = h:cursor()
    assert(row ~= nil, "cursor should be visible")
    assert(row >= 1 and row <= 7, "cursor row must be within terminal: got " .. tostring(row))
    -- Bottom border must appear on the last terminal row
    local last_row = h:row(7)
    assert(last_row:find("\xe2\x94\x98") or last_row:find("\xe2\x94\x94") or last_row:find("+"),
        "bottom border should appear on last terminal row, got: " .. last_row)
    -- The last typed line "L8" must be visible somewhere in the terminal
    local found = false
    for r = 1, 7 do
        if h:row(r):match("L8") then found = true; break end
    end
    assert(found, "last line 'L8' should be visible in the terminal")
    -- Cursor must NOT be on the last row (that's the border)
    assert(row < 7, "cursor should not be on the border row, got row=" .. tostring(row))
    h:unmount()
end


function suite:test_backspace_merges_lines()
    local value = "a\nb"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Caret starts at end of last line (line 2, col 1 = after "b").
    -- Move to beginning of "b" line then backspace to merge.
    h:press("home")
    h:press("backspace")
    lt.assertEquals(value, "ab")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Up/Down arrow navigation.
-- ---------------------------------------------------------------------------

function suite:test_up_down_navigation()
    local value = "abc\nxyz"
    local calls = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v; calls[#calls + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Caret is at end of "xyz" (line 2, col 3).
    -- Press Up → should move to line 1, col min(3, 3) = 3 (end of "abc").
    -- Then type to confirm we're on line 1.
    h:press("up")
    h:type("!")
    lt.assertEquals(value, "abc!\nxyz")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Paste inserts multi-line text.
-- ---------------------------------------------------------------------------

function suite:test_paste_singleline()
    local value = ""
    local function App()
        return tui.Box {
            width = 40, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 4 })
    h:dispatch(input_helpers.paste("hello world"))
    lt.assertEquals(value, "hello world")
    h:unmount()
end

function suite:test_paste_multiline()
    local value = ""
    local function App()
        return tui.Box {
            width = 40, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 4 })
    h:dispatch(input_helpers.paste("line1\nline2\nline3"))
    lt.assertEquals(value, "line1\nline2\nline3")
    h:unmount()
end

function suite:test_paste_into_existing_text()
    local value = "ac"
    local function App()
        return tui.Box {
            width = 40, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 4 })
    -- Caret at end of "ac"; press Left to get before 'c', then paste "b".
    h:press("left")
    h:dispatch(input_helpers.paste("b"))
    lt.assertEquals(value, "abc")
    h:unmount()
end

function suite:test_paste_multiline_into_existing_text()
    local value = "start end"
    local function App()
        return tui.Box {
            width = 40, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 4 })
    -- Move to end of "start " (position 6), paste "mid1\nmid2\n".
    h:press("home")
    for _ = 1, 6 do h:press("right") end
    h:dispatch(input_helpers.paste("mid1\nmid2\n"))
    lt.assertEquals(value, "start mid1\nmid2\nend")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Delete across line boundary.
-- ---------------------------------------------------------------------------

function suite:test_delete_merges_next_line()
    local value = "a\nb"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Caret at end of "b" (line 2). Move up to end of "a" (line 1).
    h:press("up")
    h:press("end")
    h:press("delete")
    lt.assertEquals(value, "ab")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Ctrl+Enter triggers onSubmit without inserting newline.
-- ---------------------------------------------------------------------------

function suite:test_ctrl_enter_submit()
    local value = "hello"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Ctrl+Enter should call onSubmit and NOT change the value.
    -- The testing harness cannot inject ctrl+enter via :press, so we use
    -- h:dispatch_event() which bypasses key parsing.
    h:dispatch_event({ name = "enter", ctrl = true, meta = false, shift = false, input = "\r", raw = "\r" })
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "hello")
    lt.assertEquals(value, "hello")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Shift+Enter via ESC[13;2u (kitty-style, emitted by tui_terminal.c on
-- Windows when Shift+Enter is pressed) inserts a newline.
-- ---------------------------------------------------------------------------

function suite:test_shift_enter_inserts_newline_via_csi_u()
    local value = "hi"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- ESC [ 1 3 ; 2 u  (Shift+Enter in kitty keyboard protocol) → insert newline
    h:dispatch(input_helpers.raw("\x1b[13;2u"))
    h:_paint()
    lt.assertEquals(#submitted, 0)
    lt.assertEquals(value, "hi\n")
    h:unmount()
end

-- Ctrl+Enter via ESC[13;5u (kitty-style) triggers onSubmit.
function suite:test_ctrl_enter_submit_via_csi_u()
    local value = "world"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- ESC [ 1 3 ; 5 u  (Ctrl+Enter in kitty keyboard protocol)
    h:dispatch(input_helpers.raw("\x1b[13;5u"))
    h:_paint()
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "world")
    lt.assertEquals(value, "world")
    h:unmount()
end

function suite:test_ctrl_home_and_ctrl_end_move_across_document()
    local value = "abc\ndef"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("ctrl+a")
    h:type("X")
    lt.assertEquals(value, "X")
    h:press("backspace")
    h:paste("abc\ndef")
    lt.assertEquals(value, "abc\ndef")
    h:press("ctrl+home")
    h:type("Y")
    lt.assertEquals(value, "Yabc\ndef")
    h:press("ctrl+end")
    h:type("Z")
    lt.assertEquals(value, "Yabc\ndefZ")
    h:unmount()
end

function suite:test_ctrl_u_ctrl_k_and_ctrl_w_are_line_local()
    local value = "hello\nwide words here"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("ctrl+w")
    lt.assertEquals(value, "hello\nwide words ")
    h:press("ctrl+u")
    lt.assertEquals(value, "hello\n")
    h:type("again")
    h:press("ctrl+a")
    h:type("X")
    lt.assertEquals(value, "X")
    h:press("backspace")
    h:paste("hello\nagain")
    h:press("home")
    h:press("ctrl+k")
    lt.assertEquals(value, "hello\n")
    h:unmount()
end

function suite:test_ctrl_left_right_and_delete_are_word_aware()
    local value = "hello brave world"
    local function App()
        return tui.Box {
            width = 30, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 4 })
    h:press("ctrl+left")
    h:press("ctrl+left")
    h:type("X")
    lt.assertEquals(value, "hello Xbrave world")
    h:press("ctrl+delete")
    lt.assertEquals(value, "hello Xworld")
    h:unmount()
end

function suite:test_enter_behavior_newline()
    local value = "hello"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                enterBehavior = "newline",
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("enter")
    lt.assertEquals(value, "hello\n")
    lt.assertEquals(#submitted, 0)
    h:press("ctrl+enter")
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "hello\n")
    h:unmount()
end

function suite:test_shift_left_type_replaces_textarea_selection()
    local value = "abcd"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("shift+left")
    h:type("X")
    lt.assertEquals(value, "abcX")
    h:unmount()
end

function suite:test_shift_up_paste_replaces_multiline_selection()
    local value = "ab\ncd"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("shift+up")
    h:paste("Z")
    lt.assertEquals(value, "abZ")
    h:unmount()
end

function suite:test_textarea_ime_confirm_replaces_selection()
    local value = "ab\ncd"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("home")
    h:press("shift+end")
    h:type_composing_confirm("中")
    lt.assertEquals(value, "ab\n中")
    h:unmount()
end

function suite:test_ctrl_a_highlights_multiline_selection()
    local value = "ab\ncd"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:dispatch_event(key_event("char", "a", true))
    local row1 = h:cells(1)
    local row2 = h:cells(2)
    lt.assertEquals(row1[1].inverse, true)
    lt.assertEquals(row1[2].inverse, true)
    lt.assertEquals(row2[1].inverse, true)
    lt.assertEquals(row2[2].inverse, true)
    h:unmount()
end

function suite:test_copy_cut_undo_redo()
    local value = "ab\ncd"
    local clipboard = require "tui.internal.clipboard"
    local old_copy = clipboard.copy
    local copied = {}
    clipboard.copy = function(text)
        copied[#copied + 1] = text
        return true
    end
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:dispatch_event(key_event("char", "a", true))
    h:dispatch_event(key_event("char", "c", true, true))
    lt.assertEquals(copied[1], "ab\ncd")
    h:dispatch_event(key_event("char", "x", true))
    lt.assertEquals(copied[2], "ab\ncd")
    lt.assertEquals(value, "")
    h:dispatch_event(key_event("char", "z", true))
    lt.assertEquals(value, "ab\ncd")
    h:dispatch_event(key_event("char", "y", true))
    lt.assertEquals(value, "")
    clipboard.copy = old_copy
    h:unmount()
end

function suite:test_textarea_typing_undo_coalesces()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type("ab")
    h:dispatch_event(key_event("char", "z", true))
    lt.assertEquals(value, "")
    h:dispatch_event(key_event("char", "y", true))
    lt.assertEquals(value, "ab")
    h:unmount()
end

function suite:test_can_disable_undo_and_redo_feature()
    local value = "ab"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                height = 4,
                features = { undoRedo = false },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type("c")
    lt.assertEquals(value, "abc")
    h:dispatch_event(key_event("char", "z", true))
    lt.assertEquals(value, "abc")
    h:dispatch_event(key_event("char", "y", true))
    lt.assertEquals(value, "abc")
    h:unmount()
end

function suite:test_can_disable_selection_copy_word_kill_features()
    local value = "ab\ncd"
    local clipboard = require "tui.internal.clipboard"
    local old_copy = clipboard.copy
    local copied = {}
    clipboard.copy = function(text)
        copied[#copied + 1] = text
        return true
    end
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                height = 4,
                features = {
                    selection = false,
                    copyCut = false,
                    selectAll = false,
                    wordOps = false,
                    killOps = false,
                },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("shift+up")
    h:type("!")
    lt.assertEquals(value, "ab!\ncd")
    h:dispatch_event(key_event("char", "x", true))
    lt.assertEquals(value, "ab!\ncd")
    lt.assertEquals(#copied, 0)
    h:press("ctrl+left")
    h:type("?")
    lt.assertEquals(value, "ab!?\ncd")
    h:press("ctrl+k")
    lt.assertEquals(value, "ab!?\ncd")
    clipboard.copy = old_copy
    h:unmount()
end

function suite:test_can_disable_paste_submit_and_ime_preview_features()
    local value = "ab"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
                features = {
                    paste = false,
                    submit = false,
                    imeComposing = false,
                },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:paste("ZZ")
    lt.assertEquals(value, "ab")
    h:press("enter")
    lt.assertEquals(#submitted, 0)
    lt.assertEquals(value, "ab")
    h:type_composing("中")
    lt.assertEquals(h:row(1):match("中") ~= nil, false)
    h:type_composing_confirm("中")
    lt.assertEquals(value, "ab中")
    h:unmount()
end

function suite:test_can_customize_textarea_keymap()
    local value = "ab"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
                keymap = {
                    ["enter"] = false,
                    ["shift+enter"] = false,
                    ["ctrl+enter"] = false,
                    ["ctrl+j"] = "newline",
                    ["ctrl+s"] = "submit",
                },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("enter")
    lt.assertEquals(value, "ab")
    lt.assertEquals(#submitted, 0)
    h:dispatch_event(key_event("char", "j", true))
    lt.assertEquals(value, "ab\n")
    h:dispatch_event(key_event("char", "s", true))
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "ab\n")
    h:unmount()
end

function suite:test_can_customize_textarea_core_keymap()
    local value = "ab\ncd"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                height = 4,
                keymap = {
                    ["left"] = false,
                    ["up"] = false,
                    ["backspace"] = false,
                    ["ctrl+b"] = "moveLeft",
                    ["ctrl+p"] = "moveUp",
                    ["ctrl+d"] = "deleteForward",
                },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("left")
    h:type("x")
    lt.assertEquals(value, "ab\ncdx")
    h:dispatch_event(key_event("char", "b", true))
    h:type("?")
    lt.assertEquals(value, "ab\ncd?x")
    h:dispatch_event(key_event("char", "p", true))
    h:type("!")
    lt.assertEquals(value, "ab!\ncd?x")
    h:dispatch_event(key_event("char", "d", true))
    lt.assertEquals(value, "ab!cd?x")
    h:unmount()
end

function suite:test_composing_preview_and_confirm_on_textarea()
    local value = "ab"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type_composing("中")
    lt.assertEquals(value, "ab")
    lt.assertEquals(h:row(1):match("^ab中") ~= nil, true)
    h:type_composing_confirm("中")
    lt.assertEquals(value, "ab中")
    h:unmount()
end

function suite:test_escape_clears_textarea_composing_preview()
    local value = "ab"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type_composing("中")
    lt.assertEquals(h:row(1):match("^ab中") ~= nil, true)
    h:dispatch_event({ name = "escape", ctrl = false, meta = false, shift = false, input = "", raw = "\27" })
    lt.assertEquals(value, "ab")
    lt.assertEquals(h:row(1):match("^ab中") == nil, true)
    lt.assertEquals(h:row(1):match("^ab") ~= nil, true)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- VS Code sendSequence Shift+Enter: "\" + CR + LF (0x5C 0x0D 0x0A).
-- The dispatch() pre-processor converts this to ESC[13;2u before parsing,
-- which results in {name="enter", shift=true} → insert newline.
-- ---------------------------------------------------------------------------

function suite:test_vscode_shift_enter_inserts_newline()
    local value = "hello"
    local submitted = {}
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea {
                value = value,
                onChange = function(v) value = v end,
                onSubmit = function(v) submitted[#submitted + 1] = v end,
                height = 4,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- VS Code sendSequence { text = "\\\r\n" } → 0x5C 0x0D 0x0A → ESC[13;2u → newline
    h:dispatch("\x5c\x0d\x0a")
    h:_paint()
    lt.assertEquals(#submitted, 0)
    lt.assertEquals(value, "hello\n")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Up/Down cursor navigation tests (display-column aware).
-- ---------------------------------------------------------------------------

function suite:test_up_snaps_to_display_column()
    -- Line 1: "ab中c"  (widths: 1 1 2 1, display cols: 0 1 2 4 5)
    -- Line 2: "xyz"    (widths: 1 1 1)
    -- Caret at end of "xyz" = line 2, col 3, display x=3.
    -- Press Up: target display x=3, line 1 has chars at x=0,1,2,4.
    --   x=2 is left edge of '中' (width 2), x=4 is right edge.
    --   3 is equidistant (3-2=1, 4-3=1): col_for_x snaps to the right edge = idx 3.
    --   So caret → line 1, col 3 (after '中').
    -- Then pressing End should be at col 4 (end of line), type '!' → "ab中c!"
    local value = "ab\xe4\xb8\xad" .. "c\nxyz"  -- "ab中c\nxyz"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Caret starts at end of "xyz" (line 2, col 3, x=3).
    h:press("up")    -- → line 1, col 3 (after 中, x=4 or x=3 clamped)
    h:press("end")   -- → line 1, col 4 (after 'c')
    h:type("!")
    -- value should be "ab中c!\nxyz"
    lt.assertEquals(value, "ab\xe4\xb8\xad" .. "c!\nxyz")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Split escape-sequence robustness (Windows read_raw may deliver ESC alone
-- in one call and the rest of the CSI sequence in the next).
-- ---------------------------------------------------------------------------

function suite:test_split_esc_right_arrow()
    -- Simulate: ESC arrives alone, then [C arrives separately.
    -- Expected: cursor moves right (no chars inserted).
    local value = "ab"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:press("home")            -- cursor at col 0
    h:dispatch(input_helpers.raw("\x1b"))         -- ESC alone (should be buffered, not "escape")
    h:dispatch("[C")           -- rest of right-arrow CSI
    -- Value must be unchanged (cursor moved; nothing inserted)
    lt.assertEquals(value, "ab")
    h:unmount()
end

function suite:test_split_esc_up_arrow()
    -- Two-line value; caret on line 2. Split ESC + [A should move up, not insert.
    local value = "foo\nbar"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:dispatch(input_helpers.raw("\x1b"))
    h:dispatch("[A")           -- up arrow split
    h:type("!")                -- should land on line 1
    lt.assertEquals(value, "foo!\nbar")
    h:unmount()
end

function suite:test_split_esc_bracket_then_final()
    -- Three-piece split: ESC | [ | A
    local value = "foo\nbar"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:dispatch(input_helpers.raw("\x1b"))
    h:dispatch("[")
    h:dispatch("A")            -- up arrow delivered byte-by-byte
    h:type("!")
    lt.assertEquals(value, "foo!\nbar")
    h:unmount()
end

function suite:test_sticky_x_through_short_line()
    -- Line 1: "abcde"  (x=5 at end)
    -- Line 2: "x"      (x=1 at end)
    -- Line 3: "fghij"  (x=5 at end)
    -- Caret at end of line 1 (x=5). Down → line 2, col 1 (clamped, x=1).
    -- Down again (sticky x=5) → line 3, col 5 (back to end).
    local value = "abcde\nx\nfghij"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    -- Caret at end of "fghij" (line 3, col 5). Press Up twice to reach line 1.
    h:press("up")   -- line 3→2, sticky x=5, col clamped to 1
    h:press("up")   -- line 2→1, sticky x=5 still, col=5
    h:type("!")
    lt.assertEquals(value, "abcde!\nx\nfghij")
    h:unmount()
end

function suite:test_windows_ime_confirm_space_not_inserted()
    local input_helpers = require "tui.testing.input"
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 4,
            Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    local bytes = input_helpers.windows {
        { vk = 0xE5, char = "" },  -- VK_PROCESSKEY
        { vk = 0,    char = "中" },
        { vk = 0,    char = "午" },
        { vk = 0x20, char = " " }, -- swallowed confirmation space
        { vk = 0xE5, char = "" },
        { vk = 0,    char = "中" },
        { vk = 0,    char = "午" },
        { vk = 0x20, char = " " },
    }
    h:dispatch(bytes)
    lt.assertEquals(value, "中午中午")
    h:unmount()
end

-- =========================================================================
-- Mouse click tests (via testing.load_app)
-- =========================================================================
--
-- Uses chat.lua (which has a Textarea) to test mouse interactions
-- end-to-end through the hit-test pipeline.

local function find_clickable_box(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "box" and e.props and type(e.props.onClick) == "function" then
            return e
        end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

local function find_scrollable_box(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "box" and e.props and type(e.props.onScroll) == "function" then
            return e
        end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

-- Click on the Textarea to focus it, then type to verify input goes in.
function suite:test_click_focuses_textarea()
    testing.capture_stderr(function()
        local App = testing.load_app("test/apps/textarea_app.lua")
        local h   = testing.render(App, { cols = 30, rows = 6 })

        -- Find the Textarea's clickable Box and click it.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a clickable Box")
        local r = box.rect
        h:mouse("down", 1, r.x + 1, r.y + 1)
        h:mouse("up", 1, r.x + 1, r.y + 1)

        -- Type into the now-focused Textarea.
        h:type("hello")
        local frame = h:frame()
        lt.assertNotEquals(frame:find("hello", 1, true), nil,
            "typed text should appear in the Textarea")
        h:unmount()
    end)
end

-- Click at a specific column in the Textarea to reposition the cursor.
function suite:test_click_positions_cursor_in_textarea()
    testing.capture_stderr(function()
        local App = testing.load_app("test/apps/textarea_app.lua")
        local h   = testing.render(App, { cols = 30, rows = 6 })

        -- Type some text first (autoFocus).
        h:type("abcde")

        -- Find the Textarea's clickable Box.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil)
        local r = box.rect

        -- Click at column offset 2 (3rd cell) within the Box.
        local click_x = r.x + 1 + 2
        local click_y = r.y + 1
        h:mouse("down", 1, click_x, click_y)
        h:mouse("up", 1, click_x, click_y)

        -- Type at the new cursor position.
        h:type("X")
        local frame = h:frame()
        lt.assertNotEquals(frame:find("abXcde", 1, true), nil,
            "cursor should be repositioned by click")
        h:unmount()
    end)
end

-- Click on a specific row in a multi-line Textarea to move the cursor
-- to that line.
function suite:test_click_moves_to_different_line()
    testing.capture_stderr(function()
        local App = testing.load_app("test/apps/textarea_app.lua")
        local h   = testing.render(App, { cols = 30, rows = 6 })

        -- Type two lines of text.
        h:type("line1")
        h:press("shift+enter")
        h:type("line2")

        -- Find the Textarea's clickable Box.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil)
        local r = box.rect

        -- Cursor is at end of "line2" (row 1). Click on row 0 at col 5
        -- (past the '1' in "line1") to move caret to end of line 1.
        local click_x = r.x + 1 + 5  -- col 5 within the Box (past "line1")
        local click_y = r.y + 1       -- first row of the Box (0-based row 0)
        h:mouse("down", 1, click_x, click_y)
        h:mouse("up", 1, click_x, click_y)

        -- Type to verify we're at end of line 1.
        h:type("!")
        local frame = h:frame()
        lt.assertNotEquals(frame:find("line1!", 1, true), nil,
            "should type on line 1 after clicking it")
        h:unmount()
    end)
end

-- Mouse scroll in the Textarea scrolls the viewport when content overflows.
function suite:test_scroll_in_textarea()
    testing.capture_stderr(function()
        local App = testing.load_app("test/apps/textarea_app.lua")
        local h   = testing.render(App, { cols = 30, rows = 6 })

        -- Fill the Textarea with many lines to force scrolling.
        -- Textarea height=4, so only 4 rows visible at a time.
        for i = 1, 5 do
            h:type("L" .. i)
            h:press("shift+enter")
        end
        h:type("L6")

        -- Move cursor to line 3 (middle of viewport) so scrolling down
        -- keeps the cursor visible and clamp_scroll won't undo it.
        h:press("ctrl+home")  -- cursor at line 1
        h:press("down")       -- line 2
        h:press("down")       -- line 3

        -- Verify L1 is visible.
        local frame_before = h:frame()
        lt.assertNotEquals(frame_before:find("L1", 1, true), nil,
            "L1 should be visible before scroll_down")

        -- Find the scrollable Box.
        local box = find_scrollable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a scrollable Box")
        local r = box.rect

        -- Scroll down. Cursor is at line 3, scroll_top=0, visible rows 1-4.
        -- After scroll_down, scroll_top=1, visible rows 2-5. Cursor at line 3 is still visible.
        h:mouse("scroll_down", nil, r.x + 1, r.y + 1)

        -- After scrolling down, L1 should have moved out of view.
        local frame_after = h:frame()
        lt.assertEquals(frame_after:find("L1", 1, true), nil,
            "L1 should have scrolled out of view")
        h:unmount()
    end)
end
