local lt = require "ltest"
local tui = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"

local suite = lt.test "link"

local function has_hyperlink(cells, url)
    for _, cell in ipairs(cells) do
        if cell.hyperlink == url then
            return true
        end
    end
    return false
end

function suite:test_mouse_click_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com",
                onClick = function(ev) got = ev end,
                "docs",
            },
        }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    local cx, cy = h:sgr(0, 0)
    h:mouse("down", 1, cx, cy)
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.href, "https://example.com")
    lt.assertEquals(got.source, "mouse")
    lt.assertEquals(got.localCol, 0)
    lt.assertEquals(h:cells(1)[1].hyperlink, "https://example.com")
    h:unmount()
end

function suite:test_enter_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com/docs",
                autoFocus = true,
                onClick = function(ev) got = ev end,
                "docs",
            },
        }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    h:press("enter")
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.href, "https://example.com/docs")
    lt.assertEquals(got.source, "keyboard")
    h:unmount()
end

function suite:test_disabled_link_suppresses_callback_and_hyperlink()
    local called = false

    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com",
                isDisabled = true,
                onClick = function() called = true end,
                "docs",
            },
        }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    local cx, cy = h:sgr(0, 0)
    h:mouse("down", 1, cx, cy)
    h:press("enter")
    h:rerender()

    lt.assertEquals(called, false)
    lt.assertEquals(h:cells(1)[1].hyperlink, nil)
    h:unmount()
end

function suite:test_rich_children_mouse_click_fires_onclick_and_hyperlink()
    local got

    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com/rich",
                onClick = function(ev) got = ev end,
                "My ",
                tui.Text { color = "cyan", "Website" },
            },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 2 })
    local cx, cy = h:sgr(0, 0)
    h:mouse("down", 1, cx, cy)
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.href, "https://example.com/rich")
    lt.assertEquals(got.source, "mouse")
    lt.assertTrue(has_hyperlink(h:cells(1), "https://example.com/rich"))
    h:unmount()
end

function suite:test_rich_children_enter_fires_onclick()
    local got

    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com/rich-enter",
                autoFocus = true,
                onClick = function(ev) got = ev end,
                "My ",
                tui.Text { color = "cyan", "Website" },
            },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 2 })
    h:press("enter")
    h:rerender()

    lt.assertNotEquals(got, nil)
    lt.assertEquals(got.href, "https://example.com/rich-enter")
    lt.assertEquals(got.source, "keyboard")
    h:unmount()
end

function suite:test_link_rejects_label_and_children_together()
    local function App()
        return tui.Box {
            extra.Link {
                href = "https://example.com",
                label = "docs",
                tui.Text { "child" },
            },
        }
    end

    lt.assertError(function()
        local h = testing.render(App, { cols = 10, rows = 1 })
        h:unmount()
    end)
end
