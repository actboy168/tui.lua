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
    write(ansi.cursorHide() .. ansi.enableBracketedPaste .. ansi.enableFocusEvents)
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
        local move_seq = "\r"
        if inst._last_content_h and inst._last_content_h > 0 then
            local target_row = inst._last_content_h + 1
            if inst._last_display_y then
                local dy = target_row - inst._last_display_y
                if dy > 0 then
                    move_seq = ansi.cursorDown(dy) .. "\r"
                end
            else
                move_seq = "\n\r"
            end
        end
        local write = inst._terminal.write
        write(ansi.disableBracketedPaste .. ansi.disableFocusEvents .. move_seq .. ansi.cursorShow() .. "\n")
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
function M.reset_framework()
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
end

--- Install the shared hit-test handler for mouse events.
function setup_hit_test()
    input_mod.set_hit_test_handler(function(ev)
        if ev.type == "down" and ev.button == 1 then
            return hit_test.dispatch_click(ev.x, ev.y)
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

--- Stabilize the tree by re-rendering until no components are dirty.
-- This ensures effects that synchronously trigger setState are fully
-- resolved within a single frame, matching the harness behavior.
-- Returns the final tree and the number of render passes performed.
-- Caller is responsible for freeing the returned tree when done.
stabilize = function(rec_state, root, app_handle, w, h, is_main, throw_on_error)
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

    local tree = render_once()
    local passes = 1

    for _ = 1, 8 do
        if not reconciler.has_dirty(rec_state) then break end
        layout.free(tree)
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
--   throw_on_error — bool (app: false, harness: true)
--   on_paint_done  — function(inst, tree, passes) or nil
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
    M.reset_framework()

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
        _capabilities      = opts.capabilities,
        _last_content_h    = 0,
    }

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

    local function build_cursor(tree, content_h)
        local cursor_seq = ""
        local ccol, crow = find_cursor(tree)
        if ccol and crow then
            if interactive and (crow - 1) < content_h then
                local cx, cy = screen_mod.cursor_pos(screen_state)
                local dx = (ccol - 1) - cx
                local dy = (crow - 1) - cy
                cursor_seq = ansi.cursorShow() .. ansi.cursorMove(dx, dy)
                screen_mod.set_display_cursor(screen_state, ccol - 1, crow - 1)
            elseif not interactive then
                cursor_seq = ansi.cursorShow() .. ansi.cursorPosition(ccol, crow, inst._capabilities)
            end
        elseif interactive then
            cursor_seq = ansi.cursorHide()
            screen_mod.set_display_cursor(screen_state, -1, -1)
        end
        return cursor_seq, ccol, crow
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

        -- Free the previous tree.
        if inst._tree then
            hit_test.clear_tree()
            layout.free(inst._tree)
        end

        local tree, passes = stabilize(rec_state, opts.root, opts.app_handle, w, h, interactive, throw_on_error)

        hit_test.set_tree(tree)

        local content_h = tree.rect and math.min(tree.rect.h, h) or h
        local new_mouse = update_mouse(tree)

        -- clear + paint + diff
        screen_mod.clear(screen_state)
        renderer.paint(tree, screen_state)
        local diff = screen_mod.diff(screen_state, interactive and resized,
                                     interactive and content_h or nil)

        local cursor_seq, ccol, crow = build_cursor(tree, content_h)
        write_output(diff, cursor_seq)

        if interactive then
            inst._last_display_y = crow
            inst._last_content_h = content_h
        end
        inst._render_count = inst._render_count + passes
        inst._mouse_auto_release = new_mouse
        inst._tree = tree
        if opts.on_paint_done then
            opts.on_paint_done(inst, tree, passes)
        end
    end
    inst.paint = paint_fn

    -- Scheduler opts shared by rerender/dispatch/run.
    inst._scheduler_opts = {
        read     = terminal.read_raw,
        on_input = function(bytes) return input_mod.dispatch(bytes) end,
        paint    = paint_fn,
        terminal = terminal,
    }

    setup_hit_test()

    require("tui.internal.hooks")._set_terminal_write(terminal.write)
    require("tui.internal.hooks")._set_terminal_caps(opts.capabilities)

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
        layout.free(inst._tree)
        inst._tree = nil
    end
    inst._mouse_auto_release = nil
    teardown_interactive(inst)
    require("tui.internal.hooks")._set_terminal_write(nil)
    require("tui.internal.hooks")._set_terminal_caps(nil)
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
