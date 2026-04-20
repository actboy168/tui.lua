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

local element    = require "tui.internal.element"
local layout     = require "tui.internal.layout"
local renderer   = require "tui.internal.renderer"
local screen_mod = require "tui.internal.screen"
local reconciler = require "tui.internal.reconciler"
local scheduler  = require "tui.internal.scheduler"
local hooks      = require "tui.internal.hooks"
local input_mod  = require "tui.internal.input"
local resize_mod = require "tui.internal.resize"
local focus_mod  = require "tui.internal.focus"
local cursor_mod = require "tui.internal.cursor"
local ansi       = require "tui.internal.ansi"
local text_mod   = require "tui.internal.text"
local tui_core   = require "tui_core"

local terminal = tui_core.terminal

local M = {}
-- Pre-register in package.loaded so that circular requires from tui.extra.*
-- (which all do `require "tui"`) safely receive this table rather than
-- triggering a second load of this file.
package.loaded["tui"] = M

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

-- Host elements (core)
M.Box            = element.Box
M.Text           = element.Text
M.ErrorBoundary  = element.ErrorBoundary

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
M.usePaste       = hooks.usePaste
M.useFocus        = hooks.useFocus
M.useFocusManager = hooks.useFocusManager
M.useDeclaredCursor = cursor_mod.useDeclaredCursor
M.useMeasure     = hooks.useMeasure
M.useErrorBoundary = hooks.useErrorBoundary
M.useTerminalFocus = hooks.useTerminalFocus
M.useTerminalTitle = hooks.useTerminalTitle

-- Scheduler passthrough (users can bypass hooks if they really want to).
M.setInterval = scheduler.setInterval
M.setTimeout  = scheduler.setTimeout
M.clearTimer  = scheduler.clearTimer

-- Layout utilities
M.intrinsicSize = layout.intrinsic_size

-- Inline layout helpers (avoid requiring tui.extra for commonly used primitives).
--- Newline { count = n } — vertical spacer of n rows (default 1).
function M.Newline(t)
    t = t or {}
    local count = t.count or 1
    if count < 1 then count = 1 end
    return element.Box { key = t.key, height = count, flexShrink = 0 }
end

--- Spacer { } — flexible empty space that expands to fill the parent.
function M.Spacer(t)
    t = t or {}
    return element.Box { key = t.key, flexGrow = 1 }
end

-- Text utilities
M.iterChars     = text_mod.iterChars
M.displayWidth   = text_mod.display_width
M.wrap           = text_mod.wrap
M.wrapHard       = text_mod.wrap_hard
M.truncate       = text_mod.truncate
M.truncateStart  = text_mod.truncate_start
M.truncateMiddle = text_mod.truncate_middle


-- Cursor position is set by the focused component via cursor.set(col, row)
-- during render. We consume it here after layout (so coordinates are absolute).
-- Single-writer model: only one component sets the cursor per frame.
--
-- Fallback: if no component calls cursor.set(), we scan the tree for Text
-- elements with _cursor_offset (legacy TextInput behavior).
local function find_cursor(tree)
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

    layout.compute(tree, h)
    return tree
end

--- tui.render(root, opts)
-- Run the main loop with `root` as the top of the component tree. Blocks
-- until the app calls `useApp():exit()`, or an emergency key is received
-- (Ctrl+C / Ctrl+D — always honored by the framework).
--
-- opts (optional):
--   colorLevel  "16" | "256" | "truecolor"  — override auto-detected color level
function M.render(root, opts)
    opts = opts or {}
    local interactive = ansi.interactive()

    terminal.windows_vt_enable()
    terminal.set_raw(true)
    if interactive then
        terminal.write(ansi.cursorHide() .. ansi.enableBracketedPaste .. ansi.enableFocusEvents)
    end

    local rec_state    = reconciler.new()
    local init_w, init_h = terminal.get_size()
    local screen_state = screen_mod.new(init_w, init_h)

    -- Color level: auto-detect, then apply user override from opts.
    do
        local screen_c = tui_core.screen
        local level = ansi.color_level
        if opts.colorLevel == "16" then
            level = 0
        elseif opts.colorLevel == "256" then
            level = 1
        elseif opts.colorLevel == "truecolor" then
            level = 2
        end
        screen_c.set_color_level(screen_state, level)
    end

    if interactive then
        screen_mod.set_mode(screen_state, "main")
    end
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()

    local app_handle  = {
        exit = function() scheduler.stop() end,
    }

    -- Track last display cursor position for clean exit (see teardown below).
    local last_display_y = nil

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
            -- Guard: if the declared cursor row is outside the visible area
            -- (content taller than the terminal), treat it as hidden. Storing
            -- an out-of-bounds display_y would corrupt the next frame's preamble
            -- because the terminal clamps the physical cursor but diff_main
            -- calculates relative moves using the unclamped value.
            if ccol and crow and (crow - 1) < content_h then
                local cx, cy = screen_mod.cursor_pos(screen_state)
                local dx = (ccol - 1) - cx
                local dy = (crow - 1) - cy
                cursor_seq = ansi.cursorShow() .. ansi.cursorMove(dx, dy)
                screen_mod.set_display_cursor(screen_state, ccol - 1, crow - 1)
                last_display_y = crow - 1
            else
                cursor_seq = ansi.cursorHide()
                screen_mod.set_display_cursor(screen_state, -1, -1)
                last_display_y = nil
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
        -- The physical cursor is at the display cursor position (inside the
        -- Textarea/TextInput caret). Move it down to the bottom row of the
        -- rendered content (virt_y), go to column 0, then \n so the shell
        -- prompt appears cleanly below all TUI output.
        local move_seq = "\r"
        if last_display_y then
            local _, vy = screen_mod.cursor_pos(screen_state)
            local dy = vy - last_display_y
            if dy > 0 then
                move_seq = ansi.cursorDown(dy) .. "\r"
            end
        end
        terminal.write(ansi.disableBracketedPaste .. ansi.disableFocusEvents .. move_seq .. ansi.cursorShow() .. "\n")
    end
    terminal.set_raw(false)

    if not ok then error(err) end
end

-- Re-export tui.extra components so examples can use a single `require "tui"`
-- import. These are loaded last: by the time the extras do `require "tui"`,
-- all hooks and host elements are already in M (Lua stores the partial module
-- table in package.loaded before executing the body, so circular requires
-- safely return the in-progress table).
do
    local extra = require "tui.extra"
    M.TextInput   = extra.TextInput
    M.Textarea    = extra.Textarea
    M.Static      = extra.Static
    M.Select      = extra.Select
    M.Spinner     = extra.Spinner
    M.ProgressBar = extra.ProgressBar
end

return M
