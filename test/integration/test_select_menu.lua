-- test/integration/test_select_menu.lua — Select component integration tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local extra   = require "tui.extra"

local suite = lt.test "select_menu"

-- ============================================================================
-- Shared fixture
-- ============================================================================

local ITEMS = {
    { label = "Alpha",   value = "alpha" },
    { label = "Beta",    value = "beta" },
    { label = "Gamma",   value = "gamma" },
    { label = "Delta",   value = "delta" },
}

local function MenuApp(on_select, on_change)
    return function()
        return tui.Box {
            flexDirection = "column",
            width = 30, height = 10,
            tui.Text { key = "title", "Pick one:" },
            extra.Select {
                key      = "sel",
                items    = ITEMS,
                onSelect = on_select,
                onChange = on_change,
            },
        }
    end
end

-- ============================================================================
-- Initial render — first item highlighted
-- ============================================================================

function suite:test_initial_highlight()
    local h = testing.render(MenuApp(nil, nil), { cols = 35, rows = 12 })

    -- First item should be prefixed with the indicator glyph "❯ "
    local frame = h:frame()
    lt.assertNotEquals(frame:find("❯"), nil, "initial highlight indicator missing")
    lt.assertNotEquals(frame:find("Alpha"), nil)

    h:unmount()
end

-- ============================================================================
-- Arrow-key navigation
-- ============================================================================

function suite:test_down_moves_highlight()
    local changed_to = nil
    local App = MenuApp(nil, function(item)
        changed_to = item.value
    end)

    local h = testing.render(App, { cols = 35, rows = 12 })

    tui_input.press("down")
    h:rerender()

    lt.assertEquals(changed_to, "beta")

    -- Indicator should now be on Beta
    local frame = h:frame()
    -- Find the line with "❯" and confirm it contains "Beta"
    for line in (frame .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("❯") then
            lt.assertNotEquals(line:find("Beta"), nil,
                "indicator should be on Beta after one down press")
            break
        end
    end

    h:unmount()
end

function suite:test_up_wraps_to_last()
    local changed_to = nil
    local App = MenuApp(nil, function(item)
        changed_to = item.value
    end)

    local h = testing.render(App, { cols = 35, rows = 12 })

    -- Up from first item wraps to last (delta)
    tui_input.press("up")
    h:rerender()
    lt.assertEquals(changed_to, "delta")

    h:unmount()
end

function suite:test_navigation_sequence()
    local trail = {}
    local App = MenuApp(nil, function(item)
        trail[#trail + 1] = item.value
    end)

    local h = testing.render(App, { cols = 35, rows = 12 })

    tui_input.press("down")  -- → beta
    tui_input.press("down")  -- → gamma
    tui_input.press("down")  -- → delta
    tui_input.press("down")  -- → alpha (wrap)
    tui_input.press("up")    -- → delta

    h:rerender()

    lt.assertEquals(trail, { "beta", "gamma", "delta", "alpha", "delta" })

    h:unmount()
end

-- ============================================================================
-- Enter confirms selection
-- ============================================================================

function suite:test_enter_confirms_first_item()
    local selected = nil
    local App = MenuApp(function(item) selected = item end, nil)

    local h = testing.render(App, { cols = 35, rows = 12 })

    tui_input.press("enter")

    h:rerender()

    lt.assertNotEquals(selected, nil)
    lt.assertEquals(selected.value, "alpha")
    lt.assertEquals(selected.label, "Alpha")

    h:unmount()
end

function suite:test_enter_confirms_navigated_item()
    local selected = nil
    local App = MenuApp(function(item) selected = item end, nil)

    local h = testing.render(App, { cols = 35, rows = 12 })

    tui_input.press("down")
    tui_input.press("down")
    tui_input.press("enter")

    h:rerender()

    lt.assertNotEquals(selected, nil)
    lt.assertEquals(selected.value, "gamma")

    h:unmount()
end

-- ============================================================================
-- Snapshot
-- ============================================================================

function suite:test_snapshot_initial()
    local h = testing.render(MenuApp(nil, nil), { cols = 35, rows = 12 })
    h:match_snapshot("select_initial_35x12")
    h:unmount()
end

function suite:test_snapshot_after_navigation()
    local h = testing.render(MenuApp(nil, nil), { cols = 35, rows = 12 })
    tui_input.press("down")
    h:rerender()
    tui_input.press("down")
    h:rerender()
    h:match_snapshot("select_gamma_highlighted_35x12")
    h:unmount()
end

-- ============================================================================
-- Render efficiency
-- ============================================================================

function suite:test_one_render_per_keypress()
    local h = testing.render(MenuApp(nil, nil), { cols = 35, rows = 12 })
    h:reset_render_count()

    tui_input.press("down")
    h:rerender()
    h:expect_renders(1, "one down → one render")

    tui_input.press("down")
    h:rerender()
    h:expect_renders(2, "two downs → two renders total")

    h:unmount()
end
