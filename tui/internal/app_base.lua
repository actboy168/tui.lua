-- tui/internal/app_base.lua — shared initialization / teardown helpers
-- used by both tui.internal.app (production) and tui.testing.harness.

local input_mod  = require "tui.internal.input"
local resize_mod = require "tui.internal.resize"
local focus_mod  = require "tui.internal.focus"
local scheduler  = require "tui.internal.scheduler"
local hit_test   = require "tui.internal.hit_test"
local ansi       = require "tui.internal.ansi"
local clipboard  = require "tui.internal.clipboard"
local screen_mod = require "tui.internal.screen"
local element    = require "tui.internal.element"
local layout     = require "tui.internal.layout"
local renderer   = require "tui.internal.renderer"
local reconciler = require "tui.internal.reconciler"

local M = {}

-- Forward declarations for the paint pipeline (defined below).
local find_cursor
local stabilize
local setup_interactive
local teardown_interactive
local setup_hit_test

--- Write interactive-mode startup sequences and wire writers.
function setup_interactive(terminal, interactive, use_kkp)
    if not interactive then return end
    local write = terminal.write
    write(ansi.cursorHide .. ansi.enableBracketedPaste .. ansi.enableFocusEvents)
    if use_kkp then
        write(ansi.kittyKeyboard.push)
    end
    input_mod.set_mouse_mode_writer(write)
    clipboard.set_writer(write)
    clipboard._osc52_enabled = true
end

--- Write interactive-mode teardown sequences and detach writers.
function teardown_interactive(inst)
    if inst._interactive then
        -- _last_buf_row: 0-based buffer row where the physical cursor sits after
        -- the last frame (C park position or TextInput position).
        -- We need to move to one row below the last content row so the shell
        -- prompt appears on a fresh line.
        -- dy = content_h - last_buf_row  (always >= 0 because buf_row < content_h)
        local move_seq = "\r"
        if inst._last_content_h and inst._last_content_h > 0 then
            local last_row = inst._last_buf_row or (inst._last_content_h - 1)
            local dy = inst._last_content_h - last_row
            if dy > 0 then
                move_seq = ansi.cursorDown(dy) .. "\r"
            end
        end
        local write = inst._terminal.write
        write(ansi.disableBracketedPaste .. ansi.disableFocusEvents .. move_seq .. ansi.cursorShow .. "\n")
        if inst._use_kkp then
            write(ansi.kittyKeyboard.pop)
        end
        input_mod.set_mouse_mode_writer(nil)
        clipboard.set_writer(nil)
    end
    local set_raw = inst._terminal.set_raw
    if set_raw then
        set_raw(false)
    end
    clipboard._osc52_enabled = false
end

--- Reset the framework singletons that both production and harness use.
function M.reset_framework(extension)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hit_test._reset()
    if extension and extension.reset then
        extension.reset()
    end
end

--- Install the shared hit-test handler for mouse events.
function setup_hit_test()
    input_mod.set_hit_test_handler(function(ev)
        if ev.type == "down" and ev.button == 1 then
            return hit_test.dispatch_mouse_down(ev.x, ev.y)
        elseif ev.type == "scroll" then
            return hit_test.dispatch_scroll(ev.x, ev.y, ev.scroll)
        end
        return false
    end)
end

-- ============================================================================
-- Paint frame pipeline (merged from paint_frame.lua)
-- ============================================================================

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

local function ensure_root_bounds(tree, w, h, is_main)
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = w end
        if not is_main and tree.props.height == nil then tree.props.height = h end
    end
    return tree
end

