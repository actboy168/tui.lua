-- test/extra/test_spinner.lua — <Spinner> component behavior.

local lt        = require "ltest"
local tui       = require "tui"
local Spinner   = require "tui.extra.spinner".Spinner
local testing   = require "tui.testing"

local suite = lt.test "spinner"

-- Default type=dots renders its first frame (Braille "⠋") on mount.
function suite:test_default_first_frame()
    local function App()
        return tui.Box {
            width = 10, height = 1,
            Spinner {},
        }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    -- First frame of the dots set.
    lt.assertEquals(h:row(1):sub(1, #"⠋"), "⠋")
    h:unmount()
end

-- Advancing a tick switches to the next frame glyph.
function suite:test_frame_advances_on_interval()
    local function App()
        return tui.Box {
            width = 10, height = 1,
            Spinner { type = "line" },
        }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    lt.assertEquals(h:row(1):sub(1, 1), "-")
    h:advance(80)
    lt.assertEquals(h:row(1):sub(1, 1), "\\")
    h:advance(80)
    lt.assertEquals(h:row(1):sub(1, 1), "|")
    h:unmount()
end

-- After a full cycle the glyph wraps around.
function suite:test_frame_wraps_around()
    local function App()
        return tui.Box {
            width = 10, height = 1,
            Spinner { type = "line" },
        }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    -- line has 4 frames; advance 4 * 80 = 320ms should return to the first.
    h:advance(320)
    lt.assertEquals(h:row(1):sub(1, 1), "-")
    h:unmount()
end

-- Label renders with a single space after the glyph.
function suite:test_label_appended()
    local function App()
        return tui.Box {
            width = 20, height = 1,
            Spinner { type = "line", label = "loading" },
        }
    end
    local h = testing.harness(App, { cols = 20, rows = 1 })
    lt.assertEquals(h:row(1):sub(1, #"- loading"), "- loading")
    h:unmount()
end

-- Custom frames override built-in.
function suite:test_custom_frames()
    local function App()
        return tui.Box {
            width = 10, height = 1,
            Spinner { frames = { "A", "B", "C" }, interval = 50 },
        }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    lt.assertEquals(h:row(1):sub(1, 1), "A")
    h:advance(50)
    lt.assertEquals(h:row(1):sub(1, 1), "B")
    h:advance(50)
    lt.assertEquals(h:row(1):sub(1, 1), "C")
    h:advance(50)
    lt.assertEquals(h:row(1):sub(1, 1), "A")
    h:unmount()
end

-- Passing both `type` and `frames` is an error.
function suite:test_type_and_frames_conflict()
    local ok, err = pcall(function()
        local function App()
            return tui.Box {
                Spinner { type = "dots", frames = { "X" } },
            }
        end
        testing.harness(App, { cols = 10, rows = 1 }):unmount()
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err), "string")
    lt.assertEquals(err:find("`type` or `frames`", 1, true) ~= nil, true)
end

-- Unknown type raises a descriptive error.
function suite:test_unknown_type_errors()
    local ok, err = pcall(function()
        local function App()
            return tui.Box {
                Spinner { type = "no-such-thing" },
            }
        end
        testing.harness(App, { cols = 10, rows = 1 }):unmount()
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(err:find("unknown type", 1, true) ~= nil, true)
end

-- Conditionally unmounting the spinner (loading-done pattern) clears timer.
function suite:test_conditional_mount_clears_timer()
    local show = true
    local function App()
        return tui.Box {
            width = 10, height = 1,
            show and Spinner { type = "line" },
        }
    end
    local h = testing.harness(App, { cols = 10, rows = 1 })
    lt.assertEquals(testing.timer_count(), 1)
    show = false
    h:rerender()
    lt.assertEquals(testing.timer_count(), 0)
    h:unmount()
end
