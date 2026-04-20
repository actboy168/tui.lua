-- test/snapshot/test_themes.lua — theme and style combination snapshot tests
--
-- Tests various borderStyle, color, and styling combinations.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local extra = require "tui.extra"

local suite = lt.test "themes"

-- ============================================================================
-- Border style combinations
-- ============================================================================

function suite:test_border_styles_comparison()
    local App = function()
        return tui.Box {
            flexDirection = "row",
            width = 50, height = 6,
            tui.Box {
                key = "single",
                borderStyle = "single",
                width = 12, height = 6,
                tui.Text { "Single" }
            },
            tui.Box {
                key = "double",
                borderStyle = "double",
                width = 12, height = 6,
                tui.Text { "Double" }
            },
            tui.Box {
                key = "round",
                borderStyle = "round",
                width = 12, height = 6,
                tui.Text { "Round" }
            },
            tui.Box {
                key = "bold",
                borderStyle = "bold",
                width = 12, height = 6,
                tui.Text { "Bold" }
            },
        }
    end
    local h = testing.render(App, { cols = 55, rows = 8 })
    h:match_snapshot("border_styles_compare_55x8")
    h:unmount()
end

function suite:test_border_with_padding()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 40, height = 12,
            tui.Box {
                key = "none",
                borderStyle = "round",
                paddingX = 0, paddingY = 0,
                height = 3,
                tui.Text { "No padding" }
            },
            tui.Box {
                key = "x",
                borderStyle = "round",
                paddingX = 1, paddingY = 0,
                height = 3,
                tui.Text { "X padding" }
            },
            tui.Box {
                key = "y",
                borderStyle = "round",
                paddingX = 0, paddingY = 1,
                height = 4,
                tui.Text { "Y padding" }
            },
            tui.Box {
                key = "both",
                borderStyle = "round",
                paddingX = 2, paddingY = 1,
                height = 4,
                tui.Text { "Both padding" }
            },
        }
    end
    local h = testing.render(App, { cols = 45, rows = 14 })
    h:match_snapshot("border_padding_45x14")
    h:unmount()
end

function suite:test_nested_borders()
    local App = function()
        return tui.Box {
            borderStyle = "double",
            paddingX = 1, paddingY = 1,
            width = 30, height = 10,
            tui.Box {
                borderStyle = "single",
                paddingX = 1, paddingY = 1,
                tui.Box {
                    borderStyle = "round",
                    paddingX = 1, paddingY = 1,
                    tui.Text { "Nested" }
                }
            }
        }
    end
    local h = testing.render(App, { cols = 35, rows = 12 })
    h:match_snapshot("nested_borders_35x12")
    h:unmount()
end

-- ============================================================================
-- Color combinations
-- ============================================================================

function suite:test_text_colors()
    local colors = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }
    local App = function()
        local children = {}
        for i, color in ipairs(colors) do
            children[#children + 1] = tui.Text {
                key = "c" .. i,
                color = color,
                ("%-8s"):format(color)
            }
        end
        return tui.Box {
            flexDirection = "column",
            width = 20, height = #colors + 2,
            table.unpack(children)
        }
    end
    local h = testing.render(App, { cols = 25, rows = 12 })
    h:match_snapshot("text_colors_25x12")
    h:unmount()
end

function suite:test_colored_borders()
    local App = function()
        return tui.Box {
            flexDirection = "row",
            width = 60, height = 6,
            tui.Box {
                key = "red",
                borderStyle = "single",
                borderColor = "red",
                width = 14, height = 6,
                tui.Text { "Red" }
            },
            tui.Box {
                key = "green",
                borderStyle = "single",
                borderColor = "green",
                width = 14, height = 6,
                tui.Text { "Green" }
            },
            tui.Box {
                key = "blue",
                borderStyle = "single",
                borderColor = "blue",
                width = 14, height = 6,
                tui.Text { "Blue" }
            },
            tui.Box {
                key = "yellow",
                borderStyle = "single",
                borderColor = "yellow",
                width = 14, height = 6,
                tui.Text { "Yellow" }
            },
        }
    end
    local h = testing.render(App, { cols = 65, rows = 8 })
    h:match_snapshot("colored_borders_65x8")
    h:unmount()
end

function suite:test_background_colors()
    local colors = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }
    local App = function()
        local children = {}
        for i, bg in ipairs(colors) do
            children[#children + 1] = tui.Text {
                key = "bg" .. i,
                backgroundColor = bg,
                color = bg == "white" and "black" or "white",
                (" %-8s "):format(bg)
            }
        end
        return tui.Box {
            flexDirection = "column",
            width = 20, height = #colors + 2,
            table.unpack(children)
        }
    end
    local h = testing.render(App, { cols = 25, rows = 12 })
    h:match_snapshot("background_colors_25x12")
    h:unmount()
end

-- ============================================================================
-- Component-specific styling
-- ============================================================================

