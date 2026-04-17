-- tui/testing.lua — offscreen test harness for tui.lua.
--
-- This module exposes a small API that turns the framework's render/input/
-- timer loop into a step-driven rig suitable for unit tests. It replaces the
-- per-file `new_harness` helpers that each test module used to roll by hand.
--
-- USAGE
-- -----
--   local testing = require "tui.testing"
--
--   local h = testing.render(App, { cols = 40, rows = 10 })
--   h:type("hi"):press("enter")
--   h:advance(100)       -- drive timers forward 100ms of virtual time
--   h:resize(60, 20)
--   local frame = h:frame()
--   h:unmount()
--
-- For tests that only exercise reconciler/hooks without any layout concern,
-- use `testing.mount_bare(App)` instead — it skips layout + renderer and
-- exposes only :rerender / :dispatch / :unmount / :tree / :state.
--
-- CONCURRENCY WARNING
-- -------------------
-- `tui_core.terminal` is a **process-wide singleton**. `render()` replaces its
-- methods in place and `unmount()` restores them. This means you CANNOT have
-- two live `testing.render()` harnesses at once in the same process. ltest
-- currently runs tests serially so this is fine; if the runner ever goes
-- parallel, either add mutex in here or push the work upstream: make
-- `tui/init.lua`'s paint accept a `terminal` object so testing.lua can pass
-- a per-instance fake without global replacement. Tracked in roadmap.

local element    = require "tui.element"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local screen_mod = require "tui.screen"
local reconciler = require "tui.reconciler"
local scheduler  = require "tui.scheduler"
local input_mod  = require "tui.input"
local resize_mod = require "tui.resize"
local tui_core   = require "tui_core"

local M = {}

-- ---------------------------------------------------------------------------
-- Named-key table used by Harness:press(). Values are the raw byte sequences
-- that would come from a real terminal; input_mod.dispatch -> keys.parse
-- handles the parsing.

local KEYS = {
    enter     = "\r",
    ["return"] = "\r",
    escape    = "\27",
    esc       = "\27",
    tab       = "\t",
    backspace = "\127",
    up        = "\27[A",
    down      = "\27[B",
    right     = "\27[C",
    left      = "\27[D",
    home      = "\27[H",
    ["end"]   = "\27[F",
    delete    = "\27[3~",
    pageup    = "\27[5~",
    pagedown  = "\27[6~",
    f1        = "\27OP",
    f2        = "\27OQ",
    f3        = "\27OR",
    f4        = "\27OS",
}

-- Translate one key spec ("enter" / "left" / "ctrl+c") into raw bytes.
local function resolve_key(name)
    if type(name) ~= "string" or #name == 0 then
        error("press/keys: expected non-empty string, got " .. tostring(name), 3)
    end
    -- ctrl+<x> → C0 control byte (x - '`').
    local cx = name:match("^ctrl%+(.)$") or name:match("^%^(.)$")
    if cx then
        local b = cx:lower():byte()
        if b < 97 or b > 122 then
            error("press: ctrl+<letter> required, got " .. name, 3)
        end
        return string.char(b - 96)
    end
    local raw = KEYS[name:lower()]
    if not raw then
        error("press: unknown key '" .. name .. "'", 3)
    end
    return raw
end

-- ---------------------------------------------------------------------------
-- Terminal hijack guard. Only one live harness at a time owns the real
-- tui_core.terminal table.

local HIJACKED = false
local real_terminal = nil

local function hijack_terminal(fake)
    if HIJACKED then
        error("tui.testing: another harness is already active. Call :unmount() first.", 3)
    end
    real_terminal = {}
    for k, v in pairs(tui_core.terminal) do real_terminal[k] = v end
    for k, v in pairs(fake) do tui_core.terminal[k] = v end
    HIJACKED = true
end

local function restore_terminal()
    if not HIJACKED then return end
    -- Clear first so stale keys from fake don't persist if real had fewer.
    for k in pairs(tui_core.terminal) do tui_core.terminal[k] = nil end
    for k, v in pairs(real_terminal) do tui_core.terminal[k] = v end
    real_terminal = nil
    HIJACKED = false
end

-- ---------------------------------------------------------------------------
-- Harness metatable.

local Harness = {}
Harness.__index = Harness

-- Produce + commit one frame. Called internally by render / rerender /
-- type / press / advance / resize.
function Harness:_paint()
    -- Observe the (possibly changed) terminal size; triggers useWindowSize
    -- subscribers installed on prior renders.
    resize_mod.observe(self._w, self._h)

    local tree = reconciler.render(self._state, self._App, self._app_handle)
    if not tree then
        tree = element.Box { width = self._w, height = self._h }
    end
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = self._w end
        if tree.props.height == nil then tree.props.height = self._h end
    end

    layout.compute(tree)
    local rows = renderer.render_rows(tree, self._w, self._h)
    local ansi = screen_mod.diff(self._screen, rows, self._w, self._h)
    if #ansi > 0 then self._ansi_buf[#self._ansi_buf + 1] = ansi end

    -- Keep `tree` live for the caller (h:tree()) — don't layout.free it here,
    -- free on next paint or unmount.
    if self._tree then layout.free(self._tree) end
    self._tree = tree
    self._rows = rows
end

function Harness:rerender()
    self:_paint()
    return self
end

-- Read access.
function Harness:width()  return self._w end
function Harness:height() return self._h end
function Harness:rows()
    local out = {}
    for i, r in ipairs(self._rows or {}) do out[i] = r end
    return out
end
function Harness:row(n)   return (self._rows or {})[n] end
function Harness:frame()  return table.concat(self._rows or {}, "\n") end
function Harness:tree()   return self._tree end

