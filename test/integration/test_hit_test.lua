local lt       = require "ltest"
local testing  = require "tui.testing"
local tui      = require "tui"
local hit_test = require "tui.internal.hit_test"

local suite = lt.test "hit_test_integration"

function suite:teardown()
    hit_test._reset()
end

-- ---------------------------------------------------------------------------
-- Harness click tests (row_offset matches production behavior)
-- ---------------------------------------------------------------------------

function suite:test_harness_click_on_full_height_content()
    -- Content fills the terminal (height=4 == rows) → row_offset = 0, coordinates aligned.
    local clicked = false
    local App = function()
        return tui.Box {
            flexDirection = "column",
            height = 4,
            tui.Box {
                onClick = function() clicked = true end,
                tui.Text { "Click" },
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 4 })
    local cx, cy = h:sgr(0, 0)
    h:mouse("down", 1, cx, cy)
    h:rerender()
    lt.assertTrue(clicked)
    h:unmount()
end

function suite:test_harness_click_with_short_content()
    -- Content is shorter than terminal height → row_offset > 0.
    -- h:sgr() handles the offset automatically.
    local clicked = false
    local App = function()
        return tui.Box {
            onClick = function() clicked = true end,
            tui.Text { "Hi" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 10 })
    -- row_offset = 10 - content_h; content is 1 row, so offset = 9.
    -- Content row 0 is at SGR row 10.  h:sgr(0,0) returns (1, 10).
    local cx, cy = h:sgr(0, 0)
    h:mouse("down", 1, cx, cy)
    h:rerender()
    lt.assertTrue(clicked)
    h:unmount()
end

function suite:test_harness_row_offset_with_short_content()
    -- Verify that the harness calculates a non-zero row_offset when
    -- content height < terminal height, matching production behavior.
    local App = function()
        return tui.Box {
            tui.Text { "Content" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 10 })
    -- Content is 1 row, terminal is 10 rows → offset = 9
    lt.assertEquals(h:row_offset(), 9)

    -- Clicking at SGR row 1 (terminal top) should miss the content.
    lt.assertEquals(hit_test.hit_test(1, 1), nil)

    -- Clicking at the content's SGR position should hit.
    local cx, cy = h:sgr(0, 0)
    lt.assertNotEquals(hit_test.hit_test(cx, cy), nil)
    h:unmount()
end

function suite:test_harness_full_height_has_zero_offset()
    -- When content fills the terminal, row_offset should be 0.
    testing.capture_stderr(function()
        local App = function()
            return tui.Box {
                height = 5,
                tui.Text { key = "1", "Line 1" },
                tui.Text { key = "2", "Line 2" },
                tui.Text { key = "3", "Line 3" },
                tui.Text { key = "4", "Line 4" },
                tui.Text { key = "5", "Line 5" },
            }
        end
        local h = testing.render(App, { cols = 20, rows = 5 })
        lt.assertEquals(h:row_offset(), 0)
        h:unmount()
    end)
end

-- ---------------------------------------------------------------------------
-- Unit-level test: manual row_offset override
-- ---------------------------------------------------------------------------

function suite:test_row_offset_shifts_hit_target()
    -- Simulate a production scenario: terminal 24 rows, content 10 rows.
    -- After paint, row_offset = 24 - 10 = 14.
    -- Content row 0 is at terminal row 15 (1-based).
    local App = function()
        return tui.Box {
            onClick = function() end,
            tui.Text { "Content" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 24 })

    -- Override row_offset to simulate a different production scenario
    hit_test.set_row_offset(14)
    hit_test.set_tree(h:tree())

    -- SGR row 15 → content row 0 → should hit
    local path = hit_test.hit_test(1, 15)
    lt.assertNotEquals(path, nil, "should hit content at SGR row 15 with offset 14")

    -- SGR row 14 → content row -1 → should miss
    lt.assertEquals(hit_test.hit_test(1, 14), nil)

    h:unmount()
end
