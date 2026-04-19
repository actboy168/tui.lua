-- tui/layout.lua — build Yoga tree from element tree and compute layout.
--
-- Stage 4:
--   * Box with optional border / padding / width / height
--   * Text leaf: intrinsic width = display width via wcwidth; height accounts
--     for soft-wrap when wrap != "nowrap" (handled in tui/text.lua).
--
-- Stage N: Yoga tree reuse + single-pass C property setting.
--   * node_set_box_props / node_set_text_props: C iterates props directly,
--     eliminating the Lua loop and the intermediate style table.
--   * Cross-frame reconcile: Yoga nodes are pooled and reused.  Yoga's
--     idempotent style setters preserve the internal layout cache for
--     subtrees whose structure and props haven't changed.

local yoga     = require "yoga"
local tui_core = require "tui_core"
local text_mod = require "tui.text"

local wcwidth = tui_core.wcwidth

local M = {}

-- Cross-frame state: element tree from previous frame (with yoga_node attached)
-- and a pool of detached, reset Yoga nodes ready for reuse.
local _prev_element = nil
local _pool = {}

local function pool_acquire()
    -- Pool nodes are already reset by release_subtree before insertion.
    -- yoga.node_new() returns a fresh node with default style.
    return table.remove(_pool) or yoga.node_new()
end

