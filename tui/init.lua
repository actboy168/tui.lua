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

-- Expose scheduler configuration for production integrators.
M.configureScheduler = scheduler.configure

-- Host elements
M.Box  = element.Box
M.Text = element.Text

-- Hooks
M.useState    = hooks.useState
M.useEffect   = hooks.useEffect
M.useInterval = hooks.useInterval
M.useTimeout  = hooks.useTimeout
M.useInput    = hooks.useInput
M.useApp      = hooks.useApp

-- Scheduler passthrough (users can bypass hooks if they really want to).
M.setInterval = scheduler.setInterval
M.setTimeout  = scheduler.setTimeout
M.clearTimer  = scheduler.clearTimer

-- ANSI helpers
local CLEAR    = "\27[2J\27[H"
local HIDE_CUR = "\27[?25l"
local SHOW_CUR = "\27[?25h"

-- Produce a fresh host tree (with layout applied) for the current frame.
-- Caller is responsible for layout.free() after using the tree.
local function produce_tree(rec_state, root, app_handle, w, h)
    local tree = reconciler.render(rec_state, root, app_handle)
    if not tree then
        -- Component returned nil; render a blank root box to keep the screen sane.
        tree = element.Box { width = w, height = h }
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
    local screen_state = screen_mod.new()
    input_mod._reset()

    local app_handle  = {
        exit = function() scheduler.stop() end,
    }

    local function paint()
        local w, h = terminal.get_size()
        local tree = produce_tree(rec_state, root, app_handle, w, h)
        local rows = renderer.render_rows(tree, w, h)
        local ansi = screen_mod.diff(screen_state, rows, w, h)
        if #ansi > 0 then terminal.write(ansi) end
        layout.free(tree)
    end

    local function read()
        return terminal.read_raw()
    end

    local function on_input(s)
        -- Framework-level emergency exit: Ctrl+C (0x03) / Ctrl+D (0x04).
        -- These are always honored even if the app didn't register useInput.
        for i = 1, #s do
            local b = s:byte(i)
            if b == 3 or b == 4 then return true end
        end
        -- Otherwise, parse + broadcast to subscribed useInput handlers.
        input_mod.dispatch(s)
        -- Input handlers may have flipped state; ensure a repaint happens.
        scheduler.requestRedraw()
        return false
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

    -- Restore terminal state regardless of error.
    terminal.write(SHOW_CUR .. "\r\n")
    terminal.set_raw(false)

    if not ok then error(err) end
end

return M
