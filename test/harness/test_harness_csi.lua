-- test/test_harness_csi.lua — CSI validation, cursor coordinates, and leak recovery tests

local lt      = require "ltest"
local tui     = require "tui"
local extra   = require "tui.extra"
local testing = require "tui.testing"

local suite = lt.test "harness_csi"

-- ============================================================================
-- CSI validation
-- ============================================================================

function suite.test_float_csi_fails_fatal()
    local function App() return tui.Text { "x" } end
    local h = testing.harness(App, { cols = 10, rows = 2 })

    local ok, err = pcall(function()
        h._terminal.write("\27[73.0;3.0H")
    end)
    lt.assertEquals(ok, false, "float CSI params must fail")
    lt.assertEquals(err:find("malformed CSI parameter", 1, true) ~= nil, true,
        "error should mention malformed CSI; got: " .. tostring(err))

    h:unmount()
end

function suite.test_valid_csi_passes()
    local function App() return tui.Text { "x" } end
    local h = testing.harness(App, { cols = 10, rows = 2 })

    h._terminal.write("\27[22;3H\27[0m\27[?25h\27[?25l")
    lt.assertEquals(type(h:ansi()), "string")
    h:unmount()
end

-- ============================================================================
-- Cursor integer coordinates
-- ============================================================================

local function is_integer(n)
    return type(n) == "number" and n == math.floor(n)
end

function suite:test_cursor_coords_are_integers_simple()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 40, height = 3,
            extra.TextInput { value = v, onChange = setV, autoFocus = true },
        }
    end
    local h = testing.harness(App, { cols = 40, rows = 3 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
    local col, row = h:cursor()
    lt.assertEquals(is_integer(col), true,
        ("cursor col must be integer, got %s"):format(tostring(col)))
    lt.assertEquals(is_integer(row), true,
        ("cursor row must be integer, got %s"):format(tostring(row)))
    h:unmount()
end

function suite:test_cursor_coords_are_integers_nested_flex()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            flexDirection = "column",
            width = 80, height = 75,
            tui.Box { key = "header", borderStyle = "round", paddingX = 1,
                tui.Text { key = "t", "title" },
            },
            tui.Box { key = "grow", flexGrow = 1 },
            tui.Box { key = "input", borderStyle = "round", paddingX = 1,
                extra.TextInput { value = v, onChange = setV, autoFocus = true },
            },
        }
    end
    local h = testing.harness(App, { cols = 80, rows = 75 })
    -- autoFocus sets isFocused state on the next paint.
    h:rerender()
    local col, row = h:cursor()
    lt.assertEquals(is_integer(col), true,
        ("cursor col must be integer, got %s"):format(tostring(col)))
    lt.assertEquals(is_integer(row), true,
        ("cursor row must be integer, got %s"):format(tostring(row)))
    h:unmount()
end

function suite:test_no_cursor_when_input_disabled()
    local function App()
        local v, setV = tui.useState("")
        return tui.Box {
            width = 40, height = 3,
            extra.TextInput { value = v, onChange = setV, focus = false },
        }
    end
    local h = testing.harness(App, { cols = 40, rows = 3 })
    local col, row = h:cursor()
    lt.assertEquals(col, nil, "disabled input should not advertise a cursor")
    lt.assertEquals(row, nil)
    h:unmount()
end

-- ============================================================================
-- CSI float detection via harness
-- ============================================================================

function suite.test_csi_rejects_float_coords()
    local h = testing.harness(function()
        return tui.Box {
            width = 10,
            height = 5,
            extra.TextInput { value = "test", focus = true }
        }
    end, { cols = 20, rows = 10 })
    -- focus=true implies autoFocus=true; isFocused state takes effect on
    -- the next paint.
    h:rerender()

    local col, row = h:cursor()
    if col and row then
        lt.assertEquals(math.type(col), "integer", "cursor col should be integer")
        lt.assertEquals(math.type(row), "integer", "cursor row should be integer")
    end
    h:unmount()
end

-- ============================================================================
-- Harness leak recovery
-- ============================================================================

function suite.test_leaked_harness_does_not_corrupt_next_render()
    local function App()
        return tui.Text { "first" }
    end
    local function App2()
        return tui.Text { "second" }
    end

    -- Deliberately leak: no :unmount() on the first harness.
    local h1 = testing.harness(App, { cols = 20, rows = 3 })
    -- Second render must work cleanly despite the leaked h1.
    local h2 = testing.harness(App2, { cols = 20, rows = 3 })

    -- h2 should render fresh content independently.
    lt.assertEquals(h2:row(1):find("second", 1, true) ~= nil, true,
                    "second harness should render fresh content")

    -- h1 still holds its own terminal state — verify it didn't get corrupted.
    lt.assertEquals(h1:row(1):find("first", 1, true) ~= nil, true,
                    "first harness should still hold its own state")

    h1:unmount()
    h2:unmount()
end

-- ============================================================================
-- Render count tracking (performance testing)
-- ============================================================================

function suite.test_harness_render_count_tracks_renders()
    local renders = 0
    local set_val
    local function App()
        renders = renders + 1
        local v, setV = tui.useState(0)
        set_val = setV
        return tui.Text { tostring(v) }
    end
    local h = testing.harness(App, { cols = 10, rows = 2 })

    -- Initial render only (no stabilization loop)
    h:expect_renders(1, "after initial render")

    -- Trigger setState then rerender
    set_val(1)
    h:rerender()

    -- Should have 2 renders: initial + after setState
    lt.assertEquals(h:render_count(), 2)
    lt.assertEquals(renders, 2)

    -- Reset and verify manual rerender
    h:reset_render_count()
    h:rerender()
    lt.assertEquals(h:render_count(), 1)
    lt.assertEquals(renders, 3)

    h:unmount()
end

function suite.test_harness_expect_renders()
    local function App()
        return tui.Text { "x" }
    end
    local h = testing.harness(App, { cols = 10, rows = 2 })
    -- Initial render only
    h:expect_renders(1, "after initial render")

    h:rerender()
    h:expect_renders(2, "after one manual rerender")

    h:unmount()
end
