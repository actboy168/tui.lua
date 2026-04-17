-- test/test_text_wrap.lua — unit tests for tui.text.wrap and integration
-- with the layout/renderer pipeline.

local lt       = require "ltest"
local text_mod = require "tui.text"
local tui      = require "tui"
local layout   = require "tui.layout"
local renderer = require "tui.renderer"

local suite = lt.test "text_wrap"

function suite:test_wrap_empty_returns_one_line()
    local r = text_mod.wrap("", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "")
end

function suite:test_wrap_fits_single_line()
    local r = text_mod.wrap("hello", 10)
    lt.assertEquals(#r, 1)
    lt.assertEquals(r[1], "hello")
end

function suite:test_wrap_at_space_boundary()
    local r = text_mod.wrap("hello world how are you", 10)
    -- "hello world" = 11 cols > 10; break at space after "hello" → "hello", "world how", "are you"
    lt.assertEquals(#r, 3)
    lt.assertEquals(r[1], "hello")
    lt.assertEquals(r[2], "world how")
    lt.assertEquals(r[3], "are you")
end

function suite:test_wrap_hard_break_when_no_space()
    -- No whitespace → must hard-break at column boundary.
    local r = text_mod.wrap("abcdefghij", 4)
    lt.assertEquals(#r, 3)
    lt.assertEquals(r[1], "abcd")
    lt.assertEquals(r[2], "efgh")
    lt.assertEquals(r[3], "ij")
end

function suite:test_wrap_cjk_by_columns()
    -- Each CJK char = 2 cols. Width 6 → 3 chars per line.
    local r = text_mod.wrap("今天天气真好适合散步", 6)
    lt.assertEquals(r[1], "今天天")
    lt.assertEquals(r[2], "气真好")
    lt.assertEquals(r[3], "适合散")
    lt.assertEquals(r[4], "步")
end

function suite:test_wrap_respects_explicit_newlines()
    local r = text_mod.wrap("line1\nline2", 80)
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
    layout.free(root)
end

function suite:test_renderer_draws_wrapped_lines()
    local root = tui.Box {
        width = 20, height = 5,
        tui.Text { width = 10, "hello world how" },
    }
    layout.compute(root)
    local rows = renderer.render_rows(root, 20, 5)
    lt.assertEquals(rows[1]:sub(1, 5), "hello")
    lt.assertEquals(rows[2]:sub(1, 9), "world how")
    layout.free(root)
end

function suite:test_renderer_handles_wide_char_cells()
    -- "中a" = 3 cols; cell 1 = "中", cell 2 = sentinel, cell 3 = "a".
    local root = tui.Box {
        width = 5, height = 1,
        tui.Text { wrap = "nowrap", "中a" },
    }
    layout.compute(root)
    local rows = renderer.render_rows(root, 5, 1)
    -- Row string should render as "中a  " (2-col + 1-col + 2 padding spaces).
    lt.assertEquals(rows[1], "中a  ")
    layout.free(root)
end
