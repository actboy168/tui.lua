-- test/integration/test_counter.lua — counter app integration tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"

local suite = lt.test "counter"

local function Counter()
    local count, setCount = tui.useState(0)

    tui.useInput(function(_, key)
        if key.name == "up" then
            setCount(count + 1)
        elseif key.name == "down" then
            setCount(count - 1)
        end
    end)

    return tui.Box {
        flexDirection = "column",
        width = 20, height = 5,
        tui.Text { key = "title", bold = true, "Counter" },
        tui.Text { key = "value", ("%d"):format(count) },
        tui.Text { key = "hint", dim = true, "up/down" },
    }
end

-- ============================================================================
-- Basic increment / decrement
-- ============================================================================

function suite:test_increment()
    local h = testing.render(Counter, { cols = 25, rows = 7 })

    lt.assertEquals(h:row(2), "0                        ")

    h:press("up")
    lt.assertEquals(h:row(2), "1                        ")

    h:press("up")
    h:press("up")
    lt.assertEquals(h:row(2), "3                        ")

    h:press("down")
    lt.assertEquals(h:row(2), "2                        ")

    h:unmount()
end

function suite:test_decrement_below_zero()
    local h = testing.render(Counter, { cols = 25, rows = 7 })

    h:press("down")
    h:press("down")
    lt.assertEquals(h:row(2), "-2                       ")

    h:unmount()
end

-- ============================================================================
-- Render efficiency
-- ============================================================================

function suite:test_render_count_per_keypress()
    local h = testing.render(Counter, { cols = 25, rows = 7 })
    h:reset_render_count()

    h:press("up")
    h:expect_renders(1, "one keypress → one render")

    h:press("up")
    h:press("down")
    h:expect_renders(3, "three keypresses → three renders")

    h:unmount()
end

-- ============================================================================
-- Snapshot
-- ============================================================================

function suite:test_snapshot_initial()
    local h = testing.render(Counter, { cols = 25, rows = 7 })
    h:match_snapshot("counter_initial_25x7")
    h:unmount()
end

function suite:test_snapshot_after_increments()
    local h = testing.render(Counter, { cols = 25, rows = 7 })
    h:press("up")
    h:press("up")
    h:press("up")
    h:match_snapshot("counter_at_3_25x7")
    h:unmount()
end
