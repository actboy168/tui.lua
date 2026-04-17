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
                focus = true,
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
                focus = true,
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
                focus = true,
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
                focus = true,
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
                focus = true,
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
                focus = true,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local te = testing.find_text_with_cursor(h:tree())
    lt.assertEquals(te ~= nil, true)
    lt.assertEquals(te._cursor_offset, 3)
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
                focus = true,
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