--- Stabilize the tree by re-rendering until no components are dirty.
-- This ensures effects that synchronously trigger setState are fully
-- resolved within a single frame, matching the harness behavior.
-- Returns the final tree and the number of render passes performed.
-- Caller is responsible for freeing the returned tree when done.
stabilize = function(rec_state, root, app_handle, w, h, is_main, throw_on_error, extension)
    local function render_once()
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

        tree = ensure_root_bounds(tree, w, h, is_main)
        if extension and extension.decorate then
            tree = extension.decorate(tree, {
                width = w,
                height = h,
                interactive = is_main,
            })
        end
        tree = ensure_root_bounds(tree, w, h, is_main)

        reconciler.clear_dirty(rec_state)
        layout.compute(tree, h)
        return tree
    end

    local tree = render_once()
    local passes = 1

    for _ = 1, 8 do
        if not reconciler.has_dirty(rec_state) then break end
        tree = render_once()
        passes = passes + 1
    end

    return tree, passes
end

--- Find the cursor position in the laid-out tree.
-- Returns col, row (1-based) or nil.
find_cursor = function(tree)
    local first_candidate = nil
    local focused_candidate = nil
    local root_w = tree.rect and tree.rect.w
    local root_h = tree.rect and tree.rect.h

    local function push_candidate(col, row, focused)
        local cand = { col = col, row = row }
        if not first_candidate then
            first_candidate = cand
        end
        if focused and not focused_candidate then
            focused_candidate = cand
        end
    end

    local function walk(e)
        if not e then return end

        local r = e.rect or { x = 0, y = 0 }
        if e._cursor_position ~= nil then
            local pos = e._cursor_position
            local x = pos.x or 0
            local y = pos.y or 0
            if x < 0 then x = 0 end
            if y < 0 then y = 0 end
            if r.w and x > r.w then x = r.w end
            if r.h and y > math.max(0, r.h - 1) then y = math.max(0, r.h - 1) end
            local col = r.x + x + 1
            if root_w and col > root_w then col = root_w end
            local row = r.y + y + 1
            if root_h and row > root_h then row = root_h end
            push_candidate(col, row, true)
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

-- ============================================================================
-- Mount / unmount — shared initialization and teardown for app and harness
-- ============================================================================

