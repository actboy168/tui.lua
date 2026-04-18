-- tui/layout.lua — build Yoga tree from element tree and compute layout.
--
-- Stage 4:
--   * Box with optional border / padding / width / height
--   * Text leaf: intrinsic width = display width via wcwidth; height accounts
--     for soft-wrap when wrap != "nowrap" (handled in tui/text.lua).

local yoga     = require "yoga"
local tui_core = require "tui_core"
local text_mod = require "tui.text"

local wcwidth = tui_core.wcwidth

local M = {}

-- Map our friendly Box prop names to yoga style keys.
-- Most keys pass through unchanged; only a couple need translation.
local function apply_box_style(node, props)
    local style = {}

    -- borderStyle: "single" | "double" | "round" | "bold" | "singleDouble" | "doubleSingle" | "classic"
    -- → 1 on every edge (for layout reservation). Actual glyph choice happens in renderer.
    if props.borderStyle then
        style.border = 1
    end

    -- pass-through keys that map 1:1 to luayoga style names
    -- Note: Yoga binding only accepts integers (not floats or percentages)
    local passthrough = {
        "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
        "flexGrow", "flexShrink", "flexBasis", "flexDirection", "flexWrap",
        "justifyContent", "alignItems", "alignContent", "alignSelf",
        "margin", "marginTop", "marginBottom", "marginLeft", "marginRight",
        "marginX", "marginY",
        "padding", "paddingTop", "paddingBottom", "paddingLeft", "paddingRight",
        "paddingX", "paddingY",
        "borderTop", "borderBottom", "borderLeft", "borderRight",
        "gap", "rowGap", "columnGap",
        "overflow", "boxSizing",
        "display", "position", "top", "bottom", "left", "right",
    }
    for _, k in ipairs(passthrough) do
        if props[k] ~= nil then
            -- arrays like {1,2} become "1 2" for luayoga multi-value syntax
            -- (e.g., margin = {1, 2} means top/bottom=1, left/right=2)
            local v = props[k]
            if type(v) == "table" then
                v = table.concat(v, " ")
            end
            style[k] = v
        end
    end

    -- overflowX/Y fallback to overflow (Yoga has no per-axis overflow)
    if props.overflowX ~= nil then style.overflow = props.overflowX end
    if props.overflowY ~= nil then style.overflow = props.overflowY end

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
        -- Intrinsic size via wcwidth. Soft-wrap decisions defer to yoga
        -- measure when wrap is enabled; for now compute a single-line width
        -- and let tui/text.lua install a measure callback if wrap is on.
        local text  = element.text or ""
        local iw    = wcwidth.string_width(text)
        local props = element.props or {}
        local wrap  = props.wrap
        if wrap == nil then wrap = "wrap" end
        -- Respect user-supplied width/height; otherwise fall back to intrinsic.
        local style = {
            width  = props.width  or iw,
            height = props.height or 1,
        }
        if props.flexGrow     ~= nil then style.flexGrow     = props.flexGrow end
        if props.flexShrink   ~= nil then style.flexShrink   = props.flexShrink end
        if props.flexBasis    ~= nil then style.flexBasis    = props.flexBasis end
        if props.alignSelf    ~= nil then style.alignSelf    = props.alignSelf end
        if props.overflow     ~= nil then style.overflow     = props.overflow end
        if props.marginTop  ~= nil then style.marginTop  = props.marginTop end
        if props.marginBottom ~= nil then style.marginBottom = props.marginBottom end
        if props.marginLeft ~= nil then style.marginLeft = props.marginLeft end
        if props.marginRight~= nil then style.marginRight= props.marginRight end
        yoga.node_set(node, style)
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

-- Public entry: build → calc → readback. Frees nothing; caller owns the root
-- and should call free(root) when done.
function M.compute(element)
    local root = build(element, nil)
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
    if element.yoga_node then
        yoga.node_free(element.yoga_node)
        element.yoga_node = nil
    end
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

return M
