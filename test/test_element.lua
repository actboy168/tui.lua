-- test/test_element.lua — smoke tests for tui.element factories.
local lt      = require "ltest"
local element = require "tui.element"

local test_element = lt.test "element"

function test_element:test_box_kind()
    local b = element.Box {}
    lt.assertEquals(b.kind, "box")
end

function test_element:test_text_kind()
    local t = element.Text { "hi" }
    lt.assertEquals(t.kind, "text")
    lt.assertEquals(t.text, "hi")
end

function test_element:test_box_splits_props_and_children()
    local child = element.Text { "x" }
    local b = element.Box {
        padding = 1,
        child,
    }
    lt.assertEquals(b.props.padding, 1)
    lt.assertEquals(#b.children, 1)
    lt.assertEquals(b.children[1], child)
end

function test_element:test_text_joins_string_children()
    local t = element.Text { "hello", " ", "world" }
    lt.assertEquals(t.text, "hello world")
end
