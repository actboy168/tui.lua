-- test/integration/test_text_inline.lua — inline mixed styles for Text elements.
--
-- Exercises the span-child syntax:
--   tui.Text { "plain ", {text="colored", color="red"}, " end" }
-- and verifies that each segment is rendered with the correct style while
-- plain-text fallback behaviour is preserved.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local vterm   = require "tui.testing.vterm"

local suite = lt.test "text_inline"

-- ============================================================================
-- Helpers
-- ============================================================================

-- Build a minimal App that renders a single Text element inside a fixed-size
-- Box, then returns the rendered cells for row 1.
local function cells_for(text_args, opts)
    opts = opts or {}
    local cols = opts.cols or 40
    local rows = opts.rows or 3
    local App = function()
        return tui.Box {
            width = cols, height = rows,
            tui.Text(text_args),
        }
    end
    local h = testing.harness(App, { cols = cols, rows = rows })
    local cells = h:cells(1)
    h:unmount()
    return cells
end

-- Return the text content of the cells as a concatenated string.
local function cells_text(cells)
    local parts = {}
    for _, c in ipairs(cells) do
        parts[#parts + 1] = c.char
    end
    return table.concat(parts)
end

-- ============================================================================
-- Backward-compatibility: plain strings are unchanged
-- ============================================================================

function suite:test_plain_string_unchanged()
    local cells = cells_for { "Hello, world!" }
    local text = cells_text(cells)
    lt.assertNotEquals(text:find("Hello, world!", 1, true), nil,
        "expected 'Hello, world!' in cells: got " .. text)
    -- no foreground colour on any printable cell
    for i = 1, 13 do
        lt.assertEquals(cells[i].fg, nil,
            "plain text should have no fg colour at col " .. i)
    end
end

function suite:test_multiple_plain_strings_concatenated()
    local cells = cells_for { "foo", "bar" }
    local text = cells_text(cells)
    lt.assertNotEquals(text:find("foobar", 1, true), nil,
        "expected 'foobar': got " .. text)
end

-- ============================================================================
-- Single span: colour
-- ============================================================================

function suite:test_span_color_applied()
    -- "AB" plain, then "CD" in red.
    local cells = cells_for { "AB", {text="CD", color="red"} }
    -- "AB" at columns 1-2 should have no fg
    lt.assertEquals(cells[1].fg, nil, "A: no fg")
    lt.assertEquals(cells[2].fg, nil, "B: no fg")
    -- "CD" at columns 3-4 should have red fg (index 1)
    lt.assertEquals(cells[3].fg, 1,   "C: red fg")
    lt.assertEquals(cells[4].fg, 1,   "D: red fg")
end

function suite:test_span_color_middle()
    -- Plain prefix, colored middle, plain suffix.
    local cells = cells_for { "X", {text="Y", color="blue"}, "Z" }
    lt.assertEquals(cells[1].fg, nil, "X: no fg")
    lt.assertEquals(cells[2].fg, 4,   "Y: blue fg")
    lt.assertEquals(cells[3].fg, nil, "Z: no fg")
end

-- ============================================================================
-- Span: bold and italic
-- ============================================================================

function suite:test_span_bold()
    local cells = cells_for { "A", {text="B", bold=true}, "C" }
    lt.assertEquals(cells[1].bold, false, "A: not bold")
    lt.assertEquals(cells[2].bold, true,  "B: bold")
    lt.assertEquals(cells[3].bold, false, "C: not bold")
end

function suite:test_span_italic()
    local cells = cells_for { "A", {text="B", italic=true}, "C" }
    lt.assertEquals(cells[1].italic, false, "A: not italic")
    lt.assertEquals(cells[2].italic, true,  "B: italic")
    lt.assertEquals(cells[3].italic, false, "C: not italic")
end

-- ============================================================================
-- Span: truecolor / 256-color
-- ============================================================================

function suite:test_span_truecolor()
    local cells = cells_for { {text="X", color="#ff8000"} }
    -- truecolor fg (case may vary from C snprintf, normalise to lower)
    local fg = cells[1].fg
    lt.assertEquals(type(fg), "string", "X: truecolor fg should be string")
    lt.assertEquals(fg:lower(), "#ff8000", "X: truecolor fg value")
end

function suite:test_span_256_color()
    local cells = cells_for { {text="X", color=200} }
    lt.assertEquals(cells[1].fg, 200, "X: 256-color fg")
end

-- ============================================================================
-- Colour inheritance from parent Box
-- ============================================================================

function suite:test_span_inherits_parent_color()
    -- Box sets color="green"; span that doesn't override should stay green.
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            color = "green",
            tui.Text { "A", {text="B", bold=true}, "C" },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 3 })
    local cells = h:cells(1)
    h:unmount()
    -- All three cells should have fg = green (index 2)
    lt.assertEquals(cells[1].fg, 2, "A: inherited green")
    lt.assertEquals(cells[2].fg, 2, "B: inherited green (bold span)")
    lt.assertEquals(cells[3].fg, 2, "C: inherited green")
    -- B should additionally be bold
    lt.assertEquals(cells[2].bold, true, "B: bold")
end

