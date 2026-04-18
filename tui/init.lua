-- tui/init.lua — public API entry for the tui framework.
--
-- Stage 2 API surface:
--   tui.Box { ... }
--   tui.Text { ... }
--   tui.render(root)            -- root can be a function component or a host element
--   tui.useState(initial)
--   tui.useEffect(fn, deps)
--   tui.useInterval(fn, ms)
--   tui.useTimeout(fn, ms)
--   tui.setInterval/setTimeout/clearTimer (scheduler passthrough)
--   tui.useApp() -> { exit = fn }
--   tui.configureScheduler{ now=fn, sleep=fn }  -- swap scheduler backend
--                                                  (call before tui.render)

local element    = require "tui.element"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local screen_mod = require "tui.screen"
local reconciler = require "tui.reconciler"
local scheduler  = require "tui.scheduler"
local hooks      = require "tui.hooks"
local input_mod  = require "tui.input"
local resize_mod = require "tui.resize"
local focus_mod  = require "tui.focus"
local static_mod = require "tui.builtin.static"
local text_input = require "tui.builtin.text_input"
local cursor_mod = require "tui.builtin.cursor"
local spinner_mod = require "tui.builtin.spinner"
local select_mod = require "tui.builtin.select"
local progress_mod = require "tui.builtin.progress_bar"
local tui_core   = require "tui_core"

local terminal = tui_core.terminal

-- ---------------------------------------------------------------------------
-- Default scheduler backend (bee-based).
--
-- The scheduler itself is platform-agnostic; here we install sensible defaults
-- so out-of-the-box `tui.render(App)` just works. Production integrators may
-- call `tui.configureScheduler{ now=..., sleep=... }` before `tui.render` to
-- plug in ltask / libuv / their own event loop.
local function install_default_backend()
    local ok_time,   time   = pcall(require, "bee.time")
    local ok_thread, thread = pcall(require, "bee.thread")
    if ok_time and ok_thread then
        scheduler.configure {
            now   = function() return time.monotonic() end,
            sleep = function(ms) thread.sleep(ms) end,
        }
    end
end
install_default_backend()

local M = {}

-- Dev-mode (Stage 17). Enable in-framework validation of hook order,
-- setState-during-render, and missing key warnings. Default OFF in
-- production (zero overhead — each check is a single early-return branch).
-- The test harness (tui.testing) force-enables it; flip manually with
-- tui.setDevMode(true/false) from a demo or REPL if needed.
M._dev_mode = false

function M.setDevMode(on)
    M._dev_mode = on and true or false
    hooks._set_dev_mode(M._dev_mode)
end

-- Expose scheduler configuration for production integrators.
M.configureScheduler = scheduler.configure

-- Host elements
M.Box            = element.Box
M.Text           = element.Text
M.ErrorBoundary  = element.ErrorBoundary
M.Static         = static_mod.Static
M.TextInput      = text_input.TextInput
M.Spinner        = spinner_mod.Spinner
M.Select         = select_mod.Select
M.ProgressBar    = progress_mod.ProgressBar

-- Hooks
M.useState       = hooks.useState
M.useEffect      = hooks.useEffect
M.useMemo        = hooks.useMemo
M.useCallback    = hooks.useCallback
M.useRef         = hooks.useRef
M.useLatestRef   = hooks.useLatestRef
M.useReducer     = hooks.useReducer
M.useContext     = hooks.useContext
M.createContext  = hooks.createContext
M.useInterval    = hooks.useInterval
M.useTimeout     = hooks.useTimeout
M.useAnimation   = hooks.useAnimation
M.useInput       = hooks.useInput
M.useWindowSize  = hooks.useWindowSize
M.useApp         = hooks.useApp
M.useFocus        = hooks.useFocus
M.useFocusManager = hooks.useFocusManager
M.useErrorBoundary = hooks.useErrorBoundary

-- Scheduler passthrough (users can bypass hooks if they really want to).
M.setInterval = scheduler.setInterval
M.setTimeout  = scheduler.setTimeout
M.clearTimer  = scheduler.clearTimer

-- ANSI helpers
local <const> CLEAR    = "\27[2J\27[H"
local <const> HIDE_CUR = "\27[?25l"
local <const> SHOW_CUR = "\27[?25h"

