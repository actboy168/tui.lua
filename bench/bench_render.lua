-- bench/bench_render.lua — end-to-end frame time benchmarks.
--
-- Measures the full render pipeline (reconciler → layout → paint → diff)
-- using the offscreen test harness. Each scenario runs multiple rounds of
-- N iterations and reports trimmed-mean frame time with stddev across rounds.
--
-- Can be used as a module:
--   local bench = require "bench.bench_render"; local results = bench.run{...}

local testing = require "tui.testing"
local tui     = require "tui"
local time    = require "bee.time"

-- ---------------------------------------------------------------------------
-- Statistics
-- ---------------------------------------------------------------------------

local function sorted_copy(t)
    local s = {}
    for i = 1, #t do s[i] = t[i] end
    table.sort(s)
    return s
end

local function mean(t)
    local sum = 0
    for i = 1, #t do sum = sum + t[i] end
    return sum / #t
end

local function stddev(t, m)
    if #t < 2 then return 0 end
    m = m or mean(t)
    local sum = 0
    for i = 1, #t do
        local d = t[i] - m
        sum = sum + d * d
    end
    return math.sqrt(sum / (#t - 1))
end

-- Trimmed mean: discard the lowest and highest `trim_frac` fraction of
-- samples (e.g. 0.1 = discard top 10% and bottom 10%). At least 3 samples
-- must remain; if the sample count is too small, falls back to full mean.
local function trimmed_mean(t, trim_frac)
    local s = sorted_copy(t)
    local n = #s
    local drop = math.floor(n * trim_frac + 0.5)
    -- Keep at least 3 samples.
    if n - 2 * drop < 3 then drop = math.max(0, (n - 3) // 2) end
    local trimmed = {}
    for i = 1 + drop, n - drop do
        trimmed[#trimmed + 1] = s[i]
    end
    return mean(trimmed)
end

-- ---------------------------------------------------------------------------
-- Timing
-- ---------------------------------------------------------------------------

-- Run one round of n iterations, return total time in ms.
local function bench_round(h, n)
    local start = time.monotonic()
    for _ = 1, n do
        h:rerender()
    end
    return time.monotonic() - start
end

-- Run multiple rounds, collect per-round average frame times.
-- Returns trimmed mean + stddev of the per-round averages.
local function bench_run(h, n, rounds)
    -- Warm up: one extra render to prime JIT / caches.
    h:rerender()

    local avgs = {}  -- average frame time per round (seconds)
    for _ = 1, rounds do
        collectgarbage("collect")
        local total_ms = bench_round(h, n)
        avgs[#avgs + 1] = (total_ms / 1000) / n
    end

    local tm  = trimmed_mean(avgs, 0.1)
    local sd  = stddev(avgs, tm)
    return {
        iterations = n * rounds,
        mean_s     = tm,
        stddev_s   = sd,
        ops_per_s  = 1 / tm,
        -- Raw samples for advanced external analysis.
        samples    = avgs,
    }
end

-- ---------------------------------------------------------------------------
-- Scenarios
-- ---------------------------------------------------------------------------

local scenarios = {}

-- 1. N-layer nested Box
--    Stress-tests reconciler recursion + Yoga layout depth.
scenarios["nested_box_10"] = {
    build = function()
        local function App()
            local inner = tui.Text { key = "leaf", "leaf" }
            for i = 1, 10 do
                local child = inner
                inner = tui.Box { key = "b"..i, child }
            end
            return inner
        end
        return App
    end,
}

scenarios["nested_box_50"] = {
    build = function()
        local function App()
            local inner = tui.Text { key = "leaf", "leaf" }
            for i = 1, 50 do
                local child = inner
                inner = tui.Box { key = "b"..i, child }
            end
            return inner
        end
        return App
    end,
}

scenarios["nested_box_100"] = {
    build = function()
        local function App()
            local inner = tui.Text { key = "leaf", "leaf" }
            for i = 1, 100 do
                local child = inner
                inner = tui.Box { key = "b"..i, child }
            end
            return inner
        end
        return App
    end,
}

-- 2. Wide text wrap
--    Stress-tests C text.wrap + screen cell writes.
scenarios["text_wrap_short"] = {
    iter_scale = 5,  -- very fast; needs more iters for reliable timing
    build = function()
        local function App()
            return tui.Text { string.rep("hello world ", 10) }
        end
        return App
    end,
    opts = { cols = 40, rows = 24 },
}

scenarios["text_wrap_long"] = {
    build = function()
        local function App()
            return tui.Text { string.rep("hello world ", 100) }
        end
        return App
    end,
    opts = { cols = 40, rows = 24 },
}

-- 3. Many leaf Text nodes (wide tree)
--    Stress-tests diff + paint traversal over many siblings.
scenarios["wide_tree_50"] = {
    build = function()
        local function App()
            local children = {}
            for i = 1, 50 do
                children[i] = tui.Text { key = "t"..i, "T" .. i }
            end
            return tui.Box {
                flexDirection = "row",
                table.unpack(children),
            }
        end
        return App
    end,
}

scenarios["wide_tree_200"] = {
    build = function()
        local function App()
            local children = {}
            for i = 1, 200 do
                children[i] = tui.Text { key = "t"..i, "T" .. i }
            end
            return tui.Box {
                flexDirection = "row",
                table.unpack(children),
            }
        end
        return App
    end,
}

-- 4. Frequent setState (rerender storm)
--    Stress-tests reconciler diff + scheduler stabilisation.
scenarios["state_update"] = {
    iter_scale = 5,  -- very fast; needs more iters for reliable timing
    build = function()
        local function App()
            local count, setCount = tui.useState(0)
            tui.useEffect(function()
                setCount(function(c) return c + 1 end)
            end, {})
            return tui.Text { "count=" .. count }
        end
        return App
    end,
    -- For this scenario we measure bare rerender (no state change driven
    -- by the loop itself; the component is already stable after mount).
}

-- 5. Static + dynamic mix
--    A realistic-ish UI: header (static) + body (dynamic count) + footer.
scenarios["mixed_ui"] = {
    build = function()
        local function App()
            local count, setCount = tui.useState(0)
            return tui.Box {
                flexDirection = "column",
                width = 80, height = 24,
                tui.Box {
                    key = "header",
                    borderStyle = "single",
                    tui.Text { "Header" },
                },
                tui.Box {
                    key = "body",
                    flexGrow = 1,
                    tui.Text { "Body: " .. count },
                },
                tui.Box {
                    key = "footer",
                    borderStyle = "single",
                    tui.Text { "Footer" },
                },
            }
        end
        return App
    end,
}

-- 6. Large screen (120x40)
--    Measures how screen size affects diff + ANSI output generation.
scenarios["large_screen"] = {
    build = function()
        local function App()
            local children = {}
            for i = 1, 20 do
                children[i] = tui.Text { key = "r"..i, "Row " .. i .. ": " .. string.rep("x", 60) }
            end
            return tui.Box {
                flexDirection = "column",
                table.unpack(children),
            }
        end
        return App
    end,
    opts = { cols = 120, rows = 40 },
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

local M = {}
M.scenarios = scenarios

function M.run(opts)
    opts = opts or {}
    local filter     = opts.filter
    local iterations = opts.iterations or 1000
    local rounds     = opts.rounds or 10

    local results = {}

    for name, scenario in pairs(scenarios) do
        if filter and not name:find(filter, 1, true) then
            goto continue
        end

        local App  = scenario.build()
        local sopts = scenario.opts or { cols = 80, rows = 24 }
        local h    = testing.harness(App, sopts)

        local n = iterations * (scenario.iter_scale or 1)
        local r = bench_run(h, n, rounds)
        r.name = name
        results[#results + 1] = r

        h:unmount()

        ::continue::
    end

    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end

return M
