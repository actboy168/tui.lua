local lt = require "ltest"
local tui = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"

local suite = lt.test "button"

function suite:test_mouse_click_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Button {
                label = "Save",
                onClick = function(ev) got = ev end,
            },
        }
    end

    local h = testing.harness(App, { cols = 12, rows = 3 })
    local cx, cy = h:sgr(1, 1)
    h:mouse("down", 1, cx, cy)
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.source, "mouse")
    lt.assertEquals(got.localCol, 1)
    h:unmount()
end

function suite:test_enter_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Button {
                label = "Save",
                autoFocus = true,
                onClick = function(ev) got = ev end,
            },
        }
    end

    local h = testing.harness(App, { cols = 12, rows = 3 })
    h:press("enter")
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.source, "keyboard")
    h:unmount()
end

function suite:test_disabled_button_suppresses_callback()
    local called = false

    local function App()
        return tui.Box {
            extra.Button {
                label = "Save",
                isDisabled = true,
                onClick = function() called = true end,
            },
        }
    end

    local h = testing.harness(App, { cols = 12, rows = 3 })
    local cx, cy = h:sgr(1, 1)
    h:mouse("down", 1, cx, cy)
    h:press("enter")
    h:rerender()

    lt.assertEquals(called, false)
    h:unmount()
end

function suite:test_label_renders()
    local function App()
        return tui.Box {
            extra.Button { label = "Save" },
        }
    end

    local h = testing.harness(App, { cols = 12, rows = 3 })
    local frame = h:frame()
    lt.assertNotEquals(frame:find("Save", 1, true), nil)
    h:unmount()
end

function suite:test_rich_children_render_and_click()
    local got

    local function App()
        return tui.Box {
            extra.Button {
                onClick = function(ev) got = ev end,
                "Go ",
                tui.Text { color = "cyan", "Now" },
            },
        }
    end

    local h = testing.harness(App, { cols = 16, rows = 3 })
    local frame = h:frame()
    lt.assertNotEquals(frame:find("Go Now", 1, true), nil)

    local cx, cy = h:sgr(2, 1)
    h:mouse("down", 1, cx, cy)
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.source, "mouse")
    h:unmount()
end

function suite:test_rich_children_enter_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Button {
                autoFocus = true,
                onClick = function(ev) got = ev end,
                "Go ",
                tui.Text { color = "cyan", "Now" },
            },
        }
    end

    local h = testing.harness(App, { cols = 16, rows = 3 })
    h:press("enter")
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.source, "keyboard")
    h:unmount()
end

function suite:test_button_rejects_label_and_children_together()
    local function App()
        return tui.Box {
            extra.Button {
                label = "Save",
                tui.Text { "child" },
            },
        }
    end

    lt.assertError(function()
        local h = testing.harness(App, { cols = 12, rows = 3 })
        h:unmount()
    end)
end
