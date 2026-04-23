-- tui/hooks.lua — React-style hooks for tui.lua.
--
-- Stage 2 scope:
--   useState(initial)       -> value, setter
--   useEffect(fn, deps)     -> deps=={} mount-once; deps==nil run every render
--   useInterval(fn, ms)     -> sugar over scheduler.setInterval + cleanup
--   useTimeout(fn, ms)      -> sugar over scheduler.setTimeout + cleanup
--
-- All hooks read/write slots on the *current* component instance tracked by
-- the reconciler. The reconciler is responsible for:
--   * setting tui.hooks._current_instance before invoking a component fn
--   * calling tui.hooks._begin_render(instance) to reset the cursor
--   * calling tui.hooks._end_render() after the fn returns
--   * invoking queued effects after commit via _flush_effects(instance)

local scheduler = require "tui.internal.scheduler"

local _SOURCE = debug.getinfo(1, "S").source

-- Message handler for xpcall: wraps error into {message, trace} so
-- boundaries receive a structured object rather than a bare string.
-- Idempotent so re-throws across nested boundaries don't double-wrap.
-- Fatal errors (with the [tui:fatal] prefix) are NOT wrapped — they bypass
-- boundaries entirely, so wrapping adds no value and complicates callers.
local function wrap_err(e)
    if type(e) == "table" and e.message ~= nil then return e end
    if type(e) == "string" and e:sub(1, 12) == "[tui:fatal] " then return e end
    return { message = e, trace = debug.traceback(e, 2) }
end

local M = {}

-- ---------------------------------------------------------------------------
-- Dev mode (Stage 17). When enabled:
--   * Hook order is validated across renders; drift is a [tui:fatal] error.
--   * useState/useReducer setters warn if called synchronously during render.
--   * Reconciler warns on >1 element children with any unkeyed child.
-- Disabled by default -> all checks compile out behind a single `if` each.

local dev_mode = false

function M._set_dev_mode(on)
    dev_mode = on and true or false
end

function M._is_dev_mode() return dev_mode end

