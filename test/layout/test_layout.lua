-- test/test_layout.lua — Yoga layout edge cases (flex, padding, deep nesting).
--
-- These tests assert the final rendered frame rather than probing the layout
-- tree directly — the frame is the externally-observable contract. Each test
-- constructs a deterministic layout and checks specific cells in the output.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "layout"

-- ---------------------------------------------------------------------------
-- 1. flexGrow distribution: two siblings with `flexGrow = 1` and `flexGrow = 2`
--    on a 30-col row both grow to fill free space, with the second getting
--    roughly twice as much as the first.

function suite:test_flex_grow_ratio_1_to_2()
    local function App()
        return tui.Box {
            width = 30, height = 1,
            flexDirection = "row",
            tui.Box {
                flexGrow = 1,
                tui.Text { "A" },
            },
            tui.Box {
                flexGrow = 2,
                tui.Text { "B" },
            },
        }
    end
    local h = testing.harness(App, { cols = 30, rows = 1 })
    local row = h:row(1)
    lt.assertEquals(row:sub(1, 1), "A", "first child starts at col 1")
    local b_col = row:find("B", 1, true)
    lt.assertEquals(b_col ~= nil, true, "expected 'B' somewhere in the row")
    -- With 30 cols and 1:2 flexGrow ratio, B should appear roughly 1/3 across.
    lt.assertEquals(b_col > 5 and b_col < 15, true,
        "B should land roughly 1/3 across the row, got col " .. tostring(b_col))
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Padding and margin compose correctly: outer has marginLeft=2,
--    inner has paddingLeft=3; content "X" should land at col 6 (1 + 2 + 3).

function suite:test_padding_and_margin_combined()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            flexDirection = "row",
            tui.Box {
                marginLeft = 2,
                paddingLeft = 3,
                tui.Text { "X" },
            },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 1 })
    local row = h:row(1)
    lt.assertEquals(row:sub(1, 5), "     ", "first 5 cols blank (2 margin + 3 padding)")
    lt.assertEquals(row:sub(6, 6), "X", "content at col 6")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. 20 levels of nested Box with paddingLeft = 1 on each level shifts the
--    content by exactly 20 columns. Verifies the layout engine handles deep
--    recursion without stack exhaustion.

function suite:test_deep_nesting_20_levels()
    local function make_nested(depth)
        if depth == 0 then
            return tui.Text { "!" }
        end
        return tui.Box {
            paddingLeft = 1,
            make_nested(depth - 1),
        }
    end
    local function App()
        return tui.Box {
            width = 40, height = 1,
            make_nested(20),
        }
    end
    local h = testing.harness(App, { cols = 40, rows = 1 })
    local row = h:row(1)
    -- 20 nested paddingLeft=1 → content at col 21.
    lt.assertEquals(row:sub(1, 20), string.rep(" ", 20),
        "first 20 cols are padding")
    lt.assertEquals(row:sub(21, 21), "!", "content lands at col 21")
    h:unmount()
end
