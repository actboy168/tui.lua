-- tui/internal/hit_test.lua — global hit testing and mouse event dispatch.
--
-- After each layout pass, the framework stores the rendered element tree
-- (with absolute screen rects) via set_tree().  When a mouse event arrives,
-- hit_test() finds the deepest element whose rect contains the (col, row),
-- and dispatch_mouse_down() bubbles the event up through ancestors looking for
-- an onMouseDown handler.
--
-- This mirrors Ink's hit-test + dispatch architecture:
--   * Box supports onMouseDown / onScroll props
--   * Text does NOT support mouse event props (clicks on text bubble to
--     the nearest ancestor Box with a handler)
--   * hit_test walks children in reverse order (later siblings overlay
--     earlier ones, matching the painter's algorithm)

local M = {}

-- The latest laid-out host element tree.  Set by init.lua paint() after
-- layout.compute() and cleared on teardown.
local _last_tree = nil

-- Row offset between terminal coordinates and content coordinates.
-- In interactive (main-screen) mode, TUI content may not start at the top
-- of the terminal — it starts wherever the cursor was when the app
-- launched (typically the bottom).  SGR mouse events report terminal-
-- absolute coordinates, but element rects use content-relative (0-based)
-- coordinates.  This offset bridges the gap:
--   content_row = terminal_row_0based - _row_offset
-- In harness mode (vterm), content always starts at row 0, so offset = 0.
local _row_offset = 0

--- set_tree(tree) — store the current element tree for hit testing.
-- Call after layout.compute() so every element has a rect.
function M.set_tree(tree)
    _last_tree = tree
end

--- clear_tree() — drop the stored tree (called on teardown / unmount).
function M.clear_tree()
    _last_tree = nil
end

--- set_row_offset(n) — set the row offset for coordinate conversion.
-- n is the 0-based terminal row where content y=0 starts.
-- In interactive mode this is typically (terminal_height - content_height).
-- In harness mode this is 0.
---@param n integer
function M.set_row_offset(n)
    _row_offset = n
end

-- do_hit_test: internal implementation, exposed as M.hit_test below.
local function do_hit_test(col, row)
    if not _last_tree then return nil end
    -- Convert 1-based terminal coordinates to 0-based content coordinates.
    -- SGR mouse events are 1-based terminal-absolute; element rects are
    -- 0-based content-relative.  Subtract _row_offset to bridge the gap.
    local c = col - 1
    local r = (row - 1) - _row_offset
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

--- hit_test(col, row) -> path | nil
-- Returns an array of elements from root to the deepest hit element,
-- or nil if the point is outside the tree.
-- col/row are 1-based terminal-absolute SGR coordinates.
---@param col integer 1-based terminal column (SGR)
---@param row integer 1-based terminal row (SGR)
---@return table|nil path array from root to deepest hit element, or nil
M.hit_test = do_hit_test

--- dispatch_mouse_down(col, row) -> consumed: bool
-- Hit-test and bubble a left-button mouse-down event. Walks the hit path
-- from leaf to root; the first element with an onMouseDown prop handles it.
-- The handler receives { col, row, localCol, localRow, target } where
-- localCol/localRow are 0-based offsets relative to the handler element.
function M.dispatch_mouse_down(col, row)
    local path = do_hit_test(col, row)
    if not path then return false end
    local leaf = path[#path]
    for i = #path, 1, -1 do
        local e = path[i]
        if e.props and type(e.props.onMouseDown) == "function" then
            local r = e.rect or { x = 0, y = 0 }
            e.props.onMouseDown({
                col      = col,
                row      = row,
                localCol = (col - 1) - r.x,
                localRow = ((row - 1) - _row_offset) - r.y,
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
                localRow  = ((row - 1) - _row_offset) - r.y,
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
local _MOUSE_PROPS = { onMouseDown = true, onScroll = true }

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

--- _reset() — clear all state (called between harness mounts).
function M._reset()
    _last_tree = nil
    _row_offset = 0
end

return M
