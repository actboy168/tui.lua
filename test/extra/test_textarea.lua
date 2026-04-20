-- test/extra/test_textarea.lua — unit tests for <Textarea> component.
--
-- Drives the component offscreen via tui.testing: dispatch input bytes →
-- auto-render → inspect onChange callbacks and cursor position.

local lt       = require "ltest"
local tui      = require "tui"
local Textarea = require "tui.extra.textarea".Textarea
local testing  = require "tui.testing"

local suite = lt.test "textarea"

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
    h:dispatch("\x1b[13;2u")  -- Shift+Enter → insert newline
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
    h:dispatch("\x1b[13;2u")  -- Shift+Enter → insert newline
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
        h:dispatch("\x1b[13;2u")  -- Shift+Enter
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
        h:dispatch("\x1b[13;2u")  -- Shift+Enter
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
    h:dispatch("\x1b[200~hello world\x1b[201~")
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
    h:dispatch("\x1b[200~line1\nline2\nline3\x1b[201~")
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
    h:dispatch("\x1b[200~b\x1b[201~")
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
    h:dispatch("\x1b[200~mid1\nmid2\n\x1b[201~")
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
    -- The testing harness cannot inject ctrl+enter via :press, so we use the
    -- lower-level _dispatch_event API that bypasses key parsing.
    local input_mod = require "tui.internal.input"
    input_mod._dispatch_event({ name = "enter", ctrl = true, meta = false, shift = false, input = "\r", raw = "\r" })
    h:_paint()
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
    h:dispatch("\x1b[13;2u")
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
    h:dispatch("\x1b[13;5u")
    h:_paint()
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "world")
    lt.assertEquals(value, "world")
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
    h:dispatch("\x1b")         -- ESC alone (should be buffered, not "escape")
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
    h:dispatch("\x1b")
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
    h:dispatch("\x1b")
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
