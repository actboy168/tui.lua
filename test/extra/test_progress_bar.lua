-- test/extra/test_progress_bar.lua — <ProgressBar> component behavior.

local lt          = require "ltest"
local tui         = require "tui"
local ProgressBar = require "tui.extra.progress_bar".ProgressBar
local testing     = require "tui.testing"

local suite = lt.test "progress_bar"

local function strip_ansi(s)
    return (s:gsub("\27%[[%d;]*m", ""))
end

-- value=0 renders width * empty glyphs, no fill.
function suite:test_zero_is_all_empty()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            ProgressBar { value = 0, width = 10 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local row = strip_ansi(h:row(1))
    lt.assertEquals(row:find("\u{2588}", 1, true), nil, "no fill at value=0")
    lt.assertEquals(select(2, row:gsub("\u{2591}", "")), 10,
                    "exactly 10 empty glyphs")
    h:unmount()
end

-- value=1 renders width * fill glyphs.
function suite:test_one_is_all_fill()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            ProgressBar { value = 1, width = 10 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local row = strip_ansi(h:row(1))
    lt.assertEquals(select(2, row:gsub("\u{2588}", "")), 10,
                    "exactly 10 fill glyphs")
    lt.assertEquals(row:find("\u{2591}", 1, true), nil, "no empty at value=1")
    h:unmount()
end

-- Intermediate value splits fill/empty proportionally.
function suite:test_half_is_half_and_half()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            ProgressBar { value = 0.5, width = 10 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local row = strip_ansi(h:row(1))
    lt.assertEquals(select(2, row:gsub("\u{2588}", "")), 5, "5 fill glyphs")
    lt.assertEquals(select(2, row:gsub("\u{2591}", "")), 5, "5 empty glyphs")
    h:unmount()
end

-- value > 1 clamps to full; value < 0 clamps to empty.
function suite:test_value_clamps_out_of_range()
    local function App()
        return tui.Box {
            width = 20, height = 2, flexDirection = "column",
            ProgressBar { value = 2.0, width = 10 },
            ProgressBar { value = -1,  width = 10 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 2 })
    lt.assertEquals(select(2, strip_ansi(h:row(1)):gsub("\u{2588}", "")), 10)
    lt.assertEquals(select(2, strip_ansi(h:row(2)):gsub("\u{2591}", "")), 10)
    h:unmount()
end

-- Custom chars override the defaults.
function suite:test_custom_chars()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            ProgressBar {
                value = 0.3, width = 10,
                chars = { fill = "#", empty = "-" },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local row = strip_ansi(h:row(1))
    lt.assertEquals(select(2, row:gsub("#", "")), 3, "3 fill chars at 0.3")
    lt.assertEquals(select(2, row:gsub("%-", "")), 7, "7 empty chars at 0.3")
    h:unmount()
end

-- Non-number / nil value is treated as 0 (no crash).
function suite:test_nil_value_is_zero()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            ProgressBar { width = 5 },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    local row = strip_ansi(h:row(1))
    lt.assertEquals(row:find("\u{2588}", 1, true), nil)
    h:unmount()
end

-- Default width draws 20 glyphs total.
function suite:test_default_width()
    local function App()
        return tui.Box {
            width = 40, height = 1,
            ProgressBar { value = 0.5 },
        }
    end
    local h = testing.render(App, { cols = 40, rows = 1 })
    local row = strip_ansi(h:row(1))
    local fill_n  = select(2, row:gsub("\u{2588}", ""))
    local empty_n = select(2, row:gsub("\u{2591}", ""))
    lt.assertEquals(fill_n + empty_n, 20, "default width is 20")
    lt.assertEquals(fill_n, 10)
    h:unmount()
end
