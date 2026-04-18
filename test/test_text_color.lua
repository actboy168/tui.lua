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
-- Case 2: no color inheritance — Box color does not propagate to Text.

function suite:test_box_color_does_not_inherit()
    local function App()
        return Box { width = 5, height = 1, color = "green",
            Text { "hi" },
        }
    end
    local h = testing.render(App)
    local ansi = h:ansi()
    -- Text has no color, so no green SGR should appear for the text run.
    lt.assertEquals(ansi:find(ESC .. "[32m", 1, true), nil,
        "Text should not inherit Box color: " .. (ansi:gsub(ESC, "<ESC>")))
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
        return Box { width = 4, height = 3, border = "single", color = "cyan",
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
