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
local scheduler  = require "tui.internal.scheduler"
local hooks      = require "tui.internal.hooks"
local cursor_mod = require "tui.internal.cursor"
local text_mod   = require "tui.internal.text"

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
    local app = require("tui.internal.app").render(root, opts)
    app:run()
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