function suite:test_span_overrides_parent_color()
    -- Box color="green"; span overrides with color="red".
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            color = "green",
            tui.Text { "A", {text="B", color="red"}, "C" },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 3 })
    local cells = h:cells(1)
    h:unmount()
    lt.assertEquals(cells[1].fg, 2, "A: inherited green")
    lt.assertEquals(cells[2].fg, 1, "B: red override")
    lt.assertEquals(cells[3].fg, 2, "C: inherited green")
end

-- ============================================================================
-- Element-level props apply to all segments
-- ============================================================================

function suite:test_element_bold_inherits_to_plain_segs()
    -- The Text element itself is bold; all children should be bold.
    local cells = cells_for { bold = true, "A", {text="B", color="red"}, "C" }
    lt.assertEquals(cells[1].bold, true, "A: element bold")
    lt.assertEquals(cells[2].bold, true, "B: element bold retained")
    lt.assertEquals(cells[3].bold, true, "C: element bold")
    -- B has red fg
    lt.assertEquals(cells[2].fg, 1, "B: red fg")
end

-- ============================================================================
-- dimColor override by plain color
-- ============================================================================

function suite:test_span_color_clears_inherited_dimcolor()
    -- Element has dimColor="yellow" (dim+yellow); span sets color="cyan" →
    -- the span should be cyan without dim.
    local cells = cells_for { dimColor="yellow", "A", {text="B", color="cyan"} }
    -- A should have dim+yellow
    lt.assertEquals(cells[1].fg,  3,    "A: yellow fg")
    lt.assertEquals(cells[1].dim, true, "A: dim")
    -- B should have cyan without dim
    lt.assertEquals(cells[2].fg,  6,     "B: cyan fg")
    lt.assertEquals(cells[2].dim, false, "B: not dim")
end

-- ============================================================================
-- Multi-line wrapping with spans
-- ============================================================================

function suite:test_span_wrap_across_lines()
    -- "Hello " + {text="world", color="red"} in a 8-wide box.
    -- "Hello" fits on line 1; "world" wraps to line 2 in red.
    -- Text needs explicit width so Yoga constrains it (same as non-span text).
    local App = function()
        return tui.Box {
            width = 8, height = 4,
            tui.Text { width = 8, "Hello ", {text="world", color="red"} },
        }
    end
    local h = testing.harness(App, { cols = 8, rows = 4 })
    local row1 = h:cells(1)
    local row2 = h:cells(2)
    h:unmount()

    -- Row 1 contains "Hello"
    local t1 = cells_text(row1)
    lt.assertNotEquals(t1:find("Hello", 1, true), nil,
        "row1 should contain 'Hello': " .. t1)
    -- Row 1 cells are not red
    for i = 1, 5 do
        lt.assertEquals(row1[i].fg, nil,
            "row1 col" .. i .. " should have no red fg")
    end
    -- Row 2 contains "world" in red
    local t2 = cells_text(row2)
    lt.assertNotEquals(t2:find("world", 1, true), nil,
        "row2 should contain 'world': " .. t2)
    for i = 1, 5 do
        lt.assertEquals(row2[i].fg, 1,
            "row2 col" .. i .. " should have red fg")
    end
end

function suite:test_span_same_line_character_layout()
    -- Two spans on one line: exact character + color positions.
    -- Width=10: "Hi " (3) + {text="bye", color="blue"} (3) → fits on one line.
    local cells = cells_for({ "Hi ", {text="bye", color="blue"} }, { cols=10 })
    lt.assertEquals(cells[1].char, "H", "col1 = H")
    lt.assertEquals(cells[2].char, "i", "col2 = i")
    lt.assertEquals(cells[3].char, " ", "col3 = space")
    lt.assertEquals(cells[1].fg,   nil, "H: no fg")
    lt.assertEquals(cells[2].fg,   nil, "i: no fg")
    lt.assertEquals(cells[4].char, "b", "col4 = b")
    lt.assertEquals(cells[5].char, "y", "col5 = y")
    lt.assertEquals(cells[6].char, "e", "col6 = e")
    lt.assertEquals(cells[4].fg,   4,   "b: blue")
    lt.assertEquals(cells[5].fg,   4,   "y: blue")
    lt.assertEquals(cells[6].fg,   4,   "e: blue")
end

-- ============================================================================
-- Frame-level visual check
-- ============================================================================

function suite:test_frame_text_correct()
    -- Text content is correct regardless of styles.
    local App = function()
        return tui.Box {
            width = 20, height = 1,
            tui.Text { "foo", {text="bar", color="magenta"}, "baz" },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 1 })
    local frame = h:frame()
    h:unmount()
    lt.assertNotEquals(frame:find("foobarbaz", 1, true), nil,
        "frame should contain 'foobarbaz': " .. frame)
end

-- ============================================================================
-- Re-render stability
-- ============================================================================

function suite:test_rerender_stable()
    -- Re-rendering an app with inline spans produces no screen changes.
    local App = function()
        return tui.Box {
            width = 20, height = 2,
            tui.Text { "key=", {text="value", color="cyan"} },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 2 })
    local vt = h:vterm()
    -- Capture screen before rerender
    local before = vterm.screen_string(vt)
    h:rerender()
    local after = vterm.screen_string(vt)
    h:unmount()
    lt.assertEquals(after, before, "second render should not change screen content")
end

