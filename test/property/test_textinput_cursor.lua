-- test/property/test_textinput_cursor.lua — cursor position stays within bounds.
--
-- Property: for any TextInput value / terminal size / border / padding
-- configuration, the cursor position reported by h:cursor() is a valid
-- screen coordinate and consistent with the text element's position.
--
-- Known bug: when TextInput has no explicit `width` prop and the text is
-- wider than the container, the pre-layout caret_col can exceed the
-- post-layout element rect, placing the cursor outside the screen.
-- See roadmap: "TextInput 无 width prop 光标越界".

local lt      = require "ltest"
local tui     = require "tui"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local extra = require "tui.extra"
local testing = require "tui.testing"
local pbt     = require "test.property.pbt"

local suite = lt.test "textinput_cursor"

-- ---------------------------------------------------------------------------
-- Cursor validity check.
-- h:cursor() returns (col, row) 1-based.
--
-- The cursor is a vertical bar between cells.  When the caret is at the end
-- of the text (insert position), cursor col can be one past the text element's
-- right edge — i.e. rect.x + rect.w + 1.  This is valid terminal behavior.
--
-- Invariant:
--   1 ≤ row ≤ screen_height
--   1 ≤ col ≤ screen_width
--   row is on the text element's row
--   col is within [rect.x + 1, rect.x + rect.w + 1]

local function assert_cursor_valid(h)
    local col, row = h:cursor()
    if col == nil then return end  -- no cursor (unfocused), OK

    local sw, sh = h:width(), h:height()

    if col < 1 then
        error(("cursor col %d < 1"):format(col), 0)
    end
    if col > sw then
        error(("cursor col %d > screen width %d"):format(col, sw), 0)
    end
    if row < 1 then
        error(("cursor row %d < 1"):format(row), 0)
    end
    if row > sh then
        error(("cursor row %d > screen height %d"):format(row, sh), 0)
    end

    local te = testing.find_text_with_cursor(h:tree())
    if te and te.rect then
        local r = te.rect
        -- Row must be on the text element.
        if row < r.y + 1 or row > r.y + r.h then
            error(("cursor row %d outside text element rows [%d, %d]"):format(
                row, r.y + 1, r.y + r.h), 0)
        end
        -- Col must be within text element + 1 (insert position at end).
        if col < r.x + 1 then
            error(("cursor col %d before text element start %d"):format(
                col, r.x + 1), 0)
        end
        if col > r.x + r.w + 1 then
            error(("cursor col %d past text element end+1 %d"):format(
                col, r.x + r.w + 1), 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Test 1: random value and explicit width

function suite:test_cursor_within_bounds_random_value()
    pbt.check {
        name       = "cursor within bounds for random value/size",
        iterations = 100,
        property   = function(rng)
            local value_len = rng.int(0, 50)
            local value     = rng.graphemes(value_len)
            local cols = rng.int(5, 120)
            local rows = rng.int(1, 10)
            -- Always set an explicit width so render_width matches layout.
            local width_prop = rng.int(3, cols - 2)

            local v = value
            local function App()
                return tui.Box {
                    width = cols, height = rows,
                    extra.TextInput {
                        value = v,
                        onChange = function(nv) v = nv end,
                        width = width_prop,
                    },
                }
            end

            local h = testing.render(App, { cols = cols, rows = rows })
            h:rerender()  -- consume autoFocus isFocused state
            local ok, err = pcall(assert_cursor_valid, h)
            h:unmount()
            if not ok then error(err, 0) end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Test 2: with border and padding

function suite:test_cursor_within_bounds_with_border()
    pbt.check {
        name       = "cursor within bounds with border/padding",
        iterations = 100,
        property   = function(rng)
            local value_len = rng.int(0, 50)
            local value     = rng.graphemes(value_len)
            local cols  = rng.int(10, 120)
            local border = rng.pick({ nil, "single", "round" })
            local padX = rng.int(0, 3)
            local padY = rng.int(0, 3)
            local rows_min = 3 + padY * 2
            if border then rows_min = rows_min + 2 end
            local rows  = rng.int(rows_min, rows_min + 7)
            -- Compute max TextInput width respecting border/padding.
            local content_width = cols - padX * 2
            if border then content_width = content_width - 2 end
            if content_width < 3 then content_width = 3 end
            local width_prop = rng.int(3, content_width)

            local v = value
            local function App()
                local props = {
                    width = cols, height = rows,
                    extra.TextInput {
                        value = v,
                        onChange = function(nv) v = nv end,
                        width = width_prop,
                    },
                }
                if border then props.borderStyle = border end
                if padX > 0 then props.paddingX = padX end
                if padY > 0 then props.paddingY = padY end
                return tui.Box(props)
            end

            local h = testing.render(App, { cols = cols, rows = rows })
            h:rerender()
            local ok, err = pcall(assert_cursor_valid, h)
            h:unmount()
            if not ok then error(err, 0) end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Test 3: after caret navigation

function suite:test_cursor_within_bounds_after_navigation()
    pbt.check {
        name       = "cursor within bounds after caret navigation",
        iterations = 100,
        property   = function(rng)
            local value_len = rng.int(1, 30)
            local value     = rng.graphemes(value_len)
            local cols = rng.int(10, 80)
            local rows = rng.int(1, 5)
            -- Explicit width to keep cursor in-bounds after layout.
            local width_prop = rng.int(3, cols - 2)

            local v = value
            local function App()
                return tui.Box {
                    width = cols, height = rows,
                    extra.TextInput {
                        value = v,
                        onChange = function(nv) v = nv end,
                        width = width_prop,
                    },
                }
            end

            local h = testing.render(App, { cols = cols, rows = rows })
            h:rerender()

            local <const> NAV_KEYS = { "home", "end", "left", "right" }
            local steps = rng.int(1, 10)
            local ok, err
            for _ = 1, steps do
                tui_input.press(rng.pick(NAV_KEYS))
                ok, err = pcall(assert_cursor_valid, h)
                if not ok then
                    h:unmount()
                    error(err, 0)
                end
            end

            h:unmount()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Test 4: auto-width (no explicit width prop)
-- SKIP: triggers "TextInput 无 width prop 光标越界" bug — when the text
-- is wider than the container, caret_col exceeds the actual layout width.
-- Will be enabled once useMeasure is implemented.

function suite:test_cursor_within_bounds_auto_width()
    pbt.check {
        name       = "cursor within bounds for auto-width (no width prop)",
        iterations = 100,
        property   = function(rng)
            local value_len = rng.int(0, 50)
            local value     = rng.graphemes(value_len)
            local cols = rng.int(5, 120)
            local rows = rng.int(1, 10)

            local v = value
            local function App()
                return tui.Box {
                    width = cols, height = rows,
                    extra.TextInput {
                        value = v,
                        onChange = function(nv) v = nv end,
                    },
                }
            end

            local h = testing.render(App, { cols = cols, rows = rows })
            h:rerender()
            local ok, err = pcall(assert_cursor_valid, h)
            h:unmount()
            if not ok then error(err, 0) end
        end,
    }
end


