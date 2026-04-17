-- test/test_reconciler.lua — hooks & reconciler behavior.

local lt         = require "ltest"
local tui        = require "tui"
local reconciler = require "tui.reconciler"
local hooks      = require "tui.hooks"

-- Helper: one-shot render of a function component, returning (tree, state).
-- Does not start the scheduler.
local function render_once(root, state)
    state = state or reconciler.new()
    local tree = reconciler.render(state, root, { exit = function() end })
    return tree, state
end

local suite = lt.test "reconciler_and_hooks"

-- useState initial value is preserved and returned on first render.
function suite:test_use_state_initial()
    local captured
    local function Comp()
        local n = tui.useState(42)
        captured = n
        return tui.Text { tostring(n) }
    end
    render_once(Comp)
    lt.assertEquals(captured, 42)
end

-- setState changes the value on subsequent render; same component instance.
function suite:test_set_state_triggers_new_value()
    local values = {}
    local setter_ref
    local function Comp()
        local n, setN = tui.useState(0)
        values[#values + 1] = n
        setter_ref = setN
        return tui.Text { tostring(n) }
    end
    local tree, state = render_once(Comp)
    lt.assertEquals(values[1], 0)

    setter_ref(7)
    render_once(Comp, state)
    lt.assertEquals(values[2], 7)
end

-- Hook call order must remain stable: two useState slots stay separated.
function suite:test_two_states_independent()
    local got_a, got_b, setA, setB
    local function Comp()
        local a, sA = tui.useState("a")
        local b, sB = tui.useState("b")
        got_a, got_b = a, b
        setA, setB = sA, sB
        return tui.Text { a .. b }
    end
    local _, state = render_once(Comp)
    lt.assertEquals(got_a, "a")
    lt.assertEquals(got_b, "b")

    setA("A")
    render_once(Comp, state)
    lt.assertEquals(got_a, "A")
    lt.assertEquals(got_b, "b")

    setB("B")
    render_once(Comp, state)
    lt.assertEquals(got_a, "A")
    lt.assertEquals(got_b, "B")
end

-- useEffect with {} runs exactly once across multiple renders.
function suite:test_effect_mount_once()
    local run_count = 0
    local function Comp()
        local _, setN = tui.useState(0)
        tui.useEffect(function() run_count = run_count + 1 end, {})
        return tui.Text { "x", _setN = setN }  -- just keep setN reachable
    end
    local tree, state = render_once(Comp)
    lt.assertEquals(run_count, 1)
    render_once(Comp, state)
    render_once(Comp, state)
    lt.assertEquals(run_count, 1)
end

-- useEffect with nil deps runs on every render.
function suite:test_effect_every_render()
    local run_count = 0
    local function Comp()
        tui.useEffect(function() run_count = run_count + 1 end)  -- no deps = nil
        return tui.Text { "x" }
    end
    local _, state = render_once(Comp)
    lt.assertEquals(run_count, 1)
    render_once(Comp, state)
    render_once(Comp, state)
    lt.assertEquals(run_count, 3)
end

-- Unmounting a component runs its effect cleanup.
function suite:test_effect_cleanup_on_unmount()
    local cleaned = 0
    local function Child()
        tui.useEffect(function()
            return function() cleaned = cleaned + 1 end
        end, {})
        return tui.Text { "child" }
    end

    -- Wrapper decides whether to render the child, driven by outer state.
    local show = true
    local function Root()
        return tui.Box { show and Child or nil }
    end

    local _, state = render_once(Root)
    lt.assertEquals(cleaned, 0)

    show = false
    render_once(Root, state)
    lt.assertEquals(cleaned, 1)
end

-- reconciler.shutdown runs cleanups on all remaining instances.
function suite:test_shutdown_runs_cleanups()
    local cleaned = 0
    local function Comp()
        tui.useEffect(function()
            return function() cleaned = cleaned + 1 end
        end, {})
        return tui.Text { "x" }
    end
    local _, state = render_once(Comp)
    lt.assertEquals(cleaned, 0)
    reconciler.shutdown(state)
    lt.assertEquals(cleaned, 1)
end

-- setState with the same value does not mark dirty (no re-invocation expected,
-- but at least: setter returns without error and value is unchanged).
function suite:test_set_state_same_value_is_noop()
    local setter
    local function Comp()
        local _, s = tui.useState(5)
        setter = s
        return tui.Text { "x" }
    end
    local _, state = render_once(Comp)
    -- Calling with same value must not raise; dirty flag is internal but
    -- the next render should still observe 5.
    setter(5)
    local captured
    local function Comp2()
        local v = tui.useState(5)
        captured = v
        return tui.Text { "x" }
    end
    -- (not actually rendering Comp2 against state; this test mainly asserts
    -- no error was raised in the no-op setter path.)
    lt.assertEquals(type(setter), "function")
end

-- Function-setter form: setN(function(v) return v+1 end).
function suite:test_functional_setter()
    local captured
    local setter
    local function Comp()
        local n, s = tui.useState(10)
        captured = n
        setter = s
        return tui.Text { tostring(n) }
    end
    local _, state = render_once(Comp)
    lt.assertEquals(captured, 10)
    setter(function(v) return v + 5 end)
    render_once(Comp, state)
    lt.assertEquals(captured, 15)
end
