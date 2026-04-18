-- test/test_bare_mode.lua — tests for Bare mode features.
-- Bare mode provides reconciler + hooks without layout/renderer/screen.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "bare_mode"

-- ============================================================================
-- Basic Bare functionality
-- ============================================================================

function suite:test_bare_rerender_and_tree()
    local function App()
        return tui.Text { "hello" }
    end
    local b = testing.mount_bare(App)
    b:expect_renders(1)
    lt.assertEquals(b:tree().kind, "text")
    lt.assertEquals(b:tree().text, "hello")

    b:rerender()
    b:expect_renders(2)
    b:unmount()
end

function suite:test_bare_dispatch_input()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "test" }
    end
    local b = testing.mount_bare(App)
    b:dispatch("a")
    lt.assertEquals(events[1].name, "char")
    lt.assertEquals(events[1].input, "a")

    b:dispatch("\27[A")  -- up arrow
    lt.assertEquals(events[2].name, "up")
    b:unmount()
end

-- ============================================================================
-- Bare :type() method
-- ============================================================================

function suite:test_bare_type_ascii()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:type("hi")
    lt.assertEquals(#events, 2)
    lt.assertEquals(events[1].name, "char")
    lt.assertEquals(events[1].input, "h")
    lt.assertEquals(events[2].name, "char")
    lt.assertEquals(events[2].input, "i")
    b:unmount()
end

function suite:test_bare_type_cjk()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    -- "中" is 3 bytes in UTF-8
    b:type("\228\184\173")
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].name, "char")
    lt.assertEquals(events[1].input, "\228\184\173")
    b:unmount()
end

-- ============================================================================
-- Bare :press() method
-- ============================================================================

function suite:test_bare_press_named_keys()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("enter")
    -- Note: "tab" is intercepted by focus system, use "up" instead
    b:press("up")
    b:press("down")
    b:press("ctrl+c")
    lt.assertEquals(events[1].name, "enter")
    lt.assertEquals(events[2].name, "up")
    lt.assertEquals(events[3].name, "down")
    -- ctrl+c is parsed as name="char", ctrl=true, input="c"
    lt.assertEquals(events[4].name, "char")
    lt.assertEquals(events[4].ctrl, true)
    lt.assertEquals(events[4].input, "c")
    b:unmount()
end

function suite:test_bare_press_error_on_invalid()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    local ok, err = pcall(function() b:press("invalid_key") end)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("unknown key", 1, true) ~= nil, true)
    b:unmount()
end

-- ============================================================================
-- Bare :advance() method (virtual clock for timers)
-- ============================================================================

function suite:test_bare_advance_triggers_interval()
    local ticks = 0
    local function App()
        tui.useInterval(function()
            ticks = ticks + 1
        end, 100)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(ticks, 0)

    b:advance(50)   -- not enough
    lt.assertEquals(ticks, 0)

    b:advance(100)  -- 150 total, should fire once
    lt.assertEquals(ticks, 1)

    b:advance(200)  -- 350 total, should fire twice more
    lt.assertEquals(ticks, 3)
    b:unmount()
end

function suite:test_bare_advance_triggers_timeout()
    local fired = false
    local function App()
        tui.useEffect(function()
            local id = tui.setTimeout(function()
                fired = true
            end, 100)
            return function() tui.clearTimeout(id) end
        end, {})
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(fired, false)

    b:advance(99)
    lt.assertEquals(fired, false)

    b:advance(2)  -- 101 total
    lt.assertEquals(fired, true)
    b:unmount()
end

function suite:test_bare_advance_error_on_negative()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    local ok, err = pcall(function() b:advance(-1) end)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("non-negative", 1, true) ~= nil, true)
    b:unmount()
end

-- ============================================================================
-- Bare focus helpers
-- ============================================================================

function suite:test_bare_focus_id()
    local function App()
        tui.useFocus { id = "test", autoFocus = true }
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(b:focus_id(), "test")
    b:unmount()
end

function suite:test_bare_focus_next_prev()
    local function A() tui.useFocus { id = "a" }; return tui.Text { "a" } end
    local function B() tui.useFocus { id = "b", autoFocus = true }; return tui.Text { "b" } end
    local function C() tui.useFocus { id = "c" }; return tui.Text { "c" } end
    local function App()
        return tui.Box {
            { kind = "component", fn = A, props = {}, key = "a" },
            { kind = "component", fn = B, props = {}, key = "b" },
            { kind = "component", fn = C, props = {}, key = "c" },
        }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(b:focus_id(), "b")  -- b has autoFocus

    b:focus_next()
    lt.assertEquals(b:focus_id(), "c")

    b:focus_next()
    lt.assertEquals(b:focus_id(), "a")  -- wrap

    b:focus_prev()
    lt.assertEquals(b:focus_id(), "c")  -- wrap back
    b:unmount()
