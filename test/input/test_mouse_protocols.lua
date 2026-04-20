local lt = require "ltest"
local mouse_helpers = require "tui.testing.mouse"

local suite = lt.test "mouse_protocols"

local function first(evs)
    return evs[1]
end

function suite:test_sgr_button_down_parses_to_mouse_event()
    local ev = first(mouse_helpers.parse_sgr {
        type = "down", button = 1, x = 10, y = 5,
    })
    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "down")
    lt.assertEquals(ev.button, 1)
    lt.assertEquals(ev.x, 10)
    lt.assertEquals(ev.y, 5)
end

function suite:test_sgr_scroll_with_modifier_parses()
    local ev = first(mouse_helpers.parse_sgr {
        type = "scroll", scroll = -1, x = 2, y = 3, shift = true,
    })
    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "scroll")
    lt.assertEquals(ev.scroll, -1)
    lt.assertTrue(ev.shift)
end

function suite:test_sgr_hover_move_keeps_nil_button()
    local ev = first(mouse_helpers.parse_sgr {
        type = "move", x = 4, y = 6,
    })
    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "move")
    lt.assertNil(ev.button)
    lt.assertEquals(ev.x, 4)
    lt.assertEquals(ev.y, 6)
end

function suite:test_x10_button_down_parses_to_mouse_event()
    local ev = first(mouse_helpers.parse_x10 {
        type = "down", button = 2, x = 7, y = 8,
    })
    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "down")
    lt.assertEquals(ev.button, 2)
    lt.assertEquals(ev.x, 7)
    lt.assertEquals(ev.y, 8)
end

function suite:test_x10_release_drops_button_identity()
    local ev = first(mouse_helpers.parse_x10 {
        type = "up", x = 1, y = 1,
    })
    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "up")
    lt.assertNil(ev.button)
end

return suite
