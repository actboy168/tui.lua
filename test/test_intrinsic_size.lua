-- test/test_intrinsic_size.lua — tui.intrinsicSize() tests.
--
-- intrinsicSize(element) returns the minimum (cols, rows) the element tree
-- needs to render without clipping. Apps compare this against useWindowSize()
-- to show a "terminal too small" fallback.

local lt   = require "ltest"
local tui  = require "tui"

local suite = lt.test "intrinsic_size"

function suite:test_simple_text()
    local w, h = tui.intrinsicSize(tui.Text { "hello" })
    lt.assertEquals(w, 5, "5-char text => 5 cols")
    lt.assertEquals(h, 1, "single line => 1 row")
end

function suite:test_box_with_padding()
    local w, h = tui.intrinsicSize(tui.Box {
        paddingLeft = 2, paddingRight = 2,
        tui.Text { "ab" },
    })
    lt.assertEquals(w, 6, "2 padding + 2 content = 6 cols")
    lt.assertEquals(h, 1)
end

function suite:test_box_with_border()
    local w, h = tui.intrinsicSize(tui.Box {
        border = "round",
        tui.Text { "hi" },
    })
    -- border reserves 1 cell on each side (left+right, top+bottom)
    lt.assertEquals(w, 4, "border 1+1 + content 2 = 4 cols")
    lt.assertEquals(h, 3, "border 1+1 + content 1 = 3 rows")
end

function suite:test_nested_box()
    local w, h = tui.intrinsicSize(tui.Box {
        paddingLeft = 1,
        tui.Box {
            paddingLeft = 2,
            tui.Text { "x" },
        },
    })
    lt.assertEquals(w, 4, "1 + 2 padding + 1 content = 4 cols")
    lt.assertEquals(h, 1)
end

function suite:test_row_layout()
    local w, h = tui.intrinsicSize(tui.Box {
        flexDirection = "row",
        tui.Text { "abc" },
        tui.Text { "de" },
    })
    lt.assertEquals(w, 5, "3 + 2 in a row = 5 cols")
    lt.assertEquals(h, 1)
end

function suite:test_column_layout()
    local w, h = tui.intrinsicSize(tui.Box {
        flexDirection = "column",
        tui.Text { "abc" },
        tui.Text { "de" },
    })
    lt.assertEquals(w, 3, "max(3, 2) = 3 cols")
    lt.assertEquals(h, 2, "2 rows stacked")
end

function suite:test_margin_not_in_content_size()
    -- Margin is space the element demands from its parent; with no
    -- parent constraint the root size only includes content + padding.
    local w, h = tui.intrinsicSize(tui.Box {
        marginLeft = 5,
        tui.Text { "hi" },
    })
    lt.assertEquals(w, 2, "margin does not inflate intrinsic width")
    lt.assertEquals(h, 1)
end

function suite:test_cjk_text()
    local w, h = tui.intrinsicSize(tui.Text { "\228\189\160\229\165\189" })  -- 你好
    lt.assertEquals(w, 4, "2 CJK chars = 4 display cols")
    lt.assertEquals(h, 1)
end
