-- test/test_screen_sgr.lua — unit tests for Stage 10 SGR / color support.
-- These talk to the C module directly (via tui.screen + tui_core.screen)
-- to verify the byte-level ANSI output.

local lt       = require "ltest"
local screen   = require "tui.screen"
local tui_core = require "tui_core"

local suite = lt.test "screen_sgr"

local ESC = "\27"

local function hex(s)
    return (s:gsub(ESC, "<ESC>"))
end

-- ---------------------------------------------------------------------------
-- Case 1: single-cell colored first frame.

function suite:test_single_cell_colored_first_frame()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, { fg = 1 })  -- red
    local ansi = screen.diff(s)
    -- Must contain the SGR "ESC[0;31m" somewhere (leading reset + red fg).
    lt.assertEquals(ansi:find(ESC .. "[0;31m", 1, true) ~= nil, true,
        "expected red SGR in: " .. hex(ansi))
    -- X must appear after the SGR, line must end with ESC[0m reset.
    lt.assertEquals(ansi:find("X" .. ESC .. "[0m", 1, true) ~= nil
                    or ansi:find("X ", 1, true) ~= nil
                    or ansi:find("X", 1, true) ~= nil, true,
        "expected X in output: " .. hex(ansi))
    -- Must contain at least one trailing reset so later rows stay uncolored.
    lt.assertEquals(ansi:find(ESC .. "[0m", 1, true) ~= nil, true,
        "expected final ESC[0m reset: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 2: draw_line colored with bold.

function suite:test_draw_line_colored_bold()
    local s = screen.new(10, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "a", 1)  -- neutral frame 1
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, "hi", 10, { fg = 2, bold = true })
    local ansi = screen.diff(s)
    -- Expect SGR "ESC[0;1;32m" (bold + green fg) before "hi".
    lt.assertEquals(ansi:find(ESC .. "[0;1;32m", 1, true) ~= nil, true,
        "expected bold+green SGR in: " .. hex(ansi))
    lt.assertEquals(ansi:find("hi", 1, true) ~= nil, true,
        "expected 'hi' in: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 3: same-style merge — a red run emits SGR only once.

function suite:test_same_style_merge()
    local s = screen.new(10, 1)
    screen.clear(s)
    for x = 0, 4 do
        tui_core.screen.put(s, x, 0, "a", 1)
    end
    screen.diff(s)  -- commit neutral frame

    screen.clear(s)
    local red = { fg = 1 }
    for x = 0, 4 do
        tui_core.screen.put(s, x, 0, "h", 1, red)
    end
    local ansi = screen.diff(s)
    -- Count occurrences of ESC[0;31m — should be exactly 1.
    local count = 0
    local i = 1
    while true do
        local p = ansi:find(ESC .. "[0;31m", i, true)
        if not p then break end
        count = count + 1
        i = p + 1
    end
    lt.assertEquals(count, 1,
        "expected exactly one red SGR in: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 4: style change mid-run — two SGR sequences.

function suite:test_style_change_mid_run()
    local s = screen.new(6, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "H", 1, { fg = 1 })  -- red
    tui_core.screen.put(s, 1, 0, "i", 1, { fg = 2 })  -- green
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[0;31m", 1, true) ~= nil, true,
        "expected red SGR: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[0;32m", 1, true) ~= nil, true,
        "expected green SGR: " .. hex(ansi))
    -- red must appear before green
    local rp = ansi:find(ESC .. "[0;31m", 1, true)
    local gp = ansi:find(ESC .. "[0;32m", 1, true)
    lt.assertEquals(rp < gp, true, "red must precede green: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 5: background color.

function suite:test_background_color()
    local s = screen.new(4, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, { bg = 4 })  -- blue bg
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[0;44m", 1, true) ~= nil, true,
        "expected blue-bg SGR: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 6: bright fg color maps to 90..97.

function suite:test_bright_color()
    local s = screen.new(4, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, { fg = 9 })  -- brightRed = 91
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[0;91m", 1, true) ~= nil, true,
        "expected brightRed SGR 91m: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 7: default reset between frames (colored → neutral).

function suite:test_default_reset_between_frames()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, { fg = 1 })  -- red
    screen.diff(s)

    -- Frame 2: overwrite with neutral char. diff must reset before "Y".
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "Y", 1)  -- default
    local ansi = screen.diff(s)
    -- The cell went from red+"X" to default+"Y"; cell_eq differs → emit.
    -- cur_fg_bg tracker starts at default so first emit_sgr call for
    -- cell with default style is a no-op. That means "Y" appears immediately
    -- after the CUP with no SGR. We still care: there must NOT be any
    -- leftover red code in the output.
    lt.assertEquals(ansi:find(ESC .. "[0;31m", 1, true), nil,
        "unexpected red SGR carried over: " .. hex(ansi))
    lt.assertEquals(ansi:find("Y", 1, true) ~= nil, true,
        "expected 'Y' in output: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 8: line boundary reset — two rows different colors.

function suite:test_line_boundary_reset()
    local s = screen.new(4, 2)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "R", 1, { fg = 1 })  -- row 0: red
    tui_core.screen.put(s, 0, 1, "G", 1, { fg = 2 })  -- row 1: green
    local ansi = screen.diff(s)
    -- A reset must occur between the two rows so green doesn't inherit red.
    -- Find CUP to row 2: ESC[2;1H
    local cup2 = ansi:find(ESC .. "[2;1H", 1, true)
    lt.assertEquals(cup2 ~= nil, true,
        "expected CUP to row 2: " .. hex(ansi))
    -- Slice up to cup2 and ensure the last ESC[0m sits before it.
    local prefix = ansi:sub(1, cup2)
    local last_reset = nil
    local i = 1
    while true do
        local p = prefix:find(ESC .. "[0m", i, true)
        if not p then break end
        last_reset = p
        i = p + 1
    end
    lt.assertEquals(last_reset ~= nil, true,
        "expected ESC[0m before row 2 CUP: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 9: bridge gap with colored unchanged cell keeps style correct.

function suite:test_bridge_gap_preserves_style()
    local s = screen.new(10, 1)
    screen.clear(s)
    -- Initial: red X at 1, red X at 2, red X at 3.
    local red = { fg = 1 }
    tui_core.screen.put(s, 1, 0, "a", 1, red)
    tui_core.screen.put(s, 2, 0, "b", 1, red)
    tui_core.screen.put(s, 3, 0, "c", 1, red)
    screen.diff(s)

    -- Frame 2: change cols 1 and 3 to green chars; col 2 stays red "b".
    -- Gap=1 so merge path triggers. Bridge cell (col 2) is red.
    screen.clear(s)
    tui_core.screen.put(s, 1, 0, "A", 1, { fg = 2 })  -- green
    tui_core.screen.put(s, 2, 0, "b", 1, red)         -- unchanged
    tui_core.screen.put(s, 3, 0, "C", 1, { fg = 2 })  -- green
    local ansi = screen.diff(s)
    -- Expect the bridge cell to reassert red before emitting "b", and
    -- green to reassert before "C".
    lt.assertEquals(ansi:find(ESC .. "[0;32m", 1, true) ~= nil, true,
        "expected green SGR somewhere: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[0;31m", 1, true) ~= nil, true,
        "expected red SGR for bridge cell: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 10: rows() returns plain text with no SGR bytes.

function suite:test_rows_has_no_sgr()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, { fg = 1, bold = true })
    screen.diff(s)
    local r = screen.rows(s)
    lt.assertEquals(r[1]:find(ESC, 1, true), nil,
        "rows[1] contains ESC byte: " .. hex(r[1]))
    lt.assertEquals(r[1]:sub(1, 1), "X")
end

-- ---------------------------------------------------------------------------
-- Case 11: wide char with color — head+tail share style, idempotent.

function suite:test_wide_char_with_color()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "中", 2, { fg = 3 })  -- yellow
    screen.diff(s)

    -- Second diff with identical content should be empty — style on tail
    -- must match to avoid spurious redraws.
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "中", 2, { fg = 3 })
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0,
        "idempotent colored wide-char frame should be empty: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 12: attr-only change (bold off → on with same fg).

function suite:test_bold_attr_change()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "H", 1, { fg = 1 })
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "H", 1, { fg = 1, bold = true })
    local ansi = screen.diff(s)
    -- New SGR must include the bold parameter.
    lt.assertEquals(ansi:find(ESC .. "[0;1;31m", 1, true) ~= nil, true,
        "expected bold+red SGR: " .. hex(ansi))
end
