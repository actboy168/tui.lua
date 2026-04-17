-- examples/counter.lua — Stage 2 demo: auto-incrementing counter.
--
-- Press q / Ctrl+C / Ctrl+D to exit.

local tui = require "tui"

local function Counter()
    local n, setN = tui.useState(0)
    tui.useInterval(function() setN(function(v) return v + 1 end) end, 100)

    return tui.Box {
        justifyContent = "center", alignItems = "center",
        tui.Box {
            border = "round", padding = "0 1",
            tui.Text { "ticks: " .. tostring(n) },
        },
    }
end

tui.render(Counter)
