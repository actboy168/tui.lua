-- test/test_snapshots.lua — end-to-end snapshot tests.
--
-- Snapshots are plain-text files under test/__snapshots__/. On first run
-- they're written and the test passes. On subsequent runs the harness
-- compares frame-by-frame; any mismatch fails with a context diff.
--
-- To intentionally update snapshots: TUI_UPDATE_SNAPSHOTS=1 luamake test
--
-- Keep each scenario small and deterministic: fixed cols×rows, no real I/O,
-- virtual clock. These tests double as regression fixtures for the layout +
-- renderer + screen diff pipeline.

local lt      = require "ltest"
local testing = require "tui.testing"
local helpers = require "test.helpers"

local suite = lt.test "snapshots"

local make_chat_app = helpers.make_chat_app

-- Scenario 1: idle app with an empty input box — the simplest baseline.
function suite:test_chat_idle()
    local h = testing.render(make_chat_app("hi"), { cols = 30, rows = 8 })
    h:match_snapshot("chat_idle_30x8")
    h:unmount()
end

-- Scenario 2: typed a few characters, cursor visible. Static region still
-- empty because nothing was submitted.
function suite:test_chat_typed()
    local h = testing.render(make_chat_app("hi"), { cols = 30, rows = 8 })
    h:type("hello")
    h:rerender()
    h:match_snapshot("chat_typed_30x8")
    h:unmount()
end

-- Scenario 3: mid-stream after submit. history has [you] hi, streaming row
-- shows a partial bot reply. Exercises Static output + live streaming line.
function suite:test_chat_streaming()
    local h = testing.render(make_chat_app("hello world"), { cols = 30, rows = 8 })
    h:type("hi")
    h:rerender()
    h:press("enter")
    h:rerender()
    -- 3 ticks → "[bot] hel"
    h:advance(40)
    h:advance(40)
    h:advance(40)
    h:match_snapshot("chat_streaming_30x8")
    h:unmount()
end

-- Scenario 4: after a resize — useWindowSize should re-render with the new
-- dimensions. Captures both cols and rows changing.
function suite:test_chat_resized()
    local h = testing.render(make_chat_app("hi"), { cols = 30, rows = 8 })
    h:resize(40, 10)
    h:rerender()
    h:match_snapshot("chat_resized_40x10")
    h:unmount()
end
