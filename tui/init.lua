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
local newline_mod = require "tui.builtin.newline"
local ansi       = require "tui.ansi"
local tui_core   = require "tui_core"
local info       = require "tui.terminal_info"

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
M.Newline        = newline_mod.Newline
M.Spacer         = newline_mod.Spacer

-- Component factory helper
--- Create a component factory from a render function. Two usage modes:
---   1) Factory mode:  local Header = tui.component(fn)
---                      Box { Header { title = "hi" } }
---   2) Direct mode:   tui.component(fn, { title = "hi" })
---                      — produces an element directly, useful when fn is dynamic
--- In both modes, `key` in props is auto-plucked to element top level.
function M.component(fn, props)
    if props == nil then
        -- Factory mode: return a callable factory
        return function(p)
            p = p or {}
            local key = p.key
            p.key = nil
            return { kind = "component", fn = fn, props = p, key = key }
        end
    end
    -- Direct mode: produce an element right away
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = fn, props = props, key = key }
end

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
M.useStdout      = hooks.useStdout
M.useStderr      = hooks.useStderr
M.useFocus        = hooks.useFocus
M.useFocusManager = hooks.useFocusManager
M.useDeclaredCursor = cursor_mod.useDeclaredCursor
M.useErrorBoundary = hooks.useErrorBoundary

-- Scheduler passthrough (users can bypass hooks if they really want to).
M.setInterval = scheduler.setInterval
M.setTimeout  = scheduler.setTimeout
M.clearTimer  = scheduler.clearTimer

-- Layout utilities
M.intrinsicSize = layout.intrinsic_size


-- Cursor position is set by the focused component via cursor.set(col, row)
-- during render. We consume it here after layout (so coordinates are absolute).
-- Single-writer model: only one component sets the cursor per frame.
--
-- Fallback: if no component calls cursor.set(), we scan the tree for Text
-- elements with _cursor_offset (legacy TextInput behavior).
local function find_cursor(tree)
    local first_candidate = nil
    local focused_candidate = nil

    local function walk(e)
        if not e then return end
        if e.kind == "text" and e._cursor_offset ~= nil then
            local r = e.rect or { x = 0, y = 0 }
            local col = r.x + e._cursor_offset + 1
            local row = r.y + 1
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
-- In main-screen mode (is_main=true) the root box height is NOT auto-filled
-- to h; content determines its own height so only the needed rows are claimed.
local function produce_tree(rec_state, root, app_handle, w, h, is_main)
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

    -- Expand root Box to fill the terminal width; fill height only in alt mode.
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = w end
        if not is_main and tree.props.height == nil then tree.props.height = h end
    end

    layout.compute(tree)
    return tree
end

--- tui.render(root)
-- Run the main loop with `root` as the top of the component tree. Blocks
-- until the app calls `useApp():exit()`, or an emergency key is received
-- (Ctrl+C / Ctrl+D — always honored by the framework).
function M.render(root)
    local interactive = info.interactive()

    terminal.windows_vt_enable()
    terminal.set_raw(true)
    if interactive then
        terminal.write(ansi.cursorHide())
    end

    local rec_state    = reconciler.new()
    local init_w, init_h = terminal.get_size()
    local screen_state = screen_mod.new(init_w, init_h)
    if interactive then
        screen_mod.set_mode(screen_state, "main")
    end
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()

    local app_handle  = {
        exit = function() scheduler.stop() end,
    }

    local function paint(term)
        local w, h = terminal.get_size()
        local cw, ch = screen_mod.size(screen_state)
        local resized = (cw ~= w or ch ~= h)
        if resized then
            screen_mod.resize(screen_state, w, h)
        end
        if resize_mod.observe(w, h) then
            screen_mod.invalidate(screen_state)
        end
        local tree = produce_tree(rec_state, root, app_handle, w, h, interactive)
        screen_mod.clear(screen_state)
        renderer.paint(tree, screen_state)

        -- Content height: how many rows the layout actually used. Clamped to h.
        -- In main-screen mode this limits how many rows are claimed in the
        -- terminal (so a small widget doesn't scroll the whole screen).
        local content_h = tree.rect and math.min(tree.rect.h, h) or h
        local diff = screen_mod.diff(screen_state, interactive and resized,
                                     interactive and content_h or nil)

        -- Post-commit: cursor positioning.
        -- In main-screen mode: use relative cursor movement from cursor_pos()
        -- (the virtual position after cursor_restore) to the TextInput coords.
        -- In non-interactive mode: no cursor handling.
        local cursor_seq = ""
        if interactive then
            local ccol, crow = find_cursor(tree)
            if ccol and crow then
                local cx, cy = screen_mod.cursor_pos(screen_state)
                local dx = (ccol - 1) - cx
                local dy = (crow - 1) - cy
                cursor_seq = ansi.cursorShow() .. ansi.cursorMove(dx, dy)
                screen_mod.set_display_cursor(screen_state, ccol - 1, crow - 1)
            else
                cursor_seq = ansi.cursorHide()
                screen_mod.set_display_cursor(screen_state, -1, -1)
            end
        end

        -- Single write: BSU + diff + cursor + ESU. The terminal buffers
        -- everything until ESU, then refreshes atomically.
        if interactive and (#diff > 0 or #cursor_seq > 0) then
            terminal.write(ansi.beginSyncUpdate() .. diff .. cursor_seq .. ansi.endSyncUpdate())
        elseif #diff > 0 then
            terminal.write(diff)
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
            terminal = terminal,
        }
    end)

    -- Teardown: run cleanups on all live instances.
    reconciler.shutdown(rec_state)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()

    -- Restore terminal state regardless of error.
    if interactive then
        terminal.write(ansi.cursorShow() .. "\n")
    end
    terminal.set_raw(false)

    if not ok then error(err) end
end

return M
