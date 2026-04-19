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

-- -- fatal error protocol ------------------------------------------------------
--
-- Some errors (duplicate focus id, duplicate reconciler key, internal
-- invariant violations) are programming bugs that an ErrorBoundary should
-- NOT paper over — swallowing them would mask the bug and produce misleading
-- fallback UI for the rest of the session. We tag such errors with a
-- "[tui:fatal] " prefix so the Boundary pcall can recognize and rethrow them.
--
-- Regular user errors (throw inside a component's render, etc.) have no
-- prefix and are caught normally.

local <const> FATAL_PREFIX = "[tui:fatal] "

function M.fatal(msg)
    error(FATAL_PREFIX .. tostring(msg), 0)
end

function M.is_fatal(err)
    return type(err) == "string" and err:sub(1, #FATAL_PREFIX) == FATAL_PREFIX
end

-- ---------------------------------------------------------------------------
-- Instance registry: path-string -> instance

local function make_state()
    return {
        instances      = {},   -- path -> instance
        seen           = {},   -- path -> true (for this render pass)
        app            = nil,  -- app handle injected by tui.render
        boundary_stack = {},   -- ancestor ErrorBoundary instances, innermost last
        context_stack  = {},   -- ancestor Provider entries { context=ctx, value=v }
        _key_warned    = {},   -- parent_path -> true, reset each render pass
                               -- (dev_mode missing-key warning dedup)
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

local function is_error_boundary(e)
    return type(e) == "table" and e.kind == "error_boundary"
end

local function is_provider(e)
    return type(e) == "table" and e.kind == "provider"
end

-- Dev-mode helper: warn once per (parent_path, render pass) if a list of
-- element children lacks keys. Mirrors the React DevTools heuristic:
--
--   * only lists with three-or-more *element* children are candidates
--     (static two-child compositions like `Box { A, B }` are almost never
--     the site of keying bugs; DevTools/Ink only warn on larger lists,
--     which in practice are iteration-built and where reuse correctness
--     actually matters)
--   * text (string) children never trigger
--   * if any element child has key == nil, warn — identifies the whole list
--
-- The warning is deduped per parent path within a single render pass via
-- state._key_warned (cleared at the top of M.render).
local function dev_check_keys(state, parent_path, children)
    if not hooks._is_dev_mode() then return end
    if state._key_warned[parent_path] then return end
    if type(children) ~= "table" or #children < 3 then return end
    local elem_count = 0
    local missing = false
    for _, c in ipairs(children) do
        if type(c) == "table" then
            elem_count = elem_count + 1
            if c.key == nil then missing = true end
        end
    end
    if elem_count < 3 or not missing then return end
    state._key_warned[parent_path] = true
    hooks._warn("children of '" .. parent_path ..
        "' should each have a unique `key` prop; missing keys can cause " ..
        "incorrect reuse across renders")
end

-- Compute the path for the i-th child under `parent_path`. If the child has
-- an `element.key`, it gets its own namespace `parent/#<key>`; otherwise the
-- child uses its positional index `parent/<i>`. The two namespaces do not
-- collide (the `#` prefix is never produced by numeric i).
--
-- `seen_keys` is a per-parent table tracking keys already used in this loop;
-- duplicate keys raise a render-time error with the parent path for context.
local function child_path_for(parent_path, i, child, seen_keys)
    local ck = type(child) == "table" and child.key
    if ck ~= nil then
        local ks = tostring(ck)
        if seen_keys[ks] then
            M.fatal("reconciler: duplicate key '" .. ks ..
                    "' in children of '" .. parent_path .. "'")
        end
        seen_keys[ks] = true
        return parent_path .. "/#" .. ks
    end
    return parent_path .. "/" .. tostring(i)
end

-- ---------------------------------------------------------------------------
-- Walk and expand. Returns a fresh host element tree (function nodes replaced
-- by whatever they rendered).
--
-- `path` uniquely identifies a node slot; we use a string built from indices.

-- Forward declaration so Boundary's expand branch can invoke the fallback
-- renderer both on caught errors and on sticky replays.
local render_boundary_fallback

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
        -- Track nearest ancestor ErrorBoundary for post-commit error routing
        -- (useEffect body/cleanup throws, useInput handler throws). Refreshed
        -- every render pass so the mapping stays correct when components
        -- move across the tree.
        inst.nearest_boundary = state.boundary_stack[#state.boundary_stack]

        -- Record which Lua function is *this* component's render body so
        -- hooks can detect "hook called from a plain function nested under
        -- a component" (see detect_plain_function_hook in tui/hooks.lua).
        inst._component_fn = fn

        hooks._begin_render(inst)
        -- Clear dirty BEFORE calling fn. If fn (or a mount effect queued
        -- below) calls a setter, inst.dirty flips back to true and the
        -- outer driver (main loop / harness stabilization) can detect
        -- that another render pass is needed.
        inst.dirty = false
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

    if is_error_boundary(element) then
        -- ErrorBoundary: wrap the children expand loop in pcall. Any error
        -- raised by a descendant (component fn throwing, or malformed host
        -- element) is caught here; we swap in `fallback` for the rest of
        -- this render pass. Once tripped, `inst.caught_error` is sticky —
        -- the boundary keeps showing fallback across frames until the
        -- caller resets it (Ink/React semantics). Post-commit errors
        -- (useEffect body/cleanup, useInput handler) route through
        -- `hooks._flush_effects` which sets caught_error directly on the
        -- nearest_boundary inst and requests a redraw.
        state.seen[path] = true
        local inst = state.instances[path]
        if not inst then
            inst = { kind = "error_boundary", caught_error = nil }
            state.instances[path] = inst
        end
        -- Clear any dirty flag set by a descendant effect-error routing so
        -- the harness stabilization loop doesn't spin. We'll consume it on
        -- this pass by rendering fallback (or revisit if children throw).
        inst.dirty = false

        -- Already tripped? Skip children entirely and render fallback.
        if inst.caught_error ~= nil then
            return render_boundary_fallback(state, element, path, inst.caught_error)
        end

        -- Push onto the ancestor stack so descendants' component instances
        -- can record `inst.nearest_boundary = this`.
        state.boundary_stack[#state.boundary_stack + 1] = inst

        local out = { kind = "box", props = {}, children = {} }
        local ok, err = pcall(function()
            dev_check_keys(state, path, element.children)
            local seen_keys = {}
            for i, c in ipairs(element.children or {}) do
                local cp = child_path_for(path, i, c, seen_keys)
                local expanded = expand(state, c, cp)
                if expanded ~= nil then
                    out.children[#out.children + 1] = expanded
                end
            end
        end)

        -- Always pop, even on error, to keep the stack balanced.
        state.boundary_stack[#state.boundary_stack] = nil

        if ok then
            return out
        end

        -- Fatal errors (duplicate key/id, internal asserts) must not be
        -- papered over by a fallback — rethrow so the framework's top-level
        -- pcall in produce_tree turns them into a visible error screen.
        if M.is_fatal(err) then error(err, 0) end

        inst.caught_error = err
        return render_boundary_fallback(state, element, path, err)
    end

    if is_provider(element) then
        -- Provider is a structural wrapper: no instance, no hooks, no effects.
        -- Push its (context, value) onto state.context_stack for the duration
        -- of the children expand. Wrap in pcall to guarantee stack balance on
        -- any exception; rethrow afterwards so an ancestor ErrorBoundary still
        -- sees the error and can render its fallback.
        local ctx_stack = state.context_stack
        ctx_stack[#ctx_stack + 1] = { context = element.context, value = element.value }
        local out = { kind = "box", props = {}, children = {} }
        local ok, err = pcall(function()
            dev_check_keys(state, path, element.children)
            local seen_keys = {}
            for i, c in ipairs(element.children or {}) do
                local cp = child_path_for(path, i, c, seen_keys)
                local expanded = expand(state, c, cp)
                if expanded ~= nil then
                    out.children[#out.children + 1] = expanded
                end
            end
        end)
        ctx_stack[#ctx_stack] = nil
        if not ok then error(err, 0) end
        return out
    end

    if is_host_element(element) then
        -- Recurse into children.
        local out = { kind = element.kind, props = element.props, children = {} }
        if element.kind == "text" then
            -- Text children are strings; copy verbatim + keep .text field.
            for i, c in ipairs(element.children or {}) do out.children[i] = c end
            out.text = element.text
            -- Propagate cursor metadata fields used by builtin components.
            -- TextInput sets these during render based on focus state.
            out._cursor_offset = element._cursor_offset
            out._cursor_focused = element._cursor_focused
        else
            dev_check_keys(state, path, element.children)
            local seen_keys = {}
            for i, c in ipairs(element.children or {}) do
                local cp = child_path_for(path, i, c, seen_keys)
                local expanded = expand(state, c, cp)
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

-- Return (creating if needed) a stable `reset` closure for a Boundary inst.
-- The closure must be reference-stable across frames because React-style
-- consumers ($.reset === prev.reset) often use it as a dep or memoization
-- key. We cache on the inst the first time anyone asks.
local scheduler_mod
local function get_boundary_reset(inst)
    if inst._reset then return inst._reset end
    inst._reset = function()
        if inst.caught_error == nil then return end
        inst.caught_error = nil
        inst.dirty = true
        if not scheduler_mod then scheduler_mod = require "tui.scheduler" end
        scheduler_mod.requestRedraw()
    end
    return inst._reset
end

-- Expose the reset getter so hooks.useErrorBoundary can lazy-create the
-- same closure that fallback(err, reset) would see, even before the
-- boundary has tripped.
M._get_boundary_reset = get_boundary_reset

-- The state actively being walked by expand() right now, or nil outside a
-- render pass. hooks.useContext reads this via M._lookup_context to resolve
-- the nearest ancestor Provider.
M._current_state = nil

function M._lookup_context(ctx)
    local state = M._current_state
    if not state then
        error("useContext: called outside of a render pass", 3)
    end
    local stack = state.context_stack
    for i = #stack, 1, -1 do
        if stack[i].context == ctx then return stack[i].value end
    end
    return ctx._default
end

-- Render a boundary's fallback subtree. Always protected by its own pcall
-- so fallback crashes don't escape the boundary (the whole point). Fatal
-- errors inside fallback still propagate.
--
-- Fallback shapes handled here:
--   * nil      -> empty box
--   * function -> called as fallback(err, reset); return value treated as
--                 an element (expanded recursively). Throwing is caught;
--                 fatal prefix rethrows.
--   * element  -> expanded directly
function render_boundary_fallback(state, element, path, err)
    local fb = element.fallback
    if fb == nil then
        return { kind = "box", props = {}, children = {} }
    end

    local inst = state.instances[path]
    local resolved
    if type(fb) == "function" then
        local reset = get_boundary_reset(inst)
        local call_ok, call_ret = pcall(fb, err, reset)
        if not call_ok then
            if M.is_fatal(call_ret) then error(call_ret, 0) end
            return { kind = "box", props = {}, children = {} }
        end
        resolved = call_ret
    else
        resolved = fb
    end

    if resolved == nil then
        return { kind = "box", props = {}, children = {} }
    end

    -- Make the boundary visible to useErrorBoundary() calls inside the
    -- fallback subtree. We push the *same* inst on boundary_stack so its
    -- descendants capture it as nearest_boundary. Render-time errors in
    -- the fallback subtree are still caught by the local pcall below;
    -- post-commit errors (effects / input) from fallback descendants will
    -- route back to this boundary's caught_error — harmless because it's
    -- already tripped and sticky, so they just refresh the err value.
    state.boundary_stack[#state.boundary_stack + 1] = inst

    local fb_ok, fb_tree = pcall(expand, state, resolved, path .. "/fallback")

    state.boundary_stack[#state.boundary_stack] = nil

    if not fb_ok then
        if M.is_fatal(fb_tree) then error(fb_tree, 0) end
        return { kind = "box", props = {}, children = {} }
    end
    if fb_tree == nil then
        return { kind = "box", props = {}, children = {} }
    end
    return fb_tree
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
    state.context_stack = state.context_stack or {}
    state._key_warned = {}

    -- Publish the state so hooks.useContext can look up Providers. Wrap in
    -- pcall so _current_state is always cleared even if expand() throws.
    M._current_state = state
    local ok, tree_or_err = pcall(expand, state, root, "")
    M._current_state = nil
    if not ok then error(tree_or_err, 0) end
    local tree = tree_or_err

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
