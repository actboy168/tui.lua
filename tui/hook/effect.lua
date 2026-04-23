-- tui/hook/effect.lua — effect hooks and lifecycle.
--
-- useEffect, _flush_effects, _unmount.

local core = require "tui.hook.core"

local M = {}

-- ---------------------------------------------------------------------------
-- useEffect

function M.useEffect(fn, deps)
    local inst, i = core.require_instance("effect")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "effect", ran = false, cleanup = nil }
        inst.hooks[i] = slot
    end
    -- Queue; _flush_effects will decide whether to actually run.
    inst.pending_fx[#inst.pending_fx + 1] = { slot = slot, fn = fn, deps = deps }
end

-- ---------------------------------------------------------------------------
-- _flush_effects — called after the element tree has been committed, so
-- effects observe the latest rendered output.
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
            should_run = not core.deps_equal(slot.deps, fx.deps)
        end
        if should_run then
            -- Always cleanup the previous effect before running the new one
            -- (S2.11 — React-aligned ordering). Both pcalls advance deps
            -- afterwards regardless of outcome.
            if slot.cleanup then
                local old = slot.cleanup
                slot.cleanup = nil
                local ok, err = xpcall(old, core.wrap_err)
                if not ok then core.route_effect_error(instance, err) end
            end
            local ok, result = xpcall(fx.fn, core.wrap_err)
            if ok then
                slot.cleanup = result or nil
            else
                slot.cleanup = nil
                core.route_effect_error(instance, result)
            end
            slot.deps = fx.deps
            slot.ran  = true
        end
    end
    instance.pending_fx = nil
end

-- ---------------------------------------------------------------------------
-- _unmount — called when an instance is being torn down; run all cleanups.
-- Cleanup errors during unmount are routed through the same boundary
-- mechanism as effect errors so they don't crash the render pass. If the
-- instance has no ancestor boundary, we swallow (rather than rethrow) —
-- unmount typically happens as part of already-in-progress error recovery
-- or harness shutdown, and re-raising at that point is more disruptive
-- than useful. First error wins: subsequent cleanups still run so every
-- slot gets a chance to release its resources.

local reconciler_mod   -- lazy require to avoid init cycle
local function ensure_reconciler()
    reconciler_mod = reconciler_mod or require "tui.internal.reconciler"
    return reconciler_mod
end

function M._unmount(instance)
    for _, slot in ipairs(instance.hooks or {}) do
        if slot and slot.cleanup then
            local fn = slot.cleanup
            slot.cleanup = nil
            local ok, err = xpcall(fn, core.wrap_err)
            if not ok then
                local rec = ensure_reconciler()
                if rec.is_fatal(err) then error(err, 0) end
                local boundary = instance.nearest_boundary
                if boundary and boundary.caught_error == nil then
                    boundary.caught_error = err
                    boundary.dirty = true
                    require("tui.internal.scheduler").requestRedraw()
                end
                -- else: swallow. See function header for rationale.
            end
        end
    end
end

return M
