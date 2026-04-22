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
local clipboard  = require "tui.internal.clipboard"
local hit_test   = require "tui.internal.hit_test"
local paint_frame = require "tui.internal.paint_frame"
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
M.useMouse         = hooks.useMouse
M.useClipboard     = hooks.useClipboard

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


--- tui.render(root, opts)
-- Run the main loop with `root` as the top of the component tree. Blocks
-- until the app calls `useApp():exit()`, or an emergency key is received
-- (Ctrl+C / Ctrl+D — always honored by the framework).
--
-- opts (optional):
--   colorLevel      "16" | "256" | "truecolor"  — override auto-detected color level
function M.render(root, opts)
    opts = opts or {}
    local interactive = ansi.interactive()

    -- Resolve whether Kitty Keyboard Protocol should be used.
    -- opts.kitty_keyboard = true  → force-enable (overrides detection)
    -- opts.kitty_keyboard = false → force-disable
    -- opts.kitty_keyboard = nil   → use auto-detected value
    local use_kkp
    if opts.kitty_keyboard ~= nil then
        use_kkp = opts.kitty_keyboard
    else
        use_kkp = ansi.supports_kitty_keyboard
    end

    terminal.windows_vt_enable()
    terminal.set_raw(true)
    if interactive then
        terminal.write(ansi.cursorHide() .. ansi.enableBracketedPaste .. ansi.enableFocusEvents)
        if use_kkp then
            terminal.write(ansi.kittyKeyboard.push)
        end
        -- Wire terminal.write as the mouse mode sequence emitter.
        -- Mouse modes are enabled on demand (ref-counted via request_mouse_level).
        input_mod.set_mouse_mode_writer(terminal.write)
        -- Enable OSC 52 clipboard and wire it to the terminal writer.
        clipboard.set_writer(terminal.write)
        clipboard._osc52_enabled = true
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

    -- Auto-enable mouse mode when the tree contains onClick/onScroll handlers.
    -- Managed as a persistent level-1 request that is held while any handler
    -- exists in the tree and released when none remain.
    local _mouse_auto_release = nil

    local function paint(term)
        local mouse_ref = { current = _mouse_auto_release }
        local tree, _ = paint_frame.frame {
            rec_state  = rec_state,
            root       = root,
            app_handle = app_handle,
            get_size   = terminal.get_size,
            screen     = screen_state,
            interactive = interactive,
            write_fn   = terminal.write,
            on_cursor_move = function(col, row) last_display_y = row end,
            mouse_auto_release = mouse_ref,
        }
        _mouse_auto_release = mouse_ref.current

        hit_test.clear_tree()
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

    -- Hit-test hook: called by input._process_event for mouse events
    -- before they are broadcast to useMouse subscribers.
    input_mod.set_hit_test_handler(function(ev)
        if ev.type == "down" and ev.button == 1 then
            return hit_test.dispatch_click(ev.x, ev.y)
        elseif ev.type == "scroll" then
            return hit_test.dispatch_scroll(ev.x, ev.y, ev.scroll)
        end
        return false
    end)

    local ok, err = pcall(function()
        scheduler._reset()
        scheduler.run {
            paint    = paint,
            read     = read,
            on_input = on_input,
            terminal = terminal,
        }
    end)

    -- Run cleanups on all live instances (useMouse components release their
    -- level refs here via useEffect cleanup, then _reset zeroes everything).
    reconciler.shutdown(rec_state)
    input_mod._reset()
    hit_test.clear_tree()
    _mouse_auto_release = nil  -- already released by _reset, just drop the ref
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
        if use_kkp then
            terminal.write(ansi.kittyKeyboard.pop)
        end
        -- Detach the mouse mode writer; mouse level is already 0 after releases above.
        input_mod.set_mouse_mode_writer(nil)
    end
    terminal.set_raw(false)
    -- Reset clipboard state so the module is clean for subsequent render() calls.
    clipboard._osc52_enabled = false

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