--- Mount a render instance: shared initialization used by both app and harness.
-- The caller creates the terminal and screen objects, then passes them in.
-- Returns an instance table with paint and common state fields.
--
-- opts fields:
--   root           — component function
--   app_handle     — { exit = fn }
--   interactive    — bool
--   use_kkp        — bool
--   throw_on_error  — bool (app: false, harness: true)
--   extension       — optional object with methods:
--     * decorate(tree, ctx) -> tree
--     * subscribe(request_redraw) -> unsubscribe_fn
--     * reset() -> nil
--   onPaintDone   — function(inst, tree, passes) or nil
--     App uses this to free the tree; Harness uses it to store the tree.
function M.mount(terminal, screen_state, opts)
    local interactive = opts.interactive
    local use_kkp    = opts.use_kkp

    setup_interactive(terminal, interactive, use_kkp)

    if interactive then
        screen_mod.set_mode(screen_state, "main")
    end

    local w, h = terminal.get_size()
    local rec_state = reconciler.new()
    M.reset_framework(opts.extension)

    -- If a clock backend is provided (e.g. vclock for testing),
    -- configure the scheduler before any timers are created.
    if opts.clock then
        scheduler.configure(opts.clock)
    end

    local inst = {
        _terminal          = terminal,
        _screen            = screen_state,
        _rec_state         = rec_state,
        _app_handle        = opts.app_handle,
        _interactive       = interactive,
        _use_kkp           = use_kkp,
        _w                 = w,
        _h                 = h,
        _mouse_auto_release = nil,
        _tree              = nil,
        _render_count      = 0,
        _capabilities        = opts.capabilities,
        _last_content_h       = 0,
        _last_buf_row         = nil,
        _extension_unsubscribe = nil,
        _extension            = opts.extension,
    }

    if opts.extension and opts.extension.subscribe then
        inst._extension_unsubscribe = opts.extension.subscribe(function()
            scheduler.requestRedraw()
        end)
    end

    local function check_resize()
        local w, h = terminal.get_size()
        local cw, ch = screen_mod.size(screen_state)
        local resized = (cw ~= w or ch ~= h)
        if resized then
            screen_mod.resize(screen_state, w, h)
        end
        if resize_mod.observe(w, h) then
            screen_mod.invalidate(screen_state)
        end
        return w, h, resized
    end

    local function update_mouse(tree)
        local new_mouse = inst._mouse_auto_release
        if interactive then
            local needs_mouse = hit_test.has_mouse_props(tree)
            if needs_mouse and not inst._mouse_auto_release then
                new_mouse = input_mod.request_mouse_level(1)
            elseif not needs_mouse and inst._mouse_auto_release then
                inst._mouse_auto_release()
                new_mouse = nil
            end
        end
        return new_mouse
    end

    local function build_cursor(tree, content_h, y_off)
        local cursor_seq = ""
        local ccol, crow = find_cursor(tree)
        -- buf_row: 0-based buffer row where the physical cursor will be after
        -- cursor_seq is emitted.  Defaults to the C park position (last row).
        local buf_row = content_h - 1
        if ccol and crow then
            -- crow-1 is absolute content row; visible range is [y_off, y_off+content_h-1].
            local br = (crow - 1) - y_off
            if interactive and br >= 0 and br < content_h then
                local cx, cy = screen_mod.cursor_pos(screen_state)
                local dx = (ccol - 1) - cx
                local dy = br - cy
                cursor_seq = ansi.cursorShow .. ansi.cursorMove(dx, dy)
                screen_mod.set_display_cursor(screen_state, ccol - 1, br)
                buf_row = br
            elseif not interactive then
                cursor_seq = ansi.cursorShow .. ansi.cursorPosition(ccol, crow, inst._capabilities)
            end
        elseif interactive then
            cursor_seq = ansi.cursorHide
            screen_mod.set_display_cursor(screen_state, -1, -1)
        end
        return cursor_seq, ccol, crow, buf_row
    end

    local function write_output(diff, cursor_seq)
        if interactive and (#diff > 0 or #cursor_seq > 0) then
            local caps = inst._capabilities
            if caps and caps.sync_output then
                terminal.write(ansi.beginSyncUpdate(caps) .. diff .. cursor_seq .. ansi.endSyncUpdate(caps))
            else
                terminal.write(diff .. cursor_seq)
            end
        elseif #diff > 0 then
            terminal.write(diff)
        elseif not interactive and #cursor_seq > 0 then
            terminal.write(cursor_seq)
        end
    end

    local function paint_fn()
        local w, h, resized = check_resize()
        local throw_on_error = opts.throw_on_error or false

        -- Discard previous tree reference.
        if inst._tree then
            hit_test.clear_tree()
        end

        local tree, passes = stabilize(rec_state, opts.root, opts.app_handle, w, h, interactive, throw_on_error, opts.extension)

        hit_test.set_tree(tree)

        local raw_h = tree.rect and tree.rect.h or h
        -- y_off: rows of content scrolled off the top (only in interactive mode
        -- when content is taller than the terminal).  The bottom min(raw_h, h)
        -- rows are painted; the top y_off rows scroll into the terminal's
        -- scroll-back buffer on the first render via \r\n.
        local y_off     = interactive and math.max(0, raw_h - h) or 0
        local content_h = math.min(raw_h, h)
        local new_mouse = update_mouse(tree)

        -- In interactive (main-screen) mode the content may not start at the
        -- top of the terminal.  row_offset maps SGR terminal rows to absolute
        -- content rows:  content_row = (sgr_row - 1) - row_offset.
        --   content_h <= h: row_offset = h - raw_h  (positive; content at bottom)
        --   content_h >  h: row_offset = h - raw_h  (negative; content overflows)
        -- The unified formula h - raw_h handles both cases.
        local row_offset = opts.row_offset
        if row_offset == nil then
            row_offset = interactive and (h - raw_h) or 0
        end
        hit_test.set_row_offset(row_offset)
        inst._row_offset = row_offset

        -- clear + paint + diff
        -- y_off shifts rendering up so the visible bottom content_h rows land
        -- in the screen buffer (indices 0..content_h-1).
        screen_mod.clear(screen_state)
        renderer.paint(tree, screen_state, y_off)
        local diff = screen_mod.diff(screen_state, interactive and resized,
                                     interactive and content_h or nil)

        local cursor_seq, ccol, crow, buf_row = build_cursor(tree, content_h, y_off)
        write_output(diff, cursor_seq)

        if interactive then
            inst._last_buf_row   = buf_row
            inst._last_content_h = content_h
        end
        inst._render_count = inst._render_count + passes
        inst._mouse_auto_release = new_mouse
        inst._tree = tree
        if opts.onPaintDone then
            opts.onPaintDone(inst, tree, passes)
        end
    end
    inst.paint = paint_fn

    -- Scheduler opts shared by rerender/dispatch/run.
    inst._scheduler_opts = {
        read     = terminal.read,
        onInput = function(bytes) return input_mod.dispatch(bytes) end,
        paint    = paint_fn,
        terminal = terminal,
    }

    setup_hit_test()

    require("tui.hook.terminal")._set_terminal_write(terminal.write)
    require("tui.hook.terminal")._set_terminal_caps(opts.capabilities)

    -- Initial paint.
    paint_fn()

    -- Mark scheduler running (initial paint done, ready for loop_once).
    scheduler.start()

    return inst
end

--- Unmount a render instance: shared teardown for both app and harness.
-- Handles reconciler shutdown, tree cleanup, and interactive teardown.
-- Harness-specific cleanup (layout.reset, hooks, ansi_restore, capture)
-- should be done by the caller after calling unmount.
function M.unmount(inst)
    reconciler.shutdown(inst._rec_state)
    if inst._tree then
        hit_test.clear_tree()
        inst._tree = nil
    end
    if inst._extension_unsubscribe then
        inst._extension_unsubscribe()
        inst._extension_unsubscribe = nil
    end
    inst._mouse_auto_release = nil
    teardown_interactive(inst)
    require("tui.hook.terminal")._set_terminal_write(nil)
    require("tui.hook.terminal")._set_terminal_caps(nil)
    if inst._extension and inst._extension.reset then
        inst._extension.reset()
    end
end

--- Re-render through the scheduler path.
-- Calls requestRedraw() + loop_once with the shared scheduler opts.
-- If inst has a _clock, uses clock.t as the `now` parameter;
-- otherwise callers should pass `now` explicitly.
-- `immediate` controls frame-rate throttling (true = bypass).
function M.rerender(inst, now, immediate)
    scheduler.requestRedraw()
    if inst._clock then
        now = inst._clock.t
        immediate = true
    end
    scheduler.loop_once(inst._scheduler_opts, inst._terminal, now, immediate)
end

--- Advance the virtual clock, run timers, and repaint.
-- If inst has a _clock, advances it by ms and uses clock.t for
-- scheduler.step(). Otherwise uses now_fn to compute the target time.
function M.advance(inst, ms_or_fn)
    if inst._clock then
        local ms = ms_or_fn
        assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
        inst._clock.t = inst._clock.t + ms
        scheduler.step(inst._clock.t)
    else
        scheduler.step(ms_or_fn())
    end
    inst:paint()
end

--- Resize the terminal dimensions.
function M.resize(inst, cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    inst._w, inst._h = cols, rows
    if inst._terminal.resize then inst._terminal.resize(cols, rows) end
end

M.find_cursor = find_cursor

--- Dimension getters.
function M.width(inst)  return inst._w end
function M.height(inst) return inst._h end
function M.size(inst)   return inst._w, inst._h end
function M.screen(inst) return inst._screen end

return M
