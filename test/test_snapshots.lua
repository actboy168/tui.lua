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
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "snapshots"

-- Inline the same chat app as test_chat_flow so snapshots exercise Static +
-- TextInput + useInterval + useWindowSize in combination.
local function make_chat_app(reply_text)
    return function()
        local history, setHistory  = tui.useState({})
        local input, setInput      = tui.useState("")
        local streaming, setStream = tui.useState(nil)
        local size                 = tui.useWindowSize()

        tui.useInterval(function()
            if not streaming then return end
            local s = streaming
            if s.shown >= #s.target then
                setHistory(function(h)
                    local nh = {}
                    for i, m in ipairs(h) do nh[i] = m end
                    nh[#nh + 1] = { who = "bot", text = s.target }
                    return nh
                end)
                setStream(nil)
                return
            end
            setStream({ target = s.target, shown = s.shown + 1 })
        end, 40)

        local function submit(value)
            if value == "" then return end
            setHistory(function(h)
                local nh = {}
                for i, m in ipairs(h) do nh[i] = m end
                nh[#nh + 1] = { who = "user", text = value }
                return nh
            end)
            setInput("")
            setStream({ target = reply_text, shown = 0 })
        end

        local function fmt(m)
            local tag = m.who == "user" and "you" or "bot"
            return tui.Text { ("[%s] %s"):format(tag, m.text) }
        end

        return tui.Box {
            flexDirection = "column",
            width  = size.cols,
            height = size.rows,
            tui.Static { items = history, render = fmt, key = "history" },
            streaming and tui.Text { ("[bot] %s"):format(streaming.target:sub(1, streaming.shown)), key = "stream" } or nil,
            tui.Box { flexGrow = 1, key = "spacer" },
            tui.Box {
                borderStyle = "round",
                paddingX = 1,
                key = "prompt",
                tui.TextInput {
                    value    = input,
                    onChange = setInput,
                    onSubmit = submit,
                },
            },
        }
    end
end

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
    h:match_snapshot("chat_typed_30x8")
    h:unmount()
end

-- Scenario 3: mid-stream after submit. history has [you] hi, streaming row
-- shows a partial bot reply. Exercises Static output + live streaming line.
function suite:test_chat_streaming()
    local h = testing.render(make_chat_app("hello world"), { cols = 30, rows = 8 })
    h:type("hi"):press("enter")
    -- 3 ticks → "[bot] hel"
    h:advance(40):advance(40):advance(40)
    h:match_snapshot("chat_streaming_30x8")
    h:unmount()
end

-- Scenario 4: after a resize — useWindowSize should re-render with the new
-- dimensions. Captures both cols and rows changing.
function suite:test_chat_resized()
    local h = testing.render(make_chat_app("hi"), { cols = 30, rows = 8 })
    h:resize(40, 10)
    h:match_snapshot("chat_resized_40x10")
    h:unmount()
end
