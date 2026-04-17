-- tui/element.lua — host element factories.
--
-- All user-facing elements are plain Lua tables of the shape:
--   { kind = "box"|"text", props = {...}, children = {...} }
-- children are either other elements (for Box) or strings (for Text).

local M = {}

-- Internal helper: given a table that may mix hash-style props and
-- array-style children, split them into a props table and a children list.
local function split_props_children(t)
    local props = {}
    local children = {}
    for k, v in pairs(t) do
        if type(k) == "number" then
            children[k] = v
        else
            props[k] = v
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

return M
