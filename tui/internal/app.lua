-- tui/internal/app.lua — production app loop.
--
-- Parallel to tui.testing.harness.lua: both call app_base.mount() for
-- initialization but differ in terminal (real vs vterm-backed) and scheduler
-- integration (scheduler.run vs harness loop_once).

local tui_core     = require "tui.core"
local terminal     = tui_core.terminal
local scheduler    = require "tui.internal.scheduler"
local terminal_mod = require "tui.internal.terminal"
local app_base     = require "tui.internal.app_base"
local log_bar      = require "tui.internal.log_bar"

local M = {}

local App = {}
App.__index = App

--- Run the production app loop and return an App object.
-- Non-blocking: sets up terminal and scheduler, returns immediately.
-- Call App:run() to start the blocking event loop.
function M.render(root, opts)
    opts = opts or {}

    terminal.init()
    terminal.set_raw(true)

    local caps = terminal_mod.detect_capabilities()
    local interactive = terminal_mod.interactive()
    local use_kkp = opts.kitty_keyboard ~= nil and opts.kitty_keyboard or caps.kitty_keyboard

    local w, h = terminal.get_size()
    local screen_state = tui_core.screen.new(w, h)

    local level = caps.color_level
    if opts.colorLevel == "16" then level = 0
    elseif opts.colorLevel == "256" then level = 1
    elseif opts.colorLevel == "truecolor" then level = 2 end
    tui_core.screen.set_color_level(screen_state, level)

    local inst = app_base.mount(terminal, screen_state, {
        root           = root,
        app_handle     = { exit = function() scheduler.stop() end },
        capabilities   = caps,
        interactive    = interactive,
        use_kkp        = use_kkp,
        throw_on_error = false,
        extension      = log_bar,
    })

    inst._running = false

    return setmetatable(inst, App)
end

--- Block and run the production event loop.
function App:run()
    if self._running then return end
    self._running = true

    local ok, err = pcall(function()
        self._scheduler_opts.skip_initial_paint = true
        scheduler.run(self._scheduler_opts)
        self._scheduler_opts.skip_initial_paint = nil
    end)

    app_base.unmount(self)
    self._running = false
    if not ok then error(err) end
end

function App:rerender()
    app_base.rerender(self, nil, true)
end

function App:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    app_base.advance(self, function() return scheduler.now() + ms end)
end

function App:resize(cols, rows)
    app_base.resize(self, cols, rows)
end

function App:exit() scheduler.stop(); end

function App:size()   return app_base.size(self) end
function App:screen() return app_base.screen(self) end

return M
