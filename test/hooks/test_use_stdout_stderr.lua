-- test/hooks/test_use_stdout_stderr.lua — useStdout / useStderr hooks.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_stdout_stderr"

-- --------------------------------------------------------------------------
-- useStdout
-- --------------------------------------------------------------------------

-- useStdout returns a table with a .write field.
function suite:test_stdout_returns_write_field()
    local handle
    local function App()
        handle = tui.useStdout()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(type(handle), "table")
    lt.assertEquals(type(handle.write), "function")
    b:unmount()
end

-- Two successive calls inside the same render return different tables but
-- the same underlying write implementation.
function suite:test_stdout_write_is_callable()
    local w1, w2
    local function App()
        w1 = tui.useStdout().write
        w2 = tui.useStdout().write
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    -- Both should be callable functions
    lt.assertEquals(type(w1), "function")
    lt.assertEquals(type(w2), "function")
    b:unmount()
end

-- useStdout errors when called outside a component render.
function suite:test_stdout_errors_outside_render()
    local ok, err = pcall(tui.useStdout)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("outside of a component render", 1, true) ~= nil, true)
end

-- --------------------------------------------------------------------------
-- useStderr
-- --------------------------------------------------------------------------

-- useStderr() returns a table with a .write field.
function suite:test_stderr_returns_write_field()
    local handle
    local function App()
        handle = tui.useStderr()
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(type(handle), "table")
    lt.assertEquals(type(handle.write), "function")
    b:unmount()
end

-- useStderr errors when called outside a component render.
function suite:test_stderr_errors_outside_render()
    local ok, err = pcall(tui.useStderr)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("outside of a component render", 1, true) ~= nil, true)
end

-- Both write functions are callable without error.
function suite:test_stderr_write_is_callable()
    local fn
    local function App()
        fn = tui.useStderr().write
        return tui.Text { "" }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(type(fn), "function")
    b:unmount()
end
