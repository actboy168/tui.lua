-- tui/builtin/static.lua — <Static items=..., render=fn(item,i)> component.
--
-- Ink-style append-only region. Semantics:
--   * Renders as a column Box stacking render(item, i) for each item.
--   * The children *list is memoized per-item*: once item i has been rendered
--     into a host element, we keep that element verbatim across subsequent
--     renders. This matches Ink's guarantee that Static output is committed
--     exactly once per item — callers may rely on it for log-like output.
--   * When props.items shrinks, we discard the dropped tail; when the array
--     prefix changes identity (a different item at an existing index), we
--     re-render from that index outward. (Normal usage is append-only.)
--
-- The combination of (memoized children + row-level screen diff) means items
-- already on screen do NOT produce ANSI output on subsequent paints: previous
-- rows compare equal in tui/screen.lua and get skipped.

local element = require "tui.element"

local M = {}

local function StaticImpl(props)
    props = props or {}
    local items  = props.items  or {}
    local render = props.render or function() return nil end

    local hooks = require "tui.hooks"
    -- Persistent cache: { [i] = { item = items[i], el = rendered_element } }
    local ref, _ = hooks.useState({ cache = {}, n = 0 })

    -- Determine from which index we need to (re)render. Default: nothing new.
    -- If any cached slot's item identity differs from the current items[i],
    -- invalidate from that index onward. If the cache is shorter than items,
    -- render from (cache size + 1).
    local invalidate_from = ref.n + 1
    for i = 1, math.min(#items, ref.n) do
        if ref.cache[i] == nil or not rawequal(ref.cache[i].item, items[i]) then
            invalidate_from = i
            break
        end
    end
    for i = invalidate_from, ref.n do
        ref.cache[i] = nil
    end

    -- Render any new items from invalidate_from..#items.
    for i = invalidate_from, #items do
        local el = render(items[i], i)
        if type(el) == "string" then el = element.Text { el } end
        ref.cache[i] = { item = items[i], el = el }
    end
    ref.n = #items

    -- Assemble children in order. Skip nils. Each slot gets a position-based
    -- `key` so the reconciler sees a properly-keyed list (Static is append-only,
    -- and its own `ref.cache` already guarantees per-item identity, so keying
    -- by index is correct and suppresses the dev-mode missing-key warning).
    local children = {}
    for i = 1, ref.n do
        local slot = ref.cache[i]
        if slot and slot.el ~= nil then
            -- Don't mutate cached element: shallow-copy only if key missing.
            if slot.el.key == nil then
                local copy = {}
                for k, v in pairs(slot.el) do copy[k] = v end
                copy.key = "static:" .. tostring(i)
                slot.el = copy
            end
            children[#children + 1] = slot.el
        end
    end

    -- Default Box props: column stack, shrink to content height.
    local box_props = {
        flexDirection = "column",
        flexShrink    = 0,
    }
    -- Allow user overrides via props (width/flexGrow/etc.).
    for k, v in pairs(props) do
        if k ~= "items" and k ~= "render" then box_props[k] = v end
    end

    -- Place children after props.
    for _, c in ipairs(children) do box_props[#box_props + 1] = c end
    return element.Box(box_props)
end

-- Public factory: wraps the implementation as a component element so the
-- reconciler creates a stable hook-bearing instance for it. `key` (if any)
-- is hoisted to the element for sibling identity.
function M.Static(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = StaticImpl, props = props, key = key }
end

return M
