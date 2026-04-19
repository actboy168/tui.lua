-- test/text/test_textarea.lua — unit tests for <Textarea> component.
--
-- Drives the component offscreen via tui.testing: dispatch input bytes →
-- auto-render → inspect onChange callbacks and cursor position.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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

function suite:test_enter_inserts_newline()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 4,
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    h:type("a")
    h:press("enter")
    h:type("b")
    lt.assertEquals(value, "a\nb")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Backspace across line boundary merges lines.
-- ---------------------------------------------------------------------------

function suite:test_backspace_merges_lines()
    local value = "a\nb"
    local function App()
        return tui.Box {
            width = 20, height = 4,
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea {
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea {
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
    local input_mod = require "tui.input"
    input_mod._dispatch_event({ name = "enter", ctrl = true, meta = false, shift = false, input = "\r", raw = "\r" })
    h:_paint()
    lt.assertEquals(#submitted, 1)
    lt.assertEquals(submitted[1], "hello")
    lt.assertEquals(value, "hello")
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
            tui.Textarea { value = value, onChange = function(v) value = v end, height = 4 },
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
