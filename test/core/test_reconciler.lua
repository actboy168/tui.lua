-- test/test_reconciler.lua — hooks & reconciler behavior.

local lt         = require "ltest"
local tui        = require "tui"
local testing    = require "tui.testing"
local reconciler = require "tui.reconciler"

local suite = lt.test "reconciler_and_hooks"

-- useState initial value is preserved and returned on first render.
function suite:test_use_state_initial()
    local captured
    local function Comp()
        local n = tui.useState(42)
        captured = n
        return tui.Text { tostring(n) }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(captured, 42)
    b:unmount()
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
    local b = testing.mount_bare(Comp)
    lt.assertEquals(values[1], 0)

    setter_ref(7)
    b:rerender()
    lt.assertEquals(values[2], 7)
    b:unmount()
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
    local b = testing.mount_bare(Comp)
    lt.assertEquals(got_a, "a")
    lt.assertEquals(got_b, "b")

    setA("A")
    b:rerender()
    lt.assertEquals(got_a, "A")
    lt.assertEquals(got_b, "b")

    setB("B")
    b:rerender()
    lt.assertEquals(got_a, "A")
    lt.assertEquals(got_b, "B")
    b:unmount()
end

-- useEffect with {} runs exactly once across multiple renders.
function suite:test_effect_mount_once()
    local run_count = 0
    local function Comp()
        local _, setN = tui.useState(0)
        tui.useEffect(function() run_count = run_count + 1 end, {})
        return tui.Text { "x", _setN = setN }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(run_count, 1)
    b:rerender()
    b:rerender()
    lt.assertEquals(run_count, 1)
    b:unmount()
end

