-- test/test_static.lua — unit tests for <Static> component.

local lt         = require "ltest"
local tui        = require "tui"
local reconciler = require "tui.reconciler"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local screen_mod = require "tui.screen"

local suite = lt.test "static"

-- Minimal shared harness: render App returning a Box containing a Static.
local function new_harness(W, H)
    local state = reconciler.new()
    local scr   = screen_mod.new()
    local app   = { exit = function() end }
    return {
        render_once = function(App)
            local tree = reconciler.render(state, App, app)
            if tree and tree.kind == "box" then
                tree.props.width  = tree.props.width  or W
                tree.props.height = tree.props.height or H
            end
            layout.compute(tree)
            local rows = renderer.render_rows(tree, W, H)
            local ansi = screen_mod.diff(scr, rows, W, H)
            layout.free(tree)
            return rows, ansi
        end,
        teardown = function()
            reconciler.shutdown(state)
        end,
    }
end

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
    local h = new_harness(20, 5)
    local rows = h.render_once(App)
    lt.assertEquals(rows[1]:sub(1, 5), "hello")
    lt.assertEquals(rows[2]:sub(1, 5), "world")
    h.teardown()
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
    local h = new_harness(20, 5)
    h.render_once(App)
    -- Append one item; next diff should only write the changed row.
    items[#items + 1] = "second"
    local _, ansi = h.render_once(App)
    -- A single-row diff is substantially shorter than a full redraw of 5 rows.
    lt.assertEquals(#ansi > 0, true, "expected some ANSI for new row")
    lt.assertEquals(#ansi < 150, true, "expected a small diff, got " .. #ansi .. " bytes")
    -- The new row's content should appear.
    lt.assertEquals(ansi:find("second", 1, true) ~= nil, true)
    h.teardown()
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
    local h = new_harness(20, 5)
    h.render_once(App)
    local _, ansi = h.render_once(App)
    lt.assertEquals(#ansi, 0, "second identical render should emit no ANSI")
    h.teardown()
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
    local h = new_harness(20, 5)
    h.render_once(App)
    h.render_once(App)
    lt.assertEquals(render_calls, 2, "render() should be memoized per item")
    h.teardown()
end
