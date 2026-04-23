-- tui/hook/state.lua — state-related hooks.
--
-- useState, useReducer, useRef, useLatestRef, useMemo, useCallback.

local core       = require "tui.hook.core"
local scheduler  = require "tui.internal.scheduler"

local M = {}

-- ---------------------------------------------------------------------------
-- useState

function M.useState(initial)
    local inst, i = core.require_instance("state")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "state", value = initial }
        inst.hooks[i] = slot
        -- Setter is stable across renders (captures slot + inst).
        slot.setter = function(v)
            if core._is_dev_mode() and core._rendering_inst == inst then
                core._warn("setState called synchronously during render of a component; " ..
                      "move it to useEffect or an event handler")
            end
            if type(v) == "function" then v = v(slot.value) end
            if slot.value == v then return end
            slot.value = v
            inst.dirty = true
            scheduler.requestRedraw()
        end
    end
    return slot.value, slot.setter
end

-- ---------------------------------------------------------------------------
-- useReducer(reducer, initial[, init]) -> (state, dispatch)
-- Redux-style state management.
--   reducer(state, action) -> next_state
--   initial                : the initial state (or seed for `init`, if given)
--   init(initial)          : optional lazy initializer, called once on mount
--
-- `dispatch` identity is stable across renders. When `reducer` returns the
-- same state value (rawequal) the hook performs no work — no rerender is
-- scheduled, matching React's bail-out semantics.
function M.useReducer(reducer, initial, init)
    local inst, i = core.require_instance("reducer")
    local slot = inst.hooks[i]
    if not slot then
        local state0
        if init ~= nil then state0 = init(initial) else state0 = initial end
        slot = { kind = "reducer", state = state0 }
        inst.hooks[i] = slot
        slot.dispatch = function(action)
            if core._is_dev_mode() and core._rendering_inst == inst then
                core._warn("dispatch called synchronously during render of a component; " ..
                      "move it to useEffect or an event handler")
            end
            local next_state = reducer(slot.state, action)
            if rawequal(next_state, slot.state) then return end
            slot.state = next_state
            inst.dirty = true
            scheduler.requestRedraw()
        end
    end
    return slot.state, slot.dispatch
end

-- ---------------------------------------------------------------------------
-- useRef(initial) -> ref (table with `.current` = initial)
-- Creates a mutable container whose identity is stable across renders.
-- Mutating `.current` does NOT trigger a rerender (use useState for that).
-- `initial` is evaluated eagerly on first mount only; subsequent renders
-- ignore the argument and return the existing ref untouched (distinct from
-- useLatestRef, which refreshes .current every render).
function M.useRef(initial)
    local inst, i = core.require_instance("ref_user")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "ref_user", ref = { current = initial } }
        inst.hooks[i] = slot
    end
    return slot.ref
end

-- ---------------------------------------------------------------------------
-- useLatestRef(value) -> ref
-- Stores `value` in a hook slot and returns a stable ref table whose .current
-- is updated every render. Used by useInterval/useTimeout/useInput/useFocus
-- internally, and exposed publicly for user code that needs stale-closure
-- avoidance without the deps ergonomics of useCallback.
function M.useLatestRef(value)
    local inst, i = core.require_instance("ref")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "ref", ref = { current = value } }
        inst.hooks[i] = slot
    else
        slot.ref.current = value
    end
    return slot.ref
end

-- ---------------------------------------------------------------------------
-- useMemo(fn, deps) -> value
-- Caches the result of `fn()` across renders; recomputes when `deps` shallow-
-- changes. Passing `deps == nil` recomputes every render (React-aligned).
function M.useMemo(fn, deps)
    local inst, i = core.require_instance("memo")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "memo", value = nil, deps = nil }
        inst.hooks[i] = slot
        slot.value = fn()
        slot.deps  = deps
        return slot.value
    end
    if deps == nil or not core.deps_equal(slot.deps, deps) then
        slot.value = fn()
        slot.deps  = deps
    end
    return slot.value
end

-- ---------------------------------------------------------------------------
-- useCallback(fn, deps) -> stable_fn
-- Returns a wrapper whose reference identity stays stable across renders
-- (so it can be passed as a dep or used in keyed child lists without
-- re-registering subscriptions). The wrapper forwards every call to the
-- current `fn`, which is updated when `deps` shallow-changes; with
-- `deps == nil` the wrapper always forwards to the freshest fn and deps
-- count as "changed" every render — matching React.
--
-- Note: this is NOT equivalent to useMemo(function() return fn end, deps),
-- because that would return a fresh `fn` each time deps change. Here the
-- outer wrapper object is created once and never replaced.
function M.useCallback(fn, deps)
    local inst, i = core.require_instance("callback")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "callback", fn = fn, wrapper = nil, deps = deps }
        slot.wrapper = function(...) return slot.fn(...) end
        inst.hooks[i] = slot
        return slot.wrapper
    end
    if deps == nil or not core.deps_equal(slot.deps, deps) then
        slot.fn   = fn
        slot.deps = deps
    end
    return slot.wrapper
end

return M
