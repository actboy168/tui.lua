-- test/test_screen_diff.lua — unit tests for the C-side screen module
-- (tui_core.screen) that replaced the old Lua row-level screen.lua.
--
-- These tests talk to the C module directly (via tui.screen which is a
-- thin wrapper) rather than going through the reconciler; they verify the
-- cell buffer + diff algorithm in isolation.

local lt     = require "ltest"
local screen = require "tui.screen"

local suite = lt.test "screen_diff"

local ESC = "\27"

-- ---------------------------------------------------------------------------
-- Helpers.

local function hex(s)
    -- For failure messages only; renders control bytes as <ESC>, tabs, etc.
    return (s:gsub(ESC, "<ESC>"):gsub("[\t\n\r]", function(c)
        if c == "\t" then return "<TAB>"
        elseif c == "\n" then return "<LF>"
        else return "<CR>" end
    end))
end

-- ---------------------------------------------------------------------------
-- Case 1: first frame full redraw.

function suite:test_first_frame_full_redraw()
    local s = screen.new(4, 2)
    screen.clear(s)
    local ansi = screen.diff(s)
    -- Must begin with clear-screen sequence.
    lt.assertEquals(ansi:sub(1, 7), ESC .. "[H" .. ESC .. "[2J")
end

-- ---------------------------------------------------------------------------
-- Case 2: identical second frame produces empty diff.

function suite:test_idempotent_second_diff()
    local s = screen.new(4, 2)
    screen.clear(s)
    screen.diff(s)  -- commit frame 1

    screen.clear(s)  -- frame 2 identical (all spaces)
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0, "identical frame produced ANSI: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 3: single cell change is localized (no full clear).

function suite:test_single_cell_change_localized()
    local tui_core = require "tui_core"
    local s = screen.new(10, 3)
    -- frame 1: fill with 'A'
    screen.clear(s)
    for y = 0, 2 do
        for x = 0, 9 do
            tui_core.screen.put(s, x, y, "A", 1)
        end
    end
    screen.diff(s)

    -- frame 2: same everywhere except (5,2) → 'B'
    screen.clear(s)
    for y = 0, 2 do
        for x = 0, 9 do
            tui_core.screen.put(s, x, y, "A", 1)
        end
    end
    tui_core.screen.put(s, 5, 2, "B", 1)
    local ansi = screen.diff(s)

    lt.assertEquals(ansi:find(ESC .. "[2J", 1, true), nil,
        "diff unexpectedly contains full-screen clear: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[3;6H", 1, true) ~= nil, true,
        "diff does not contain CUP to row 3 col 6: " .. hex(ansi))
    -- Make sure only the 'B' byte appears, not extra 'A's from neighboring cells.
    lt.assertEquals(ansi:sub(-1), "B")
end

-- ---------------------------------------------------------------------------
-- Case 4: segment merge within MERGE_GAP (=3).

function suite:test_segment_merge_within_gap()
    local tui_core = require "tui_core"
    local s = screen.new(10, 1)
    screen.clear(s)
    screen.diff(s)

    -- Change (1,0) and (3,0): gap = 1 (< MERGE_GAP=3), should merge.
    screen.clear(s)
    tui_core.screen.put(s, 1, 0, "X", 1)
    tui_core.screen.put(s, 3, 0, "Y", 1)
    local ansi = screen.diff(s)

    -- Expect a single CUP at col 2 followed by "X Y" (space bridges the gap).
    lt.assertEquals(ansi, ESC .. "[1;2HX Y")
end

-- ---------------------------------------------------------------------------
-- Case 5: segment break when gap > MERGE_GAP.

function suite:test_segment_break_over_gap()
    local tui_core = require "tui_core"
    local s = screen.new(15, 1)
    screen.clear(s)
    screen.diff(s)

    -- Change (1,0) and (10,0): gap = 8 (> MERGE_GAP=3), should split.
    screen.clear(s)
    tui_core.screen.put(s, 1, 0, "X", 1)
    tui_core.screen.put(s, 10, 0, "Y", 1)
    local ansi = screen.diff(s)

    lt.assertEquals(ansi, ESC .. "[1;2HX" .. ESC .. "[1;11HY")
