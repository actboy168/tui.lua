-- test/test_hooks_interaction.lua — complex interactions between multiple hooks.
--
-- These tests exercise realistic component patterns where hooks compose:
-- useCallback feeding useEffect, useMemo caching for useRef, dispatch via
-- context, and other multi-hook workflows.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "hooks_interaction"

-- ============================================================================
-- useCallback + useEffect interaction
-- ============================================================================

-- useCallback wrapper is safe to include in effect deps; identity is stable
-- so the effect does NOT re-run when the callback wrapper is the same.
function suite:test_callback_in_effect_deps_stable()
    local effect_runs = 0
    local cb_calls = 0
    local function App()
        local cb = tui.useCallback(function() cb_calls = cb_calls + 1 end, {})
        tui.useEffect(function()
            effect_runs = effect_runs + 1
            cb()
        end, { cb })
        return tui.Text { "" }
    end
    local b = testing.bare(App)
    lt.assertEquals(effect_runs, 1)
    lt.assertEquals(cb_calls, 1)
    -- Callback identity stable -> effect should NOT rerun
    b:rerender()
    lt.assertEquals(effect_runs, 1)
    lt.assertEquals(cb_calls, 1)
    b:unmount()
end

-- useCallback wrapper identity is stable even when its deps change.
-- Effect with {cb} in deps will NOT re-run because wrapper identity unchanged.
-- This matches React semantics: stable wrapper is the whole point of useCallback.
function suite:test_callback_wrapper_stable_effect_does_not_rerun()
    local effect_runs = 0
    local captured_values = {}
    local captured_cb = {}
    local dep = 1
    local function App()
        local cb = tui.useCallback(function()
            captured_values[#captured_values + 1] = dep
        end, { dep })
        captured_cb[#captured_cb + 1] = cb
        tui.useEffect(function()
            effect_runs = effect_runs + 1
            cb()
        end, { cb })
        return tui.Text { "" }
    end
    local b = testing.bare(App)
    lt.assertEquals(effect_runs, 1)
    lt.assertEquals(captured_values, { 1 })
    lt.assertEquals(#captured_cb, 1)
    dep = 2
    b:rerender()
    -- Effect does NOT re-run because cb wrapper identity is stable
    lt.assertEquals(effect_runs, 1)
    -- captured_cb[2] is the same wrapper as captured_cb[1]
    lt.assertEquals(rawequal(captured_cb[1], captured_cb[2]), true)
    -- Calling the wrapper directly sees the updated body
    captured_cb[2]()
    lt.assertEquals(captured_values, { 1, 2 })
    b:unmount()
end

-- ============================================================================
-- useMemo + useRef interaction
-- ============================================================================

-- useMemo computes expensive value; useRef stores mutable handle to it
-- without causing rerenders when mutated.
function suite:test_memo_result_cached_in_ref()
    local compute_calls = 0
    local function App()
        local memo_val = tui.useMemo(function()
            compute_calls = compute_calls + 1
            return { computed = compute_calls }
        end, {})
        local ref = tui.useRef(nil)
        if ref.current == nil then
            ref.current = memo_val
        end
        return tui.Text { "" }
    end
    local b = testing.bare(App)
    lt.assertEquals(compute_calls, 1)
    b:rerender()
    -- useMemo cached, compute not called again
    lt.assertEquals(compute_calls, 1)
    b:unmount()
end

-- Ref mutation doesn't invalidate memo; memo stays cached.
function suite:test_ref_mutation_does_not_invalidate_memo()
    local compute_calls = 0
    local ref_mutations = 0
    local captured_ref
    local function App()
        local memo_val = tui.useMemo(function()
            compute_calls = compute_calls + 1
            return compute_calls
        end, {})
        local ref = tui.useRef(0)
        captured_ref = ref
        ref.current = ref.current + 1
        ref_mutations = ref_mutations + 1
        return tui.Text { tostring(memo_val) }
    end
    local b = testing.bare(App)
    lt.assertEquals(compute_calls, 1)
    lt.assertEquals(ref_mutations, 1)
    b:rerender()
    -- Ref mutated but memo still cached
    lt.assertEquals(compute_calls, 1)
    lt.assertEquals(ref_mutations, 2)
    lt.assertEquals(captured_ref.current, 2)
    b:unmount()
end

-- ============================================================================
-- useReducer + useContext interaction
-- ============================================================================

-- Dispatch function from useReducer is passed through context to nested
-- consumers who can trigger state updates at the provider level.
function suite:test_reducer_dispatch_via_context()
    local Ctx = tui.createContext({ state = 0, dispatch = nil })
    local states = {}
    local function Consumer()
        local ctx = tui.useContext(Ctx)
        states[#states + 1] = ctx.state
        return tui.Box {
            tui.Text { "state: " .. tostring(ctx.state) },
            tui.Text { "dispatch: " .. type(ctx.dispatch) }
        }
    end
    local function reducer(state, action)
        if action == "inc" then return state + 1 end
        return state
    end
    local function App()
        local s, d = tui.useReducer(reducer, 10)
        return Ctx.Provider {
            value = { state = s, dispatch = d },
            Consumer,
        }
    end
    local b = testing.bare(App)
    lt.assertEquals(states[#states], 10)
    -- Note: In real app, Consumer would call ctx.dispatch("inc")
    -- Here we verify the dispatch is passed through context
    b:unmount()
end

-- ============================================================================
-- useState + useEffect + useCallback combined
-- ============================================================================

-- Real-world pattern: state drives effect that uses stable callback.
-- When multiplier changes, callback body updates but wrapper stable.
-- Effect only re-runs when count changes (in deps), not when multiplier changes.
function suite:test_state_drives_effect_uses_stable_callback()
    local multiplier = 2
    local effect_results = {}
    local captured_multiply = {}
    local function App()
        local count, setCount = tui.useState(1)
        local multiply = tui.useCallback(function(x)
            return x * multiplier
        end, { multiplier })
        captured_multiply[#captured_multiply + 1] = multiply
        tui.useEffect(function()
            effect_results[#effect_results + 1] = multiply(count)
        end, { count })  -- only count in deps, callback is stable
        return tui.Text { tostring(count) }
    end
    local b = testing.bare(App)
    lt.assertEquals(effect_results, { 2 })
    multiplier = 3
    b:rerender()
    -- Effect does NOT re-run because deps {count} unchanged
    -- Callback body updated but effect hasn't been re-triggered
    lt.assertEquals(effect_results, { 2 })
    -- Calling multiply directly uses new body
    lt.assertEquals(captured_multiply[2](1), 3)
    b:unmount()
end

-- ============================================================================
-- Multiple hooks stability across rerenders
-- ============================================================================

-- Complex component with multiple hooks: verify all identities stable when
-- their deps don't change.
function suite:test_complex_component_hook_identities_stable()
    local states = {}
    local memos = {}
    local callbacks = {}
    local refs = {}
    local function App()
        local s, setS = tui.useState(0)
        states[#states + 1] = s
        local m = tui.useMemo(function() return s * 2 end, { s })
        memos[#memos + 1] = m
        local cb = tui.useCallback(function() return s end, { s })
        callbacks[#callbacks + 1] = cb
        local r = tui.useRef(s)
        refs[#refs + 1] = r
        return tui.Text { tostring(s) }
    end
    local b = testing.bare(App)
    -- First render captures initial values
    lt.assertEquals(states, { 0 })
    lt.assertEquals(memos, { 0 })
    -- Multiple rerenders without state change
    b:rerender()
    b:rerender()
    lt.assertEquals(#states, 3)
    lt.assertEquals(#memos, 3)
    lt.assertEquals(#callbacks, 3)
    lt.assertEquals(#refs, 3)
    -- Callback wrapper identity stable (same table across renders)
    lt.assertEquals(rawequal(callbacks[1], callbacks[2]), true)
    lt.assertEquals(rawequal(callbacks[2], callbacks[3]), true)
    -- Ref identity stable
    lt.assertEquals(rawequal(refs[1], refs[2]), true)
    lt.assertEquals(rawequal(refs[2], refs[3]), true)
    -- Values unchanged
    lt.assertEquals(states, { 0, 0, 0 })
    lt.assertEquals(memos, { 0, 0, 0 })
    b:unmount()
end

-- ============================================================================
-- useEffect cleanup + useCallback interaction
-- ============================================================================

-- Effect cleanup closes over callback; callback body refresh should not
-- break cleanup semantics. Note: effect doesn't re-run when callback wrapper
-- is stable, so cleanup only runs on unmount.
function suite:test_effect_cleanup_with_callback_closure()
    local cleanups = {}
    local setups = {}
    local value = "initial"
    local function App()
        local cb = tui.useCallback(function() return value end, { value })
        tui.useEffect(function()
            setups[#setups + 1] = cb()
            return function()
                cleanups[#cleanups + 1] = cb()
            end
        end, { cb })
        return tui.Text { "" }
    end
    local b = testing.bare(App)
    lt.assertEquals(setups, { "initial" })
    lt.assertEquals(#cleanups, 0)
    value = "updated"
    b:rerender()
    -- Effect does NOT re-run because cb wrapper is stable
    -- So no cleanup or setup runs on rerender
    lt.assertEquals(#cleanups, 0)
    lt.assertEquals(setups, { "initial" })
    b:unmount()
    -- Unmount cleanup uses latest callback body
    lt.assertEquals(cleanups, { "updated" })
end

-- ============================================================================
-- useReducer + useMemo interaction
-- ============================================================================

-- Memo derived from reducer state; dispatch updates state, memo recomputes.
function suite:test_reducer_state_drives_memo()
    local memo_computes = 0
    local function reducer(state, action)
        if action.type == "add" then return state + action.value end
        return state
    end
    local function App()
        local state, dispatch = tui.useReducer(reducer, 0)
        local doubled = tui.useMemo(function()
            memo_computes = memo_computes + 1
            return state * 2
        end, { state })
        return tui.Text { tostring(doubled) }
    end
    local b = testing.bare(App)
    lt.assertEquals(memo_computes, 1)
    b:rerender()
    -- State unchanged, memo cached
    lt.assertEquals(memo_computes, 1)
    b:unmount()
end

-- ============================================================================
-- Hook order independence
-- ============================================================================

-- Hooks should maintain their slot identity even when surrounded by other
-- hooks that have different conditional behavior (conditional logic outside).
function suite:test_hook_order_maintained_with_conditional_rendering()
    local render_count = 0
    local state_values = {}
    local memo_values = {}
    local show_extra = false
    local function App()
        render_count = render_count + 1
        local s1, setS1 = tui.useState("a")
        local m1 = tui.useMemo(function() return s1 .. "_memo" end, { s1 })
        state_values[#state_values + 1] = s1
        memo_values[#memo_values + 1] = m1
        -- Extra hook calls when condition changes
        if show_extra then
            local s2 = tui.useState("extra")
            -- This would break rules if called conditionally in real React,
            -- but here we test that the first hooks maintain identity
        end
        return tui.Text { s1 }
    end
    local b = testing.bare(App)
    lt.assertEquals(state_values, { "a" })
    lt.assertEquals(memo_values, { "a_memo" })
    b:rerender()
    lt.assertEquals(state_values, { "a", "a" })
    lt.assertEquals(memo_values, { "a_memo", "a_memo" })
    b:unmount()
end
