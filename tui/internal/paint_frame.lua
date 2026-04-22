local element    = require "tui.internal.element"
local layout     = require "tui.internal.layout"
local renderer   = require "tui.internal.renderer"
local screen_mod = require "tui.internal.screen"
local reconciler = require "tui.internal.reconciler"
local ansi       = require "tui.internal.ansi"
local hit_test   = require "tui.internal.hit_test"
local input_mod  = require "tui.internal.input"

local resize_mod = require "tui.internal.resize"

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

-- Render the component tree, clear dirty flags, and compute layout.
-- Optionally expands the root Box to fill the given dimensions.
-- `is_main` controls whether height is auto-filled (false=alt-screen).
-- `throw_on_error` (default false): when true, render errors propagate
-- instead of being swapped to a fallback banner tree. The test harness
-- passes true so that `pcall(testing.render(...))` contracts still work.
local function render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
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
    local tree = render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
    local passes = 1

    for _ = 1, 8 do
        if not reconciler.has_dirty(rec_state) then break end
        layout.free(tree)
        tree = render_and_layout(rec_state, root, app_handle, w, h, is_main, throw_on_error)
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

--- Perform a full paint frame: resize detection → stabilize → set_tree → paint.
-- Returns the laid-out tree and the number of render passes.
-- Caller is responsible for freeing the returned tree when done.
--
-- opts:
--   rec_state:       reconciler state
--   root:            root component/element
--   app_handle:      { exit = fn }
--   get_size:        function() -> w, h  (terminal.get_size)
--   screen:          screen state object
--   interactive:     boolean
--   throw_on_error:  boolean (default false)
--   prev_tree:      previous tree to free before stabilizing (harness only)
--   write_fn:        function(s) — terminal.write
--   on_cursor_move:  function(col, row)? — called when cursor is positioned
--   mouse_auto_release:  { current = nil|function } — managed by paint_interactive
function M.frame(opts)
    -- Resize detection.
    local w, h = opts.get_size()
    local cw, ch = screen_mod.size(opts.screen)
    local resized = (cw ~= w or ch ~= h)
    if resized then
        screen_mod.resize(opts.screen, w, h)
    end
    if resize_mod.observe(w, h) then
        screen_mod.invalidate(opts.screen)
    end

    local interactive = opts.interactive
    local throw_on_error = opts.throw_on_error or false

    -- Free the previous tree (caller must ensure it's cleared from hit_test).
    if opts.prev_tree then
        layout.free(opts.prev_tree)
    end

    local tree, passes = M.stabilize(opts.rec_state, opts.root, opts.app_handle, w, h, interactive, throw_on_error)

    -- Store tree for mouse hit testing.
    hit_test.set_tree(tree)

    local content_h = tree.rect and math.min(tree.rect.h, h) or h
    local mouse_ref = { current = opts.mouse_auto_release and opts.mouse_auto_release.current }
    M.paint_interactive(opts.screen, tree, {
        interactive = interactive,
        resized = resized,
        content_h = content_h,
        write_fn = opts.write_fn,
        set_display_cursor = screen_mod.set_display_cursor,
        cursor_pos_fn = function() return screen_mod.cursor_pos(opts.screen) end,
        on_cursor_move = opts.on_cursor_move,
        _mouse_auto_release_handler = mouse_ref,
    })
    if opts.mouse_auto_release then
        opts.mouse_auto_release.current = mouse_ref.current
    end

    return tree, passes
end

--- Paint a tree and write output.
-- Called from both init.lua paint() and harness _paint().
-- Handles both interactive (BSU/ESU wrapped, mouse auto-enable) and
-- non-interactive (plain diff + cursor) modes.
--
-- opts:
--   interactive: boolean
--   resized: boolean — true if terminal was resized this frame
--   content_h: number — layout content height (for cursor bounds clamp)
--   set_display_cursor: function(screen, col, row) — screen_mod.set_display_cursor
--   cursor_pos_fn: function() -> col, row — screen_mod.cursor_pos
--   on_cursor_move: function(col, row)? — called when cursor is positioned
--   _mouse_auto_release_handler: function(ref) — called with { current = nil|function }
--     so the caller can do:  local r = { current = self._mouse_auto_release }; paint_interactive(..., r); self._mouse_auto_release = r.current
function M.paint_interactive(screen_state, tree, opts)
    local interactive = opts.interactive
    local content_h = opts.content_h

    -- Auto-enable mouse mode when the tree has click/scroll handlers.
    if interactive then
        local needs_mouse = hit_test.has_mouse_props(tree)
        local r = opts._mouse_auto_release_handler
        if needs_mouse and not r.current then
            r.current = input_mod.request_mouse_level(1)
        elseif not needs_mouse and r.current then
            r.current()
            r.current = nil
        end
    end

    -- clear + paint + diff
    screen_mod.clear(screen_state)
    renderer.paint(tree, screen_state)
    local diff = screen_mod.diff(screen_state, interactive and opts.resized,
                                 interactive and content_h or nil)

    -- cursor
    local cursor_seq = ""
    local ccol, crow = M.find_cursor(tree)
    if ccol and crow then
        if interactive and (crow - 1) < content_h then
            local cx, cy = opts.cursor_pos_fn()
            local dx = (ccol - 1) - cx
            local dy = (crow - 1) - cy
            cursor_seq = ansi.cursorShow() .. ansi.cursorMove(dx, dy)
            opts.set_display_cursor(screen_state, ccol - 1, crow - 1)
        elseif not interactive then
            cursor_seq = ansi.cursorShow() .. ansi.cursorPosition(ccol, crow)
        end
    elseif interactive then
        cursor_seq = ansi.cursorHide()
        opts.set_display_cursor(screen_state, -1, -1)
    end

    if opts.on_cursor_move and ccol and crow then
        opts.on_cursor_move(ccol, crow)
    end

    -- write
    if interactive and (#diff > 0 or #cursor_seq > 0) then
        opts.write_fn(ansi.beginSyncUpdate() .. diff .. cursor_seq .. ansi.endSyncUpdate())
    elseif #diff > 0 then
        opts.write_fn(diff)
    elseif not interactive and #cursor_seq > 0 then
        opts.write_fn(cursor_seq)
    end
end

return M
