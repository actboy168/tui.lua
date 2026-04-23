-- test/test_screen_sgr.lua — unit tests for Stage 11 incremental SGR diff.
-- These talk to the C module directly (via tui.screen + tui_core.screen)
-- to verify the byte-level ANSI output. After Stage 11 the writer emits
-- only the deltas between the current and next styles (no leading "0;"
-- reset on every transition).
--
-- Stage 16: style packing uses the C-side StylePool.
-- intern(s, style) maps the old {fg=N, bg=N, bold=...} shape to a
-- style_id via screen_c.intern_style so assertion bodies stay readable.

local lt        = require "ltest"
local screen    = require "tui.internal.screen"
local tui_core  = require "tui.core"
local screen_c  = tui_core.screen

local suite = lt.test "screen_sgr"

local <const> ESC = "\27"

local <const> ATTR_BOLD      = 0x01
local <const> ATTR_DIM       = 0x02
local <const> ATTR_UNDERLINE = 0x04
local <const> ATTR_INVERSE   = 0x08
local <const> COLOR_MODE_DEFAULT = 0
local <const> COLOR_MODE_16      = 1

-- Translate the old {fg=N, bg=N, bold=...} shape to a style_id.
-- fg/bg are ANSI 16-color indices (0..15); nil means terminal default.
local function intern(s, style)
    if not style then return 0 end
    local fg_mode, fg_val = COLOR_MODE_DEFAULT, 0
    local bg_mode, bg_val = COLOR_MODE_DEFAULT, 0
    local attrs = 0
    if style.fg  ~= nil then fg_mode, fg_val = COLOR_MODE_16, style.fg  end
    if style.bg  ~= nil then bg_mode, bg_val = COLOR_MODE_16, style.bg  end
    if style.bold      then attrs = attrs | ATTR_BOLD      end
    if style.dim       then attrs = attrs | ATTR_DIM       end
    if style.underline then attrs = attrs | ATTR_UNDERLINE end
    if style.inverse   then attrs = attrs | ATTR_INVERSE   end
    return screen_c.intern_style(s, fg_mode, fg_val, bg_mode, bg_val, attrs)
end

local function hex(s)
    return (s:gsub(ESC, "<ESC>"))
end

-- ---------------------------------------------------------------------------
-- Case 1: single-cell colored first frame.

