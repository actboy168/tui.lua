-- tui/internal/hit_test.lua — global hit testing and mouse event dispatch.
--
-- After each layout pass, the framework stores the rendered element tree
-- (with absolute screen rects) via set_tree().  When a mouse event arrives,
-- hit_test() finds the deepest element whose rect contains the (col, row),
-- and dispatch_click() bubbles the event up through ancestors looking for
-- an onClick handler.
--
-- This mirrors Ink's hit-test + dispatch architecture:
--   * Box supports onClick / onScroll / onMouseEnter / onMouseLeave props
--   * Text does NOT support mouse event props (clicks on text bubble to
--     the nearest ancestor Box with a handler)
--   * hit_test walks children in reverse order (later siblings overlay
--     earlier ones, matching the painter's algorithm)

local M = {}

-- The latest laid-out host element tree.  Set by init.lua paint() after
-- layout.compute() and cleared on teardown.
local _last_tree = nil

--- set_tree(tree) — store the current element tree for hit testing.
-- Call after layout.compute() so every element has a rect.
function M.set_tree(tree)
    _last_tree = tree
end

--- clear_tree() — drop the stored tree (called on teardown / unmount).
function M.clear_tree()
    _last_tree = nil
end

--- hit_test(col, row) -> path | nil
-- Returns an array of elements from root to the deepest hit element,
-- or nil if the point is outside the tree.
-- col/row are 1-based screen coordinates (matching SGR mouse events).
local function do_hit_test(col, row)
    if not _last_tree then return nil end
    -- Convert 1-based to 0-based for rect comparison (rects are 0-based from layout).
    local c = col - 1
    local r = row - 1
    local path = {}
    local function walk(e)
        if not e or not e.rect then return false end
        local rc = e.rect
        if c < rc.x or c >= rc.x + rc.w or r < rc.y or r >= rc.y + rc.h then
            return false
        end
        path[#path + 1] = e
        -- Walk children in reverse: later siblings are painted on top.
        if e.children then
            for i = #e.children, 1, -1 do
                if walk(e.children[i]) then return true end
            end
        end
        return true
    end
    walk(_last_tree)
    return #path > 0 and path or nil
end

M.hit_test = do_hit_test

--- dispatch_click(col, row) -> consumed: bool
-- Hit-test and bubble a click event.  Walks the hit path from leaf to
-- root; the first element with an onClick prop handles the event.
-- The handler receives { col, row, localCol, localRow, target } where
-- localCol/localRow are 0-based offsets relative to the handler element.
function M.dispatch_click(col, row)
    local path = do_hit_test(col, row)
    if not path then return false end
    local leaf = path[#path]
    for i = #path, 1, -1 do
        local e = path[i]
        if e.props and type(e.props.onClick) == "function" then
            local r = e.rect or { x = 0, y = 0 }
            e.props.onClick({
                col      = col,
                row      = row,
                localCol = (col - 1) - r.x,
                localRow = (row - 1) - r.y,
                target   = leaf,
            })
            return true
        end
    end
    return false
end

--- dispatch_scroll(col, row, direction) -> consumed: bool
-- Hit-test and dispatch a scroll event.  direction is 1 (up) or -1 (down).
-- The handler receives { col, row, localCol, localRow, direction, target }.
function M.dispatch_scroll(col, row, direction)
    local path = do_hit_test(col, row)
    if not path then return false end
    local leaf = path[#path]
    for i = #path, 1, -1 do
        local e = path[i]
        if e.props and type(e.props.onScroll) == "function" then
            local r = e.rect or { x = 0, y = 0 }
            e.props.onScroll({
                col       = col,
                row       = row,
                localCol  = (col - 1) - r.x,
                localRow  = (row - 1) - r.y,
                direction = direction,
                target    = leaf,
            })
            return true
        end
    end
    return false
end

--- has_mouse_props(tree) -> bool
-- Scan the tree for any element with mouse-related props.
-- Used to auto-enable terminal mouse mode.
local _MOUSE_PROPS = { onClick = true, onScroll = true, onMouseEnter = true, onMouseLeave = true }

local function has_mouse_props(tree)
    if not tree then return false end
    local props = tree.props
    if props then
        for k in pairs(_MOUSE_PROPS) do
            if props[k] ~= nil then return true end
        end
    end
    if tree.children then
        for _, ch in ipairs(tree.children) do
            if has_mouse_props(ch) then return true end
        end
    end
    return false
end

M.has_mouse_props = has_mouse_props

return M