end

-- ---------------------------------------------------------------------------
-- Case 6: wide char + WIDE_TAIL handled correctly.

function suite:test_wide_char_and_tail()
    local tui_core = require "tui_core"
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "中", 2)
    screen.diff(s)
    local r = screen.rows(s)
    -- row[1] should begin with the 3 UTF-8 bytes of 中 then 2 spaces.
    lt.assertEquals(r[1]:sub(1, 3), "中")
    lt.assertEquals(r[1]:sub(4), "  ")  -- remaining 2 cells (col 2, 3)

    -- frame 2: replace 中 with 啊.
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "啊", 2)
    local ansi = screen.diff(s)
    -- Expect CUP to (1,1) + UTF-8 bytes of 啊 only.
    lt.assertEquals(ansi, ESC .. "[1;1H啊")
end

-- ---------------------------------------------------------------------------
-- Case 7: long cluster stored in slab round-trips through rows() and diff().

function suite:test_long_cluster_to_slab()
    local tui_core = require "tui_core"
    local s = screen.new(3, 1)
    screen.clear(s)
    -- 20-byte "cluster" (simulating a long ZWJ emoji sequence).
    local long = string.rep("a", 20)
    tui_core.screen.put(s, 0, 0, long, 1)
    screen.diff(s)
    local r = screen.rows(s)
    -- row[1] = 20-byte blob + 2 spaces for cells 1,2.
    lt.assertEquals(#r[1], 20 + 2)
    lt.assertEquals(r[1]:sub(1, 20), long)
end

-- ---------------------------------------------------------------------------
-- Case 8: slab growth via many long cells.

function suite:test_slab_growth()
    local tui_core = require "tui_core"
    local s = screen.new(8, 1)
    screen.clear(s)
    for i = 0, 7 do
        tui_core.screen.put(s, i, 0, string.rep("x", 12), 1)  -- each 12 bytes
    end
    screen.diff(s)
    local r = screen.rows(s)
    lt.assertEquals(#r[1], 8 * 12)
    lt.assertEquals(r[1], string.rep("x", 96))
end

-- ---------------------------------------------------------------------------
-- Case 9: row-pool stability across ring-buffer generations.
--
-- The C module maintains a ring of ROW_POOL_GEN=4 buffers. Strings returned
-- by rows() are zero-copy views into the generation's buffer and remain
-- valid until the 4th subsequent rows() call overwrites that generation.

function suite:test_row_pool_stability()
    local tui_core = require "tui_core"
    local s = screen.new(3, 1)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "A", 1)
    screen.diff(s)
    local r1 = screen.rows(s)
    lt.assertEquals(r1[1]:sub(1, 1), "A")

    -- 3 more rows() calls; r1 should still read as "A..." because they
    -- used generations 1,2,3 (not wrapping back to gen 0 yet).
    for _, ch in ipairs({"B", "C", "D"}) do
        screen.clear(s)
        tui_core.screen.put(s, 0, 0, ch, 1)
        screen.diff(s)
        screen.rows(s)
    end
    lt.assertEquals(r1[1]:sub(1, 1), "A",
        "r1 was overwritten before ROW_POOL_GEN generations elapsed")
end

-- ---------------------------------------------------------------------------
-- Case 10: resize triggers full redraw.

function suite:test_resize_triggers_full_redraw()
    local s = screen.new(4, 2)
    screen.clear(s)
    screen.diff(s)  -- prev_valid now true

    screen.resize(s, 6, 3)
    screen.clear(s)
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:sub(1, 7), ESC .. "[H" .. ESC .. "[2J")
end

-- ---------------------------------------------------------------------------
-- Case 11: invalidate triggers full redraw.

function suite:test_invalidate_triggers_full_redraw()
    local s = screen.new(4, 2)
    screen.clear(s)
    screen.diff(s)  -- prev_valid now true

    screen.invalidate(s)
    screen.clear(s)
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:sub(1, 7), ESC .. "[H" .. ESC .. "[2J")
end
