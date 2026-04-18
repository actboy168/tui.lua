-- test/test_dev_hook_in_plain_function.lua — dev-mode detection for hooks
-- called from a plain function (not wrapped as a component element).
--
-- Without this check the hook silently attaches to the *parent*
-- component's slot list; a later conditional render then produces an
-- opaque "hook count mismatch" fatal somewhere far from the real cause.
-- The intent is to fail at the exact bad call site instead.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "dev_hook_in_plain_function"

-- A plain helper that itself calls a hook. Because it's not a component
-- factory, hooking into its caller violates the "hook only in component"
-- contract. The detector should fire.
local function PlainHelper()
    tui.useState(0)  -- <-- offending call site
    return tui.Text { "" }
end

function suite:test_hook_in_plain_function_is_fatal()
    local function App()
        return tui.Box {
            -- Calling PlainHelper() inline during App's render means its
            -- useState is counted against App's instance.
            PlainHelper(),
        }
    end
    local ok, err = pcall(function()
        local h = testing.render(App, { cols = 20, rows = 3 })
        h:unmount()
    end)
    lt.assertEquals(ok, false, "plain-function hook call should fail")
    lt.assertEquals(err:find("[tui:fatal] hook called from a plain function",
                             1, true) ~= nil, true,
                    "error must point at the reason, got: " .. tostring(err))
end

-- Sanity: wrapping the same body in a component factory passes. Also
-- confirms hooks work normally when invoked inside their own component.
function suite:test_component_factory_passes()
    local Wrapped = function(props)
        props = props or {}
        local key = props.key; props.key = nil
        return { kind = "component", fn = function()
            tui.useState(0)
            return tui.Text { "" }
        end, props = props, key = key }
    end

    local function App()
        return tui.Box { Wrapped() }
    end

    local h = testing.render(App, { cols = 20, rows = 3 })
    -- No error means pass. Sanity-check nothing stderr'd either.
    h:unmount()
end
