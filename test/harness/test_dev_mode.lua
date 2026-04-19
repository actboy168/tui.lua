-- test/test_dev_mode.lua — Dev-mode validation tests (Stage 17)

local lt      = require "ltest"
local tui     = require "tui"
local hooks   = require "tui.hooks"
local testing = require "tui.testing"

local suite = lt.test "dev_mode"

-- ============================================================================
-- Key warning (3+ children without key)
-- ============================================================================

function suite.test_missing_key_warns()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
                tui.Text { "c" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("[tui:dev]", 1, true) ~= nil, true,
        "expected dev warning, got: " .. stderr)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true) ~= nil, true,
        "expected 'unique key prop' in message, got: " .. stderr)
end

function suite.test_all_keyed_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                { kind = "text", children = { "a" }, props = {}, key = "a" },
                { kind = "text", children = { "b" }, props = {}, key = "b" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "did not expect warning, got: " .. stderr)
end

function suite.test_single_child_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box { tui.Text { "only" } }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "did not expect warning for single child, got: " .. stderr)
end

function suite.test_two_children_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "2 children should not trigger key warning, got: " .. stderr)
end

-- ============================================================================
-- Render-time setter guard
-- ============================================================================

function suite.test_setstate_in_render_warns()
    local stderr = testing.capture_stderr(function()
        local did_dirty_set
        local function Comp()
            local n, setN = tui.useState(0)
            if not did_dirty_set then
                did_dirty_set = true
                setN(1)
            end
            return tui.Text { tostring(n) }
        end
        local b = testing.mount_bare(Comp)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("[tui:dev]", 1, true) ~= nil, true,
        "expected [tui:dev] prefix in stderr, got: " .. stderr)
    lt.assertEquals(stderr:find("setState called synchronously", 1, true) ~= nil, true,
        "expected setState warning, got: " .. stderr)
end

function suite.test_setstate_in_effect_no_warn()
    local stderr = testing.capture_stderr(function()
        local function Comp()
            local n, setN = tui.useState(0)
            tui.useEffect(function()
                if n == 0 then setN(1) end
            end, { n })
            return tui.Text { tostring(n) }
        end
        local b = testing.mount_bare(Comp)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("setState called synchronously", 1, true), nil,
        "did not expect warning, got stderr: " .. stderr)
end

function suite.test_dispatch_in_render_warns()
    local function reducer(s, a) return (s or 0) + (a or 1) end
    local stderr = testing.capture_stderr(function()
        local fired
        local function Comp()
            local s, dispatch = tui.useReducer(reducer, 0)
            if not fired then
                fired = true
                dispatch(1)
            end
            return tui.Text { tostring(s) }
        end
        local b = testing.mount_bare(Comp)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("dispatch called synchronously", 1, true) ~= nil, true,
        "expected dispatch warning, got: " .. stderr)
end

-- ============================================================================
-- Hook order validation
-- ============================================================================

function suite.test_hook_count_added_on_rerender_errors()
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
    lt.assertEquals(err:find("[tui:fatal]", 1, true) ~= nil, true,
        "expected fatal prefix, got: " .. tostring(err))
    b:unmount()
end

function suite.test_hook_kind_swapped_errors()
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
    lt.assertEquals(err:find("[tui:fatal]", 1, true) ~= nil, true,
        "expected fatal prefix, got: " .. tostring(err))
    b:unmount()
end

function suite.test_same_kinds_no_error()
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

-- ============================================================================
-- Hook in plain function detection
-- ============================================================================

local function PlainHelper()
    tui.useState(0)
    return tui.Text { "" }
end

function suite.test_hook_in_plain_function_is_fatal()
    local function App()
        return tui.Box { PlainHelper() }
    end
    local ok, err = pcall(function()
        local h = testing.render(App, { cols = 20, rows = 3 })
        h:unmount()
    end)
    lt.assertEquals(ok, false, "plain-function hook call should fail")
    lt.assertEquals(err:find("[tui:fatal] hook called from a plain function", 1, true) ~= nil, true,
        "error must point at the reason, got: " .. tostring(err))
end

function suite.test_component_factory_passes()
    local Wrapped = tui.component(function()
        tui.useState(0)
        return tui.Text { "" }
    end)

    local function App()
        return tui.Box { Wrapped() }
    end

    local h = testing.render(App, { cols = 20, rows = 3 })
    h:unmount()
end
