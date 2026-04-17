-- tui/layout.lua — build Yoga tree from element tree and compute layout.
--
-- Stage 1 only handles the subset needed by hello.lua:
--   * Box with optional border / padding / width / height
--   * Text as leaf (intrinsic width = string length, height = 1)
--
-- The element table is mutated in place with `.rect = { x, y, w, h }` for
-- the renderer to consume.

local yoga = require "yoga"

local M = {}

-- Map our friendly Box prop names to yoga style keys.
-- Most keys pass through unchanged; only a couple need translation.
local function apply_box_style(node, props)
    local style = {}

    -- border: "single" | "double" | "round" → 1 on every edge (for layout
    -- reservation). Actual glyph choice happens in renderer.
    if props.border then
        style.border = 1
    end

    -- pass-through keys that map 1:1 to luayoga style names
    local passthrough = {
        "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
        "flex", "flexDirection", "flexWrap",
        "justifyContent", "alignItems", "alignContent", "alignSelf",
        "margin", "marginTop", "marginBottom", "marginLeft", "marginRight",
        "marginX", "marginY",
        "padding", "paddingTop", "paddingBottom", "paddingLeft", "paddingRight",
        "paddingX", "paddingY",
        "gap", "rowGap", "columnGap",
        "display", "position", "top", "bottom", "left", "right",
    }
    for _, k in ipairs(passthrough) do
        if props[k] ~= nil then
            -- arrays like {0,1} become "0 1" for luayoga's string parser
            local v = props[k]
            if type(v) == "table" then
                v = table.concat(v, " ")
            end
            style[k] = v
        end
    end

    yoga.node_set(node, style)
end

-- Recursively create yoga nodes; returns the root node.
-- Also attaches `element.yoga_node` on every element for later readback.
local function build(element, parent)
    local node
    if parent then
        node = yoga.node_new(parent)
    else
        node = yoga.node_new()
    end
    element.yoga_node = node

    if element.kind == "box" then
        apply_box_style(node, element.props or {})
        for _, child in ipairs(element.children or {}) do
            build(child, node)
        end
    elseif element.kind == "text" then
        -- Stage 1: each text is a single-line leaf with intrinsic width.
        -- We count bytes for ASCII-only here; CJK/emoji width arrives in Stage 4.
        local text = element.text or ""
        yoga.node_set(node, {
            width  = #text,
            height = 1,
        })
    end

    return node
end

-- Recursively read computed layout back and stash it on each element.
-- Returns absolute x/y by accumulating parent offsets (yoga only gives local).
local function readback(element, ox, oy)
    local lx, ly, lw, lh = yoga.node_get(element.yoga_node)
    local ax, ay = ox + lx, oy + ly
    element.rect = { x = ax, y = ay, w = lw, h = lh }
    if element.kind == "box" then
        for _, child in ipairs(element.children or {}) do
            readback(child, ax, ay)
        end
    end
end

-- Public entry: build → calc → readback. Frees nothing; caller owns the root
-- and should call free(root) when done.
function M.compute(element)
    local root = build(element, nil)
    yoga.node_calc(root)
    readback(element, 0, 0)
    return root
end

function M.free(element)
    if element.yoga_node then
        yoga.node_free(element.yoga_node)
        element.yoga_node = nil
    end
end

return M
