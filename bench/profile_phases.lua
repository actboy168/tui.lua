-- Simple instrumented benchmark: per-phase timing within the normal loop.
-- time.monotonic() returns milliseconds.
local element    = require "tui.element"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local screen_mod = require "tui.screen"
local reconciler = require "tui.reconciler"
local tui        = require "tui"
local time       = require "bee.time"

local function App()
    return tui.Text { string.rep("hello world ", 100) }
end

local state  = reconciler.new()
local ah     = {}
local screen = screen_mod.new(40, 24)

local function one_frame()
    local t = reconciler.render(state, App, ah)
    if not t then t = element.Box {} end
    if t.kind == "box" then
        t.props = t.props or {}
        t.props.width  = t.props.width  or 40
        t.props.height = t.props.height or 24
    end
    layout.compute(t)
    screen_mod.clear(screen)
    renderer.paint(t, screen)
    screen_mod.diff(screen)
end

-- warm up
for i = 1, 50 do one_frame() end

-- Instrument individual phases inline (accurate per-phase breakdown).
local t_reconcile, t_layout, t_clear, t_render, t_diff = 0, 0, 0, 0, 0
local N = 20000
collectgarbage("collect")
for i = 1, N do
    local t0

    t0 = time.monotonic()
    local t = reconciler.render(state, App, ah)
    if not t then t = element.Box {} end
    if t.kind == "box" then
        t.props = t.props or {}
        t.props.width  = t.props.width  or 40
        t.props.height = t.props.height or 24
    end
    t_reconcile = t_reconcile + (time.monotonic() - t0)

    t0 = time.monotonic()
    layout.compute(t)
    t_layout = t_layout + (time.monotonic() - t0)

    t0 = time.monotonic()
    screen_mod.clear(screen)
    t_clear = t_clear + (time.monotonic() - t0)

    t0 = time.monotonic()
    renderer.paint(t, screen)
    t_render = t_render + (time.monotonic() - t0)

    t0 = time.monotonic()
    screen_mod.diff(screen)
    t_diff = t_diff + (time.monotonic() - t0)
end

local function us(ms) return string.format("%.2f us", ms / N * 1000) end
print("reconcile:  " .. us(t_reconcile))
print("layout:     " .. us(t_layout))
print("clear:      " .. us(t_clear))
print("render:     " .. us(t_render))
print("diff:       " .. us(t_diff))
print("total:      " .. us(t_reconcile + t_layout + t_clear + t_render + t_diff))
