-- test/snapshot/test_boundary_sizes.lua — boundary size snapshot tests
--
-- Tests rendering at extreme terminal dimensions: minimum (1x1),
-- narrow/tall (10x3), and wide/short (120x40).

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"

local suite = lt.test "boundary_sizes"

-- ============================================================================
-- 1×1 minimum size tests
-- ============================================================================

function suite:test_minimal_box()
    local App = function()
        return tui.Box {
            width = 1, height = 1,
        }
    end
    local h = testing.render(App, { cols = 1, rows = 1 })
    h:match_snapshot("minimal_box_1x1")
    h:unmount()
end

function suite:test_minimal_text()
    local App = function()
        return tui.Box {
            width = 1, height = 1,
            tui.Text { "X" }
        }
    end
    local h = testing.render(App, { cols = 1, rows = 1 })
    h:match_snapshot("minimal_text_1x1")
    h:unmount()
end

function suite:test_minimal_border()
    local App = function()
        return tui.Box {
            borderStyle = "single",
            width = 1, height = 1,
        }
    end
    local h = testing.render(App, { cols = 1, rows = 1 })
    h:match_snapshot("minimal_border_1x1")
    h:unmount()
end

-- ============================================================================
-- 10×3 narrow/tall tests
-- ============================================================================

function suite:test_narrow_box_stack()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 10, height = 3,
            tui.Box { height = 1, tui.Text { "Header" } },
            tui.Box { flexGrow = 1, tui.Text { "Body" } },
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("narrow_stack_10x3")
    h:unmount()
end

function suite:test_narrow_text_wrap()
    local App = function()
        return tui.Box {
            width = 10, height = 3,
            tui.Text { "Long text here" }
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("narrow_text_10x3")
    h:unmount()
end

function suite:test_narrow_input()
    local App = function()
        local value, setValue = tui.useState("hi")
        return tui.Box {
            width = 10, height = 3,
            tui.TextInput {
                value = value,
                onChange = setValue,
            }
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("narrow_input_10x3")
    h:unmount()
end

function suite:test_narrow_spinner()
    local App = function()
        return tui.Box {
            width = 10, height = 3,
            tui.Spinner { type = "line" }
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("narrow_spinner_10x3")
    h:unmount()
end

function suite:test_narrow_progress()
    local App = function()
        return tui.Box {
            width = 10, height = 3,
            tui.ProgressBar { value = 0.5, width = 8 }
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("narrow_progress_10x3")
    h:unmount()
end

-- ============================================================================
-- 120×40 wide screen tests
-- ============================================================================

function suite:test_wide_layout()
    local App = function()
        return tui.Box {
            flexDirection = "row",
            width = 120, height = 40,
            tui.Box {
                width = 30, height = 40,
                borderStyle = "single",
                tui.Text { "Sidebar" }
            },
            tui.Box {
                flexGrow = 1,
                height = 40,
                borderStyle = "single",
                tui.Text { "Main Content" }
            },
        }
    end
    local h = testing.render(App, { cols = 120, rows = 40 })
    h:match_snapshot("wide_layout_120x40")
    h:unmount()
end

function suite:test_wide_text()
    local App = function()
        local text = string.rep("Wide ", 20)
        return tui.Box {
            width = 100, height = 3,
            tui.Text { text }
        }
    end
    local h = testing.render(App, { cols = 120, rows = 40 })
    h:match_snapshot("wide_text_120x40")
    h:unmount()
end

function suite:test_wide_row_of_boxes()
    local App = function()
        local boxes = {}
        for i = 1, 10 do
            boxes[#boxes + 1] = tui.Box {
                key = "box" .. i,
                width = 10, height = 8,
                borderStyle = "round",
                tui.Text { ("Box %d"):format(i) }
            }
        end
        return tui.Box {
            flexDirection = "row",
            width = 120, height = 10,
            table.unpack(boxes)
        }
    end
    local h = testing.render(App, { cols = 120, rows = 12 })
    h:match_snapshot("wide_row_boxes_120x12")
    h:unmount()
end

-- ============================================================================
-- Mixed boundary tests
-- ============================================================================

function suite:test_resize_from_narrow_to_wide()
    local App = function()
        local size = tui.useWindowSize()
        return tui.Box {
            width = size.cols, height = size.rows,
            borderStyle = "single",
            tui.Text { ("%dx%d"):format(size.cols, size.rows) }
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    h:match_snapshot("resize_narrow_10x3")
    h:resize(40, 10)
    h:match_snapshot("resize_medium_40x10")
    h:resize(80, 24)
    h:match_snapshot("resize_large_80x24")
    h:unmount()
end
