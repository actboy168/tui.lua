-- test/snapshot/test_components.lua — snapshot tests for built-in components
--
-- Each built-in component gets at least one snapshot to serve as visual
-- regression fixtures for the renderer.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local extra = require "tui.extra"

local suite = lt.test "components"

-- ============================================================================
-- Box component snapshots
-- ============================================================================

function suite:test_box_simple()
    local App = function()
        return tui.Box {
            width = 10, height = 3,
            tui.Text { "Hello" }
        }
    end
    local h = testing.render(App, { cols = 15, rows = 5 })
    h:match_snapshot("box_simple_15x5")
    h:unmount()
end

function suite:test_box_border_round()
    local App = function()
        return tui.Box {
            borderStyle = "round",
            width = 12, height = 4,
            tui.Text { "Rounded" }
        }
    end
    local h = testing.render(App, { cols = 15, rows = 6 })
    h:match_snapshot("box_border_round_15x6")
    h:unmount()
end

function suite:test_box_border_single()
    local App = function()
        return tui.Box {
            borderStyle = "single",
            width = 12, height = 4,
            tui.Text { "Single" }
        }
    end
    local h = testing.render(App, { cols = 15, rows = 6 })
    h:match_snapshot("box_border_single_15x6")
    h:unmount()
end

function suite:test_box_border_double()
    local App = function()
        return tui.Box {
            borderStyle = "double",
            width = 12, height = 4,
            tui.Text { "Double" }
        }
    end
    local h = testing.render(App, { cols = 15, rows = 6 })
    h:match_snapshot("box_border_double_15x6")
    h:unmount()
end

function suite:test_box_with_padding()
    local App = function()
        return tui.Box {
            borderStyle = "round",
            paddingX = 2, paddingY = 1,
            width = 16, height = 5,
            tui.Text { "Padded" }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 7 })
    h:match_snapshot("box_padding_20x7")
    h:unmount()
end

function suite:test_box_flex_row()
    local App = function()
        return tui.Box {
            flexDirection = "row",
            width = 20, height = 3,
            tui.Box { key = "a", width = 6, height = 3, tui.Text { "A" } },
            tui.Box { key = "b", width = 6, height = 3, tui.Text { "B" } },
            tui.Box { key = "c", width = 6, height = 3, tui.Text { "C" } },
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("box_flex_row_25x5")
    h:unmount()
end

function suite:test_box_flex_column()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 10, height = 9,
            tui.Box { key = "a", width = 10, height = 3, tui.Text { "A" } },
            tui.Box { key = "b", width = 10, height = 3, tui.Text { "B" } },
            tui.Box { key = "c", width = 10, height = 3, tui.Text { "C" } },
        }
    end
    local h = testing.render(App, { cols = 15, rows = 12 })
    h:match_snapshot("box_flex_column_15x12")
    h:unmount()
end

-- ============================================================================
-- Text component snapshots
-- ============================================================================

function suite:test_text_plain()
    local App = function()
        return tui.Box {
            width = 15, height = 3,
            tui.Text { "Hello World" }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:match_snapshot("text_plain_20x5")
    h:unmount()
end

function suite:test_text_colored()
    local App = function()
        return tui.Box {
            width = 20, height = 5,
            tui.Text { key = "red", color = "red", "Red Text" },
            tui.Text { key = "green", color = "green", "Green Text" },
            tui.Text { key = "blue", color = "blue", "Blue Text" },
        }
    end
    local h = testing.render(App, { cols = 25, rows = 7 })
    h:match_snapshot("text_colored_25x7")
    h:unmount()
end

function suite:test_text_multiline()
    local App = function()
        return tui.Box {
            width = 15, height = 5,
            tui.Text { "Line 1\nLine 2\nLine 3" }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 7 })
    h:match_snapshot("text_multiline_20x7")
    h:unmount()
end

function suite:test_text_truncation()
    local App = function()
        return tui.Box {
            width = 10, height = 3,
            tui.Text { "This is a very long text" }
        }
    end
    local h = testing.render(App, { cols = 15, rows = 5 })
    h:match_snapshot("text_truncated_15x5")
    h:unmount()
end

-- ============================================================================
-- extra.TextInput component snapshots
-- ============================================================================

function suite:test_textinput_empty()
    local App = function()
        local value, setValue = tui.useState("")
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                value = value,
                onChange = setValue,
                width = 18,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("textinput_empty_25x5")
    h:unmount()
end

function suite:test_textinput_with_value()
    local App = function()
        local value, setValue = tui.useState("hello")
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                value = value,
                onChange = setValue,
                width = 18,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("textinput_value_25x5")
    h:unmount()
end

function suite:test_textinput_with_placeholder()
    local App = function()
        local value, setValue = tui.useState("")
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                value = value,
                onChange = setValue,
                placeholder = "Type here...",
                width = 18,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("textinput_placeholder_25x5")
    h:unmount()
end

