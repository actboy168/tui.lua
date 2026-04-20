-- test/test_element.lua — smoke tests for tui.element factories.
local lt  = require "ltest"
local tui = require "tui"

local test_element = lt.test "element"

function test_element:test_box_kind()
    local b = tui.Box {}
    lt.assertEquals(b.kind, "box")
end

function test_element:test_text_kind()
    local t = tui.Text { "hi" }
    lt.assertEquals(t.kind, "text")
    lt.assertEquals(t.text, "hi")
end

function test_element:test_box_splits_props_and_children()
    local child = tui.Text { "x" }
    local b = tui.Box {
        padding = 1,
        child,
    }
    lt.assertEquals(b.props.padding, 1)
    lt.assertEquals(#b.children, 1)
    lt.assertEquals(b.children[1], child)
end

function test_element:test_text_joins_string_children()
    local t = tui.Text { "hello", " ", "world" }
    lt.assertEquals(t.text, "hello world")
end
