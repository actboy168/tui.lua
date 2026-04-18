-- test/test_dev_setstate_guard.lua — Stage 17 dev-mode render-time setter
-- guard. Calling setState/dispatch synchronously during render emits a
-- [tui:dev] warning on stderr (non-fatal — the write still goes through, but
-- we want users to move these calls into useEffect or an event handler).

local lt      = require "ltest"
local tui     = require "tui"
local hooks   = require "tui.hooks"
local testing = require "tui.testing"

local suite = lt.test "dev_setstate_guard"

-- Tiny helper to wrap a function as a component element (so the reconciler
-- creates a separate instance with its own _rendering_inst scope).
local function comp(fn, props)
    return { kind = "component", fn = fn, props = props or {} }
end

-- Synchronous setState call inside a component body warns.
function suite:test_setstate_in_render_warns()
    local stderr
    stderr = testing.capture_stderr(function()
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
    -- Source location prefix should point at the caller's test file/line, not
    -- at hooks.lua. The setter is invoked on line `setN(1)` above.
    lt.assertEquals(stderr:find("test_dev_setstate_guard.lua:", 1, true) ~= nil, true,
        "expected source location prefix, got: " .. stderr)
end

-- setState inside useEffect body (post-commit) is legal and does NOT warn.
function suite:test_setstate_in_effect_no_warn()
    local stderr
    stderr = testing.capture_stderr(function()
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

-- Synchronous dispatch call inside render warns.
function suite:test_dispatch_in_render_warns()
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

-- Parent calling child's setter during parent render is cross-component and
-- does NOT warn (only the child's OWN render would be flagged).
function suite:test_setstate_from_parent_render_does_not_warn()
    local child_setter
    local function Child()
        local _, setN = tui.useState(0)
        child_setter = setN
        return tui.Text { "c" }
    end
    local stderr = testing.capture_stderr(function()
        local function Parent()
            -- Only call into the child's setter after the child has already
            -- mounted once and populated child_setter.
            if child_setter then child_setter(2) end
            return tui.Box { comp(Child) }
        end
        local b = testing.mount_bare(Parent)
        b:rerender()  -- now child_setter is populated; parent re-render invokes it
        b:unmount()
    end)
    lt.assertEquals(stderr:find("setState called synchronously", 1, true), nil,
        "cross-component setter should not warn, got stderr: " .. stderr)
end

-- When dev_mode is off, render-time setState does NOT warn.
function suite:test_warn_disabled_outside_dev_mode()
    local stderr = testing.capture_stderr(function()
        local render_count = 0
        local function Comp()
            render_count = render_count + 1
            local n, setN = tui.useState(0)
            -- Only fire the offending call on the SECOND render, after we've
            -- had a chance to disable dev_mode between mount and rerender.
            if render_count == 2 then setN(1) end
            return tui.Text { tostring(n) }
        end
        local b = testing.mount_bare(Comp)   -- first render, no setter call
        hooks._set_dev_mode(false)           -- disable guard for the next pass
        b:rerender()                          -- setter fires, must NOT warn
        b:unmount()
    end)
    lt.assertEquals(stderr:find("setState called synchronously", 1, true), nil,
        "expected no warning when dev_mode off, got: " .. stderr)
end
