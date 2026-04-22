-- tui/testing/bare.lua — bare reconciler harness (no layout/screen).
--
-- Lightweight harness that only renders the reconciler tree without painting.
-- Used for tests that only care about hook/state behavior, not visual output.

local reconciler = require "tui.internal.reconciler"
local scheduler  = require "tui.internal.scheduler"
local input_mod = require "tui.internal.input"
local resize_mod = require "tui.internal.resize"
local focus_mod = require "tui.internal.focus"
local hooks     = require "tui.internal.hooks"
local tui_input = require "tui.input"
local capture   = require "tui.testing.capture"

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
    self._fake_now = self._fake_now + ms
    scheduler.step(self._fake_now)
end

function Bare:focus_id()   return focus_mod.get_focused_id() end
function Bare:focus_next() focus_mod.focus_next(); end
function Bare:focus_prev() focus_mod.focus_prev(); end
function Bare:focus(id)    focus_mod.focus(id); end

function Bare:tree()  return self._tree end
function Bare:state() return self._state end

function Bare:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    capture.drain_and_fatal_if_any()
end

--- Mount a bare reconciler harness.
function M.mount(App)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(true)
    local b = setmetatable({
        _App    = App,
        _state  = reconciler.new(),
        _tree   = nil,
        _dead   = false,
        _fake_now = 0,
        _render_count = 1,
    }, Bare)
    b._app_handle = { exit = function() b._dead = true end }
    scheduler.configure {
        now   = function() return b._fake_now end,
        sleep = function() end,
    }
    b._tree = reconciler.render(b._state, App, b._app_handle)
    return b
end

M.Bare = Bare
return M
