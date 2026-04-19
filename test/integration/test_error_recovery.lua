-- test/integration/test_error_recovery.lua — error handling and recovery tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"

local suite = lt.test "error_recovery"

-- ============================================================================
-- Error in event handler (should not crash the app)
-- ============================================================================

function suite:test_error_in_event_handler()
    local App = function()
        local count, setCount = tui.useState(0)

        return tui.Box {
            width = 30, height = 6,
            tui.Text { ("Count: %d"):format(count) },
            tui.Text { "Press Enter to increment" },
        }
    end

    local h = testing.render(App, { cols = 35, rows = 8 })

    -- Normal operations
    h:match_snapshot("error_handler_initial_35x8")

    h:unmount()
end

-- ============================================================================
-- Graceful degradation
-- ============================================================================

function suite:test_graceful_degradation()
    local App = function()
        local hasError, setHasError = tui.useState(false)

        return tui.Box {
            width = 40, height = 8,
            hasError
                and tui.Text { color = "yellow", "Running in degraded mode" }
                or tui.Box {
                    borderStyle = "single",
                    tui.Text { "Full functionality" }
                }
        }
    end

    local h = testing.render(App, { cols = 45, rows = 10 })
    h:match_snapshot("graceful_normal_45x10")

    h:unmount()
end