function suite:test_textinput_in_border()
    local App = function()
        local value, setValue = tui.useState("input")
        return tui.Box {
            borderStyle = "round",
            width = 22, height = 5,
            paddingX = 1,
            extra.TextInput {
                value = value,
                onChange = setValue,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 7 })
    h:match_snapshot("textinput_bordered_25x7")
    h:unmount()
end

function suite:test_textinput_typed()
    local App = function()
        local value, setValue = tui.useState("")
        return tui.Box {
            width = 20, height = 3,
            extra.TextInput {
                value = value,
                onChange = setValue,
                width = 18,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:type("abc")
    h:match_snapshot("textinput_typed_25x5")
    h:unmount()
end

-- ============================================================================
-- extra.Spinner component snapshots
-- ============================================================================

function suite:test_spinner_dots()
    local App = function()
        return tui.Box {
            width = 15, height = 3,
            extra.Spinner { type = "dots" }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:match_snapshot("spinner_dots_20x5")
    h:unmount()
end

function suite:test_spinner_line()
    local App = function()
        return tui.Box {
            width = 15, height = 3,
            extra.Spinner { type = "line" }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:match_snapshot("spinner_line_20x5")
    h:unmount()
end

function suite:test_spinner_with_label()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.Spinner { type = "dots", label = "Loading..." }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("spinner_label_25x5")
    h:unmount()
end

function suite:test_spinner_colored()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.Spinner { type = "dots", color = "yellow", label = "Working" }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("spinner_colored_25x5")
    h:unmount()
end

-- ============================================================================
-- extra.ProgressBar component snapshots
-- ============================================================================

function suite:test_progress_empty()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.ProgressBar { value = 0, width = 15 }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("progress_empty_25x5")
    h:unmount()
end

function suite:test_progress_half()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.ProgressBar { value = 0.5, width = 15 }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("progress_half_25x5")
    h:unmount()
end

function suite:test_progress_full()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.ProgressBar { value = 1, width = 15 }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("progress_full_25x5")
    h:unmount()
end

function suite:test_progress_colored()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.ProgressBar { value = 0.7, width = 15, color = "green" }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("progress_colored_25x5")
    h:unmount()
end

function suite:test_progress_custom_chars()
    local App = function()
        return tui.Box {
            width = 20, height = 3,
            extra.ProgressBar {
                value = 0.6,
                width = 15,
                chars = { fill = "=", empty = "-" }
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 5 })
    h:match_snapshot("progress_custom_25x5")
    h:unmount()
end

-- ============================================================================
-- extra.Static component snapshots
-- ============================================================================

function suite:test_static_list()
    local App = function()
        local items = {
            { name = "Item 1" },
            { name = "Item 2" },
            { name = "Item 3" },
        }
        return tui.Box {
            width = 15, height = 5,
            extra.Static {
                items = items,
                render = function(item)
                    return tui.Text { item.name }
                end
            }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 7 })
    h:match_snapshot("static_list_20x7")
    h:unmount()
end

function suite:test_static_empty()
    local App = function()
        return tui.Box {
            width = 15, height = 3,
            extra.Static {
                items = {},
                render = function(item)
                    return tui.Text { item.name }
                end
            }
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:match_snapshot("static_empty_20x5")
    h:unmount()
end

-- ============================================================================
-- extra.Newline/extra.Spacer component snapshots
-- ============================================================================

function suite:test_newline()
    local App = function()
        return tui.Box {
            width = 15, height = 5,
            tui.Text { key = "l1", "Line 1" },
            extra.Newline { key = "nl" },
            tui.Text { key = "l2", "Line 2" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 7 })
    h:match_snapshot("newline_20x7")
    h:unmount()
end

function suite:test_spacer()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 15, height = 7,
            tui.Text { key = "top", "Top" },
            extra.Spacer { key = "spacer" },
            tui.Text { key = "bottom", "Bottom" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 9 })
    h:match_snapshot("spacer_20x9")
    h:unmount()
end

-- ============================================================================
-- extra.Select component snapshots
-- ============================================================================

function suite:test_select_single()
    local App = function()
        local items = {
            { label = "Option A", value = "a" },
            { label = "Option B", value = "b" },
            { label = "Option C", value = "c" },
        }
        return tui.Box {
            width = 20, height = 7,
            extra.Select {
                items = items,
                onSelect = function() end,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 9 })
    h:match_snapshot("select_single_25x9")
    h:unmount()
end

function suite:test_select_with_initial_index()
    local App = function()
        local items = {
            { label = "Option A", value = "a" },
            { label = "Option B", value = "b" },
            { label = "Option C", value = "c" },
        }
        return tui.Box {
            width = 20, height = 7,
            extra.Select {
                items = items,
                initialIndex = 2,
                onSelect = function() end,
            }
        }
    end
    local h = testing.render(App, { cols = 25, rows = 9 })
    h:match_snapshot("select_initial_2_25x9")
    h:unmount()
end