-- Release an element subtree to the pool.
-- PRECONDITION: element.yoga_node has no parent (owner_ == nullptr) when called.
-- For box nodes, detaches their Yoga children first so they can be released too.
local function release_subtree(element)
    if not element.yoga_node then return end
    if element.kind == "box" then
        yoga.node_remove_all_children(element.yoga_node)
        for _, child in ipairs(element.children or {}) do
            release_subtree(child)
        end
    end
    yoga.node_reset(element.yoga_node)
    _pool[#_pool + 1] = element.yoga_node
    element.yoga_node = nil
end

-- Reconcile element against prev (previous-frame element with yoga_node attached).
-- Returns the yoga_node to use for element.
-- When a prev child was replaced (different kind), it stays attached to its Yoga
-- parent until the parent calls node_remove_all_children, which sets owner_=nullptr.
-- Only THEN is release_subtree called, satisfying the precondition above.
local function reconcile(element, prev)
    local node
    if prev and prev.kind == element.kind then
        -- Reuse: take the node and clear it from prev so the release loop skips it.
        node = prev.yoga_node
        prev.yoga_node = nil
    else
        node = pool_acquire()
    end
    element.yoga_node = node

    if element.kind == "box" then
        -- Single C pass: iterate props array directly, no intermediate Lua table.
        yoga.node_set_box_props(node, element.props or {})

        local children      = element.children or {}
        local prev_children = (prev and prev.kind == "box" and prev.children) or {}

        -- Reconcile all children first (builds new_nodes; replaced prev nodes
        -- keep their yoga_node until we detach them below).
        local new_nodes = {}
        for i, child in ipairs(children) do
            new_nodes[i] = reconcile(child, prev_children[i])
        end

        -- Check whether the Yoga child list needs to change.
        -- If unchanged, no structural C calls → parent stays clean → Yoga skips
        -- the entire subtree when layout props are also unchanged.
        local needs_rewire = yoga.node_child_count(node) ~= #children
        if not needs_rewire then
            for i, cn in ipairs(new_nodes) do
                if yoga.node_get_child(node, i - 1) ~= cn then
                    needs_rewire = true; break
                end
            end
        end

        if needs_rewire then
            -- Detach ALL current Yoga children (sets their owner_ to nullptr).
            yoga.node_remove_all_children(node)
            -- Now safe to release replaced / excess prev children.
            for i = 1, math.max(#children, #prev_children) do
                local pc = prev_children[i]
                if pc and pc.yoga_node then
                    release_subtree(pc)
                end
            end
            -- Re-wire the new children in order.
            for i, cn in ipairs(new_nodes) do
                yoga.node_insert_child(node, cn, i - 1)
            end
        end

    elseif element.kind == "text" then
        local iw    = wcwidth.string_width(element.text or "")
        local props = element.props or {}
        yoga.node_set_text_props(node, props, iw, 1)
        local wrap = props.wrap; if wrap == nil then wrap = "wrap" end
        if wrap ~= "nowrap" then element._wrap = true end
    end

    return node
end

-- Recursively create yoga nodes; returns the root node.
-- Uses pool_acquire() so nodes released by M.reset() can be reused.
-- Used for the first frame (no _prev_element yet) and for intrinsic_size.
-- Also attaches `element.yoga_node` on every element for later readback.
local function build(element, parent_node)
    local node = pool_acquire()
    element.yoga_node = node
    if parent_node then
        yoga.node_insert_child(parent_node, node,
            yoga.node_child_count(parent_node))
    end

    if element.kind == "box" then
        yoga.node_set_box_props(node, element.props or {})
        for _, child in ipairs(element.children or {}) do
            build(child, node)
        end
    elseif element.kind == "text" then
        local text  = element.text or ""
        local iw    = wcwidth.string_width(text)
        local props = element.props or {}
        local wrap  = props.wrap
        if wrap == nil then wrap = "wrap" end
        yoga.node_set_text_props(node, props, iw, 1)
        if wrap ~= "nowrap" then
            element._wrap = true
        end
    end

    return node
end

-- Recursively read computed layout back and stash it on each element.
-- Returns absolute x/y by accumulating parent offsets (yoga only gives local).
-- `phase` == "measure" : first pass, record rect on everything and collect
--                         wrap-capable text nodes that need re-measuring.
-- `phase` == "final"   : second pass, rect/lines final.
local function readback(element, ox, oy, phase, wrap_nodes)
    local lx, ly, lw, lh = yoga.node_get(element.yoga_node)
    local ax, ay = ox + lx, oy + ly
    element.rect = { x = ax, y = ay, w = lw, h = lh }
    if element.kind == "box" then
        for _, child in ipairs(element.children or {}) do
            readback(child, ax, ay, phase, wrap_nodes)
        end
    elseif element.kind == "text" then
        if element._wrap then
            -- Produce line array bounded by the current rect width.
            local lines = text_mod.wrap(element.text or "", lw)
            element.lines = lines
            if phase == "measure" and wrap_nodes and #lines > 1 then
                wrap_nodes[#wrap_nodes + 1] = { node = element, lines = lines }
            end
        end
    end
end

-- Public entry: build/reconcile → calc → readback.
function M.compute(element)
    local root
    if _prev_element then
        root = reconcile(element, _prev_element)
        -- If root kind changed, _prev_element.yoga_node was not claimed by
        -- reconcile (it didn't match).  Root has no parent so it's safe to
        -- release directly.
        if _prev_element.yoga_node then
            release_subtree(_prev_element)
        end
    else
        root = build(element, nil)
    end
    _prev_element = element
    yoga.node_calc(root)

    -- Pass 1: measure-only readback to gather text nodes whose wrapped height
    -- differs from the intrinsic height=1 yoga used.
    local wrap_nodes = {}
    readback(element, 0, 0, "measure", wrap_nodes)

    -- Pass 2: if any text wrapped to multiple lines, resize their yoga nodes
    -- and recompute so ancestors see the real height.
    if #wrap_nodes > 0 then
        for _, wn in ipairs(wrap_nodes) do
            yoga.node_set(wn.node.yoga_node, { height = #wn.lines })
        end
        yoga.node_calc(root)
        readback(element, 0, 0, "final", nil)
    end
    return root
end

function M.free(element)
    -- Nodes are now pooled and reused across frames; layout.lua manages their
    -- lifetime via _prev_element.  This function is kept for API compatibility
    -- (init.lua still calls it) but does nothing.
    _ = element
end

-- Compute the minimum intrinsic size (cols, rows) the element tree needs.
-- This is the smallest terminal size at which the layout can render without
-- content being clipped or overlapping. Apps can compare this against
-- useWindowSize() to show a "terminal too small" fallback.
--
-- Implementation: build a fresh Yoga tree, calculate with no constraints
-- (YGUndefined), then read the root node size. Flex-grow children shrink to
-- 0 without constraints, but the non-flex content (padding, border, text)
-- determines the actual minimum. We take the max of the computed size and
-- any explicit minWidth/minHeight on the root.
function M.intrinsic_size(element)
    local root = build(element, nil)
    yoga.node_calc(root)
    local _, _, w, h = yoga.node_get(root)
    yoga.node_free(root)
    element.yoga_node = nil
    return w, h
end

-- Reset all cross-frame state. Call this at session end (e.g., unmount) to
-- ensure the next compute() starts from a clean slate.  M.free() is kept as
-- a no-op so the between-frame calling convention in testing.lua is harmless.
function M.reset()
    if _prev_element then
        release_subtree(_prev_element)
        _prev_element = nil
    end
end

return M
