-- test/integration/test_log_bar.lua — implicit bottom log bar integration tests.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"

local suite = lt.test "log_bar"

local function LinesApp(lines)
    return function()
        local box = {
            width = 12,
            height = #lines,
            flexDirection = "column",
        }
        for i, line in ipairs(lines) do
            box[#box + 1] = tui.Text {
                key = "line:" .. tostring(i),
                line,
            }
        end
        return tui.Box(box)
    end
end

function suite:test_log_bar_hidden_by_default()
    local h = testing.render(LinesApp { "A", "B" }, {
        cols = 12,
        rows = 4,
    })
    lt.assertEquals(h:row(1):sub(1, 1), "A")
    lt.assertEquals(h:row(2):sub(1, 1), "B")
    lt.assertEquals(h:row(3), "            ")
    h:unmount()
end

function suite:test_log_bar_appears_after_content()
    local h = testing.render(LinesApp { "A", "B" }, {
        cols = 12,
        rows = 4,
    })
    tui.log("hello")
    h:rerender()
    lt.assertEquals(h:row(1):sub(1, 1), "A")
    lt.assertEquals(h:row(2):sub(1, 1), "B")
    lt.assertEquals(h:row(3):sub(1, 10), " LOG hello")
    lt.assertEquals(h:row(4), "            ")
    h:unmount()
end

function suite:test_log_bar_uses_badge_style()
    local h = testing.render(LinesApp { "A", "B" }, {
        cols = 12,
        rows = 4,
    })
    tui.log("hello")
    h:rerender()

    local cells = h:cells(3)
    for i = 1, 5 do
        lt.assertEquals(cells[i].bg, 3)
        lt.assertEquals(cells[i].fg, 0)
        lt.assertEquals(cells[i].bold, true)
    end
    lt.assertEquals(cells[6].bg, 8)
    lt.assertEquals(cells[6].fg, 7)

    h:unmount()
end

function suite:test_log_bar_shows_only_latest()
    local h = testing.render(LinesApp { "A", "B" }, {
        cols = 12,
        rows = 4,
    })
    tui.log("first")
    h:rerender()
    tui.log("second")
    h:rerender()
    lt.assertEquals(h:row(3):sub(1, 11), " LOG second")
    h:unmount()
end

function suite:test_log_bar_stays_below_full_content()
    local h = testing.render(LinesApp { "A", "B", "C", "D" }, {
        cols = 12,
        rows = 4,
    })
    tui.log("LOG")
    h:rerender()
    lt.assertEquals(h:row(1):sub(1, 1), "A")
    lt.assertEquals(h:row(2):sub(1, 1), "B")
    lt.assertEquals(h:row(3):sub(1, 1), "C")
    lt.assertEquals(h:row(4):sub(1, 1), "D")
    h:unmount()
end

function suite:test_log_bar_resets_between_mounts()
    local h1 = testing.render(LinesApp { "body" }, {
        cols = 12,
        rows = 3,
    })
    tui.log("persist")
    h1:rerender()
    lt.assertEquals(h1:row(2):sub(1, #" LOG persist"), " LOG persist")
    h1:unmount()

    local h2 = testing.render(LinesApp { "body" }, {
        cols = 12,
        rows = 3,
    })
    lt.assertEquals(h2:row(2), "            ")
    h2:unmount()
end

function suite:test_log_bar_truncates_long_message()
    local h = testing.render(LinesApp { "body" }, {
        cols = 8,
        rows = 3,
    })
    tui.log("hello world")
    h:rerender()
    lt.assertEquals(h:row(2):sub(1, #" LOG he…"), " LOG he…")
    h:unmount()
end

function suite:test_tui_log_works_without_component_state()
    local function App()
        tui.useTimeout(function()
            tui.log("tick")
        end, 10)

        return tui.Box {
            width = 12,
            height = 1,
            flexDirection = "column",
            tui.Text {
                key = "body",
                "body",
            },
        }
    end

    local h = testing.render(App, {
        cols = 12,
        rows = 3,
    })
    lt.assertEquals(h:row(2), "            ")
    h:advance(10)
    lt.assertEquals(h:row(2):sub(1, 9), " LOG tick")
    lt.assertEquals(h:row(3), "            ")
    h:unmount()
end
