-- examples/counter.lua — Stage 3 demo:
--   * auto-incrementing counter (every 100ms)
--   * +/- or up/down change the step size
--   * space pauses/resumes
--   * q / esc exits

local tui = require "tui"

local function Counter()
    local n,      setN      = tui.useState(0)
    local step,   setStep   = tui.useState(1)
    local paused, setPaused = tui.useState(false)
    local app = tui.useApp()

    tui.useInterval(function()
        if not paused then
            setN(function(v) return v + step end)
        end
    end, 100)

    tui.useInput(function(input, key)
        if key.name == "char" and (input == "q") then
            app.exit()
        elseif key.name == "escape" then
            app.exit()
        elseif input == "+" or key.name == "up" then
            setStep(function(s) return s + 1 end)
        elseif input == "-" or key.name == "down" then
            setStep(function(s) return math.max(1, s - 1) end)
        elseif input == " " then
            setPaused(function(p) return not p end)
        end
    end)

    local status = paused and "paused" or "running"
    return tui.Box {
        justifyContent = "center", alignItems = "center",
        flexDirection = "column",
        tui.Box {
            border = "round", padding = "0 1",
            tui.Text { "ticks: " .. tostring(n) .. "  step: " .. tostring(step) },
        },
        tui.Text { "[" .. status .. "]  +/-: step   space: pause   q: quit" },
    }
end

tui.render(Counter)
