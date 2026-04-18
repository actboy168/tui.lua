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

local scheduler = require "tui.scheduler"

local M = {}

-- ---------------------------------------------------------------------------
-- Current instance (set by reconciler during a render pass)

local current   = nil
local cursor    = 0

function M._begin_render(instance)
    current = instance
    cursor  = 0
    instance.hooks         = instance.hooks         or {}
    instance.pending_fx    = {}
end

function M._end_render()
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
            -- (S2.11 — React-aligned ordering).
            if slot.cleanup then slot.cleanup(); slot.cleanup = nil end
            slot.cleanup = fx.fn() or nil
            slot.deps    = fx.deps
            slot.ran     = true
        end
    end
    instance.pending_fx = nil
end

-- Called when an instance is being torn down; run all cleanups.
function M._unmount(instance)
    for _, slot in ipairs(instance.hooks or {}) do
        if slot and slot.cleanup then
            slot.cleanup()
            slot.cleanup = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Internal helpers

local function require_instance()
    assert(current, "hook called outside of a component render")
    cursor = cursor + 1
    return current, cursor
end

-- ---------------------------------------------------------------------------
-- useState

function M.useState(initial)
    local inst, i = require_instance()
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "state", value = initial }
        inst.hooks[i] = slot
        -- Setter is stable across renders (captures slot + inst).
        slot.setter = function(v)
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
    local inst, i = require_instance()
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "effect", ran = false, cleanup = nil }
        inst.hooks[i] = slot
    end
    -- Queue; _flush_effects will decide whether to actually run.
    inst.pending_fx[#inst.pending_fx + 1] = { slot = slot, fn = fn, deps = deps }
end

-- ---------------------------------------------------------------------------
-- Internal: useLatestRef(value)
-- Stores `value` in a hook slot and returns a stable ref table whose .current
-- is updated every render. Used by useInterval/useTimeout/useInput to avoid
-- stale closures without forcing the user to specify deps.
local function useLatestRef(value)
    local inst, i = require_instance()
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
-- useInput(handler) — subscribe to keyboard events for the lifetime of the
-- component. Handler signature: handler(input_str, key_table).
--
-- Stage 3: broadcasts to all subscribers (no focus yet — see Stage 5).

local input_mod -- lazy-loaded to avoid a static require cycle

function M.useInput(fn)
    if not input_mod then input_mod = require "tui.input" end
    local ref = useLatestRef(fn)
    M.useEffect(function()
        return input_mod.subscribe(function(input, key)
            ref.current(input, key)
        end)
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
    if not focus_mod then focus_mod = require "tui.focus" end

    local isFocused, setFocused = M.useState(false)
    local onInputRef = useLatestRef(opts.on_input)

    -- A dedicated slot holds the live focus entry so the returned `focus()`
    -- closure can reach it even though subscribe happens in a later effect.
    local inst, i = require_instance()
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "focus", entry = nil }
        inst.hooks[i] = slot
    end

    local auto     = opts.autoFocus
    local id       = opts.id
    local isActive = opts.isActive

    -- Effect 1: (re-)subscribe when id changes. deps={id} — a nil id stays
    -- stable across rerenders (shallow-equal), so auto-id entries never
    -- remount; a string id change triggers cleanup + new subscribe.
    M.useEffect(function()
        local entry, unsub = focus_mod.subscribe {
            id        = id,
            autoFocus = auto,
            isActive  = isActive,
            on_change = function(b) setFocused(b) end,
            on_input  = function(input, key)
                if onInputRef.current then onInputRef.current(input, key) end
            end,
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
-- useFocusManager() — return the focus system's control surface.
--
-- Methods are direct pass-throughs to tui.focus; there is no component-
-- level state attached (hence no hook slot), but we still require the
-- call to happen during render so usage is consistent with other hooks.

function M.useFocusManager()
    assert(current, "useFocusManager called outside of a component render")
    if not focus_mod then focus_mod = require "tui.focus" end
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
    if not resize_mod then resize_mod = require "tui.resize" end
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

return M
