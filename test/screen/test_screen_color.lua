-- test/screen/test_screen_color.lua
-- Integration tests for the Truecolor / StylePool feature (Stage 16).
--
-- Tests cover:
--   • 16-color SGR codes (30-37 fg, 40-47 bg, 90-97 bright fg, 100-107 bright bg)
--   • 256-color SGR: ESC[38;5;Nm / ESC[48;5;Nm
--   • 24-bit truecolor SGR: ESC[38;2;R;G;Bm / ESC[48;2;R;G;Bm
--   • Downgrade: 24-bit at level=1 → 256-color; at level=0 → 16-color
--   • Downgrade: 256-color at level=0 → 16-color
--   • cells() return types: nil / integer / "#RRGGBB"
--   • pack_style + cells() roundtrip for all color modes
--   • style_id=0 default (no SGR prefix)

local lt       = require "ltest"
local screen   = require "tui.internal.screen"
local sgr      = require "tui.internal.sgr"
local tui_core = require "tui_core"
local screen_c = tui_core.screen

local suite = lt.test "screen_color"

local <const> ESC = "\27"

local function hex(s)
    return (s:gsub(ESC, "<ESC>"))
end

-- Helper: new screen already past first frame (so diffs are incremental),
-- with truecolor enabled by default.
local function make_screen(w, h, level)
    local s = screen.new(w or 4, h or 1)
    screen_c.set_color_level(s, level or 2)
    screen.clear(s)
    screen.diff(s)  -- commit blank first frame
    return s
end

-- Helper: put one char with a style, run diff, return ANSI output.
local function diff_one(s, props)
    screen.clear(s)
    local style_id = sgr.pack_style(s, props)
    screen_c.put(s, 0, 0, "X", 1, style_id)
    return screen.diff(s)
end

-- ---------------------------------------------------------------------------
-- 16-color fg/bg

function suite:test_16color_fg_normal()
    local s = make_screen()
    local ansi = diff_one(s, { color = "green" })  -- index 2 → ESC[32m
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true) ~= nil, true,
        "expected ESC[32m: " .. hex(ansi))
end

function suite:test_16color_fg_bright()
    local s = make_screen()
    local ansi = diff_one(s, { color = "brightBlue" })  -- index 12 → ESC[94m
    lt.assertEquals(ansi:find(ESC .. "[94m", 1, true) ~= nil, true,
        "expected ESC[94m: " .. hex(ansi))
end

function suite:test_16color_bg_normal()
    local s = make_screen()
    local ansi = diff_one(s, { backgroundColor = "red" })  -- index 1 → ESC[41m
    lt.assertEquals(ansi:find(ESC .. "[41m", 1, true) ~= nil, true,
        "expected ESC[41m: " .. hex(ansi))
end

function suite:test_16color_bg_bright()
    local s = make_screen()
    local ansi = diff_one(s, { backgroundColor = "brightCyan" })  -- index 14 → ESC[106m
    lt.assertEquals(ansi:find(ESC .. "[106m", 1, true) ~= nil, true,
        "expected ESC[106m: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- 256-color fg/bg (color_level >= 1)

function suite:test_256color_fg_emit()
    local s = make_screen(4, 1, 1)  -- level=256
    local ansi = diff_one(s, { color = 200 })
    lt.assertEquals(ansi:find(ESC .. "[38;5;200m", 1, true) ~= nil, true,
        "expected ESC[38;5;200m: " .. hex(ansi))
end

function suite:test_256color_bg_emit()
    local s = make_screen(4, 1, 1)
    local ansi = diff_one(s, { backgroundColor = 100 })
    lt.assertEquals(ansi:find(ESC .. "[48;5;100m", 1, true) ~= nil, true,
        "expected ESC[48;5;100m: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- 24-bit truecolor fg/bg (color_level = 2)

function suite:test_truecolor_fg_emit()
    local s = make_screen(4, 1, 2)
    local ansi = diff_one(s, { color = "#FF4080" })
    lt.assertEquals(ansi:find(ESC .. "[38;2;255;64;128m", 1, true) ~= nil, true,
        "expected ESC[38;2;255;64;128m: " .. hex(ansi))
end

function suite:test_truecolor_bg_emit()
    local s = make_screen(4, 1, 2)
    local ansi = diff_one(s, { backgroundColor = "#001122" })
    lt.assertEquals(ansi:find(ESC .. "[48;2;0;17;34m", 1, true) ~= nil, true,
        "expected ESC[48;2;0;17;34m: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Downgrade: truecolor → 256-color at level=1

function suite:test_truecolor_downgrade_to_256()
    local s = make_screen(4, 1, 1)  -- level=256, not truecolor
    -- #FF0000 = pure red → closest xterm-256 is index 196
    local ansi = diff_one(s, { color = "#FF0000" })
    -- Should use 256-color form, not 24-bit
    lt.assertEquals(ansi:find(ESC .. "[38;2;", 1, true), nil,
        "must not emit 24-bit at level=1: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[38;5;", 1, true) ~= nil, true,
        "expected 256-color form at level=1: " .. hex(ansi))
end

-- Downgrade: truecolor → 16-color at level=0

function suite:test_truecolor_downgrade_to_16()
    local s = make_screen(4, 1, 0)  -- level=16
    local ansi = diff_one(s, { color = "#FF0000" })
    -- Must not emit 24-bit or 256-color sequences
    lt.assertEquals(ansi:find(ESC .. "[38;2;", 1, true), nil,
        "must not emit 24-bit at level=0: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[38;5;", 1, true), nil,
        "must not emit 256-color at level=0: " .. hex(ansi))
    -- Must emit a basic ANSI color code (30-37 or 90-97)
    lt.assertEquals(ansi:find(ESC .. "[3", 1, true) ~= nil or
                    ansi:find(ESC .. "[9", 1, true) ~= nil, true,
        "expected 16-color ANSI code at level=0: " .. hex(ansi))
end

-- Downgrade: 256-color → 16-color at level=0

function suite:test_256color_downgrade_to_16()
    local s = make_screen(4, 1, 0)
    local ansi = diff_one(s, { color = 200 })
    lt.assertEquals(ansi:find(ESC .. "[38;5;", 1, true), nil,
        "must not emit 256-color at level=0: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- cells() return value format

function suite:test_cells_default_is_nil()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    screen.clear(s)
    screen_c.put(s, 0, 0, "X", 1, 0)  -- style_id=0 = default
    screen.diff(s)
    local c = screen_c.cells(s, 1)[1]
    lt.assertEquals(c.fg, nil)
    lt.assertEquals(c.bg, nil)
end

function suite:test_cells_16color_returns_integer()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    screen.clear(s)
    local id = sgr.pack_style(s, { color = "cyan" })  -- index 6
    screen_c.put(s, 0, 0, "X", 1, id)
    screen.diff(s)
    local c = screen_c.cells(s, 1)[1]
    lt.assertEquals(c.fg, 6)
end

function suite:test_cells_256color_returns_integer()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    screen.clear(s)
    local id = sgr.pack_style(s, { color = 200 })
    screen_c.put(s, 0, 0, "X", 1, id)
    screen.diff(s)
    local c = screen_c.cells(s, 1)[1]
    lt.assertEquals(c.fg, 200)
end

function suite:test_cells_truecolor_returns_hex_string()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    screen.clear(s)
    local id = sgr.pack_style(s, { color = "#AABBCC" })
    screen_c.put(s, 0, 0, "X", 1, id)
    screen.diff(s)
    local c = screen_c.cells(s, 1)[1]
    lt.assertEquals(type(c.fg), "string")
    lt.assertEquals(c.fg:lower(), "#aabbcc")
end

-- ---------------------------------------------------------------------------
-- Style pool: same props → same style_id

function suite:test_same_props_same_id()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    local id1 = sgr.pack_style(s, { color = "red", bold = true })
    local id2 = sgr.pack_style(s, { color = "red", bold = true })
    lt.assertEquals(id1, id2)
end

function suite:test_diff_props_diff_id()
    local s = screen.new(4, 1)
    screen_c.set_color_level(s, 2)
    local id1 = sgr.pack_style(s, { color = "red" })
    local id2 = sgr.pack_style(s, { color = "blue" })
    lt.assertNotEquals(id1, id2)
end

-- ---------------------------------------------------------------------------
-- Style_id=0 → no SGR prefix emitted

function suite:test_default_style_no_sgr()
    local s = make_screen()
    screen.clear(s)
    screen_c.put(s, 0, 0, "A", 1, 0)
    local ansi = screen.diff(s)
    -- No color/attribute codes should appear (only cursor positioning + char)
    lt.assertEquals(ansi:find(ESC .. "[3", 1, true), nil,
        "default style must not emit fg SGR: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[4", 1, true), nil,
        "default style must not emit bg SGR: " .. hex(ansi))
    lt.assertEquals(ansi:find(ESC .. "[1m", 1, true), nil,
        "default style must not emit bold SGR: " .. hex(ansi))
end

-- ---------------------------------------------------------------------------
-- Idempotency: same style across two frames → zero diff

function suite:test_truecolor_idempotent()
    local s = make_screen(4, 1, 2)
    local id = sgr.pack_style(s, { color = "#123456" })
    screen.clear(s)
    screen_c.put(s, 0, 0, "X", 1, id)
    screen.diff(s)

    -- Identical second frame
    screen.clear(s)
    screen_c.put(s, 0, 0, "X", 1, id)
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0,
        "identical truecolor frame should produce empty diff: " .. hex(ansi))
end

function suite:test_256color_idempotent()
    local s = make_screen(4, 1, 1)
    local id = sgr.pack_style(s, { color = 150 })
    screen.clear(s)
    screen_c.put(s, 0, 0, "X", 1, id)
    screen.diff(s)

    screen.clear(s)
    screen_c.put(s, 0, 0, "X", 1, id)
    local ansi = screen.diff(s)
    lt.assertEquals(#ansi, 0,
        "identical 256-color frame should produce empty diff: " .. hex(ansi))
end
