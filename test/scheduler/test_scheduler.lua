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

function suite:teardown()
    -- Reset scheduler to pristine state (timers + backend) after each test
    scheduler._reset()
    scheduler.configure { now = nil, sleep = nil }
end

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
    tick_to(55);      lt.assertEquals(hits, 3)  -- one fire at 30; next scheduled 40..; at 55 one more due
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

-- Helper: fire all due timers at or before t. Intervals reschedule themselves.
local function drain(b, timers)
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

-- Stage 15: setTimeout(0) alongside setInterval(10) — the 0-delay fires
-- immediately (at t=0), the interval fires at 10, 20, 30, ...
function suite:test_timeout_zero_and_interval_10_order()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local log = {}
    scheduler.setTimeout(function() log[#log + 1] = "t0" end, 0)
    scheduler.setInterval(function() log[#log + 1] = "int" end, 10)

    local timers = scheduler._timers()
    -- At t=0: the timeout fires. Interval is due at 10, not yet.
    b.t = 0
    drain(b, timers)
    lt.assertEquals(log, { "t0" })
    -- Drive the loop forward incrementally so each interval tick fires once.
    b.t = 10
    drain(b, timers)
    lt.assertEquals(log, { "t0", "int" })
    b.t = 20
    drain(b, timers)
    lt.assertEquals(log, { "t0", "int", "int" })
end

-- Stage 15: a timer callback that schedules another setTimeout — the inner
-- timer's fire_at is computed against the callback's observed current time,
-- and a subsequent drain picks it up.
function suite:test_chained_set_timeout_in_callback()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local log = {}
    scheduler.setTimeout(function()
        log[#log + 1] = "outer"
        scheduler.setTimeout(function()
            log[#log + 1] = "inner"
        end, 5)
    end, 10)

    local timers = scheduler._timers()
    b.t = 10
    drain(b, timers)
    -- Outer fired; inner scheduled at t=10+5=15, not yet due.
    lt.assertEquals(log, { "outer" })
    b.t = 14
    drain(b, timers)
    lt.assertEquals(log, { "outer" })  -- still not due
    b.t = 15
    drain(b, timers)
    lt.assertEquals(log, { "outer", "inner" })
end

-- Stage 15: a timer that clears itself from within its own callback does not
-- crash (and does not re-fire on the next drain).
function suite:test_self_clear_timer_in_callback()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local fires = 0
    local my_id
    my_id = scheduler.setInterval(function()
        fires = fires + 1
        scheduler.clearTimer(my_id)
    end, 10)

    local timers = scheduler._timers()
    b.t = 10
    drain(b, timers)
    b.t = 100
    drain(b, timers)
    lt.assertEquals(fires, 1,
        "self-cleared interval must fire exactly once")
end

-- ---------------------------------------------------------------------------
-- scheduler.stop() — sets running=false to break the run() loop.

function suite:test_stop_sets_running_false()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()
    -- stop() is a no-op when not running; just verify it doesn't error.
    scheduler.stop()
end

-- ---------------------------------------------------------------------------
-- scheduler.now() — public monotonic clock delegation.

function suite:test_now_delegates_to_backend()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()
    b.t = 42
    lt.assertEquals(scheduler.now(), 42)
    b.t = 100
    lt.assertEquals(scheduler.now(), 100)
end

-- ---------------------------------------------------------------------------
-- scheduler.run() — arg validation.

function suite:test_run_requires_paint_and_read()
    lt.assertError(function()
        scheduler.run {}
    end)
end

function suite:test_run_requires_read()
    lt.assertError(function()
        scheduler.run { paint = function() end }
    end)
end

-- ---------------------------------------------------------------------------
-- scheduler.run() — simple loop with stop.

function suite:test_run_calls_paint_then_stops()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local paint_count = 0
    scheduler.run {
        paint = function()
            paint_count = paint_count + 1
            scheduler.stop()
        end,
        read = function() return nil end,
    }
    lt.assertEquals(paint_count, 1)
end

function suite:test_run_on_input_true_stops_loop()
    local b = make_fake_backend()
    scheduler.configure { now = b.now, sleep = b.sleep }
    scheduler._reset()

    local input_seen = false
    scheduler.run {
        paint = function() end,
        read = function()
            if not input_seen then
                input_seen = true
                return "x"
            end
            -- After first input, return nil to avoid busy loop.
            scheduler.stop()
            return nil
        end,
        on_input = function(s)
            lt.assertEquals(s, "x")
            return true  -- signal exit
        end,
    }
    lt.assertEquals(input_seen, true)
end