function suite:test_single_cell_colored_first_frame()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, intern(s, { fg = 1 }))  -- red
    local ansi = screen.diff(s)
    -- Incremental diff: ESC[31m (delta from default), not ESC[0;31m.
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "expected red SGR in: " .. hex(ansi))
    -- Trailing spaces on first frame now inherit red style, so the row
    -- ends with ESC[39m (fg reset delta) before the diff's safety ESC[0m.
    lt.assertEquals(ansi:find("X", 1, true) ~= nil, true,
        "expected X in output: " .. hex(ansi))
    -- Diff-end safety net: trailing ESC[0m must still appear.
    lt.assertEquals(ansi:find(ESC .. "[0m", 1, true) ~= nil, true,
        "expected final ESC[0m safety reset: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 2: draw_line colored with bold.

function suite:test_draw_line_colored_bold()
    local s = screen.new(10, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "a", 1)  -- neutral frame 1
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.draw_line(s, 0, 0, "hi", 10, intern(s, { fg = 2, bold = true }))
    local ansi = screen.diff(s)
    -- Incremental delta from (default, no attrs): ESC[1;32m.
    lt.assertEquals(ansi:find(ESC .. "[1;32m", 1, true) ~= nil, true,
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
    local red_id = intern(s, { fg = 1 })
    for x = 0, 4 do
        tui_core.screen.put(s, x, 0, "h", 1, red_id)
    end
    local ansi = screen.diff(s)
    -- Count occurrences of ESC[31m (incremental form) — should be exactly 1.
    local count = 0
    local i = 1
    while true do
        local p = ansi:find(ESC .. "[31m", i, true)
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
    tui_core.screen.put(s, 0, 0, "H", 1, intern(s, { fg = 1 }))  -- red
    tui_core.screen.put(s, 1, 0, "i", 1, intern(s, { fg = 2 }))  -- green
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "expected red SGR: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true) ~= nil, true,
        "expected green SGR: " .. hex(ansi))
    -- red must appear before green
    local rp = ansi:find(ESC .. "[31m", 1, true)
    local gp = ansi:find(ESC .. "[32m", 1, true)
    lt.assertEquals(rp < gp, true, "red must precede green: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 5: background color.

function suite:test_background_color()
    local s = screen.new(4, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, intern(s, { bg = 4 }))  -- blue bg
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[44m", 1, true) ~= nil, true,
        "expected blue-bg SGR: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 6: bright fg color maps to 90..97.

function suite:test_bright_color()
    local s = screen.new(4, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, intern(s, { fg = 9 }))  -- brightRed = 91
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find(ESC .. "[91m", 1, true) ~= nil, true,
        "expected brightRed SGR 91m: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 7: default reset between frames (colored → neutral).

function suite:test_default_reset_between_frames()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, intern(s, { fg = 1 }))  -- red
    screen.diff(s)

    -- Frame 2: overwrite with neutral char.The diff-end safety reset at
    -- the tail of frame 1 put the tracker back to default, so frame 2's
    -- default-style "Y" needs zero SGR prefix — yet crucially must NOT
    -- carry any red code over.
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "Y", 1)  -- default
    local ansi = screen.diff(s)
    lt.assertEquals(ansi:find("Y", 1, true) ~= nil, true,
        "expected 'Y' in output: " .. hex(ansi))
    -- No stray red SGR re-emitted.
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true), nil,
        "unexpected red SGR re-emitted: " .. hex(ansi))
    -- And no "0;31m" leftover either (Stage 10 regression guard).
    lt.assertEquals(ansi:find(ESC .. "[0;31m", 1, true), nil,
        "unexpected full-form red SGR: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 8: line boundary reset — two rows different colors.

function suite:test_line_boundary_sgr_inheritance()
    -- Stage 11: SGR state is explicitly NOT reset at row boundaries.
    -- The second row's first colored cell must emit the delta (ESC[32m)
    -- since the tracker still remembers red from row 1.
    local s = screen.new(4, 2)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "R", 1, intern(s, { fg = 1 }))  -- row 0: red
    tui_core.screen.put(s, 0, 1, "G", 1, intern(s, { fg = 2 }))  -- row 1: green
    local ansi = screen.diff(s)
    local cup2 = ansi:find(ESC .. "[2;1H", 1, true)
    lt.assertEquals(cup2 ~= nil, true,
        "expected CUP to row 2: " .. hex(ansi))
    -- Prefix (through the row-2 CUP) must NOT contain an ESC[0m. Stage 11
    -- carries SGR state across row boundaries instead of resetting.
    local prefix = ansi:sub(1, cup2)
    lt.assertEquals(prefix:find(ESC .. "[0m", 1, true), nil,
        "row boundary must not emit ESC[0m (Stage 11): " .. hex(ansi))
    -- And the switch red→green must land as an ESC[32m delta.
    lt.assertEquals(ansi:find(ESC .. "[32m", cup2, true) ~= nil, true,
        "expected green delta after row-2 CUP: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 9: bridge gap with colored unchanged cell keeps style correct.

function suite:test_bridge_gap_preserves_style()
    local s = screen.new(10, 1)
    screen.clear(s)
    -- Initial: red X at 1, red X at 2, red X at 3.
    local red_id = intern(s, { fg = 1 })
    tui_core.screen.put(s, 1, 0, "a", 1, red_id)
    tui_core.screen.put(s, 2, 0, "b", 1, red_id)
    tui_core.screen.put(s, 3, 0, "c", 1, red_id)
    screen.diff(s)

    -- Frame 2: change cols 1 and 3 to green chars; col 2 stays red "b".
    -- Gap=1 so merge path triggers. Bridge cell (col 2) is red.
    screen.clear(s)
    tui_core.screen.put(s, 1, 0, "A", 1, intern(s, { fg = 2 }))  -- green
    tui_core.screen.put(s, 2, 0, "b", 1, red_id) -- unchanged
    tui_core.screen.put(s, 3, 0, "C", 1, intern(s, { fg = 2 }))  -- green
    local ansi = screen.diff(s)
    -- Expect the bridge cell to reassert red before emitting "b", and
    -- green to reassert before "C".
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true) ~= nil, true,
        "expected green SGR somewhere: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "expected red SGR for bridge cell: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 10: rows() returns plain text with no SGR bytes.

function suite:test_rows_has_no_sgr()
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "X", 1, intern(s, { fg = 1, bold = true }))
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
    tui_core.screen.put(s, 0, 0, "中", 2, intern(s, { fg = 3 }))  -- yellow
    screen.diff(s)

    -- Second diff with identical content should be empty — style on tail
    -- must match to avoid spurious redraws.
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "中", 2, intern(s, { fg = 3 }))
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0,
        "idempotent colored wide-char frame should be empty: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 12: attr-only change (bold off → on with same fg).

function suite:test_bold_attr_change()
    -- To observe incremental delta (bold-only toggle on unchanged fg) we
    -- need a single frame that transitions from (red) to (red+bold) to
    -- (red) \u2014 same frame so the tracker isn't reset between cells.
    local s = screen.new(3, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "A", 1, intern(s, { fg = 1 }))              -- red
    tui_core.screen.put(s, 1, 0, "B", 1, intern(s, { fg = 1, bold = true })) -- red+bold
    tui_core.screen.put(s, 2, 0, "C", 1, intern(s, { fg = 1 }))              -- red again
    local ansi = screen.diff(s)

    -- First SGR: entering red from default \u2192 "ESC[31m".
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "expected initial red delta ESC[31m: " .. hex(ansi))
    -- Second SGR: only bold flips on (fg unchanged) \u2192 "ESC[1m", NOT "ESC[1;31m".
    lt.assertEquals(ansi:find(ESC .. "[1m", 1, true) ~= nil, true,
        "expected bold-only delta ESC[1m: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[1;31m", 1, true), nil,
        "should not re-emit fg when only bold toggled on: " .. hex(ansi))
    -- Third SGR: bold flips off (22m) \u2192 must appear.
    lt.assertEquals(ansi:find(ESC .. "[22m", 1, true) ~= nil, true,
        "expected ESC[22m to clear bold: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 13 (Stage 15): wide-char \u2192 narrow-char with SGR transition. The tail
-- cell of a wide glyph inherits the head cell's style; a narrow glyph that
-- follows with a different style must emit a fresh SGR.

function suite:test_wide_to_narrow_sgr_transition()
    local s = screen.new(4, 1)
    screen.clear(s)
    screen.diff(s)

    screen.clear(s)
    tui_core.screen.put(s, 0, 0, "\228\184\173", 2, intern(s, { fg = 2 }))  -- 中, green
    tui_core.screen.put(s, 2, 0, "X", 1, intern(s, { fg = 4 }))             -- X, blue
    local ansi = screen.diff(s)

    -- Must emit green at start and blue at the narrow glyph.
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true) ~= nil, true,
        "expected ESC[32m (green) for wide char: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[34m", 1, true) ~= nil, true,
        "expected ESC[34m (blue) for narrow char after wide: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Case 14 (Stage 15): base emoji + skin-tone modifier + ZWJ sequence renders
-- as a single wide cluster with a single style.

function suite:test_skin_tone_zwj_single_cluster_styled()
    -- 👨🏻 (man + skin tone 1-2) = 8 bytes, width 2.
    local man_skin = "\240\159\145\168\240\159\143\187"
    local s = screen.new(4, 1)
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, man_skin, 2, intern(s, { fg = 3 }))  -- yellow
    screen.diff(s)

    -- Second identical frame: no diff.
    screen.clear(s)
    tui_core.screen.put(s, 0, 0, man_skin, 2, intern(s, { fg = 3 }))
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0,
        "skin-tone emoji cluster must be idempotent: " .. hex(ansi))
end

function suite:test_screen_size()
    local s = screen.new(30, 10)
    local w, h = screen.size(s)
    lt.assertEquals(w, 30)
    lt.assertEquals(h, 10)
end
