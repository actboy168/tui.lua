-- test/test_dirty.lua — regression for inst.dirty clearing.
--
-- Background: setState schedules `inst.dirty = true` (hooks.lua). reconciler
-- clears dirty right before calling the component fn. Mount effects that call
-- setState will be reflected on the next frame (via requestRedraw → next
-- _paint), not the current one.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "dirty"

-- Calling setState inside a mount-once useEffect should be visible after
-- a rerender (mount-effect state changes are consumed on the next frame).
function suite:test_mount_effect_setter_on_next_frame()
    local function App()
        local n, setN = tui.useState(0)
        tui.useEffect(function()
            if n == 0 then setN(42) end
        end, {})
        return tui.Text { ("n=%d"):format(n) }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    -- First frame: mount effect has not fired yet (or fired but setState
    -- is not consumed until next paint).
    lt.assertEquals(h:frame():sub(1, 5), "n=0  ", "first frame should show n=0")
    h:rerender()
    lt.assertEquals(h:frame():sub(1, 5), "n=42 ", "second frame should show n=42")
    h:unmount()
end
