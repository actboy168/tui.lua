-- test/test_memory.lua — subscription and state cleanup across mount/unmount.
--
-- These tests do not measure byte-level memory; they verify that the
-- bookkeeping structures the framework maintains (input subscribers, focus
-- entries, any global listener list) return to baseline after unmount. If
-- they don't, long-running CLI apps that repeatedly remount subtrees will
-- leak handlers.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "memory"

-- ---------------------------------------------------------------------------
-- 1. 500 mount/unmount cycles: broadcast_handlers must return to baseline
--    after each iteration. A leak would monotonically grow the handler list.

function suite:test_mount_unmount_loop_does_not_leak_handlers()
    -- Explicit useInput component forces a subscription per mount.
    local function Listener()
        tui.useInput(function() end)
        return tui.Text { "L" }
    end
    local ListenerComp = tui.component(Listener)
    local function AppWithInput()
        return tui.Box {
            width = 4, height = 1,
            ListenerComp {},
        }
    end
    -- Do one mount+unmount first to establish the post-unmount baseline
    -- (anything persistent that happens to exist won't bias us).
    local h0 = testing.harness(AppWithInput, { cols = 4, rows = 1 })
    h0:unmount()
    local baseline = testing.input_handler_count()
    for _ = 1, 500 do
        local h = testing.harness(AppWithInput, { cols = 4, rows = 1 })
        h:unmount()
    end
    lt.assertEquals(testing.input_handler_count(), baseline,
        "handler count must return to baseline after 500 mount/unmount cycles")
end

-- ---------------------------------------------------------------------------
-- 2. Subscription cleanup: a subtree that installs N listeners removes all
--    N on unmount. We add multiple useInput hooks inside one render to
--    exercise the loop in reconciler's unmount path.

function suite:test_multiple_subscriptions_all_cleaned_up()
    local function MultiListener()
        tui.useInput(function() end)
        tui.useInput(function() end)
        tui.useInput(function() end)
        return tui.Text { "M" }
    end
    local MultiListenerComp = tui.component(MultiListener)
    local function App()
        return tui.Box {
            width = 4, height = 1,
            MultiListenerComp {},
        }
    end
    -- Warm-up cycle to stabilize any global state.
    local h0 = testing.harness(App, { cols = 4, rows = 1 })
    h0:unmount()
    local baseline = testing.input_handler_count()
    local h = testing.harness(App, { cols = 4, rows = 1 })
    lt.assertEquals(testing.input_handler_count(), baseline + 3,
        "three useInput hooks should register three subscribers")
    h:unmount()
    lt.assertEquals(testing.input_handler_count(), baseline,
        "all three subscribers must be removed on unmount")
end
