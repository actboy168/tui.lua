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

-- Exposed for hooks.createContext: Provider factory needs the same split
-- logic so `MyCtx.Provider { value=X, child1, child2 }` works like Box.
M._split_props_children = split_props_children

-- Pull reserved props off to the element's top level so they don't leak into
-- layout/renderer. `key` is for reconciler identity; `ref` is for useMeasure().
local function pluck_reserved(props)
    local key = props.key
    props.key = nil
    local ref = props.ref
    props.ref = nil
    return key, ref
end

--- Box(props_and_children) -> element
-- Supports both `Box { child1, child2 }` and `Box { padding=1, child }`.
function M.Box(t)
    t = t or {}
    local props, children = split_props_children(t)
    local key, ref = pluck_reserved(props)
    return { kind = "box", key = key, ref = ref, props = props, children = children }
end

--- Text(props_and_children) -> element
-- Children may be strings or span tables.
-- A span table has the shape { text = "...", color = "...", bold = true, ... }
-- and applies per-segment style overrides within the rendered text.
-- Mixed and plain-string children may be combined freely.
function M.Text(t)
    t = t or {}
    local props, children = split_props_children(t)
    local key, _ref = pluck_reserved(props)
    _ref = nil  -- Text does not use ref
    local parts     = {}
    local runs      = {}
    local has_spans = false
    for _, v in ipairs(children) do
        if type(v) == "table" then
            -- Span child: must have a string `text` field.
            if type(v.text) ~= "string" then
                error("Text: span child must have a string 'text' field, got "
                      .. type(v.text), 2)
            end
            parts[#parts + 1] = v.text
            -- Collect span style props (every key except `text`).
            local span_props = nil
            for k, sv in pairs(v) do
                if k ~= "text" then
                    if not span_props then span_props = {} end
                    span_props[k] = sv
                end
            end
            runs[#runs + 1] = { text = v.text, props = span_props }
            has_spans = true
        else
            local s = tostring(v)
            parts[#parts + 1] = s
            runs[#runs + 1]   = { text = s, props = nil }
        end
    end
    return {
        kind     = "text",
        key      = key,
        props    = props,
        children = parts,
        text     = table.concat(parts),
        runs     = has_spans and runs or nil,
    }
end

--- ErrorBoundary { fallback = element_or_fn_or_nil, child1, child2, ... }
-- Catches errors raised while expanding any descendant during reconciliation,
-- and errors bubbled from post-commit channels (useEffect body/cleanup,
-- useInput / useFocus on_input). On a caught error, children are replaced
-- by `fallback` until the boundary is reset.
--
-- `fallback` shapes:
--   * element  — static tree rendered verbatim
--   * function — invoked as `fallback(err, reset)` each time the boundary
--                renders its fallback branch; must return an element (or
--                nil to render an empty box). `err` is a table with fields
--                `message` (the error value) and `trace` (debug.traceback
--                string captured at throw time). `reset` is a stable closure
--                that clears `caught_error` and schedules a redraw, letting
--                children re-attempt. Throwing inside `fallback` falls back
--                to an empty box (fatal prefix still propagates).
--   * nil      — render an empty box (legal, rarely useful)
function M.ErrorBoundary(t)
    t = t or {}
    local props, children = split_props_children(t)
    local key, _ref = pluck_reserved(props)
    _ref = nil  -- ErrorBoundary does not use ref
    local fb = props.fallback
    if fb ~= nil and type(fb) ~= "function" and type(fb) ~= "table" then
        error("ErrorBoundary: fallback must be an element, function, or nil; got " .. type(fb), 2)
    end
    return {
        kind = "error_boundary",
        key = key,
        fallback = fb,
        children = children,
    }
end

return M