function Harness:ansi()
    return table.concat(self._ansi_buf)
end
function Harness:clear_ansi()
    self._ansi_buf = {}
    return self
end

-- Driving.

function Harness:dispatch(bytes)
    if bytes and #bytes > 0 then
        input_mod.dispatch(bytes)
    end
    self:_paint()
    return self
end

function Harness:type(str)
    if type(str) ~= "string" then
        error("type: expected string, got " .. type(str), 2)
    end
    -- Feed character by character so each insertion gets its own render,
    -- matching real keyboard behavior (one keystroke at a time).
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n
        if b < 0x80     then n = 1
        elseif b < 0xC0 then n = 1             -- stray continuation; send as-is
        elseif b < 0xE0 then n = 2
        elseif b < 0xF0 then n = 3
        else                 n = 4 end
        local chunk = str:sub(i, i + n - 1)
        input_mod.dispatch(chunk)
        self:_paint()
        i = i + n
    end
    return self
end

function Harness:press(name)
    input_mod.dispatch(resolve_key(name))
    self:_paint()
    return self
end

-- Advance the virtual clock and fire due timers.
-- Mirrors the loop used in test_scheduler's tick_to() helper; repeats until
-- no more timers are due so that intervals can self-reschedule.
function Harness:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    local target = self._fake_now + ms
    self._fake_now = target
    local timers = scheduler._timers()
    local fired
    repeat
        fired = false
        for tid, t in pairs(timers) do
            if t.fire_at <= target then
                if t.interval then
                    t.fire_at = target + t.interval
                else
                    timers[tid] = nil
                end
                t.fn()
                fired = true
            end
        end
    until not fired
    self:_paint()
    return self
end

function Harness:resize(cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    self._w, self._h = cols, rows
    -- Invalidate screen so next diff produces full redraw; real tui/init does
    -- the same when resize fires.
    screen_mod.invalidate(self._screen)
    self:_paint()
    return self
end

function Harness:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    if self._tree then layout.free(self._tree); self._tree = nil end
    input_mod._reset()
    resize_mod._reset()
    scheduler._reset()
    restore_terminal()
end

-- ---------------------------------------------------------------------------
-- Public: full harness with layout + renderer.

--- tui.testing.render(App, opts) -> Harness
-- opts:
--   cols (default 80), rows (default 24)
--   now  (default 0) — virtual start time in milliseconds
function M.render(App, opts)
    opts = opts or {}
    local W    = opts.cols or 80
    local H    = opts.rows or 24
    local now0 = opts.now  or 0

    -- Isolated globals. Any leftover state from a previous (possibly
    -- unclean) harness is wiped.
    input_mod._reset()
    resize_mod._reset()
    scheduler._reset()

    local h = setmetatable({
        _App         = App,
        _w           = W,
        _h           = H,
        _fake_now    = now0,
        _ansi_buf    = {},
        _state       = reconciler.new(),
        _screen      = screen_mod.new(),
        _tree        = nil,
        _rows        = nil,
        _dead        = false,
        _ime         = nil,
    }, Harness)
    h._app_handle = { exit = function() h._dead = true end }

    -- Fake terminal bound to this harness.
    local fake = {
        get_size          = function() return h._w, h._h end,
        write             = function(s) h._ansi_buf[#h._ansi_buf + 1] = s end,
        read_raw          = function() return nil end,
        set_raw           = function() end,
        set_ime_pos       = function(c, r) h._ime = { col = c, row = r } end,
        windows_vt_enable = function() return true end,
    }
    hijack_terminal(fake)

    -- Virtual clock. Every call to scheduler.setTimeout / setInterval reads
    -- `now` immediately to compute fire_at, so we must install this BEFORE
    -- the first render runs effects.
    scheduler.configure {
        now   = function() return h._fake_now end,
        sleep = function() end,
    }

    -- Initial paint — installs subscriptions, runs mount-effects.
    h:_paint()
    return h
end

-- ---------------------------------------------------------------------------
-- Public: bare mode — reconciler + hooks only, no layout/renderer/screen.
-- For unit tests of hooks & component identity.

local Bare = {}
Bare.__index = Bare

function Bare:rerender()
    if self._tree then self._tree = nil end
    self._tree = reconciler.render(self._state, self._App, self._app_handle)
    return self
end

function Bare:dispatch(bytes)
    if bytes and #bytes > 0 then input_mod.dispatch(bytes) end
    return self
end

function Bare:tree()  return self._tree end
function Bare:state() return self._state end

function Bare:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    input_mod._reset()
    resize_mod._reset()
    scheduler._reset()
end

--- tui.testing.mount_bare(App) -> BareHarness
-- Minimal rig for reconciler/hooks tests. Does NOT hijack the terminal, does
-- NOT run layout or renderer.
function M.mount_bare(App)
    input_mod._reset()
    resize_mod._reset()
    scheduler._reset()
    scheduler.configure {
        now   = function() return 0 end,
        sleep = function() end,
    }
    local b = setmetatable({
        _App         = App,
        _state       = reconciler.new(),
        _tree        = nil,
        _dead        = false,
    }, Bare)
    b._app_handle = { exit = function() b._dead = true end }
    b._tree = reconciler.render(b._state, App, b._app_handle)
    return b
end

-- Handy tree-walker exported for tests that need to locate a Text node by
-- its _cursor_offset marker (TextInput-tagged nodes).
function M.find_text_with_cursor(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "text" and e._cursor_offset ~= nil then return e end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c); if r then return r end
        end
    end
    return walk(tree)
end

return M
