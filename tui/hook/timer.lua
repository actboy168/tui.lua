-- tui/hook/timer.lua — timer and animation hooks.
--
-- useInterval, useTimeout, useAnimation.

local core      = require "tui.hook.core"
local state_mod = require "tui.hook.state"
local effect_mod = require "tui.hook.effect"

local M = {}

-- ---------------------------------------------------------------------------
-- Timer sugar (built on top of useEffect for cleanup)

function M.useInterval(fn, ms)
    local ref = state_mod.useLatestRef(fn)
    effect_mod.useEffect(function()
        local id = require("tui.internal.scheduler").setInterval(function() ref.current() end, ms)
        return function() require("tui.internal.scheduler").clearTimer(id) end
    end, { ms })
end

function M.useTimeout(fn, ms)
    local ref = state_mod.useLatestRef(fn)
    effect_mod.useEffect(function()
        local id = require("tui.internal.scheduler").setTimeout(function() ref.current() end, ms)
        return function() require("tui.internal.scheduler").clearTimer(id) end
    end, { ms })
end

-- ---------------------------------------------------------------------------
-- useAnimation(opts) -> { frame, time, delta, reset }
--
-- opts = {
--   interval = number ms (default 80),
--   isActive = bool    (default true),
-- }
--
-- A frame-ticking primitive for animated components (Spinner, ProgressBar,
-- marquee text, etc.). Every `interval` ms the hook bumps an internal tick
-- counter, which triggers a rerender; the returned values describe the
-- current tick relative to when animation last started.
--
--   frame : 0-based tick count since the last start / reset. Cycles
--           forever — consumers typically `frames[frame % N + 1]`.
--   time  : virtual ms elapsed since last start / reset, summed from the
--           actual deltas observed at each tick.
--   delta : virtual ms between this frame and the previous. First frame is
--           `interval`. Under a single `harness:advance(N)` that batch-
--           fires the timer multiple times, each firing reads scheduler.now()
--           to compute the real delta for that tick (catches up faithfully).
--   reset : stable fn () -> nil. Restarts counters; if isActive is true the
--           next tick fires `interval` ms later.
--
-- isActive=false pauses the timer AND freezes time/delta. Flipping back to
-- true resumes counting from the frozen values (off-interval does not
-- accumulate). For a cold restart, call reset() alongside the flip.
function M.useAnimation(opts)
    opts = opts or {}
    local interval = opts.interval or 80
    local isActive = opts.isActive
    if isActive == nil then isActive = true end

    local scheduler = require "tui.internal.scheduler"

    -- Persistent mutable snapshot. Using useRef (not useState) because the
    -- interval callback writes here *and* calls setTick to request a
    -- rerender; we don't want two setState writes per tick.
    local state = state_mod.useRef {
        frame     = 0,
        time      = 0,
        delta     = 0,
        last_tick = nil,  -- scheduler.now() when last tick fired; nil = none yet
    }

    -- Drives rerenders. The interval callback bumps this via setTick.
    local _tick, setTick = state_mod.useState(0)
    local function bump() setTick(function(v) return (v + 1) % 1e9 end) end

    -- Stable reset closure, installed once on mount.
    local reset_ref = state_mod.useRef(nil)
    if reset_ref.current == nil then
        reset_ref.current = function()
            state.current.frame     = 0
            state.current.time      = 0
            state.current.delta     = 0
            state.current.last_tick = nil
            bump()
        end
    end

    -- Install / tear down the interval based on isActive + interval.
    -- Deps = {interval, isActive}: toggling either restarts the timer.
    effect_mod.useEffect(function()
        if not isActive then return end
        -- Seed last_tick on (re)start so the first delta equals the interval
        -- rather than the potentially-large gap since last paint.
        state.current.last_tick = scheduler.now()
        local id = scheduler.setInterval(function()
            local now = scheduler.now()
            local prev = state.current.last_tick or (now - interval)
            local dt = now - prev
            if dt < 0 then dt = interval end  -- defensive: clock went backwards
            state.current.frame     = state.current.frame + 1
            state.current.delta     = dt
            state.current.time      = state.current.time + dt
            state.current.last_tick = now
            bump()
        end, interval)
        return function() scheduler.clearTimer(id) end
    end, { interval, isActive })

    return {
        frame = state.current.frame,
        time  = state.current.time,
        delta = state.current.delta,
        reset = reset_ref.current,
    }
end

return M
