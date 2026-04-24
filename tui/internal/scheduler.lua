-- tui/scheduler.lua — minimal main loop for Stage 2.
--
-- Responsibilities:
--   * keep a list of active timers (setInterval/setTimeout)
--   * drive a render loop with a dirty flag + frame-rate cap
--   * poll non-blocking input each tick and forward bytes to a handler
--
-- PLATFORM INDEPENDENCE
-- ---------------------
-- This module ships with built-in defaults from tui_core.time so it
-- works out of the box.  The backend can still be overridden via configure():
--
--   scheduler.configure {
--       now   = function() return <monotonic time in milliseconds (number)> end,
--       sleep = function(ms) ... end,   -- yield/block for ms milliseconds
--   }
--
-- Production integrators (ltask / libuv / custom event loop) should call
-- configure() with their own implementations before tui.render.

local tui_core = require "tui.core"

local M = {}

-- ---------------------------------------------------------------------------
-- Backend (injectable; defaults to tui_core.time)

local backend = {
    now   = tui_core.time.now,
    sleep = tui_core.time.sleep,
}

function M.configure(opts)
    assert(type(opts) == "table", "scheduler.configure: opts table required")
    if opts.now   ~= nil then backend.now   = opts.now   end
    if opts.sleep ~= nil then backend.sleep = opts.sleep end
end

local function now_ms()
    return backend.now()
end

local function sleep_ms(ms)
    backend.sleep(ms)
end

-- ---------------------------------------------------------------------------
-- Internal state (one global loop — Stage 2 runs a single tui.render at a time)

local timers        = {}    -- id -> { fire_at, interval, fn }
local next_timer_id = 1
local dirty         = true  -- force first paint
local running       = false
local last_frame    = 0    -- timestamp of last paint (updated by loop_once and run)
local <const> frame_ms      = 16    -- ~60 fps cap
local <const> input_poll_ms = 8     -- how often to look at stdin

-- ---------------------------------------------------------------------------
-- Public timer API

local function add_timer(delay_ms, interval_ms, fn)
    local id = next_timer_id
    next_timer_id = next_timer_id + 1
    timers[id] = {
        fire_at  = now_ms() + delay_ms,
        interval = interval_ms,  -- nil for one-shot
        fn       = fn,
    }
    return id
end

function M.setTimeout(fn, ms)
    return add_timer(ms, nil, fn)
end

function M.setInterval(fn, ms)
    return add_timer(ms, ms, fn)
end

function M.clearTimer(id)
    timers[id] = nil
end

-- ---------------------------------------------------------------------------
-- Dirty flag + stop

function M.requestRedraw()
    dirty = true
end

-- Public monotonic clock. Delegates to the configured backend so tests
-- running under harness get the virtual clock and production code gets
-- real time. Useful for hooks that need to compute real elapsed deltas
-- (useAnimation) independent of timer firing schedule.
function M.now()
    return now_ms()
end

function M.stop()
    running = false
end

-- Start the scheduler loop. Called by the test harness after mount so that
-- loop_once() can process iterations. The harness calls stop() at unmount.
-- The dirty flag is cleared here because mount already performed the initial
-- paint via _paint() (bypassing the scheduler), so the first loop_once iteration
-- should not repaint.
function M.start()
    running = true
    last_frame = 0
    dirty = false
end

-- ---------------------------------------------------------------------------
-- Internal: process pending timers; returns true if any fired.
--
-- Semantics: one-shots fire once and are removed; intervals self-catch-up
-- via fire_at+=interval so that a large step (e.g. testing:advance(N) with
-- N >> interval) fires the interval the appropriate number of times in one
-- call. Callbacks may mutate the timers table (add/remove); we iterate by
-- snapshotting ids per outer pass and re-check each timer's live state.

local function tick_timers(now)
    local fired = false
    local ids = {}
    for id in pairs(timers) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local t = timers[id]
        -- Fire all due iterations for this timer. One-shots loop at most
        -- once; intervals loop until fire_at passes `now`.
        while t and t.fire_at <= now do
            if t.interval then
                t.fire_at = t.fire_at + t.interval
            else
                timers[id] = nil
            end
            t.fn()
            fired = true
            t = timers[id]   -- may be nil if fn() called clearTimer(id)
        end
    end
    return fired
end

-- Public: advance time to `now` (absolute ms on the configured clock) and
-- fire all due timers. Used by tui.testing:advance and by external event
-- loops that want to drive the scheduler's timer wheel without running the
-- full run() loop.
--
-- Callers are responsible for keeping the backend's `now` function in sync
-- with the `now` passed here — otherwise a subsequent setInterval(fn, ms)
-- will compute fire_at off the backend's idea of time and drift from the
-- caller's. The testing harness does this by configuring now = function()
-- return h._fake_now end; production integrators using step() manually
-- should take the same care.
function M.step(now)
    tick_timers(now)
end

-- ---------------------------------------------------------------------------
-- Run loop
--
-- opts = {
--   onInput = function(str)  -- called with each non-empty read batch
--                             -- return true to stop the loop
--   read     = function() -> string|nil   -- non-blocking stdin read
--   paint    = function(terminal)  -- called whenever a repaint should happen;
--                                   -- receives the terminal object so callers can
--                                   -- pass a real or fake terminal without global
--                                   -- replacement (eliminates the tui_core.terminal
--                                   -- singleton hijack that testing.harness used to need)
--   terminal = <terminal object>  -- passed as first arg to paint
-- }

-- Do one iteration of the run loop: read → onInput → tick_timers →
-- paint if dirty and frame_ms has elapsed (or immediately if immediate=true).
-- Exposed so the test harness can simulate one iteration after injecting
-- input via h:dispatch, going through the full production code path.
function M.loop_once(opts, terminal, now, immediate)
    now = now or now_ms()

    -- Input: forward raw bytes; handler can stop loop by returning true.
    if opts.read then
        local s = opts.read()
        if s and #s > 0 and opts.onInput then
            if opts.onInput(s) then
                running = false
                return false
            end
        end
    end

    -- Timers.
    tick_timers(now)

    -- Repaint if dirty and a frame worth of time has elapsed (or immediately
    -- for harness:immediate mode that bypasses frame throttle).
    local elapsed = now - last_frame
    if dirty and (immediate or elapsed >= frame_ms) then
        dirty = false
        opts.paint(terminal)
        last_frame = now
    end

    return running
end

function M.run(opts)
    assert(opts and opts.paint and opts.read, "scheduler.run requires paint+read")
    local terminal = opts.terminal
    running = true
    last_frame = 0

    -- Initial paint so the screen isn't blank before first event.
    if not opts.skip_initial_paint then
        dirty = false
        opts.paint(terminal)
        last_frame = now_ms()
    end

    while running do
        local now = now_ms()

        -- Input: forward raw bytes; handler can stop loop by returning true.
        if opts.read then
            local s = opts.read()
            if s and #s > 0 and opts.onInput then
                if opts.onInput(s) then
                    running = false
                    break
                end
            end
        end

        -- Timers.
        if tick_timers(now) then
            -- Timer callbacks may have flipped dirty via requestRedraw.
        end

        -- Repaint if dirty and a frame worth of time has elapsed (or immediately).
        local elapsed = now - last_frame
        if dirty and (opts.immediate or elapsed >= frame_ms) then
            dirty = false
            opts.paint(terminal)
            last_frame = now
        end

        sleep_ms(input_poll_ms)
    end
end

-- Expose for tests / introspection.
function M._timers() return timers end
function M._reset()
    timers = {}
    next_timer_id = 1
    dirty = true
    running = false
end

return M
