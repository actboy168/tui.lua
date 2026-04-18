-- test/test_harness_leak_recovery.lua — with per-instance fake terminals
-- (no global hijack), multiple harnesses can coexist in the same process
-- without interference. This test verifies that leaking a harness (not
-- unmounting it) does not corrupt subsequent renders.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "harness_leak_recovery"

function suite:test_leaked_harness_does_not_corrupt_next_render()
    local function App()
        return tui.Text { "first" }
    end
    local function App2()
        return tui.Text { "second" }
    end

    -- Deliberately leak: no :unmount() on the first harness.
    local h1 = testing.render(App, { cols = 20, rows = 3 })
    -- Second render must work cleanly despite the leaked h1.
    local h2 = testing.render(App2, { cols = 20, rows = 3 })

    -- h2 should render fresh content independently.
    lt.assertEquals(h2:row(1):find("second", 1, true) ~= nil, true,
                    "second harness should render fresh content")

    -- h1 still holds its own terminal state — verify it didn't get corrupted.
    lt.assertEquals(h1:row(1):find("first", 1, true) ~= nil, true,
                    "first harness should still hold its own state")

    h1:unmount()
    h2:unmount()
end
