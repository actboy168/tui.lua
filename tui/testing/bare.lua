-- tui/testing/bare.lua — bare reconciler harness (no layout/screen).
--
-- Lightweight harness that only renders the reconciler tree without painting.
-- Used for tests that only care about hook/state behavior, not visual output.

local reconciler = require "tui.internal.reconciler"
local scheduler  = require "tui.internal.scheduler"
local hooks      = require "tui.internal.hooks"
local tui_input  = require "tui.input"
local app_base   = require "tui.internal.app_base"
local capture    = require "tui.testing.capture"
local vclock     = require "tui.testing.vclock"

local M = {}

local Bare = {}
Bare.__index = Bare

function Bare:rerender()
    if self._tree then self._tree = nil end
    self._render_count = (self._render_count or 0) + 1
    self._tree = reconciler.render(self._state, self._App, self._app_handle)
end

function Bare:render_count() return self._render_count or 0 end
function Bare:reset_render_count() self._render_count = 0; end

function Bare:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

function Bare:dispatch(bytes)
    tui_input.dispatch(bytes)
end

function Bare:type(str)
    tui_input.type(str)
end

function Bare:press(name)
    tui_input.press(name)
end

function Bare:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    vclock.advance(self._clock, ms)
    scheduler.step(self._clock.t)
end

function Bare:tree()  return self._tree end
function Bare:state() return self._state end

function Bare:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    app_base.reset_framework()
    hooks._set_dev_mode(false)
    capture.drain_and_fatal_if_any()
end

--- Mount a bare reconciler harness.
function M.mount(App)
    app_base.reset_framework()
    hooks._set_dev_mode(true)

    local clock = vclock.new(0)
    scheduler.configure(vclock.as_backend(clock))

    local b = setmetatable({
        _App    = App,
        _state  = reconciler.new(),
        _tree   = nil,
        _dead   = false,
        _clock  = clock,
        _render_count = 1,
    }, Bare)
    b._app_handle = { exit = function() b._dead = true end }
    b._tree = reconciler.render(b._state, App, b._app_handle)
    return b
end

M.Bare = Bare
return M
