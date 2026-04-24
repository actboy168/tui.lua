local lt = require "ltest"
local tui = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"

local suite = lt.test "link"

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
