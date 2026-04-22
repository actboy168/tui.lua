local element    = require "tui.internal.element"
local layout     = require "tui.internal.layout"
local renderer   = require "tui.internal.renderer"
local screen_mod = require "tui.internal.screen"
local reconciler = require "tui.internal.reconciler"

local M = {}

-- Error-handling: `reconciler.render` can raise if a component fn throws
-- and there is no `<ErrorBoundary>` ancestor to catch it. We swap in a
-- banner tree so the event loop keeps running instead of crashing the
-- whole TUI (the "framework-level implicit boundary" guarantee).
local function fallback_error_tree(msg, w, h)
    return element.Box {
        width = w, height = h,
        element.Text {
            "[tui] render error: " .. tostring(msg),
        },
    }
end

--- Render the component tree, clear dirty flags, and compute layout.
-- Optionally expands the root Box to fill the given dimensions.
-- `is_main` controls whether height is auto-filled (false=alt-screen).
-- `throw_on_error` (default false): when true, render errors propagate
-- instead of being swapped to a fallback banner tree. The test harness
-- passes true so that `pcall(testing.render(...))` contracts still work.
function M.render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
    local tree
    if throw_on_error then
        tree = reconciler.render(rec_state, root, app_handle)
        if not tree then
            tree = element.Box { width = w, height = h }
        end
    else
        local ok, tree_or_err = pcall(reconciler.render, rec_state, root, app_handle)
        if ok then
            tree = tree_or_err
            if not tree then
                tree = element.Box { width = w, height = h }
            end
        else
            tree = fallback_error_tree(tree_or_err, w, h)
        end
    end

    -- Expand root Box to fill the terminal width; fill height only in alt mode.
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = w end
        if not is_main and tree.props.height == nil then tree.props.height = h end
    end

    reconciler.clear_dirty(rec_state)
    layout.compute(tree, h)
    return tree
end

--- Stabilize the tree by re-rendering until no components are dirty.
-- This ensures effects that synchronously trigger setState are fully
-- resolved within a single frame, matching the harness behavior.
-- Returns the final tree and the number of render passes performed.
-- Caller is responsible for freeing the returned tree when done.
function M.stabilize(rec_state, root, app_handle, w, h, is_main, throw_on_error)
    local tree = M.render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
    local passes = 1

    for _ = 1, 8 do
        if not reconciler.has_dirty(rec_state) then break end
        layout.free(tree)
        tree = M.render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
        passes = passes + 1
    end

    return tree, passes
end

--- Find the cursor position in the laid-out tree.
-- Returns col, row (1-based) or nil.
function M.find_cursor(tree)
    local first_candidate = nil
    local focused_candidate = nil
    local root_w = tree.rect and tree.rect.w
    local root_h = tree.rect and tree.rect.h

    local function walk(e)
        if not e then return end
        if e.kind == "text" and e._cursor_offset ~= nil then
            local r = e.rect or { x = 0, y = 0 }
            local offset = math.min(e._cursor_offset, r.w or e._cursor_offset)
            local col = r.x + offset + 1
            if root_w and col > root_w then col = root_w end
            local row = r.y + 1
            if root_h and row > root_h then row = root_h end
            local cand = { col = col, row = row }
            if not first_candidate then
                first_candidate = cand
            end
            if e._cursor_focused and not focused_candidate then
                focused_candidate = cand
            end
        end
        if e.children then
            for _, c in ipairs(e.children) do
                walk(c)
            end
        end
    end

    walk(tree)
    local chosen = focused_candidate or first_candidate
    if chosen then
        return chosen.col, chosen.row
    end
    return nil
end

--- Paint a laid-out tree to the screen state and return the diff string.
function M.paint_and_diff(tree, screen_state, interactive, resized, content_h)
    screen_mod.clear(screen_state)
    renderer.paint(tree, screen_state)
    return screen_mod.diff(screen_state, interactive and resized,
                           interactive and content_h or nil)
end

return M
