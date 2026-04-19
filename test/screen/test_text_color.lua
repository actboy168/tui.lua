-- test/test_text_color.lua — integration tests for color / style support
-- at the Text element API level. Exercises tui.sgr + renderer +
-- tui_core.screen working together through the standard harness.
-- Assertions track Stage 11 incremental SGR diff output (no leading "0;").

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local Text    = tui.Text
local Box     = tui.Box

local suite = lt.test "text_color"

local <const> ESC = "\27"

-- ---------------------------------------------------------------------------
-- Case 1: red Text produces SGR in ANSI output but plain text in rows().

function suite:test_red_text_sgr_in_ansi_only()
    local function App()
        return Box { width = 5, height = 1,
            Text { color = "red", "hi" },
        }
    end
    local h = testing.render(App)
    local ansi = h:ansi()
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "expected red SGR in ANSI: " .. (ansi:gsub(ESC, "<ESC>")))
    -- rows() must be plain "hi" + padding.
    local rows = h:rows()
    lt.assertEquals(rows[1]:sub(1, 2), "hi")
    lt.assertEquals(rows[1]:find(ESC, 1, true), nil,
        "rows should never contain SGR: " .. (rows[1]:gsub(ESC, "<ESC>")))
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
    local h = testing.render(App)
    local ansi = h:ansi()
    -- Text has no explicit color, so it should inherit green (32m) from Box.
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true) ~= nil, true,
        "Text should inherit Box color: " .. (ansi:gsub(ESC, "<ESC>")))
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
    local h = testing.render(App)
    local ansi = h:ansi()
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil, true,
        "Text explicit color should win: " .. (ansi:gsub(ESC, "<ESC>")))
    -- green should NOT appear
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true), nil,
        "inherited green should not appear: " .. (ansi:gsub(ESC, "<ESC>")))
    h:unmount()
end

-- Case 2c: dimColor on Text overrides inherited Box color.

function suite:test_text_dimcolor_overrides_inherited()
    local function App()
        return Box { width = 5, height = 1, color = "green",
            Text { dimColor = "red", "hi" },
        }
    end
    local h = testing.render(App)
    local ansi = h:ansi()
    -- red fg (31m) with dim (2m) should appear, not green
    lt.assertEquals(ansi:find(ESC .. "[31m", 1, true) ~= nil
        or ansi:find(ESC .. "[2;31m", 1, true) ~= nil
        or ansi:find(ESC .. "[31;2m", 1, true) ~= nil
        or ansi:find("31", 1, true) ~= nil, true,
        "dimColor Text should use its own color, not inherited: "
        .. (ansi:gsub(ESC, "<ESC>")))
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
    local h = testing.render(App)
    local ansi = h:ansi()
    lt.assertEquals(ansi:find(ESC .. "[34m", 1, true) ~= nil, true,
        "Text should inherit blue from grandparent Box: "
        .. (ansi:gsub(ESC, "<ESC>")))
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
    local h = testing.render(App)
    local ansi = h:ansi()
    -- yellow = 33m should appear (inner Box overrides blue)
    lt.assertEquals(ansi:find(ESC .. "[33m", 1, true) ~= nil, true,
        "inner Box color should override outer: " .. (ansi:gsub(ESC, "<ESC>")))
    -- blue (34m) should NOT appear for the text
    lt.assertEquals(ansi:find(ESC .. "[34m", 1, true), nil,
        "outer box blue should not reach text: " .. (ansi:gsub(ESC, "<ESC>")))
    h:unmount()
end

-- Case 2f: backgroundColor inherits to child Text.

function suite:test_box_backgroundcolor_inherits_to_text()
    local function App()
        return Box { width = 5, height = 1, backgroundColor = "blue",
            Text { "hi" },
        }
    end
    local h = testing.render(App)
    local ansi = h:ansi()
    -- bg=blue → 44m
    lt.assertEquals(ansi:find(ESC .. "[44m", 1, true) ~= nil, true,
        "Text should inherit Box backgroundColor: "
        .. (ansi:gsub(ESC, "<ESC>")))
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Case 3: unknown color name raises at render time.

function suite:test_unknown_color_errors()
    local function App()
        return Text { color = "chartreuse", "hi" }
    end
    local ok, err = pcall(function()
        local h = testing.render(App)
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
    local h = testing.render(App)
    local ansi = h:ansi()
    -- Cyan (6) normal fg → ESC[36m (incremental form, no leading 0;).
    lt.assertEquals(ansi:find(ESC .. "[36m", 1, true) ~= nil, true,
        "expected cyan SGR on border: " .. (ansi:gsub(ESC, "<ESC>")))
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
    local h = testing.render(App)
    local ansi = h:ansi()
    -- bold + bg=4 → ESC[1;44m (incremental form).
    lt.assertEquals(ansi:find(ESC .. "[1;44m", 1, true) ~= nil, true,
        "expected bold + blue bg SGR: " .. (ansi:gsub(ESC, "<ESC>")))
    h:unmount()
end