end

function suite:test_bare_focus_explicit()
    local function A() tui.useFocus { id = "a", autoFocus = true }; return tui.Text { "a" } end
    local function B() tui.useFocus { id = "b" }; return tui.Text { "b" } end
    local function App()
        return tui.Box {
            { kind = "component", fn = A, props = {}, key = "a" },
            { kind = "component", fn = B, props = {}, key = "b" },
        }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(b:focus_id(), "a")

    b:focus("b")
    lt.assertEquals(b:focus_id(), "b")
    b:unmount()
end

-- ============================================================================
-- Bare does NOT auto-rerender (unlike Harness)
-- ============================================================================

function suite:test_bare_does_not_auto_rerender_on_input()
    local function App()
        tui.useInput(function() end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:expect_renders(1)

    b:type("x")
    b:expect_renders(1, "type should not auto-rerender")

    b:rerender()
    b:expect_renders(2)
    b:unmount()
end

function suite:test_bare_does_not_auto_rerender_on_advance()
    local function App()
        tui.useEffect(function() end, {})
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:expect_renders(1)

    b:advance(1000)
    b:expect_renders(1, "advance should not auto-rerender")

    b:rerender()
    b:expect_renders(2)
    b:unmount()
end

-- ============================================================================
-- Combined operations
-- ============================================================================

function suite:test_bare_input_then_advance_combined()
    local inputs = {}
    local timeout_fired = false
    local function App()
        tui.useInput(function(data)
            if data then inputs[#inputs + 1] = data end
        end)
        tui.useEffect(function()
            local id = tui.setTimeout(function()
                timeout_fired = true
            end, 500)
            return function() tui.clearTimeout(id) end
        end, {})
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)

    b:type("abc")
    lt.assertEquals(inputs, { "a", "b", "c" })
    lt.assertEquals(timeout_fired, false)

    b:advance(500)
    lt.assertEquals(timeout_fired, true)
    b:unmount()
end

function suite:test_bare_focus_with_input()
    local focus_changes = {}
    local function App()
        local f = tui.useFocus { id = "main", autoFocus = true }
        tui.useEffect(function()
            focus_changes[#focus_changes + 1] = f.isFocused
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:rerender()  -- run effect after initial render
    lt.assertEquals(b:focus_id(), "main")
    lt.assertEquals(focus_changes[#focus_changes], true)
    b:unmount()
end

-- ============================================================================
-- Shift modifier support
-- ============================================================================

function suite:test_bare_shift_arrow_keys()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("shift+up")
    b:press("shift+down")
    b:press("shift+left")
    b:press("shift+right")
    lt.assertEquals(events[1].name, "up")
    lt.assertEquals(events[1].shift, true)
    lt.assertEquals(events[2].name, "down")
    lt.assertEquals(events[2].shift, true)
    lt.assertEquals(events[3].name, "left")
    lt.assertEquals(events[3].shift, true)
    lt.assertEquals(events[4].name, "right")
    lt.assertEquals(events[4].shift, true)
    b:unmount()
end

function suite:test_bare_shift_home_end()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("shift+home")
    b:press("shift+end")
    lt.assertEquals(events[1].name, "home")
    lt.assertEquals(events[1].shift, true)
    lt.assertEquals(events[2].name, "end")
    lt.assertEquals(events[2].shift, true)
    b:unmount()
end

-- ============================================================================
-- Single char press() falls back to type()
-- ============================================================================

function suite:test_bare_press_single_char_uses_type()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("a")
    b:press("Z")
    b:press("1")
    b:press(" ")
    lt.assertEquals(#events, 4)
    lt.assertEquals(events[1].name, "char")
    lt.assertEquals(events[1].input, "a")
    lt.assertEquals(events[2].name, "char")
    lt.assertEquals(events[2].input, "Z")
    lt.assertEquals(events[3].name, "char")
    lt.assertEquals(events[3].input, "1")
    lt.assertEquals(events[4].name, "char")
    lt.assertEquals(events[4].input, " ")
    b:unmount()
end

function suite:test_bare_press_cjk_falls_back_to_type()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    -- Single CJK character passed to press() should work via type() fallback
    b:press("\228\184\173")  -- "中"
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].name, "char")
    lt.assertEquals(events[1].input, "\228\184\173")
    b:unmount()
end

-- ============================================================================
-- Extended key support (F5-F12, insert)
-- ============================================================================

function suite:test_bare_f5_to_f12_keys()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("f5")
    b:press("f6")
    b:press("f7")
    b:press("f8")
    b:press("f9")
    b:press("f10")
    b:press("f11")
    b:press("f12")
    lt.assertEquals(#events, 8)
    lt.assertEquals(events[1].name, "f5")
    lt.assertEquals(events[5].name, "f9")
    lt.assertEquals(events[8].name, "f12")
    b:unmount()
end

function suite:test_bare_insert_key()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            if key then events[#events + 1] = key end
        end)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:press("insert")
    lt.assertEquals(#events, 1)
    lt.assertEquals(events[1].name, "insert")
    b:unmount()
end

-- ============================================================================
-- Tree query utilities
-- ============================================================================

function suite:test_find_by_kind()
    local function App()
        return tui.Box {
            tui.Text { "hello" },
            tui.Box {
                tui.Text { "world" },
            },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 5 })
    local tree = h:tree()

    -- find_by_kind returns the first match in DFS order
    local first_text = testing.find_by_kind(tree, "text")
    lt.assertEquals(first_text ~= nil, true)
    lt.assertEquals(first_text.text, "hello")

    local first_box = testing.find_by_kind(tree, "box")
    lt.assertEquals(first_box ~= nil, true)
    lt.assertEquals(first_box.kind, "box")

    -- Non-existent kind returns nil
    lt.assertEquals(testing.find_by_kind(tree, "component"), nil)
    h:unmount()
end

function suite:test_find_all_by_kind()
    local function App()
        return tui.Box {
            tui.Text { "a" },
            tui.Box {
                tui.Text { "b" },
                tui.Text { "c" },
            },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 5 })
    local tree = h:tree()

    local texts = testing.find_all_by_kind(tree, "text")
    lt.assertEquals(#texts, 3)
    lt.assertEquals(texts[1].text, "a")
    lt.assertEquals(texts[2].text, "b")
    lt.assertEquals(texts[3].text, "c")

    local boxes = testing.find_all_by_kind(tree, "box")
    lt.assertEquals(#boxes, 2)
    h:unmount()
end

function suite:test_text_content()
    local function App()
        return tui.Box {
            tui.Text { "hello" },
            tui.Box {
                tui.Text { " " },
                tui.Text { "world" },
            },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 5 })
    local contents = testing.text_content(h:tree())
    lt.assertEquals(contents, { "hello", " ", "world" })
    h:unmount()
end

function suite:test_text_content_empty_tree()
    lt.assertEquals(testing.text_content(nil), {})
end

-- ============================================================================
-- Render count tracking (performance testing)
-- ============================================================================

function suite:test_bare_render_count_initial()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    -- mount_bare does 1 initial render
    lt.assertEquals(b:render_count(), 1)
    b:unmount()
end

function suite:test_bare_render_count_tracks_rerenders()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(b:render_count(), 1)

    b:rerender()
    lt.assertEquals(b:render_count(), 2)

    b:rerender():rerender()
    lt.assertEquals(b:render_count(), 4)
    b:unmount()
end

function suite:test_bare_reset_render_count()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    b:rerender():rerender()
    lt.assertEquals(b:render_count(), 3)

    b:reset_render_count()
    lt.assertEquals(b:render_count(), 0)

    b:rerender()
    lt.assertEquals(b:render_count(), 1)
    b:unmount()
end

function suite:test_bare_expect_renders_pass()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    -- Should not error when count matches
    b:expect_renders(1)
    b:rerender()
    b:expect_renders(2)
    b:unmount()
end

function suite:test_bare_expect_renders_fail()
    local function App()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    local ok, err = pcall(function()
        b:expect_renders(5)  -- actually 1
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("render count mismatch", 1, true) ~= nil, true)
    lt.assertEquals(err:find("expected 5, got 1", 1, true) ~= nil, true)
    b:unmount()
end

-- ============================================================================
-- Detecting unnecessary renders (bail-out verification)
-- ============================================================================

function suite:test_bare_same_state_no_rerender()
    -- Verify setState bail-out: when setting same value, reconciler
    -- should not mark instance dirty. We check this via state inspection.
    local set_value
    local function App()
        local v, setV = tui.useState(0)
        set_value = setV
        return tui.Text { tostring(v) }
    end
    local b = testing.mount_bare(App)
    local state = b:state()

    -- Setting same value should not mark dirty
    set_value(0)
    for _, inst in pairs(state.instances) do
        lt.assertEquals(inst.dirty, false, "same value setState should not mark dirty")
    end
    b:unmount()
end

function suite:test_bare_different_state_triggers_rerender()
    local renders = 0
    local set_value
    local function App()
        renders = renders + 1
        local v, setV = tui.useState(0)
        set_value = setV
        return tui.Text { tostring(v) }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(b:render_count(), 1)

    -- Setting different value triggers rerender
    set_value(1)
    b:rerender()

    lt.assertEquals(b:render_count(), 2)
    lt.assertEquals(renders, 2)  -- component re-executed
    b:unmount()
end
