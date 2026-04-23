-- tui/hook/context.lua — context hooks.
--
-- createContext, useContext.

local core = require "tui.hook.core"

local M = {}

-- ---------------------------------------------------------------------------
-- useContext(ctx) -> value
-- Consumes the nearest ancestor <ctx.Provider value=...> in the element
-- tree. Returns `ctx._default` if no Provider is in scope. The hook slot
-- exists only to keep the cursor position stable across renders — the
-- actual lookup goes through the reconciler's context_stack so Provider
-- changes reflect immediately.
function M.useContext(ctx)
    local inst, i = core.require_instance("context")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "context" }
        inst.hooks[i] = slot
    end
    if type(ctx) ~= "table" or ctx._kind ~= "tui_context" then
        error("useContext: expected a context created by tui.createContext", 2)
    end
    local rec = reconciler_mod or require "tui.internal.reconciler"
    return rec._lookup_context(ctx)
end

-- ---------------------------------------------------------------------------
-- createContext(default_value) -> context object
-- The returned table carries a `Provider` factory: `MyCtx.Provider { value=X, ... }`
-- produces an element of kind "provider" that the reconciler splices into
-- the render tree without creating a component instance.
local element_mod   -- lazy require to avoid init cycle with element.lua
local reconciler_mod

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

return M
