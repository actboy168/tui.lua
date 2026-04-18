-- test/test_use_animation.lua — useAnimation hook behavior.

local lt        = require "ltest"
local tui       = require "tui"
local testing   = require "tui.testing"
local scheduler = require "tui.scheduler"

local suite = lt.test "use_animation"

-- Helper: count live timers (harness configures fake clock; scheduler._timers
-- is a dict keyed by numeric id).
local function timer_count()
    local n = 0
    for _ in pairs(scheduler._timers()) do n = n + 1 end
    return n
end

-- Initial frame is 0, time is 0, delta is 0 before any tick has fired.
function suite:test_initial_snapshot()
    local seen
    local function App()
        seen = tui.useAnimation { interval = 100 }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    lt.assertEquals(seen.frame, 0)
    lt.assertEquals(seen.time, 0)
    lt.assertEquals(seen.delta, 0)
    lt.assertEquals(type(seen.reset), "function")
    h:unmount()
end

-- advance(interval) fires one tick: frame++, delta=interval, time=interval.
function suite:test_tick_advances_frame_and_time()
    local snaps = {}
    local function App()
        snaps[#snaps + 1] = tui.useAnimation { interval = 100 }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:advance(100)
    local last = snaps[#snaps]
    lt.assertEquals(last.frame, 1)
    lt.assertEquals(last.delta, 100)
    lt.assertEquals(last.time, 100)
    h:advance(100)
    last = snaps[#snaps]
    lt.assertEquals(last.frame, 2)
    lt.assertEquals(last.time, 200)
    h:unmount()
end

-- A batch advance across multiple intervals fires the interval the full
-- number of times in one call (scheduler.step catches up).
function suite:test_batch_advance_accumulates_deltas()
    local seen
    local function App()
        seen = tui.useAnimation { interval = 50 }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:advance(250)
    -- 5 ticks should have fired at t=50,100,150,200,250.
    lt.assertEquals(seen.frame, 5)
    lt.assertEquals(seen.time, 250)
    h:unmount()
end

-- isActive=false installs no timer and freezes frame/time.
function suite:test_inactive_freezes()
    local seen
    local function App()
        seen = tui.useAnimation { interval = 100, isActive = false }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    lt.assertEquals(timer_count(), 0)
    h:advance(500)
    lt.assertEquals(seen.frame, 0)
    lt.assertEquals(seen.time, 0)
    h:unmount()
end

-- Toggling isActive off/on restarts the timer but preserves frozen counters.
function suite:test_toggle_active_preserves_counters()
    local seen
    local active = true
    local function App()
        seen = tui.useAnimation { interval = 100, isActive = active }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:advance(200)
    lt.assertEquals(seen.frame, 2)
    lt.assertEquals(seen.time, 200)

    active = false
    h:rerender()
    lt.assertEquals(timer_count(), 0)
    h:advance(500)   -- no-op for the hook
    lt.assertEquals(seen.frame, 2)
    lt.assertEquals(seen.time, 200)

    active = true
    h:rerender()
    -- Timer re-armed; first tick lands `interval` ms after the resume point.
    h:advance(100)
    lt.assertEquals(seen.frame, 3)
    -- After the off-period (500ms) + 100ms resume, the first tick's delta
    -- equals the 100ms window since re-seeding last_tick, so time grows by
    -- 100 — the 500ms off-period does NOT accumulate.
    lt.assertEquals(seen.time, 300)
    h:unmount()
end

-- reset() zeros the counters and schedules a rerender.
function suite:test_reset_clears_counters()
    local seen
    local function App()
        seen = tui.useAnimation { interval = 100 }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:advance(300)
    lt.assertEquals(seen.frame, 3)

    seen.reset()
    h:rerender()
    lt.assertEquals(seen.frame, 0)
    lt.assertEquals(seen.time, 0)
    lt.assertEquals(seen.delta, 0)
    -- Ticking resumes from zero.
    h:advance(100)
    lt.assertEquals(seen.frame, 1)
    h:unmount()
end

-- reset identity is stable across rerenders (safe to put in deps).
function suite:test_reset_identity_stable()
    local resets = {}
    local function App()
        local a = tui.useAnimation { interval = 100 }
        resets[#resets + 1] = a.reset
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:rerender()
    h:rerender()
    lt.assertEquals(rawequal(resets[1], resets[2]), true)
    lt.assertEquals(rawequal(resets[2], resets[3]), true)
    h:unmount()
end

-- Changing interval restarts the timer with the new cadence.
function suite:test_interval_change_restarts_timer()
    local seen
    local interval_v = 100
    local function App()
        seen = tui.useAnimation { interval = interval_v }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    h:advance(100)
    lt.assertEquals(seen.frame, 1)

    interval_v = 50
    h:rerender()
    -- After restart, first tick of the new interval fires at +50ms.
    h:advance(50)
    lt.assertEquals(seen.frame, 2)
    h:advance(50)
    lt.assertEquals(seen.frame, 3)
    h:unmount()
end

-- Unmount clears the interval timer — no lingering in scheduler._timers.
function suite:test_unmount_clears_timer()
    local function App()
        tui.useAnimation { interval = 100 }
        return tui.Text { "" }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    lt.assertEquals(timer_count(), 1)
    h:unmount()
    lt.assertEquals(timer_count(), 0)
end
