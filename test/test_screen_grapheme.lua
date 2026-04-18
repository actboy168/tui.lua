-- test/test_screen_grapheme.lua — Stage 12: grapheme-cluster-aware draw_line.
--
-- Verifies that screen.draw_line walks clusters (not code points) and that
-- combining marks, ZWJ sequences, RI pairs, VS16 and Hangul jamo all occupy
-- exactly one cell with the expected display width.

local lt       = require "ltest"
local screen   = require "tui.screen"
local tui_core = require "tui_core"

local suite = lt.test "screen_grapheme"

local <const> ESC = "\27"

-- Helper: draw a single line on a fresh screen, commit frame 1 (discard
-- its clear-screen noise), and return the first row bytes.
local function draw_and_row(width, text)
    local s = screen.new(width, 1)
    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, text, width)
    screen.diff(s)  -- commit
    local r = screen.rows(s)
    return s, r[1]
end

-- ---------------------------------------------------------------------------
-- Case 1: combining mark fuses onto previous cell.

function suite:test_combining_mark_single_cell()
    -- "a" + COMBINING ACUTE (2B) + "b" = "á" in cell 0, "b" in cell 1.
    local s, row = draw_and_row(4, "a\204\129b")
    -- Cell 0 holds 3 bytes ("a\204\129"), cell 1 holds "b", cells 2/3 are spaces.
    lt.assertEquals(row:sub(1, 3), "a\204\129")
    lt.assertEquals(row:sub(4, 4), "b")
    lt.assertEquals(row:sub(5, 6), "  ")
    -- width check: the text occupies columns 0 and 1 only (column 2+ is blank).
    -- A second identical frame must produce an empty diff.
    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, "a\204\129b", 4)
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0)
end

-- ---------------------------------------------------------------------------
-- Case 2: ZWJ family fits in one cell via slab (cluster > 8 bytes).

function suite:test_zwj_family_one_cell()
    -- 👨ZWJ👩ZWJ👧 = 18 bytes, width 2.
    local fam = "\240\159\145\168\226\128\141\240\159\145\169\226\128\141\240\159\145\167"
    local s, row = draw_and_row(4, fam .. "x")
    -- Cell 0-1 hold the 18-byte family (head cell contains all bytes, tail is
    -- a WIDE_TAIL). Cell 2 = "x", cell 3 = " ".
    lt.assertEquals(row:sub(1, 18), fam)
    lt.assertEquals(row:sub(19, 19), "x")
    lt.assertEquals(row:sub(20, 20), " ")
end

-- ---------------------------------------------------------------------------
-- Case 3: regional indicator pair = one cell, width 2.

function suite:test_regional_indicator_flag_width_2()
    -- 🇯🇵 (8 bytes) + "X"
    local jp = "\240\159\135\175\240\159\135\181"
    local s, row = draw_and_row(4, jp .. "X")
    lt.assertEquals(row:sub(1, 8), jp)   -- cell 0 head holds all 8 bytes
    lt.assertEquals(row:sub(9, 9), "X")  -- cell 2
    lt.assertEquals(row:sub(10, 10), " ")  -- cell 3

    -- Idempotency: same content twice → empty diff.
    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, jp .. "X", 4)
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0)
end

-- ---------------------------------------------------------------------------
-- Case 4: VS16 promotes base to width 2.

function suite:test_vs16_promotes_to_wide()
    -- ❤FE0F = 6 bytes, base ❤ is width 1 but VS16 forces emoji presentation
    -- (width 2). Following "x" must land in column 2.
    local heart_vs16 = "\226\157\164\239\184\143"
    local s, row = draw_and_row(4, heart_vs16 .. "x")
    -- Cell 0 head holds all 6 heart bytes, cell 1 is WIDE_TAIL, cell 2 = "x".
    lt.assertEquals(row:sub(1, 6), heart_vs16)
    lt.assertEquals(row:sub(7, 7), "x")
    lt.assertEquals(row:sub(8, 8), " ")
end

-- ---------------------------------------------------------------------------
-- Case 5: Hangul jamo L+V+T fuses into one width-2 cell.

function suite:test_hangul_jamo_fuses()
    -- ᄒ (U+1112) + ᅡ (U+1161) + ᆫ (U+11AB) = 한, 9 bytes total, width 2.
    local han = "\225\132\146\225\133\161\225\134\171"
    local s, row = draw_and_row(4, han .. "z")
    lt.assertEquals(row:sub(1, 9), han)
    lt.assertEquals(row:sub(10, 10), "z")
end
