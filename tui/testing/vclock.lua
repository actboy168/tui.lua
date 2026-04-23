-- tui/testing/vclock.lua — virtual clock for test harnesses.
--
-- Provides a deterministic, injectable time source that replaces the
-- production tui_core.time backend.  Follows the same "state + adapter"
-- pattern as vterm.lua:
--
--   local clock = vclock.new(0)            -- create state
--   scheduler.configure(vclock.as_backend(clock))  -- inject
--   vclock.advance(clock, 100)             -- tick forward
--   assert(vclock.now(clock) == 100)

local M = {}

--- Create a new virtual clock state object.
-- `now` is the initial time in milliseconds (default 0).
function M.new(now)
    return { t = now or 0 }
end

--- Return a scheduler-compatible backend table.
-- The returned { now, sleep } can be passed directly to
-- scheduler.configure().  Because `clock.t` is read on each
-- call (not captured as a value), subsequent advance() calls
-- are automatically visible.
function M.as_backend(clock)
    return {
        now   = function() return clock.t end,
        sleep = function() end,
    }
end

--- Advance the virtual clock by ms milliseconds.
function M.advance(clock, ms)
    assert(type(ms) == "number" and ms >= 0, "vclock.advance: non-negative ms required")
    clock.t = clock.t + ms
end

--- Get the current virtual time in milliseconds.
function M.now(clock)
    return clock.t
end

return M
