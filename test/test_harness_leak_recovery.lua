-- test/test_harness_leak_recovery.lua — when a previous testing.render
-- harness is never unmounted (because an assertion failed between
-- render() and unmount()), the next render() used to hard-fail with
-- "another harness is already active". That cascade hid the real first
-- failure. Recovery logic now auto-restores the leaked hijack.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "harness_leak_recovery"

function suite:test_leaked_harness_is_auto_recovered()
    local function App()
        return tui.Text { "first" }
    end
    local function App2()
        return tui.Text { "second" }
    end

    -- The recovery path writes a "[tui:test]" warning to the real stderr.
    -- Route that into capture_stderr so the test suite's output stays
    -- quiet and we can assert the warning content.
    local captured
    local h2
    captured = testing.capture_stderr(function()
        -- Deliberately leak: no :unmount() on the first harness.
        testing.render(App, { cols = 20, rows = 3 })
        -- Second render triggers the auto-recover path.
        h2 = testing.render(App2, { cols = 20, rows = 3 })
    end)

    lt.assertEquals(h2:row(1):find("second", 1, true) ~= nil, true,
                    "second harness should render fresh content")
    lt.assertEquals(captured:find("previous harness leaked", 1, true) ~= nil, true,
                    "recovery path should have emitted a warning, got: " ..
                    tostring(captured))
    h2:unmount()
end
