local lt       = require "ltest"
local hit_test = require "tui.internal.hit_test"

local suite = lt.test "hit_test"

function suite:teardown()
    hit_test._reset()
end

-- ---------------------------------------------------------------------------
-- Basic hit testing (row_offset = 0)
-- ---------------------------------------------------------------------------

function suite:test_hit_root()
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 24 },
        children = {},
    })
    local path = hit_test.hit_test(1, 1)
    lt.assertNotEquals(path, nil)
    lt.assertEquals(#path, 1)
end

function suite:test_hit_nested_text()
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 1 },
        children = {
            { kind = "text", props = {}, rect = { x = 0, y = 0, w = 5, h = 1 },
              children = { "Hello" }, text = "Hello" },
        },
    })
    local path = hit_test.hit_test(1, 1)
    lt.assertNotEquals(path, nil)
    lt.assertEquals(#path, 2)
    lt.assertEquals(path[1].kind, "box")
    lt.assertEquals(path[2].kind, "text")
end

function suite:test_click_bubbles_from_text_to_box()
    local clicked = false
    hit_test.set_tree({
        kind = "box", props = { onMouseDown = function() clicked = true end },
        rect = { x = 0, y = 0, w = 80, h = 1 },
        children = {
            { kind = "text", props = {}, rect = { x = 0, y = 0, w = 5, h = 1 },
              children = { "Hi" }, text = "Hi" },
        },
    })
    lt.assertTrue(hit_test.dispatch_mouse_down(1, 1))
    lt.assertTrue(clicked)
end

function suite:test_click_on_clickable_box()
    local info
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 24 },
        children = {
            { kind = "box", props = {},
              rect = { x = 0, y = 0, w = 80, h = 20 }, children = {} },
            { kind = "box", props = { onMouseDown = function(ev) info = ev end },
              rect = { x = 0, y = 20, w = 80, h = 1 }, children = {} },
        },
    })
    lt.assertTrue(hit_test.dispatch_mouse_down(1, 21))
    lt.assertNotEquals(info, nil)
    lt.assertEquals(info.localCol, 0)
    lt.assertEquals(info.localRow, 0)
end

function suite:test_later_sibling_overlays_earlier()
    local hit_key
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 24 },
        children = {
            { kind = "box", key = "A",
              props = { onMouseDown = function() hit_key = "A" end },
              rect = { x = 0, y = 0, w = 80, h = 10 }, children = {} },
            { kind = "box", key = "B",
              props = { onMouseDown = function() hit_key = "B" end },
              rect = { x = 0, y = 5, w = 80, h = 10 }, children = {} },
        },
    })
    lt.assertTrue(hit_test.dispatch_mouse_down(1, 7))
    lt.assertEquals(hit_key, "B")
end

function suite:test_outside_tree_returns_nil()
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 24 },
        children = {},
    })
    lt.assertEquals(hit_test.hit_test(81, 1), nil)
    lt.assertEquals(hit_test.hit_test(1, 25), nil)
end

function suite:test_no_tree_returns_nil()
    hit_test._reset()
    lt.assertEquals(hit_test.hit_test(1, 1), nil)
end

-- ---------------------------------------------------------------------------
-- Row offset (content not at terminal top)
-- ---------------------------------------------------------------------------

function suite:test_row_offset_maps_terminal_to_content_coords()
    -- Simulate: terminal is 24 rows, content is 10 rows starting at
    -- terminal row 15 (0-based row 14).  row_offset = 14.
    hit_test.set_row_offset(14)
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 10 },
        children = {},
    })
    -- SGR row=15 (1-based) → 0-based terminal row 14 → content row 0
    local path = hit_test.hit_test(1, 15)
    lt.assertNotEquals(path, nil)
    -- SGR row=24 → 0-based 23 → content row 9 (last content row)
    lt.assertNotEquals(hit_test.hit_test(1, 24), nil)
    -- SGR row=14 → 0-based 13 → content row -1 (above content)
    lt.assertEquals(hit_test.hit_test(1, 14), nil)
end

function suite:test_row_offset_click_localRow_is_content_relative()
    local info
    hit_test.set_row_offset(5)
    hit_test.set_tree({
        kind = "box", props = { onMouseDown = function(ev) info = ev end },
        rect = { x = 0, y = 0, w = 80, h = 10 },
        children = {},
    })
    -- SGR (1, 8) → content (0, 2)
    lt.assertTrue(hit_test.dispatch_mouse_down(1, 8))
    lt.assertNotEquals(info, nil)
    lt.assertEquals(info.localRow, 2)
end

function suite:test_row_offset_zero_means_content_at_top()
    hit_test.set_row_offset(0)
    hit_test.set_tree({
        kind = "box", props = {},
        rect = { x = 0, y = 0, w = 80, h = 10 },
        children = {},
    })
    lt.assertNotEquals(hit_test.hit_test(1, 1), nil)
    lt.assertEquals(hit_test.hit_test(1, 11), nil)
end

-- ---------------------------------------------------------------------------
-- Scroll dispatch
-- ---------------------------------------------------------------------------

function suite:test_scroll_dispatch_with_offset()
    local info
    hit_test.set_row_offset(3)
    hit_test.set_tree({
        kind = "box", props = {
            onScroll = function(ev) info = ev end,
        },
        rect = { x = 0, y = 0, w = 80, h = 10 },
        children = {},
    })
    lt.assertTrue(hit_test.dispatch_scroll(1, 4, 1))
    lt.assertNotEquals(info, nil)
    lt.assertEquals(info.direction, 1)
    lt.assertEquals(info.localRow, 0)
end
