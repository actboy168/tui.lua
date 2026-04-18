-- test/test_dirty.lua — regression for inst.dirty clearing and Harness
-- stabilization.
--
-- Background: setState schedules `inst.dirty = true` (hooks.lua). reconciler
-- clears dirty right before calling the component fn; Harness:_paint loops
-- until no instance is dirty. The two cooperate so that a mount effect which
-- calls setState is reflected in the very first frame (no manual :rerender
-- required). Without this, the focus system's autoFocus behavior would leak
-- "first frame has no cursor" into snapshot tests.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "dirty"

-- Calling setState inside a mount-once useEffect should be visible in the
-- very first rendered frame returned by testing.render.
function suite:test_mount_effect_setter_stabilizes()
    local function App()
        local n, setN = tui.useState(0)
        tui.useEffect(function()
            if n == 0 then setN(42) end
        end, {})
        return tui.Text { ("n=%d"):format(n) }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    -- The first :_paint has already happened inside render(); the mount
    -- effect bumped n to 42, so the stabilization loop should have re-run
    -- render until the frame reflects n=42.
    local frame = h:frame()
    lt.assertEquals(frame:sub(1, 5), "n=42 ", "mount-effect setter should land on first frame")
    h:unmount()
end

-- Infinite setState in an effect should trip the stabilization guard rather
-- than hang forever. We verify it raises an error mentioning "did not
-- stabilize".
function suite:test_infinite_setter_raises()
    local function App()
        local n, setN = tui.useState(0)
        tui.useEffect(function() setN(n + 1) end)   -- deps=nil → every render
        return tui.Text { ("n=%d"):format(n) }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 10, rows = 1 })
    end)
    lt.assertEquals(ok, false, "infinite setter should error")
    lt.assertEquals(type(err) == "string" and err:find("did not stabilize", 1, true) ~= nil, true,
        "error should mention stabilization failure, got: " .. tostring(err))
end
