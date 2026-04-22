-- tui/internal/app.lua — production app loop.
--
-- Parallel to tui.testing.harness.lua: both call app_base.paint() for
-- rendering but differ in terminal (real vs vterm-backed) and scheduler
-- integration (scheduler.run vs harness loop_once).

local tui_core   = require "tui_core"
local terminal   = tui_core.terminal
local screen_mod = require "tui.internal.screen"
local reconciler = require "tui.internal.reconciler"
local scheduler  = require "tui.internal.scheduler"
local input_mod = require "tui.internal.input"
local hit_test  = require "tui.internal.hit_test"
local layout    = require "tui.internal.layout"
local ansi     = require "tui.internal.ansi"
local app_base = require "tui.internal.app_base"

local M = {}

local App = {}
App.__index = App

--- Run the production app loop and return an App object.
-- Non-blocking: sets up terminal and scheduler, returns immediately.
-- Call App:run() to start the blocking event loop.
function M.render(root, opts)
    opts = opts or {}

    terminal.windows_vt_enable()
    terminal.set_raw(true)

    local interactive = ansi.interactive()
    local use_kkp = opts.kitty_keyboard ~= nil and opts.kitty_keyboard or ansi.supports_kitty_keyboard

    app_base.setup_interactive(terminal.write, interactive, use_kkp)

    local w, h = terminal.get_size()
    local screen_state = screen_mod.new(w, h)

    local level = ansi.color_level
    if opts.colorLevel == "16" then level = 0
    elseif opts.colorLevel == "256" then level = 1
    elseif opts.colorLevel == "truecolor" then level = 2 end
    tui_core.screen.set_color_level(screen_state, level)

    if interactive then
        screen_mod.set_mode(screen_state, "main")
    end

    local rec_state = reconciler.new()
    app_base.reset_framework()

    local app_handle = { exit = function() scheduler.stop() end }

    local obj = setmetatable({
        _terminal   = terminal,
        _root       = root,
        _w          = w,
        _h          = h,
        _screen_state = screen_state,
        _rec_state  = rec_state,
        _app_handle = app_handle,
        _interactive = interactive,
        _use_kkp    = use_kkp,
        _running    = false,
        _render_count = 0,
        _tree       = nil,
        _mouse_auto_release = nil,
        _last_display_y = nil,
    }, App)

    local function paint(term)
        local tree, _, new_mouse = app_base.paint({
            rec_state        = rec_state,
            root             = root,
            app_handle       = app_handle,
            get_size         = terminal.get_size,
            screen           = screen_state,
            interactive      = interactive,
            write_fn         = terminal.write,
            on_cursor_move   = function(col, row)
                obj._last_display_y = row
            end,
            mouse_auto_release = obj._mouse_auto_release,
        })
        obj._mouse_auto_release = new_mouse
        hit_test.clear_tree()
        layout.free(tree)
    end

    app_base.setup_hit_test()

    obj._paint_fn = paint

    -- Initial paint.
    paint()

    return obj
end

--- Block and run the production event loop.
function App:run()
    if self._running then return end
    self._running = true

    local ok, err = pcall(function()
        scheduler.run {
            paint              = self._paint_fn,
            read               = self._terminal.read_raw,
            on_input           = function(s)
                local should_exit = input_mod.dispatch(s)
                scheduler.requestRedraw()
                return should_exit
            end,
            skip_initial_paint = true,
        }
    end)

    self:_teardown()
    self._running = false
    if not ok then error(err) end
end

function App:_teardown()
    reconciler.shutdown(self._rec_state)
    hit_test.clear_tree()
    self._mouse_auto_release = nil

    app_base.teardown_interactive(
        self._terminal.write,
        self._terminal.set_raw,
        self._interactive,
        self._use_kkp,
        self._screen_state,
        self._last_display_y
    )
end

function App:paint()      self._paint_fn() end

function App:rerender()
    scheduler.requestRedraw()
    scheduler.loop_once({
        read     = self._terminal.read_raw,
        on_input = function(s) return input_mod.dispatch(s) end,
        paint    = self._paint_fn,
        terminal = self._terminal,
    }, self._terminal, nil, true)
end

function App:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    scheduler._tick_and_paint({
        paint    = self._paint_fn,
        terminal = self._terminal,
    }, scheduler.now() + ms, true)
end

function App:resize(cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    self._w, self._h = cols, rows
end

function App:exit() scheduler.stop(); end

-- Feed simulated input bytes directly into the app's input pipeline.
-- Injects through scheduler so it integrates with the event loop.
function App:feed_input(bytes)
    if bytes and #bytes > 0 then
        local should_exit = input_mod.dispatch(bytes)
        scheduler.requestRedraw()
    end
end

function App:size()   return self._w, self._h end
function App:screen()  return self._screen_state end

return M
