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

-- Called after the element tree has been committed, so effects observe the
-- latest rendered output.
function M._flush_effects(instance)
    for _, fx in ipairs(instance.pending_fx or {}) do
        local slot = fx.slot
        -- Deps check: {} = mount-once; nil = every render.
        local should_run
        if fx.deps == nil then
            should_run = true
        else
            -- deps=={} => run once; reuse slot.ran flag.
            should_run = not slot.ran
        end
        if should_run then
            if slot.cleanup then slot.cleanup() end
            slot.cleanup = fx.fn() or nil
            slot.ran = true
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
-- Timer sugar (built on top of useEffect for cleanup)

function M.useInterval(fn, ms)
    M.useEffect(function()
        local id = scheduler.setInterval(fn, ms)
        return function() scheduler.clearTimer(id) end
    end, {})
end

function M.useTimeout(fn, ms)
    M.useEffect(function()
        local id = scheduler.setTimeout(fn, ms)
        return function() scheduler.clearTimer(id) end
    end, {})
end

-- ---------------------------------------------------------------------------
-- useApp: exposes a handle with .exit(); provided by reconciler each render.

function M.useApp()
    assert(current, "useApp called outside of a component render")
    assert(current.app, "no app handle available on instance")
    return current.app
end

return M
