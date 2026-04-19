-- bench/run.lua — benchmark runner with baseline comparison.
--
-- Runs benchmarks, compares against saved baselines, and optionally
-- updates the baseline files.  Regression detection uses confidence-
-- interval overlap: a scenario is flagged only when the current mean
-- minus one stddev is still above the baseline mean plus one stddev
-- (i.e. the two distributions don't overlap at the 1-sigma level).
--
-- Usage:
--   luamake lua bench/run.lua                  # run + compare
--   luamake lua bench/run.lua --update         # run + update baselines
--   luamake lua bench/run.lua --filter nested  # run only matching scenarios
--   luamake lua bench/run.lua --iterations 500 # override iteration count
--   luamake lua bench/run.lua --rounds 20      # override round count
--   luamake lua bench/run.lua --threshold 0.3  # 30% regression threshold (default 0.25)

local json         = require "json"
local bench_render = require "bench.bench_render"

-- ---------------------------------------------------------------------------
-- CLI argument parsing
-- ---------------------------------------------------------------------------

local do_update   = false
local filter      = nil
local iterations  = 1000
local rounds      = 10
local threshold   = 0.25   -- 25% regression threshold

for i = 1, #arg do
    local a = arg[i]
    if a == "--update" then
        do_update = true
    elseif a == "--filter" and arg[i + 1] then
        filter = arg[i + 1]
    elseif a == "--iterations" and arg[i + 1] then
        iterations = tonumber(arg[i + 1]) or iterations
    elseif a == "--rounds" and arg[i + 1] then
        rounds = tonumber(arg[i + 1]) or rounds
    elseif a == "--threshold" and arg[i + 1] then
        threshold = tonumber(arg[i + 1]) or threshold
    end
end

-- ---------------------------------------------------------------------------
-- Baseline I/O
-- ---------------------------------------------------------------------------

local BASELINE_DIR = "bench/baselines"

local function baseline_path(name)
    return BASELINE_DIR .. "/" .. name .. ".json"
end

local function load_baseline(name)
    local path = baseline_path(name)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(json.decode, content)
    if not ok then return nil end
    return data
end

local function save_baseline(name, data)
    local path = baseline_path(name)
    local f = io.open(path, "w")
    if not f then
        io.stderr:write("[bench] cannot write " .. path .. "\n")
        return false
    end
    f:write(json.encode(data), "\n")
    f:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

local fmt = string.format

local function format_time(s)
    if s < 1e-6 then
        return fmt("%.2f ns", s * 1e9)
    elseif s < 1e-3 then
        return fmt("%.2f us", s * 1e6)
    elseif s < 1 then
        return fmt("%.3f ms", s * 1e3)
    else
        return fmt("%.3f s", s)
    end
end

local function format_pct(ratio)
    local pct = ratio * 100
    if pct >= 0 then
        return fmt("+%.1f%%", pct)
    else
        return fmt("%.1f%%", pct)
    end
end

-- ---------------------------------------------------------------------------
-- Regression detection
-- ---------------------------------------------------------------------------
-- A result is a REGRESSION when BOTH conditions hold:
--   1. The point estimate changed by more than `threshold` (e.g. 25%).
--   2. The 1-sigma confidence intervals do NOT overlap — meaning the
--      current mean minus 1 sigma is still above the baseline mean plus
--      1 sigma.  This filters out noise: if the distributions overlap
--      significantly, the change is not statistically meaningful even
--      if the point estimate shifted.
-- An IMPROVEMENT is the symmetric case on the fast side.
-- Otherwise the scenario is "ok".

local function classify(current, baseline, thr)
    local ratio = (current.mean_s - baseline.mean_s) / baseline.mean_s
    local lo = current.mean_s - current.stddev_s
    local hi = baseline.mean_s + baseline.stddev_s
    local intervals_overlap = lo <= hi

    if ratio > thr and not intervals_overlap then
        return "REGRESSION", ratio
    elseif ratio < -thr and not intervals_overlap then
        return "improved", ratio
    else
        return "ok", ratio
    end
end

-- ---------------------------------------------------------------------------
-- Run benchmarks
-- ---------------------------------------------------------------------------

print(fmt("Running benchmarks (%d iters x %d rounds)...", iterations, rounds))
print()

local results = bench_render.run {
    filter     = filter,
    iterations = iterations,
    rounds     = rounds,
}

-- ---------------------------------------------------------------------------
-- Compare against baselines
-- ---------------------------------------------------------------------------

local regressions   = 0
local improvements  = 0
local new_baselines = 0

-- Table header
print(fmt("%-25s  %8s  %14s  %8s  %10s  %10s  %s",
    "Scenario", "Iters", "Avg/frame", "stddev", "ops/s", "vs base", "Status"))
print(string.rep("-", 100))

for _, r in ipairs(results) do
    local baseline = load_baseline(r.name)
    local status, ratio

    if baseline then
        status, ratio = classify(r, baseline, threshold)
        if status == "REGRESSION" then
            regressions = regressions + 1
        elseif status == "improved" then
            improvements = improvements + 1
        end
    else
        ratio = 0
        status = "new"
        new_baselines = new_baselines + 1
    end

    local vs_base = baseline and format_pct(ratio) or "  --"
    local cv = r.mean_s > 0 and (r.stddev_s / r.mean_s * 100) or 0

    print(fmt("%-25s  %8d  %14s  %5.1f%%  %10.0f  %10s  %s",
        r.name, r.iterations, format_time(r.mean_s), cv,
        r.ops_per_s, vs_base, status))

    -- Update baseline if requested
    if do_update then
        save_baseline(r.name, {
            iterations = r.iterations,
            mean_s     = r.mean_s,
            stddev_s   = r.stddev_s,
            ops_per_s  = r.ops_per_s,
        })
    end
end

print()

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

if do_update then
    print("Baselines updated in " .. BASELINE_DIR .. "/")
end

print(fmt("%d scenarios: %d ok, %d improved, %d regression, %d new",
    #results, #results - regressions - improvements - new_baselines,
    improvements, regressions, new_baselines))

if regressions > 0 then
    print(fmt("FAIL: %d scenario(s) regressed beyond %.0f%% threshold (CI non-overlap)",
        regressions, threshold * 100))
    os.exit(1)
else
    print("All clear.")
end
