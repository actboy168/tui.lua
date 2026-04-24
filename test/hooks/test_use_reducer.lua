-- test/test_use_reducer.lua — useReducer behavior.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_reducer"

local function counter(state, action)
    if action == "inc" then return state + 1 end
    if action == "dec" then return state - 1 end
    if action == "noop" then return state end
    return state
end

-- First render returns initial state, dispatch is non-nil function.
function suite:test_reducer_initial_state()
    local captured_state, captured_dispatch
    local function Comp()
        local s, d = tui.useReducer(counter, 0)
        captured_state    = s
        captured_dispatch = d
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(captured_state, 0)
    lt.assertEquals(type(captured_dispatch), "function")
    b:unmount()
end

-- Dispatch updates the state on next render.
function suite:test_reducer_dispatch_updates_state()
    local states = {}
    local dispatch_ref
    local function Comp()
        local s, d = tui.useReducer(counter, 0)
        states[#states + 1] = s
        dispatch_ref = d
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    dispatch_ref("inc")
    b:rerender()
    dispatch_ref("inc")
    b:rerender()
    dispatch_ref("dec")
    b:rerender()
    lt.assertEquals(states, { 0, 1, 2, 1 })
    b:unmount()
end

-- Dispatch identity stays the same across renders.
function suite:test_reducer_dispatch_identity_stable()
    local seen = {}
    local function Comp()
        local _, d = tui.useReducer(counter, 0)
        seen[#seen + 1] = d
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    b:rerender()
    b:rerender()
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    lt.assertEquals(rawequal(seen[2], seen[3]), true)
    b:unmount()
end

-- When reducer returns the same state (rawequal), no rerender is scheduled.
function suite:test_reducer_noop_when_state_unchanged()
    local dispatch_ref
    local function Comp()
        local _, d = tui.useReducer(counter, 7)
        dispatch_ref = d
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    b:expect_renders(1)
    -- noop action returns same state -> should not mark dirty
    dispatch_ref("noop")
    -- Inst shouldn't be dirty now; verify via state traversal.
    local state = b:state()
    for _, inst in pairs(state.instances) do
        lt.assertEquals(inst.dirty, false)
    end
    b:unmount()
end

-- Third-argument lazy initializer: init(initial) -> state_0.
function suite:test_reducer_lazy_init_with_third_arg()
    local init_calls = 0
    local function init(seed) init_calls = init_calls + 1; return seed * 10 end
    local captured
    local function Comp()
        local s = tui.useReducer(counter, 5, init)
        captured = s
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(captured, 50)
    lt.assertEquals(init_calls, 1)
    b:rerender()
    lt.assertEquals(init_calls, 1)     -- not called again
    b:unmount()
end