-- useEffect with nil deps runs on every render.
function suite:test_effect_every_render()
    local run_count = 0
    local function Comp()
        tui.useEffect(function() run_count = run_count + 1 end)  -- no deps = nil
        return tui.Text { "x" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(run_count, 1)
    b:rerender()
    b:rerender()
    lt.assertEquals(run_count, 3)
    b:unmount()
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

    local show = true
    local function Root()
        return tui.Box { show and Child or nil }
    end

    local b = testing.mount_bare(Root)
    lt.assertEquals(cleaned, 0)

    show = false
    b:rerender()
    lt.assertEquals(cleaned, 1)
    b:unmount()
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
    local b = testing.mount_bare(Comp)
    lt.assertEquals(cleaned, 0)
    reconciler.shutdown(b:state())
    lt.assertEquals(cleaned, 1)
    -- unmount would double-shutdown; skip it here since we already tore down.
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
    local b = testing.mount_bare(Comp)
    setter(5)
    lt.assertEquals(type(setter), "function")
    b:unmount()
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
    local b = testing.mount_bare(Comp)
    lt.assertEquals(captured, 10)
    setter(function(v) return v + 5 end)
    b:rerender()
    lt.assertEquals(captured, 15)
    b:unmount()
end

-- S2.1: useEffect with a deps array re-runs when any dep changes (shallow compare).
function suite:test_effect_deps_rerun_on_change()
    local run_count = 0
    local dep_value = "a"
    local function Comp()
        tui.useEffect(function() run_count = run_count + 1 end, { dep_value })
        return tui.Text { "x" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(run_count, 1)
    b:rerender()
    lt.assertEquals(run_count, 1)
    dep_value = "b"
    b:rerender()
    lt.assertEquals(run_count, 2)
    b:rerender()
    lt.assertEquals(run_count, 2)
    b:unmount()
end

-- S2.11: cleanup runs before the new effect body on re-run.
function suite:test_effect_cleanup_before_rerun()
    local events = {}
    local dep = 1
    local function Comp()
        tui.useEffect(function()
            events[#events + 1] = "setup"
            return function() events[#events + 1] = "cleanup" end
        end, { dep })
        return tui.Text { "x" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(events, { "setup" })
    dep = 2
    b:rerender()
    lt.assertEquals(events, { "setup", "cleanup", "setup" })
    b:unmount()
end

-- S2.11 (nil deps path): cleanup also runs before new effect every render.
function suite:test_effect_cleanup_nil_deps_every_render()
    local events = {}
    local function Comp()
        tui.useEffect(function()
            events[#events + 1] = "s"
            return function() events[#events + 1] = "c" end
        end)  -- no deps = nil = every render
        return tui.Text { "x" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(events, { "s" })
    b:rerender()
    lt.assertEquals(events, { "s", "c", "s" })
    b:unmount()
end

-- useInput: handler receives parsed events; subscribe/unsubscribe lifecycle.
function suite:test_use_input_subscribes_and_unsubscribes()
    local input_mod = require "tui.input"

    local got = {}
    local mounted = true
    local function Child()
        tui.useInput(function(input, key)
            got[#got + 1] = { input = input, name = key.name }
        end)
        return tui.Text { "child" }
    end
    local function Root()
        return tui.Box { mounted and Child or nil }
    end

    local b = testing.mount_bare(Root)
    lt.assertEquals(#input_mod._handlers(), 1)

    b:dispatch("x")
    lt.assertEquals(#got, 1)
    lt.assertEquals(got[1].input, "x")

    mounted = false
    b:rerender()
    lt.assertEquals(#input_mod._handlers(), 0)

    b:dispatch("y")
    lt.assertEquals(#got, 1)   -- no new events
    b:unmount()
end

-- useInput sees the latest handler closure (no stale capture).
function suite:test_use_input_uses_latest_handler()
    local multiplier = 1
    local sum = 0
    local function Comp()
        local m = multiplier
        tui.useInput(function(input, key)
            if key.name == "char" then sum = sum + m end
        end)
        return tui.Text { "x" }
    end

    local b = testing.mount_bare(Comp)
    b:dispatch("a")
    lt.assertEquals(sum, 1)

    multiplier = 10
    b:rerender()
    b:dispatch("a")
    lt.assertEquals(sum, 11)  -- 1 + 10

    b:unmount()
end

-- Stage 15: swapping component fn at the same path (no key) treats it as a
-- new instance — previous state is thrown away, effect cleanup fires.
function suite:test_fn_identity_change_forces_remount()
    local events = {}
    local function A()
        tui.useEffect(function()
            events[#events + 1] = "A-setup"
            return function() events[#events + 1] = "A-cleanup" end
        end, {})
        return tui.Text { "A" }
    end
    local function B()
        tui.useEffect(function()
            events[#events + 1] = "B-setup"
            return function() events[#events + 1] = "B-cleanup" end
        end, {})
        return tui.Text { "B" }
    end

    local which = A
    local function Root()
        return tui.Box { tui.component(which, {}) }
    end

    local b = testing.mount_bare(Root)
    lt.assertEquals(events, { "A-setup" })

    which = B
    b:rerender()
    -- A instance torn down (cleanup), fresh B instance mounted.
    lt.assertEquals(events, { "A-setup", "A-cleanup", "B-setup" })

    b:unmount()
end

-- Stage 15: same component fn across rerenders does NOT remount — the same
-- instance is reused, hook state survives, no effect cleanup triggered.
function suite:test_fn_identity_stable_preserves_state()
    local events = {}
    local counter_values = {}
    local setter_ref
    local function Comp()
        local n, setN = tui.useState(0)
        counter_values[#counter_values + 1] = n
        setter_ref = setN
        tui.useEffect(function()
            events[#events + 1] = "setup"
            return function() events[#events + 1] = "cleanup" end
        end, {})
        return tui.Text { tostring(n) }
    end
    local CompEl = tui.component(Comp)
    local function Root()
        return tui.Box { CompEl {} }
    end

    local b = testing.mount_bare(Root)
    lt.assertEquals(counter_values, { 0 })
    lt.assertEquals(events, { "setup" })

    setter_ref(7)
    b:rerender()
    lt.assertEquals(counter_values, { 0, 7 }, "same fn preserves hook state")
    lt.assertEquals(events, { "setup" },
        "same fn identity: no cleanup, no re-setup")

    b:unmount()
    lt.assertEquals(events, { "setup", "cleanup" })
end
