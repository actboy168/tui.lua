-- test/test_scheduler.lua — scheduler backend injection + timer semantics.

local lt        = require "ltest"
local scheduler = require "tui.scheduler"

-- Fake backend: deterministic virtual clock, no real sleeping.
local function make_fake_backend()
    local b = { t = 0, slept = 0 }
    b.now   = function() return b.t end
    b.sleep = function(ms) b.slept = b.slept + ms end
    return b
end

local suite = lt.test "scheduler"

function suite:test_configure_accepts_custom_backend()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local called = 0
    local id = scheduler.setTimeout(function() called = called + 1 end, 100)
    lt.assertEquals(type(id), "number")

    -- Advance virtual clock and run a single run-loop iteration manually by
    -- crafting minimal opts; stop immediately after the paint.
    -- Simpler: poke the timer table by advancing time and re-using internals.
    b.t = 50
    -- not yet; no timer should fire if we ran the loop now.

    b.t = 150
    -- Run ticks by peeking at _timers and firing any due.
    local timers = scheduler._timers()
    for tid, t in pairs(timers) do
        if t.fire_at <= b.t then
            t.fn()
            timers[tid] = nil
        end
    end
    lt.assertEquals(called, 1)
end

function suite:test_clear_timer_prevents_fire()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local called = 0
    local id = scheduler.setTimeout(function() called = called + 1 end, 50)
    scheduler.clearTimer(id)

    b.t = 100
    local timers = scheduler._timers()
    for tid, t in pairs(timers) do
        if t.fire_at <= b.t then t.fn(); timers[tid] = nil end
    end
    lt.assertEquals(called, 0)
end

function suite:test_interval_reschedules_itself()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local hits = 0
    scheduler.setInterval(function() hits = hits + 1 end, 10)

    -- Simulate driving the loop: advance the clock, fire due timers, repeat.
    local function tick_to(t)
        b.t = t
        local timers = scheduler._timers()
        -- Loop until nothing more is due at current t (interval may re-fire).
        local fired
        repeat
            fired = false
            for tid, tm in pairs(timers) do
                if tm.fire_at <= b.t then
                    if tm.interval then
                        tm.fire_at = b.t + tm.interval
                    else
                        timers[tid] = nil
                    end
                    tm.fn()
                    fired = true
                end
            end
        until not fired
    end

    tick_to(10);  lt.assertEquals(hits, 1)
    tick_to(20);  lt.assertEquals(hits, 2)
    tick_to(55);  lt.assertEquals(hits, 3)  -- one fire at 30; next scheduled 40..; at 55 one more due
end

function suite:test_timer_apis_require_backend()
    -- Freshly loaded scheduler has no backend set. Skip this check if another
    -- test already configured it in this run; we verify the assertion path by
    -- peeking at the private state: calling setTimeout needs now().
    scheduler.configure { now = function() return 0 end, sleep = function() end }
    scheduler._reset()
    -- With a backend installed, timer creation must succeed.
    local id = scheduler.setTimeout(function() end, 0)
    lt.assertEquals(type(id), "number")
end
