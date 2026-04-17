-- tui/element.lua — host element factories.
--
-- All user-facing elements are plain Lua tables of the shape:
--   { kind = "box"|"text", props = {...}, children = {...} }
-- children are either other elements (for Box) or strings (for Text).

local M = {}

-- Internal helper: given a table that may mix hash-style props and
-- array-style children, split them into a props table and a children list.
-- Children are compacted to a contiguous array (nil slots are dropped) so
-- that downstream `ipairs(children)` works even when users write conditional
-- expressions like `cond and X or nil` inside the constructor.
local function split_props_children(t)
    local props = {}
    local sparse = {}
    local max_idx = 0
    for k, v in pairs(t) do
        if type(k) == "number" then
            sparse[k] = v
            if k > max_idx then max_idx = k end
        else
            props[k] = v
        end
    end
    local children = {}
    for i = 1, max_idx do
        if sparse[i] ~= nil then
            children[#children + 1] = sparse[i]
        end
    end
    return props, children
end

--- Box(props_and_children) -> element
-- Supports both `Box { child1, child2 }` and `Box { padding=1, child }`.
function M.Box(t)
    t = t or {}
    local props, children = split_props_children(t)
    return { kind = "box", props = props, children = children }
end

--- Text(props_and_children) -> element
-- Children must all be strings (concatenated on render).
function M.Text(t)
    t = t or {}
    local props, children = split_props_children(t)
    -- Join all string children into a single string for now.
    local parts = {}
    for i, v in ipairs(children) do
        parts[i] = tostring(v)
    end
    return {
        kind = "text",
        props = props,
        children = parts,
        text = table.concat(parts),
    }
end

--- ErrorBoundary { fallback = element_or_nil, child1, child2, ... }
-- Catches errors raised while expanding any descendant during reconciliation.
-- On a caught error, the boundary's children are replaced by `fallback` for
-- the rest of this (and subsequent) render passes, until the element
-- remounts. `fallback` must be a static element (host or component); it is
-- not passed any error info in this version.
function M.ErrorBoundary(t)
    t = t or {}
    local props, children = split_props_children(t)
    return {
        kind = "error_boundary",
        fallback = props.fallback,
        children = children,
    }
end

return M
