-- test/test_harness_csi_validation.lua — the offscreen harness's fake
-- terminal rejects malformed CSI sequences (non-integer params) that
-- real terminals silently drop. Catches the 2026-04-18 "Yoga returned
-- y=72.0 -> \27[73.0;3.0H -> cursor stuck" bug in tests.

local lt       = require "ltest"
local tui      = require "tui"
local testing  = require "tui.testing"

local suite = lt.test "harness_csi_validation"

-- Direct write of a malformed CUP should fail fatally.  The fake terminal
-- lives on the harness instance (no global hijack), so we test via h._terminal.
function suite:test_float_csi_fails_fatal()
    local function App() return tui.Text { "x" } end
    local h = testing.render(App, { cols = 10, rows = 2 })

    local ok, err = pcall(function()
        h._terminal.write("\27[73.0;3.0H")
    end)
    lt.assertEquals(ok, false, "float CSI params must fail")
    lt.assertEquals(err:find("malformed CSI parameter", 1, true) ~= nil, true,
                    "error should mention malformed CSI; got: " .. tostring(err))

    h:unmount()
end

-- Well-formed CSI (integer params, SGR, DEC private) passes through.
function suite:test_valid_csi_passes()
    local function App() return tui.Text { "x" } end
    local h = testing.render(App, { cols = 10, rows = 2 })

    -- Plain CUP, SGR reset, DEC private show/hide cursor — all legal.
    h._terminal.write("\27[22;3H\27[0m\27[?25h\27[?25l")
    -- If we got here, no fatal was raised — good.
    lt.assertEquals(type(h:ansi()), "string")
    h:unmount()
end
