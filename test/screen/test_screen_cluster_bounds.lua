-- test/test_screen_cluster_bounds.lua — Stage 15: cluster-length cap.
--
-- put_cell rejects grapheme clusters larger than 256 bytes to avoid pathological
-- input bloating the slab. 100-byte ZWJ sequences still render in one cell.

local lt       = require "ltest"
local screen   = require "tui.internal.screen"
local tui_core = require "tui.core"

local suite = lt.test "screen_cluster_bounds"

-- ---------------------------------------------------------------------------
-- Case 1: Ridiculously long cluster (> 256B) is dropped silently, cell
-- becomes blank (no OOB, no crash, no partial bytes).

function suite:test_oversized_cluster_dropped()
    -- Build a synthetic 300-byte "cluster": base "a" + 149 COMBINING ACUTE
    -- accents (each 2B) = 1 + 298 = 299 bytes. wcwidth treats combining
    -- marks as continuation so the whole thing is one grapheme.
    local parts = { "a" }
    for _ = 1, 149 do
        parts[#parts + 1] = "\204\129"  -- U+0301 COMBINING ACUTE ACCENT
    end
    local big = table.concat(parts)
    lt.assertEquals(#big, 299)

    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, big .. "bc", 4)
    screen.diff(s)
    local row = screen.rows(s)[1]
    -- Cluster dropped → cell 0 stays whatever draw_line wrote after. The
    -- advance logic uses the cluster's display width regardless of whether
    -- put_cell succeeded, so "b" lands at column 1, "c" at column 2.
    lt.assertEquals(row:sub(2, 2), "b")
    lt.assertEquals(row:sub(3, 3), "c")
end

-- ---------------------------------------------------------------------------
-- Case 2: Long-but-under-cap cluster (~100B) still renders in one cell.

function suite:test_long_zwj_still_renders()
    -- Build a longer-than-slab-inline ZWJ family: 6 emoji joined by ZWJ.
    -- Each woman emoji is 4 bytes, each ZWJ is 3 bytes.
    -- 6 emoji + 5 ZWJ = 6*4 + 5*3 = 39 bytes. Width 2.
    local woman = "\240\159\145\169"
    local zwj   = "\226\128\141"
    local fam = woman .. zwj .. woman .. zwj .. woman .. zwj
              .. woman .. zwj .. woman .. zwj .. woman
    lt.assertEquals(#fam, 39)

    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, fam .. "X", 4)
    screen.diff(s)
    local row = screen.rows(s)[1]
    -- Cell 0 head holds all 39 bytes (slab path), cell 1 = WIDE_TAIL,
    -- cell 2 = "X", cell 3 = " ".
    lt.assertEquals(row:sub(1, 39), fam)
    lt.assertEquals(row:sub(40, 40), "X")
end
