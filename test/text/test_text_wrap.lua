-- test/test_text_wrap.lua — unit tests for tui.text.wrap and integration
-- with the layout/renderer pipeline.

local lt       = require "ltest"
local tui      = require "tui"
local layout   = require "tui.internal.layout"
local renderer = require "tui.internal.renderer"
local screen   = require "tui.internal.screen"

local suite = lt.test "text_wrap"

function suite:test_wrap_empty_returns_one_line()
    local r = tui.wrap("", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "")
end

function suite:test_wrap_fits_single_line()
    local r = tui.wrap("hello", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "hello")
end

function suite:test_wrap_at_space_boundary()
    local r = tui.wrap("hello world how are you", 10)
    -- "hello world" = 11 cols > 10; break at space after "hello" → "hello", "world how", "are you"
    lt.assertEquals(#r, 3)
    lt.assertEquals(r[1], "hello")
    lt.assertEquals(r[2], "world how")
    lt.assertEquals(r[3], "are you")
end

function suite:test_wrap_hard_break_when_no_space()
    -- No whitespace → must hard-break at column boundary.
    local r = tui.wrap("abcdefghij", 4)
    lt.assertEquals(#r, 3)
    lt.assertEquals(r[1], "abcd")
    lt.assertEquals(r[2], "efgh")
    lt.assertEquals(r[3], "ij")
end

function suite:test_wrap_cjk_by_columns()
    -- Each CJK char = 2 cols. Width 6 → 3 chars per line.
    local r = tui.wrap("今天天气真好适合散步", 6)
    lt.assertEquals(r[1], "今天天")
    lt.assertEquals(r[2], "气真好")
    lt.assertEquals(r[3], "适合散")
    lt.assertEquals(r[4], "步")
end

function suite:test_wrap_respects_explicit_newlines()
    local r = tui.wrap("line1\nline2", 80)
    lt.assertEquals(#r, 2)
    lt.assertEquals(r[1], "line1")
    lt.assertEquals(r[2], "line2")
end

function suite:test_layout_integrates_wrap_into_height()
    -- A Text node with width=10 and a multi-word string should get height=3
    -- after the two-pass layout.
    local el = tui.Text { width = 10, "hello world how are you" }
    -- Wrap root in a Box to satisfy layout's tree expectations.
    local root = tui.Box { width = 20, height = 10, el }
    layout.compute(root)
    lt.assertEquals(el.rect.w, 10)
    lt.assertEquals(el.rect.h, 3)
end

function suite:test_renderer_draws_wrapped_lines()
    local root = tui.Box {
        width = 20, height = 5,
        tui.Text { width = 10, "hello world how" },
    }
    layout.compute(root)
    local s = screen.new(20, 5)
    screen.clear(s)
    renderer.paint(root, s)
    screen.diff(s)
    local rows = screen.rows(s)
    lt.assertEquals(rows[1]:sub(1, 5), "hello")
    lt.assertEquals(rows[2]:sub(1, 9), "world how")
end

function suite:test_renderer_handles_wide_char_cells()
    -- "中a" = 3 cols; cell 1 = "中", cell 2 = WIDE_TAIL, cell 3 = "a".
    local root = tui.Box {
        width = 5, height = 1,
        tui.Text { wrap = "nowrap", "中a" },
    }
    layout.compute(root)
    local s = screen.new(5, 1)
    screen.clear(s)
    renderer.paint(root, s)
    screen.diff(s)
    local rows = screen.rows(s)
    -- Row string should render as "中a  " (2-col + 1-col + 2 padding spaces).
    lt.assertEquals(rows[1], "中a  ")
end

-- ---------------------------------------------------------------------------
-- wrap_hard

function suite:test_wrap_hard_empty()
    local r = tui.wrapHard("", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "")
end

function suite:test_wrap_hard_fits()
    local r = tui.wrapHard("hello", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "hello")
end

function suite:test_wrap_hard_breaks_at_boundary()
    local r = tui.wrapHard("abcdefgh", 4)
    lt.assertEquals(#r, 2)
    lt.assertEquals(r[1], "abcd")
    lt.assertEquals(r[2], "efgh")
end

function suite:test_wrap_hard_no_whitespace_break()
    -- hard wrap never breaks at whitespace — spaces stay in-line
    local r = tui.wrapHard("ab cd", 4)
    lt.assertEquals(r[1], "ab c")
    lt.assertEquals(r[2], "d")
end

function suite:test_wrap_hard_respects_newlines()
    local r = tui.wrapHard("line1\nline2", 80)
    lt.assertEquals(#r, 2)
    lt.assertEquals(r[1], "line1")
    lt.assertEquals(r[2], "line2")
end

function suite:test_wrap_hard_cjk()
    -- Each CJK char = 2 cols, hard break at 4 = 2 chars per line.
    local r = tui.wrapHard("今天天气", 4)
    lt.assertEquals(#r, 2)
    lt.assertEquals(r[1], "今天")
    lt.assertEquals(r[2], "天气")
end

-- ---------------------------------------------------------------------------
-- truncate (end)

function suite:test_truncate_fits()
    lt.assertEquals(tui.truncate("hello", 10), "hello")
end

function suite:test_truncate_exact()
    lt.assertEquals(tui.truncate("hello", 5), "hello")
end

function suite:test_truncate_over()
    -- "hello world" = 11 cols, max 8 → "hello w…" (7 + ellipsis)
    lt.assertEquals(tui.truncate("hello world", 8), "hello w\xe2\x80\xa6")
end

function suite:test_truncate_single_char()
    -- max_cols=1: budget=0 → just "…"
    lt.assertEquals(tui.truncate("hello", 1), "\xe2\x80\xa6")
end

function suite:test_truncate_cjk()
    -- "今天天气" = 8 cols, max 5 → "今天" (4 cols) + "…" = 5
    lt.assertEquals(tui.truncate("今天天气", 5), "今天\xe2\x80\xa6")
end

-- ---------------------------------------------------------------------------
-- truncate_start

function suite:test_truncate_start_fits()
    lt.assertEquals(tui.truncateStart("hello", 10), "hello")
end

function suite:test_truncate_start_over()
    -- "hello world" = 11 cols, max 8 → "…" + last 7 cols = "…o world"
    lt.assertEquals(tui.truncateStart("hello world", 8), "\xe2\x80\xa6o world")
end

function suite:test_truncate_start_single()
    lt.assertEquals(tui.truncateStart("hello", 1), "\xe2\x80\xa6")
end

-- ---------------------------------------------------------------------------
-- truncate_middle

function suite:test_truncate_middle_fits()
    lt.assertEquals(tui.truncateMiddle("hello", 10), "hello")
end

function suite:test_truncate_middle_over()
    -- "hello world" = 11 cols, max 7 → head 3 + "…" + tail 3 = "hel…rld"
    lt.assertEquals(tui.truncateMiddle("hello world", 7), "hel\xe2\x80\xa6rld")
end

function suite:test_truncate_middle_even_budget()
    -- budget = max_cols-1 = 6 (even) → head=3, tail=3
    lt.assertEquals(tui.truncateMiddle("abcdefghij", 7), "abc\xe2\x80\xa6hij")
end

function suite:test_truncate_middle_odd_budget()
    -- budget = max_cols-1 = 5 (odd) → head=2, tail=3
    lt.assertEquals(tui.truncateMiddle("abcdefghij", 6), "ab\xe2\x80\xa6hij")
end

-- ---------------------------------------------------------------------------
-- layout integration: wrap="hard"

function suite:test_layout_hard_wrap()
    local el = tui.Text { width = 4, wrap = "hard", "abcdefgh" }
    local root = tui.Box { width = 20, height = 10, el }
    layout.compute(root)
    lt.assertEquals(el.rect.h, 2)
    lt.assertEquals(el.lines[1], "abcd")
    lt.assertEquals(el.lines[2], "efgh")
end

-- ---------------------------------------------------------------------------
-- layout integration: wrap="truncate"

function suite:test_layout_truncate_end()
    local el = tui.Text { width = 8, wrap = "truncate", "hello world" }
    local root = tui.Box { width = 20, height = 5, el }
    layout.compute(root)
    lt.assertEquals(el.rect.h, 1)
    lt.assertEquals(el.lines[1], "hello w\xe2\x80\xa6")
end

function suite:test_layout_truncate_end_alias()
    local el = tui.Text { width = 8, wrap = "truncate-end", "hello world" }
    local root = tui.Box { width = 20, height = 5, el }
    layout.compute(root)
    lt.assertEquals(el.lines[1], "hello w\xe2\x80\xa6")
end

function suite:test_layout_truncate_start()
    local el = tui.Text { width = 8, wrap = "truncate-start", "hello world" }
    local root = tui.Box { width = 20, height = 5, el }
    layout.compute(root)
    lt.assertEquals(el.rect.h, 1)
    lt.assertEquals(el.lines[1], "\xe2\x80\xa6o world")
end

function suite:test_layout_truncate_middle()
    local el = tui.Text { width = 7, wrap = "truncate-middle", "hello world" }
    local root = tui.Box { width = 20, height = 5, el }
    layout.compute(root)
    lt.assertEquals(el.rect.h, 1)
    lt.assertEquals(el.lines[1], "hel\xe2\x80\xa6rld")
end
