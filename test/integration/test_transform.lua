local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "transform"

local function row_has_hyperlink(cells, url)
    for _, cell in ipairs(cells) do
        if cell.hyperlink == url then
            return true
        end
    end
    return false
end

function suite:test_transform_can_apply_hyperlink_to_subtree()
    local function App()
        return tui.Box {
            tui.Transform {
                transform = function(region)
                    region:setHyperlink("https://example.com/transform")
                end,
                tui.Text { "Hi" },
            },
        }
    end

    local h = testing.harness(App, { cols = 2, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].hyperlink, "https://example.com/transform")
    lt.assertEquals(cells[2].hyperlink, "https://example.com/transform")
    h:unmount()
end

function suite:test_transform_only_affects_wrapped_subtree()
    local function App()
        return tui.Box {
            flexDirection = "row",
            tui.Transform {
                transform = function(region)
                    region:setHyperlink("https://example.com/left")
                end,
                tui.Text { "AB" },
            },
            tui.Text { "CD" },
        }
    end

    local h = testing.harness(App, { cols = 4, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].hyperlink, "https://example.com/left")
    lt.assertEquals(cells[2].hyperlink, "https://example.com/left")
    lt.assertEquals(cells[3].hyperlink, nil)
    lt.assertEquals(cells[4].hyperlink, nil)
    h:unmount()
end

function suite:test_transform_clear_hyperlink_with_nil()
    local function App()
        return tui.Box {
            tui.Transform {
                transform = function(region)
                    region:setHyperlink("https://example.com/temp")
                    region:setHyperlink(nil)
                end,
                tui.Text { "X" },
            },
        }
    end

    local h = testing.harness(App, { cols = 1, rows = 1 })
    local cells = h:cells(1)
    lt.assertEquals(cells[1].hyperlink, nil)
    h:unmount()
end