-- Walk the laid-out tree and record the first Text node that requested a
-- cursor. 1-based (col, row) returned for direct use in `\27[<row>;<col>H`.
-- Returned coords are ALWAYS integers: Yoga layout can produce float rect
-- origins, and `\27[73.0;3.0H` is rejected by most terminals as a parse
-- error (bug observed 2026-04-18 — cursor stuck wherever the previous SGR
-- diff left it). Round defensively here rather than trusting layout.
local function find_cursor(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "text" and e._cursor_offset ~= nil then
            local r = e.rect or { x = 0, y = 0 }
            local col = math.floor(r.x + e._cursor_offset + 1)
            local row = math.floor(r.y + 1)
            return col, row
        end
        if e.children then
            for _, c in ipairs(e.children) do
                local col, row = walk(c)
                if col then return col, row end
            end
        end
        return nil
    end
    return walk(tree)
end

-- Produce + commit one frame. Called internally by render / rerender /
-- type / press / advance / resize.
--
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

-- Produce a fresh host tree (with layout applied) for the current frame.
-- Caller is responsible for layout.free() after using the tree.
local function produce_tree(rec_state, root, app_handle, w, h)
    local ok, tree_or_err = pcall(reconciler.render, rec_state, root, app_handle)
    local tree
    if ok then
        tree = tree_or_err
        if not tree then
            tree = element.Box { width = w, height = h }
        end
    else
        tree = fallback_error_tree(tree_or_err, w, h)
    end

    -- Expand root Box to fill the terminal if user didn't set size.
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = w end
        if tree.props.height == nil then tree.props.height = h end
    end

    layout.compute(tree)
    return tree
end

--- tui.render(root)
-- Run the main loop with `root` as the top of the component tree. Blocks
-- until the app calls `useApp():exit()`, or an emergency key is received
-- (Ctrl+C / Ctrl+D — always honored by the framework).
function M.render(root)
    terminal.windows_vt_enable()
    terminal.set_raw(true)
    terminal.write(HIDE_CUR .. CLEAR)

    local rec_state    = reconciler.new()
    local init_w, init_h = terminal.get_size()
    local screen_state = screen_mod.new(init_w, init_h)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()

    local app_handle  = {
        exit = function() scheduler.stop() end,
    }

    local function paint()
        local w, h = terminal.get_size()
        local cw, ch = screen_mod.size(screen_state)
        if cw ~= w or ch ~= h then
            screen_mod.resize(screen_state, w, h)
        end
        if resize_mod.observe(w, h) then
            screen_mod.invalidate(screen_state)
        end
        local tree = produce_tree(rec_state, root, app_handle, w, h)
        screen_mod.clear(screen_state)
        renderer.paint(tree, screen_state)
        local ansi = screen_mod.diff(screen_state)
        if #ansi > 0 then terminal.write(ansi) end

        -- Post-commit: cursor + IME positioning. A focused TextInput tags its
        -- Text element with _cursor_offset; we translate that to absolute
        -- coordinates and move the terminal's real cursor there.
        local ccol, crow = find_cursor(tree)
        if ccol and crow then
            terminal.write(SHOW_CUR .. "\27[" .. crow .. ";" .. ccol .. "H")
            terminal.set_ime_pos(ccol, crow)
        else
            terminal.write(HIDE_CUR)
        end

        layout.free(tree)
    end

    local function read()
        return terminal.read_raw()
    end

    local function on_input(s)
        -- Dispatch to useInput subscribers and focused handlers; the
        -- dispatcher inspects parsed events semantically and returns true
        -- if Ctrl+C / Ctrl+D was seen. This matches Ink: handlers still
        -- observe the key, but the outer loop always tears down cleanly.
        local should_exit = input_mod.dispatch(s)
        -- Input handlers may have flipped state; ensure a repaint happens.
        scheduler.requestRedraw()
        return should_exit
    end

    local ok, err = pcall(function()
        scheduler._reset()
        scheduler.run {
            paint    = paint,
            read     = read,
            on_input = on_input,
        }
    end)

    -- Teardown: run cleanups on all live instances.
    reconciler.shutdown(rec_state)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()

    -- Restore terminal state regardless of error.
    terminal.write(SHOW_CUR .. "\r\n")
    terminal.set_raw(false)

    if not ok then error(err) end
end

return M
