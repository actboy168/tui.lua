-- test/test_chat_flow.lua — end-to-end offscreen simulation of the chat demo.
--
-- Mirrors examples/chat_mock.lua but uses shared helper from helpers.lua.
-- Exercises Static + TextInput + useInterval + useWindowSize in one flow.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"
local helpers = require "test.helpers"

local suite = lt.test "chat_flow"

local make_chat_app = helpers.make_chat_app

function suite:test_type_submit_stream_resize_flow()
    local App = make_chat_app("hello")

    local h = testing.render(App, { cols = 40, rows = 10 })

    -- Type "hi" and press Enter. :type walks UTF-8 boundaries and rerenders
    -- between each keystroke; :press rerenders once after.
    h:type("hi")
    h:press("enter")
    h:rerender()

    -- After submit: history gains [you] hi; streaming starts at shown=0 so
    -- no streaming row text rendered yet.
    local texts = testing.text_content(h:tree())
    local found_user = false
    for _, t in ipairs(texts) do
        if t:find("[you] hi", 1, true) then found_user = true; break end
    end
    lt.assertEquals(found_user, true, "user message should appear in history")

    -- Advance 40ms three times → streaming shown = 3 → "[bot] hel".
    h:advance(40):advance(40):advance(40)
    local partial_found = false
    for _, t in ipairs(testing.text_content(h:tree())) do
        if t == "[bot] hel" then partial_found = true; break end
    end
    lt.assertEquals(partial_found, true, "streaming partial 'hel' should render")

    -- Two more ticks finalize "hello" (shown=5 triggers the finalize branch
    -- on the following tick, so advance enough to land on finalize).
    h:advance(40):advance(40):advance(40)
    local final_found = false
    for _, t in ipairs(testing.text_content(h:tree())) do
        if t == "[bot] hello" then final_found = true; break end
    end
    lt.assertEquals(final_found, true, "bot reply should finalize into history")

    -- Resize to 60×20: row width expands accordingly and useWindowSize
    -- drives a re-render with the new dimensions.
    h:resize(60, 20)
    h:rerender()
    lt.assertEquals(#h:rows(), 20, "row count should match new height")
    lt.assertEquals(#h:row(1), 60, "row width should match new cols")

    h:unmount()
end