-- Walk up the call stack to find the first frame whose source file is NOT
-- inside the framework itself (tui/*.lua or tui_core). That's the user code
-- that triggered the warning — far more useful than a hook-internal line.
-- Returns "file.lua:NN: " ready to be prepended, or "" if no user frame was
-- found (framework-internal call path).
local function _source_prefix()
    for lvl = 2, 20 do
        local info = debug.getinfo(lvl, "Sl")
        if not info then break end
        local src = info.source or ""
        -- Skip C frames, =[C] tags, and any source inside the framework tree.
        -- Match on "/tui/" or "\tui\" — cross-platform path separators.
        if src:sub(1, 1) == "@"
            and not src:find("[/\\]tui[/\\]", 1, false)
            and not src:find("[/\\]ltest%.lua$")
        then
            -- Strip leading "@" and any directory prefix for readability.
            local path = src:sub(2)
            local tail = path:match("[^/\\]+$") or path
            return tail .. ":" .. tostring(info.currentline) .. ": "
        end
    end
    return ""
end
M._source_prefix = _source_prefix

local function _warn(msg)
    if dev_mode then
        io.stderr:write("[tui:dev] " .. _source_prefix() .. msg .. "\n")
    end
end
M._warn = _warn

-- ---------------------------------------------------------------------------
-- Current instance (set by reconciler during a render pass)

local current   = nil
local cursor    = 0

-- Set while a component fn is actively executing; cleared when it returns.
-- setState/dispatch compare against this to detect synchronous state writes
-- inside render (an anti-pattern). Post-commit effects run with this cleared,
-- so `setN(...)` inside useEffect bodies is legal and won't warn.
M._rendering_inst = nil

function M._begin_render(instance)
    current = instance
    cursor  = 0
    instance.hooks         = instance.hooks         or {}
    instance.pending_fx    = {}
    if dev_mode then
        instance._hook_kinds = {}
    end
    M._rendering_inst = instance
end

function M._end_render()
    if dev_mode and current then
        local prev = current._prev_hook_kinds
        local curr = current._hook_kinds
        if prev and curr then
            if #prev ~= #curr then
                local err = ("[tui:fatal] hook count mismatch: last render used %d hooks, this render used %d")
                    :format(#prev, #curr)
                current._prev_hook_kinds = nil
                current._hook_kinds = nil
                M._rendering_inst = nil
                current = nil
                cursor = 0
                error(err, 0)
            end
            for i = 1, #curr do
                if prev[i] ~= curr[i] then
                    local err = ("[tui:fatal] hook order violation at slot %d: expected %s, got %s")
                        :format(i, tostring(prev[i]), tostring(curr[i]))
                    current._prev_hook_kinds = nil
                    current._hook_kinds = nil
                    M._rendering_inst = nil
                    current = nil
                    cursor = 0
                    error(err, 0)
                end
            end
        end
        current._prev_hook_kinds = curr
        current._hook_kinds = nil
    end
    M._rendering_inst = nil
    current = nil
    cursor  = 0
end

-- Shallow-equal for two arrays of deps (rawequal per element, same length).
local function deps_equal(a, b)
    if a == nil or b == nil then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if not rawequal(a[i], b[i]) then return false end
    end
    return true
end

-- Called after the element tree has been committed, so effects observe the
-- latest rendered output.
--
-- Deps semantics (React-aligned):
--   nil       -> run every render; always cleanup previous first.
--   {}        -> run exactly once on mount; cleanup on unmount.
--   {d1,d2}   -> re-run only when any dep changed (shallow); cleanup prev first.
--
-- Error handling: both cleanup() and fn() are pcall-wrapped. On error:
--   * fatal (reconciler.is_fatal)    → rethrow; produce_tree's outer pcall
--                                       paints the banner error screen.
--   * nearest_boundary present       → set its caught_error + mark it dirty
--                                       + requestRedraw. Next frame skips
--                                       the boundary's children and shows
--                                       fallback; the throwing component
--                                       unmounts as part of that transition.
--   * no ancestor boundary           → rethrow; framework pcall handles it.
-- After handling, we still advance slot.deps/ran so the faulty effect isn't
-- retried every frame in a tight loop — the boundary transition itself is
-- the recovery signal.
local reconciler_mod   -- lazy require to avoid init cycle
local function ensure_reconciler()
    reconciler_mod = reconciler_mod or require "tui.internal.reconciler"
    return reconciler_mod
end

local function route_effect_error(instance, err)
    local rec = ensure_reconciler()
    if rec.is_fatal(err) then error(err, 0) end

    local boundary = instance.nearest_boundary
    if boundary then
        boundary.caught_error = err
        boundary.dirty = true   -- pokes harness stabilization + main loop
        scheduler.requestRedraw()
        return
    end
    -- No boundary: unwrap to the original message string so that callers
    -- above (framework pcall, test pcall) see a plain error, not a table.
    error(type(err) == "table" and err.message or err, 0)
end

-- Wrap a user-supplied event handler (useInput, useFocus on_input) so any
-- error raised during dispatch routes to the nearest ErrorBoundary set on
-- the owning component instance at subscribe time. The instance reference
-- is captured *once* here; its `.nearest_boundary` field is refreshed by
-- the reconciler every render so the lookup stays current.
--
-- The wrapped closure has the same calling convention as `fn`. Returning
-- fn's first result would complicate the happy path for no benefit since
-- input handlers are fire-and-forget — we just preserve nil.
local function wrap_handler_for_boundary(instance, fn)
    return function(...)
        local ok, err = xpcall(fn, wrap_err, ...)
        if not ok then route_effect_error(instance, err) end
    end
end

function M._route_handler_error(instance, err)
    route_effect_error(instance, err)
end

function M._flush_effects(instance)
    for _, fx in ipairs(instance.pending_fx or {}) do
        local slot = fx.slot
        local should_run
        if fx.deps == nil then
            should_run = true
        elseif not slot.ran then
            should_run = true   -- first mount
        else
            -- Re-run only if deps changed. `{}` with ran=true compares equal
            -- to itself and thus stays mounted (correct mount-once behavior).
            should_run = not deps_equal(slot.deps, fx.deps)
        end
        if should_run then
            -- Always cleanup the previous effect before running the new one
            -- (S2.11 — React-aligned ordering). Both pcalls advance deps
            -- afterwards regardless of outcome.
            if slot.cleanup then
                local old = slot.cleanup
                slot.cleanup = nil
                local ok, err = xpcall(old, wrap_err)
                if not ok then route_effect_error(instance, err) end
            end
            local ok, result = xpcall(fx.fn, wrap_err)
            if ok then
                slot.cleanup = result or nil
            else
                slot.cleanup = nil
                route_effect_error(instance, result)
            end
            slot.deps = fx.deps
            slot.ran  = true
        end
    end
    instance.pending_fx = nil
end

-- Called when an instance is being torn down; run all cleanups.
-- Cleanup errors during unmount are routed through the same boundary
-- mechanism as effect errors so they don't crash the render pass. If the
-- instance has no ancestor boundary, we swallow (rather than rethrow) —
-- unmount typically happens as part of already-in-progress error recovery
-- or harness shutdown, and re-raising at that point is more disruptive
-- than useful. First error wins: subsequent cleanups still run so every
-- slot gets a chance to release its resources.
function M._unmount(instance)
    for _, slot in ipairs(instance.hooks or {}) do
        if slot and slot.cleanup then
            local fn = slot.cleanup
            slot.cleanup = nil
            local ok, err = xpcall(fn, wrap_err)
            if not ok then
                local rec = ensure_reconciler()
                if rec.is_fatal(err) then error(err, 0) end
                local boundary = instance.nearest_boundary
                if boundary and boundary.caught_error == nil then
                    boundary.caught_error = err
                    boundary.dirty = true
                    scheduler.requestRedraw()
                end
                -- else: swallow. See function header for rationale.
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Internal helpers

-- When a plain function (not a registered component) calls a hook, Lua's
-- `current` at hook time points at the *parent* component whose render is
-- on the call stack — not nil. So `assert(current, ...)` won't catch this
-- footgun; the hook silently tacks itself onto the parent's slot list,
-- and a later conditional render produces a hook count mismatch somewhere
-- far from the real cause.
--
-- Dev-mode detection: every `_begin_render` records the component's `fn`
-- on the instance. `require_instance` finds the first user-code frame
-- above itself (skipping all tui/hooks.lua frames — internal hooks like
-- useInterval call useEffect) and checks whether that frame's function
-- is the currently-rendering component. If not, some intermediate helper
-- function is the direct caller — raise with its source location.
local function detect_plain_function_hook()
    if not dev_mode then return end
    if not current then return end
    local expected = current._component_fn
    if not expected then return end

    local user_lvl
    for lvl = 3, 30 do
        local info = debug.getinfo(lvl, "S")
        if not info then break end
        if info.source ~= _SOURCE then
            user_lvl = lvl
            break
        end
    end
    if not user_lvl then return end

    local info = debug.getinfo(user_lvl, "Sfl")
    if not info then return end
    if info.func == expected then return end

    local where = (info.source or "?") .. ":" .. tostring(info.currentline)
    error("[tui:fatal] hook called from a plain function (" .. where ..
          ") inside the render of another component; wrap it with " ..
          "`{ kind='component', fn=..., props=... }` (see tui/builtin/spinner.lua) " ..
          "so its hooks live on their own instance.", 0)
end

local function require_instance(kind)
    assert(current, "hook called outside of a component render")
    detect_plain_function_hook()
    cursor = cursor + 1
    if dev_mode and kind then
        current._hook_kinds[cursor] = kind
    end
    return current, cursor
end

-- ---------------------------------------------------------------------------
-- useState

function M.useState(initial)
    local inst, i = require_instance("state")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "state", value = initial }
        inst.hooks[i] = slot
        -- Setter is stable across renders (captures slot + inst).
        slot.setter = function(v)
            if dev_mode and M._rendering_inst == inst then
                _warn("setState called synchronously during render of a component; " ..
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
-- useEffect

function M.useEffect(fn, deps)
    local inst, i = require_instance("effect")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "effect", ran = false, cleanup = nil }
        inst.hooks[i] = slot
    end
    -- Queue; _flush_effects will decide whether to actually run.
    inst.pending_fx[#inst.pending_fx + 1] = { slot = slot, fn = fn, deps = deps }
end

-- ---------------------------------------------------------------------------
-- useMemo(fn, deps) -> value
-- Caches the result of `fn()` across renders; recomputes when `deps` shallow-
-- changes. Passing `deps == nil` recomputes every render (React-aligned).
function M.useMemo(fn, deps)
    local inst, i = require_instance("memo")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "memo", value = nil, deps = nil }
        inst.hooks[i] = slot
        slot.value = fn()
        slot.deps  = deps
        return slot.value
    end
    if deps == nil or not deps_equal(slot.deps, deps) then
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
    local inst, i = require_instance("callback")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "callback", fn = fn, wrapper = nil, deps = deps }
        slot.wrapper = function(...) return slot.fn(...) end
        inst.hooks[i] = slot
        return slot.wrapper
    end
    if deps == nil or not deps_equal(slot.deps, deps) then
        slot.fn   = fn
        slot.deps = deps
    end
    return slot.wrapper
end

-- ---------------------------------------------------------------------------
-- useRef(initial) -> ref (table with `.current` = initial)
-- Creates a mutable container whose identity is stable across renders.
-- Mutating `.current` does NOT trigger a rerender (use useState for that).
-- `initial` is evaluated eagerly on first mount only; subsequent renders
-- ignore the argument and return the existing ref untouched (distinct from
-- useLatestRef, which refreshes .current every render).
function M.useRef(initial)
    local inst, i = require_instance("ref_user")
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
    local inst, i = require_instance("ref")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "ref", ref = { current = value } }
        inst.hooks[i] = slot
    else
        slot.ref.current = value
    end
    return slot.ref
end
local useLatestRef = M.useLatestRef

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
    local inst, i = require_instance("reducer")
    local slot = inst.hooks[i]
    if not slot then
        local state0
        if init ~= nil then state0 = init(initial) else state0 = initial end
        slot = { kind = "reducer", state = state0 }
        inst.hooks[i] = slot
        slot.dispatch = function(action)
            if dev_mode and M._rendering_inst == inst then
                _warn("dispatch called synchronously during render of a component; " ..
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
-- useContext(ctx) -> value
-- Consumes the nearest ancestor <ctx.Provider value=...> in the element
-- tree. Returns `ctx._default` if no Provider is in scope. The hook slot
-- exists only to keep the cursor position stable across renders — the
-- actual lookup goes through the reconciler's context_stack so Provider
-- changes reflect immediately.
function M.useContext(ctx)
    local inst, i = require_instance("context")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "context" }
        inst.hooks[i] = slot
    end
    if type(ctx) ~= "table" or ctx._kind ~= "tui_context" then
        error("useContext: expected a context created by tui.createContext", 2)
    end
    return ensure_reconciler()._lookup_context(ctx)
end

-- ---------------------------------------------------------------------------
-- createContext(default_value) -> context object
-- The returned table carries a `Provider` factory: `MyCtx.Provider { value=X, ... }`
-- produces an element of kind "provider" that the reconciler splices into
-- the render tree without creating a component instance.
local element_mod   -- lazy require to avoid init cycle with element.lua
function M.createContext(default_value)
    element_mod = element_mod or require "tui.internal.element"
    local ctx = {
        _kind    = "tui_context",
        _default = default_value,
    }
    ctx.Provider = function(t)
        t = t or {}
        local props, children = element_mod._split_props_children(t)
        local key = props.key
        props.key = nil
        if props.value == nil then
            error("Context.Provider: missing required `value` prop", 2)
        end
        return {
            kind     = "provider",
            context  = ctx,
            value    = props.value,
            key      = key,
            children = children,
        }
    end
    return ctx
end

-- ---------------------------------------------------------------------------
-- Timer sugar (built on top of useEffect for cleanup)

function M.useInterval(fn, ms)
    local ref = useLatestRef(fn)
    M.useEffect(function()
        local id = scheduler.setInterval(function() ref.current() end, ms)
        return function() scheduler.clearTimer(id) end
    end, { ms })
end

function M.useTimeout(fn, ms)
    local ref = useLatestRef(fn)
    M.useEffect(function()
        local id = scheduler.setTimeout(function() ref.current() end, ms)
        return function() scheduler.clearTimer(id) end
    end, { ms })
end

-- ---------------------------------------------------------------------------
-- useAnimation(opts) -> { frame, time, delta, reset }
--
-- opts = {
--   interval = number ms (default 80),
--   isActive = bool    (default true),
-- }
--
-- A frame-ticking primitive for animated components (Spinner, ProgressBar,
-- marquee text, etc.). Every `interval` ms the hook bumps an internal tick
-- counter, which triggers a rerender; the returned values describe the
-- current tick relative to when animation last started.
--
--   frame : 0-based tick count since the last start / reset. Cycles
--           forever — consumers typically `frames[frame % N + 1]`.
--   time  : virtual ms elapsed since last start / reset, summed from the
--           actual deltas observed at each tick.
--   delta : virtual ms between this frame and the previous. First frame is
--           `interval`. Under a single `harness:advance(N)` that batch-
--           fires the timer multiple times, each firing reads scheduler.now()
--           to compute the real delta for that tick (catches up faithfully).
--   reset : stable fn () -> nil. Restarts counters; if isActive is true the
--           next tick fires `interval` ms later.
--
-- isActive=false pauses the timer AND freezes time/delta. Flipping back to
-- true resumes counting from the frozen values (off-interval does not
-- accumulate). For a cold restart, call reset() alongside the flip.
function M.useAnimation(opts)
    opts = opts or {}
    local interval = opts.interval or 80
    local isActive = opts.isActive
    if isActive == nil then isActive = true end

    -- Persistent mutable snapshot. Using useRef (not useState) because the
    -- interval callback writes here *and* calls setTick to request a
    -- rerender; we don't want two setState writes per tick.
    local state = M.useRef {
        frame     = 0,
        time      = 0,
        delta     = 0,
        last_tick = nil,  -- scheduler.now() when last tick fired; nil = none yet
    }

    -- Drives rerenders. The interval callback bumps this via setTick.
    local _tick, setTick = M.useState(0)
    local function bump() setTick(function(v) return (v + 1) % 1e9 end) end

    -- Stable reset closure, installed once on mount.
    local reset_ref = M.useRef(nil)
    if reset_ref.current == nil then
        reset_ref.current = function()
            state.current.frame     = 0
            state.current.time      = 0
            state.current.delta     = 0
            state.current.last_tick = nil
            bump()
        end
    end

    -- Install / tear down the interval based on isActive + interval.
    -- Deps = {interval, isActive}: toggling either restarts the timer.
    M.useEffect(function()
        if not isActive then return end
        -- Seed last_tick on (re)start so the first delta equals the interval
        -- rather than the potentially-large gap since last paint.
        state.current.last_tick = scheduler.now()
        local id = scheduler.setInterval(function()
            local now = scheduler.now()
            local prev = state.current.last_tick or (now - interval)
            local dt = now - prev
            if dt < 0 then dt = interval end  -- defensive: clock went backwards
            state.current.frame     = state.current.frame + 1
            state.current.delta     = dt
            state.current.time      = state.current.time + dt
            state.current.last_tick = now
            bump()
        end, interval)
        return function() scheduler.clearTimer(id) end
    end, { interval, isActive })

    return {
        frame = state.current.frame,
        time  = state.current.time,
        delta = state.current.delta,
        reset = reset_ref.current,
    }
end

-- ---------------------------------------------------------------------------
-- useInput(handler) — subscribe to keyboard events for the lifetime of the
-- component. Handler signature: handler(input_str, key_table).
--
-- Stage 3: broadcasts to all subscribers (no focus yet — see Stage 5).

local input_mod -- lazy-loaded to avoid a static require cycle

function M.useInput(fn)
    if not input_mod then input_mod = require "tui.internal.input" end
    local ref = useLatestRef(fn)
    assert(current, "useInput called outside of a component render")
    local inst = current
    M.useEffect(function()
        return input_mod.subscribe(wrap_handler_for_boundary(inst, function(input, key)
            ref.current(input, key)
        end))
    end, {})
end

-- ---------------------------------------------------------------------------
-- usePaste(handler) — subscribe to bracketed-paste events for the lifetime of
-- the component. Handler signature: handler(text: string).
-- Ink API parity: called once with the complete pasted text after the terminal
-- sends the closing ESC[201~ marker.

function M.usePaste(fn)
    if not input_mod then input_mod = require "tui.internal.input" end
    local ref = useLatestRef(fn)
    assert(current, "usePaste called outside of a component render")
    local inst = current
    M.useEffect(function()
        return input_mod.subscribe_paste(wrap_handler_for_boundary(inst, function(text)
            ref.current(text)
        end))
    end, {})
end

-- ---------------------------------------------------------------------------
-- useFocus(opts) — register this component into the focus chain.
--
-- opts = {
--   autoFocus = bool?,       -- explicitly take focus on mount / re-subscribe
--   id        = string?,     -- manual id; generated otherwise
--   isActive  = bool?,       -- default true. When false, entry is registered
--                            --   but skipped by Tab navigation and never
--                            --   auto-focuses.
--   on_input  = fn?,         -- called when a key is delivered to us
-- }
--
-- Hot-update semantics:
--   * id        — changing the explicit id triggers a re-subscribe (old
--                 entry unmounts, new entry appended at the tail). autoFocus
--                 is re-evaluated against the new entry.
--   * isActive  — hot-updates in place via focus_mod.set_active(); the
--                 entry's position in the Tab order is preserved.
--   * autoFocus — read at each subscribe time only; toggling it alone on
--                 a rerender is a no-op (matches Ink: autoFocus is a mount
--                 intent, not an imperative command — use the returned
--                 focus() instead).
--   * on_input  — always sees latest closure via useLatestRef.
--
-- returns { isFocused : bool, focus : fn }
--
-- Implementation note: subscription happens inside a useEffect whose deps
-- are the sanitized id. Registering on every render would re-append the
-- entry each frame, permanently shifting Tab order.

local focus_mod

function M.useFocus(opts)
    opts = opts or {}
    if not focus_mod then focus_mod = require "tui.internal.focus" end

    local isFocused, setFocused = M.useState(false)
    local onInputRef = useLatestRef(opts.on_input)

    -- A dedicated slot holds the live focus entry so the returned `focus()`
    -- closure can reach it even though subscribe happens in a later effect.
    local inst, i = require_instance("focus")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "focus", entry = nil }
        inst.hooks[i] = slot
    end

    local auto     = opts.autoFocus
    local id       = opts.id
    local isActive = opts.isActive

    -- Capture the owning instance once so the focus on_input wrapper can
    -- route handler errors through the same nearest_boundary path useInput
    -- uses. The instance's .nearest_boundary is refreshed each render.
    local inst_outer = inst

    -- Effect 1: (re-)subscribe when id changes. deps={id} — a nil id stays
    -- stable across rerenders (shallow-equal), so auto-id entries never
    -- remount; a string id change triggers cleanup + new subscribe.
    M.useEffect(function()
        local entry, unsub = focus_mod.subscribe {
            id        = id,
            autoFocus = auto,
            isActive  = isActive,
            on_change = function(b) setFocused(b) end,
            on_input  = wrap_handler_for_boundary(inst_outer, function(input, key)
                if onInputRef.current then onInputRef.current(input, key) end
            end),
        }
        slot.entry = entry
        return function()
            slot.entry = nil
            unsub()
        end
    end, { id })

    -- Effect 2: hot-update isActive when it changes. No-op on first mount
    -- (subscribe already saw the initial value) but cheap to run.
    M.useEffect(function()
        if slot.entry then
            focus_mod.set_active(slot.entry.id, isActive)
        end
    end, { isActive })

    return {
        isFocused = isFocused,
        focus     = function()
            if slot.entry then focus_mod.focus(slot.entry.id) end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- useErrorBoundary() -> { caught_error, reset }
-- Read the nearest ancestor ErrorBoundary's current state from inside a
-- descendant component. Useful for rendering custom recovery UI without
-- declaring a fallback function: e.g. a toast next to normal content that
-- offers a retry button.
--
-- Semantics:
--   * caught_error : the error value the boundary currently holds, or nil
--                    if it hasn't tripped. This is a snapshot at render
--                    time; the component won't automatically re-render
--                    when caught_error changes unless another mechanism
--                    (the boundary itself flipping, a parent rerender)
--                    forces a pass. In practice that's fine because the
--                    boundary's fallback branch replaces this subtree
--                    when tripped, so callers read `caught_error` mainly
--                    inside that fallback's own children.
--   * reset        : stable closure clearing the boundary's caught_error
--                    and requesting a redraw. No-op if no ancestor
--                    boundary exists (we still return a function so
--                    callers don't need to nil-check).
--
-- Returns nil `caught_error` and a no-op `reset` when there is no ancestor
-- ErrorBoundary. Consumers that need to detect that case can check
-- `result.boundary ~= nil`.
local NOOP = function() end

function M.useErrorBoundary()
    assert(current, "useErrorBoundary called outside of a component render")
    local boundary = current.nearest_boundary
    if not boundary then
        return { caught_error = nil, reset = NOOP, boundary = nil }
    end
    return {
        caught_error = boundary.caught_error,
        reset        = ensure_reconciler()._get_boundary_reset(boundary),
        boundary     = boundary,
    }
end

-- ---------------------------------------------------------------------------
-- useFocusManager() — return the focus system's control surface.
--
-- Methods are direct pass-throughs to tui.focus; there is no component-
-- level state attached (hence no hook slot), but we still require the
-- call to happen during render so usage is consistent with other hooks.

function M.useFocusManager()
    assert(current, "useFocusManager called outside of a component render")
    if not focus_mod then focus_mod = require "tui.internal.focus" end
    return {
        enableFocus   = focus_mod.enable,
        disableFocus  = focus_mod.disable,
        focus         = focus_mod.focus,
        focusNext     = focus_mod.focus_next,
        focusPrevious = focus_mod.focus_prev,
    }
end

-- ---------------------------------------------------------------------------
-- useWindowSize() -> { cols, rows }
-- Returns the current terminal size. Re-renders when the terminal is resized.

local resize_mod

function M.useWindowSize()
    if not resize_mod then resize_mod = require "tui.internal.resize" end
    local w0, h0 = resize_mod.current()
    local size, setSize = M.useState({ cols = w0 or 80, rows = h0 or 24 })
    M.useEffect(function()
        -- Seed initial size in case it wasn't known when useState ran.
        local cw, ch = resize_mod.current()
        if cw and ch and (cw ~= size.cols or ch ~= size.rows) then
            setSize({ cols = cw, rows = ch })
        end
        return resize_mod.subscribe(function(w, h)
            setSize({ cols = w, rows = h })
        end)
    end, {})
    return size
end

-- ---------------------------------------------------------------------------
-- useApp: exposes a handle with .exit(); provided by reconciler each render.

function M.useApp()
    assert(current, "useApp called outside of a component render")
    assert(current.app, "no app handle available on instance")
    return current.app
end

-- ---------------------------------------------------------------------------
-- useStdout() -> { write = fn(s) }
-- Returns a handle for writing directly to the terminal's output stream.
-- Intended for use inside effects or event handlers, not during render.

local _terminal_write
local _terminal_caps

function M._set_terminal_write(fn)
    _terminal_write = fn
end

function M._set_terminal_caps(caps)
    _terminal_caps = caps
end

function M.useStdout()
    assert(current, "useStdout called outside of a component render")
    return {
        write = function(s)
            if _terminal_write then
                _terminal_write(s)
            end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- useStderr() -> { write = fn(s) }
-- Returns a handle for writing to stderr (diagnostics, debug output, etc.).

function M.useStderr()
    assert(current, "useStderr called outside of a component render")
    return {
        write = function(s) io.stderr:write(s) end,
    }
end

-- ---------------------------------------------------------------------------
-- useMeasure() -> ref, { w, h }
--
-- Lets a component read the post-layout size (in cells) of one of its host
-- (Box / Text) elements.  Usage:
--
--   local measureRef, size = tui.useMeasure()
--   return Box { ref = measureRef, ... }
--   -- size.w / size.h are the Yoga-allocated dims; 0 on the first frame.
--
-- After each layout pass the framework calls `ref._measure(w, h)`.  When the
-- dimensions differ from the previous frame, setSize is called, the component
-- is marked dirty and re-renders with accurate dimensions on the next frame.
-- Multiple `useMeasure` calls in the same component are independent: each
-- call gets its own ref/setSize pair.

function M.useMeasure()
    assert(current, "useMeasure called outside of a component render")
    local size, setSize = M.useState({ w = 0, h = 0 })
    local ref = M.useRef(nil)
    -- Attach the update callback to the ref so the post-layout pass can call
    -- it without re-allocating a closure on every render (ref is stable).
    ref._measure = function(w, h)
        if size.w ~= w or size.h ~= h then
            setSize({ w = w, h = h })
        end
    end
    return ref, size
end

-- ---------------------------------------------------------------------------
-- useTerminalFocus() -> { focused: bool }
--
-- Subscribes to DEC 1004 terminal focus/blur events for the component's
-- lifetime. Returns a state table with a single `focused` boolean field.
-- Assumes focused = true on mount (the terminal window is usually in
-- focus when the app starts).
--
-- Note: requires DEC 1004 to be enabled by the render loop (tui.render
-- enables it automatically alongside bracketed-paste).

local _terminal_focus_input_mod

function M.useTerminalFocus()
    if not _terminal_focus_input_mod then
        _terminal_focus_input_mod = require "tui.internal.input"
    end
    assert(current, "useTerminalFocus called outside of a component render")
    local state, setState = M.useState({ focused = true })
    M.useEffect(function()
        return _terminal_focus_input_mod.subscribe_focus(function(event_name)
            setState({ focused = event_name == "focus_in" })
        end)
    end, {})
    return state
end

-- ---------------------------------------------------------------------------
-- useTerminalTitle(title)
--
-- Sets the terminal window/tab title (OSC 0) for the component's lifetime.
-- Title is updated whenever `title` changes. On unmount the title is cleared
-- to an empty string so the terminal reverts to its default.

local _ansi_mod_for_title

function M.useTerminalTitle(title)
    assert(current, "useTerminalTitle called outside of a component render")
    if not _ansi_mod_for_title then
        _ansi_mod_for_title = require "tui.internal.ansi"
    end
    M.useEffect(function()
        if _terminal_write then
            _terminal_write(_ansi_mod_for_title.setTitle(title or "", _terminal_caps))
        end
        return function()
            if _terminal_write then
                _terminal_write(_ansi_mod_for_title.setTitle("", _terminal_caps))
            end
        end
    end, { title })
end

--- useMouse(fn)
-- Registers a mouse-event handler for the lifetime of the component.
-- `fn(event)` is called with each mouse event:
--   { name="mouse", type, button, x, y, scroll, shift, meta, ctrl }
-- where:
--   type   = "down" | "up" | "move" | "scroll"
--   button = 1 (left) | 2 (middle) | 3 (right) | nil (scroll/move)
--   scroll = 1 (up) | -1 (down) | nil
--   shift/meta/ctrl = boolean modifier flags
function M.useMouse(fn)
    assert(current, "useMouse called outside of a component render")
    M.useEffect(function()
        if not input_mod then input_mod = require "tui.internal.input" end
        local unsub   = input_mod.subscribe_mouse(function(ev) fn(ev) end)
        local release = input_mod.request_mouse_level(2)  -- drag level
        return function() unsub(); release() end
    end, {})
end

-- useClipboard() → { write = fn(text), read = fn() → string|nil }
--
-- write(text) copies text to the clipboard via the same priority chain used
-- by the framework (OSC 52 → wl-copy → xclip → xsel → pbcopy).
-- read()      reads the clipboard via xclip / pbcopy / xsel -o / wl-paste.
--             Returns nil if no tool is available or the clipboard is empty.
--
-- Unlike clipboard.copy() which is called at the framework level, the hook
-- exposes clipboard access directly to components.
function M.useClipboard()
    assert(current, "useClipboard called outside of a component render")
    local clipboard_mod = require "tui.internal.clipboard"

    local handle = M.useMemo(function()
        return {
            write = function(text) clipboard_mod.copy(text) end,
            read  = function() return clipboard_mod.read() end,
        }
    end, {})

    return handle
end

return M
