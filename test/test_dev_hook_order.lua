-- test/test_dev_hook_order.lua — Stage 17 dev-mode hook order validation.
--
-- When TUI_DEV_MODE is on (which the testing harness force-enables), the
-- reconciler remembers the sequence of hook kinds a component called on each
-- render. If a subsequent render calls a different number/kind of hooks at
-- the same slot index, it raises a [tui:fatal] error — because the slot
-- storage is already corrupted past that point and recovery isn't safe.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "dev_hook_order"

-- Adding a hook on a later render bumps the count → fatal error.
function suite:test_hook_count_added_on_rerender_errors()
    local include_second
    local function Comp()
        tui.useState(0)
        if include_second then tui.useState(1) end
        return tui.Text { "x" }
    end

    include_second = false
    local b = testing.mount_bare(Comp)

    include_second = true
    local ok, err = pcall(function() b:rerender() end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("[tui:fatal]", 1, true) ~= nil, true,
        "expected fatal prefix, got: " .. tostring(err))
    lt.assertEquals(err:find("hook count mismatch", 1, true) ~= nil, true,
        "expected count-mismatch message, got: " .. tostring(err))
    b:unmount()
end

-- Swapping a hook kind at the same slot (state→effect) → fatal error.
function suite:test_hook_kind_swapped_errors()
    local use_effect_here
    local function Comp()
        if use_effect_here then
            tui.useEffect(function() end, {})
        else
            tui.useState(0)
        end
        tui.useState(1)
        return tui.Text { "x" }
    end

    use_effect_here = false
    local b = testing.mount_bare(Comp)

    use_effect_here = true
    local ok, err = pcall(function() b:rerender() end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("[tui:fatal]", 1, true) ~= nil, true,
        "expected fatal prefix, got: " .. tostring(err))
    lt.assertEquals(err:find("hook order violation", 1, true) ~= nil, true,
        "expected order-violation message, got: " .. tostring(err))
    lt.assertEquals(err:find("expected state", 1, true) ~= nil, true,
        "expected 'expected state' in message, got: " .. tostring(err))
    b:unmount()
end

-- Control case: same hook kinds across renders → no error.
function suite:test_same_kinds_no_error()
    local function Comp()
        tui.useState(0)
        tui.useEffect(function() end, {})
        tui.useMemo(function() return 1 end, {})
        return tui.Text { "x" }
    end

    local b = testing.mount_bare(Comp)
    b:rerender()
    b:rerender()
    b:unmount()
end