function suite:test_progress_bar_colors()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 25, height = 10,
            extra.ProgressBar { key = "red", value = 0.5, width = 20, color = "red" },
            extra.ProgressBar { key = "green", value = 0.5, width = 20, color = "green" },
            extra.ProgressBar { key = "blue", value = 0.5, width = 20, color = "blue" },
            extra.ProgressBar { key = "yellow", value = 0.5, width = 20, color = "yellow" },
            extra.ProgressBar { key = "cyan", value = 0.5, width = 20, color = "cyan" },
            extra.ProgressBar { key = "magenta", value = 0.5, width = 20, color = "magenta" },
        }
    end
    local h = testing.render(App, { cols = 30, rows = 12 })
    h:match_snapshot("progress_colors_30x12")
    h:unmount()
end

function suite:test_spinner_colors()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 20, height = 10,
            extra.Spinner { key = "red", type = "dots", color = "red", label = "Red" },
            extra.Spinner { key = "green", type = "dots", color = "green", label = "Green" },
            extra.Spinner { key = "blue", type = "dots", color = "blue", label = "Blue" },
            extra.Spinner { key = "yellow", type = "dots", color = "yellow", label = "Yellow" },
        }
    end
    local h = testing.render(App, { cols = 25, rows = 12 })
    h:match_snapshot("spinner_colors_25x12")
    h:unmount()
end

function suite:test_input_styling()
    local App = function()
        local value1, setValue1 = tui.useState("default")
        local value2, setValue2 = tui.useState("")
        return tui.Box {
            flexDirection = "column",
            width = 30, height = 8,
            tui.Box {
                key = "box1",
                borderStyle = "single",
                borderColor = "blue",
                paddingX = 1,
                extra.TextInput {
                    key = "input1",
                    value = value1,
                    onChange = setValue1,
                }
            },
            tui.Box {
                key = "box2",
                borderStyle = "round",
                borderColor = "green",
                paddingX = 1,
                extra.TextInput {
                    key = "input2",
                    value = value2,
                    onChange = setValue2,
                    placeholder = "Type here...",
                }
            },
        }
    end
    local h = testing.render(App, { cols = 35, rows = 10 })
    h:match_snapshot("input_styling_35x10")
    h:unmount()
end

-- ============================================================================
-- Complex theme combinations
-- ============================================================================

function suite:test_full_panel_theme()
    local App = function()
        return tui.Box {
            flexDirection = "row",
            width = 60, height = 15,
            tui.Box {
                key = "sidebar",
                borderStyle = "double",
                borderColor = "blue",
                width = 20, height = 15,
                paddingX = 1,
                tui.Text { key = "title", color = "cyan", "Sidebar" },
                extra.Newline { key = "nl" },
                tui.Text { key = "i1", "Item 1" },
                tui.Text { key = "i2", "Item 2" },
                tui.Text { key = "i3", "Item 3" },
            },
            tui.Box {
                key = "main",
                flexGrow = 1,
                flexDirection = "column",
                tui.Box {
                    key = "header",
                    borderStyle = "single",
                    borderColor = "green",
                    height = 3,
                    paddingX = 1,
                    tui.Text { key = "ht", color = "green", "Header" }
                },
                tui.Box {
                    key = "content",
                    borderStyle = "round",
                    flexGrow = 1,
                    paddingX = 1, paddingY = 1,
                    tui.Text { key = "ct", "Main content area" },
                    extra.Newline { key = "nl" },
                    extra.Spinner { key = "spinner", type = "dots", color = "yellow", label = "Loading" }
                },
                tui.Box {
                    key = "footer",
                    borderStyle = "single",
                    borderColor = "yellow",
                    height = 3,
                    paddingX = 1,
                    extra.ProgressBar { key = "pb", value = 0.6, width = 30, color = "cyan" }
                },
            },
        }
    end
    local h = testing.render(App, { cols = 65, rows = 17 })
    h:match_snapshot("full_panel_theme_65x17")
    h:unmount()
end

function suite:test_alert_styles()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 50, height = 14,
            tui.Box {
                key = "error",
                borderStyle = "round",
                borderColor = "red",
                backgroundColor = "red",
                height = 3,
                paddingX = 1,
                tui.Text { color = "white", "ERROR: Something went wrong!" }
            },
            extra.Newline { key = "nl1" },
            tui.Box {
                key = "warn",
                borderStyle = "round",
                borderColor = "yellow",
                height = 3,
                paddingX = 1,
                tui.Text { color = "yellow", "WARNING: Check your input" }
            },
            extra.Newline { key = "nl2" },
            tui.Box {
                key = "success",
                borderStyle = "round",
                borderColor = "green",
                height = 3,
                paddingX = 1,
                tui.Text { color = "green", "SUCCESS: Operation completed" }
            },
        }
    end
    local h = testing.render(App, { cols = 55, rows = 16 })
    h:match_snapshot("alert_styles_55x16")
    h:unmount()
end
