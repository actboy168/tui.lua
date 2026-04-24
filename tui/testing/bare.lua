-- tui/testing/bare.lua — bare reconciler harness (no layout/screen).
--
-- Lightweight harness that only renders the reconciler tree without painting.
-- Used for tests that only care about hook/state behavior, not visual output.

local reconciler = require "tui.internal.reconciler"
local scheduler  = require "tui.internal.scheduler"
local hooks      = require "tui.hook.core"
local input_mod    = require "tui.internal.input"
local testing_input = require "tui.testing.input"
local app_base   = require "tui.internal.app_base"
local log_bar    = require "tui.internal.log_bar"
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
function Bare:reset_render_count() self._render_count = 0 end

function Bare:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

function Bare:dispatch(bytes)
    if not bytes or #bytes == 0 then return end
    input_mod.dispatch(bytes)
end

function Bare:type(str)
    if type(str) ~= "string" then error("type: expected string", 2) end
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n = b < 0x80 and 1 or b < 0xC0 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        self:dispatch(str:sub(i, i + n - 1))
        i = i + n
    end
end

function Bare:press(name)
    local raw = testing_input.resolve_key(name)
    if raw == nil then self:type(name); return end
    self:dispatch(raw)
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
    app_base.reset_framework(log_bar)
    hooks._set_dev_mode(false)
    capture.drain_and_fatal_if_any()
end

--- Mount a bare reconciler harness.
function M.mount(App)
    app_base.reset_framework(log_bar)
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

M.bare = M.mount

M.Bare = Bare
return M
