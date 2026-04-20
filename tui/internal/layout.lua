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
local text_mod = require "tui.internal.text"

local wcwidth = tui_core.wcwidth

local M = {}

-- Cross-frame state: element tree from previous frame (with yoga_node attached)
-- and a pool of detached, reset Yoga nodes ready for reuse.
local _prev_element = nil
local _pool = {}

-- Per-node layout cache: maps yoga_node → {lx, ly, lw, lh, ox, oy, lines}
-- Cleared when a node is released back to the pool.
local _node_layout = {}

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
    _node_layout[element.yoga_node] = nil  -- clear stale cache entry
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
        if wrap ~= "nowrap" then
            element._wrap = true
            element._wrap_mode = wrap
        end
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
            element._wrap_mode = wrap
        end
    end

    return node
end

-- Restore element.rect from the cache (using parent's absolute position), then
-- recurse into children.  Used by readback's fast path when yoga layout is
-- unchanged for the whole subtree.  Text lines are always recomputed from the
-- current text content so stale content is never displayed.
local function readback_from_cache(element, ax, ay)
    local node  = element.yoga_node
    local cache = _node_layout[node]
    if not cache then
        -- Cache miss — fall through to normal readback.
        return false
    end
    local lw = cache[3]
    local cax = ax + cache[1]
    local cay = ay + cache[2]
    element.rect = { x = cax, y = cay, w = lw, h = cache[4] }
    if element.kind == "text" and element._wrap then
        local mode = element._wrap_mode or "wrap"
        if mode == "hard" then
            element.lines = text_mod.wrap_hard(element.text or "", lw)
        elseif mode == "truncate" or mode == "truncate-end" then
            element.lines = { text_mod.truncate(element.text or "", lw) }
        elseif mode == "truncate-start" then
            element.lines = { text_mod.truncate_start(element.text or "", lw) }
        elseif mode == "truncate-middle" then
            element.lines = { text_mod.truncate_middle(element.text or "", lw) }
        else
            element.lines = text_mod.wrap(element.text or "", lw)
        end
    end
    if element.kind == "box" then
        for _, child in ipairs(element.children or {}) do
            if not readback_from_cache(child, cax, cay) then
                return false
            end
        end
    end
    return true
end

-- Recursively read computed layout back and stash it on each element.
-- Returns absolute x/y by accumulating parent offsets (yoga only gives local).
-- `phase` == "measure" : first pass, record rect on everything and collect
--                         wrap-capable text nodes that need re-measuring.
-- `phase` == "final"   : second pass, rect/lines final.
local function readback(element, ox, oy, phase, wrap_nodes)
    local node = element.yoga_node
    local has_new = yoga.node_has_new_layout(node)
    yoga.node_set_has_new_layout(node, false)

    local cache = _node_layout[node]

    -- FAST PATH: layout unchanged and parent offset unchanged → entire subtree
    -- coordinates are identical to last frame.  Text lines are still
    -- recomputed from current content so dynamic text is always fresh.
    if not has_new and cache and cache[5] == ox and cache[6] == oy then
        local ax = ox + cache[1]
        local ay = oy + cache[2]
        local lw = cache[3]
        element.rect = { x = ax, y = ay, w = lw, h = cache[4] }
        if element.kind == "text" and element._wrap then
            local mode = element._wrap_mode or "wrap"
            local lines
            if mode == "hard" then
                lines = text_mod.wrap_hard(element.text or "", lw)
                element.lines = lines
                if phase == "measure" and wrap_nodes and #lines > 1 then
                    wrap_nodes[#wrap_nodes + 1] = { node = element, lines = lines }
                end
            elseif mode == "truncate" or mode == "truncate-end" then
                element.lines = { text_mod.truncate(element.text or "", lw) }
            elseif mode == "truncate-start" then
                element.lines = { text_mod.truncate_start(element.text or "", lw) }
            elseif mode == "truncate-middle" then
                element.lines = { text_mod.truncate_middle(element.text or "", lw) }
            else
                lines = text_mod.wrap(element.text or "", lw)
                element.lines = lines
                if phase == "measure" and wrap_nodes and #lines > 1 then
                    wrap_nodes[#wrap_nodes + 1] = { node = element, lines = lines }
                end
            end
        end
        if element.kind == "box" then
            for _, child in ipairs(element.children or {}) do
                if not readback_from_cache(child, ax, ay) then
                    -- Cache miss mid-subtree: full readback for this child.
                    readback(child, ax, ay, phase, wrap_nodes)
                end
            end
        end
        return
    end

    -- NORMAL PATH: read local layout from Yoga (or from cache if only ox/oy changed).
    local lx, ly, lw, lh
    if has_new or not cache then
        lx, ly, lw, lh = yoga.node_get(node)
    else
        -- Parent offset changed but local layout is the same; reuse cached values.
        lx, ly, lw, lh = cache[1], cache[2], cache[3], cache[4]
    end
    local ax, ay = ox + lx, oy + ly
    element.rect = { x = ax, y = ay, w = lw, h = lh }

    -- Update cache.
    if not cache then
        cache = {}
        _node_layout[node] = cache
    end
    cache[1], cache[2], cache[3], cache[4] = lx, ly, lw, lh
    cache[5], cache[6] = ox, oy

    if element.kind == "box" then
        for _, child in ipairs(element.children or {}) do
            readback(child, ax, ay, phase, wrap_nodes)
        end
    elseif element.kind == "text" then
        if element._wrap then
            local mode = element._wrap_mode or "wrap"
            local lines
            if mode == "hard" then
                lines = text_mod.wrap_hard(element.text or "", lw)
                element.lines = lines
                if phase == "measure" and wrap_nodes and #lines > 1 then
                    wrap_nodes[#wrap_nodes + 1] = { node = element, lines = lines }
                end
            elseif mode == "truncate" or mode == "truncate-end" then
                lines = { text_mod.truncate(element.text or "", lw) }
                element.lines = lines
            elseif mode == "truncate-start" then
                lines = { text_mod.truncate_start(element.text or "", lw) }
                element.lines = lines
            elseif mode == "truncate-middle" then
                lines = { text_mod.truncate_middle(element.text or "", lw) }
                element.lines = lines
            else
                -- default "wrap" mode
                lines = text_mod.wrap(element.text or "", lw)
                element.lines = lines
                if phase == "measure" and wrap_nodes and #lines > 1 then
                    wrap_nodes[#wrap_nodes + 1] = { node = element, lines = lines }
                end
            end
            cache[7] = nil  -- lines not cached; always recomputed from current text
        end
    end
end

-- Walk the element tree after layout and fire ref._measure(w, h) on any
-- Box that carries a ref with a _measure callback (used by useMeasure()).
-- `clip_bottom` is the absolute Y limit imposed by ancestor clipping (parent
-- height + terminal height). When a Box's layout height would extend past
-- clip_bottom, only the visible portion is reported so useMeasure()-based
-- scroll windows are correctly capped at the actual visible area.
local function fire_measure_refs(element, clip_bottom)
    if element.kind ~= "box" then return end
    local rect = element.rect
    if not rect then return end

    -- Compute visible height: min of intrinsic height and remaining space
    -- above the clip boundary.
    local visible_h = rect.h
    if clip_bottom then
        visible_h = math.max(0, math.min(rect.h, clip_bottom - rect.y))
    end

    local ref = element.ref
    if ref and type(ref._measure) == "function" then
        ref._measure(rect.w, visible_h)
    end

    -- Children are clipped by this element's visible bottom.
    local child_clip = rect.y + visible_h
    -- When a bordered box overflows the terminal clip, reserve the last
    -- visible row for the bottom border so children's scroll windows don't
    -- extend into the row that will be used to draw the border.
    local props = element.props
    if props and props.borderStyle
       and clip_bottom and (rect.y + rect.h > clip_bottom)
       and child_clip > rect.y then
        child_clip = child_clip - 1
    end
    for _, child in ipairs(element.children or {}) do
        fire_measure_refs(child, child_clip)
    end
end

-- Public entry: build/reconcile → calc → readback.
-- `term_h` (optional) is the terminal height in rows; passed to
-- fire_measure_refs so useMeasure() consumers see the actually-visible
-- height when content overflows the terminal.
function M.compute(element, term_h)
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

    -- Pass 3: fire ref._measure callbacks so useMeasure() consumers see the
    -- Yoga-allocated dimensions on the next render frame.
    -- Compute the initial clip bottom from the root rect and term_h.
    local root_clip = nil
    if element.rect then
        root_clip = term_h and math.min(element.rect.y + element.rect.h, term_h)
                           or  (element.rect.y + element.rect.h)
    end
    fire_measure_refs(element, root_clip)

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
