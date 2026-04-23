local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_cursor"

local CursorBox = tui.component(function(props)
    local cursor = tui.useCursor()
    if props.position ~= nil then
        cursor.setCursorPosition(props.position)
    end
    return tui.Box {
        width = props.width or 6,
        height = props.height or 2,
        tui.Text { "hello" },
        tui.Text { "world" },
    }
end)

function suite:test_cursor_is_relative_to_component_root()
    local function App()
        return tui.Box {
            width = 20,
            height = 6,
            paddingX = 2,
            paddingY = 1,
            CursorBox {
                position = { x = 3, y = 1 },
            },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 6 })
    local col, row = h:cursor()
    lt.assertEquals(col, 6)
    lt.assertEquals(row, 3)
    h:unmount()
end

function suite:test_cursor_disappears_when_component_stops_declaring_it()
    local set_active

    local function App()
        local active, setActive = tui.useState(true)
        set_active = setActive
        return CursorBox {
            position = active and { x = 2, y = 0 } or nil,
            height = 1,
        }
    end

    local h = testing.render(App, { cols = 10, rows = 2 })
    local col, row = h:cursor()
    lt.assertEquals(col, 3)
    lt.assertEquals(row, 1)

    set_active(false)
    h:rerender()
    col, row = h:cursor()
    lt.assertEquals(col, nil)
    lt.assertEquals(row, nil)
    h:unmount()
end

function suite:test_nil_position_hides_cursor()
    local set_position

    local function App()
        local position, setPosition = tui.useState({ x = 1, y = 0 })
        set_position = setPosition
        local cursor = tui.useCursor()
        cursor.setCursorPosition(position)
        return tui.Box {
            width = 5,
            height = 1,
            tui.Text { "abc" },
        }
    end

    local h = testing.render(App, { cols = 10, rows = 2 })
    local col, row = h:cursor()
    lt.assertEquals(col, 2)
    lt.assertEquals(row, 1)

    set_position(nil)
    h:rerender()
    col, row = h:cursor()
    lt.assertEquals(col, nil)
    lt.assertEquals(row, nil)
    h:unmount()
end
