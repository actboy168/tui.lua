-- test/test_resize.lua — terminal resize edge cases.
--
-- Exercises the harness :resize() path which invalidates the screen ring
-- pool and forces a full repaint. Covers extreme sizes, rapid resizing,
-- and clipping of focused elements when the viewport shrinks.

local lt      = require "ltest"
local tui     = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"

local suite = lt.test "resize"

-- ---------------------------------------------------------------------------
-- 1. 1x1 viewport: the smallest legal size. Render a Box that tries to be
--    larger — layout clips to the single cell without crashing.

function suite:test_minimum_1x1_viewport()
    local function App()
        return tui.Box {
            width = 5, height = 5,
            flexDirection = "column",
            tui.Text { "hello" },
        }
    end
    local h = testing.render(App, { cols = 1, rows = 1 })
    local row = h:row(1)
    lt.assertEquals(#row, 1, "1-col viewport yields 1-byte row")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Very large viewport: 999x999 must allocate and render without error.

function suite:test_large_999x999_viewport()
    local function App()
        return tui.Box {
            width = 999, height = 999,
            flexDirection = "column",
            tui.Text { "ok" },
        }
    end
    local h = testing.render(App, { cols = 999, rows = 999 })
    lt.assertEquals(h:row(1):sub(1, 2), "ok")
    -- Bottom row should be all spaces (no content there).
    lt.assertEquals(h:row(999):sub(1, 5), "     ")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. Rapid sequence of resizes: each resize invalidates the row ring and
--    forces full repaint. 10 different sizes in a row must not crash and
--    must end in the final state.

function suite:test_rapid_resize_sequence()
    local function App()
        return tui.Box {
            width = 200, height = 100,
            flexDirection = "column",
            tui.Text { "content" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    local sizes = {
        { 10,  3 }, { 50, 20 }, { 5,  2 }, { 100, 50 }, { 1, 1 },
        { 40, 10 }, { 80, 24 }, { 30, 8 }, { 120, 40 }, { 25, 5 },
    }
    for _, sz in ipairs(sizes) do
        h:resize(sz[1], sz[2])
    end
    -- Final size 25x5: row 1 should still show "content" (clipped to 7 cols).
    lt.assertEquals(h:row(1):sub(1, 7), "content")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. Focused element clipped by a shrink: TextInput remains focused (focus
--    state survives resize) but its render is clipped to the new viewport.

function suite:test_focused_element_clipped_after_shrink()
    local value = "hello_world_abc"
    local function App()
        return tui.Box {
            width = 30, height = 1,
            extra.TextInput {
                value = value,
                onChange = function(v) value = v end,
                focusId = "only",
            },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 1 })
    lt.assertEquals(h:focus_id(), "only")
    -- Shrink viewport to fewer cols than the input's content.
    h:resize(5, 1)
    lt.assertEquals(h:focus_id(), "only",
        "focus must survive a viewport resize")
    local row = h:row(1)
    lt.assertEquals(#row, 5, "row length matches new viewport width")
    h:unmount()
end
