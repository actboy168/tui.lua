-- tui/reconciler.lua — expand function components into host element trees.
--
-- Stage 2 strategy:
--   * Each component-node (identified by an element whose `fn` is a Lua function
--     or whose `kind == "component"`) has an instance keyed by its path in the
--     tree (positional matching — no `key` prop yet, see Stage 5 S2.2).
--   * On each render pass we walk the user's element tree top-down; whenever
--     we see a function, we call it with `props` inside a hook-cursor scope.
--   * After the walk, any instance whose path was not visited is unmounted
--     (effect cleanups run).
--
-- Note: the public API lets users pass either:
--   * a function component to tui.render(MyApp)
--   * a host element tree to tui.render(Box{...})
-- A function is wrapped as a 0-prop component instance.

local hooks = require "tui.hooks"

local M = {}

-- ---------------------------------------------------------------------------
-- Instance registry: path-string -> instance

local function make_state()
    return {
        instances   = {},   -- path -> instance
        seen        = {},   -- path -> true (for this render pass)
        app         = nil,  -- app handle injected by tui.render
    }
end

-- ---------------------------------------------------------------------------
-- Detect whether a value is a component (Lua function) vs a host element.

local function is_component_element(e)
    -- Shape the user wrote: Box { MyComponent, ... } — a raw function child.
    if type(e) == "function" then return true end
    -- Or a table element tagged as component (produced by tui.component(fn)).
    if type(e) == "table" and e.kind == "component" then return true end
    return false
end

local function is_host_element(e)
    return type(e) == "table" and (e.kind == "box" or e.kind == "text")
end

-- ---------------------------------------------------------------------------
-- Walk and expand. Returns a fresh host element tree (function nodes replaced
-- by whatever they rendered).
--
-- `path` uniquely identifies a node slot; we use a string built from indices.

local function expand(state, element, path)
    if element == nil or element == false then return nil end
    if type(element) == "string" then return element end  -- passthrough for Text children

    if is_component_element(element) then
        -- Resolve fn + props.
        local fn, props
        if type(element) == "function" then
            fn, props = element, {}
        else
            fn, props = element.fn, element.props or {}
        end

        state.seen[path] = true
        local inst = state.instances[path]
        if not inst or inst.fn ~= fn then
            -- New instance or component identity changed (Stage 2: we just
            -- replace — S2.9 will make this cleaner later).
            if inst then hooks._unmount(inst) end
            inst = { fn = fn, hooks = {}, dirty = true, app = state.app }
            state.instances[path] = inst
        else
            inst.app = state.app
        end

        hooks._begin_render(inst)
        local ok, rendered = pcall(fn, props)
        hooks._end_render()
        if not ok then
            error(rendered, 0)
        end

        -- Recurse: the fn's output may itself contain components.
        local expanded = expand(state, rendered, path .. "/fn")

        -- Queue effects for post-commit.
        state._effects_to_flush[#state._effects_to_flush + 1] = inst
        return expanded
    end

    if is_host_element(element) then
        -- Recurse into children.
        local out = { kind = element.kind, props = element.props, children = {} }
        if element.kind == "text" then
            -- Text children are strings; copy verbatim + keep .text field.
            for i, c in ipairs(element.children or {}) do out.children[i] = c end
            out.text = element.text
        else
            for i, c in ipairs(element.children or {}) do
                local child_path = path .. "/" .. tostring(i)
                local expanded = expand(state, c, child_path)
                if expanded ~= nil then
                    out.children[#out.children + 1] = expanded
                end
            end
        end
        return out
    end

    -- Unknown: drop it.
    return nil
end

-- ---------------------------------------------------------------------------
-- Public API

--- new() -> reconciler state
function M.new()
    return make_state()
end

--- render(state, root_element, app_handle) -> host_element_tree
-- Walks the user's tree, expanding function components into host elements,
-- unmounts any instances that disappeared this pass, and flushes effects.
function M.render(state, root, app_handle)
    state.seen = {}
    state.app  = app_handle
    state._effects_to_flush = {}

    local tree = expand(state, root, "")

    -- Unmount stale instances.
    for path, inst in pairs(state.instances) do
        if not state.seen[path] then
            hooks._unmount(inst)
            state.instances[path] = nil
        end
    end

    -- Run pending effects after commit.
    for _, inst in ipairs(state._effects_to_flush) do
        hooks._flush_effects(inst)
    end
    state._effects_to_flush = nil

    return tree
end

--- shutdown(state): run cleanups on everything.
function M.shutdown(state)
    for path, inst in pairs(state.instances) do
        hooks._unmount(inst)
        state.instances[path] = nil
    end
end

return M
