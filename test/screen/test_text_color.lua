-- test/test_text_color.lua — integration tests for color / style support
-- at the Text element API level. Exercises tui.sgr + renderer +
-- tui_core.screen working together through the standard harness.
-- Uses vterm + cells() API to assert color attributes instead of raw ANSI.

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local Text    = tui.Text
local Box     = tui.Box

local suite = lt.test "text_color"

-- ---------------------------------------------------------------------------
-- Case 1: red Text produces colored cells but plain text in rows().

function suite:test_red_text_in_cells_only()
    local function App()
        return Box { width = 5, height = 1,
            Text { color = "red", "hi" },
        }
    end
    local h = testing.harness(App)
    -- cells should have red fg (index 1)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1, "cell 1 should have red fg")
    lt.assertEquals(cells[2].fg, 1, "cell 2 should have red fg")
    -- rows() must be plain "hi" + padding (no escape sequences).
    local rows = h:rows()
    lt.assertEquals(rows[1]:sub(1, 2), "hi")
    lt.assertEquals(rows[1]:find("\27", 1, true), nil,
        "rows should never contain SGR")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Case 2: color inheritance — Box color propagates to child Text.

function suite:test_box_color_inherits_to_text()
    local function App()
        return Box { width = 5, height = 1, color = "green",
            Text { "hi" },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    -- Text has no explicit color, so it should inherit green (fg=2) from Box.
    lt.assertEquals(cells[1].fg, 2, "Text should inherit Box green color")
    lt.assertEquals(cells[2].fg, 2, "Text should inherit Box green color")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Case 2b: child Text explicit color overrides inherited Box color.

function suite:test_text_color_overrides_inherited()
    local function App()
        return Box { width = 5, height = 1, color = "green",
            Text { color = "red", "hi" },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1, "Text explicit red should win")
    lt.assertEquals(cells[2].fg, 1, "Text explicit red should win")
    h:unmount()
end

-- Case 2c: dimColor on Text overrides inherited Box color.

function suite:test_text_dimcolor_overrides_inherited()
    local function App()
        return Box { width = 5, height = 1, color = "green",
            Text { dimColor = "red", "hi" },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    -- dimColor="red" → dim=true, fg=1 (red)
    lt.assertEquals(cells[1].fg, 1, "dimColor Text should use red fg")
    lt.assertEquals(cells[1].dim, true, "dimColor Text should be dim")
    lt.assertEquals(cells[2].fg, 1, "dimColor Text should use red fg")
    lt.assertEquals(cells[2].dim, true, "dimColor Text should be dim")
    h:unmount()
end

-- Case 2d: multi-level Box nesting inherits the nearest ancestor's color.

function suite:test_nested_box_color_inheritance()
    local function App()
        return Box { width = 8, height = 1, color = "blue",
            Box { width = 8,
                Text { "hi" },
            },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 4, "Text should inherit blue from grandparent Box")
    lt.assertEquals(cells[2].fg, 4, "Text should inherit blue from grandparent Box")
    h:unmount()
end

-- Case 2e: inner Box color overrides outer Box color for its descendants.

function suite:test_inner_box_overrides_inherited_color()
    local function App()
        return Box { width = 10, height = 1, color = "blue",
            Box { width = 10, color = "yellow",
                Text { "hi" },
            },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    -- yellow = fg=3 should appear (inner Box overrides blue)
    lt.assertEquals(cells[1].fg, 3, "inner Box yellow should override outer blue")
    lt.assertEquals(cells[2].fg, 3, "inner Box yellow should override outer blue")
    h:unmount()
end

-- Case 2f: backgroundColor inherits to child Text.

function suite:test_box_backgroundcolor_inherits_to_text()
    local function App()
        return Box { width = 5, height = 1, backgroundColor = "blue",
            Text { "hi" },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    -- bg=blue → bg=4
    lt.assertEquals(cells[1].bg, 4, "Text should inherit Box backgroundColor blue")
    lt.assertEquals(cells[2].bg, 4, "Text should inherit Box backgroundColor blue")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Case 3: unknown color name raises at render time.

function suite:test_unknown_color_errors()
    local function App()
        return Text { color = "chartreuse", "hi" }
    end
    local ok, err = pcall(function()
        local h = testing.harness(App)
        h:unmount()
    end)
    lt.assertEquals(ok, false, "render should fail with bad color name")
    lt.assertEquals(tostring(err):find("chartreuse", 1, true) ~= nil, true,
        "error should mention the bad color name: " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- Case 4: border color renders on the border glyphs.

function suite:test_border_color()
    local function App()
        return Box { width = 4, height = 3, borderStyle = "single", color = "cyan",
            Text { "" },
        }
    end
    local h = testing.harness(App)
    -- Border cells on row 1 should have cyan fg (fg=6)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 6, "border cell should have cyan fg")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Case 5: bold + background combine.

function suite:test_bold_with_background()
    local function App()
        return Box { width = 6, height = 1,
            Text { bold = true, backgroundColor = "blue", "hey" },
        }
    end
    local h = testing.harness(App)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].bold, true, "cell should be bold")
    lt.assertEquals(cells[1].bg, 4, "cell should have blue bg")
    h:unmount()
end
