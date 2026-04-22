-- test/extra/test_select.lua — <Select> component behavior.

local lt     = require "ltest"
local tui    = require "tui"
local Select = require "tui.extra.select".Select
local testing = require "tui.testing"

local suite = lt.test "select"

-- Rough helper: strip ANSI SGR escape sequences from a row string so text
-- assertions don't depend on color output.
local function strip_ansi(s)
    return (s:gsub("\27%[[%d;]*m", ""))
end

-- Assert the given row begins with the given prefix (after ANSI stripping).
local function row_starts_with(h, row_idx, prefix)
    local row = strip_ansi(h:row(row_idx))
    lt.assertEquals(row:sub(1, #prefix), prefix,
                    "row " .. row_idx .. " did not start with " .. prefix)
end

-- Default render: first row is highlighted with "❯ ", others with "  ".
function suite:test_initial_highlight_and_default_indicator()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select { items = { "alpha", "beta", "gamma" } },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    row_starts_with(h, 1, "❯ alpha")
    row_starts_with(h, 2, "  beta")
    row_starts_with(h, 3, "  gamma")
    h:unmount()
end

-- Down arrow moves highlight and fires onChange (not onSelect).
function suite:test_down_moves_highlight_and_fires_onchange()
    local changes, selects = {}, {}
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items    = { "a", "b", "c" },
                onChange = function(item, idx) changes[#changes + 1] = { item.value, idx } end,
                onSelect = function(item, idx) selects[#selects + 1] = { item.value, idx } end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("down")
    h:rerender()
    lt.assertEquals(#changes, 1)
    lt.assertEquals(changes[1][1], "b")
    lt.assertEquals(changes[1][2], 2)
    lt.assertEquals(#selects, 0)
    row_starts_with(h, 2, "❯ b")
    h:unmount()
end

-- Up at the first row wraps to the last.
function suite:test_up_wraps_to_last()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select { items = { "a", "b", "c" } },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("up")
    h:rerender()
    row_starts_with(h, 3, "❯ c")
    h:unmount()
end

-- Down at the last row wraps to the first.
function suite:test_down_wraps_to_first()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select { items = { "a", "b", "c" }, initialIndex = 3 },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("down")
    h:rerender()
    row_starts_with(h, 1, "❯ a")
    h:unmount()
end

-- Home / End jump to the ends.
function suite:test_home_end_jump()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select { items = { "a", "b", "c" }, initialIndex = 2 },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("end")
    h:rerender()
    row_starts_with(h, 3, "❯ c")
    h:press("home")
    h:rerender()
    row_starts_with(h, 1, "❯ a")
    h:unmount()
end

-- Enter fires onSelect with the current item + index.
function suite:test_enter_fires_onselect()
    local selected
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items    = { "a", "b", "c" },
                onSelect = function(item, idx) selected = { item.value, idx } end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("down")
    h:press("enter")
    h:rerender()
    lt.assertEquals(selected[1], "b")
    lt.assertEquals(selected[2], 2)
    h:unmount()
end

-- isDisabled=true prevents key handling (and takes itself out of focus nav).
function suite:test_disabled_ignores_keys()
    local changes = 0
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items      = { "a", "b", "c" },
                isDisabled = true,
                onChange   = function() changes = changes + 1 end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("down")
    h:rerender()
    lt.assertEquals(changes, 0)
    -- Highlight stays on the first row.
    row_starts_with(h, 1, "❯ a")
    h:unmount()
end

-- Empty items list: component renders nothing but does not error.
function suite:test_empty_items_no_error()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select { items = {} },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    lt.assertEquals(strip_ansi(h:row(1)):match("%S"), nil)  -- no non-space
    -- Enter / arrows are no-ops and must not raise.
    h:press("down")
    h:press("enter")
    h:unmount()
end

-- Table-shape items with explicit value that differs from label.
function suite:test_table_items_value_distinct_from_label()
    local got
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items    = {
                    { label = "Alpha", value = "A" },
                    { label = "Beta",  value = "B" },
                },
                onSelect = function(item, idx) got = { item.value, idx, item.label } end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    h:press("down")
    h:press("enter")
    h:rerender()
    lt.assertEquals(got[1], "B")
    lt.assertEquals(got[2], 2)
    lt.assertEquals(got[3], "Beta")
    h:unmount()
end

-- limit=N shows at most N rows; window scrolls with the highlight.
function suite:test_limit_window_scrolls()
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items = { "a", "b", "c", "d", "e" },
                limit = 3,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    -- Initial window: first 3.
    row_starts_with(h, 1, "❯ a")
    row_starts_with(h, 2, "  b")
    row_starts_with(h, 3, "  c")

    -- Move highlight down far enough that the window shifts.
    h:press("down") -- hl=2
    h:press("down") -- hl=3
    h:press("down") -- hl=4 — window must shift to show 'd'
    h:rerender()
    -- Whichever row the highlighted 'd' ends up on, it must be visible.
    local found
    for i = 1, 3 do
        if strip_ansi(h:row(i)):find("^❯ d") then found = i; break end
    end
    lt.assertEquals(type(found), "number", "highlighted 'd' must be visible")
    h:unmount()
end

-- renderItem callback overrides default rendering.
function suite:test_render_item_override()
    local function App()
        return tui.Box {
            width = 30, height = 2, flexDirection = "column",
            Select {
                items = { "a", "b" },
                renderItem = function(item, ctx)
                    return tui.Text {
                        (ctx.isSelected and "[*] " or "[ ] ") .. tostring(item),
                    }
                end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 2 })
    row_starts_with(h, 1, "[*] a")
    row_starts_with(h, 2, "[ ] b")
    h:press("down")
    h:rerender()
    row_starts_with(h, 1, "[ ] a")
    row_starts_with(h, 2, "[*] b")
    h:unmount()
end

-- Shrinking items below the current highlight clamps the highlight down.
function suite:test_items_shrink_clamps_highlight()
    local items = { "a", "b", "c", "d" }
    local function App()
        return tui.Box {
            width = 30, height = 4, flexDirection = "column",
            Select { items = items, initialIndex = 4 },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 4 })
    row_starts_with(h, 4, "❯ d")
    items = { "a", "b" }
    h:rerender()
    -- Highlight clamping happens in a useEffect (dirty state); the next
    -- paint observes the clamped highlight.
    h:rerender()
    -- Highlight was on 4, must clamp to 2 (the new last).
    row_starts_with(h, 2, "❯ b")
    h:unmount()
end

-- Pressing a key with no matching name (e.g. random letter) is a no-op.
function suite:test_unknown_key_is_noop()
    local changes = 0
    local function App()
        return tui.Box {
            width = 30, height = 2, flexDirection = "column",
            Select {
                items    = { "a", "b" },
                onChange = function() changes = changes + 1 end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 2 })
    h:type("x")
    h:rerender()
    lt.assertEquals(changes, 0)
    h:unmount()
end

-- Bulk dispatch: two "down" events in one dispatch must both take effect
-- (highlight moves from 1→2→3, not 1→2→2).
function suite:test_bulk_dispatch_two_downs()
    local changes = {}
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items    = { "a", "b", "c" },
                onChange = function(item, idx) changes[#changes + 1] = idx end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    -- Two down-arrow CSI sequences in one dispatch.
    h:dispatch("\27[B\27[B")
    lt.assertEquals(#changes, 2, "both downs must fire onChange")
    lt.assertEquals(changes[1], 2, "first down → index 2")
    lt.assertEquals(changes[2], 3, "second down → index 3")
    row_starts_with(h, 3, "❯ c")
    h:unmount()
end

-- Bulk dispatch: home then down in one batch.
function suite:test_bulk_dispatch_home_then_down()
    local changes = {}
    local function App()
        return tui.Box {
            width = 30, height = 3, flexDirection = "column",
            Select {
                items        = { "a", "b", "c" },
                initialIndex = 3,
                onChange     = function(item, idx) changes[#changes + 1] = idx end,
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 3 })
    -- Home (CSI 1~) then down in one dispatch.
    h:dispatch("\27[1~\27[B")
    lt.assertEquals(#changes, 2, "home and down both fire onChange")
    lt.assertEquals(changes[1], 1, "home → index 1")
    lt.assertEquals(changes[2], 2, "down from home → index 2")
    row_starts_with(h, 2, "❯ b")
    h:unmount()
end
