-- test/test_text_input.lua — unit tests for <TextInput> component.
--
-- Drives the component offscreen: render → dispatch a key via tui.input →
-- render again → inspect the produced element and (for onSubmit) the
-- collected callback invocations.

local lt         = require "ltest"
local tui        = require "tui"
local reconciler = require "tui.reconciler"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local scheduler  = require "tui.scheduler"
local input_mod  = require "tui.input"
local resize_mod = require "tui.resize"

local suite = lt.test "text_input"

-- Configure the scheduler with a nop backend so useEffect-scheduled work
-- (which we don't use here) doesn't blow up.
scheduler.configure {
    now   = function() return 0 end,
    sleep = function() end,
}

local function find_text_with_cursor(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "text" and e._cursor_offset ~= nil then return e end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c); if r then return r end
        end
    end
    return walk(tree)
end

local function new_harness(W, H)
    local state = reconciler.new()
    local app   = { exit = function() end }
    input_mod._reset()
    resize_mod._reset()
    return {
        render = function(App)
            local tree = reconciler.render(state, App, app)
            if tree and tree.kind == "box" then
                tree.props.width  = tree.props.width  or W
                tree.props.height = tree.props.height or H
            end
            layout.compute(tree)
            local _rows = renderer.render_rows(tree, W, H)
            layout.free(tree)
            return tree
        end,
        teardown = function()
            reconciler.shutdown(state)
            input_mod._reset()
            resize_mod._reset()
        end,
    }
end

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
    local h = new_harness(20, 1)
    local tree = h.render(App)
    local te = find_text_with_cursor(tree)
    -- focus=false → no cursor tag.
    lt.assertEquals(te, nil)
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)
    input_mod.dispatch("h")
    h.render(App)   -- re-render so TextInput picks up new props.value
    input_mod.dispatch("i")
    lt.assertEquals(value, "hi")
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)
    -- Simulate IME-confirmed "中" then "文" as two UTF-8 bursts.
    input_mod.dispatch("\228\184\173")  -- "中"
    h.render(App)
    input_mod.dispatch("\230\150\135")  -- "文"
    lt.assertEquals(value, "\228\184\173\230\150\135")  -- "中文"
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)     -- initial caret = #value = 3
    input_mod.dispatch("\127")  -- DEL/backspace
    lt.assertEquals(value, "ab")
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)
    input_mod.dispatch("\27[D")  -- left arrow → caret moves from 2 to 1
    h.render(App)                -- re-render so caret state is committed
    input_mod.dispatch("b")      -- insert "b" at position 1 → "abc"
    lt.assertEquals(value, "abc")
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)
    input_mod.dispatch("\r")
    lt.assertEquals(submitted, "hello")
    h.teardown()
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
    local h = new_harness(20, 1)
    h.render(App)
    input_mod.dispatch("xyz")
    lt.assertEquals(value, "start")
    h.teardown()
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
    local h = new_harness(20, 1)
    local tree = h.render(App)
    local te = find_text_with_cursor(tree)
    lt.assertEquals(te ~= nil, true)
    lt.assertEquals(te._cursor_offset, 3)
    h.teardown()
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
    local h = new_harness(20, 1)
    local tree = h.render(App)
    local te = find_text_with_cursor(tree)
    lt.assertEquals(te.text, "****")
    lt.assertEquals(te._cursor_offset, 4)
    h.teardown()
end
