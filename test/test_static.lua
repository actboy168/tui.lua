-- test/test_static.lua — unit tests for <Static> component.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "static"

function suite:test_static_initial_items_render()
    local items = { "hello", "world" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            tui.Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    lt.assertEquals(h:row(1):sub(1, 5), "hello")
    lt.assertEquals(h:row(2):sub(1, 5), "world")
    h:unmount()
end

function suite:test_static_appending_items_produces_incremental_diff()
    local items = { "first" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            tui.Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    -- Drain the initial-frame ANSI so we only measure the incremental diff.
    h:clear_ansi()
    items[#items + 1] = "second"
    h:rerender()
    local ansi = h:ansi()
    lt.assertEquals(#ansi > 0, true, "expected some ANSI for new row")
    lt.assertEquals(#ansi < 150, true, "expected a small diff, got " .. #ansi .. " bytes")
    lt.assertEquals(ansi:find("second", 1, true) ~= nil, true)
    h:unmount()
end

function suite:test_static_no_change_produces_zero_diff()
    local items = { "a", "b" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            tui.Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:clear_ansi()
    h:rerender()
    lt.assertEquals(#h:ansi(), 0, "second identical render should emit no ANSI")
    h:unmount()
end

function suite:test_static_preserves_item_identity_when_cached()
    -- Each render() call increments a counter. After two paints with the same
    -- items array, render() should have been called exactly len(items) times.
    local items = { "x", "y" }
    local render_calls = 0
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            tui.Static {
                items = items,
                render = function(s)
                    render_calls = render_calls + 1
                    return tui.Text { s }
                end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:rerender()
    lt.assertEquals(render_calls, 2, "render() should be memoized per item")
    h:unmount()
end
